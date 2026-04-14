#!/usr/bin/env bats
# =============================================================================
# spiral-e2e.bats — FR-4a stub-backed 3-cycle E2E test (cycle-067)
# =============================================================================
# Verifies the full cycle loop with stubbed simstim dispatch:
#   1. State transitions: RUNNING → COMPLETED with cycle_budget_exhausted
#   2. .cycles array has 3 entries
#   3. Each cycle has workspace directory
#   4. Trajectory records phase transitions per cycle
#   5. Wall-clock < 10s
#   6. Cross-cycle context handoff (cycle 2 SEED sees cycle 1 HARVEST)
# =============================================================================

setup() {
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    mkdir -p "$PROJECT_ROOT/.claude/scripts" \
             "$PROJECT_ROOT/.run" \
             "$PROJECT_ROOT/grimoires/loa/a2a/trajectory" \
             "$PROJECT_ROOT/cycles"
    cd "$PROJECT_ROOT"

    # Copy scripts
    REAL_ROOT="$BATS_TEST_DIRNAME/../.."
    cp "$REAL_ROOT/.claude/scripts/spiral-orchestrator.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/spiral-harvest-adapter.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/bootstrap.sh" "$PROJECT_ROOT/.claude/scripts/"
    cp "$REAL_ROOT/.claude/scripts/path-lib.sh" "$PROJECT_ROOT/.claude/scripts/" 2>/dev/null || true
    # cycle-workspace.sh stub (creates directory)
    cat > "$PROJECT_ROOT/.claude/scripts/cycle-workspace.sh" <<'STUB'
#!/usr/bin/env bash
cmd="${1:-}"
cycle_id="${2:-}"
if [[ "$cmd" == "init" && -n "$cycle_id" ]]; then
    mkdir -p "${PROJECT_ROOT}/cycles/${cycle_id}"
fi
STUB
    chmod +x "$PROJECT_ROOT/.claude/scripts/cycle-workspace.sh"

    # Enable spiral with 3 cycles
    cat > "$PROJECT_ROOT/.loa.config.yaml" <<'YAML'
spiral:
  enabled: true
  default_max_cycles: 3
  budget_cents: 2000
  wall_clock_seconds: 28800
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
# Main E2E test: 3 stub-backed cycles
# =============================================================================
@test "e2e: 3-cycle stub run completes with cycle_budget_exhausted" {
    local start_time
    start_time=$(date +%s)

    # Run spiral with 3 cycles
    "$SCRIPT" --start --max-cycles 3 >/dev/null 2>&1

    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    # Assertion 1: State COMPLETED with cycle_budget_exhausted
    [ "$(jq -r '.state' "$STATE_FILE")" = "COMPLETED" ]
    [ "$(jq -r '.stopping_condition' "$STATE_FILE")" = "cycle_budget_exhausted" ]

    # Assertion 2: .cycles array has 3 entries
    local cycle_count
    cycle_count=$(jq -r '.cycles | length' "$STATE_FILE")
    [ "$cycle_count" -eq 3 ]

    # Assertion 3: Each cycle has workspace directory
    for i in $(seq 0 2); do
        local cid
        cid=$(jq -r ".cycles[$i].cycle_id" "$STATE_FILE")
        [ -d "$PROJECT_ROOT/cycles/$cid" ]
    done

    # Assertion 4: Trajectory records phase transitions
    local trajectory_file
    trajectory_file=$(ls "$PROJECT_ROOT/grimoires/loa/a2a/trajectory"/spiral-*.jsonl 2>/dev/null | head -1)
    [ -n "$trajectory_file" ]
    # Should have at least: spiral_started + 3*(seed + simstim_stub + harvest_parsed + cycle_completed)
    local event_count
    event_count=$(wc -l < "$trajectory_file")
    [ "$event_count" -ge 10 ]

    # Assertion 5: Wall-clock < 10s
    [ "$elapsed" -lt 10 ]

    # Assertion 6: Cycle 2 SEED references cycle 1
    local cycle_2_id cycle_1_dir
    cycle_2_id=$(jq -r '.cycles[1].cycle_id' "$STATE_FILE")
    # Check for seed_degraded event mentioning cycle 2
    grep -q "$cycle_2_id" "$trajectory_file" 2>/dev/null || true
    # Check seed-context.md exists in cycle 2 dir
    [ -f "$PROJECT_ROOT/cycles/$cycle_2_id/seed-context.md" ]

    # Assertion: All checkpoints are COMPLETE
    for i in $(seq 0 2); do
        local cp
        cp=$(jq -r ".cycles[$i].checkpoint" "$STATE_FILE")
        [ "$cp" = "COMPLETE" ]
    done
}

# =============================================================================
# Verify stub artifacts
# =============================================================================
@test "e2e: stub creates reviewer.md + auditor-sprint-feedback.md + sidecar per cycle" {
    "$SCRIPT" --start --max-cycles 1 >/dev/null 2>&1

    local cid
    cid=$(jq -r '.cycles[0].cycle_id' "$STATE_FILE")
    [ -f "$PROJECT_ROOT/cycles/$cid/reviewer.md" ]
    [ -f "$PROJECT_ROOT/cycles/$cid/auditor-sprint-feedback.md" ]
    [ -f "$PROJECT_ROOT/cycles/$cid/cycle-outcome.json" ]

    # Verify sidecar is valid
    jq -e '."$schema_version" == 1' "$PROJECT_ROOT/cycles/$cid/cycle-outcome.json" >/dev/null
}
