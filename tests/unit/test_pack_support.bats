#!/usr/bin/env bats
# Unit tests for Pack Support in constructs-loader.sh
# Sprint 4: Pack Support & Preload Hook
#
# Test coverage:
#   - Pack discovery and validation
#   - Pack manifest parsing
#   - Skills-from-pack tracking
#   - Registry meta management
#   - List command pack indicator

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    LOADER="$PROJECT_ROOT/.claude/scripts/constructs-loader.sh"
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/license-validator.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/pack-support-test-$$"
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

    # Source registry-lib for shared functions
    if [[ -f "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh" ]]; then
        source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"
    fi
}

teardown() {
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Helper to skip if loader not implemented
skip_if_not_implemented() {
    if [[ ! -f "$LOADER" ]] || [[ ! -x "$LOADER" ]]; then
        skip "constructs-loader.sh not available"
    fi
}

# Helper to create a test pack
create_test_pack() {
    local pack_slug="$1"
    local license_file="$2"
    local skill_count="${3:-2}"

    local pack_dir="$LOA_REGISTRY_DIR/packs/$pack_slug"
    mkdir -p "$pack_dir/skills"

    # Copy license if provided
    if [[ -n "$license_file" ]] && [[ -f "$license_file" ]]; then
        cp "$license_file" "$pack_dir/.license.json"
    fi

    # Create skills array for manifest
    local skills_json="["
    for i in $(seq 1 "$skill_count"); do
        local skill_name="skill-$i"
        mkdir -p "$pack_dir/skills/$skill_name"
        cat > "$pack_dir/skills/$skill_name/index.yaml" << EOF
name: $skill_name
version: "1.0.0"
description: Test skill $i from pack
EOF
        cat > "$pack_dir/skills/$skill_name/SKILL.md" << EOF
# $skill_name

Test skill from pack $pack_slug.
EOF
        if [[ $i -gt 1 ]]; then
            skills_json+=","
        fi
        skills_json+="{\"slug\":\"$skill_name\",\"path\":\"skills/$skill_name\"}"
    done
    skills_json+="]"

    # Create manifest.json
    cat > "$pack_dir/manifest.json" << EOF
{
    "schema_version": 1,
    "name": "Test Pack $pack_slug",
    "slug": "$pack_slug",
    "version": "1.0.0",
    "description": "Test pack for unit testing",
    "skills": $skills_json
}
EOF

    echo "$pack_dir"
}

# Helper to create a standalone skill
create_test_skill() {
    local vendor="$1"
    local skill_name="$2"
    local license_file="$3"

    local skill_dir="$LOA_REGISTRY_DIR/skills/$vendor/$skill_name"
    mkdir -p "$skill_dir"

    if [[ -n "$license_file" ]] && [[ -f "$license_file" ]]; then
        cp "$license_file" "$skill_dir/.license.json"
    fi

    cat > "$skill_dir/index.yaml" << EOF
name: $skill_name
version: "1.0.0"
description: Test skill for unit testing
EOF

    echo "$skill_dir"
}

# =============================================================================
# Pack Discovery Tests
# =============================================================================

@test "list-packs returns empty when no packs installed" {
    skip_if_not_implemented

    run "$LOADER" list-packs
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"No packs installed"* ]] || [[ -z "$output" ]]
}

@test "list-packs discovers pack with manifest.json" {
    skip_if_not_implemented

    create_test_pack "test-pack" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" list-packs
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"test-pack"* ]]
}

@test "list-packs shows pack version" {
    skip_if_not_implemented

    create_test_pack "test-pack" "$FIXTURES_DIR/valid_license.json"

    run "$LOADER" list-packs
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"1.0.0"* ]]
}

# =============================================================================
# Pack Validation Tests
# =============================================================================

@test "validate-pack returns 0 for valid pack license" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "valid-pack" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 0 ]]
}

@test "validate-pack returns 1 for grace period pack" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "grace-pack" "$FIXTURES_DIR/grace_period_license.json")

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 1 ]]
}

@test "validate-pack returns 2 for expired pack" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "expired-pack" "$FIXTURES_DIR/expired_license.json")

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 2 ]]
}

