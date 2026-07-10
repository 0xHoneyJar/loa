#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-117-stop-guard-zombie-exemption.bats
#
# cycle-117 item A — run-mode-stop-guard.sh session-cap zombie exemption
# (bd-c117-a-session-cap-x04j, issue #1177 A).
#
# When an UNEXPIRED .run/session-limit-state.json is present, the bg-task
# soft-block is swapped for a loud stderr advisory and falls through (so a
# quota-hung teammate cannot deadlock Stop). Expired/absent/malformed marker →
# today's block is preserved (fail-open to the existing deadlock guard).
#
# Reuses cycle-114-stop-guard-bg-tasks.bats's harness: clean CWD (so the repo's
# own .run/ never leaks), stdin-piped JSON, substring assertions.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/run-mode-stop-guard.sh"
    export HOOK
    CLEAN_CWD="$BATS_TEST_TMPDIR/clean"
    mkdir -p "$CLEAN_CWD/.run"
}

_run_stop() {
    ( cd "$CLEAN_CWD" && printf '%s' "$1" | "$HOOK" 2>&1 )
}

# Seed a session-limit marker with reset_at_epoch=$1.
_marker() {
    printf '{"hit_at":"2026-07-06T00:00:00Z","reset_at":"x","reset_at_epoch":%s}' "$1" \
        > "$CLEAN_CWD/.run/session-limit-state.json"
}

@test "a) bg tasks, NO marker → today's block preserved (regression guard)" {
    run _run_stop '{"background_tasks":[{"id":"t-1"},{"id":"t-2"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"t-1"* ]]
}

@test "b) bg tasks + UNEXPIRED marker → exempt: advisory, no block, fall through" {
    _marker 9999999999
    run _run_stop '{"background_tasks":[{"id":"zombie-1"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
    [[ "$output" == *"[session-limit-active]"* ]]
    [[ "$output" == *"zombie-1"* ]]
}

@test "c) bg tasks + EXPIRED marker → NOT exempt, normal block (freshness)" {
    _marker 1577836800   # 2020, long past
    run _run_stop '{"background_tasks":[{"id":"t-9"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" != *"[session-limit-active]"* ]]
}

@test "d) bg tasks + MALFORMED marker → fail-open to today's block" {
    printf 'not json {{{' > "$CLEAN_CWD/.run/session-limit-state.json"
    run _run_stop '{"background_tasks":[{"id":"t-3"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" != *"[session-limit-active]"* ]]
}

@test "d2) bg tasks + marker missing reset_at_epoch → fail-open to block" {
    printf '{"hit_at":"x"}' > "$CLEAN_CWD/.run/session-limit-state.json"
    run _run_stop '{"background_tasks":[{"id":"t-4"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" != *"[session-limit-active]"* ]]
}

@test "e) NO bg tasks + UNEXPIRED marker → empty-bg path untouched, no block" {
    _marker 9999999999
    run _run_stop '{"background_tasks":[]}'
    [ "$status" -eq 0 ]
    [[ "$output" != *'"decision": "block"'* ]]
    [[ "$output" != *"[session-limit-active]"* ]]
}

@test "f) exempt bg tasks fall through to an active sprint block" {
    # Unexpired marker exempts bg tasks, but a RUNNING sprint still soft-blocks.
    _marker 9999999999
    printf '{"state":"RUNNING","sprints":{"current":"sprint-3"}}' > "$CLEAN_CWD/.run/sprint-plan-state.json"
    run _run_stop '{"background_tasks":[{"id":"z-1"}]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"[session-limit-active]"* ]]
    [[ "$output" == *'"decision": "block"'* ]]
    [[ "$output" == *"state=RUNNING"* ]]
}
