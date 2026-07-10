#!/usr/bin/env bats
# =============================================================================
# tests/unit/stop-input-probe.bats
#
# cycle-117 item A — stop-input-probe.sh (default-OFF diagnostic Stop dumper)
# (bd-c117-a-session-cap-x04j, issue #1177 A).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    HOOK="$REPO_ROOT/.claude/hooks/safety/stop-input-probe.sh"
    PR="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$PR"
    LOG="$PR/.run/stop-input-probe.jsonl"
    export PROJECT_ROOT="$PR"
}

@test "gate off (unset) → no-op, no log file created" {
    unset LOA_STOP_INPUT_PROBE
    run bash -c "printf '%s' '{\"a\":1}' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -f "$LOG" ]
}

@test "gate off (=0) → no-op, no log file created" {
    export LOA_STOP_INPUT_PROBE=0
    run bash -c "printf '%s' '{\"a\":1}' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ ! -f "$LOG" ]
}

@test "gate on → appends one line containing the verbatim stdin" {
    export LOA_STOP_INPUT_PROBE=1
    run bash -c "printf '%s' '{\"background_tasks\":[{\"id\":\"t-1\"}]}' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ -f "$LOG" ]
    [ "$(wc -l < "$LOG")" -eq 1 ]
    # Decoding the stored string yields back the verbatim stdin JSON.
    [ "$(jq -r '.stop_input' "$LOG")" = '{"background_tasks":[{"id":"t-1"}]}' ]
    [ "$(jq -r '.ts' "$LOG")" != "null" ]
}

@test "gate on → multiple invocations append (not overwrite)" {
    export LOA_STOP_INPUT_PROBE=1
    bash -c "printf '%s' '{\"n\":1}' | '$HOOK'"
    bash -c "printf '%s' '{\"n\":2}' | '$HOOK'"
    [ "$(wc -l < "$LOG")" -eq 2 ]
}

@test "gate on with non-JSON stdin → still logs, still exits 0" {
    export LOA_STOP_INPUT_PROBE=1
    run bash -c "printf '%s' 'not json{{' | '$HOOK'"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.stop_input' "$LOG")" = 'not json{{' ]
}
