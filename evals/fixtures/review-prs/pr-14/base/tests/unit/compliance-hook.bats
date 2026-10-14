#!/usr/bin/env bats
# =============================================================================
# compliance-hook.bats — Dual-mode compliance hook tests (FR-7)
# =============================================================================
# Tests the implement-gate.sh hook against various .run/ state scenarios.
# Part of cycle-049/050: Upstream Platform Alignment.
# Sprint-108 T4.6: Added CH-T8 through CH-T14.

setup() {
    export PROJECT_ROOT=$(mktemp -d)
    export RUN_DIR="$PROJECT_ROOT/.run"
    export HOOKS_DIR="$BATS_TEST_DIRNAME/../../.claude/hooks/compliance"
    mkdir -p "$PROJECT_ROOT/.run"
}

teardown() {
    rm -rf "$PROJECT_ROOT"
}

# Helper: write sprint-plan state
write_sprint_state() {
    local state="$1"
    local plan_id="${2:-plan-test-123}"
    local last_activity="${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    cat > "$PROJECT_ROOT/.run/sprint-plan-state.json" << EOF
{
  "plan_id": "$plan_id",
  "state": "$state",
  "timestamps": {
    "started": "2026-03-18T00:00:00Z",
    "last_activity": "$last_activity"
  }
}
EOF
}

# Helper: write platform-features.json
write_platform_features() {
    local available="${1:-false}"
    cat > "$PROJECT_ROOT/.run/platform-features.json" << EOF
{"active_skill_available":${available},"detected_at":"2026-03-20T00:00:00Z","schema_version":1}
EOF
}

# Helper: write simstim-state.json
write_simstim_state() {
    local phase="$1"
    cat > "$PROJECT_ROOT/.run/simstim-state.json" << EOF
{"phase":"${phase}"}
EOF
}

# Helper: write state.json (run state)
write_run_state() {
    local state="$1"
    cat > "$PROJECT_ROOT/.run/state.json" << EOF
{"state":"${state}"}
EOF
}

# =========================================================================
# T1: State file absent → ask (fail-ask for App Zone)
# =========================================================================

@test "App Zone write with no state files returns ask decision" {
    # No state files exist
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# T2: RUNNING + valid state → allow
# =========================================================================

@test "App Zone write with RUNNING state returns allow" {
    write_sprint_state "RUNNING"
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    # Should NOT contain ADVISORY (silent allow)
    ! echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# T3: JACKED_OUT → ask
# =========================================================================

@test "App Zone write with JACKED_OUT state returns ask" {
    write_sprint_state "JACKED_OUT"
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# T4: HALTED → ask
# =========================================================================

@test "App Zone write with HALTED state returns ask" {
    write_sprint_state "HALTED"
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# T5: Stale state (>24h) → ask (integrity check)
# =========================================================================

@test "App Zone write with stale RUNNING state returns ask" {
    write_sprint_state "RUNNING" "plan-test-123" "2026-03-16T00:00:00Z"
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# T6: Missing plan_id → ask (integrity check, Red Team ATK-005)
# =========================================================================

@test "App Zone write with missing plan_id returns ask" {
    cat > "$PROJECT_ROOT/.run/sprint-plan-state.json" << 'EOF'
{
  "state": "RUNNING",
  "timestamps": {
    "last_activity": "2026-03-18T00:00:00Z"
  }
}
EOF
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# T7: Non-App-Zone write → always allow (no check)
# =========================================================================

@test "Non-App-Zone write always allowed regardless of state" {
    # No state files, writing to grimoires (State Zone)
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"grimoires/loa/notes.md\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# CH-T8: Authoritative mode — active_skill "implement" allows App Zone write
# =========================================================================

@test "CH-T8: Authoritative mode allows App Zone write for implement skill" {
    write_platform_features true
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\",\"active_skill\":\"implement\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    # Should NOT contain ADVISORY or AUTHORITATIVE ask (silent allow)
    ! echo "$output" | grep -q "ADVISORY"
    ! echo "$output" | grep -q "AUTHORITATIVE"
}

# =========================================================================
# CH-T9: Authoritative mode — no active_skill field falls back to heuristic
# =========================================================================

@test "CH-T9: Authoritative mode falls back to heuristic when no active_skill" {
    write_platform_features true
    # No active_skill in input, no RUNNING state → should ask (heuristic fallback)
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# CH-T10: Mode pinning — .compliance-mode file reused when fresh
# =========================================================================

@test "CH-T10: Mode pinning reuses .compliance-mode when fresh" {
    # Write a pinned mode file (heuristic) — should be reused without checking features
    echo "heuristic" > "$PROJECT_ROOT/.run/.compliance-mode"
    # Write features saying authoritative is available (should be ignored due to pinning)
    write_platform_features true
    # With heuristic mode pinned and no RUNNING state, should ask
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\",\"active_skill\":\"implement\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    # In heuristic mode, active_skill is ignored — should fall through to heuristic check
    # No RUNNING state → ask
    echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# CH-T11: Path normalization — absolute path correctly classified
# =========================================================================

@test "CH-T11: Path normalization strips PROJECT_ROOT prefix for zone check" {
    write_sprint_state "RUNNING"
    # Use absolute path with PROJECT_ROOT prefix — should still detect App Zone correctly
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"'"$PROJECT_ROOT"'/src/file.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    # RUNNING state + App Zone → allow (no ADVISORY)
    ! echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# CH-T12: simstim-state.json with phase=implementation allows App Zone write
# =========================================================================

@test "CH-T12: simstim-state with implementation phase allows App Zone write" {
    write_simstim_state "implementation"
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# CH-T13: state.json with state=RUNNING allows App Zone write
# =========================================================================

@test "CH-T13: state.json RUNNING allows App Zone write" {
    write_run_state "RUNNING"
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "ADVISORY"
}

# =========================================================================
# CH-T14: Portable date conversion uses _date_to_epoch (fresh RUNNING state)
# =========================================================================

@test "CH-T14: Portable date conversion allows fresh RUNNING state" {
    # Write a RUNNING state with recent timestamp (should be fresh)
    write_sprint_state "RUNNING" "plan-test-456" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "ADVISORY"
}
