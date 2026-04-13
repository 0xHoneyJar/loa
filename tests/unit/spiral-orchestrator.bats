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
    "$SCRIPT" --start >/dev/null 2>&1

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
    "$SCRIPT" --start >/dev/null 2>&1

    [ "$(jq -r '.max_cycles' "$STATE_FILE")" = "3" ]
}

# =============================================================================
# T4: safety floor clamps max_cycles
# =============================================================================
@test "start: safety floor clamps max_cycles to 50" {
    "$SCRIPT" --start --max-cycles 100 >/dev/null 2>&1

    [ "$(jq -r '.max_cycles' "$STATE_FILE")" = "50" ]
}

# =============================================================================
# T5: safety floor clamps budget_cents
# =============================================================================
@test "start: safety floor clamps budget_cents to 10000" {
    "$SCRIPT" --start --budget-cents 999999 >/dev/null 2>&1

    [ "$(jq -r '.budget.budget_cents' "$STATE_FILE")" = "10000" ]
}

# =============================================================================
# T6: safety floor clamps wall_clock_seconds
# =============================================================================
@test "start: safety floor clamps wall_clock_seconds to 86400" {
    "$SCRIPT" --start --wall-clock-seconds 1000000 >/dev/null 2>&1

    [ "$(jq -r '.budget.wall_clock_seconds' "$STATE_FILE")" = "86400" ]
}

# =============================================================================
# T7: --start refuses when spiral already RUNNING
# =============================================================================
@test "start: refuses when spiral already RUNNING (exit 3)" {
    "$SCRIPT" --start >/dev/null 2>&1

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
    "$SCRIPT" --start >/dev/null 2>&1

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
    "$SCRIPT" --start >/dev/null 2>&1
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
@test "resume: clears sentinel and restores RUNNING state" {
    "$SCRIPT" --start >/dev/null 2>&1
    "$SCRIPT" --halt >/dev/null 2>&1
    [ -f "$HALT_SENTINEL" ]

    "$SCRIPT" --resume >/dev/null 2>&1

    [ ! -f "$HALT_SENTINEL" ]
    [ "$(jq -r '.state' "$STATE_FILE")" = "RUNNING" ]
    [ "$(jq -r '.stopping_condition' "$STATE_FILE")" = "null" ]
    [ "$(jq -r '.timestamps.completed_at' "$STATE_FILE")" = "null" ]
}

# =============================================================================
# T13: --resume refuses when spiral is RUNNING
# =============================================================================
@test "resume: refuses when spiral is already RUNNING" {
    "$SCRIPT" --start >/dev/null 2>&1

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
    "$SCRIPT" --start >/dev/null 2>&1
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
    "$SCRIPT" --start --max-cycles 3 >/dev/null 2>&1
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
    "$SCRIPT" --start >/dev/null 2>&1
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
    "$SCRIPT" --start --budget-cents 500 >/dev/null 2>&1
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
    "$SCRIPT" --start >/dev/null 2>&1

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.stop == false' >/dev/null
}

# =============================================================================
# T19: trajectory log records spiral events
# =============================================================================
@test "trajectory: --start logs spiral_started event" {
    "$SCRIPT" --start >/dev/null 2>&1

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
    "$SCRIPT" --start --max-cycles 1 >/dev/null 2>&1
    # Both cycle-budget and HITL triggered — HITL should win
    jq '.cycle_index = 1' "$STATE_FILE" > "$STATE_FILE.tmp"
    mv "$STATE_FILE.tmp" "$STATE_FILE"
    touch "$HALT_SENTINEL"

    local output
    output=$("$SCRIPT" --check-stop 2>&1)

    echo "$output" | jq -e '.condition == "hitl_halt"' >/dev/null
}
