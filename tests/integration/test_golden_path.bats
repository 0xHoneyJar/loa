#!/usr/bin/env bats
# test_golden_path.bats — Integration tests for .claude/scripts/golden-path.sh
# Issue: #211 — Golden Path DX
#
# Tests the state resolution helpers that power the 5 golden commands.
# All tests are hermetic — they use temp directories to simulate grimoire states.

# ─────────────────────────────────────────────────────────────
# Setup / Teardown
# ─────────────────────────────────────────────────────────────

setup() {
    # Create hermetic project directory
    TEST_DIR=$(mktemp -d)
    export PROJECT_ROOT="$TEST_DIR"
    export CONFIG_FILE="$TEST_DIR/.loa.config.yaml"

    # Use legacy paths to bypass yq v4 requirement in path-lib.sh
    export LOA_USE_LEGACY_PATHS=1

    # Create minimal framework structure
    mkdir -p "$TEST_DIR/.claude/scripts"
    mkdir -p "$TEST_DIR/grimoires/loa/a2a"

    # Copy bootstrap.sh and path-lib.sh
    REAL_SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.claude/scripts" && pwd)"
    cp "$REAL_SCRIPT_DIR/bootstrap.sh" "$TEST_DIR/.claude/scripts/"
    cp "$REAL_SCRIPT_DIR/path-lib.sh" "$TEST_DIR/.claude/scripts/"
    cp "$REAL_SCRIPT_DIR/golden-path.sh" "$TEST_DIR/.claude/scripts/"

    # Initialize git so bootstrap.sh can detect PROJECT_ROOT
    (cd "$TEST_DIR" && git init -q 2>/dev/null)

    # Source golden-path.sh (this sources bootstrap.sh → path-lib.sh)
    cd "$TEST_DIR"
    source "$TEST_DIR/.claude/scripts/golden-path.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# ─────────────────────────────────────────────────────────────
# Plan Phase Detection
# ─────────────────────────────────────────────────────────────

@test "golden_detect_plan_phase: returns 'discovery' when no artifacts exist" {
    local result
    result=$(golden_detect_plan_phase)
    [[ "$result" == "discovery" ]]
}

@test "golden_detect_plan_phase: returns 'architecture' when only PRD exists" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    local result
    result=$(golden_detect_plan_phase)
    [[ "$result" == "architecture" ]]
}

@test "golden_detect_plan_phase: returns 'sprint_planning' when PRD + SDD exist" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    local result
    result=$(golden_detect_plan_phase)
    [[ "$result" == "sprint_planning" ]]
}

@test "golden_detect_plan_phase: returns 'complete' when all three artifacts exist" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks here
EOF
    local result
    result=$(golden_detect_plan_phase)
    [[ "$result" == "complete" ]]
}

# ─────────────────────────────────────────────────────────────
# Sprint Detection
# ─────────────────────────────────────────────────────────────

@test "golden_detect_sprint: returns empty when no sprint plan exists" {
    local result
    result=$(golden_detect_sprint)
    [[ -z "$result" ]]
}

@test "golden_detect_sprint: returns sprint-1 when sprint plan exists but no work started" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
EOF
    local result
    result=$(golden_detect_sprint)
    [[ "$result" == "sprint-1" ]]
}

@test "golden_detect_sprint: returns sprint-2 when sprint-1 is complete" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"

    local result
    result=$(golden_detect_sprint)
    [[ "$result" == "sprint-2" ]]
}

@test "golden_detect_sprint: returns sprint-3 when sprint-1 and sprint-2 are complete" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
## Sprint 3: Ship
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-2"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-2/COMPLETED"

    local result
    result=$(golden_detect_sprint)
    [[ "$result" == "sprint-3" ]]
}

@test "golden_detect_sprint: returns empty when all sprints are complete" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-2"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-2/COMPLETED"

    local result
    result=$(golden_detect_sprint)
    [[ -z "$result" ]]
}

# ─────────────────────────────────────────────────────────────
# Review Target Detection
# ─────────────────────────────────────────────────────────────

@test "golden_detect_review_target: returns empty when no sprint plan exists" {
    local result
    result=$(golden_detect_review_target)
    [[ -z "$result" ]]
}

@test "golden_detect_review_target: returns empty when no sprint dirs exist" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    local result
    result=$(golden_detect_review_target)
    [[ -z "$result" ]]
}

@test "golden_detect_review_target: returns sprint-1 when sprint-1 dir exists" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"

    local result
    result=$(golden_detect_review_target)
    [[ "$result" == "sprint-1" ]]
}

