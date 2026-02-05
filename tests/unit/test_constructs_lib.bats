#!/usr/bin/env bats
# Unit tests for .claude/scripts/constructs-lib.sh
# Test-first development: These tests define expected behavior

# Test setup
setup() {
    # Get absolute paths
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"

    # Source the library (will fail until implemented)
    if [[ -f "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh" ]]; then
        source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"
    fi

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/registry-lib-test-$$"
    mkdir -p "$TEST_TMPDIR"

    # Create minimal test config
    export TEST_CONFIG="$TEST_TMPDIR/.loa.config.yaml"
    cat > "$TEST_CONFIG" << 'EOF'
registry:
  enabled: true
  default_url: "https://api.constructs.network/v1"
  public_key_cache_hours: 24
  load_on_startup: true
  validate_licenses: true
  offline_grace_hours: 24
  auto_refresh_threshold_hours: 24
  check_updates_on_setup: true
  reserved_skill_names:
    - discovering-requirements
    - designing-architecture
    - planning-sprints
    - implementing-tasks
    - reviewing-code
    - auditing-security
    - deploying-infrastructure
    - riding-codebase
    - mounting-framework
    - translating-for-executives
EOF

    # Set working directory to temp for config tests
    cd "$TEST_TMPDIR"

    # Config is already at .loa.config.yaml in TEST_TMPDIR (written above)
}

