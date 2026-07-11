#!/usr/bin/env bats
# =============================================================================
# tests/unit/agent-ergonomics-loa-status.bats
# agent-ergonomics pass 1 (bd-m1o6) R-001 — loa-status.sh strict arg parsing
# + NO_COLOR/non-TTY color guard.
#
# Pre-fix behavior being pinned against regression:
#   - '--jsno' (typo'd --json) fell through the --economy forwarding catch-all
#     and produced FULL HUMAN output with exit 0 — a JSON consumer got ANSI
#     prose and a success code.
#   - Human output carried raw ANSI escapes into pipes regardless of NO_COLOR
#     or TTY state.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    STATUS="$PROJECT_ROOT/.claude/scripts/loa-status.sh"
}

@test "R-001: unknown flag --jsno rejected with exit 2 + Unknown option + Usage" {
    run timeout 30 bash "$STATUS" --jsno
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown option: --jsno" ]]
    [[ "$output" =~ "Usage: loa-status.sh" ]]
}

@test "R-001: piped human output contains no ANSI escapes (non-TTY guard)" {
    run timeout 30 bash "$STATUS"
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

@test "R-001: NO_COLOR=1 suppresses ANSI escapes" {
    NO_COLOR=1 run timeout 30 bash "$STATUS"
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]]
}

@test "R-001: --json still emits valid JSON with a state field" {
    run timeout 30 bash "$STATUS" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.state' >/dev/null
}

@test "R-001: --help exits 0 and shows usage" {
    run timeout 30 bash "$STATUS" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage: loa-status.sh" ]]
}

# --- R-007: --triage mega-command (one call: state + health + next) ---

@test "R-007: --triage --json emits ONE valid JSON envelope with status/health/next" {
    run timeout 90 bash "$STATUS" --triage --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -s 'length')" -eq 1 ]
    echo "$output" | jq -e '.schema_version and .status.state and .health.status and .next' >/dev/null
}

@test "R-007: --triage human mode shows state/health lines, exit 0, no ANSI when piped" {
    run timeout 90 bash "$STATUS" --triage
    [ "$status" -eq 0 ]
    [[ "$output" =~ "state:" ]]
    [[ "$output" =~ "health:" ]]
    [[ "$output" != *$'\033'* ]]
}

@test "R-007: --triage help text documents the flag" {
    run timeout 30 bash "$STATUS" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "--triage" ]]
}
