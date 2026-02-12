#!/usr/bin/env bats
# Unit tests for golden-path.sh bridge state detection
# Sprint 3: Integration — bridge state in golden path

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/golden-bridge-test-$$"
    mkdir -p "$TEST_TMPDIR/.claude/scripts" "$TEST_TMPDIR/.run"
    mkdir -p "$TEST_TMPDIR/grimoires/loa"

    # Copy required scripts
    cp "$PROJECT_ROOT/.claude/scripts/bootstrap.sh" "$TEST_TMPDIR/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/golden-path.sh" "$TEST_TMPDIR/.claude/scripts/"
    if [[ -f "$PROJECT_ROOT/.claude/scripts/path-lib.sh" ]]; then
        cp "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$TEST_TMPDIR/.claude/scripts/"
    fi

    # Initialize git repo for bootstrap
    cd "$TEST_TMPDIR"
    git init -q
    git add -A 2>/dev/null || true
    git commit -q -m "init" --allow-empty

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
# Bridge State Detection
# =============================================================================

@test "golden-path: detect_bridge_state returns none when no state file" {
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local state
    state=$(golden_detect_bridge_state)
    [ "$state" = "none" ]
}

@test "golden-path: detect_bridge_state returns ITERATING" {
    skip_if_deps_missing
    cat > "$TEST_TMPDIR/.run/bridge-state.json" <<'EOF'
{
    "schema_version": 1,
    "state": "ITERATING",
    "bridge_id": "bridge-test-123",
    "config": {"depth": 3, "mode": "full", "flatline_threshold": 0.05, "per_sprint": false, "branch": "feature/test"},
    "timestamps": {"started": "2026-01-01T00:00:00Z", "last_activity": "2026-01-01T01:00:00Z"},
    "iterations": [{"iteration": 1, "state": "completed", "sprint_plan_source": "existing", "sprints_executed": 2, "bridgebuilder": {"total_findings": 10, "by_severity": {"critical": 1, "high": 2, "medium": 3, "low": 2, "vision": 2}, "severity_weighted_score": 28, "pr_comment_url": null}, "visions_captured": 0, "started_at": "2026-01-01T00:00:00Z"}],
    "flatline": {"initial_score": 15.5, "last_score": 4.0, "consecutive_below_threshold": 0},
    "metrics": {"total_sprints_executed": 2, "total_files_changed": 10, "total_findings_addressed": 0, "total_visions_captured": 0},
    "finalization": {"ground_truth_updated": false, "rtfm_passed": false, "pr_url": null}
}
EOF

    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local state
    state=$(golden_detect_bridge_state)
    [ "$state" = "ITERATING" ]
}

@test "golden-path: detect_bridge_state returns HALTED" {
    skip_if_deps_missing
    cat > "$TEST_TMPDIR/.run/bridge-state.json" <<'EOF'
{
    "schema_version": 1,
    "state": "HALTED",
    "bridge_id": "bridge-test-456",
    "config": {"depth": 3, "mode": "full", "flatline_threshold": 0.05, "per_sprint": false, "branch": "feature/test"},
    "timestamps": {"started": "2026-01-01T00:00:00Z", "last_activity": "2026-01-01T01:00:00Z"},
    "iterations": [{"iteration": 1, "state": "completed", "sprint_plan_source": "existing", "sprints_executed": 2, "bridgebuilder": {"total_findings": 10, "by_severity": {"critical": 1, "high": 2, "medium": 3, "low": 2, "vision": 2}, "severity_weighted_score": 28, "pr_comment_url": null}, "visions_captured": 0, "started_at": "2026-01-01T00:00:00Z"}],
    "flatline": {"initial_score": 28, "last_score": 28, "consecutive_below_threshold": 0},
    "metrics": {"total_sprints_executed": 2, "total_files_changed": 10, "total_findings_addressed": 0, "total_visions_captured": 0},
    "finalization": {"ground_truth_updated": false, "rtfm_passed": false, "pr_url": null}
}
EOF

    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local state
    state=$(golden_detect_bridge_state)
    [ "$state" = "HALTED" ]
}

@test "golden-path: detect_bridge_state returns JACKED_OUT" {
    skip_if_deps_missing
    cat > "$TEST_TMPDIR/.run/bridge-state.json" <<'EOF'
{
    "schema_version": 1,
    "state": "JACKED_OUT",
    "bridge_id": "bridge-test-789",
    "config": {"depth": 3, "mode": "full", "flatline_threshold": 0.05, "per_sprint": false, "branch": "feature/test"},
    "timestamps": {"started": "2026-01-01T00:00:00Z", "last_activity": "2026-01-01T02:00:00Z"},
    "iterations": [{"iteration": 1, "state": "completed", "sprint_plan_source": "existing", "sprints_executed": 2, "bridgebuilder": {"total_findings": 5, "by_severity": {"critical": 0, "high": 1, "medium": 2, "low": 1, "vision": 1}, "severity_weighted_score": 10, "pr_comment_url": null}, "visions_captured": 0, "started_at": "2026-01-01T00:00:00Z"}],
    "flatline": {"initial_score": 10, "last_score": 1, "consecutive_below_threshold": 2},
    "metrics": {"total_sprints_executed": 2, "total_files_changed": 8, "total_findings_addressed": 4, "total_visions_captured": 0},
    "finalization": {"ground_truth_updated": true, "rtfm_passed": true, "pr_url": "https://github.com/test/repo/pull/1"}
}
EOF

    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local state
    state=$(golden_detect_bridge_state)
    [ "$state" = "JACKED_OUT" ]
}

# =============================================================================
# Bridge Progress Display
# =============================================================================

