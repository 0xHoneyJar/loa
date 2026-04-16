#!/usr/bin/env bats
# =============================================================================
# spiral-orchestrator.bats — cycle-066 MVP tests
# =============================================================================
# Verifies the /spiral meta-orchestrator scaffolding (v0.1.0):
#   - State machine init/status/halt/resume
#   - All 6 stopping-condition predicates
#   - Safety floors (hardcoded maxes cannot be overridden)
#   - HITL halt via sentinel file
#   - Trajectory logging
# =============================================================================

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    mkdir -p "$PROJECT_ROOT/.claude" "$PROJECT_ROOT/.run" \
             "$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
    cd "$PROJECT_ROOT"
    git init -q -b main
    git config user.email test@test
    git config user.name test

    # Enable spiral in config
    cat > "$PROJECT_ROOT/.loa.config.yaml" <<'EOF'
spiral:
  enabled: true
  default_max_cycles: 3
  flatline:
    min_new_findings_per_cycle: 3
    consecutive_low_cycles: 2
  budget_cents: 2000
  wall_clock_seconds: 28800
EOF

    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"
    export HALT_SENTINEL="$PROJECT_ROOT/.run/spiral-halt"
}

teardown() {
    cd /
    rm -rf "$PROJECT_ROOT"
}

# =============================================================================
# T1: --start with spiral.enabled=false exits 2
# =============================================================================
@test "start: refuses to start when spiral.enabled=false" {
    # Disable in config
    sed -i 's/enabled: true/enabled: false/' "$PROJECT_ROOT/.loa.config.yaml"

    set +e
    output=$("$SCRIPT" --start 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 2 ]
    [[ "$output" == *"disabled"* ]]
    [ ! -f "$STATE_FILE" ]
}

# =============================================================================
# T2: --start initializes state with all required fields
# =============================================================================
@test "start: initializes state with spiral_id, state=RUNNING, phase=SEED" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    [ -f "$STATE_FILE" ]
    [ "$(jq -r '.state' "$STATE_FILE")" = "RUNNING" ]
    [ "$(jq -r '.phase' "$STATE_FILE")" = "SEED" ]
    [ "$(jq -r '.cycle_index' "$STATE_FILE")" = "0" ]
    # spiral_id must be non-null
    local spiral_id
    spiral_id=$(jq -r '.spiral_id' "$STATE_FILE")
    [[ "$spiral_id" =~ ^spiral-[0-9]{8}-[a-f0-9]{6}$ ]]
}

# =============================================================================
# T3: --start respects config defaults
# =============================================================================
@test "start: picks up max_cycles from config" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    [ "$(jq -r '.max_cycles' "$STATE_FILE")" = "3" ]
}

# =============================================================================
# T4: safety floor clamps max_cycles
# =============================================================================
@test "start: safety floor clamps max_cycles to 50" {
    "$SCRIPT" --start --init-only --max-cycles 100 >/dev/null 2>&1

    [ "$(jq -r '.max_cycles' "$STATE_FILE")" = "50" ]
}

# =============================================================================
# T5: safety floor clamps budget_cents
# =============================================================================
@test "start: safety floor clamps budget_cents to 10000" {
    "$SCRIPT" --start --init-only --budget-cents 999999 >/dev/null 2>&1

    [ "$(jq -r '.budget.budget_cents' "$STATE_FILE")" = "10000" ]
}

# =============================================================================
# T6: safety floor clamps wall_clock_seconds
# =============================================================================
@test "start: safety floor clamps wall_clock_seconds to 86400" {
    "$SCRIPT" --start --init-only --wall-clock-seconds 1000000 >/dev/null 2>&1

    [ "$(jq -r '.budget.wall_clock_seconds' "$STATE_FILE")" = "86400" ]
}

# =============================================================================
# T7: --start refuses when spiral already RUNNING
# =============================================================================
@test "start: refuses when spiral already RUNNING (exit 3)" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    set +e
    output=$("$SCRIPT" --start 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 3 ]
    [[ "$output" == *"already RUNNING"* ]]
}

