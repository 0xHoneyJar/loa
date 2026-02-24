#!/usr/bin/env bats
# test-mount-submodule-default.bats - Tests for submodule-first default (cycle-035)
#
# Run with: bats .claude/scripts/tests/test-mount-submodule-default.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
MOUNT_SCRIPT="${SCRIPT_DIR}/mount-loa.sh"
SUBMODULE_SCRIPT="${SCRIPT_DIR}/mount-submodule.sh"

setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    git init --quiet
    git config user.email "test@test.com"
    git config user.name "Test"
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Task 1.1: Default is submodule
# =============================================================================

@test "SUBMODULE_MODE defaults to true in mount-loa.sh" {
    run grep -c "^SUBMODULE_MODE=true" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "mount-loa.sh does not have SUBMODULE_MODE=false as default" {
    # Only check the variable initialization, not flag handling
    run bash -c "head -200 '$MOUNT_SCRIPT' | grep -c 'SUBMODULE_MODE=false'"
    [ "$output" = "0" ]
}

# =============================================================================
# Task 1.2: --vendored flag and --submodule deprecation
# =============================================================================

@test "--vendored flag exists in argument parser" {
    run grep -c -- "--vendored)" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "--vendored sets SUBMODULE_MODE=false" {
    run grep -A2 -- "--vendored)" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "SUBMODULE_MODE=false"
}

@test "--submodule shows deprecation warning" {
    run grep -A3 -- "--submodule)" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "deprecated"
}

@test "help text shows submodule as default" {
    run bash -c "bash '$MOUNT_SCRIPT' --help 2>&1 || true"
    echo "$output" | grep -q "Submodule mode"
    echo "$output" | grep -qi "default"
}

@test "help text shows vendored as opt-in" {
    run bash -c "bash '$MOUNT_SCRIPT' --help 2>&1 || true"
    echo "$output" | grep -q "\-\-vendored"
}

# =============================================================================
# Task 1.3: Mode conflict messages updated
# =============================================================================

@test "mode conflict standard-to-sub mentions migration" {
    run grep -A5 "standard.*Cannot switch" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "migrate"
}

@test "mode conflict sub-to-vendored mentions --vendored" {
    run grep -A5 "submodule.*Cannot switch" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "\-\-vendored"
}

# =============================================================================
# Task 1.4: Graceful degradation preflight
# =============================================================================

@test "preflight_submodule_environment function exists" {
    run grep -c "preflight_submodule_environment()" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "preflight checks for git availability" {
    run grep -A50 "preflight_submodule_environment()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q "git_not_available"
}

@test "preflight checks for symlink support" {
    run grep -A50 "preflight_submodule_environment()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q "symlinks_not_supported"
}

@test "mount lock file mechanism exists" {
    run grep -c "MOUNT_LOCK_FILE" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "CI guard checks for uninitialized submodule" {
    run grep -A80 "preflight_submodule_environment()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q "CI"
    echo "$output" | grep -q "submodule update"
}

@test "fallback reason is recorded in version file" {
    run grep -c "record_fallback_reason" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

# =============================================================================
# Task 1.5: Missing symlinks in mount-submodule.sh
# =============================================================================

@test "manifest includes hooks directory" {
    local manifest_lib="${SCRIPT_DIR}/lib/symlink-manifest.sh"
    run grep "hooks" "$manifest_lib"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q ".claude/hooks"
}

@test "manifest includes data directory" {
    local manifest_lib="${SCRIPT_DIR}/lib/symlink-manifest.sh"
    run grep "data" "$manifest_lib"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q ".claude/data"
}

@test "manifest includes loa/reference directory" {
    local manifest_lib="${SCRIPT_DIR}/lib/symlink-manifest.sh"
    run grep "reference" "$manifest_lib"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "reference"
}

@test "manifest includes loa/learnings directory" {
    local manifest_lib="${SCRIPT_DIR}/lib/symlink-manifest.sh"
    run grep "learnings" "$manifest_lib"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "learnings"
}

@test "manifest includes feedback-ontology.yaml" {
    local manifest_lib="${SCRIPT_DIR}/lib/symlink-manifest.sh"
    run grep "feedback-ontology" "$manifest_lib"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "feedback-ontology"
}

@test "create_symlinks calls safe_symlink in loop" {
    # Verify create_symlinks iterates the manifest and calls safe_symlink
    run grep -A30 "create_symlinks()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q "get_symlink_manifest"
    echo "$output" | grep -q "safe_symlink"
}

@test "Memory Stack relocation function exists" {
    run grep -c "relocate_memory_stack()" "$SUBMODULE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "auto_init_submodule function exists" {
    run grep -c "auto_init_submodule()" "$SUBMODULE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "Memory Stack relocation uses copy-then-verify pattern" {
    run grep -A60 "relocate_memory_stack()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q "cp -r"
    echo "$output" | grep -q "source_count"
    echo "$output" | grep -q "target_count"
}

# =============================================================================
# Task 1.6: .gitignore fixes
# =============================================================================

@test ".gitignore has .loa-state/ not .loa/" {
    local gitignore="${SCRIPT_DIR}/../../.gitignore"
    run grep "^\.loa-state/" "$gitignore"
    [ "$status" -eq 0 ]
}

@test ".gitignore does not ignore .loa/ directory" {
    local gitignore="${SCRIPT_DIR}/../../.gitignore"
    # Should NOT have a bare .loa/ entry (submodule must be tracked)
    run bash -c "grep '^\.loa/$' '$gitignore' | wc -l"
    [ "$output" = "0" ]
}

@test "mount-submodule.sh has update_gitignore_for_submodule function" {
    run grep -c "update_gitignore_for_submodule()" "$SUBMODULE_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "update_gitignore_for_submodule adds .claude/scripts entry" {
    run grep -A40 "update_gitignore_for_submodule()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q '\.claude/scripts'
}

@test "update_gitignore_for_submodule adds .claude/hooks entry" {
    run grep -A40 "update_gitignore_for_submodule()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q '\.claude/hooks'
}

@test "update_gitignore_for_submodule adds .claude/data entry" {
    run grep -A40 "update_gitignore_for_submodule()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q '\.claude/data'
}

@test "update_gitignore_for_submodule removes .loa/ if present" {
    run grep -A50 "update_gitignore_for_submodule()" "$SUBMODULE_SCRIPT"
    echo "$output" | grep -q "Removed .loa/"
}
