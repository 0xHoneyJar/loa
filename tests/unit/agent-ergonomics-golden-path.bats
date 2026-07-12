#!/usr/bin/env bats
# =============================================================================
# tests/unit/agent-ergonomics-golden-path.bats
# agent-ergonomics pass 1 (bd-m1o6) R-013 — golden-path.sh direct-execution
# guard. Pre-fix: bash golden-path.sh (bare / --help / -h / help) ALL exited 0
# with zero output on both streams — a silent no-op indistinguishable from
# success. Now: executed-not-sourced → usage on stderr + exit 2; sourcing is
# unchanged.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    GP="$PROJECT_ROOT/.claude/scripts/golden-path.sh"
}

@test "R-013: bare direct execution exits 2 and teaches 'source'" {
    run timeout 15 bash "$GP"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "sourced function library" ]]
    [[ "$output" =~ "source .claude/scripts/golden-path.sh" ]]
}

@test "R-013: direct execution with --help exits 2 with the same usage (not silence)" {
    run timeout 15 bash "$GP" --help
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "R-013: usage names the machine-readable alternatives (triage one-call + capabilities)" {
    run timeout 15 bash "$GP"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "loa-status.sh --triage --json" ]]
    [[ "$output" =~ "loa-capabilities.sh" ]]
}

@test "R-013: sourcing still works and defines the golden_* functions" {
    run timeout 15 bash -c "cd '$PROJECT_ROOT' && source '$GP' && declare -F golden_suggest_command >/dev/null && declare -F golden_detect_workflow_state >/dev/null && echo sourced-ok"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sourced-ok" ]]
}