# =============================================================================
# T8: --start --dry-run validates config without creating state
# =============================================================================
@test "start: --dry-run returns computed config without creating state" {
    local output
    output=$("$SCRIPT" --start --dry-run 2>&1)

    [ ! -f "$STATE_FILE" ]
    echo "$output" | jq -e '.dry_run == true' >/dev/null
    echo "$output" | jq -e '.computed.max_cycles == 3' >/dev/null
    echo "$output" | jq -e '.safety_floors.max_cycles == 50' >/dev/null
}

# =============================================================================
# T9: --status with no state returns NO_SPIRAL
# =============================================================================
@test "status: returns NO_SPIRAL when no state file" {
    local output
    output=$("$SCRIPT" --status --json 2>&1)
    echo "$output" | jq -e '.state == "NO_SPIRAL"' >/dev/null
}

# =============================================================================
# T10: --status reports current cycle index and phase
# =============================================================================
@test "status: reports spiral_id, state, phase, cycle count" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    local output
    output=$("$SCRIPT" --status 2>&1)

    [[ "$output" == *"Spiral:"* ]]
    [[ "$output" == *"State:  RUNNING"* ]]
    [[ "$output" == *"Phase:  SEED"* ]]
    [[ "$output" == *"Cycle:  0 / 3"* ]]
}

# =============================================================================
# T11: --halt creates sentinel and coalesces state to HALTED
# =============================================================================
@test "halt: creates sentinel file and transitions state to HALTED" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1
    "$SCRIPT" --halt --reason "test_halt" >/dev/null 2>&1

    [ -f "$HALT_SENTINEL" ]
    [ "$(cat "$HALT_SENTINEL")" = "test_halt" ]
    [ "$(jq -r '.state' "$STATE_FILE")" = "HALTED" ]
    [ "$(jq -r '.stopping_condition' "$STATE_FILE")" = "test_halt" ]
    # completed_at must be populated (coalescer invariant)
    local completed_at
    completed_at=$(jq -r '.timestamps.completed_at' "$STATE_FILE")
    [[ "$completed_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# =============================================================================
# T12: --resume clears sentinel and transitions back to RUNNING
# =============================================================================
@test "resume: clears sentinel and runs to completion" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1
    "$SCRIPT" --halt >/dev/null 2>&1
    [ -f "$HALT_SENTINEL" ]

    "$SCRIPT" --resume >/dev/null 2>&1

    [ ! -f "$HALT_SENTINEL" ]
    # Resume now dispatches the cycle loop (cycle-067), so state is COMPLETED
    [ "$(jq -r '.state' "$STATE_FILE")" = "COMPLETED" ]
}

# =============================================================================
# T13: --resume refuses when spiral is RUNNING
# =============================================================================
@test "resume: refuses when spiral is already RUNNING (PID alive)" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1
    # Record current process PID to simulate live spiral
    local tmp="${STATE_FILE}.tmp"
    jq --argjson pid "$$" '.pid = $pid' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"

    set +e
    output=$("$SCRIPT" --resume 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 3 ]
    [[ "$output" == *"already RUNNING"* ]]
}

# =============================================================================
# T14: --check-stop with HITL halt sentinel returns stop=true
# =============================================================================
@test "check-stop: detects HITL halt via sentinel file" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1
    touch "$HALT_SENTINEL"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.stop == true' >/dev/null
    echo "$output" | jq -e '.condition == "hitl_halt"' >/dev/null
}

# =============================================================================
# T15: --check-stop detects cycle-budget exhausted
# =============================================================================
@test "check-stop: detects cycle budget exhausted" {
    "$SCRIPT" --start --init-only --max-cycles 3 >/dev/null 2>&1
    # Artificially advance cycle_index to max
    jq '.cycle_index = 3' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.stop == true' >/dev/null
    echo "$output" | jq -e '.condition == "cycle_budget_exhausted"' >/dev/null
}

