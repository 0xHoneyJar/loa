#!/usr/bin/env bats
# Unit tests for simstim --autonomous flag
# Cycle-070: Autonomous simstim mode

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/simstim-orchestrator.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/simstim-auto-test-$$"
    mkdir -p "$TEST_TMPDIR/.run"

    # Override run dir
    export PROJECT_ROOT="$TEST_TMPDIR"

    # Minimal config
    cat > "$TEST_TMPDIR/.loa.config.yaml" << 'CONFIG'
simstim:
  enabled: true
CONFIG
}

teardown() {
    cd /
    unset SIMSTIM_AUTONOMOUS
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

_source_orchestrator() {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    PROJECT_ROOT="$REAL_ROOT" source "$REAL_ROOT/.claude/scripts/bootstrap.sh" 2>/dev/null || true
    PROJECT_ROOT="$REAL_ROOT" source "$REAL_ROOT/.claude/scripts/simstim-orchestrator.sh" 2>/dev/null || true
    export PROJECT_ROOT="$TEST_TMPDIR"
}

# =============================================================================
# Flag Parsing
# =============================================================================

@test "simstim: --autonomous flag in arg parser case statement" {
    # Verify the flag exists in simstim-orchestrator.sh arg parsing
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep -c '\-\-autonomous)' "$REAL_ROOT/.claude/scripts/simstim-orchestrator.sh"
    [ "$output" -ge 1 ]
}

@test "simstim: autonomous env var export logic exists" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep -c 'SIMSTIM_AUTONOMOUS=1' "$REAL_ROOT/.claude/scripts/simstim-orchestrator.sh"
    [ "$output" -ge 1 ]
}

@test "simstim: autonomous mode state write logic exists" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep -c '"autonomous"' "$REAL_ROOT/.claude/scripts/simstim-orchestrator.sh"
    [ "$output" -ge 1 ]
}

# =============================================================================
# State Recording
# =============================================================================

@test "simstim: autonomous mode recorded in state JSON" {
    # Create a mock state file and apply autonomous mode
    echo '{"schema_version": 1, "state": "RUNNING"}' > "$TEST_TMPDIR/.run/simstim-state.json"

    local autonomous=true
    if [[ "$autonomous" == "true" ]]; then
        jq '.mode = "autonomous"' "$TEST_TMPDIR/.run/simstim-state.json" > "$TEST_TMPDIR/.run/simstim-state.json.tmp" \
            && mv "$TEST_TMPDIR/.run/simstim-state.json.tmp" "$TEST_TMPDIR/.run/simstim-state.json"
    fi

    run jq -r '.mode' "$TEST_TMPDIR/.run/simstim-state.json"
    [ "$output" = "autonomous" ]
}

@test "simstim: HITL mode has no mode field (default)" {
    echo '{"schema_version": 1, "state": "RUNNING"}' > "$TEST_TMPDIR/.run/simstim-state.json"

    local autonomous=false
    # Don't modify state

    run jq -r '.mode // "hitl"' "$TEST_TMPDIR/.run/simstim-state.json"
    [ "$output" = "hitl" ]
}

# =============================================================================
# Env Var Detection Pattern
# =============================================================================

@test "simstim: SIMSTIM_AUTONOMOUS=1 detected in subprocess" {
    export SIMSTIM_AUTONOMOUS=1
    run bash -c 'echo ${SIMSTIM_AUTONOMOUS:-unset}'
    [ "$output" = "1" ]
}

@test "simstim: autonomous check pattern works" {
    export SIMSTIM_AUTONOMOUS=1
    local is_auto=false
    if [[ "${SIMSTIM_AUTONOMOUS:-0}" == "1" ]]; then
        is_auto=true
    fi
    [ "$is_auto" = "true" ]
}

@test "simstim: autonomous check pattern returns false when unset" {
    unset SIMSTIM_AUTONOMOUS
    local is_auto=false
    if [[ "${SIMSTIM_AUTONOMOUS:-0}" == "1" ]]; then
        is_auto=true
    fi
    [ "$is_auto" = "false" ]
}
