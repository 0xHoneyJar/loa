#!/usr/bin/env bats
# =============================================================================
# spiral-seed-ingestion.bats — tests for #575 item 2 (flight-recorder → SEED)
# =============================================================================
# Validates:
# - _find_prior_cycle locates the lexicographically previous cycle dir
# - _summarize_prior_cycle_failures extracts load-bearing events
# - _build_seed_failure_prelude gates on config (default false) and emits
#   markdown block only when prior cycle has real failure events
# - Feature is OFF by default (safe rollout)
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export EVIDENCE_SH="$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/spiral-seed-test"
    mkdir -p "$TEST_DIR"
}

teardown() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# Helper: write a flight-recorder.jsonl at a given path with specific events.
_make_cycle() {
    local cycle_dir="$1"
    mkdir -p "$cycle_dir"
    touch "$cycle_dir/flight-recorder.jsonl"
}

_append_to_cycle() {
    local cycle_dir="$1"
    local phase="$2" actor="$3" action="$4" verdict="${5:-}"
    jq -n -c \
        --arg phase "$phase" \
        --arg actor "$actor" \
        --arg action "$action" \
        --arg verdict "$verdict" \
        '{seq: 0, ts: "2026-04-19T00:00:00Z", phase: $phase, actor: $actor, action: $action,
          input_checksum: null, output_checksum: null, output_path: null,
          output_bytes: 0, duration_ms: 0, cost_usd: 0,
          verdict: (if $verdict == "" then null else $verdict end)}' \
        >> "$cycle_dir/flight-recorder.jsonl"
}

# =========================================================================
# SSI-T1: _find_prior_cycle locates the predecessor
# =========================================================================

@test "_find_prior_cycle returns empty when no siblings exist" {
    local cycles_root="$TEST_DIR/cycles"
    local current="$cycles_root/cycle-002"
    _make_cycle "$current"

    run bash -c "
        source '$EVIDENCE_SH'
        _find_prior_cycle '$current'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "_find_prior_cycle picks lexicographically previous sibling" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    _make_cycle "$cycles_root/cycle-002"
    _make_cycle "$cycles_root/cycle-003"

    run bash -c "
        source '$EVIDENCE_SH'
        _find_prior_cycle '$cycles_root/cycle-003'
    "
    [[ "$output" == *"/cycle-002" ]]
}

@test "_find_prior_cycle skips dirs without flight-recorder" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    # cycle-002 has no flight recorder — should be skipped
    mkdir -p "$cycles_root/cycle-002"
    _make_cycle "$cycles_root/cycle-003"

    run bash -c "
        source '$EVIDENCE_SH'
        _find_prior_cycle '$cycles_root/cycle-003'
    "
    [[ "$output" == *"/cycle-001" ]]
}

@test "_find_prior_cycle returns empty when current cycle is first" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"

    run bash -c "
        source '$EVIDENCE_SH'
        _find_prior_cycle '$cycles_root/cycle-001'
    "
    [ -z "$output" ]
}

# =========================================================================
# SSI-T2: _summarize_prior_cycle_failures extracts load-bearing events
# =========================================================================

@test "summary extracts CIRCUIT_BREAKER events" {
    local prior="$TEST_DIR/cycles/cycle-001"
    _make_cycle "$prior"
    _append_to_cycle "$prior" "CIRCUIT_BREAKER" "spiral-harness" "gate_trip" "FAIL:REVIEW:max_retries"
    _append_to_cycle "$prior" "DISCOVERY" "claude" "invoke" "OK"

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    [[ "$output" == *"CIRCUIT_BREAKER"* ]]
    [[ "$output" == *"max_retries"* ]]
}

@test "summary extracts BB_FINDING_STUCK events" {
    local prior="$TEST_DIR/cycles/cycle-001"
    _make_cycle "$prior"
    _append_to_cycle "$prior" "BB_FINDING_STUCK" "bb-fix-loop" "stuck_detected"

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    [[ "$output" == *"BB_FINDING_STUCK"* ]]
}

@test "summary extracts AUTO_ESCALATION events" {
    local prior="$TEST_DIR/cycles/cycle-001"
    _make_cycle "$prior"
    _append_to_cycle "$prior" "AUTO_ESCALATION" "spiral-harness" "profile_escalated" "profile_escalated"

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    [[ "$output" == *"AUTO_ESCALATION"* ]]
}

@test "summary extracts REVIEW_FIX_LOOP_EXHAUSTED events" {
    local prior="$TEST_DIR/cycles/cycle-001"
    _make_cycle "$prior"
    _append_to_cycle "$prior" "REVIEW_FIX_LOOP_EXHAUSTED" "review-fix-loop" "changes_required"

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    [[ "$output" == *"REVIEW_FIX_LOOP_EXHAUSTED"* ]]
}

@test "summary extracts BUDGET FAIL events" {
    local prior="$TEST_DIR/cycles/cycle-001"
    _make_cycle "$prior"
    _append_to_cycle "$prior" "BUDGET" "evidence-gate" "check" "FAIL:EXCEEDED:spent=15 max=12"

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    [[ "$output" == *"BUDGET"* ]]
    [[ "$output" == *"EXCEEDED"* ]]
}