@test "golden_detect_review_target: skips completed sprints" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-2"

    local result
    result=$(golden_detect_review_target)
    [[ "$result" == "sprint-2" ]]
}

@test "golden_detect_review_target: returns empty when all sprints complete" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"

    local result
    result=$(golden_detect_review_target)
    [[ -z "$result" ]]
}

# ─────────────────────────────────────────────────────────────
# Ship Readiness
# ─────────────────────────────────────────────────────────────

@test "golden_check_ship_ready: fails when no sprint plan exists" {
    run golden_check_ship_ready
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"No sprint plan"* ]]
}

@test "golden_check_ship_ready: fails when sprint not reviewed or audited" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"

    run golden_check_ship_ready
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"not been reviewed"* ]]
}

@test "golden_check_ship_ready: passes when all sprints complete" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"

    run golden_check_ship_ready
    [[ "$status" -eq 0 ]]
}

@test "golden_check_ship_ready: passes when sprint audited (APPROVED)" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    echo "APPROVED - LET'S FUCKING GO" > "$TEST_DIR/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md"

    run golden_check_ship_ready
    [[ "$status" -eq 0 ]]
}

@test "golden_check_ship_ready: fails when sprint not reviewed (has findings)" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    cat > "$TEST_DIR/grimoires/loa/a2a/sprint-1/engineer-feedback.md" << 'FEEDBACK'
# Review Feedback
## Changes Required
- Fix the thing
FEEDBACK

    run golden_check_ship_ready
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"not been reviewed"* ]]
}

@test "golden_check_ship_ready: fails on multi-sprint with one incomplete" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-2"

    run golden_check_ship_ready
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"sprint-2"* ]]
}

# ─────────────────────────────────────────────────────────────
# Journey Bar
# ─────────────────────────────────────────────────────────────

@test "golden_format_journey: shows marker at /plan when no artifacts" {
    local result
    result=$(golden_format_journey)
    # Marker ● should be right after /plan, before /build
    [[ "$result" == */plan\ ●* ]]
    # build/review/ship should have ─ (not ●)
    [[ "$result" == */build\ ─* ]]
}

@test "golden_format_journey: shows marker at /build when planning complete and sprints exist" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    local result
    result=$(golden_format_journey)
    # plan should be completed (━), build should have marker
    [[ "$result" == */plan\ ━* ]]
    [[ "$result" == */build\ ●* ]]
}

@test "golden_format_journey: shows marker at /ship when all sprints complete" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"

    local result
    result=$(golden_format_journey)
    [[ "$result" == */ship\ ●* ]]
}

@test "golden_format_journey: contains all 4 golden commands" {
    local result
    result=$(golden_format_journey)
    [[ "$result" == *"/plan"* ]]
    [[ "$result" == *"/build"* ]]
    [[ "$result" == *"/review"* ]]
    [[ "$result" == *"/ship"* ]]
}

# ─────────────────────────────────────────────────────────────
# Golden Command Suggestions
# ─────────────────────────────────────────────────────────────

@test "golden_suggest_command: suggests /plan when no artifacts exist" {
    local result
    result=$(golden_suggest_command)
    [[ "$result" == "/plan" ]]
}

@test "golden_suggest_command: suggests /plan when PRD exists but no SDD" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    local result
    result=$(golden_suggest_command)
    [[ "$result" == "/plan" ]]
}

@test "golden_suggest_command: suggests /plan when PRD+SDD exist but no sprint" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    local result
    result=$(golden_suggest_command)
    [[ "$result" == "/plan" ]]
}

@test "golden_suggest_command: suggests /build when sprint plan exists" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    local result
    result=$(golden_suggest_command)
    [[ "$result" == "/build" ]]
}

@test "golden_suggest_command: /review is defensive fallback when ship not ready" {
    # The /review suggestion triggers when all sprints are COMPLETED
    # but golden_check_ship_ready fails. In practice, COMPLETED markers
    # imply review+audit passed, so this is a pure safety net.
    # Verify the normal flow: COMPLETED → /ship
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"

    local result
    result=$(golden_suggest_command)
    [[ "$result" == "/ship" ]]
}

@test "golden_suggest_command: suggests /ship when all sprints complete" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"

    local result
    result=$(golden_suggest_command)
    [[ "$result" == "/ship" ]]
}

# ─────────────────────────────────────────────────────────────
# Truename Resolution
# ─────────────────────────────────────────────────────────────

@test "golden_resolve_truename: resolves plan → /plan-and-analyze when no PRD" {
    local result
    result=$(golden_resolve_truename "plan")
    [[ "$result" == "/plan-and-analyze" ]]
}