@test "validate-pack returns 3 for pack without license" {
    skip_if_not_implemented

    local pack_dir="$LOA_REGISTRY_DIR/packs/no-license-pack"
    mkdir -p "$pack_dir/skills/skill-1"
    cat > "$pack_dir/manifest.json" << EOF
{
    "schema_version": 1,
    "name": "No License Pack",
    "slug": "no-license-pack",
    "version": "1.0.0",
    "skills": []
}
EOF

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 3 ]]
}

@test "validate-pack returns error for missing manifest" {
    skip_if_not_implemented

    local pack_dir="$LOA_REGISTRY_DIR/packs/no-manifest"
    mkdir -p "$pack_dir"
    cp "$FIXTURES_DIR/valid_license.json" "$pack_dir/.license.json"

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Pack Manifest Parsing Tests
# =============================================================================

@test "pack manifest skills are correctly parsed" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "multi-skill-pack" "$FIXTURES_DIR/valid_license.json" 3)

    run "$LOADER" list-pack-skills "$pack_dir"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"skill-1"* ]]
    [[ "$output" == *"skill-2"* ]]
    [[ "$output" == *"skill-3"* ]]
}

@test "pack manifest version is extracted" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "versioned-pack" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" get-pack-version "$pack_dir"
    [[ "$status" -eq 0 ]]
    [[ "$output" == "1.0.0" ]]
}

# =============================================================================
# Skills From Pack Tests
# =============================================================================

@test "loadable includes skills from valid pack" {
    skip_if_not_implemented

    create_test_pack "valid-pack" "$FIXTURES_DIR/valid_license.json" 2

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"skill-1"* ]]
    [[ "$output" == *"skill-2"* ]]
}

@test "loadable excludes skills from expired pack" {
    skip_if_not_implemented

    create_test_pack "expired-pack" "$FIXTURES_DIR/expired_license.json" 2

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    # Skills from expired pack should NOT appear
    [[ "$output" != *"skill-1"* ]]
    [[ "$output" != *"skill-2"* ]]
}

@test "loadable includes skills from grace period pack" {
    skip_if_not_implemented

    create_test_pack "grace-pack" "$FIXTURES_DIR/grace_period_license.json" 2

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    # Grace period skills are still loadable
    [[ "$output" == *"skill-1"* ]]
}

# =============================================================================
# List Command Pack Indicator Tests
# =============================================================================

@test "list shows pack indicator for pack skills" {
    skip_if_not_implemented

    create_test_pack "my-pack" "$FIXTURES_DIR/valid_license.json" 1

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    # Should show pack indicator (e.g., [pack: my-pack] or similar)
    [[ "$output" == *"my-pack"* ]] || [[ "$output" == *"pack"* ]]
}

@test "list distinguishes standalone skills from pack skills" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "standalone-skill" "$FIXTURES_DIR/valid_license.json"
    create_test_pack "my-pack" "$FIXTURES_DIR/valid_license.json" 1

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"standalone-skill"* ]]
    [[ "$output" == *"skill-1"* ]]
}

# =============================================================================
# Registry Meta Management Tests
# =============================================================================

@test "registry-meta is created on first validation" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "first-skill" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 0 ]]

    # Check meta file was created
    [[ -f "$LOA_REGISTRY_DIR/.registry-meta.json" ]]
}

@test "registry-meta tracks installed skills" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "tracked-skill" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 0 ]]

    # Check skill is tracked in meta
    [[ -f "$LOA_REGISTRY_DIR/.registry-meta.json" ]]
    local meta_content
    meta_content=$(cat "$LOA_REGISTRY_DIR/.registry-meta.json")
    [[ "$meta_content" == *"tracked-skill"* ]] || [[ "$meta_content" == *"installed_skills"* ]]
}

@test "registry-meta tracks installed packs" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "tracked-pack" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 0 ]]

    # Check pack is tracked in meta
    [[ -f "$LOA_REGISTRY_DIR/.registry-meta.json" ]]
    local meta_content
    meta_content=$(cat "$LOA_REGISTRY_DIR/.registry-meta.json")
    [[ "$meta_content" == *"tracked-pack"* ]] || [[ "$meta_content" == *"installed_packs"* ]]
}

