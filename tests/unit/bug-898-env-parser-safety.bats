#!/usr/bin/env bats
# =============================================================================
# tests/unit/bug-898-env-parser-safety.bats
#
# Bug #898 — flatline-orchestrator.sh & bridgebuilder-review/entry.sh
# previously used `set -a; source .env; set +a`, which executes arbitrary
# bash inside .env files (command substitution, backticks, chained
# commands). Replaced with `.claude/scripts/lib/env-loader.sh` exposing
# `load_env_file <path>`.
#
# This suite proves:
#   - bug-898-1..3: hostile .env payloads do NOT execute (security)
#   - bug-898-4..8: positive controls — well-formed values still load
#   - bug-898-9..10: integration smoke — callsites use load_env_file
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    # Per-test scratch dir so .env fixtures are isolated.
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR}/bug-898.XXXXXX")"
    export TEST_TMP

    # Source the loader fresh each test (the guard variable would
    # otherwise short-circuit if a previous test sourced it).
    unset _LOA_ENV_LOADER_SOURCED
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.claude/scripts/lib/env-loader.sh"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# =============================================================================
# SECURITY — hostile payloads must NOT execute
# =============================================================================

@test "bug-898-1: load_env_file does NOT execute \$(...) payload" {
    # The marker file would be touched by a successful command-substitution.
    cat > "$TEST_TMP/.env" <<EOF
PWN=\$(touch "$TEST_TMP/owned-by-cmdsub")
EOF
    run load_env_file "$TEST_TMP/.env"
    # The loader must refuse the line (warn) but exit 0 overall.
    [ "$status" -eq 0 ]
    # Side-effect file MUST be absent.
    [ ! -e "$TEST_TMP/owned-by-cmdsub" ]
}

@test "bug-898-2: load_env_file does NOT execute backtick payload" {
    cat > "$TEST_TMP/.env" <<EOF
PWN=\`touch "$TEST_TMP/owned-by-backtick"\`
EOF
    run load_env_file "$TEST_TMP/.env"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/owned-by-backtick" ]
}

@test "bug-898-3: load_env_file does NOT execute chained command via ;" {
    cat > "$TEST_TMP/.env" <<EOF
KEY=value; touch "$TEST_TMP/owned-by-chained"
EOF
    run load_env_file "$TEST_TMP/.env"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/owned-by-chained" ]
}

@test "bug-898-3b: load_env_file does NOT execute && chained command" {
    cat > "$TEST_TMP/.env" <<EOF
KEY=value && touch "$TEST_TMP/owned-by-and"
EOF
    run load_env_file "$TEST_TMP/.env"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/owned-by-and" ]
}

@test "bug-898-3c: load_env_file does NOT execute redirect" {
    cat > "$TEST_TMP/.env" <<EOF
KEY=value > "$TEST_TMP/owned-by-redirect"
EOF
    run load_env_file "$TEST_TMP/.env"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/owned-by-redirect" ]
}

# =============================================================================
# POSITIVE CONTROLS — well-formed values still parse correctly
# =============================================================================

@test "bug-898-4: plain KEY=VALUE exports as expected" {
    cat > "$TEST_TMP/.env" <<'EOF'
SIMPLE_KEY=simple_value
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$SIMPLE_KEY" = "simple_value" ]
}

@test "bug-898-5: double-quoted values preserve whitespace and limited escapes" {
    cat > "$TEST_TMP/.env" <<'EOF'
QUOTED="hello   world"
ESCAPED="line1\nline2"
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$QUOTED" = "hello   world" ]
    # \n should expand to a newline (limited-escape contract).
    [[ "$ESCAPED" == *$'\n'* ]]
}

@test "bug-898-5b: single-quoted values pass through raw (no escape expansion)" {
    cat > "$TEST_TMP/.env" <<'EOF'
RAW='no\nexpand'
EOF
    load_env_file "$TEST_TMP/.env"
    # Single quotes: \n must remain literal characters.
    [ "$RAW" = 'no\nexpand' ]
}

@test "bug-898-6: comment lines starting with # are skipped" {
    cat > "$TEST_TMP/.env" <<'EOF'
# This is a comment
GOOD_KEY=good_value
  # indented comment
ANOTHER=another_value
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$GOOD_KEY" = "good_value" ]
    [ "$ANOTHER" = "another_value" ]
}

@test "bug-898-7: blank lines are skipped" {
    cat > "$TEST_TMP/.env" <<'EOF'
KEY_A=value_a

KEY_B=value_b

KEY_C=value_c
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$KEY_A" = "value_a" ]
    [ "$KEY_B" = "value_b" ]
    [ "$KEY_C" = "value_c" ]
}

@test "bug-898-8: CRLF line endings tolerated" {
    # Embed CR explicitly to avoid editor / heredoc stripping.
    printf 'KEY_X=value_x\r\nKEY_Y=value_y\r\n' > "$TEST_TMP/.env"
    load_env_file "$TEST_TMP/.env"
    [ "$KEY_X" = "value_x" ]
    [ "$KEY_Y" = "value_y" ]
}

@test "bug-898-9: 'export KEY=VALUE' form is accepted" {
    cat > "$TEST_TMP/.env" <<'EOF'
export EXPORTED_KEY=exported_value
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$EXPORTED_KEY" = "exported_value" ]
}

@test "bug-898-10: missing file returns 0 (no-op semantics)" {
    run load_env_file "$TEST_TMP/does-not-exist.env"
    [ "$status" -eq 0 ]
}

# =============================================================================
# CALLSITE WIRING — the two production consumers use load_env_file
# =============================================================================

@test "bug-898-11: flatline-orchestrator.sh uses load_env_file (not source .env)" {
    grep -qE 'load_env_file[[:space:]]+\.env\b' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "bug-898-12: flatline-orchestrator.sh uses load_env_file for .env.local" {
    grep -qE 'load_env_file[[:space:]]+\.env\.local' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
}

@test "bug-898-13: bridgebuilder entry.sh uses load_env_file (not source .env)" {
    grep -qE 'load_env_file[[:space:]]+\.env\b' \
        "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/entry.sh"
}

@test "bug-898-14: NEGATIVE CONTROL — production callsites no longer use 'set -a; source .env'" {
    # The exact regex that USED to match in T35-3. After the fix it MUST NOT
    # match on CODE lines. Comment lines that mention the legacy pattern
    # (e.g., "Issue #898: replaced legacy `set -a; source .env`") are
    # filtered out because they document the fix.
    local hits
    hits=$(grep -hE 'set[[:space:]]+-a[[:space:]]*;[[:space:]]*source[[:space:]]+\.env' \
        "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh" \
        "$PROJECT_ROOT/.claude/skills/bridgebuilder-review/resources/entry.sh" \
        | grep -vE '^[[:space:]]*#' || true)
    if [[ -n "$hits" ]]; then
        echo "FAIL: legacy 'set -a; source .env' pattern resurfaced on a code line:" >&2
        echo "$hits" >&2
        return 1
    fi
}
