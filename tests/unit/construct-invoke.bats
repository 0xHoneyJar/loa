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

# -----------------------------------------------------------------------------
# Bridgebuilder PR #617 iter-3 HIGH_CONSENSUS: race condition in session-id
# storage. Filesystem-as-shared-memory keyed by (persona, construct) is
# race-prone — parallel entry calls with the same key overwrite each other,
# and the first process's exit then emits the second process's session_id.
# Mitigation: callers can pass session_id explicitly via positional arg 6 or
# LOA_SESSION_ID env var; that path bypasses the temp file entirely.
# -----------------------------------------------------------------------------
@test "construct-invoke: exit accepts explicit session_id as positional arg 6" {
    local sid="explicit-fixed-uuid-12345"
    "$SCRIPT" exit ALEXANDER artisan 100 completed "" "$sid" >/dev/null
    local emitted_sid
    emitted_sid=$(jq -r '.session_id' "$LOA_TRAJECTORY_FILE")
    [ "$emitted_sid" = "$sid" ]
    # Should NOT have emitted the no-session-id-found warning, since explicit
    # value-passing skips the temp-file lookup entirely.
}

@test "construct-invoke: LOA_SESSION_ID env is honored when no explicit arg" {
    local sid="env-passed-uuid-67890"
    LOA_SESSION_ID="$sid" "$SCRIPT" exit ALEXANDER artisan 100 completed >/dev/null
    local emitted_sid
    emitted_sid=$(jq -r '.session_id' "$LOA_TRAJECTORY_FILE")
    [ "$emitted_sid" = "$sid" ]
}

@test "construct-invoke: explicit positional session_id beats env var" {
    local positional_sid="positional-wins"
    local env_sid="env-loses"
    LOA_SESSION_ID="$env_sid" "$SCRIPT" exit ALEXANDER artisan 100 completed "" "$positional_sid" >/dev/null
    local emitted_sid
    emitted_sid=$(jq -r '.session_id' "$LOA_TRAJECTORY_FILE")
    [ "$emitted_sid" = "$positional_sid" ]
}

@test "construct-invoke: temp-file fallback emits deprecation warning by default" {
    # Iter-4 escalation: the temp-file fallback path is documented as racy
    # under concurrency. Make the racy path noisy so callers see it and
    # migrate to explicit session_id passing.
    "$SCRIPT" entry ALEXANDER artisan >/dev/null
    run "$SCRIPT" exit ALEXANDER artisan 100 completed
    [ "$status" -eq 0 ]
    [[ "$output" == *"DEPRECATION"* ]]
    [[ "$output" == *"explicit"* ]]
}

@test "construct-invoke: LOA_INVOKE_FALLBACK_QUIET=1 silences the deprecation warning" {
    "$SCRIPT" entry ALEXANDER artisan >/dev/null
    LOA_INVOKE_FALLBACK_QUIET=1 run "$SCRIPT" exit ALEXANDER artisan 100 completed
    [ "$status" -eq 0 ]
    [[ "$output" != *"DEPRECATION"* ]]
}

@test "construct-invoke: explicit session_id never triggers the deprecation warning" {
    local sid="explicit-no-warn"
    run "$SCRIPT" exit ALEXANDER artisan 100 completed "" "$sid"
    [ "$status" -eq 0 ]
    [[ "$output" != *"DEPRECATION"* ]]
}

@test "construct-invoke: race regression — explicit session_id survives concurrent entries from another process" {
    # Simulate the race: a second 'entry' call with the same (persona, construct)
    # overwrites the temp file. The original caller still gets its correct
    # session_id IF it captured the value from entry's stdout and threads it
    # explicitly into exit. The temp-file fallback would lose.
    local first_sid second_sid
    first_sid=$("$SCRIPT" entry ALEXANDER artisan)
    # A "concurrent" second entry stomps on the temp file.
    second_sid=$("$SCRIPT" entry ALEXANDER artisan)
    [ "$first_sid" != "$second_sid" ]

    # Without explicit-pass, exit reads whatever the temp file currently
    # holds — i.e. the second_sid. (Demonstrates the race.)
    rm -f "$LOA_TRAJECTORY_FILE"
    "$SCRIPT" exit ALEXANDER artisan 100 completed >/dev/null
    local raced_sid
    raced_sid=$(jq -r '.session_id' "$LOA_TRAJECTORY_FILE")
    [ "$raced_sid" = "$second_sid" ]   # temp-file race lost the first call

    # With explicit-pass, the first caller's session_id is preserved
    # regardless of what the temp file contains.
    rm -f "$LOA_TRAJECTORY_FILE"
    "$SCRIPT" exit ALEXANDER artisan 100 completed "" "$first_sid" >/dev/null
    local preserved_sid
    preserved_sid=$(jq -r '.session_id' "$LOA_TRAJECTORY_FILE")
    [ "$preserved_sid" = "$first_sid" ]
}
