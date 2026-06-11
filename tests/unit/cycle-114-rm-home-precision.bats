#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-114-rm-home-precision.bats
#
# Cycle-114 FR-6 — block-destructive-bash.sh $HOME-trailing-slash precision.
#
# Before: `rm -rf $HOME/` matched neither BLOCK alternation (the first group
# needs an exact `$HOME`; the second lacked `$HOME/`), so it fell to the
# conservative AMBIGUOUS branch — still exit-2 blocked, but mislabeled.
# After: the home-ROOT trailing-slash forms ($HOME/, ${HOME}/, ~/) hit
# FR-2-BLOCK with the catastrophic-path message. A home CHILD path
# ($HOME/projects, ~/subdir) is NOT catastrophic and stays AMBIGUOUS.
#
# Mirrors the Claude Code 2.1.154 `rm -rf $HOME` trailing-slash fix.
# Dangerous literals live in THIS file only (never on a shell command line),
# so the active PreToolUse hook does not intercept the test author.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/block-destructive-bash.sh"
    export HOOK PROJECT_ROOT
    export LOA_REPO_ROOT="$BATS_TEST_TMPDIR"
    unset LOA_BLOCK_DESTRUCTIVE_JQ_MISSING_WARNED
}

# Invoke the hook with a command; capture combined output + exit status.
_run_hook() {
    jq -cn --arg c "$1" '{tool_input: {command: $c}}' | "$HOOK" 2>&1
}

@test "c114-FR6: rm -rf \$HOME/ → FR-2-BLOCK (was AMBIGUOUS)" {
    run _run_hook 'rm -rf $HOME/'
    [ "$status" -eq 2 ]
    [[ "$output" == *"FR-2-BLOCK"* ]]
    [[ "$output" == *"catastrophic"* ]]
}

@test "c114-FR6: rm -rf \${HOME}/ → FR-2-BLOCK" {
    run _run_hook 'rm -rf ${HOME}/'
    [ "$status" -eq 2 ]
    [[ "$output" == *"FR-2-BLOCK"* ]]
}

@test "c114-FR6: bare \$HOME (no slash) still FR-2-BLOCK (no regression)" {
    run _run_hook 'rm -rf $HOME'
    [ "$status" -eq 2 ]
    [[ "$output" == *"FR-2-BLOCK"* ]]
}

@test "c114-FR6: ~/ (tilde home root) still FR-2-BLOCK (no regression)" {
    run _run_hook 'rm -rf ~/'
    [ "$status" -eq 2 ]
    [[ "$output" == *"FR-2-BLOCK"* ]]
}

@test "c114-FR6: rm -rf \$HOME/projects (child) stays AMBIGUOUS, not catastrophic" {
    run _run_hook 'rm -rf $HOME/projects'
    [ "$status" -eq 2 ]
    [[ "$output" == *"FR-2-AMBIGUOUS"* ]]
    [[ "$output" != *"FR-2-BLOCK"* ]]
}

@test "c114-FR6: safe bounded path still allowed (no regression)" {
    run _run_hook 'rm -rf node_modules/'
    [ "$status" -eq 0 ]
}
