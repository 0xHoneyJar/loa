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
    init_bridge_state "bridge-20260101-abcdef" 5 false 0.05 "feature/test-bridge"
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

# Resume must restore run params frozen at JACK_IN from the persisted .config,
# not silently revert to script defaults (3 / 0.05 / 2). Uses the same
# function-extraction pattern as the load_bridge_config precedence tests.
@test "orchestrator: resume restores depth/flatline/consecutive_flatline from persisted .config" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bootstrap.sh"
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"
    # Seed a HALTED bridge with NON-default params (defaults are 3 / 0.05 / 2).
    init_bridge_state "bridge-20260101-abcde5" 5 false 0.2 "feature/test-bridge" "" 4
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    update_bridge_state "HALTED"

    source <(sed -n '/^restore_bridge_config_from_state()/,/^}/p' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh")

    # Resume invocation with no CLI overrides — globals sit at hardcoded defaults.
    DEPTH=3; CLI_DEPTH=""
    PER_SPRINT=false; CLI_PER_SPRINT=""
    FLATLINE_THRESHOLD=0.05
    CONSECUTIVE_FLATLINE=2

    restore_bridge_config_from_state

    [ "$DEPTH" = "5" ]
    [ "$PER_SPRINT" = "false" ]
    [ "$FLATLINE_THRESHOLD" = "0.2" ]
    [ "$CONSECUTIVE_FLATLINE" = "4" ]
}

@test "orchestrator: resume keeps re-passed CLI --depth over persisted .config depth" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bootstrap.sh"
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"
    init_bridge_state "bridge-20260101-abcde6" 5 false 0.2 "feature/test-bridge" "" 4
    update_bridge_state "JACK_IN"

    source <(sed -n '/^restore_bridge_config_from_state()/,/^}/p' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh")

    # Operator re-passed --depth 7 on the resume invocation → CLI sentinel set.
    DEPTH=7; CLI_DEPTH=7
    PER_SPRINT=false; CLI_PER_SPRINT=""
    FLATLINE_THRESHOLD=0.05
    CONSECUTIVE_FLATLINE=2

    restore_bridge_config_from_state

    [ "$DEPTH" = "7" ]                 # CLI override wins over persisted 5
    [ "$CONSECUTIVE_FLATLINE" = "4" ]  # no CLI flag → still restored from state
}

@test "orchestrator: resume falls back to defaults for old state files missing consecutive_flatline" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bootstrap.sh"
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"
    init_bridge_state "bridge-20260101-abcde7" 5 false 0.2 "feature/test-bridge"
    # Simulate a pre-fix state file: strip the new key entirely.
    jq 'del(.config.consecutive_flatline)' "$TEST_TMPDIR/.run/bridge-state.json" > "$TEST_TMPDIR/.run/bridge-state.json.tmp"
    mv "$TEST_TMPDIR/.run/bridge-state.json.tmp" "$TEST_TMPDIR/.run/bridge-state.json"

    source <(sed -n '/^restore_bridge_config_from_state()/,/^}/p' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh")

    DEPTH=3; CLI_DEPTH=""
    PER_SPRINT=false; CLI_PER_SPRINT=""
    FLATLINE_THRESHOLD=0.05
    CONSECUTIVE_FLATLINE=2

    restore_bridge_config_from_state

    [ "$DEPTH" = "5" ]                 # still restored
    [ "$CONSECUTIVE_FLATLINE" = "2" ]  # missing key → // 2 fallback, no error
}

# =============================================================================
# CLI > Config Precedence
# =============================================================================

@test "orchestrator: --help shows usage" {
    run bash "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# Function-level tests for load_bridge_config()'s CLI > config > default
# precedence (cycle-116 D5). Extract the function in isolation rather than
# driving bridge_main() end to end, to avoid Finalization side effects
# (butterfreezone-gen.sh, lore-discover.sh) that a full run would trigger.
skip_if_yq_missing() {
    command -v yq &>/dev/null || skip "yq not installed"
}

@test "orchestrator: load_bridge_config resolves hardcoded default 3 when config omits depth" {
    skip_if_deps_missing
    skip_if_yq_missing
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
run_bridge:
  enabled: true
EOF
    source <(sed -n '/^load_bridge_config()/,/^}/p' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh")

    CONFIG_FILE="$TEST_TMPDIR/.loa.config.yaml"
    DEPTH=3
    CLI_DEPTH=""
    PER_SPRINT=false
    CLI_PER_SPRINT=""
    FLATLINE_THRESHOLD=0.05
    CLI_FLATLINE_THRESHOLD=""
    CONSECUTIVE_FLATLINE=2

    load_bridge_config

    [ "$DEPTH" = "3" ]
}

@test "orchestrator: load_bridge_config applies config-only depth override" {
    skip_if_deps_missing
    skip_if_yq_missing
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
run_bridge:
  enabled: true
  defaults:
    depth: 2
EOF
    source <(sed -n '/^load_bridge_config()/,/^}/p' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh")

    CONFIG_FILE="$TEST_TMPDIR/.loa.config.yaml"
    DEPTH=3
    CLI_DEPTH=""
    PER_SPRINT=false
    CLI_PER_SPRINT=""
    FLATLINE_THRESHOLD=0.05
    CLI_FLATLINE_THRESHOLD=""
    CONSECUTIVE_FLATLINE=2

    load_bridge_config

    [ "$DEPTH" = "2" ]
}

@test "orchestrator: load_bridge_config lets CLI --depth win over config" {
    skip_if_deps_missing
    skip_if_yq_missing
    cat > "$TEST_TMPDIR/.loa.config.yaml" <<'EOF'
run_bridge:
  enabled: true
  defaults:
    depth: 2
EOF
    source <(sed -n '/^load_bridge_config()/,/^}/p' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh")

    CONFIG_FILE="$TEST_TMPDIR/.loa.config.yaml"
    DEPTH=4
    CLI_DEPTH=4
    PER_SPRINT=false
    CLI_PER_SPRINT=""
    FLATLINE_THRESHOLD=0.05
    CLI_FLATLINE_THRESHOLD=""
    CONSECUTIVE_FLATLINE=2

    load_bridge_config

    [ "$DEPTH" = "4" ]
}

# =============================================================================
# Termination Reason (cycle-116 D5) — source-grep, matching existing
# "SINGLE-ITERATION banner text present in source" style.
# =============================================================================

@test "orchestrator: MAX ITERATIONS REACHED banner present in source" {
    grep -q 'MAX ITERATIONS REACHED' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh"
}

@test "orchestrator: empirical plateau citation present in source" {
    grep -q 'empirical: code PRs plateau at 2 iters (cycles 102-114 record)' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh"
}

@test "orchestrator: finalization.termination_reason write present in source" {
    grep -q 'finalization.termination_reason' "$TEST_TMPDIR/.claude/scripts/bridge-orchestrator.sh"
}
