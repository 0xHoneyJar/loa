#!/usr/bin/env bats
# Integration tests for setup phase removal (v0.15.0)
# Verifies commands work without .loa-setup-complete marker

# Test setup
setup() {
    # Get absolute paths
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/setup-removal-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create test project structure
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/sprint-1"

    # Save original environment
    ORIG_LOA_CONSTRUCTS_API_KEY="${LOA_CONSTRUCTS_API_KEY:-}"

    # Set working directory
    cd "$TEST_TMPDIR"
}

teardown() {
    # Restore original environment
    if [[ -n "$ORIG_LOA_CONSTRUCTS_API_KEY" ]]; then
        export LOA_CONSTRUCTS_API_KEY="$ORIG_LOA_CONSTRUCTS_API_KEY"
    else
        unset LOA_CONSTRUCTS_API_KEY
    fi

    # Clean up temp directory
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Phase command prerequisite tests (without marker)
# =============================================================================

@test "plan-and-analyze: works without .loa-setup-complete" {
    # plan/prd phase should have no prerequisites

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase plan
    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

@test "architect: works without .loa-setup-complete (needs prd.md)" {
    # Create PRD
    cat > "$TEST_TMPDIR/grimoires/loa/prd.md" << 'EOF'
# Product Requirements Document
Test PRD content
EOF

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase architect
    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

@test "architect: fails only if prd.md missing (not marker)" {
    # No PRD, no marker
    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase architect

    [[ "$status" -eq 1 ]]
    [[ "$output" == *"prd.md"* ]]
    # Should NOT mention setup-complete
    [[ "$output" != *"setup"* ]]
}

@test "sprint-plan: works without .loa-setup-complete (needs prd.md, sdd.md)" {
    # Create PRD and SDD
    cat > "$TEST_TMPDIR/grimoires/loa/prd.md" << 'EOF'
# Product Requirements Document
Test PRD content
EOF
    cat > "$TEST_TMPDIR/grimoires/loa/sdd.md" << 'EOF'
# Software Design Document
Test SDD content
EOF

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase sprint-plan
    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

@test "implement: works without .loa-setup-complete" {
    # Create all required files
    cat > "$TEST_TMPDIR/grimoires/loa/prd.md" << 'EOF'
# Product Requirements Document
Test PRD content
EOF
    cat > "$TEST_TMPDIR/grimoires/loa/sdd.md" << 'EOF'
# Software Design Document
Test SDD content
EOF
    cat > "$TEST_TMPDIR/grimoires/loa/sprint.md" << 'EOF'
# Sprint Plan
Test sprint content
EOF

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase implement
    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

# =============================================================================
# Feedback command tests
# =============================================================================

@test "feedback: works with API key set (THJ user)" {
    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    run "$PROJECT_ROOT/.claude/scripts/check-thj-member.sh"
    [[ "$status" -eq 0 ]]
}

@test "feedback: fails gracefully without API key (OSS user)" {
    unset LOA_CONSTRUCTS_API_KEY

    run "$PROJECT_ROOT/.claude/scripts/check-thj-member.sh"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# Git safety tests
# =============================================================================

@test "git-safety: detects template without marker" {
    # Initialize git repo
    git init --quiet "$TEST_TMPDIR"
    cd "$TEST_TMPDIR"

    # Add origin pointing to template
    git remote add origin "https://github.com/0xHoneyJar/loa.git"

    source "$PROJECT_ROOT/.claude/scripts/git-safety.sh"

    run detect_template
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Origin URL match"* ]]
}

@test "git-safety: detects non-template without marker" {
    # Initialize git repo
    git init --quiet "$TEST_TMPDIR"
    cd "$TEST_TMPDIR"

    # Add origin pointing to different repo
    git remote add origin "https://github.com/example/my-project.git"

    source "$PROJECT_ROOT/.claude/scripts/git-safety.sh"

    run detect_template
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Edge cases
# =============================================================================

@test "old marker ignored when present - THJ detection uses API key" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    # Create old marker saying THJ
    cat > "$TEST_TMPDIR/.loa-setup-complete" << 'EOF'
{
  "user_type": "thj",
  "detected": true
}
EOF

    # But no API key = OSS
    unset LOA_CONSTRUCTS_API_KEY

    result=$(get_user_type)
    [[ "$result" == "oss" ]]
}

@test "old marker ignored - OSS marker but API key present = THJ" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    # Create old marker saying OSS
    cat > "$TEST_TMPDIR/.loa-setup-complete" << 'EOF'
{
  "user_type": "oss",
  "detected": false
}
EOF

    # But API key present = THJ
    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    result=$(get_user_type)
    [[ "$result" == "thj" ]]
}

@test "preflight: check_user_is_thj ignores marker file" {
    source "$PROJECT_ROOT/.claude/scripts/preflight.sh"

    # Create old marker
    cat > "$TEST_TMPDIR/.loa-setup-complete" << 'EOF'
{
  "user_type": "thj"
}
EOF

    # No API key = not THJ
    unset LOA_CONSTRUCTS_API_KEY

    run check_user_is_thj
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# Workflow simulation tests
# =============================================================================

@test "fresh clone workflow: can start plan immediately" {
    # Simulate fresh clone - no setup, no marker, no grimoires
    rm -rf "$TEST_TMPDIR/grimoires"
    rm -f "$TEST_TMPDIR/.loa-setup-complete"

    # Plan phase should work
    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase plan
    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

@test "THJ workflow: API key enables full access" {
    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    # Check THJ detection
    run "$PROJECT_ROOT/.claude/scripts/check-thj-member.sh"
    [[ "$status" -eq 0 ]]

    # Check analytics tracking enabled
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"
    run should_track_analytics
    [[ "$status" -eq 0 ]]
}

@test "OSS workflow: works without API key" {
    unset LOA_CONSTRUCTS_API_KEY

    # Plan phase works
    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase plan
    [[ "$status" -eq 0 ]]

    # Analytics not tracked
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"
    run should_track_analytics
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# Deploy phase tests
# =============================================================================

@test "deploy: works without .loa-setup-complete (needs prd, sdd)" {
    # Create PRD and SDD
    cat > "$TEST_TMPDIR/grimoires/loa/prd.md" << 'EOF'
# Product Requirements Document
Test PRD content
EOF
    cat > "$TEST_TMPDIR/grimoires/loa/sdd.md" << 'EOF'
# Software Design Document
Test SDD content
EOF

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase deploy
    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}
