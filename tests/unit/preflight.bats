#!/usr/bin/env bats
# Unit tests for .claude/scripts/preflight.sh
# Tests preflight check functions and integrity verification

setup() {
    # Setup test environment
    export PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."
    export TEST_TMPDIR="${BATS_TMPDIR}/preflight-test-$$"
    mkdir -p "${TEST_TMPDIR}"

    # Source the script
    source "${PROJECT_ROOT}/.claude/scripts/preflight.sh"
}

teardown() {
    # Cleanup
    rm -rf "${TEST_TMPDIR}"
}

# =============================================================================
# File Existence Tests
# =============================================================================

@test "check_file_exists returns 0 when file exists" {
    touch "${TEST_TMPDIR}/test-file"
    run check_file_exists "${TEST_TMPDIR}/test-file"
    [ "$status" -eq 0 ]
}

@test "check_file_exists returns 1 when file does not exist" {
    run check_file_exists "${TEST_TMPDIR}/nonexistent-file"
    [ "$status" -eq 1 ]
}

@test "check_file_not_exists returns 0 when file does not exist" {
    run check_file_not_exists "${TEST_TMPDIR}/nonexistent-file"
    [ "$status" -eq 0 ]
}

@test "check_file_not_exists returns 1 when file exists" {
    touch "${TEST_TMPDIR}/test-file"
    run check_file_not_exists "${TEST_TMPDIR}/test-file"
    [ "$status" -eq 1 ]
}

@test "check_directory_exists returns 0 when directory exists" {
    mkdir -p "${TEST_TMPDIR}/test-dir"
    run check_directory_exists "${TEST_TMPDIR}/test-dir"
    [ "$status" -eq 0 ]
}