# =============================================================================
# T16: --check-stop detects flatline convergence
# =============================================================================
@test "check-stop: detects flatline convergence after N low cycles" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1
    # Simulate 2 consecutive low-signal cycles
    jq '.flatline_counter = 2' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.stop == true' >/dev/null
    echo "$output" | jq -e '.condition == "flatline_convergence"' >/dev/null
}

# =============================================================================
# T17: --check-stop detects cost budget exhausted
# =============================================================================
@test "check-stop: detects cost budget exhausted" {
    "$SCRIPT" --start --init-only --budget-cents 500 >/dev/null 2>&1
    # Simulate cost accumulated past budget
    jq '.budget.cost_cents = 600' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.stop == true' >/dev/null
    echo "$output" | jq -e '.condition == "cost_budget_exhausted"' >/dev/null
}

# =============================================================================
# T18: --check-stop with no stopping condition returns stop=false
# =============================================================================
@test "check-stop: returns stop=false when no condition triggered" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.stop == false' >/dev/null
}

# =============================================================================
# T19: trajectory log records spiral events
# =============================================================================
@test "trajectory: --start logs spiral_started event" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    local log_dir="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
    local log_file
    log_file=$(find "$log_dir" -name 'spiral-*.jsonl' | head -1)

    [ -f "$log_file" ]
    grep -q '"event":"spiral_started"' "$log_file"
    grep -q '"spiral_id":"spiral-' "$log_file"
}

# =============================================================================
# T20: unknown command returns exit 1
# =============================================================================
@test "cli: unknown command exits 1 with usage" {
    set +e
    output=$("$SCRIPT" --unknown-flag 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 1 ]
    [[ "$output" == *"Unknown command"* ]]
}

# =============================================================================
# T21: help output documents all commands
# =============================================================================
@test "cli: help output lists all commands" {
    local output
    output=$("$SCRIPT" --help 2>&1)

    [[ "$output" == *"--start"* ]]
    [[ "$output" == *"--status"* ]]
    [[ "$output" == *"--halt"* ]]
    [[ "$output" == *"--resume"* ]]
    [[ "$output" == *"--check-stop"* ]]
}

# =============================================================================
# T22: HITL halt takes priority over other stopping conditions
# =============================================================================
@test "check-stop: HITL halt has priority over other stopping conditions" {
    "$SCRIPT" --start --init-only --max-cycles 1 >/dev/null 2>&1
    # Both cycle-budget and HITL triggered — HITL should win
    jq '.cycle_index = 1' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    touch "$HALT_SENTINEL"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.condition == "hitl_halt"' >/dev/null
}

# =============================================================================
# T23: Wall-clock exhaustion test — cycle-067 FR-3
# =============================================================================
@test "check-stop: wall-clock exhaustion triggers stop" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Manipulate timestamps.started to 60000s ago, budget to 30000s
    local past
    past=$(date -u -d "60000 seconds ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -v-60000S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

    local tmp="${STATE_FILE}.tmp"
    jq --arg ts "$past" --argjson budget 30000 '
        .timestamps.started = $ts |
        .budget.wall_clock_seconds = $budget
    ' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    echo "$output" | jq -e '.condition == "wall_clock_exhausted"' >/dev/null
}

# =============================================================================
# Quality Gate Truth Table Tests (T24-T31) — cycle-067 FR-2
# =============================================================================

# Helper: init state and inject a cycle record with given verdicts
_init_with_cycle() {
    local review_v="$1"
    local audit_v="$2"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Inject a cycle record with given verdicts
    # Need to handle null verdicts
    local review_json audit_json
    if [[ "$review_v" == "null" ]]; then
        review_json="null"
    else
        review_json="\"$review_v\""
    fi
    if [[ "$audit_v" == "null" ]]; then
        audit_json="null"
    else
        audit_json="\"$audit_v\""
    fi

    local tmp="${STATE_FILE}.tmp"
    jq --argjson rv "$review_json" --argjson av "$audit_json" '
        .cycles = [{
            "cycle_id": "cycle-test",
            "index": 1,
            "review_verdict": $rv,
            "audit_verdict": $av,
            "findings_critical": 0,
            "findings_minor": 0
        }] |
        .cycle_index = 1
    ' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"
}

