#!/usr/bin/env bats
# =============================================================================
# bridge-mediums-summary.bats — Tests for MEDIUM-finding visibility (Issue #665)
# =============================================================================
# sprint-bug-127. Validates the MEDIUM-tally helper used by phase_bridgebuilder_review
# to surface MEDIUMs in the orchestrator log. Convergence semantics are NOT
# changed; this is a pure visibility addition.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export LIB="$PROJECT_ROOT/.claude/scripts/lib/bridge-mediums-summary.sh"

    export TMPDIR_TEST="$(mktemp -d)"
    export TRAJ_DIR="$TMPDIR_TEST/trajectory"
    export SUMMARY_PATH="$TMPDIR_TEST/post-pr-mediums-summary.json"
    mkdir -p "$TRAJ_DIR"
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# Helper: write a fixture trajectory file with the given findings
_fixture_trajectory() {
    local file="$1"
    shift
    : >"$file"
    while [[ $# -gt 0 ]]; do
        local sev="$1" act="$2" id="$3"
        echo "{\"severity\":\"${sev}\",\"action\":\"${act}\",\"finding_id\":\"${id}\",\"reasoning\":\"x\"}" >>"$file"
        shift 3
    done
}

# =========================================================================
# BMS-T1..T3: tally_mediums
# =========================================================================

@test "BMS-T1: empty trajectory dir → count 0, empty file" {
    run "$LIB" tally "$TRAJ_DIR"
    [ "$status" -eq 0 ]
    [ "$output" = "0:" ]
}

@test "BMS-T2: trajectory with 0 MEDIUM findings → count 0" {
    local traj="$TRAJ_DIR/bridge-triage-20260502.jsonl"
    _fixture_trajectory "$traj" \
        HIGH dispatch_bug f1 \
        BLOCKER dispatch_bug f2 \
        LOW log_only f3
    run "$LIB" tally "$TRAJ_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "0:"* ]]
    [[ "$output" == *"$traj" ]]
}

@test "BMS-T3: trajectory with 3 MEDIUM log_only → count 3" {
    local traj="$TRAJ_DIR/bridge-triage-20260502.jsonl"
    _fixture_trajectory "$traj" \
        MEDIUM log_only m1 \
        HIGH dispatch_bug h1 \
        MEDIUM log_only m2 \
        BLOCKER dispatch_bug b1 \
        MEDIUM log_only m3
    run "$LIB" tally "$TRAJ_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "3:"* ]]
    [[ "$output" == *"$traj" ]]
}

@test "BMS-T4: MEDIUM dispatch_bug NOT counted (only log_only)" {
    local traj="$TRAJ_DIR/bridge-triage-20260502.jsonl"
    _fixture_trajectory "$traj" \
        MEDIUM dispatch_bug d1 \
        MEDIUM dispatch_bug d2 \
        MEDIUM log_only m1
    run "$LIB" tally "$TRAJ_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "1:"* ]]
}

@test "BMS-T5: latest trajectory file selected when multiple exist" {
    local older="$TRAJ_DIR/bridge-triage-20260501.jsonl"
    local newer="$TRAJ_DIR/bridge-triage-20260502.jsonl"
    _fixture_trajectory "$older" MEDIUM log_only old1 MEDIUM log_only old2
    sleep 1
    _fixture_trajectory "$newer" MEDIUM log_only new1
    run "$LIB" tally "$TRAJ_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == "1:"* ]]
    [[ "$output" == *"$newer" ]]
}

# =========================================================================
# BMS-T6..T9: emit_mediums_warning
# =========================================================================

@test "BMS-T6: zero MEDIUMs → no WARN line, but summary file written with count 0" {
    run "$LIB" emit 0 "" "$SUMMARY_PATH"
    [ "$status" -eq 0 ]
    [[ "$output" != *"[WARN]"* ]]
    [ -f "$SUMMARY_PATH" ]
    run jq -r '.count' "$SUMMARY_PATH"
    [ "$output" = "0" ]
}

@test "BMS-T7: 3 MEDIUMs → WARN line with count and trajectory path" {
    local traj="$TRAJ_DIR/bridge-triage-20260502.jsonl"
    _fixture_trajectory "$traj" \
        MEDIUM log_only m1 \
        MEDIUM log_only m2 \
        MEDIUM log_only m3
    run bash -c "$LIB emit 3 '$traj' '$SUMMARY_PATH' 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"3 MEDIUM findings"* ]]
    [[ "$output" == *"$traj"* ]]
}

@test "BMS-T8: summary JSON includes finding IDs" {
    local traj="$TRAJ_DIR/bridge-triage-20260502.jsonl"
    _fixture_trajectory "$traj" \
        MEDIUM log_only m1 \
        MEDIUM log_only m2
    run "$LIB" emit 2 "$traj" "$SUMMARY_PATH"
    [ "$status" -eq 0 ]
    [ -f "$SUMMARY_PATH" ]
    run jq -r '.finding_ids[]' "$SUMMARY_PATH"
    [[ "$output" == *"m1"* ]]
    [[ "$output" == *"m2"* ]]
}

@test "BMS-T9: summary JSON has correct schema (count, trajectory_path, finding_ids, timestamp)" {
    "$LIB" emit 0 "" "$SUMMARY_PATH"
    run jq -e 'has("count") and has("trajectory_path") and has("finding_ids") and has("timestamp")' "$SUMMARY_PATH"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
}

# =========================================================================
# BMS-T10: end-to-end (tally → emit pipeline)
# =========================================================================

@test "BMS-T10: tally + emit pipeline produces consistent results" {
    local traj="$TRAJ_DIR/bridge-triage-20260502.jsonl"
    _fixture_trajectory "$traj" \
        MEDIUM log_only m1 \
        HIGH dispatch_bug h1 \
        MEDIUM log_only m2

    local result count file
    result=$("$LIB" tally "$TRAJ_DIR")
    count="${result%%:*}"
    file="${result#*:}"
    [ "$count" = "2" ]

    run bash -c "$LIB emit '$count' '$file' '$SUMMARY_PATH' 2>&1"
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"2 MEDIUM findings"* ]]
    run jq -r '.count' "$SUMMARY_PATH"
    [ "$output" = "2" ]
}
