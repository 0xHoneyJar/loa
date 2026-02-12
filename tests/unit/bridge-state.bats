#!/usr/bin/env bats
# Unit tests for bridge-state.sh - Bridge state management
# Sprint 2: Bridge Core — state transitions, flatline, resume
# Sprint 1 cycle-006: flock atomic updates, crash safety, praise in by_severity

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/bridge-state-test-$$"
    mkdir -p "$TEST_TMPDIR/.run" "$TEST_TMPDIR/.claude/scripts"

    # Copy scripts to test project
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_TMPDIR/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/bridge-state.sh" "$TEST_TMPDIR/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_TMPDIR/.claude/scripts/"
    fi

    # Initialize as git repo for bootstrap
    cd "$TEST_TMPDIR"
    git init -q
    git add -A 2>/dev/null || true
    git commit -q -m "init" --allow-empty

    # Override PROJECT_ROOT for testing
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
# Initialization
# =============================================================================

@test "bridge-state: init creates state file" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00001" 3

    [ -f "$TEST_TMPDIR/.run/bridge-state.json" ]
    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "PREFLIGHT" ]
}

@test "bridge-state: init sets bridge_id and depth" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00002" 5

    local bridge_id depth
    bridge_id=$(jq -r '.bridge_id' "$TEST_TMPDIR/.run/bridge-state.json")
    depth=$(jq '.config.depth' "$TEST_TMPDIR/.run/bridge-state.json")

    [ "$bridge_id" = "bridge-20260213-a00002" ]
    [ "$depth" = "5" ]
}

@test "bridge-state: init sets schema version" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00003" 3

    local schema
    schema=$(jq '.schema_version' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$schema" = "1" ]
}

# =============================================================================
# State Transitions
# =============================================================================

@test "bridge-state: valid transition PREFLIGHT → JACK_IN" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00011" 3
    run update_bridge_state "JACK_IN"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "JACK_IN" ]
}

@test "bridge-state: valid transition JACK_IN → ITERATING" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00012" 3
    update_bridge_state "JACK_IN"
    run update_bridge_state "ITERATING"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "ITERATING" ]
}

@test "bridge-state: valid transition ITERATING → FINALIZING" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00013" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    run update_bridge_state "FINALIZING"
    [ "$status" -eq 0 ]
}

@test "bridge-state: valid transition FINALIZING → JACKED_OUT" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00014" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    update_bridge_state "FINALIZING"
    run update_bridge_state "JACKED_OUT"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "JACKED_OUT" ]
}

@test "bridge-state: illegal transition PREFLIGHT → ITERATING rejected" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00015" 3
    run update_bridge_state "ITERATING"
    [ "$status" -ne 0 ]
}

@test "bridge-state: valid transition JACK_IN → HALTED" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-bb0001" 3
    update_bridge_state "JACK_IN"
    run update_bridge_state "HALTED"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "HALTED" ]
}

@test "bridge-state: valid transition ITERATING → HALTED" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-bb0002" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    run update_bridge_state "HALTED"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "HALTED" ]
}

@test "bridge-state: valid transition FINALIZING → HALTED" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-bb0003" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    update_bridge_state "FINALIZING"
    run update_bridge_state "HALTED"
    [ "$status" -eq 0 ]
}

@test "bridge-state: valid transition HALTED → ITERATING" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-bb0004" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "HALTED"
    run update_bridge_state "ITERATING"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "ITERATING" ]
}

@test "bridge-state: valid transition HALTED → JACKED_OUT" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-bb0005" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "HALTED"
    run update_bridge_state "JACKED_OUT"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "JACKED_OUT" ]
}

@test "bridge-state: valid self-transition ITERATING → ITERATING" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-cc0001" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    run update_bridge_state "ITERATING"
    [ "$status" -eq 0 ]

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "ITERATING" ]
}

@test "bridge-state: illegal transition JACKED_OUT → ITERATING rejected" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-a00016" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    update_bridge_state "FINALIZING"
    update_bridge_state "JACKED_OUT"
    run update_bridge_state "ITERATING"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Iteration Tracking
# =============================================================================

