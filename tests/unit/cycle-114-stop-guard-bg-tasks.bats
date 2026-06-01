#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-114-stop-guard-bg-tasks.bats
#
# Cycle-114 FR-5 — run-mode-stop-guard.sh background_tasks/session_crons.
#
# Claude Code 2.1.145+ adds `background_tasks` and `session_crons` to Stop /
# SubagentStop hook input. The guard now soft-blocks (decision:block) when a
# Stop would orphan live background tasks. session_crons alone do NOT block.
# Fail-open on malformed/absent input.
#
# Each test runs the hook from a CLEAN temp CWD so the repo's own
# .run/*-state.json (which may be RUNNING) does not pre-empt the bg-task check.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/run-mode-stop-guard.sh"
    export HOOK
    CLEAN_CWD="$BATS_TEST_TMPDIR/clean"
    mkdir -p "$CLEAN_CWD"          # no .run/ here → state checks are inert
}

# Feed $1 as stdin to the hook, run from the clean CWD; capture output+status.
_run_stop() {
    ( cd "$CLEAN_CWD" && printf '%s' "$1" | "$HOOK" 2>&1 )
}

@test "c114-FR5: live background_tasks → decision block with ids" {
    run _run_stop '{"background_tasks":[{"id":"t-1"},{"id":"t-2"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"t-1"* ]]
    [[ "$output" == *"t-2"* ]]
}

@test "c114-FR5: empty background_tasks → no block (allow stop)" {
    run _run_stop '{"background_tasks":[]}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
}

@test "c114-FR5: absent background_tasks field → no block" {
    run _run_stop '{"session_id":"abc"}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
}

@test "c114-FR5: session_crons alone (no bg tasks) does NOT block" {
    run _run_stop '{"background_tasks":[],"session_crons":[{"id":"cron-1"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
}

@test "c114-FR5: bg tasks + session_crons → block mentions persisting crons" {
    run _run_stop '{"background_tasks":[{"id":"t-9"}],"session_crons":[{"id":"c-1"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"scheduled cron"* ]]
}

@test "c114-FR5: malformed JSON stdin → fail-open (no block)" {
    run _run_stop 'not-json{{{'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
}

@test "c114-FR5: empty stdin → fail-open (no block)" {
    run _run_stop ''
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
}
