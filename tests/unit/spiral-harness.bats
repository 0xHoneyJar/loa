#!/usr/bin/env bats
# Unit tests for spiral-harness.sh — Evidence-Gated Orchestrator
# Cycle-071: Spiral Harness Architecture

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/spiral-harness-test-$$"
    mkdir -p "$TEST_TMPDIR"

    export PROJECT_ROOT="$TEST_TMPDIR"

    # Minimal config
    cat > "$TEST_TMPDIR/.loa.config.yaml" << 'CONFIG'
spiral:
  harness:
    enabled: true
    max_phase_retries: 3
    planning_budget_usd: 1
    implement_budget_usd: 5
    review_budget_usd: 2
    audit_budget_usd: 2
CONFIG
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Argument Validation
# =============================================================================

@test "harness: requires --task" {
    run "$SCRIPT" --cycle-dir /tmp --cycle-id test --branch test --budget 10
    [ "$status" -eq 2 ]
    [[ "$output" == *"--task required"* ]]
}

@test "harness: requires --cycle-dir" {
    run "$SCRIPT" --task "test" --cycle-id test --branch test --budget 10
    [ "$status" -eq 2 ]
    [[ "$output" == *"--cycle-dir required"* ]]
}

@test "harness: requires --cycle-id" {
    run "$SCRIPT" --task "test" --cycle-dir /tmp --branch test --budget 10
    [ "$status" -eq 2 ]
    [[ "$output" == *"--cycle-id required"* ]]
}

@test "harness: requires --branch" {
    run "$SCRIPT" --task "test" --cycle-dir /tmp --cycle-id test --budget 10
    [ "$status" -eq 2 ]
    [[ "$output" == *"--branch required"* ]]
}

@test "harness: rejects unknown option" {
    run "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

# =============================================================================
# Harness Script Structure
# =============================================================================

@test "harness: script is executable" {
    [ -x "$PROJECT_ROOT/.claude/scripts/spiral-harness.sh" ] || \
    [ -x "$BATS_TEST_DIR/../../.claude/scripts/spiral-harness.sh" ]
}

@test "harness: sources spiral-evidence.sh" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep "spiral-evidence.sh" "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

@test "harness: has all 6 phase functions" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    local script="$REAL_ROOT/.claude/scripts/spiral-harness.sh"

    grep -q '_phase_discovery' "$script"
    grep -q '_phase_architecture' "$script"
    grep -q '_phase_planning' "$script"
    grep -q '_phase_implement' "$script"
    grep -q '_gate_review' "$script"
    grep -q '_gate_audit' "$script"
}

@test "harness: has all gate functions" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    local script="$REAL_ROOT/.claude/scripts/spiral-harness.sh"

    grep -q '_gate_flatline' "$script"
    grep -q '_gate_review' "$script"
    grep -q '_gate_audit' "$script"
    grep -q '_gate_bridgebuilder' "$script"
}

@test "harness: uses --allow-dangerously-skip-permissions" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep -c 'allow-dangerously-skip-permissions' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$output" -ge 1 ]
}

@test "harness: has circuit breaker in _run_gate" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    grep -q 'CIRCUIT_BREAKER' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
}

# =============================================================================
# Prompt Scoping
# =============================================================================

@test "harness: discovery prompt forbids code writing" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep 'Do NOT write code' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

@test "harness: discovery prompt requires Assumptions section" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep 'Assumptions' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

@test "harness: review prompt uses git diff (not implementation context)" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep 'git diff' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

@test "harness: audit prompt includes OWASP" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep -i 'injection\|secrets\|validation' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Dispatch Integration
# =============================================================================

@test "harness: dispatch calls harness instead of claude -p directly" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep 'spiral-harness.sh' "$REAL_ROOT/.claude/scripts/spiral-simstim-dispatch.sh"
    [ "$status" -eq 0 ]
}

@test "harness: dispatch passes --task to harness" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep '\-\-task.*\$task' "$REAL_ROOT/.claude/scripts/spiral-simstim-dispatch.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Evidence Integration
# =============================================================================

@test "harness: creates evidence directory" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep 'EVIDENCE_DIR' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

@test "harness: initializes flight recorder" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep '_init_flight_recorder' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

@test "harness: finalizes flight recorder" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run grep '_finalize_flight_recorder' "$REAL_ROOT/.claude/scripts/spiral-harness.sh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Config
# =============================================================================

@test "harness: config has harness section" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run yq eval '.spiral.harness.enabled' "$REAL_ROOT/.loa.config.yaml"
    [ "$output" = "true" ]
}

@test "harness: config has budget keys" {
    local REAL_ROOT
    REAL_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    run yq eval '.spiral.harness.planning_budget_usd' "$REAL_ROOT/.loa.config.yaml"
    [ "$output" = "1" ]
}