teardown() {
    # Clean up temp directory
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Configuration Functions
# =============================================================================

@test "get_registry_config returns value from config file" {
    skip_if_not_implemented

    result=$(get_registry_config "enabled" "false")
    [[ "$result" == "true" ]]
}

@test "get_registry_config returns default when key missing" {
    skip_if_not_implemented

    result=$(get_registry_config "nonexistent_key" "default_value")
    [[ "$result" == "default_value" ]]
}

@test "get_registry_config reads default_url correctly" {
    skip_if_not_implemented

    result=$(get_registry_config "default_url" "")
    [[ "$result" == "https://api.constructs.network/v1" ]]
}

@test "get_registry_config reads public_key_cache_hours as number" {
    skip_if_not_implemented

    result=$(get_registry_config "public_key_cache_hours" "12")
    [[ "$result" == "24" ]]
}

@test "get_registry_url returns config value by default" {
    skip_if_not_implemented

    unset LOA_REGISTRY_URL
    result=$(get_registry_url)
    [[ "$result" == "https://api.constructs.network/v1" ]]
}

@test "get_registry_url respects LOA_REGISTRY_URL environment variable" {
    skip_if_not_implemented

    export LOA_REGISTRY_URL="http://localhost:8765/v1"
    result=$(get_registry_url)
    [[ "$result" == "http://localhost:8765/v1" ]]
}

# =============================================================================
# Directory Functions
# =============================================================================

@test "get_registry_skills_dir returns correct path" {
    skip_if_not_implemented

    result=$(get_registry_skills_dir)
    [[ "$result" == ".claude/registry/skills" ]]
}

@test "get_registry_packs_dir returns correct path" {
    skip_if_not_implemented

    result=$(get_registry_packs_dir)
    [[ "$result" == ".claude/registry/packs" ]]
}

@test "get_cache_dir returns path under HOME/.loa" {
    skip_if_not_implemented

    result=$(get_cache_dir)
    [[ "$result" == "$HOME/.loa/cache" ]]
}

# =============================================================================
# Date Handling (Critical for cross-platform compatibility)
# =============================================================================

@test "parse_iso_date converts ISO 8601 to Unix timestamp" {
    skip_if_not_implemented

    # Use a known date: 2025-01-15T12:00:00Z = 1736942400
    result=$(parse_iso_date "2025-01-15T12:00:00Z")

    # Allow small variance for timezone handling
    [[ "$result" -ge 1736935200 ]] && [[ "$result" -le 1736949600 ]]
}

@test "parse_iso_date handles dates without Z suffix" {
    skip_if_not_implemented

    result=$(parse_iso_date "2025-01-15T12:00:00")

    # Should still parse successfully
    [[ "$result" -gt 0 ]]
}

@test "now_timestamp returns current Unix time" {
    skip_if_not_implemented

    before=$(date +%s)
    result=$(now_timestamp)
    after=$(date +%s)

    # Should be between before and after
    [[ "$result" -ge "$before" ]] && [[ "$result" -le "$after" ]]
}

@test "parse_iso_date handles future dates correctly" {
    skip_if_not_implemented

    # A date in 2026
    result=$(parse_iso_date "2026-06-15T00:00:00Z")

    # Should be in the future (> current time)
    now=$(date +%s)
    [[ "$result" -gt "$now" ]]
}

@test "parse_iso_date handles past dates correctly" {
    skip_if_not_implemented

    # A date in 2020
    result=$(parse_iso_date "2020-01-01T00:00:00Z")

    # Should be in the past (< current time)
    now=$(date +%s)
    [[ "$result" -lt "$now" ]]
}

# =============================================================================
# License Helpers
# =============================================================================

@test "get_license_field extracts expires_at from license file" {
    skip_if_not_implemented

    result=$(get_license_field "$FIXTURES_DIR/valid_license.json" "expires_at")

    # Should be a valid ISO date string
    [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "get_license_field extracts tier from license file" {
    skip_if_not_implemented

    result=$(get_license_field "$FIXTURES_DIR/valid_license.json" "tier")
    [[ "$result" == "pro" ]]
}

@test "get_license_field extracts slug from license file" {
    skip_if_not_implemented

    result=$(get_license_field "$FIXTURES_DIR/valid_license.json" "slug")
    [[ "$result" == "test-vendor/valid-skill" ]]
}

@test "get_license_field extracts token from license file" {
    skip_if_not_implemented

    result=$(get_license_field "$FIXTURES_DIR/valid_license.json" "token")

    # Token should be a JWT (three base64 parts separated by dots)
    [[ "$result" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]
}

@test "get_license_field returns null for missing field" {
    skip_if_not_implemented

    result=$(get_license_field "$FIXTURES_DIR/valid_license.json" "nonexistent_field")
    [[ "$result" == "null" ]]
}

# =============================================================================
# Reserved Skill Names
# =============================================================================

@test "is_reserved_skill_name returns 0 for implementing-tasks" {
    skip_if_not_implemented

    run is_reserved_skill_name "implementing-tasks"
    [[ "$status" -eq 0 ]]
}

@test "is_reserved_skill_name returns 0 for discovering-requirements" {
    skip_if_not_implemented

    run is_reserved_skill_name "discovering-requirements"
    [[ "$status" -eq 0 ]]
}

@test "is_reserved_skill_name returns 0 for auditing-security" {
    skip_if_not_implemented

    run is_reserved_skill_name "auditing-security"
    [[ "$status" -eq 0 ]]
}

@test "is_reserved_skill_name returns non-zero for registry skill" {
    skip_if_not_implemented

    run is_reserved_skill_name "thj/terraform-assistant"
    [[ "$status" -ne 0 ]]
}

@test "is_reserved_skill_name returns non-zero for random name" {
    skip_if_not_implemented

    run is_reserved_skill_name "my-custom-skill"
    [[ "$status" -ne 0 ]]
}

@test "is_reserved_skill_name returns non-zero for empty string" {
    skip_if_not_implemented

    run is_reserved_skill_name ""
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Output Formatting
# =============================================================================

@test "colors are defined when NO_COLOR is not set" {
    skip_if_not_implemented

    unset NO_COLOR
    # Re-source to pick up color settings
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    [[ -n "$RED" ]]
    [[ -n "$GREEN" ]]
    [[ -n "$YELLOW" ]]
    [[ -n "$NC" ]]
}

@test "colors are empty when NO_COLOR is set" {
    skip_if_not_implemented

    export NO_COLOR=1
    # Re-source to pick up color settings
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    [[ -z "$RED" ]]
    [[ -z "$GREEN" ]]
    [[ -z "$YELLOW" ]]
    [[ -z "$NC" ]]
}

@test "status icons are defined" {
    skip_if_not_implemented

    [[ -n "$icon_valid" ]]
    [[ -n "$icon_warning" ]]
    [[ -n "$icon_error" ]]
    [[ -n "$icon_unknown" ]]
}

@test "print_status outputs formatted message" {
    skip_if_not_implemented

    export NO_COLOR=1
    source "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh"

    result=$(print_status "$icon_valid" "Test message")

    # Should contain the message
    [[ "$result" == *"Test message"* ]]
}

# =============================================================================
# Grace Period Calculation
# =============================================================================

@test "get_grace_hours returns 24 for free tier" {
    skip_if_not_implemented

    result=$(get_grace_hours "free")
    [[ "$result" == "24" ]]
}

@test "get_grace_hours returns 24 for pro tier" {
    skip_if_not_implemented

    result=$(get_grace_hours "pro")
    [[ "$result" == "24" ]]
}

@test "get_grace_hours returns 72 for team tier" {
    skip_if_not_implemented

    result=$(get_grace_hours "team")
    [[ "$result" == "72" ]]
}

@test "get_grace_hours returns 168 for enterprise tier" {
    skip_if_not_implemented

    result=$(get_grace_hours "enterprise")
    [[ "$result" == "168" ]]
}

@test "get_grace_hours returns 24 for unknown tier" {
    skip_if_not_implemented

    result=$(get_grace_hours "unknown")
    [[ "$result" == "24" ]]
}

# =============================================================================
# Helper function for skipping tests when lib not implemented
# =============================================================================

skip_if_not_implemented() {
    if [[ ! -f "$PROJECT_ROOT/.claude/scripts/constructs-lib.sh" ]]; then
        skip "constructs-lib.sh not yet implemented"
    fi

    # Check if specific function exists
    if ! type -t get_registry_config &>/dev/null; then
        skip "constructs-lib.sh functions not yet defined"
    fi
}
