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

# =============================================================================
# SEC-001 — key-name denylist for ambient-execution variables
#
# BB #912 review caught that the value-side gate alone is insufficient: even
# with `KEY=value` shape, certain key NAMES (BASH_ENV, LD_PRELOAD, NODE_OPTIONS,
# etc.) coerce code into every subprocess at startup. Shellshock pattern.
# =============================================================================

@test "bug-898-15: rejects BASH_ENV (every non-interactive bash sources it)" {
    cat > "$TEST_TMP/.env" <<EOF
BASH_ENV=/tmp/should-not-execute.sh
EOF
    unset BASH_ENV
    load_env_file "$TEST_TMP/.env"
    [ -z "${BASH_ENV:-}" ]
}

@test "bug-898-16: rejects LD_PRELOAD (shared-object injection)" {
    cat > "$TEST_TMP/.env" <<EOF
LD_PRELOAD=/tmp/hostile.so
EOF
    unset LD_PRELOAD
    load_env_file "$TEST_TMP/.env"
    [ -z "${LD_PRELOAD:-}" ]
}

@test "bug-898-17: rejects NODE_OPTIONS (node --require code injection)" {
    cat > "$TEST_TMP/.env" <<EOF
NODE_OPTIONS=--require=/tmp/hostile.js
EOF
    unset NODE_OPTIONS
    load_env_file "$TEST_TMP/.env"
    [ -z "${NODE_OPTIONS:-}" ]
}

@test "bug-898-18: rejects PYTHONSTARTUP (python REPL init injection)" {
    cat > "$TEST_TMP/.env" <<EOF
PYTHONSTARTUP=/tmp/hostile.py
EOF
    unset PYTHONSTARTUP
    load_env_file "$TEST_TMP/.env"
    [ -z "${PYTHONSTARTUP:-}" ]
}

@test "bug-898-19: rejects GIT_SSH_COMMAND (arbitrary command on git ops)" {
    cat > "$TEST_TMP/.env" <<EOF
GIT_SSH_COMMAND=/tmp/hostile-ssh
EOF
    unset GIT_SSH_COMMAND
    load_env_file "$TEST_TMP/.env"
    [ -z "${GIT_SSH_COMMAND:-}" ]
}

@test "bug-898-20: rejects DYLD_INSERT_LIBRARIES (macOS dyld injection)" {
    cat > "$TEST_TMP/.env" <<EOF
DYLD_INSERT_LIBRARIES=/tmp/hostile.dylib
EOF
    unset DYLD_INSERT_LIBRARIES
    load_env_file "$TEST_TMP/.env"
    [ -z "${DYLD_INSERT_LIBRARIES:-}" ]
}

@test "bug-898-21: rejects PROMPT_COMMAND (bash prompt-hook code path)" {
    cat > "$TEST_TMP/.env" <<EOF
PROMPT_COMMAND=touch /tmp/owned
EOF
    unset PROMPT_COMMAND
    load_env_file "$TEST_TMP/.env"
    [ -z "${PROMPT_COMMAND:-}" ]
}

@test "bug-898-22: rejects denylisted key even with single-quoted value" {
    cat > "$TEST_TMP/.env" <<EOF
BASH_ENV='/tmp/quoted-still-rejected.sh'
EOF
    unset BASH_ENV
    load_env_file "$TEST_TMP/.env"
    [ -z "${BASH_ENV:-}" ]
}

@test "bug-898-23: rejects denylisted key with 'export' prefix" {
    cat > "$TEST_TMP/.env" <<EOF
export BASH_ENV=/tmp/export-prefix.sh
EOF
    unset BASH_ENV
    load_env_file "$TEST_TMP/.env"
    [ -z "${BASH_ENV:-}" ]
}

@test "bug-898-24: positive control — non-denylisted key with PATH-shaped value still allowed" {
    cat > "$TEST_TMP/.env" <<'EOF'
MY_SAFE_PATH_VAR=/usr/local/bin
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$MY_SAFE_PATH_VAR" = "/usr/local/bin" ]
}

@test "bug-898-25: positive control — caller's existing BASH_ENV (set before load_env_file) is NOT clobbered" {
    # If the caller has BASH_ENV legitimately set, the loader's refusal is
    # to assign a NEW one — not to scrub the existing one. This preserves
    # operator-set values while blocking .env-supplied hijacks.
    BASH_ENV="/operator/set/value.sh"
    cat > "$TEST_TMP/.env" <<'EOF'
BASH_ENV=/hostile/value.sh
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$BASH_ENV" = "/operator/set/value.sh" ]
    unset BASH_ENV
}

@test "bug-898-26: denylist applies to non-quoted, double-quoted, single-quoted, and exported forms" {
    # Cross-cut sanity: 4 quote-shape variants of the same denylisted key,
    # all must end with the key UNset.
    for fixture in 'LD_PRELOAD=/x.so' \
                   'LD_PRELOAD="/x.so"' \
                   "LD_PRELOAD='/x.so'" \
                   'export LD_PRELOAD=/x.so'; do
        echo "$fixture" > "$TEST_TMP/.env"
        unset LD_PRELOAD
        load_env_file "$TEST_TMP/.env"
        if [[ -n "${LD_PRELOAD:-}" ]]; then
            echo "FAIL: LD_PRELOAD leaked for fixture: $fixture" >&2
            return 1
        fi
    done
}

