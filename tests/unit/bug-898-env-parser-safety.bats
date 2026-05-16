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
LOA_SIMPLE_KEY=simple_value
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_SIMPLE_KEY" = "simple_value" ]
}

@test "bug-898-5: double-quoted values preserve whitespace and limited escapes" {
    cat > "$TEST_TMP/.env" <<'EOF'
LOA_QUOTED="hello   world"
LOA_ESCAPED="line1\nline2"
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_QUOTED" = "hello   world" ]
    # \n should expand to a newline (limited-escape contract).
    [[ "$LOA_ESCAPED" == *$'\n'* ]]
}

@test "bug-898-5b: single-quoted values pass through raw (no escape expansion)" {
    cat > "$TEST_TMP/.env" <<'EOF'
LOA_RAW='no\nexpand'
EOF
    load_env_file "$TEST_TMP/.env"
    # Single quotes: \n must remain literal characters.
    [ "$LOA_RAW" = 'no\nexpand' ]
}

@test "bug-898-6: comment lines starting with # are skipped" {
    cat > "$TEST_TMP/.env" <<'EOF'
# This is a comment
LOA_GOOD_KEY=good_value
  # indented comment
LOA_ANOTHER=another_value
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_GOOD_KEY" = "good_value" ]
    [ "$LOA_ANOTHER" = "another_value" ]
}

@test "bug-898-7: blank lines are skipped" {
    cat > "$TEST_TMP/.env" <<'EOF'
LOA_KEY_A=value_a

LOA_KEY_B=value_b

LOA_KEY_C=value_c
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_KEY_A" = "value_a" ]
    [ "$LOA_KEY_B" = "value_b" ]
    [ "$LOA_KEY_C" = "value_c" ]
}

@test "bug-898-8: CRLF line endings tolerated" {
    # Embed CR explicitly to avoid editor / heredoc stripping.
    printf 'LOA_KEY_X=value_x\r\nLOA_KEY_Y=value_y\r\n' > "$TEST_TMP/.env"
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_KEY_X" = "value_x" ]
    [ "$LOA_KEY_Y" = "value_y" ]
}

@test "bug-898-9: 'export KEY=VALUE' form is accepted" {
    cat > "$TEST_TMP/.env" <<'EOF'
export LOA_EXPORTED_KEY=exported_value
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_EXPORTED_KEY" = "exported_value" ]
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
LOA_SAFE_PATH_VAR=/usr/local/bin
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_SAFE_PATH_VAR" = "/usr/local/bin" ]
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
LOA_QUOTED_KEY="hello world" # trailing comment
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_QUOTED_KEY" = "hello world" ]
}

@test "bug-898-38: COR-001 — '#' INSIDE the value (no preceding space) is preserved" {
    # `KEY=foo#bar` is a legitimate value; only ` #` (space + hash) starts a comment.
    cat > "$TEST_TMP/.env" <<'EOF'
LOA_LEGIT_HASH=foo#bar
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_LEGIT_HASH" = "foo#bar" ]
}

@test "bug-898-39: COR-001 — '#' inside double-quoted value is preserved" {
    cat > "$TEST_TMP/.env" <<'EOF'
LOA_QUOTED_HASH="value with # inside"
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$LOA_QUOTED_HASH" = "value with # inside" ]
}

# =============================================================================
# BB #912 v3 SEC-001 — PATH and ambient exec-vector denylist
# =============================================================================

@test "bug-898-40: rejects PATH (THE ambient exec vector — every subprocess call resolves through it)" {
    # Pre-set PATH so we can verify it's NOT overwritten by the hostile .env.
    local orig_path="$PATH"
    cat > "$TEST_TMP/.env" <<EOF
PATH=/tmp/evil:/usr/bin
EOF
    load_env_file "$TEST_TMP/.env"
    [ "$PATH" = "$orig_path" ]
}

@test "bug-898-41: rejects MANPATH / INFOPATH / XDG_*_DIRS (lookup-path ambient vectors)" {
    cat > "$TEST_TMP/.env" <<EOF
MANPATH=/tmp/evil-man
INFOPATH=/tmp/evil-info
XDG_DATA_DIRS=/tmp/evil-xdg
EOF
    unset MANPATH INFOPATH XDG_DATA_DIRS
    load_env_file "$TEST_TMP/.env"
    [ -z "${MANPATH:-}" ]
    [ -z "${INFOPATH:-}" ]
    [ -z "${XDG_DATA_DIRS:-}" ]
}

@test "bug-898-42: rejects SHELLOPTS / BASHOPTS (shell-state hijack)" {
    cat > "$TEST_TMP/.env" <<EOF
SHELLOPTS=xtrace:errexit
BASHOPTS=expand_aliases
EOF
    load_env_file "$TEST_TMP/.env"
    # SHELLOPTS is bash-readonly; the denylist refusal is the primary check.
    # The shell's own SHELLOPTS may still be set (legitimately) by bash itself —
    # what we test is the denylist *refused* the assignment, by checking the
    # WARN message landed.
    run load_env_file "$TEST_TMP/.env"
    # BB-912 v6 F-003 fix: pin BOTH the key name AND the rejection reason.
    # The previous OR-chain accepted "denylisted" as a v1-era artifact; the
    # current v4+ loader emits "not in positive allowlist". OR-chained
    # assertions hide refactor-driven regressions in the reason text.
    [[ "$output" == *"SHELLOPTS"* ]]
    [[ "$output" == *"positive allowlist"* ]]
}

