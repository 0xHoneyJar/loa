#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/construct-invoke.sh — cycle-006 L D
# Trajectory emission wrapper with paired entry/exit rows matched by
# session_id. JSONL append-only writes; persona session_id stored in a
# tempfile keyed by persona+construct so the exit row can find it.
# =============================================================================

setup_file() {
    # Bridgebuilder F-001: clear skip signal when external tooling is missing.
    # construct-invoke.sh uses jq for JSONL row construction.
    command -v jq >/dev/null 2>&1 || skip "jq required (the script under test depends on it)"
}

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/construct-invoke.sh"

    # Hermetic per-test trajectory + temp dir
    export LOA_TRAJECTORY_FILE="$BATS_TEST_TMPDIR/trajectory.jsonl"
    export TMPDIR="$BATS_TEST_TMPDIR"
    # The script derives TEMP_DIR="${TMPDIR}/construct-invoke" — point it at a
    # known fresh path per test run.
}

teardown() {
    unset LOA_TRAJECTORY_FILE TMPDIR
}

# -----------------------------------------------------------------------------
# Help / usage
# -----------------------------------------------------------------------------
@test "construct-invoke: --help exits 0 and prints usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"entry"* ]]
    [[ "$output" == *"exit"* ]]
}

@test "construct-invoke: unknown subcommand -> exit 1" {
    run "$SCRIPT" nonsense
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown subcommand"* ]]
}

@test "construct-invoke: entry without args -> exit 1" {
    run "$SCRIPT" entry
    [ "$status" -eq 1 ]
}

@test "construct-invoke: exit without args -> exit 1" {
    run "$SCRIPT" exit
    [ "$status" -eq 1 ]
}

# -----------------------------------------------------------------------------
# Happy path: entry/exit pair with matched session_id
# -----------------------------------------------------------------------------
@test "construct-invoke: entry creates trajectory file and emits an entry row" {
    [ ! -f "$LOA_TRAJECTORY_FILE" ]
    run "$SCRIPT" entry ALEXANDER artisan
    [ "$status" -eq 0 ]
    [ -f "$LOA_TRAJECTORY_FILE" ]
    # The script prints the session_id on stdout for the caller to capture
    [ -n "$output" ]
    # The trajectory file should now have exactly one row, an entry row
    local count
    count=$(wc -l < "$LOA_TRAJECTORY_FILE" | tr -d ' ')
    [ "$count" -eq 1 ]
    grep -q '"event":"entry"' "$LOA_TRAJECTORY_FILE"
    grep -q '"persona":"ALEXANDER"' "$LOA_TRAJECTORY_FILE"
    grep -q '"construct_slug":"artisan"' "$LOA_TRAJECTORY_FILE"
}

@test "construct-invoke: paired entry+exit share the same session_id" {
    local entry_session_id
    entry_session_id=$("$SCRIPT" entry ALEXANDER artisan)
    [ -n "$entry_session_id" ]

    "$SCRIPT" exit ALEXANDER artisan 1234 completed >/dev/null

    # Two rows in trajectory now
    local count
    count=$(wc -l < "$LOA_TRAJECTORY_FILE" | tr -d ' ')
    [ "$count" -eq 2 ]

    # Both rows carry the same session_id captured on entry
    local entry_sid exit_sid
    entry_sid=$(jq -r 'select(.event == "entry") | .session_id' "$LOA_TRAJECTORY_FILE")
    exit_sid=$(jq -r 'select(.event == "exit")  | .session_id' "$LOA_TRAJECTORY_FILE")
    [ "$entry_sid" = "$exit_sid" ]
    [ "$entry_sid" = "$entry_session_id" ]
}

@test "construct-invoke: exit row carries duration_ms when numeric, null otherwise" {
    "$SCRIPT" entry STAMETS observer >/dev/null
    "$SCRIPT" exit  STAMETS observer 4242 completed >/dev/null
    local dur
    dur=$(jq -r 'select(.event == "exit") | .duration_ms' "$LOA_TRAJECTORY_FILE")
    [ "$dur" = "4242" ]

    # Now a second pair with non-numeric duration — should normalize to null
    rm -f "$LOA_TRAJECTORY_FILE"
    "$SCRIPT" entry STAMETS observer >/dev/null
    "$SCRIPT" exit  STAMETS observer "not-a-number" completed >/dev/null
    dur=$(jq -r 'select(.event == "exit") | .duration_ms' "$LOA_TRAJECTORY_FILE")
    [ "$dur" = "null" ]
}