# =============================================================================
# BB #912 v2 SEC-001 — extended exec-hook denylist
# =============================================================================

@test "bug-898-27: rejects GIT_ASKPASS (git asks an arbitrary helper)" {
    cat > "$TEST_TMP/.env" <<EOF
GIT_ASKPASS=/tmp/hostile-askpass.sh
EOF
    unset GIT_ASKPASS
    load_env_file "$TEST_TMP/.env"
    [ -z "${GIT_ASKPASS:-}" ]
}

@test "bug-898-28: rejects GIT_EXTERNAL_DIFF (git diff driver swap)" {
    cat > "$TEST_TMP/.env" <<EOF
GIT_EXTERNAL_DIFF=/tmp/hostile-diff
EOF
    unset GIT_EXTERNAL_DIFF
    load_env_file "$TEST_TMP/.env"
    [ -z "${GIT_EXTERNAL_DIFF:-}" ]
}

@test "bug-898-29: rejects GIT_PAGER (pipes git output through arbitrary binary)" {
    cat > "$TEST_TMP/.env" <<EOF
GIT_PAGER=/tmp/hostile-pager
EOF
    unset GIT_PAGER
    load_env_file "$TEST_TMP/.env"
    [ -z "${GIT_PAGER:-}" ]
}

@test "bug-898-30: rejects PAGER (any tool's pager → arbitrary exec)" {
    cat > "$TEST_TMP/.env" <<EOF
PAGER=/tmp/hostile-pager
EOF
    unset PAGER
    load_env_file "$TEST_TMP/.env"
    [ -z "${PAGER:-}" ]
}

@test "bug-898-31: rejects EDITOR / VISUAL (interactive git commands invoke them)" {
    cat > "$TEST_TMP/.env" <<EOF
EDITOR=/tmp/hostile-editor
VISUAL=/tmp/hostile-visual
EOF
    unset EDITOR VISUAL
    load_env_file "$TEST_TMP/.env"
    [ -z "${EDITOR:-}" ]
    [ -z "${VISUAL:-}" ]
}

@test "bug-898-32: rejects RUSTC_WRAPPER (cargo invokes arbitrary compiler)" {
    cat > "$TEST_TMP/.env" <<EOF
RUSTC_WRAPPER=/tmp/hostile-rustc
EOF
    unset RUSTC_WRAPPER
    load_env_file "$TEST_TMP/.env"
    [ -z "${RUSTC_WRAPPER:-}" ]
}

@test "bug-898-33: rejects CC / LD (make / cargo / build systems honor them)" {
    cat > "$TEST_TMP/.env" <<EOF
CC=/tmp/hostile-cc
LD=/tmp/hostile-ld
EOF
    unset CC LD
    load_env_file "$TEST_TMP/.env"
    [ -z "${CC:-}" ]
    [ -z "${LD:-}" ]
}

@test "bug-898-34: rejects BROWSER (xdg-open, devtools, etc. invoke it)" {
    cat > "$TEST_TMP/.env" <<EOF
BROWSER=/tmp/hostile-browser
EOF
    unset BROWSER
    load_env_file "$TEST_TMP/.env"
    [ -z "${BROWSER:-}" ]
}

@test "bug-898-35: rejects NPM_CONFIG_* glob (any npm CLI flag via env)" {
    cat > "$TEST_TMP/.env" <<EOF
NPM_CONFIG_NODE_OPTIONS=--require=/tmp/x.js
NPM_CONFIG_PREFIX=/tmp/hostile-npm-prefix
EOF
    unset NPM_CONFIG_NODE_OPTIONS NPM_CONFIG_PREFIX
    load_env_file "$TEST_TMP/.env"
    [ -z "${NPM_CONFIG_NODE_OPTIONS:-}" ]
    [ -z "${NPM_CONFIG_PREFIX:-}" ]
}

# =============================================================================
# BB #912 v2 COR-001 — inline-comment stripping
# =============================================================================

@test "bug-898-36: COR-001 — unquoted value with inline ' # comment' has comment stripped" {
    cat > "$TEST_TMP/.env" <<'EOF'
API_KEY=sk-real-key # do not commit
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$API_KEY" = "sk-real-key" ]
}

@test "bug-898-37: COR-001 — quoted value with trailing ' # comment' has comment stripped" {
    cat > "$TEST_TMP/.env" <<'EOF'
QUOTED_KEY="hello world" # trailing comment
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$QUOTED_KEY" = "hello world" ]
}

@test "bug-898-38: COR-001 — '#' INSIDE the value (no preceding space) is preserved" {
    # `KEY=foo#bar` is a legitimate value; only ` #` (space + hash) starts a comment.
    cat > "$TEST_TMP/.env" <<'EOF'
LEGIT_HASH=foo#bar
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LEGIT_HASH" = "foo#bar" ]
}

@test "bug-898-39: COR-001 — '#' inside double-quoted value is preserved" {
    cat > "$TEST_TMP/.env" <<'EOF'
QUOTED_HASH="value with # inside"
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$QUOTED_HASH" = "value with # inside" ]
}
