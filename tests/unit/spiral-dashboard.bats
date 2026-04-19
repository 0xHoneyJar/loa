#!/usr/bin/env bats
# =============================================================================
# spiral-dashboard.bats — tests for #569 spiral observability dashboard
# =============================================================================
# Validates:
# - _emit_dashboard_snapshot aggregates flight-recorder.jsonl correctly
# - dashboard.jsonl (append-only) and dashboard-latest.json (pointer) both
#   receive the snapshot
# - Failures are detected (verdict startswith "FAIL")
# - Budget remaining is computed when SPIRAL_TOTAL_BUDGET is exported
# - Per-phase rollup groups by .phase and sums metrics
# - cmd_status --json merges dashboard into state output
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export EVIDENCE_SH="$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
    export ORCH_SH="$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/spiral-dashboard-test"
    mkdir -p "$TEST_DIR"
}

teardown() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# Helper: source the evidence script + init flight recorder at a test path.
_setup_flight_recorder() {
    local fr_path="$TEST_DIR/flight-recorder.jsonl"
    touch "$fr_path"
    export _FLIGHT_RECORDER="$fr_path"
    export _FLIGHT_RECORDER_SEQ=0
}

# Helper: append a synthetic flight-recorder entry.
_append_event() {
    local phase="$1" actor="$2" action="$3" cost="${4:-0}" duration="${5:-0}" verdict="${6:-}"
    local bytes="${7:-0}"
    jq -n -c \
        --argjson seq "$((++_FLIGHT_RECORDER_SEQ))" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg phase "$phase" \
        --arg actor "$actor" \
        --arg action "$action" \
        --argjson cost "$cost" \
        --argjson duration_ms "$duration" \
        --argjson bytes "$bytes" \
        --arg verdict "$verdict" \
        '{seq: $seq, ts: $ts, phase: $phase, actor: $actor, action: $action,
          input_checksum: null, output_checksum: null, output_path: null,
          output_bytes: $bytes, duration_ms: $duration_ms, cost_usd: $cost,
          verdict: (if $verdict == "" then null else $verdict end)}' \
        >> "$_FLIGHT_RECORDER"
}

# =========================================================================
# SPD-T1: basic snapshot structure
# =========================================================================

@test "snapshot emits dashboard.jsonl + dashboard-latest.json" {
    _setup_flight_recorder
    _append_event "DISCOVERY" "claude" "invoke" "0.10" "1500" "" "200"

    run bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'DISCOVERY' '$TEST_DIR'
    "
    [ "$status" -eq 0 ]
    [ -f "$TEST_DIR/dashboard.jsonl" ]
    [ -f "$TEST_DIR/dashboard-latest.json" ]
}

@test "snapshot payload has schema version" {
    _setup_flight_recorder
    _append_event "DISCOVERY" "claude" "invoke" "0.10" "1500"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'DISCOVERY' '$TEST_DIR'
    "
    run jq -r '.schema' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "spiral.dashboard.v1" ]
}

@test "snapshot records current_phase" {
    _setup_flight_recorder
    _append_event "DISCOVERY" "claude" "invoke" "0.10" "1500"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'ARCHITECTURE' '$TEST_DIR'
    "
    run jq -r '.current_phase' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "ARCHITECTURE" ]
}

# =========================================================================
# SPD-T2: totals rollup math
# =========================================================================

@test "totals.cost_usd sums across all events" {
    _setup_flight_recorder
    _append_event "DISCOVERY" "claude" "invoke" "0.10" "1000"
    _append_event "ARCHITECTURE" "claude" "invoke" "0.25" "2000"
    _append_event "IMPLEMENT" "claude" "invoke" "0.50" "3000"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'IMPLEMENT' '$TEST_DIR'
    "
    run jq -r '.totals.cost_usd' "$TEST_DIR/dashboard-latest.json"
    # 0.1 + 0.25 + 0.5 = 0.85
    [[ "$output" == "0.85" ]]
}

@test "totals.actions counts all events" {
    _setup_flight_recorder
    for i in 1 2 3 4 5; do
        _append_event "PHASE$i" "actor" "action" "0.01" "100"
    done

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'x' '$TEST_DIR'
    "
    run jq -r '.totals.actions' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "5" ]
}