@test "bug-898-43: rejects UID / EUID / readonly-built-in shell vars" {
    cat > "$TEST_TMP/.env" <<EOF
UID=99999
EUID=99999
GROUPS=hijack
PPID=99999
EOF
    # Real UID/EUID are readonly; the denylist rejects the assignment regardless.
    # Test passes if the loader doesn't crash (REL-001 wrap also matters here).
    run load_env_file "$TEST_TMP/.env"
    [ "$status" -eq 0 ]
}

# =============================================================================
# BB #912 v3 REL-001 — export-failure wrap (loader doesn't DoS the orchestrator)
# =============================================================================

@test "bug-898-44: REL-001 — readonly user variable does NOT abort the loader (set -e safe)" {
    # Simulate a user-readonly var (not bash built-in) by declaring one
    # before sourcing the loader. The loader's export must fail gracefully
    # WITHOUT propagating exit to the caller (which is what would crash a
    # set -e orchestrator).
    declare -r LOA_USER_READONLY="frozen-value" 2>/dev/null
    cat > "$TEST_TMP/.env" <<'EOF'
LOA_USER_READONLY=hostile-value
EOF
    # We use a subshell because `declare -r` is process-local and persists
    # for the rest of this bats test file otherwise.
    run bash -c "
        unset _LOA_ENV_LOADER_SOURCED
        source '$PROJECT_ROOT/.claude/scripts/lib/env-loader.sh'
        declare -r LOA_USER_READONLY='frozen-value'
        set -e
        load_env_file '$TEST_TMP/.env'
        echo 'reached-after-load'
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"reached-after-load"* ]]
}

@test "bug-898-45: REL-001 — export-failure warns to stderr but continues to next line" {
    declare -r LOA_USER_READONLY="frozen-value" 2>/dev/null
    cat > "$TEST_TMP/.env" <<'EOF'
LOA_USER_READONLY=should-fail-but-not-abort
LOA_GOOD_KEY_AFTER=this-must-still-load
EOF
    run bash -c "
        unset _LOA_ENV_LOADER_SOURCED
        source '$PROJECT_ROOT/.claude/scripts/lib/env-loader.sh'
        declare -r LOA_USER_READONLY='frozen-value'
        load_env_file '$TEST_TMP/.env'
        echo \"LOA_GOOD_KEY_AFTER=\$LOA_GOOD_KEY_AFTER\"
    " 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"export failed"* ]]
    [[ "$output" == *"LOA_GOOD_KEY_AFTER=this-must-still-load"* ]]
}

# =============================================================================
# BB #912 v4 → v5 — positive-allowlist closes the denylist whack-a-mole
#
# After v3 BB found PATH + REL-001, v4 BB found YET MORE denylist gaps:
#   - GIT_CONFIG_COUNT + GIT_CONFIG_KEY_* + GIT_CONFIG_VALUE_* (git env-config
#     injection — can set core.sshCommand without touching the global config)
#   - lowercase npm_config_* bypasses the uppercase NPM_CONFIG_* glob
# At which point: BB has explicitly suggested positive-allowlist three
# iterations in a row. v5 switches to positive allowlist; these tests
# pin the architectural invariant.
# =============================================================================

@test "bug-898-46: v5 architectural — GIT_CONFIG_COUNT rejected (not in allowlist)" {
    cat > "$TEST_TMP/.env" <<'EOF'
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=core.sshCommand
GIT_CONFIG_VALUE_0=/tmp/hostile-ssh
EOF
    unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
    load_env_file "$TEST_TMP/.env"
    [ -z "${GIT_CONFIG_COUNT:-}" ]
    [ -z "${GIT_CONFIG_KEY_0:-}" ]
    [ -z "${GIT_CONFIG_VALUE_0:-}" ]
}

@test "bug-898-47: v5 architectural — lowercase npm_config_* rejected (case-insensitive bypass)" {
    cat > "$TEST_TMP/.env" <<'EOF'
npm_config_node_options=--require=/tmp/x.js
npm_config_script_shell=/tmp/hostile-shell
EOF
    unset npm_config_node_options npm_config_script_shell
    load_env_file "$TEST_TMP/.env"
    [ -z "${npm_config_node_options:-}" ]
    [ -z "${npm_config_script_shell:-}" ]
}

@test "bug-898-48: v5 architectural — arbitrary unknown keys rejected (default-deny)" {
    cat > "$TEST_TMP/.env" <<'EOF'
HYPOTHETICAL_FUTURE_HOOK_VAR=/tmp/whatever
SOME_RANDOM_THING=value
ATTACKER_INVENTED_KEY=arbitrary
EOF
    unset HYPOTHETICAL_FUTURE_HOOK_VAR SOME_RANDOM_THING ATTACKER_INVENTED_KEY
    load_env_file "$TEST_TMP/.env"
    [ -z "${HYPOTHETICAL_FUTURE_HOOK_VAR:-}" ]
    [ -z "${SOME_RANDOM_THING:-}" ]
    [ -z "${ATTACKER_INVENTED_KEY:-}" ]
}

