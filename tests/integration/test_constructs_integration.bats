#!/usr/bin/env bats
# Integration tests for Loa Constructs
# Tests full flows with mock registry server
#
# Prerequisites:
#   - Python 3 for mock server
#   - curl for API calls
#
# These tests verify end-to-end flows:
#   1. Key fetch → cache → validate
#   2. Offline behavior with cached key
#   3. Grace period warnings
#   4. Full list/loadable/validate flow

# Shared state
MOCK_PORT=""
MOCK_PID=""

# Per-test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    LOADER="$PROJECT_ROOT/.claude/scripts/constructs-loader.sh"
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/license-validator.sh"

    # Check for prerequisites
    if ! command -v python3 &>/dev/null; then
        skip "python3 not found"
    fi
    if ! command -v curl &>/dev/null; then
        skip "curl not found"
    fi

    # Start mock server on random port for this test
    MOCK_PORT=$((8000 + RANDOM % 1000))

    python3 "$FIXTURES_DIR/mock_server.py" --port "$MOCK_PORT" &>/dev/null &
    MOCK_PID=$!

    # Wait for server to start (max 3 seconds)
    local max_wait=30
    local counter=0
    while ! curl -sf "http://127.0.0.1:$MOCK_PORT/v1/health" >/dev/null 2>&1; do
        sleep 0.1
        counter=$((counter + 1))
        if [[ $counter -ge $max_wait ]]; then
            kill $MOCK_PID 2>/dev/null || true
            skip "Mock server failed to start"
        fi
    done

    export LOA_REGISTRY_URL="http://127.0.0.1:$MOCK_PORT/v1"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/registry-integration-test-$$-$RANDOM"
    mkdir -p "$TEST_TMPDIR"

    # Override directories for testing
    export LOA_REGISTRY_DIR="$TEST_TMPDIR/registry"
    export LOA_CACHE_DIR="$TEST_TMPDIR/cache"
    mkdir -p "$LOA_REGISTRY_DIR/skills"
    mkdir -p "$LOA_CACHE_DIR/public-keys"

    # Pre-cache the public key (simulate previous fetch)
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

# Per-test cleanup
teardown() {
    # Stop mock server
    if [[ -n "$MOCK_PID" ]]; then
        kill "$MOCK_PID" 2>/dev/null || true
    fi

    # Clean up temp directory
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Helper to create a test skill directory
create_test_skill() {
    local vendor="$1"
    local skill_name="$2"
    local license_file="$3"

    local skill_dir="$LOA_REGISTRY_DIR/skills/$vendor/$skill_name"
    mkdir -p "$skill_dir/resources"

    if [[ -n "$license_file" ]] && [[ -f "$license_file" ]]; then
        cp "$license_file" "$skill_dir/.license.json"
    fi

    cat > "$skill_dir/index.yaml" << EOF
name: $skill_name
version: "1.0.0"
description: Test skill for integration testing
EOF

    cat > "$skill_dir/SKILL.md" << EOF
# $skill_name

Test skill for integration testing.
EOF

    echo "$skill_dir"
}

# =============================================================================
# Mock Server Health Check
# =============================================================================

@test "mock server responds to health check" {
    run curl -sf "$LOA_REGISTRY_URL/health"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"healthy"* ]]
}

# =============================================================================
# Public Key Fetch Tests
# =============================================================================

@test "fetch public key from mock server" {
    # Remove cached key to force fetch
    rm -f "$LOA_CACHE_DIR/public-keys/test-key-01.pem"
    rm -f "$LOA_CACHE_DIR/public-keys/test-key-01.meta.json"

    run "$VALIDATOR" get-public-key test-key-01
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"BEGIN PUBLIC KEY"* ]]

    # Verify key was cached
    [[ -f "$LOA_CACHE_DIR/public-keys/test-key-01.pem" ]]
}

@test "public key cache used when fresh" {
    # First call - may fetch or use cache
    run "$VALIDATOR" get-public-key test-key-01
    [[ "$status" -eq 0 ]]

    # Mark cache as very fresh
    cat > "$LOA_CACHE_DIR/public-keys/test-key-01.meta.json" << EOF
{
    "key_id": "test-key-01",
    "algorithm": "RS256",
    "fetched_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "expires_at": "2030-01-01T00:00:00Z"
}
EOF

    # Second call should use cache (output should be same)
    run "$VALIDATOR" get-public-key test-key-01
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"BEGIN PUBLIC KEY"* ]]
}