@test "construct-invoke: exit without preceding entry emits row with null session_id and warns" {
    run "$SCRIPT" exit ALEXANDER unmatched 100 completed
    [ "$status" -eq 0 ]
    [[ "$output" == *"no session_id found"* ]]
    local sid
    sid=$(jq -r '.session_id' "$LOA_TRAJECTORY_FILE")
    [ "$sid" = "null" ]
}

@test "construct-invoke: trigger derives from persona handle when not supplied" {
    "$SCRIPT" entry ALEXANDER artisan >/dev/null
    local trig
    trig=$(jq -r 'select(.event == "entry") | .trigger' "$LOA_TRAJECTORY_FILE")
    [ "$trig" = "/feel" ]

    rm -f "$LOA_TRAJECTORY_FILE"
    "$SCRIPT" entry STAMETS observer >/dev/null
    trig=$(jq -r 'select(.event == "entry") | .trigger' "$LOA_TRAJECTORY_FILE")
    [ "$trig" = "/dig" ]
}

@test "construct-invoke: explicit trigger overrides persona-derived default" {
    "$SCRIPT" entry ALEXANDER artisan "/custom-trigger" >/dev/null
    local trig
    trig=$(jq -r 'select(.event == "entry") | .trigger' "$LOA_TRAJECTORY_FILE")
    [ "$trig" = "/custom-trigger" ]
}

@test "construct-invoke: emitted rows declare stream_type and read_mode" {
    "$SCRIPT" entry ALEXANDER artisan >/dev/null
    local stream_type read_mode
    stream_type=$(jq -r '.stream_type' "$LOA_TRAJECTORY_FILE")
    read_mode=$(jq -r '.read_mode' "$LOA_TRAJECTORY_FILE")
    [ "$stream_type" = "Signal" ]
    [ "$read_mode" = "orient" ]
}

@test "construct-invoke: LOA_STREAM_TYPE env override propagates to row" {
    LOA_STREAM_TYPE="Verdict" "$SCRIPT" entry ALEXANDER artisan >/dev/null
    local stream_type
    stream_type=$(jq -r '.stream_type' "$LOA_TRAJECTORY_FILE")
    [ "$stream_type" = "Verdict" ]
}

@test "construct-invoke: distinct persona+construct keys do not collide" {
    "$SCRIPT" entry ALEXANDER artisan >/dev/null
    "$SCRIPT" entry STAMETS   observer >/dev/null
    "$SCRIPT" exit  STAMETS   observer 100 completed >/dev/null
    "$SCRIPT" exit  ALEXANDER artisan  200 completed >/dev/null

    # 4 rows, 2 paired session_ids
    local count distinct_sessions
    count=$(wc -l < "$LOA_TRAJECTORY_FILE" | tr -d ' ')
    [ "$count" -eq 4 ]
    distinct_sessions=$(jq -r '.session_id' "$LOA_TRAJECTORY_FILE" | sort -u | wc -l | tr -d ' ')
    [ "$distinct_sessions" -eq 2 ]
}

@test "construct-invoke: emit is non-fatal when trajectory dir is unwritable" {
    # Place the trajectory file inside a read-only directory; the script must
    # warn but exit 0 (non-fatal write-failure semantics in emit_row).
    [ "$(id -u)" = 0 ] && skip "chmod-based test invalid as root"
    local ro_dir="$BATS_TEST_TMPDIR/ro"
    mkdir -p "$ro_dir"
    chmod 555 "$ro_dir"
    LOA_TRAJECTORY_FILE="$ro_dir/trajectory.jsonl" run "$SCRIPT" entry ALEXANDER artisan
    chmod 755 "$ro_dir"
    [ "$status" -eq 0 ]
}