@test "bug-898-49: v5 positive controls — every documented allowlist pattern accepts a representative key" {
    cat > "$TEST_TMP/.env" <<'EOF'
ANTHROPIC_API_KEY=sk-ant-test
OPENAI_API_KEY=sk-test
GOOGLE_API_KEY=key-test
GEMINI_API_KEY=gemini-test
GOOGLE_APPLICATION_CREDENTIALS=/tmp/adc.json
AWS_ACCESS_KEY_ID=AKIA-test
AWS_SECRET_ACCESS_KEY=secret-test
AWS_REGION=us-east-1
BEDROCK_MODEL_ID=anthropic.claude-opus-4
LOA_DEBUG=1
HONEYJAR_PROJECT=test
GITHUB_TOKEN=ghp_test
EOF
    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY \
          GOOGLE_APPLICATION_CREDENTIALS \
          AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION \
          BEDROCK_MODEL_ID LOA_DEBUG HONEYJAR_PROJECT GITHUB_TOKEN
    load_env_file "$TEST_TMP/.env"
    [ "$ANTHROPIC_API_KEY" = "sk-ant-test" ]
    [ "$OPENAI_API_KEY" = "sk-test" ]
    [ "$GOOGLE_API_KEY" = "key-test" ]
    [ "$GEMINI_API_KEY" = "gemini-test" ]
    [ "$GOOGLE_APPLICATION_CREDENTIALS" = "/tmp/adc.json" ]
    [ "$AWS_ACCESS_KEY_ID" = "AKIA-test" ]
    [ "$AWS_SECRET_ACCESS_KEY" = "secret-test" ]
    [ "$AWS_REGION" = "us-east-1" ]
    [ "$BEDROCK_MODEL_ID" = "anthropic.claude-opus-4" ]
    [ "$LOA_DEBUG" = "1" ]
    [ "$HONEYJAR_PROJECT" = "test" ]
    [ "$GITHUB_TOKEN" = "ghp_test" ]
}

@test "bug-898-50: v6 SEC-001 — base URL keys are REJECTED (credential-redirection threat tier)" {
    # BB-912 v6 SEC-001 fix: .env-loaded BASE_URL would let a hostile .env
    # redirect provider traffic to an attacker-controlled endpoint while
    # real API keys come from the parent env. The allowlist no longer
    # accepts destinations; operators must set them via parent env or
    # .env.local.
    cat > "$TEST_TMP/.env" <<'EOF'
ANTHROPIC_BASE_URL=https://attacker.example.com
OPENAI_BASE_URL=https://attacker.example.com
ANTHROPIC_BEDROCK_BASE_URL=https://attacker.example.com
ANTHROPIC_VERTEX_BASE_URL=https://attacker.example.com
EVIL_BASE_URL=https://attacker.example.com
EOF
    unset ANTHROPIC_BASE_URL OPENAI_BASE_URL ANTHROPIC_BEDROCK_BASE_URL \
          ANTHROPIC_VERTEX_BASE_URL EVIL_BASE_URL
    run load_env_file "$TEST_TMP/.env"
    [ "$status" -eq 0 ]
    [ -z "${ANTHROPIC_BASE_URL:-}" ]
    [ -z "${OPENAI_BASE_URL:-}" ]
    [ -z "${ANTHROPIC_BEDROCK_BASE_URL:-}" ]
    [ -z "${ANTHROPIC_VERTEX_BASE_URL:-}" ]
    [ -z "${EVIL_BASE_URL:-}" ]
    # WARN should fire for each one
    [[ "$output" == *"ANTHROPIC_BASE_URL"* ]]
    [[ "$output" == *"OPENAI_BASE_URL"* ]]
}

@test "bug-898-51: v6 COR-001 — allowlist iteration is CWD-independent (quoted array expansion)" {
    # BB-912 v6 COR-001 fix: unquoted `${arr[@]}` in the allowlist
    # iterator let bash filename-expand glob entries like `*_API_KEY`
    # against the caller's CWD. A file literally named OPENAI_API_KEY in
    # CWD would replace the wildcard and legitimate API key loads would
    # silently fail. Test runs from a CWD seeded with such a file.
    local trap_dir
    trap_dir="$(mktemp -d -p "$TEST_TMP")"
    : > "$trap_dir/OPENAI_API_KEY"   # the trap file
    : > "$trap_dir/ANTHROPIC_API_KEY"
    cat > "$trap_dir/.env" <<'EOF'
ANTHROPIC_API_KEY=sk-ant-real
OPENAI_API_KEY=sk-real
EOF
    unset ANTHROPIC_API_KEY OPENAI_API_KEY
    (
        cd "$trap_dir"
        load_env_file "$trap_dir/.env"
        [ "$ANTHROPIC_API_KEY" = "sk-ant-real" ]
        [ "$OPENAI_API_KEY" = "sk-real" ]
    )
}