# T24: both fail → stop
@test "quality_gate: REQUEST_CHANGES + CHANGES_REQUIRED → quality_gate_failure" {
    _init_with_cycle "REQUEST_CHANGES" "CHANGES_REQUIRED"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    echo "$output" | jq -e '.condition == "quality_gate_failure"' >/dev/null
}

# T25: review fail / audit approve → continue
@test "quality_gate: REQUEST_CHANGES + APPROVED → no stop (continues)" {
    _init_with_cycle "REQUEST_CHANGES" "APPROVED"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    # Should NOT trigger quality gate; next in chain is cycle_budget
    # With max_cycles=3 and cycle_index=1, should not hit cycle_budget either
    echo "$output" | jq -e '.condition != "quality_gate_failure"' >/dev/null
}

# T26: audit fail / review approve → continue
@test "quality_gate: APPROVED + CHANGES_REQUIRED → no stop (continues)" {
    _init_with_cycle "APPROVED" "CHANGES_REQUIRED"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    echo "$output" | jq -e '.condition != "quality_gate_failure"' >/dev/null
}

# T27: both approve → continue
@test "quality_gate: APPROVED + APPROVED → no stop (continues)" {
    _init_with_cycle "APPROVED" "APPROVED"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    echo "$output" | jq -e '.condition != "quality_gate_failure"' >/dev/null
}

# T28: null review → stop
@test "quality_gate: null review → quality_gate_failure (fail-closed)" {
    _init_with_cycle "null" "APPROVED"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    echo "$output" | jq -e '.condition == "quality_gate_failure"' >/dev/null
}

# T29: null audit → stop
@test "quality_gate: APPROVED + null audit → quality_gate_failure (fail-closed)" {
    _init_with_cycle "APPROVED" "null"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    echo "$output" | jq -e '.condition == "quality_gate_failure"' >/dev/null
}

# T30: unrecognized verdict → stop
@test "quality_gate: unrecognized review verdict → quality_gate_failure" {
    _init_with_cycle "BANANA" "APPROVED"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    echo "$output" | jq -e '.condition == "quality_gate_failure"' >/dev/null
}

# T31: no cycles yet → continue
@test "quality_gate: no cycles → no quality_gate_failure" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    local output
    output=$("$SCRIPT" --check-stop 2>&1)
    # No cycles, quality gate returns 1 (continue), so shouldn't fire
    echo "$output" | jq -e '.condition != "quality_gate_failure"' >/dev/null
}

# =============================================================================
# Cycle-067 Helper Tests (T34, T37, T39, T40)
# =============================================================================

# Helper: source orchestrator functions for direct testing
_source_orchestrator() {
    # Source the script to get access to functions
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh" --source-only 2>/dev/null || true
    # Re-export state file location
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"
}

# T35: seed_phase full mode → degrades to degraded with warning
@test "seed_phase: full mode without Vision Registry degrades to degraded" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Set seed.mode to full
    cat > "$PROJECT_ROOT/.loa.config.yaml" <<'EOF'
spiral:
  enabled: true
  seed:
    mode: full
