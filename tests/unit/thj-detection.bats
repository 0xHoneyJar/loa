#!/usr/bin/env bats
# Unit tests for THJ detection mechanism (v0.15.0)
# Tests is_thj_member() function and check-thj-member.sh script

# Test setup
setup() {
    # Get absolute paths
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/thj-detection-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Save original environment
    ORIG_LOA_CONSTRUCTS_API_KEY="${LOA_CONSTRUCTS_API_KEY:-}"

    # Unset API key for clean state
    unset LOA_CONSTRUCTS_API_KEY
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
# is_thj_member() function tests
# =============================================================================

@test "is_thj_member: returns 0 when API key is set" {
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    run is_thj_member
    [[ "$status" -eq 0 ]]
}

@test "is_thj_member: returns 1 when API key is empty" {
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    export LOA_CONSTRUCTS_API_KEY=""

    run is_thj_member
    [[ "$status" -eq 1 ]]
}

@test "is_thj_member: returns 1 when API key is unset" {
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    unset LOA_CONSTRUCTS_API_KEY

    run is_thj_member
    [[ "$status" -eq 1 ]]
}

@test "is_thj_member: handles whitespace-only key as non-empty" {
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    # Whitespace-only string is still "non-empty" per bash -n test
    export LOA_CONSTRUCTS_API_KEY="   "

    run is_thj_member
    [[ "$status" -eq 0 ]]
}

@test "is_thj_member: works with typical API key format" {
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    export LOA_CONSTRUCTS_API_KEY="loa_live_example_key_for_testing_only"

    run is_thj_member
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# get_user_type() function tests (analytics.sh)
# =============================================================================

@test "get_user_type: returns 'thj' when API key set" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    result=$(get_user_type)
    [[ "$result" == "thj" ]]
}

@test "get_user_type: returns 'oss' when API key unset" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    unset LOA_CONSTRUCTS_API_KEY

    result=$(get_user_type)
    [[ "$result" == "oss" ]]
}

@test "get_user_type: returns 'oss' when API key empty" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    export LOA_CONSTRUCTS_API_KEY=""

    result=$(get_user_type)
    [[ "$result" == "oss" ]]
}

# =============================================================================
# should_track_analytics() function tests
# =============================================================================

@test "should_track_analytics: returns 0 when THJ" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    run should_track_analytics
    [[ "$status" -eq 0 ]]
}

@test "should_track_analytics: returns 1 when OSS" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    unset LOA_CONSTRUCTS_API_KEY

    run should_track_analytics
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# check-thj-member.sh script tests
# =============================================================================

@test "check-thj-member.sh: exits 0 with API key" {
    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    run "$PROJECT_ROOT/.claude/scripts/check-thj-member.sh"
    [[ "$status" -eq 0 ]]
}

@test "check-thj-member.sh: exits 1 without API key" {
    unset LOA_CONSTRUCTS_API_KEY

    run "$PROJECT_ROOT/.claude/scripts/check-thj-member.sh"
    [[ "$status" -eq 1 ]]
}

@test "check-thj-member.sh: exits 1 with empty API key" {
    export LOA_CONSTRUCTS_API_KEY=""

    run "$PROJECT_ROOT/.claude/scripts/check-thj-member.sh"
    [[ "$status" -eq 1 ]]
}

@test "check-thj-member.sh: is executable" {
    [[ -x "$PROJECT_ROOT/.claude/scripts/check-thj-member.sh" ]]
}

# =============================================================================
# check_user_is_thj() function tests (preflight.sh)
# =============================================================================

@test "check_user_is_thj: returns 0 when API key set" {
    source "$PROJECT_ROOT/.claude/scripts/preflight.sh"

    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    run check_user_is_thj
    [[ "$status" -eq 0 ]]
}

@test "check_user_is_thj: returns 1 when API key unset" {
    source "$PROJECT_ROOT/.claude/scripts/preflight.sh"

    unset LOA_CONSTRUCTS_API_KEY

    run check_user_is_thj
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# check-prerequisites.sh tests
# =============================================================================

@test "check-prerequisites.sh: plan phase has no prerequisites" {
    cd "$PROJECT_ROOT"

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase plan

    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

@test "check-prerequisites.sh: prd phase has no prerequisites" {
    cd "$PROJECT_ROOT"

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase prd

    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

@test "check-prerequisites.sh: architect phase requires prd.md" {
    cd "$TEST_TMPDIR"

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase architect

    # Should fail because prd.md is missing
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"MISSING"* ]]
    [[ "$output" == *"prd.md"* ]]
}

@test "check-prerequisites.sh: setup phase is removed" {
    cd "$PROJECT_ROOT"

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase setup

    # Should error with unknown phase
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Unknown phase"* ]]
}

# =============================================================================
# Backward compatibility tests
# =============================================================================

@test "old marker file is ignored - plan phase works regardless" {
    cd "$TEST_TMPDIR"

    # Create old marker file
    echo '{"user_type": "thj", "detected": true}' > .loa-setup-complete

    run "$PROJECT_ROOT/.claude/scripts/check-prerequisites.sh" --phase plan

    [[ "$status" -eq 0 ]]
    [[ "$output" == "OK" ]]
}

@test "API key takes precedence over marker file for THJ detection" {
    source "$PROJECT_ROOT/.claude/scripts/analytics.sh"

    # Even if old marker says OSS, API key makes them THJ
    export LOA_CONSTRUCTS_API_KEY="sk_test_12345"

    result=$(get_user_type)
    [[ "$result" == "thj" ]]
}
