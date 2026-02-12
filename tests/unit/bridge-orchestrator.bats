#!/usr/bin/env bats
# Unit tests for bridge-orchestrator.sh - Argument validation, preflight, resume
# Sprint 3: Bridge Iteration 3 — orchestrator test coverage

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/bridge-orch-test-$$"
    mkdir -p "$TEST_TMPDIR/.run" "$TEST_TMPDIR/.claude/scripts"
    mkdir -p "$TEST_TMPDIR/grimoires/loa"

    # Copy scripts to test project
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_TMPDIR/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/bridge-state.sh" "$TEST_TMPDIR/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/bridge-orchestrator.sh" "$TEST_TMPDIR/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_TMPDIR/.claude/scripts/"
    fi

    # Create minimal config allowing bridge
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
run_bridge:
  enabled: true
  defaults:
    depth: 3
EOF

    # Create sprint.md so preflight passes
    echo "# Sprint Plan" > "$TEST_TMPDIR/grimoires/loa/sprint.md"

    # Initialize git repo on a feature branch
    cd "$TEST_TMPDIR"
    git init -q
    git add -A 2>/dev/null || true
    git commit -q -m "init" --allow-empty
    git checkout -q -b feature/test-bridge

    export PROJECT_ROOT="$TEST_TMPDIR"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

skip_if_deps_missing() {
    if ! command -v jq &>/dev/null; then
        skip "jq not installed"
    fi
}

# =============================================================================
# Argument Validation: --depth
# =============================================================================

@test "orchestrator: --depth without value exits 2" {
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --depth
    [ "$status" -eq 2 ]
    [[ "$output" == *"--depth requires a value"* ]]
}

@test "orchestrator: --depth 0 rejected (below minimum)" {
    skip_if_deps_missing
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --depth 0
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be between 1 and"* ]]
}

@test "orchestrator: --depth 6 rejected (above maximum)" {
    skip_if_deps_missing
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --depth 6
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be between 1 and"* ]]
}

@test "orchestrator: --depth abc rejected (not numeric)" {
    skip_if_deps_missing
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --depth abc
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be a positive integer"* ]]
}

# =============================================================================
# Argument Validation: --from
# =============================================================================

@test "orchestrator: --from without value exits 2" {
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --from
    [ "$status" -eq 2 ]
    [[ "$output" == *"--from requires a value"* ]]
}

@test "orchestrator: unknown argument rejected" {
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown argument"* ]]
}

# =============================================================================
# Protected Branch Check
# =============================================================================

@test "orchestrator: rejects running on main branch" {
    skip_if_deps_missing
    cd "$TEST_TMPDIR"
    git checkout -q -b main 2>/dev/null || git checkout -q main
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --depth 1
    [ "$status" -eq 2 ]
    [[ "$output" == *"Cannot run bridge on protected branch"* ]]
}

@test "orchestrator: rejects running on master branch" {
    skip_if_deps_missing
    cd "$TEST_TMPDIR"
    git checkout -q -b master 2>/dev/null || git checkout -q master
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --depth 1
    [ "$status" -eq 2 ]
    [[ "$output" == *"Cannot run bridge on protected branch"* ]]
}

# =============================================================================
# Resume Logic
# =============================================================================

@test "orchestrator: state file records iteration count after HALTED" {
    skip_if_deps_missing
    # Set up a HALTED bridge state with 2 completed iterations
    source "$TEST_TMPDIR/.claude/scripts/bootstrap.sh"
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"
    init_bridge_state "bridge-resume-test" 5 false 0.05 "feature/test-bridge"
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    update_iteration 1 "completed" "existing"
    update_iteration 2 "completed" "findings"
    update_bridge_state "HALTED"

    # Verify state file records correct iteration count and HALTED state
    local state iteration_count
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    iteration_count=$(jq '.iterations | length' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "HALTED" ]
    [ "$iteration_count" = "2" ]
}

@test "orchestrator: resume without state file exits 1" {
    skip_if_deps_missing
    rm -f "$TEST_TMPDIR/.run/bridge-state.json"
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --resume
    [ "$status" -ne 0 ]
}

# =============================================================================
# CLI > Config Precedence
# =============================================================================

@test "orchestrator: --help shows usage" {
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}