@test "totals.failures counts verdicts starting with FAIL" {
    _setup_flight_recorder
    _append_event "DISCOVERY" "claude" "invoke" "0.10" "1000" ""
    _append_event "IMPL" "gate" "FAILED" "0" "0" "FAIL:MISSING:foo.md"
    _append_event "REVIEW" "gate" "FAILED" "0" "0" "FAIL:CIRCUIT_BREAKER:attempts=3"
    _append_event "AUDIT" "gate" "verified" "0" "0" "OK"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'AUDIT' '$TEST_DIR'
    "
    run jq -r '.totals.failures' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "2" ]
}

# =========================================================================
# SPD-T3: budget math
# =========================================================================

@test "totals.budget_remaining_usd = cap - cost when SPIRAL_TOTAL_BUDGET set" {
    _setup_flight_recorder
    _append_event "A" "x" "y" "3.00" "100"
    _append_event "B" "x" "y" "4.50" "100"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        export SPIRAL_TOTAL_BUDGET=12
        _emit_dashboard_snapshot 'IMPL' '$TEST_DIR'
    "
    run jq -r '.totals.budget_remaining_usd' "$TEST_DIR/dashboard-latest.json"
    # 12 - 7.5 = 4.5
    [[ "$output" == "4.5" ]]
}

@test "totals.budget_cap_usd is null when SPIRAL_TOTAL_BUDGET unset" {
    _setup_flight_recorder
    _append_event "A" "x" "y" "1.00" "100"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        unset SPIRAL_TOTAL_BUDGET
        _emit_dashboard_snapshot 'x' '$TEST_DIR'
    "
    run jq -r '.totals.budget_cap_usd' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "null" ]
}

# =========================================================================
# SPD-T4: per-phase rollup groups by .phase
# =========================================================================

@test "per_phase groups events by phase + sums durations" {
    _setup_flight_recorder
    _append_event "DISCOVERY" "claude" "invoke" "0.1" "1000"
    _append_event "DISCOVERY" "claude" "invoke" "0.2" "2000"
    _append_event "ARCHITECTURE" "claude" "invoke" "0.3" "3000"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'ARCHITECTURE' '$TEST_DIR'
    "
    run jq -r '.per_phase | length' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "2" ]

    run jq -r '.per_phase[] | select(.phase == "DISCOVERY") | .duration_ms' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "3000" ]

    run jq -r '.per_phase[] | select(.phase == "DISCOVERY") | .actions' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "2" ]
}

# =========================================================================
# SPD-T5: fix-loop + BB cycle counters
# =========================================================================

@test "totals.fix_loop_events counts REVIEW_FIX_DISPATCH actions" {
    _setup_flight_recorder
    _append_event "REVIEW_FIX_DISPATCH" "review-fix-loop" "REVIEW_FIX_DISPATCH" "0" "0"
    _append_event "REVIEW_FIX_DISPATCH" "review-fix-loop" "REVIEW_FIX_DISPATCH" "0" "0"
    _append_event "IMPL" "claude" "invoke" "1" "100"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'REVIEW' '$TEST_DIR'
    "
    run jq -r '.totals.fix_loop_events' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "2" ]
}

@test "totals.bb_fix_cycles counts BB_FIX_CYCLE_* phases" {
    _setup_flight_recorder
    _append_event "BB_FIX_CYCLE_START" "bb" "fix_cycle_start" "0" "0"
    _append_event "BB_FIX_CYCLE_COMPLETE" "bb" "fix_cycle" "0" "0"
    _append_event "REVIEW" "claude" "invoke" "0" "0"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'x' '$TEST_DIR'
    "
    run jq -r '.totals.bb_fix_cycles' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "2" ]
}

# =========================================================================
# SPD-T6: append-only journal + pointer pattern
# =========================================================================

