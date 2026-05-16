#!/usr/bin/env bats
# =============================================================================
# tests/unit/block-destructive-bash-limitations.bats
# cycle-111 sprint-164 T7.1 — pins the §11 accepted bypass classes.
#
# These tests INTENTIONALLY assert that bypass classes DO bypass (allow /
# exit 0). A future cycle that closes any of them flips the corresponding
# test to "asserts block" and the change is reviewable. See SDD §11 for
# the full table + rationale.
# =============================================================================

setup() {
    BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/block-destructive-bash.sh"
    export HOOK PROJECT_ROOT
    export LOA_REPO_ROOT="$BATS_TEST_TMPDIR"
    unset LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED
}

hook_invoke() {
    local cmd="$1"
    local payload
    payload=$(jq -cn --arg c "$cmd" '{tool_input: {command: $c}}')
    echo "$payload" | "$HOOK"
}

# =============================================================================
# SDD §11 accepted-limitation pins (each asserts the bypass DOES bypass)
# =============================================================================

@test "limitation: SQL comment containing WHERE bypasses FR-1.6" {
    # `DELETE FROM x; -- WHERE id=1` — the Pass-B `\bWHERE\b` check matches
    # the WHERE token inside the SQL comment, so the WHERE-less DELETE
    # silently passes. A real WHERE-aware SQL parser is needed; bash regex
    # is the wrong tool.
    run hook_invoke 'psql -c "DELETE FROM users -- WHERE id=1"'
    [ "$status" -eq 0 ]
}

@test "limitation: rm -rf quoted-path-with-space is conservatively blocked" {
    # `read -r -a` does NOT shell-parse quotes. The path with embedded
    # space splits into multiple tokens, neither matching the allow list,
    # triggering AMBIGUOUS conservative-block. This is desired behavior
    # for safety — not a true "bypass" but documented as a quote-parse
    # limitation (SDD §5.0.1). Pin asserts BLOCK, so a future shell-quote-
    # aware rewrite changes it intentionally.
    run hook_invoke 'rm -rf "/etc foo"'
    [ "$status" -eq 2 ]
}

@test "limitation: bash -c with destructive verb in inner quoted string IS visible" {
    # When the inner command verb is in the outer command's quoted
    # string, the regex DOES see it (this is NOT bypass — the hook
    # scans the full tool_input.command). Pinned here as a positive
    # control to distinguish from the genuine subshell-bypass classes.
    run hook_invoke "bash -c 'rm -rf /etc'"
    [ "$status" -eq 2 ]
}

@test "limitation: eval base64-decoded destructive verb bypasses" {
    # base64("rm -rf /") = "cm0gLXJmIC8=" — the outer command is `eval $(...)`
    # which the hook cannot decode at scan time. This is a fundamental
    # limit of regex-based shell guards: any general-purpose interpreter
    # can host destructive ops outside the hook's visibility.
    run hook_invoke 'eval $(echo cm0gLXJmIC8= | base64 -d)'
    [ "$status" -eq 0 ]
}

@test "limitation: python invoking destructive verb via SCRIPT FILE bypasses" {
    # When the destructive op lives in a script file (not inline), the hook
    # sees only `python3 script.py` and cannot inspect script.py contents.
    # Pinned here as a true bypass class. (Inline `python3 -c "..."` with the
    # verb in the quoted string IS now visible to the v1.38.0 leading-anchor
    # extension — that bypass class is partially closed; this script-file
    # form remains the real bypass.)
    run hook_invoke 'python3 /tmp/destructive_script.py'
    [ "$status" -eq 0 ]
}

@test "limitation: jq missing from PATH allows all destructive commands (FR-3 fail-open)" {
    # SDD §6.5 + §11 — pre-existing Loa convention. With jq absent the
    # hook cannot parse tool_input.command, fails-open per FR-3. The
    # one-shot stderr WARNING is emitted but the block-decision is
    # always allow. Cycle-112 candidate for a real fix (filesystem
    # marker + fail-closed for known-destructive verb shapes).
    # Use shim PATH (everything except jq) so the shebang `env bash`
    # lookup still works.
    local shimdir="$BATS_TEST_TMPDIR/no-jq-bin"
    mkdir -p "$shimdir"
    for bin in bash sh env grep sed awk cat tr head sort cut printf date mkdir rm cp mv ls test true false sleep dirname basename realpath; do
        if command -v "$bin" >/dev/null 2>&1; then
            ln -sf "$(command -v "$bin")" "$shimdir/$bin" 2>/dev/null || true
        fi
    done
    run env -i PATH="$shimdir" HOME="$HOME" LOA_REPO_ROOT="$LOA_REPO_ROOT" bash -c "echo '{\"tool_input\":{\"command\":\"rm -rf /\"}}' | '$HOOK'"
    [ "$status" -eq 0 ]
}