EOF

    # Create a previous cycle dir with valid sidecar
    local prev_dir="$PROJECT_ROOT/cycles/cycle-prev"
    local cur_dir="$PROJECT_ROOT/cycles/cycle-cur"
    mkdir -p "$prev_dir" "$cur_dir"
    echo '{"$schema_version":1,"cycle_id":"cycle-prev","review_verdict":"APPROVED","audit_verdict":"APPROVED","findings":{"blocker":0,"high":1,"medium":0,"low":0},"flatline_signature":null,"content_hash":null,"elapsed_sec":1,"exit_status":"success"}' > "$prev_dir/cycle-outcome.json"

    # Call seed_phase — should degrade to degraded + produce seed-context.md
    local stderr_output
    stderr_output=$(seed_phase "$cur_dir" "cycle-cur" "$prev_dir" 2>&1 >/dev/null)

    # Should log WARNING about degrading
    [[ "$stderr_output" == *"WARNING"* ]] || [[ "$stderr_output" == *"seed.mode=full"* ]]

    # Should still write seed-context.md (degraded behavior)
    [ -f "$cur_dir/seed-context.md" ]

    # Trajectory should have seed_mode_transition event
    local trajectory_file
    trajectory_file=$(ls "$PROJECT_ROOT/grimoires/loa/a2a/trajectory"/spiral-*.jsonl 2>/dev/null | head -1)
    [ -n "$trajectory_file" ]
    grep -q "seed_mode_transition" "$trajectory_file"
}

# T41: SPIRAL_STUB_FINDINGS malformed input defaults to 3
@test "simstim_phase: malformed SPIRAL_STUB_FINDINGS defaults to 3" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    local cycle_dir="$PROJECT_ROOT/cycles/cycle-stubtest"
    mkdir -p "$cycle_dir"

    # Set malformed env var
    export SPIRAL_STUB_FINDINGS="not_a_number"
    simstim_phase "$cycle_dir" "cycle-stubtest" 2>/dev/null

    # Check sidecar was written with default findings (high=3)
    [ -f "$cycle_dir/cycle-outcome.json" ]
    local high_count
    high_count=$(jq -r '.findings.high' "$cycle_dir/cycle-outcome.json")
    [ "$high_count" -eq 3 ]

    unset SPIRAL_STUB_FINDINGS
}

# T42: write_checkpoint rejects non-monotonic transition
@test "write_checkpoint: rejects backward transition HARVEST → SEED" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Create a cycle record with checkpoint at HARVEST
    local tmp="${STATE_FILE}.tmp"
    jq '.cycles = [{"cycle_id": "cycle-mono", "checkpoint": "HARVEST"}]' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"

    # Attempt backward transition: HARVEST → SEED
    set +e
    local error_output
    error_output=$(write_checkpoint "cycle-mono" "SEED" 2>&1)
    local exit_code=$?
    set -e

    [ "$exit_code" -eq 1 ]
    [[ "$error_output" == *"Non-monotonic"* ]]
}

# T34: with_step_timeout — command exceeds budget → returns 124
@test "with_step_timeout: command exceeding budget returns 124" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    # Initialize state for trajectory logging
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    require_timeout
    if [[ -z "$_TIMEOUT_CMD" ]]; then
        skip "timeout/gtimeout not available"
    fi

    set +e
    with_step_timeout "test_step" 1 sleep 10
    local exit_code=$?
    set -e

    [ "$exit_code" -eq 124 ]
}

# T37: PID guard detects stale RUNNING
@test "pid_guard: detects stale RUNNING and coalesces to CRASHED" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Inject a dead PID
    local tmp="${STATE_FILE}.tmp"
    jq '.pid = 999999 | .start_time = "2026-01-01T00:00:00Z"' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"

    # Verify state is RUNNING
    local state
    state=$(jq -r '.state' "$STATE_FILE")
    [ "$state" = "RUNNING" ]

    # Source and run PID guard
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    set +e
    check_pid_guard 2>/dev/null
    local exit_code=$?
    set -e

    [ "$exit_code" -eq 0 ]
    # State should now be CRASHED
    state=$(jq -r '.state' "$STATE_FILE")
    [ "$state" = "CRASHED" ]
}