@test "summary returns empty when cycle had no failures" {
    local prior="$TEST_DIR/cycles/cycle-001"
    _make_cycle "$prior"
    _append_to_cycle "$prior" "DISCOVERY" "claude" "invoke" "OK"
    _append_to_cycle "$prior" "ARCHITECTURE" "claude" "invoke" "OK"
    _append_to_cycle "$prior" "IMPLEMENT" "claude" "invoke" "OK"

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "summary returns empty when flight-recorder missing" {
    local prior="$TEST_DIR/cycles/cycle-001"
    mkdir -p "$prior"
    # No flight-recorder.jsonl

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "summary returns empty for missing prior cycle dir" {
    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures ''
    "
    [ -z "$output" ]

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '/nonexistent/path'
    "
    [ -z "$output" ]
}

@test "summary truncates at 2000 chars to avoid bloating prompts" {
    local prior="$TEST_DIR/cycles/cycle-001"
    _make_cycle "$prior"
    # Generate many failure events (50 × ~60 bytes each = 3000+ bytes)
    for i in $(seq 1 50); do
        _append_to_cycle "$prior" "CIRCUIT_BREAKER" "actor" "trip_$i" "FAIL:REASON_$i:detail_$i"
    done

    run bash -c "
        source '$EVIDENCE_SH'
        _summarize_prior_cycle_failures '$prior'
    "
    # Length of captured output should be <= 2000 chars
    [ "${#output}" -le 2000 ]
}

# =========================================================================
# SSI-T3: _build_seed_failure_prelude feature gate
# =========================================================================

@test "prelude is empty by default (feature off)" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    _append_to_cycle "$cycles_root/cycle-001" "CIRCUIT_BREAKER" "x" "y" "FAIL:z:w"
    _make_cycle "$cycles_root/cycle-002"

    run bash -c "
        source '$EVIDENCE_SH'
        # Explicit: feature flag NOT set
        unset SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER
        _build_seed_failure_prelude '$cycles_root/cycle-002'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "prelude emits when feature flag set + prior cycle has failures" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    _append_to_cycle "$cycles_root/cycle-001" "CIRCUIT_BREAKER" "x" "trip" "FAIL:REASON:detail"
    _make_cycle "$cycles_root/cycle-002"

    run bash -c "
        source '$EVIDENCE_SH'
        export SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=true
        _build_seed_failure_prelude '$cycles_root/cycle-002'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"Prior cycle observability"* ]]
    [[ "$output" == *"cycle-001"* ]]
    [[ "$output" == *"CIRCUIT_BREAKER"* ]]
}

@test "prelude is empty when feature on but prior cycle had no failures" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    _append_to_cycle "$cycles_root/cycle-001" "DISCOVERY" "x" "invoke" "OK"
    _make_cycle "$cycles_root/cycle-002"

    run bash -c "
        source '$EVIDENCE_SH'
        export SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=true
        _build_seed_failure_prelude '$cycles_root/cycle-002'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "prelude is empty when feature on but no prior cycle exists" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"

    run bash -c "
        source '$EVIDENCE_SH'
        export SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=true
        _build_seed_failure_prelude '$cycles_root/cycle-001'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "prelude wraps content with labeled delimiter block" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    _append_to_cycle "$cycles_root/cycle-001" "BUDGET" "x" "check" "FAIL:EXCEEDED:over"
    _make_cycle "$cycles_root/cycle-002"

    run bash -c "
        source '$EVIDENCE_SH'
        export SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=true
        _build_seed_failure_prelude '$cycles_root/cycle-002'
    "
    # Must include the ---...--- wrapper (so the model knows the boundary)
    run bash -c "
        source '$EVIDENCE_SH'
        export SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=true
        _build_seed_failure_prelude '$cycles_root/cycle-002'
    "
    local dashes
    dashes=$(echo "$output" | grep -c "^---$")
    [ "$dashes" -ge 2 ]
}

# =========================================================================
# SSI-T4: default-off invariant across configurations
# =========================================================================

@test "prelude is OFF when SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=false" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    _append_to_cycle "$cycles_root/cycle-001" "CIRCUIT_BREAKER" "x" "y" "FAIL:z:w"
    _make_cycle "$cycles_root/cycle-002"

    run bash -c "
        source '$EVIDENCE_SH'
        export SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=false
        _build_seed_failure_prelude '$cycles_root/cycle-002'
    "
    [ -z "$output" ]
}

@test "prelude is OFF when SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER is garbage" {
    local cycles_root="$TEST_DIR/cycles"
    _make_cycle "$cycles_root/cycle-001"
    _append_to_cycle "$cycles_root/cycle-001" "CIRCUIT_BREAKER" "x" "y" "FAIL:z:w"
    _make_cycle "$cycles_root/cycle-002"

    run bash -c "
        source '$EVIDENCE_SH'
        export SPIRAL_SEED_INCLUDE_FLIGHT_RECORDER=yes
        _build_seed_failure_prelude '$cycles_root/cycle-002'
    "
    # Only the literal string 'true' enables (strict comparison)
    [ -z "$output" ]
}
