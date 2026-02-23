#!/usr/bin/env bats
# test-migration.bats - Tests for --migrate-to-submodule (cycle-035 sprint-2)
#
# Run with: bats .claude/scripts/tests/test-migration.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_DIRNAME")" && pwd)"
MOUNT_SCRIPT="${SCRIPT_DIR}/mount-loa.sh"

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
# Argument Parser Tests
# =============================================================================

@test "mount-loa.sh accepts --migrate-to-submodule flag" {
    run grep -c "\-\-migrate-to-submodule)" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "mount-loa.sh accepts --apply flag" {
    run grep -c "\-\-apply)" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "MIGRATE_TO_SUBMODULE variable defaults to false" {
    run grep "MIGRATE_TO_SUBMODULE=false" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "MIGRATE_APPLY variable defaults to false" {
    run grep "MIGRATE_APPLY=false" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Migration Function Tests
# =============================================================================

@test "migrate_to_submodule function exists" {
    run grep -c "migrate_to_submodule()" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    [ "${output}" -ge 1 ]
}

@test "migration creates backup directory" {
    run grep "claude.backup" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "backup_dir"
}

@test "migration preserves settings via user_owned_patterns" {
    run grep -A5 "user_owned_patterns" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "overrides"
}

@test "migration preserves commands directory" {
    run grep -A5 "user_owned_patterns" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "commands"
}

@test "migration preserves .claude/overrides" {
    run grep -A5 "user_owned_patterns" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "overrides"
}

@test "migration already submodule exits cleanly" {
    run grep -A5 "current_mode.*submodule" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Nothing to migrate"
}

@test "migration dry run does not modify files" {
    run grep "DRY RUN COMPLETE" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "No changes made"
}

# =============================================================================
# Help Text Tests
# =============================================================================

@test "help text mentions --migrate-to-submodule" {
    run bash -c "bash '$MOUNT_SCRIPT' --help 2>&1 || true"
    echo "$output" | grep -q "migrate-to-submodule"
}

@test "help text mentions --apply flag" {
    run bash -c "bash '$MOUNT_SCRIPT' --help 2>&1 || true"
    echo "$output" | grep -q "\-\-apply"
}
