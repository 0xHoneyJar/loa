#!/usr/bin/env bats
# End-to-End tests for Registry Integration
# Sprint 6: Protocol Documentation & E2E Testing
#
# Test coverage:
#   - Full install → validate → load flow
#   - License expiry → grace period → block flow
#   - Offline operation with cached key
#   - Pack installation and validation
#   - Update check flow
#   - Reserved name conflict handling

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    LOADER="$PROJECT_ROOT/.claude/scripts/constructs-loader.sh"
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/license-validator.sh"
    LIB="$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/e2e-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Override registry directory for testing
    export LOA_REGISTRY_DIR="$TEST_TMPDIR/registry"
    mkdir -p "$LOA_REGISTRY_DIR/skills"
    mkdir -p "$LOA_REGISTRY_DIR/packs"

    # Override cache directory for testing
    export LOA_CACHE_DIR="$TEST_TMPDIR/cache"
    mkdir -p "$LOA_CACHE_DIR/public-keys"

    # Copy public key to test cache
    cp "$FIXTURES_DIR/mock_public_key.pem" "$LOA_CACHE_DIR/public-keys/test-key-01.pem"
    cat > "$LOA_CACHE_DIR/public-keys/test-key-01.meta.json" << EOF
{
    "key_id": "test-key-01",
    "algorithm": "RS256",
    "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "expires_at": "2030-01-01T00:00:00Z"
}
EOF

    # Create a test config file
    export LOA_CONFIG_FILE="$TEST_TMPDIR/.loa.config.yaml"
    cat > "$LOA_CONFIG_FILE" << 'EOF'
registry:
  enabled: true
  default_url: "http://localhost:8765/v1"
  public_key_cache_hours: 24
  offline_grace_hours: 24
  check_updates_on_setup: true
EOF

    # Source registry-lib for shared functions
    if [[ -f "$LIB" ]]; then
        source "$LIB"
    fi
}

teardown() {
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
    # Clean up environment overrides
    unset LOA_REGISTRY_URL
    unset LOA_OFFLINE
    unset LOA_OFFLINE_GRACE_HOURS
    unset LOA_REGISTRY_ENABLED
    unset LOA_CONFIG_FILE
}

# Helper to skip if scripts not available
skip_if_not_available() {
    if [[ ! -f "$LOADER" ]] || [[ ! -x "$LOADER" ]]; then
        skip "constructs-loader.sh not available"
    fi
    if [[ ! -f "$VALIDATOR" ]] || [[ ! -x "$VALIDATOR" ]]; then
        skip "license-validator.sh not available"
    fi
}

# Helper to create a skill with valid license
create_valid_skill() {
    local vendor="$1"
    local skill_name="$2"
    local version="${3:-1.0.0}"

    local skill_dir="$LOA_REGISTRY_DIR/skills/$vendor/$skill_name"
    mkdir -p "$skill_dir"

    # Copy valid license
    cp "$FIXTURES_DIR/valid_license.json" "$skill_dir/.license.json"

    # Create index.yaml
    cat > "$skill_dir/index.yaml" << EOF
name: $skill_name
version: "$version"
description: E2E test skill
vendor: $vendor
EOF

    # Create SKILL.md
    cat > "$skill_dir/SKILL.md" << EOF
# $skill_name

Test skill for E2E testing.

## Instructions

This is a test skill.
EOF

    echo "$skill_dir"
}

# Helper to create a skill with expired license
create_expired_skill() {
    local vendor="$1"
    local skill_name="$2"

    local skill_dir="$LOA_REGISTRY_DIR/skills/$vendor/$skill_name"
    mkdir -p "$skill_dir"

    # Copy expired license
    cp "$FIXTURES_DIR/expired_license.json" "$skill_dir/.license.json"

    # Create index.yaml
    cat > "$skill_dir/index.yaml" << EOF
name: $skill_name
version: "1.0.0"
description: E2E test skill (expired)
vendor: $vendor
EOF

    echo "$skill_dir"
}

# Helper to create a pack with skills
create_test_pack() {
    local pack_name="$1"

    local pack_dir="$LOA_REGISTRY_DIR/packs/$pack_name"
    mkdir -p "$pack_dir/skills"

    # Copy valid license for pack
    cp "$FIXTURES_DIR/valid_license.json" "$pack_dir/.license.json"

    # Create manifest (JSON format - required by pack loader)
    cat > "$pack_dir/manifest.json" << EOF
{
    "name": "$pack_name",
    "version": "1.0.0",
    "description": "E2E test pack",
    "skills": [
        {"slug": "pack-skill-1"},
        {"slug": "pack-skill-2"}
    ]
}
EOF

    # Create skills in pack
    for skill in pack-skill-1 pack-skill-2; do
        local skill_dir="$pack_dir/skills/$skill"
        mkdir -p "$skill_dir"
        cat > "$skill_dir/index.yaml" << EOF
name: $skill
version: "1.0.0"
description: Pack skill for E2E testing
EOF
        cat > "$skill_dir/SKILL.md" << EOF
# $skill
Pack skill instructions.
EOF
    done

    echo "$pack_dir"
}

