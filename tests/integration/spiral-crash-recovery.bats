#!/usr/bin/env bats
# =============================================================================
# spiral-crash-recovery.bats — FR-9.5 crash recovery tests (cycle-067)
# =============================================================================
# Test A: Crash handler produces diagnostic + CRASHED state (deterministic)
# Test B: Orphan recovery — resume detects stale RUNNING via PID check
# =============================================================================

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    mkdir -p "$PROJECT_ROOT/.claude/scripts" \
             "$PROJECT_ROOT/.run" \
             "$PROJECT_ROOT/grimoires/loa/a2a/trajectory" \
             "$PROJECT_ROOT/cycles"
    cd "$PROJECT_ROOT"

    REAL_ROOT="$BATS_TEST_DIRNAME/../.."
    cp "$REAL_ROOT/.claude/scripts/spiral-orchestrator.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/spiral-harvest-adapter.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/bootstrap.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/path-lib.sh" "$PROJECT_ROOT/.claude/scripts/" 2>/dev/null || true
    cat > "$PROJECT_ROOT/.claude/scripts/cycle-workspace.sh" <<'STUB'
#!/usr/bin/env bash
mkdir -p "${PROJECT_ROOT}/cycles/${2:-}"
STUB
    chmod +x "$PROJECT_ROOT/.claude/scripts/cycle-workspace.sh"

    cat > "$PROJECT_ROOT/.loa.config.yaml" <<'YAML'
spiral:
  enabled: true
  default_max_cycles: 3
  seed:
    mode: degraded
  flatline:
    min_new_findings_per_cycle: 3
    consecutive_low_cycles: 2
YAML

    git init -q -b main
    git config user.email test@test
    git config user.name test

    SCRIPT="$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"
}

teardown() {
    cd /
    rm -rf "$PROJECT_ROOT"
}

# =============================================================================
# Test A: Crash handler writes diagnostic + CRASHED state (deterministic)
# =============================================================================
@test "crash-recovery-A: crash handler writes diagnostic and sets CRASHED" {
    # Source script to access functions directly
    source "$PROJECT_ROOT/.claude/scripts/bootstrap.sh"
    source "$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    # Init state via CLI
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Verify state is RUNNING
    [ "$(jq -r '.state' "$STATE_FILE")" = "RUNNING" ]

    # Set phase to simulate mid-cycle
    update_phase "HARVEST"

    # Call crash handler directly with non-zero exit code
    spiral_crash_handler 143  # SIGTERM exit code

    # Crash diagnostic should exist
    local crash_files
    crash_files=$(ls "$PROJECT_ROOT/.run"/spiral-crash-*.json 2>/dev/null | head -1)
    [ -n "$crash_files" ]

    # Diagnostic should contain exit_code and last_phase
    jq -e '.exit_code == 143' "$crash_files" >/dev/null
    jq -e '.last_phase == "HARVEST"' "$crash_files" >/dev/null

    # State should be CRASHED
    [ "$(jq -r '.state' "$STATE_FILE")" = "CRASHED" ]
}

# =============================================================================
# Test: Crash handler skips on normal exit (exit 0)
# =============================================================================
@test "crash-recovery: handler skips on exit 0 (normal exit)" {
    source "$PROJECT_ROOT/.claude/scripts/bootstrap.sh"
    source "$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Call handler with exit 0
    spiral_crash_handler 0

    # State should still be RUNNING (not CRASHED)
    [ "$(jq -r '.state' "$STATE_FILE")" = "RUNNING" ]

    # No crash diagnostic
    local crash_count
    crash_count=$(find "$PROJECT_ROOT/.run" -name "spiral-crash-*.json" 2>/dev/null | wc -l)
    [ "$crash_count" -eq 0 ]
}

# =============================================================================
# Test: Crash handler skips if jq in flight
# =============================================================================
@test "crash-recovery: handler skips state update when jq in flight" {
    source "$PROJECT_ROOT/.claude/scripts/bootstrap.sh"
    source "$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Simulate jq in flight
    _SPIRAL_JQ_IN_FLIGHT=1

    spiral_crash_handler 143

    _SPIRAL_JQ_IN_FLIGHT=0

    # State should still be RUNNING (handler skipped state update)
    [ "$(jq -r '.state' "$STATE_FILE")" = "RUNNING" ]

    # Crash diagnostic should still be written (printf, not jq)
    local crash_files
    crash_files=$(ls "$PROJECT_ROOT/.run"/spiral-crash-*.json 2>/dev/null | head -1)
    [ -n "$crash_files" ]
}

# =============================================================================
# Test B: Orphan recovery — stale RUNNING → resume detects dead PID
# =============================================================================
@test "crash-recovery-B: stale RUNNING detected by resume, completes spiral" {
    # Init state
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Inject dead PID (simulate SIGKILL — handler never fired)
    local tmp="${STATE_FILE}.tmp"
    jq '.pid = 999999 | .start_time = "2026-01-01T00:00:00Z"' "$STATE_FILE" > "$tmp"
    mv "$tmp" "$STATE_FILE"

    # State is RUNNING with dead PID
    [ "$(jq -r '.state' "$STATE_FILE")" = "RUNNING" ]

    # Resume should detect orphan, coalesce to CRASHED, then run loop
    "$SCRIPT" --resume >/dev/null 2>&1

    # After resume: state should be COMPLETED
    [ "$(jq -r '.state' "$STATE_FILE")" = "COMPLETED" ]
    [ "$(jq -r '.stopping_condition' "$STATE_FILE")" = "cycle_budget_exhausted" ]

    # Check trajectory shows resume event
    local trajectory_file
    trajectory_file=$(ls "$PROJECT_ROOT/grimoires/loa/a2a/trajectory"/spiral-*.jsonl 2>/dev/null | head -1)
    [ -n "$trajectory_file" ]
    grep -q "spiral_resumed" "$trajectory_file"
}

# =============================================================================
# Test: Resume from CRASHED state works
# =============================================================================
@test "crash-recovery: resume from CRASHED runs to completion" {
    "$SCRIPT" --start --init-only >/dev/null 2>&1

    # Manually coalesce to CRASHED
    source "$PROJECT_ROOT/.claude/scripts/bootstrap.sh"
    source "$PROJECT_ROOT/.claude/scripts/spiral-orchestrator.sh"
    export STATE_FILE="$PROJECT_ROOT/.run/spiral-state.json"

    coalesce_spiral_terminal_state "CRASHED" "test_crash"

    [ "$(jq -r '.state' "$STATE_FILE")" = "CRASHED" ]

    # Resume should work from CRASHED
    "$SCRIPT" --resume >/dev/null 2>&1

    [ "$(jq -r '.state' "$STATE_FILE")" = "COMPLETED" ]
}