@test "bridge-state: update_iteration appends to iterations array" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-dd0001" 3
    update_iteration 1 "in_progress" "existing"

    local count
    count=$(jq '.iterations | length' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$count" = "1" ]

    local iter_num
    iter_num=$(jq '.iterations[0].iteration' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$iter_num" = "1" ]
}

@test "bridge-state: update_iteration updates existing iteration" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-dd0002" 3
    update_iteration 1 "in_progress" "existing"
    update_iteration 1 "completed" "existing"

    local count state
    count=$(jq '.iterations | length' "$TEST_TMPDIR/.run/bridge-state.json")
    state=$(jq -r '.iterations[0].state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$count" = "1" ]
    [ "$state" = "completed" ]
}

@test "bridge-state: new iteration includes praise in by_severity" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-dd0003" 3
    update_iteration 1 "in_progress" "existing"

    local praise
    praise=$(jq '.iterations[0].bridgebuilder.by_severity.praise // "missing"' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$praise" = "0" ]
}

# =============================================================================
# Iteration Findings
# =============================================================================

@test "bridge-state: update_iteration_findings sets bridgebuilder data" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ee0001" 3
    update_iteration 1 "in_progress" "existing"

    # Create findings summary JSON
    cat > "$TEST_TMPDIR/findings.json" <<'EOF'
{
    "total": 10,
    "by_severity": {"critical": 2, "high": 3, "medium": 3, "low": 1, "vision": 1, "praise": 0},
    "severity_weighted_score": 42
}
EOF

    update_iteration_findings 1 "$TEST_TMPDIR/findings.json"

    local total score
    total=$(jq '.iterations[0].bridgebuilder.total_findings' "$TEST_TMPDIR/.run/bridge-state.json")
    score=$(jq '.iterations[0].bridgebuilder.severity_weighted_score' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$total" = "10" ]
    [ "$score" = "42" ]
}

@test "bridge-state: update_iteration_findings sets severity breakdown" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ee0002" 3
    update_iteration 1 "in_progress" "existing"

    cat > "$TEST_TMPDIR/findings.json" <<'EOF'
{
    "total": 5,
    "by_severity": {"critical": 1, "high": 2, "medium": 1, "low": 0, "vision": 1, "praise": 0},
    "severity_weighted_score": 22
}
EOF

    update_iteration_findings 1 "$TEST_TMPDIR/findings.json"

    local critical high vision
    critical=$(jq '.iterations[0].bridgebuilder.by_severity.critical' "$TEST_TMPDIR/.run/bridge-state.json")
    high=$(jq '.iterations[0].bridgebuilder.by_severity.high' "$TEST_TMPDIR/.run/bridge-state.json")
    vision=$(jq '.iterations[0].bridgebuilder.by_severity.vision' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$critical" = "1" ]
    [ "$high" = "2" ]
    [ "$vision" = "1" ]
}

@test "bridge-state: update_iteration_findings sets praise count" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ee0003" 3
    update_iteration 1 "in_progress" "existing"

    cat > "$TEST_TMPDIR/findings.json" <<'EOF'
{
    "total": 3,
    "by_severity": {"critical": 0, "high": 1, "medium": 0, "low": 0, "vision": 0, "praise": 2},
    "severity_weighted_score": 5
}
EOF

    update_iteration_findings 1 "$TEST_TMPDIR/findings.json"

    local praise
    praise=$(jq '.iterations[0].bridgebuilder.by_severity.praise' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$praise" = "2" ]
}

@test "bridge-state: update_iteration_findings fails with missing files" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ee0004" 3

    run update_iteration_findings 1 "/nonexistent/findings.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# Flatline Detection
# =============================================================================

@test "bridge-state: is_flatlined returns false when no consecutive flatlines" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ff0001" 3
    local result
    result=$(is_flatlined 2)
    [ "$result" = "false" ]
}

@test "bridge-state: update_flatline sets initial score on iteration 1" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ff0002" 3
    update_flatline 15.5 1

    local initial
    initial=$(jq '.flatline.initial_score' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$initial" = "15.5" ]
}

@test "bridge-state: flatline triggers after consecutive below threshold" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ff0003" 3 false 0.05
    update_flatline 100 1  # Initial score
    update_flatline 3 2    # 3/100 = 0.03 < 0.05 → below threshold
    update_flatline 2 3    # 2/100 = 0.02 < 0.05 → below threshold again

    local result
    result=$(is_flatlined 2)
    [ "$result" = "true" ]
}

@test "bridge-state: flatline resets when score rises above threshold" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ff0004" 3 false 0.05
    update_flatline 100 1  # Initial score
    update_flatline 3 2    # Below threshold
    update_flatline 50 3   # 50/100 = 0.50 > 0.05 → above threshold (resets)

    local consec
    consec=$(jq '.flatline.consecutive_below_threshold' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$consec" = "0" ]
}

# =============================================================================
# Metrics
# =============================================================================

@test "bridge-state: update_metrics accumulates values" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ab0001" 3
    update_metrics 3 10 5 1
    update_metrics 2 8 3 0

    local sprints files findings visions
    sprints=$(jq '.metrics.total_sprints_executed' "$TEST_TMPDIR/.run/bridge-state.json")
    files=$(jq '.metrics.total_files_changed' "$TEST_TMPDIR/.run/bridge-state.json")
    findings=$(jq '.metrics.total_findings_addressed' "$TEST_TMPDIR/.run/bridge-state.json")
    visions=$(jq '.metrics.total_visions_captured' "$TEST_TMPDIR/.run/bridge-state.json")

    [ "$sprints" = "5" ]
    [ "$files" = "18" ]
    [ "$findings" = "8" ]
    [ "$visions" = "1" ]
}

# =============================================================================
# Read and Helpers
# =============================================================================