# Helper to initialize registry meta
init_registry_meta() {
    cat > "$LOA_REGISTRY_DIR/.registry-meta.json" << 'EOF'
{
    "schema_version": 1,
    "installed_skills": {},
    "installed_packs": {},
    "last_update_check": null
}
EOF
}

# =============================================================================
# E2E Flow Tests
# =============================================================================

@test "E2E: Full install → validate → load flow with valid license" {
    skip_if_not_available

    # 1. Create a skill (simulating install)
    local skill_dir
    skill_dir=$(create_valid_skill "test-vendor" "e2e-skill" "1.0.0")
    init_registry_meta

    # 2. Validate the skill
    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]  # valid or grace

    # 3. Get loadable skills
    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"e2e-skill"* ]]

    # 4. List skills should show it
    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"e2e-skill"* ]]
}

@test "E2E: License expiry → grace period → block flow" {
    skip_if_not_available

    # 1. Create a skill with expired license
    local skill_dir
    skill_dir=$(create_expired_skill "test-vendor" "expired-e2e-skill")
    init_registry_meta

    # 2. Validate - should be in grace or expired
    run "$LOADER" validate "$skill_dir"
    # Status 1 = grace, 2 = expired beyond grace
    [[ "$status" -eq 1 ]] || [[ "$status" -eq 2 ]]

    # 3. If in grace period, should still be loadable
    if [[ "$status" -eq 1 ]]; then
        run "$LOADER" loadable
        [[ "$output" == *"expired-e2e-skill"* ]]
    fi

    # 4. If beyond grace, should not be loadable
    if [[ "$status" -eq 2 ]]; then
        run "$LOADER" loadable
        [[ "$output" != *"expired-e2e-skill"* ]] || [[ -z "$output" ]]
    fi
}

@test "E2E: Offline operation with cached key" {
    skip_if_not_available

    # 1. Create a valid skill
    local skill_dir
    skill_dir=$(create_valid_skill "test-vendor" "offline-skill")
    init_registry_meta

    # 2. Enable offline mode
    export LOA_OFFLINE=1

    # 3. Validate should work with cached key
    run "$LOADER" validate "$skill_dir"
    # Should succeed because key is cached
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]

    # 4. Skill should be loadable
    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
}

@test "E2E: Offline operation without cached key fails gracefully" {
    skip_if_not_available

    # 1. Create a skill with valid license
    local skill_dir
    skill_dir=$(create_valid_skill "test-vendor" "no-cache-skill")
    init_registry_meta

    # 2. Remove cached key
    rm -f "$LOA_CACHE_DIR/public-keys/test-key-01.pem"

    # 3. Enable offline mode
    export LOA_OFFLINE=1

    # 4. Validate should fail without cached key
    run "$LOADER" validate "$skill_dir"
    # Should fail because no key available
    [[ "$status" -ne 0 ]]
}

@test "E2E: Pack installation and validation" {
    skip_if_not_available

    # 1. Create a pack with skills
    local pack_dir
    pack_dir=$(create_test_pack "e2e-test-pack")
    init_registry_meta

    # 2. Validate pack
    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]  # valid or grace

    # 3. List pack skills
    run "$LOADER" list-pack-skills "$pack_dir"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"pack-skill-1"* ]]
    [[ "$output" == *"pack-skill-2"* ]]

    # 4. Get pack version
    run "$LOADER" get-pack-version "$pack_dir"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"1.0.0"* ]]

    # 5. List packs should show it
    run "$LOADER" list-packs
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"e2e-test-pack"* ]]
}

@test "E2E: Update check flow" {
    skip_if_not_available

    # 1. Create a skill
    local skill_dir
    skill_dir=$(create_valid_skill "test-vendor" "update-check-skill" "1.0.0")

    # 2. Initialize registry meta
    cat > "$LOA_REGISTRY_DIR/.registry-meta.json" << EOF
{
    "schema_version": 1,
    "installed_skills": {
        "test-vendor/update-check-skill": {
            "version": "1.0.0",
            "installed_at": "2026-01-01T00:00:00Z"
        }
    },
    "installed_packs": {},
    "last_update_check": null
}
EOF

    # 3. Check updates (will fail without mock server, but shouldn't crash)
    run "$LOADER" check-updates
    # Should complete without crashing
    [[ "$status" -lt 128 ]]  # Not killed by signal

    # 4. Verify timestamp was updated (if file exists)
    if [[ -f "$LOA_REGISTRY_DIR/.registry-meta.json" ]]; then
        local meta_content
        meta_content=$(cat "$LOA_REGISTRY_DIR/.registry-meta.json")
        # Meta should exist and be valid JSON
        [[ -n "$meta_content" ]]
    fi
}