@test "multiple snapshots append to dashboard.jsonl" {
    _setup_flight_recorder
    _append_event "A" "x" "y" "1" "100"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'A' '$TEST_DIR'
        _emit_dashboard_snapshot 'B' '$TEST_DIR'
        _emit_dashboard_snapshot 'C' '$TEST_DIR'
    "
    run bash -c "wc -l < '$TEST_DIR/dashboard.jsonl' | tr -d ' '"
    [ "$output" = "3" ]
}

@test "dashboard-latest.json is overwritten (not appended)" {
    _setup_flight_recorder
    _append_event "A" "x" "y" "1" "100"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'A' '$TEST_DIR'
        _emit_dashboard_snapshot 'B' '$TEST_DIR'
    "
    # dashboard-latest.json should contain one JSON doc, not two concatenated
    run jq -r '.current_phase' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "B" ]
}

# =========================================================================
# SPD-T7: fail-safe — swallows errors, doesn't break pipeline
# =========================================================================

@test "emit is a no-op when flight recorder unset" {
    run bash -c "
        source '$EVIDENCE_SH'
        unset _FLIGHT_RECORDER
        _emit_dashboard_snapshot 'x' '$TEST_DIR'
    "
    # Should return 0 (no-op) without creating dashboard files
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_DIR/dashboard.jsonl" ]
    [ ! -f "$TEST_DIR/dashboard-latest.json" ]
}

@test "emit is a no-op when cycle_dir does not exist" {
    _setup_flight_recorder
    _append_event "A" "x" "y" "1" "100"
    run bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'x' '/nonexistent/cycle/path'
    "
    [ "$status" -eq 0 ]
}

@test "emit handles empty flight-recorder gracefully" {
    _setup_flight_recorder
    # No events appended — empty file

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        _emit_dashboard_snapshot 'x' '$TEST_DIR'
    "
    # Should still produce a valid snapshot with 0 actions
    run jq -r '.totals.actions' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "0" ]
}

@test "non-numeric SPIRAL_TOTAL_BUDGET defaults to 0 (no budget)" {
    _setup_flight_recorder
    _append_event "A" "x" "y" "1" "100"

    bash -c "
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$_FLIGHT_RECORDER'
        export _FLIGHT_RECORDER_SEQ=$_FLIGHT_RECORDER_SEQ
        export SPIRAL_TOTAL_BUDGET='not-a-number'
        _emit_dashboard_snapshot 'x' '$TEST_DIR'
    "
    run jq -r '.totals.budget_cap_usd' "$TEST_DIR/dashboard-latest.json"
    [ "$output" = "null" ]
}

# =========================================================================
# SPD-T8: cmd_status integration
# =========================================================================

@test "cmd_status --json merges dashboard into state output" {
    # Build a fake spiral state + dashboard combo
    local run_dir="$TEST_DIR/run-state"
    local cycle_dir="$TEST_DIR/cycles/cycle-001"
    mkdir -p "$run_dir" "$cycle_dir"

    # Fake state
    local state_file="$run_dir/state.json"
    jq -n --arg cycle "$cycle_dir" '{
        spiral_id: "spiral-test",
        state: "RUNNING",
        phase: "IMPLEMENT",
        cycle_index: 1,
        max_cycles: 3,
        cycle_dir: $cycle
    }' > "$state_file"

    # Fake dashboard
    jq -n '{
        schema: "spiral.dashboard.v1",
        ts: "2026-04-19T02:00:00Z",
        current_phase: "IMPLEMENT",
        totals: {actions: 10, cost_usd: 1.5, failures: 0},
        per_phase: []
    }' > "$cycle_dir/dashboard-latest.json"

    # Source orchestrator (main guard prevents auto-execution). Override the
    # STATE_FILE variable AFTER source so cmd_status sees the test fixture.
    run bash -c "
        source '$ORCH_SH' >/dev/null 2>&1
        STATE_FILE='$state_file'
        cmd_status --json 2>/dev/null
    "

    # Output should contain both state + dashboard
    [[ "$output" == *'"spiral_id"'* ]] || { echo "Missing spiral_id in: $output"; false; }
    [[ "$output" == *'"dashboard"'* ]] || { echo "Missing dashboard in: $output"; false; }
    [[ "$output" == *'"spiral.dashboard.v1"'* ]] || { echo "Missing schema in: $output"; false; }
}
