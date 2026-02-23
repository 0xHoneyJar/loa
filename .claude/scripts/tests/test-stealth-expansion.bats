#!/usr/bin/env bats
# test-stealth-expansion.bats - Tests for apply_stealth() expansion (cycle-035 sprint-2)
#
# Run with: bats .claude/scripts/tests/test-stealth-expansion.bats

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
# Core Entries (4)
# =============================================================================

@test "stealth has core entry: grimoires/loa/" {
    run grep -A20 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q "grimoires/loa/"
}

@test "stealth has core entry: .beads/" {
    run grep -A20 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q '\.beads/'
}

@test "stealth has core entry: .loa-version.json" {
    run grep -A20 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q '\.loa-version\.json'
}

@test "stealth has core entry: .loa.config.yaml" {
    run grep -A20 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q '\.loa\.config\.yaml'
}

# =============================================================================
# Doc Entries (10)
# =============================================================================

@test "stealth has doc entry: PROCESS.md" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q 'PROCESS\.md'
}

@test "stealth has doc entry: CHANGELOG.md" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q 'CHANGELOG\.md'
}

@test "stealth has doc entry: INSTALLATION.md" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q 'INSTALLATION\.md'
}

@test "stealth has doc entry: CONTRIBUTING.md" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q 'CONTRIBUTING\.md'
}

@test "stealth has doc entry: SECURITY.md" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q 'SECURITY\.md'
}

@test "stealth has doc entry: LICENSE.md" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q 'LICENSE\.md'
}

@test "stealth has doc entry: BUTTERFREEZONE.md" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q 'BUTTERFREEZONE\.md'
}

@test "stealth has doc entry: .reviewignore" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q '\.reviewignore'
}

@test "stealth has doc entry: .trufflehog.yaml" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q '\.trufflehog\.yaml'
}

@test "stealth has doc entry: .gitleaksignore" {
    run grep -A30 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q '\.gitleaksignore'
}

# =============================================================================
# Idempotency
# =============================================================================

@test "stealth uses grep -qxF for idempotent append" {
    run grep "grep -qxF" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
}

@test "stealth reports total entry count in log" {
    run grep -A40 "apply_stealth()" "$MOUNT_SCRIPT"
    echo "$output" | grep -q "entries"
}

# =============================================================================
# Standard mode does not add doc entries
# =============================================================================

@test "standard mode skips stealth application" {
    run grep -B5 -A5 "mode.*stealth" "$MOUNT_SCRIPT"
    [ "$status" -eq 0 ]
    # Stealth only applies when mode is "stealth"
    echo "$output" | grep -q 'mode.*==.*stealth'
}