@test "golden-path: bridge_progress returns empty for missing state" {
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local progress
    progress=$(golden_bridge_progress)
    [ -z "$progress" ]
}

@test "golden-path: bridge_progress shows iteration for ITERATING state" {
    skip_if_deps_missing
    cat > "$TEST_TMPDIR/.run/bridge-state.json" <<'EOF'
{
    "schema_version": 1,
    "state": "ITERATING",
    "bridge_id": "bridge-test-p1",
    "config": {"depth": 3, "mode": "full", "flatline_threshold": 0.05, "per_sprint": false, "branch": "feature/test"},
    "timestamps": {"started": "2026-01-01T00:00:00Z", "last_activity": "2026-01-01T02:00:00Z"},
    "iterations": [
        {"iteration": 1, "state": "completed", "sprint_plan_source": "existing", "sprints_executed": 2, "bridgebuilder": {"total_findings": 10, "by_severity": {"critical": 1, "high": 2, "medium": 3, "low": 2, "vision": 2}, "severity_weighted_score": 28, "pr_comment_url": null}, "visions_captured": 0, "started_at": "2026-01-01T00:00:00Z"},
        {"iteration": 2, "state": "in_progress", "sprint_plan_source": "findings", "sprints_executed": 0, "bridgebuilder": {"total_findings": 0, "by_severity": {"critical": 0, "high": 0, "medium": 0, "low": 0, "vision": 0}, "severity_weighted_score": 0, "pr_comment_url": null}, "visions_captured": 0, "started_at": "2026-01-01T01:00:00Z"}
    ],
    "flatline": {"initial_score": 15.5, "last_score": 4.0, "consecutive_below_threshold": 0},
    "metrics": {"total_sprints_executed": 2, "total_files_changed": 10, "total_findings_addressed": 0, "total_visions_captured": 0},
    "finalization": {"ground_truth_updated": false, "rtfm_passed": false, "pr_url": null}
}
EOF

    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local progress
    progress=$(golden_bridge_progress)
    [[ "$progress" == *"Iteration 2/3"* ]]
    [[ "$progress" == *"score"* ]]
}

@test "golden-path: bridge_progress shows resume for HALTED state" {
    skip_if_deps_missing
    cat > "$TEST_TMPDIR/.run/bridge-state.json" <<'EOF'
{
    "schema_version": 1,
    "state": "HALTED",
    "bridge_id": "bridge-test-p2",
    "config": {"depth": 3, "mode": "full", "flatline_threshold": 0.05, "per_sprint": false, "branch": "feature/test"},
    "timestamps": {"started": "2026-01-01T00:00:00Z", "last_activity": "2026-01-01T01:30:00Z"},
    "iterations": [{"iteration": 1, "state": "completed", "sprint_plan_source": "existing", "sprints_executed": 2, "bridgebuilder": {"total_findings": 8, "by_severity": {"critical": 0, "high": 2, "medium": 3, "low": 2, "vision": 1}, "severity_weighted_score": 18, "pr_comment_url": null}, "visions_captured": 0, "started_at": "2026-01-01T00:00:00Z"}],
    "flatline": {"initial_score": 18, "last_score": 18, "consecutive_below_threshold": 0},
    "metrics": {"total_sprints_executed": 2, "total_files_changed": 10, "total_findings_addressed": 0, "total_visions_captured": 0},
    "finalization": {"ground_truth_updated": false, "rtfm_passed": false, "pr_url": null}
}
EOF

    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local progress
    progress=$(golden_bridge_progress)
    [[ "$progress" == *"HALTED"* ]]
    [[ "$progress" == *"resume"* ]]
}

@test "golden-path: bridge_progress returns empty for JACKED_OUT" {
    skip_if_deps_missing
    cat > "$TEST_TMPDIR/.run/bridge-state.json" <<'EOF'
{
    "schema_version": 1,
    "state": "JACKED_OUT",
    "bridge_id": "bridge-test-p3",
    "config": {"depth": 3, "mode": "full", "flatline_threshold": 0.05, "per_sprint": false, "branch": "feature/test"},
    "timestamps": {"started": "2026-01-01T00:00:00Z", "last_activity": "2026-01-01T02:00:00Z"},
    "iterations": [{"iteration": 1, "state": "completed", "sprint_plan_source": "existing", "sprints_executed": 2, "bridgebuilder": {"total_findings": 3, "by_severity": {"critical": 0, "high": 0, "medium": 2, "low": 1, "vision": 0}, "severity_weighted_score": 5, "pr_comment_url": null}, "visions_captured": 0, "started_at": "2026-01-01T00:00:00Z"}],
    "flatline": {"initial_score": 5, "last_score": 0, "consecutive_below_threshold": 2},
    "metrics": {"total_sprints_executed": 2, "total_files_changed": 5, "total_findings_addressed": 3, "total_visions_captured": 0},
    "finalization": {"ground_truth_updated": true, "rtfm_passed": true, "pr_url": null}
}
EOF

    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local progress
    progress=$(golden_bridge_progress)
    [ -z "$progress" ]
}

# =============================================================================
# Existing Golden Path Tests Regression
# =============================================================================

@test "golden-path: detect_plan_phase works with bridge additions" {
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local phase
    phase=$(golden_detect_plan_phase)
    [ "$phase" = "discovery" ]
}

@test "golden-path: detect_sprint returns empty with no sprint file" {
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local sprint
    sprint=$(golden_detect_sprint)
    [ -z "$sprint" ]
}

@test "golden-path: suggest_command returns /plan for initial state" {
    source "$TEST_TMPDIR/.claude/scripts/golden-path.sh"
    local cmd
    cmd=$(golden_suggest_command)
    [ "$cmd" = "/plan" ]
}