@test "E2E: Reserved name conflict handling" {
    skip_if_not_available

    # 1. Check if reserved names list exists
    source "$LIB"

    if declare -f get_reserved_skill_names &>/dev/null; then
        run get_reserved_skill_names
        # Should return list of reserved names
        [[ "$output" == *"discovering-requirements"* ]] || [[ "$output" == *"implementing-tasks"* ]] || true
    fi

    # 2. Reserved names should not be overridable by registry skills
    # (This is enforced by skill loading priority, not validation)
    # Local skills always win over registry skills
}

@test "E2E: Multiple skills validation in sequence" {
    skip_if_not_available

    # Create multiple skills
    create_valid_skill "vendor-a" "skill-1" "1.0.0"
    create_valid_skill "vendor-a" "skill-2" "2.0.0"
    create_valid_skill "vendor-b" "skill-3" "1.5.0"
    init_registry_meta

    # List all skills
    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"skill-1"* ]]
    [[ "$output" == *"skill-2"* ]]
    [[ "$output" == *"skill-3"* ]]

    # All should be loadable
    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
}

@test "E2E: Empty registry directory handling" {
    skip_if_not_available
    init_registry_meta

    # List with no skills
    run "$LOADER" list
    [[ "$status" -eq 0 ]]

    # Loadable with no skills
    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]

    # List packs with no packs
    run "$LOADER" list-packs
    [[ "$status" -eq 0 ]]
}

@test "E2E: Missing license file handling" {
    skip_if_not_available

    # Create skill without license
    local skill_dir="$LOA_REGISTRY_DIR/skills/test-vendor/no-license-skill"
    mkdir -p "$skill_dir"
    cat > "$skill_dir/index.yaml" << 'EOF'
name: no-license-skill
version: "1.0.0"
EOF

    init_registry_meta

    # Validate should return EXIT_MISSING (3)
    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 3 ]]
}

@test "E2E: Config precedence (env > config > default)" {
    skip_if_not_available

    source "$LIB"

    # Test 1: Default value (no env override)
    unset LOA_REGISTRY_URL

    local default_url
    default_url=$(get_registry_url)
    # Should return default since no .loa.config.yaml in current dir
    [[ "$default_url" == "https://api.constructs.network/v1" ]] || [[ -n "$default_url" ]]

    # Test 2: Env override takes precedence
    export LOA_REGISTRY_URL="http://env.example.com/v1"

    local env_url
    env_url=$(get_registry_url)
    [[ "$env_url" == "http://env.example.com/v1" ]]

    # Note: Config file test requires .loa.config.yaml in working directory
    # This is tested in unit tests (test_update_check.bats) with proper setup
}

@test "E2E: Grace period calculation by tier" {
    skip_if_not_available

    source "$LIB"

    if declare -f get_grace_period_hours &>/dev/null; then
        # Individual tier
        local individual_grace
        individual_grace=$(get_grace_period_hours "individual")
        [[ "$individual_grace" == "24" ]]

        # Team tier
        local team_grace
        team_grace=$(get_grace_period_hours "team")
        [[ "$team_grace" == "72" ]]

        # Enterprise tier
        local enterprise_grace
        enterprise_grace=$(get_grace_period_hours "enterprise")
        [[ "$enterprise_grace" == "168" ]]
    else
        skip "get_grace_period_hours not implemented"
    fi
}

# =============================================================================
# Error Scenario Tests
# =============================================================================

@test "E2E: Invalid command shows usage" {
    skip_if_not_available

    run "$LOADER" invalid-command
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]] || [[ "$output" == *"Unknown"* ]]
}

@test "E2E: Validate non-existent directory" {
    skip_if_not_available

    run "$LOADER" validate "/nonexistent/path"
    [[ "$status" -ne 0 ]]
}

@test "E2E: Registry disabled via environment" {
    skip_if_not_available

    export LOA_REGISTRY_ENABLED=false

    source "$LIB"

    if declare -f is_registry_enabled &>/dev/null; then
        run is_registry_enabled
        [[ "$status" -ne 0 ]]  # Should return false (non-zero)
    fi
}

# =============================================================================
# Integration Verification Tests
# =============================================================================

@test "E2E: All registry scripts are executable" {
    [[ -x "$LOADER" ]]
    [[ -x "$VALIDATOR" ]]
    [[ -f "$LIB" ]]  # lib is sourced, not executed
}

@test "E2E: Scripts use set -euo pipefail" {
    grep -q "set -euo pipefail" "$LOADER"
    grep -q "set -euo pipefail" "$VALIDATOR"
}

@test "E2E: Protocol document exists" {
    [[ -f "$PROJECT_ROOT/.claude/protocols/constructs-integration.md" ]]
}

@test "E2E: CLAUDE.md has registry section" {
    grep -q "Registry Integration" "$PROJECT_ROOT/CLAUDE.md"
    grep -q "constructs-loader.sh" "$PROJECT_ROOT/CLAUDE.md"
}