@test "check_directory_exists returns 1 when directory does not exist" {
    run check_directory_exists "${TEST_TMPDIR}/nonexistent-dir"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Content Check Tests
# =============================================================================

@test "check_content_contains returns 0 when pattern found" {
    echo "test content with keyword" > "${TEST_TMPDIR}/test-file"
    run check_content_contains "${TEST_TMPDIR}/test-file" "keyword"
    [ "$status" -eq 0 ]
}

@test "check_content_contains returns 1 when pattern not found" {
    echo "test content" > "${TEST_TMPDIR}/test-file"
    run check_content_contains "${TEST_TMPDIR}/test-file" "missing"
    [ "$status" -eq 1 ]
}

@test "check_content_contains handles regex patterns" {
    echo '{"user_type": "thj"}' > "${TEST_TMPDIR}/test-file"
    run check_content_contains "${TEST_TMPDIR}/test-file" '"user_type":\s*"thj"'
    [ "$status" -eq 0 ]
}

@test "check_pattern_match returns 0 when value matches pattern" {
    run check_pattern_match "sprint-5" "^sprint-[0-9]+$"
    [ "$status" -eq 0 ]
}

@test "check_pattern_match returns 1 when value does not match" {
    run check_pattern_match "sprint-abc" "^sprint-[0-9]+$"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Command Check Tests
# =============================================================================

@test "check_command_succeeds returns 0 when command succeeds" {
    run check_command_succeeds "true"
    [ "$status" -eq 0 ]
}

@test "check_command_succeeds returns 1 when command fails" {
    run check_command_succeeds "false"
    [ "$status" -eq 1 ]
}

@test "check_command_succeeds suppresses output" {
    run check_command_succeeds "echo 'test output'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# =============================================================================
# Setup Check Tests
# =============================================================================

@test "check_setup_complete returns 1 when file missing" {
    cd "${TEST_TMPDIR}"
    run check_setup_complete
    [ "$status" -eq 1 ]
}

@test "check_setup_complete returns 0 when file exists" {
    touch "${TEST_TMPDIR}/.loa-setup-complete"
    cd "${TEST_TMPDIR}"
    run check_setup_complete
    [ "$status" -eq 0 ]
}

@test "check_user_is_thj returns 0 when user_type is thj" {
    echo '{"user_type": "thj"}' > "${TEST_TMPDIR}/.loa-setup-complete"
    cd "${TEST_TMPDIR}"
    run check_user_is_thj
    [ "$status" -eq 0 ]
}

@test "check_user_is_thj returns 1 when user_type is not thj" {
    echo '{"user_type": "oss"}' > "${TEST_TMPDIR}/.loa-setup-complete"
    cd "${TEST_TMPDIR}"
    run check_user_is_thj
    [ "$status" -eq 1 ]
}

@test "check_user_is_thj returns 1 when setup not complete" {
    cd "${TEST_TMPDIR}"
    run check_user_is_thj
    [ "$status" -eq 1 ]
}

# =============================================================================
# Sprint ID Tests
# =============================================================================

@test "check_sprint_id_format accepts valid sprint IDs" {
    run check_sprint_id_format "sprint-1"
    [ "$status" -eq 0 ]

    run check_sprint_id_format "sprint-42"
    [ "$status" -eq 0 ]

    run check_sprint_id_format "sprint-999"
    [ "$status" -eq 0 ]
}

@test "check_sprint_id_format rejects invalid sprint IDs" {
    run check_sprint_id_format "sprint-"
    [ "$status" -eq 1 ]

    run check_sprint_id_format "sprint-abc"
    [ "$status" -eq 1 ]

    run check_sprint_id_format "sprint-0"
    [ "$status" -eq 1 ]

    run check_sprint_id_format "Sprint-1"
    [ "$status" -eq 1 ]

    run check_sprint_id_format "1"
    [ "$status" -eq 1 ]
}

@test "check_sprint_directory returns 0 when directory exists" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    cd "${TEST_TMPDIR}"
    run check_sprint_directory "sprint-1"
    [ "$status" -eq 0 ]
}

@test "check_sprint_directory returns 1 when directory missing" {
    cd "${TEST_TMPDIR}"
    run check_sprint_directory "sprint-1"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Sprint Review Tests
# =============================================================================

@test "check_reviewer_exists returns 0 when reviewer.md exists" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    touch "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1/reviewer.md"
    cd "${TEST_TMPDIR}"
    run check_reviewer_exists "sprint-1"
    [ "$status" -eq 0 ]
}

@test "check_reviewer_exists returns 1 when reviewer.md missing" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    cd "${TEST_TMPDIR}"
    run check_reviewer_exists "sprint-1"
    [ "$status" -eq 1 ]
}

@test "check_sprint_approved returns 0 when feedback says 'All good'" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    echo "All good" > "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1/engineer-feedback.md"
    cd "${TEST_TMPDIR}"
    run check_sprint_approved "sprint-1"
    [ "$status" -eq 0 ]
}

@test "check_sprint_approved returns 1 when feedback has issues" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    echo "Need to fix bugs" > "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1/engineer-feedback.md"
    cd "${TEST_TMPDIR}"
    run check_sprint_approved "sprint-1"
    [ "$status" -eq 1 ]
}

@test "check_sprint_approved returns 1 when feedback file missing" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    cd "${TEST_TMPDIR}"
    run check_sprint_approved "sprint-1"
    [ "$status" -eq 1 ]
}

@test "check_sprint_completed returns 0 when COMPLETED marker exists" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    touch "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1/COMPLETED"
    cd "${TEST_TMPDIR}"
    run check_sprint_completed "sprint-1"
    [ "$status" -eq 0 ]
}

@test "check_sprint_completed returns 1 when COMPLETED marker missing" {
    mkdir -p "${TEST_TMPDIR}/loa-grimoire/a2a/sprint-1"
    cd "${TEST_TMPDIR}"
    run check_sprint_completed "sprint-1"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Git Tests
# =============================================================================

@test "check_git_clean returns 0 when working tree is clean" {
    skip "Requires git repository setup"
}

@test "check_git_clean returns 1 when working tree has changes" {
    skip "Requires git repository setup"
}