# T39: atomic_state_write handles jq failure
@test "atomic_state_write: returns 1 on jq error and cleans up tmp" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    set +e
    # Pass invalid jq expression
    atomic_state_write 'INVALID_JQ_THAT_WILL_FAIL' 2>/dev/null
    local exit_code=$?
    set -e

    [ "$exit_code" -eq 1 ]
    # .tmp should not exist
    [ ! -f "${STATE_FILE}.tmp" ]
    # Original state should be intact
    jq -e '.state == "RUNNING"' "$STATE_FILE" >/dev/null
}

# T40: Backward compat — cycle-066 state (no .pid, no .checkpoint) reads without error
@test "backward_compat: cycle-066 state without .pid or .checkpoint reads cleanly" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # State from cycle-066 won't have .pid or .start_time
    local tmp="${STATE_FILE}.tmp"
    jq 'del(.pid) | del(.start_time)' "$STATE_FILE" > "$tmp" 2>/dev/null
    mv "$tmp" "$STATE_FILE"

    # Verify fields are absent
    local pid_val
    pid_val=$(jq -r '.pid // "missing"' "$STATE_FILE")
    [ "$pid_val" = "missing" ]

    # Status should still work
    local output
    output=$("$SCRIPT" --status --json 2>&1)
    echo "$output" | jq -e '.state == "RUNNING"' >/dev/null
}

# =============================================================================
# Cycle-068: Dispatch Mode Tests (T43-T48)
# =============================================================================

# T43: SPIRAL_USE_STUB=1 → STUB
@test "dispatch_mode: SPIRAL_USE_STUB=1 → STUB" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"

    export SPIRAL_USE_STUB=1
    export SPIRAL_REAL_DISPATCH=0
    local mode
    mode=$(_resolve_dispatch_mode 2>/dev/null)
    [ "$mode" = "STUB" ]
    unset SPIRAL_USE_STUB SPIRAL_REAL_DISPATCH
}

# T44: SPIRAL_REAL_DISPATCH=1 → REAL
@test "dispatch_mode: SPIRAL_REAL_DISPATCH=1 → REAL" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"

    export SPIRAL_USE_STUB=0
    export SPIRAL_REAL_DISPATCH=1
    local mode
    mode=$(_resolve_dispatch_mode 2>/dev/null)
    [ "$mode" = "REAL" ]
    unset SPIRAL_USE_STUB SPIRAL_REAL_DISPATCH
}

# T45: Both set → STUB wins
@test "dispatch_mode: USE_STUB=1 + REAL_DISPATCH=1 → STUB wins" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"

    export SPIRAL_USE_STUB=1
    export SPIRAL_REAL_DISPATCH=1
    local mode
    mode=$(_resolve_dispatch_mode 2>/dev/null)
    [ "$mode" = "STUB" ]
    unset SPIRAL_USE_STUB SPIRAL_REAL_DISPATCH
}

# T46: Neither set → STUB default
@test "dispatch_mode: neither set → STUB default" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"

    unset SPIRAL_USE_STUB SPIRAL_REAL_DISPATCH
    export CI=1  # suppress WARNING log
    local mode
    mode=$(_resolve_dispatch_mode 2>/dev/null)
    [ "$mode" = "STUB" ]
    unset CI
}

# T47: _simstim_real with missing dispatch script → exit 127
@test "simstim_real: missing dispatch script → exit 127" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Override SCRIPT_DIR to point to nonexistent dir
    SCRIPT_DIR="/tmp/nonexistent-$RANDOM"

    local cycle_dir="$PROJECT_ROOT/cycles/cycle-test-dispatch"
    mkdir -p "$cycle_dir"

    set +e
    _simstim_real "$cycle_dir" "cycle-test-dispatch" 2>/dev/null
    local exit_code=$?
    set -e

    [ "$exit_code" -eq 127 ]
}

