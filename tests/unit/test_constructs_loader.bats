#!/usr/bin/env bats
# Unit tests for .claude/scripts/constructs-loader.sh
# Test-first development: These tests define expected behavior
#
# Commands:
#   list - Show all registry skills with status icons
#   loadable - Return paths of valid/grace-period skills
#   validate <dir> - Validate single skill's license
#
# Exit codes for validate:
#   0 = valid
#   1 = expired (in grace period)
#   2 = expired (beyond grace)
#   3 = missing license file
#   4 = invalid signature

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    LOADER="$PROJECT_ROOT/.claude/scripts/constructs-loader.sh"
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/license-validator.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/registry-loader-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Override registry directory for testing
    export LOA_REGISTRY_DIR="$TEST_TMPDIR/registry"
    mkdir -p "$LOA_REGISTRY_DIR/skills"
    mkdir -p "$LOA_REGISTRY_DIR/packs"

    # Override cache directory for testing
    export LOA_CACHE_DIR="$TEST_TMPDIR/cache"
    mkdir -p "$LOA_CACHE_DIR/public-keys"

    # Copy public key to test cache (simulate cached key)
    cp "$FIXTURES_DIR/mock_public_key.pem" "$LOA_CACHE_DIR/public-keys/test-key-01.pem"

    # Create metadata for cached key
    cat > "$LOA_CACHE_DIR/public-keys/test-key-01.meta.json" << EOF
{
    "key_id": "test-key-01",
    "algorithm": "RS256",
    "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "expires_at": "2030-01-01T00:00:00Z"
}
EOF

    # Source registry-lib for shared functions
    if [[ -f "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh" ]]; then
        source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"
    fi
}

teardown() {
    # Clean up temp directory
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Helper to skip if loader not implemented
skip_if_not_implemented() {
    if [[ ! -f "$LOADER" ]]; then
        skip "constructs-loader.sh not yet implemented"
    fi
    if [[ ! -x "$LOADER" ]]; then
        skip "constructs-loader.sh not executable"
    fi
}

# Helper to create a test skill directory
create_test_skill() {
    local vendor="$1"
    local skill_name="$2"
    local license_file="$3"  # Path to fixture license file

    local skill_dir="$LOA_REGISTRY_DIR/skills/$vendor/$skill_name"
    mkdir -p "$skill_dir"

    # Copy license file
    if [[ -n "$license_file" ]] && [[ -f "$license_file" ]]; then
        cp "$license_file" "$skill_dir/.license.json"
    fi

    # Create minimal skill structure
    mkdir -p "$skill_dir/resources"
    cat > "$skill_dir/index.yaml" << EOF
name: $skill_name
version: "1.0.0"
description: Test skill for unit testing
EOF

    cat > "$skill_dir/SKILL.md" << EOF
# $skill_name

Test skill for unit testing.
EOF

    echo "$skill_dir"
}

# =============================================================================
# list Command - Display Registry Skills
# =============================================================================

@test "list returns empty message when no skills installed" {
    skip_if_not_implemented

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No registry skills installed"* ]] || [[ "$output" == *"empty"* ]]
}

@test "list shows valid skill with checkmark" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    # Should show checkmark (✓ or similar) and skill name
    [[ "$output" == *"valid-skill"* ]]
    [[ "$output" == *"✓"* ]] || [[ "$output" == *"[valid]"* ]] || [[ "$output" == *"VALID"* ]]
}

@test "list shows grace period skill with warning" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    # Should show warning indicator and skill name
    [[ "$output" == *"grace-skill"* ]]
    [[ "$output" == *"⚠"* ]] || [[ "$output" == *"grace"* ]] || [[ "$output" == *"WARNING"* ]]
}

@test "list shows expired skill with X" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "expired-skill" "$FIXTURES_DIR/expired_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    # Should show X indicator and skill name
    [[ "$output" == *"expired-skill"* ]]
    [[ "$output" == *"✗"* ]] || [[ "$output" == *"expired"* ]] || [[ "$output" == *"EXPIRED"* ]]
}

@test "list shows all skills with mixed states" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"
    create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json"
    create_test_skill "test-vendor" "expired-skill" "$FIXTURES_DIR/expired_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"valid-skill"* ]]
    [[ "$output" == *"grace-skill"* ]]
    [[ "$output" == *"expired-skill"* ]]
}

@test "list shows skill without license as unknown" {
    skip_if_not_implemented

    # Create skill without license file
    local skill_dir="$LOA_REGISTRY_DIR/skills/test-vendor/no-license-skill"
    mkdir -p "$skill_dir"
    cat > "$skill_dir/index.yaml" << EOF
name: no-license-skill
version: "1.0.0"
EOF

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"no-license-skill"* ]]
    # Should show unknown indicator (? or similar)
    [[ "$output" == *"?"* ]] || [[ "$output" == *"missing"* ]] || [[ "$output" == *"MISSING"* ]]
}