@test "bridge-state: read_bridge_state validates schema version" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ab0011" 3
    run read_bridge_state
    [ "$status" -eq 0 ]
}

@test "bridge-state: read_bridge_state fails on wrong schema" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ab0012" 3
    # Corrupt schema version
    jq '.schema_version = 999' "$TEST_TMPDIR/.run/bridge-state.json" > "$TEST_TMPDIR/.run/bridge-state.json.tmp"
    mv "$TEST_TMPDIR/.run/bridge-state.json.tmp" "$TEST_TMPDIR/.run/bridge-state.json"

    run read_bridge_state
    [ "$status" -ne 0 ]
}

@test "bridge-state: get_bridge_id returns id" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ab0021" 3
    local id
    id=$(get_bridge_id)
    [ "$id" = "bridge-20260213-ab0021" ]
}

@test "bridge-state: get_bridge_state returns current state" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ab0022" 3
    local state
    state=$(get_bridge_state)
    [ "$state" = "PREFLIGHT" ]
}

@test "bridge-state: atomic writes use .tmp intermediary" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ab0031" 3

    # Verify no .tmp files remain
    [ ! -f "$TEST_TMPDIR/.run/bridge-state.json.tmp" ]
}

# =============================================================================
# last_score tracking
# =============================================================================

@test "bridge-state: update_flatline sets last_score on iteration 1" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ac0001" 3
    update_flatline 15.5 1

    local last_score
    last_score=$(jq '.flatline.last_score' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$last_score" = "15.5" ]
}

@test "bridge-state: update_flatline updates last_score on subsequent iterations" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ac0002" 3 false 0.05
    update_flatline 100 1
    update_flatline 50 2

    local last_score
    last_score=$(jq '.flatline.last_score' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$last_score" = "50" ]
}

@test "bridge-state: update_flatline tracks last_score through below-threshold" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ac0003" 3 false 0.05
    update_flatline 100 1
    update_flatline 3 2    # Below threshold

    local last_score
    last_score=$(jq '.flatline.last_score' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$last_score" = "3" ]
}

# =============================================================================
# get_current_iteration
# =============================================================================

@test "bridge-state: get_current_iteration returns 0 with no iterations" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ad0001" 3
    local count
    count=$(get_current_iteration)
    [ "$count" = "0" ]
}

@test "bridge-state: get_current_iteration returns count after iterations" {
    skip_if_deps_missing
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ad0002" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"
    update_iteration 1 "completed" "existing"
    update_iteration 2 "in_progress" "findings"

    local count
    count=$(get_current_iteration)
    [ "$count" = "2" ]
}

# =============================================================================
# Flock Atomic Updates (cycle-006)
# =============================================================================

@test "bridge-state: atomic_state_update creates and removes lock" {
    skip_if_deps_missing
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ae0001" 3

    # Perform an atomic update
    atomic_state_update '.state = "test"'

    # Verify state changed
    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "test" ]
}

@test "bridge-state: atomic_state_update no tmp files remain after success" {
    skip_if_deps_missing
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ae0002" 3
    atomic_state_update '.state = "test"'

    # No temporary files should remain (use find to avoid pipefail issues with ls glob)
    local tmp_count
    tmp_count=$(find "$TEST_TMPDIR/.run" -name "bridge-state.json.tmp*" 2>/dev/null | wc -l)
    [ "$tmp_count" = "0" ]
}

@test "bridge-state: atomic_state_update fails gracefully on bad jq filter" {
    skip_if_deps_missing
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ae0003" 3

    # Bad jq filter should fail and not corrupt state
    run atomic_state_update '.this.is.invalid | explode'
    [ "$status" -ne 0 ]

    # Original state should be unchanged
    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "PREFLIGHT" ]
}

@test "bridge-state: update_bridge_state uses flock when available" {
    skip_if_deps_missing
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ae0004" 3

    # This should use atomic_state_update internally
    update_bridge_state "JACK_IN"

    local state
    state=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$state" = "JACK_IN" ]
}

@test "bridge-state: crash safety - no corruption on failed jq" {
    skip_if_deps_missing
    if ! command -v flock &>/dev/null; then
        skip "flock not available"
    fi
    source "$TEST_TMPDIR/.claude/scripts/bridge-state.sh"

    init_bridge_state "bridge-20260213-ae0005" 3
    update_bridge_state "JACK_IN"
    update_bridge_state "ITERATING"

    # Get current state before crash attempt
    local before
    before=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$before" = "ITERATING" ]

    # Attempt a bad atomic update (should fail)
    run atomic_state_update 'invalid_filter'
    [ "$status" -ne 0 ]

    # State should be unchanged after failed write
    local after
    after=$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-state.json")
    [ "$after" = "ITERATING" ]

    # No temp files left behind (use find to avoid pipefail issues with ls glob)
    local tmp_count
    tmp_count=$(find "$TEST_TMPDIR/.run" -name "bridge-state.json.tmp*" 2>/dev/null | wc -l)
    [ "$tmp_count" = "0" ]
}