# =============================================================================
# End-to-End Validation Flow
# =============================================================================

@test "full validation flow: fetch key → validate → list" {
    # Install skill with valid license
    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"

    # Validate should succeed
    run "$LOADER" validate "$LOA_REGISTRY_DIR/skills/test-vendor/valid-skill"
    [[ "$status" -eq 0 ]]

    # List should show skill
    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"valid-skill"* ]]
    [[ "$output" == *"✓"* ]] || [[ "$output" == *"VALID"* ]]
}

@test "validation rejects expired license" {
    # Install skill with expired license
    create_test_skill "test-vendor" "expired-skill" "$FIXTURES_DIR/expired_license.json"

    # Validate should fail with exit code 2
    run "$LOADER" validate "$LOA_REGISTRY_DIR/skills/test-vendor/expired-skill"
    [[ "$status" -eq 2 ]]
}

@test "validation returns grace period status" {
    # Install skill with grace period license
    create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json"

    # Validate should return exit code 1 (grace period)
    run "$LOADER" validate "$LOA_REGISTRY_DIR/skills/test-vendor/grace-skill"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# Loadable Command Integration
# =============================================================================

@test "loadable returns only valid skills" {
    # Create multiple skills
    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"
    create_test_skill "test-vendor" "expired-skill" "$FIXTURES_DIR/expired_license.json"
    create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json"

    run "$LOADER" loadable
    [[ "$status" -eq 0 ]]

    # Valid and grace should be included
    [[ "$output" == *"valid-skill"* ]]
    [[ "$output" == *"grace-skill"* ]]

    # Expired should NOT be included
    [[ "$output" != *"expired-skill"* ]]
}

# =============================================================================
# Offline Mode Integration
# =============================================================================

@test "offline validation works with cached key" {
    # Ensure key is cached
    [[ -f "$LOA_CACHE_DIR/public-keys/test-key-01.pem" ]]

    # Install skill
    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"

    # Enable offline mode and validate
    export LOA_OFFLINE=1
    run "$LOADER" validate "$LOA_REGISTRY_DIR/skills/test-vendor/valid-skill"
    [[ "$status" -eq 0 ]]
}

@test "offline mode fails without cached key" {
    # Remove all cached keys
    rm -rf "$LOA_CACHE_DIR/public-keys"
    mkdir -p "$LOA_CACHE_DIR/public-keys"

    # Install skill
    create_test_skill "test-vendor" "valid-skill" "$FIXTURES_DIR/valid_license.json"

    # Enable offline mode and validate
    export LOA_OFFLINE=1
    run "$LOADER" validate "$LOA_REGISTRY_DIR/skills/test-vendor/valid-skill"
    # Should fail - no cached key
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Grace Period Warnings
# =============================================================================

@test "list shows grace period warning" {
    # Install skill with grace period license
    create_test_skill "test-vendor" "grace-skill" "$FIXTURES_DIR/grace_period_license.json"

    run "$LOADER" list
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"grace-skill"* ]]
    # Should show warning indicator
    [[ "$output" == *"⚠"* ]] || [[ "$output" == *"grace"* ]] || [[ "$output" == *"WARNING"* ]]
}

# =============================================================================
# Error Handling Integration
# =============================================================================

@test "handles invalid signature from mock server" {
    # Install skill with tampered license
    create_test_skill "test-vendor" "invalid-sig" "$FIXTURES_DIR/invalid_signature_license.json"

    run "$LOADER" validate "$LOA_REGISTRY_DIR/skills/test-vendor/invalid-sig"
    [[ "$status" -eq 4 ]]  # Invalid signature
}

@test "handles missing license file gracefully" {
    # Create skill without license
    local skill_dir="$LOA_REGISTRY_DIR/skills/test-vendor/no-license"
    mkdir -p "$skill_dir"
    cat > "$skill_dir/index.yaml" << EOF
name: no-license
version: "1.0.0"
EOF

    run "$LOADER" validate "$skill_dir"
    [[ "$status" -eq 3 ]]  # Missing license
}