# T48: _simstim_real cleans stale artifacts before dispatch
@test "simstim_real: cleans stale artifacts before dispatch" {
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/bootstrap.sh"
    source "$BATS_TEST_DIRNAME/../../.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    local cycle_dir="$PROJECT_ROOT/cycles/cycle-test-clean"
    mkdir -p "$cycle_dir"

    # Create stale artifacts
    echo "stale" > "$cycle_dir/reviewer.md"
    echo "stale" > "$cycle_dir/auditor-sprint-feedback.md"
    echo "stale" > "$cycle_dir/cycle-outcome.json"

    # SCRIPT_DIR doesn't have dispatch script → will fail at 127
    # but cleanup should happen BEFORE the script check
    SCRIPT_DIR="/tmp/nonexistent-$RANDOM"

    set +e
    _simstim_real "$cycle_dir" "cycle-test-clean" 2>/dev/null
    set -e

    # Stale artifacts should be cleaned even though dispatch failed
    [ ! -f "$cycle_dir/reviewer.md" ]
    [ ! -f "$cycle_dir/auditor-sprint-feedback.md" ]
    [ ! -f "$cycle_dir/cycle-outcome.json" ]
}

# =============================================================================
# T-MC1: stub-mode completes all max_cycles without early termination (Issue #514)
# =============================================================================
@test "multi-cycle: stub-mode completes all 3 cycles without early termination" {
    # Ensure cycle-workspace.sh is findable via SCRIPT_DIR
    # The orchestrator sources bootstrap.sh which needs PROJECT_ROOT set

    export SPIRAL_USE_STUB=1

    set +e
    output=$("$SCRIPT" --start --max-cycles 3 2>&1)
    exit_code=$?
    set -e

    [ "$exit_code" -eq 0 ]
    [ -f "$STATE_FILE" ]
    [ "$(jq -r '.state' "$STATE_FILE")" = "COMPLETED" ]
    [ "$(jq -r '.stopping_condition' "$STATE_FILE")" = "cycle_budget_exhausted" ]

    # Verify all 3 cycles were recorded
    local cycle_count
    cycle_count=$(jq '.cycles | length' "$STATE_FILE")
    [ "$cycle_count" -eq 3 ]

    unset SPIRAL_USE_STUB
}

# =============================================================================
# T-MC2: stopping_condition is a valid enum member (Issue #514)
# =============================================================================
@test "multi-cycle: stopping_condition is a valid enum member, not JSON fragment" {
    export SPIRAL_USE_STUB=1

    "$SCRIPT" --start --max-cycles 2 >/dev/null 2>&1

    local condition
    condition=$(jq -r '.stopping_condition' "$STATE_FILE")

    # Must be a simple lowercase+underscore identifier, not JSON
    [[ "$condition" =~ ^[a-z_]+$ ]]

    # Must not contain braces (the exact bug from #514)
    [[ "$condition" != *"{"* ]]
    [[ "$condition" != *"}"* ]]

    # Must be one of the documented enum values
    local valid_conditions="cycle_budget_exhausted flatline_convergence cost_budget_exhausted wall_clock_exhausted hitl_halt quality_gate_failure token_window_exhausted"
    local found=false
    for valid in $valid_conditions; do
        if [[ "$condition" == "$valid" ]]; then
            found=true
            break
        fi
    done
    [ "$found" = "true" ]

    unset SPIRAL_USE_STUB
}

# =============================================================================
# T-MC3: trajectory contains cycle_completed events for all cycles
# =============================================================================
@test "multi-cycle: trajectory logs cycle_completed for each cycle" {
    export SPIRAL_USE_STUB=1

    "$SCRIPT" --start --max-cycles 2 >/dev/null 2>&1

    # Find trajectory file
    local log_dir="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
    local log_file
    log_file=$(find "$log_dir" -name 'spiral-*.jsonl' | head -1)
    [ -n "$log_file" ]

    # Check for cycle_completed events (should have 2)
    local completed_count
    completed_count=$(grep -c '"cycle_completed"' "$log_file" || echo 0)
    [ "$completed_count" -eq 2 ]

    unset SPIRAL_USE_STUB
}