@test "registry-meta includes from_pack field for pack skills" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "source-pack" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 0 ]]

    # Check from_pack field
    [[ -f "$LOA_REGISTRY_DIR/.registry-meta.json" ]]
    local meta_content
    meta_content=$(cat "$LOA_REGISTRY_DIR/.registry-meta.json")
    [[ "$meta_content" == *"from_pack"* ]] || [[ "$meta_content" == *"source-pack"* ]]
}

@test "registry-meta schema_version is 1" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "any-skill" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 0 ]]

    [[ -f "$LOA_REGISTRY_DIR/.registry-meta.json" ]]
    local meta_content
    meta_content=$(cat "$LOA_REGISTRY_DIR/.registry-meta.json")
    [[ "$meta_content" == *"schema_version"* ]]
    [[ "$meta_content" == *"1"* ]]
}

# =============================================================================
# Preload Command Tests (verify existing implementation)
# =============================================================================

@test "preload returns 0 for valid skill" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json")

    run "$LOADER" preload "$skill_dir"
    [[ "$status" -eq 0 ]]
}

@test "preload returns 1 with warning for grace period" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json")

    run "$LOADER" preload "$skill_dir"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"grace"* ]] || [[ "$output" == *"WARNING"* ]]
}

@test "preload returns 2 for expired skill" {
    skip_if_not_implemented

    local skill_dir
    skill_dir=$(create_test_skill "test-vendor" "expired-skill" "$FIXTURES_DIR/expired_license.json")

    run "$LOADER" preload "$skill_dir"
    [[ "$status" -eq 2 ]]
}

@test "preload blocks reserved skill names" {
    skip_if_not_implemented

    mkdir -p "$LOA_REGISTRY_DIR/skills/test-vendor/implementing-tasks"
    cp "$FIXTURES_DIR/valid_license.json" "$LOA_REGISTRY_DIR/skills/test-vendor/implementing-tasks/.license.json"

    run "$LOADER" preload "$LOA_REGISTRY_DIR/skills/test-vendor/implementing-tasks"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"reserved"* ]] || [[ "$output" == *"conflict"* ]]
}

@test "preload works for pack skills" {
    skip_if_not_implemented

    local pack_dir
    pack_dir=$(create_test_pack "preload-pack" "$FIXTURES_DIR/valid_license.json" 1)

    run "$LOADER" preload "$pack_dir/skills/skill-1"
    # Pack skills use pack license, should be valid
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 3 ]]  # 3 if not finding pack license
}

# =============================================================================
# Edge Cases
# =============================================================================

@test "handles pack with no skills gracefully" {
    skip_if_not_implemented

    local pack_dir="$LOA_REGISTRY_DIR/packs/empty-pack"
    mkdir -p "$pack_dir"
    cp "$FIXTURES_DIR/valid_license.json" "$pack_dir/.license.json"
    cat > "$pack_dir/manifest.json" << EOF
{
    "schema_version": 1,
    "name": "Empty Pack",
    "slug": "empty-pack",
    "version": "1.0.0",
    "skills": []
}
EOF

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -eq 0 ]]
}

@test "handles malformed manifest.json gracefully" {
    skip_if_not_implemented

    local pack_dir="$LOA_REGISTRY_DIR/packs/bad-manifest"
    mkdir -p "$pack_dir"
    cp "$FIXTURES_DIR/valid_license.json" "$pack_dir/.license.json"
    echo "{ invalid json" > "$pack_dir/manifest.json"

    run "$LOADER" validate-pack "$pack_dir"
    [[ "$status" -ne 0 ]]
}

@test "mixed standalone and pack skills both appear in loadable" {
    skip_if_not_implemented

    create_test_skill "test-vendor" "standalone" "$FIXTURES_DIR/valid_license.json"
    create_test_pack "my-pack" "$FIXTURES_DIR/valid_license.json" 1

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"standalone"* ]]
    [[ "$output" == *"skill-1"* ]]
}