@test "list filters out reserved skill names" {
    skip_if_not_implemented

    # Create a reserved name skill (should be filtered)
    mkdir -p "$LOA_REGISTRY_DIR/skills/test-vendor/implementing-tasks"
    cat > "$LOA_REGISTRY_DIR/skills/test-vendor/implementing-tasks/index.yaml" << EOF
name: implementing-tasks
version: "1.0.0"
EOF

    # Create a valid non-reserved skill
    create_test_skill "test-vendor" "my-skill" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"my-skill"* ]]
    # Reserved name should NOT appear or should show warning
    [[ "$output" != *"implementing-tasks"* ]] || [[ "$output" == *"reserved"* ]]
}

@test "list respects NO_COLOR environment variable" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"

    export NO_COLOR=1
    run "$LOADER" list

    # Output should not contain ANSI escape codes
    [[ "$output" != *$'\033'* ]] && [[ "$output" != *$'\x1b'* ]]
}

# =============================================================================
# loadable Command - Return Valid Skill Paths
# =============================================================================

@test "loadable returns empty when no skills installed" {
    skip_if_not_implemented

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ -z "$output" ]] || [[ "$output" == "" ]]
}

@test "loadable returns path for valid skill" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"$skill_dir"* ]] || [[ "$output" == *"test-vendor/valid-skill"* ]]
}

@test "loadable returns path for grace period skill" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json")

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    # Grace period skills are still loadable
    [[ "$output" == *"$skill_dir"* ]] || [[ "$output" == *"test-vendor/grace-skill"* ]]
}

@test "loadable excludes expired skills" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"
    create_test_skill "test-vendor" "expired-skill" "$FIXTURES_DIR/expired_license.json"

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"valid-skill"* ]]
    [[ "$output" != *"expired-skill"* ]]
}

@test "loadable excludes skills without license" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"

    # Create skill without license
    mkdir -p "$LOA_REGISTRY_DIR/skills/test-vendor/no-license"
    cat > "$LOA_REGISTRY_DIR/skills/test-vendor/no-license/index.yaml" << EOF
name: no-license
version: "1.0.0"
EOF

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"valid-skill"* ]]
    [[ "$output" != *"no-license"* ]]
}

@test "loadable excludes reserved skill names" {
    skip_if_not_implemented

    # Create reserved name skill with valid license
    mkdir -p "$LOA_REGISTRY_DIR/skills/test-vendor/implementing-tasks"
    cp "$FIXTURES_DIR/valid_license.json" "$LOA_REGISTRY_DIR/skills/test-vendor/implementing-tasks/.license.json"

    # Create valid non-reserved skill
    create_test_skill "test-vendor" "my-skill" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"my-skill"* ]]
    [[ "$output" != *"implementing-tasks"* ]]
}

@test "loadable returns multiple paths on separate lines" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "skill-a" "$FIXTURES_DIR/valid_license.json"
    create_test_skill "test-vendor" "skill-b" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]

    # Count lines - should have 2
    local line_count
    line_count=$(echo "$output" | grep -c "skill" || true)
    [[ "$line_count" -ge 2 ]]
}

# =============================================================================
# validate Command - Single Skill Validation
# =============================================================================

@test "validate returns 0 for valid skill" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 0 ]]
}

@test "validate returns 1 for grace period skill" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json")

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 1 ]]
}

@test "validate returns 2 for expired skill" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "expired-skill" "$FIXTURES_DIR/expired_license.json")

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 2 ]]
}

@test "validate returns 3 for missing license file" {
    skip_if_not_implemented

    # Create skill without license
    local skill_dir="$LOA_REGISTRY_DIR/skills/test-vendor/no-license"
    mkdir -p "$skill_dir"

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 3 ]]
}

@test "validate returns 4 for invalid signature" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "invalid-sig" "$FIXTURES_DIR/invalid_signature_license.json")

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 4 ]]
}

@test "validate returns error for nonexistent directory" {
    skip_if_not_implemented

    run "$LOADER" validate "$TEST_TMPDIR/nonexistent"
    [[ "$status" -ne 0 ]]
}

@test "validate delegates to license-validator" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json")

    # Both should return the same result
    run "$LOADER" validate "$skill_dir"
    local loader_status=$status

    run "$VALIDATOR" validate "$skill_dir/.license.json"
    local validator_status=$status

    [[ "$loader_status" -eq "$validator_status" ]]
}

# =============================================================================
# Error Handling
# =============================================================================

@test "displays usage when no arguments" {
    skip_if_not_implemented

    run "$LOADER"
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "displays usage for unknown command" {
    skip_if_not_implemented

    run "$LOADER" unknown-command
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "handles missing registry directory gracefully" {
    skip_if_not_implemented

    rm -rf "$LOA_REGISTRY_DIR"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No registry"* ]] || [[ "$output" == *"empty"* ]] || [[ "$output" == *"not found"* ]]
}

# =============================================================================
# Output Formatting
# =============================================================================

@test "list output includes version when available" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    # Should show version from license or index.yaml
    [[ "$output" == *"1.0.0"* ]] || [[ "$output" == *"version"* ]]
}

@test "list output shows vendor/skill format" {
    skip_if_not_implemented

    create_test_skill "acme-corp" "super-skill" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    # Should show in vendor/skill format
    [[ "$output" == *"acme-corp/super-skill"* ]] || [[ "$output" == *"acme-corp"* ]]
}