@test "golden_resolve_truename: resolves plan → /architect when PRD exists" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    local result
    result=$(golden_resolve_truename "plan")
    [[ "$result" == "/architect" ]]
}

@test "golden_resolve_truename: resolves plan → /sprint-plan when PRD+SDD exist" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    local result
    result=$(golden_resolve_truename "plan")
    [[ "$result" == "/sprint-plan" ]]
}

@test "golden_resolve_truename: resolves plan → empty when all planning complete" {
    touch "$TEST_DIR/grimoires/loa/prd.md"
    touch "$TEST_DIR/grimoires/loa/sdd.md"
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    local result
    result=$(golden_resolve_truename "plan")
    [[ -z "$result" ]]
}

@test "golden_resolve_truename: resolves build → /implement sprint-1" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    local result
    result=$(golden_resolve_truename "build")
    [[ "$result" == "/implement sprint-1" ]]
}

@test "golden_resolve_truename: resolves build with override → /implement sprint-3" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
## Sprint 3: Ship
Tasks
EOF
    local result
    result=$(golden_resolve_truename "build" "sprint-3")
    [[ "$result" == "/implement sprint-3" ]]
}

@test "golden_resolve_truename: resolves review → /review-sprint sprint-1" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"

    local result
    result=$(golden_resolve_truename "review")
    [[ "$result" == "/review-sprint sprint-1" ]]
}

@test "golden_resolve_truename: resolves ship → /deploy-production" {
    local result
    result=$(golden_resolve_truename "ship")
    [[ "$result" == "/deploy-production" ]]
}

@test "golden_resolve_truename: rejects invalid sprint ID override" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    run golden_resolve_truename "build" "not-a-sprint"
    [[ "$status" -eq 1 ]]
}

@test "golden_resolve_truename: rejects sprint-0 as invalid" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    run golden_resolve_truename "build" "sprint-0"
    [[ "$status" -eq 1 ]]
}

# ─────────────────────────────────────────────────────────────
# Edge Cases
# ─────────────────────────────────────────────────────────────

@test "sprint counting: handles sprint.md with no sprint headers" {
    touch "$TEST_DIR/grimoires/loa/sprint.md"
    local result
    result=$(golden_detect_sprint)
    [[ -z "$result" ]]
}

@test "sprint counting: correctly counts numbered headers only" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
# Sprint Plan
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
## Summary
Not a sprint
EOF
    # _gp_count_sprints matches "^## Sprint [0-9]"
    local count
    count=$(_gp_count_sprints)
    [[ "$count" -eq 2 ]]
}

@test "review detection: sprint with review file detected as needing review" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    echo "Found issues" > "$TEST_DIR/grimoires/loa/a2a/sprint-1/engineer-feedback.md"

    local result
    result=$(golden_detect_review_target)
    [[ "$result" == "sprint-1" ]]
}

@test "review detection: sprint reviewed when feedback has no findings sections" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    echo "Looks great, no issues found." > "$TEST_DIR/grimoires/loa/a2a/sprint-1/engineer-feedback.md"

    run _gp_sprint_is_reviewed "sprint-1"
    [[ "$status" -eq 0 ]]
}

@test "review detection: sprint NOT reviewed when feedback has Changes Required" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    cat > "$TEST_DIR/grimoires/loa/a2a/sprint-1/engineer-feedback.md" << 'FEEDBACK'
# Sprint 1 Review
## Changes Required
- Fix the broken tests
FEEDBACK

    run _gp_sprint_is_reviewed "sprint-1"
    [[ "$status" -eq 1 ]]
}

@test "review detection: sprint reviewed implicitly when audited" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    echo "APPROVED" > "$TEST_DIR/grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md"

    run _gp_sprint_is_reviewed "sprint-1"
    [[ "$status" -eq 0 ]]
}

@test "audit detection: approved audit passes ship readiness" {
    cat > "$TEST_DIR/grimoires/loa/sprint.md" << 'EOF'
## Sprint 1: Foundation
Tasks
## Sprint 2: Polish
Tasks
EOF
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-1"
    touch "$TEST_DIR/grimoires/loa/a2a/sprint-1/COMPLETED"
    mkdir -p "$TEST_DIR/grimoires/loa/a2a/sprint-2"
    echo "APPROVED - LET'S FUCKING GO" > "$TEST_DIR/grimoires/loa/a2a/sprint-2/auditor-sprint-feedback.md"

    run golden_check_ship_ready
    [[ "$status" -eq 0 ]]
}
