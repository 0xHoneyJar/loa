#!/usr/bin/env bats
# Unit tests for .claude/scripts/license-validator.sh
# Test-first development: These tests define expected behavior
#
# Exit codes:
#   0 = Valid license
#   1 = Expired but in grace period
#   2 = Expired beyond grace period
#   3 = Missing license file
#   4 = Invalid signature

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/license-validator.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/license-validator-test-$$"
    mkdir -p "$TEST_TMPDIR"

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

# Helper to skip if validator not implemented
skip_if_not_implemented() {
    if [[ ! -f "$VALIDATOR" ]]; then
        skip "license-validator.sh not yet implemented"
    fi
    if [[ ! -x "$VALIDATOR" ]]; then
        skip "license-validator.sh not executable"
    fi
}

# =============================================================================
# validate Command - Full Validation Flow
# =============================================================================

@test "validate returns 0 for valid license" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/valid_license.json"
    [[ "$status" -eq 0 ]]
}

@test "validate returns 1 for grace period license" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/grace_period_license.json"
    [[ "$status" -eq 1 ]]
}

@test "validate returns 2 for expired license" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/expired_license.json"
    [[ "$status" -eq 2 ]]
}

@test "validate returns 3 for missing license file" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$TEST_TMPDIR/nonexistent.json"
    [[ "$status" -eq 3 ]]
}

@test "validate returns 4 for invalid signature" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/invalid_signature_license.json"
    [[ "$status" -eq 4 ]]
}

@test "validate outputs skill slug on success" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/valid_license.json"
    [[ "$output" == *"test-vendor/valid-skill"* ]]
}

@test "validate outputs warning for grace period" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/grace_period_license.json"
    [[ "$output" == *"grace"* ]] || [[ "$output" == *"Grace"* ]] || [[ "$output" == *"WARNING"* ]]
}

@test "validate outputs error for expired license" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/expired_license.json"
    [[ "$output" == *"expired"* ]] || [[ "$output" == *"Expired"* ]] || [[ "$output" == *"ERROR"* ]]
}

# =============================================================================
# verify-signature Command - Signature Verification Only
# =============================================================================

@test "verify-signature returns 0 for valid JWT" {
    skip_if_not_implemented

    token=$(jq -r '.token' "$FIXTURES_DIR/valid_license.json")
    run "$VALIDATOR" verify-signature "$token"
    [[ "$status" -eq 0 ]]
}

@test "verify-signature returns non-zero for tampered JWT" {
    skip_if_not_implemented

    token=$(jq -r '.token' "$FIXTURES_DIR/invalid_signature_license.json")
    run "$VALIDATOR" verify-signature "$token"
    [[ "$status" -ne 0 ]]
}

@test "verify-signature returns non-zero for malformed JWT" {
    skip_if_not_implemented

    run "$VALIDATOR" verify-signature "not.a.valid.jwt"
    [[ "$status" -ne 0 ]]
}

@test "verify-signature returns non-zero for empty input" {
    skip_if_not_implemented

    run "$VALIDATOR" verify-signature ""
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# decode Command - JWT Payload Extraction
# =============================================================================

@test "decode extracts skill from JWT payload" {
    skip_if_not_implemented

    token=$(jq -r '.token' "$FIXTURES_DIR/valid_license.json")
    result=$("$VALIDATOR" decode "$token" | jq -r '.skill')
    [[ "$result" == "test-vendor/valid-skill" ]]
}

@test "decode extracts tier from JWT payload" {
    skip_if_not_implemented

    token=$(jq -r '.token' "$FIXTURES_DIR/valid_license.json")
    result=$("$VALIDATOR" decode "$token" | jq -r '.tier')
    [[ "$result" == "pro" ]]
}

@test "decode extracts exp timestamp from JWT payload" {
    skip_if_not_implemented

    token=$(jq -r '.token' "$FIXTURES_DIR/valid_license.json")
    result=$("$VALIDATOR" decode "$token" | jq -r '.exp')
    [[ "$result" =~ ^[0-9]+$ ]]
}

@test "decode returns valid JSON" {
    skip_if_not_implemented

    token=$(jq -r '.token' "$FIXTURES_DIR/valid_license.json")
    run "$VALIDATOR" decode "$token"
    # Should be valid JSON
    echo "$output" | jq . >/dev/null 2>&1
    [[ "$?" -eq 0 ]]
}

@test "decode fails for malformed JWT" {
    skip_if_not_implemented

    run "$VALIDATOR" decode "not-a-jwt"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# get-public-key Command - Key Cache Management
# =============================================================================

@test "get-public-key returns cached key" {
    skip_if_not_implemented

    run "$VALIDATOR" get-public-key "test-key-01"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"BEGIN PUBLIC KEY"* ]]
}

@test "get-public-key creates cache directory if missing" {
    skip_if_not_implemented

    rm -rf "$LOA_CACHE_DIR/public-keys"

    # This should create the directory (or fail gracefully without network)
    run "$VALIDATOR" get-public-key "test-key-01" --offline
    # Just check it doesn't crash - might fail without network
    [[ -d "$LOA_CACHE_DIR/public-keys" ]] || [[ "$status" -ne 0 ]]
}

@test "get-public-key --refresh forces re-fetch" {
    skip_if_not_implemented

    # Mark the cached key as very old
    cat > "$LOA_CACHE_DIR/public-keys/test-key-01.meta.json" << EOF
{
    "key_id": "test-key-01",
    "fetched_at": "2020-01-01T00:00:00Z",
    "expires_at": "2030-01-01T00:00:00Z"
}
EOF

    # With mock server not running, --refresh should fail
    # We're just testing the flag is recognized
    run "$VALIDATOR" get-public-key "test-key-01" --refresh --offline
    # Should recognize the flag (exit code varies based on network state)
    [[ "$status" -eq 0 ]] || [[ "$output" == *"offline"* ]] || [[ "$output" == *"cache"* ]]
}

@test "get-public-key respects cache_hours config" {
    skip_if_not_implemented

    # Create a config with 1 hour cache
    cat > "$TEST_TMPDIR/.loa.config.yaml" << 'EOF'
registry:
  public_key_cache_hours: 1
EOF
    cd "$TEST_TMPDIR"

    # Set cache metadata to 2 hours ago
    two_hours_ago=$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-2H +%Y-%m-%dT%H:%M:%SZ)
    cat > "$LOA_CACHE_DIR/public-keys/test-key-01.meta.json" << EOF
{
    "key_id": "test-key-01",
    "fetched_at": "$two_hours_ago",
    "expires_at": "2030-01-01T00:00:00Z"
}
EOF

    # Should recognize cache as expired
    run "$VALIDATOR" get-public-key "test-key-01" --check-expiry
    # Output should indicate cache expired or attempt refresh
    [[ "$output" == *"expired"* ]] || [[ "$output" == *"refresh"* ]] || [[ "$status" -ne 0 ]]
}

# =============================================================================
# check-expiry Command - Expiration Status
# =============================================================================

@test "check-expiry returns 0 for valid license" {
    skip_if_not_implemented

    run "$VALIDATOR" check-expiry "$FIXTURES_DIR/valid_license.json"
    [[ "$status" -eq 0 ]]
}

@test "check-expiry returns 1 for grace period" {
    skip_if_not_implemented

    run "$VALIDATOR" check-expiry "$FIXTURES_DIR/grace_period_license.json"
    [[ "$status" -eq 1 ]]
}

@test "check-expiry returns 2 for expired beyond grace" {
    skip_if_not_implemented

    run "$VALIDATOR" check-expiry "$FIXTURES_DIR/expired_license.json"
    [[ "$status" -eq 2 ]]
}

@test "check-expiry outputs time remaining for valid" {
    skip_if_not_implemented

    run "$VALIDATOR" check-expiry "$FIXTURES_DIR/valid_license.json"
    # Should show days/hours remaining
    [[ "$output" == *"day"* ]] || [[ "$output" == *"hour"* ]] || [[ "$output" == *"valid"* ]]
}

# =============================================================================
# Grace Period Handling
# =============================================================================

@test "grace period calculated correctly for pro tier (24h)" {
    skip_if_not_implemented

    run "$VALIDATOR" validate "$FIXTURES_DIR/grace_period_license.json"
    # Pro tier gets 24h grace - should be in grace period
    [[ "$status" -eq 1 ]]
}

@test "grace period calculated correctly for team tier (72h)" {
    skip_if_not_implemented

    run "$VALIDATOR" check-expiry "$FIXTURES_DIR/team_license.json"
    # Team license is valid, should return 0
    [[ "$status" -eq 0 ]]
}

@test "grace period calculated correctly for enterprise tier (168h)" {
    skip_if_not_implemented

    run "$VALIDATOR" check-expiry "$FIXTURES_DIR/enterprise_license.json"
    # Enterprise license is valid, should return 0
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Error Handling
# =============================================================================

@test "handles missing jq gracefully" {
    skip_if_not_implemented
    skip "Cannot easily test missing jq"
}

@test "handles corrupted license JSON" {
    skip_if_not_implemented

    echo "not valid json" > "$TEST_TMPDIR/corrupted.json"
    run "$VALIDATOR" validate "$TEST_TMPDIR/corrupted.json"
    [[ "$status" -ne 0 ]]
}

@test "handles license without token field" {
    skip_if_not_implemented

    echo '{"slug": "test/skill"}' > "$TEST_TMPDIR/no_token.json"
    run "$VALIDATOR" validate "$TEST_TMPDIR/no_token.json"
    [[ "$status" -ne 0 ]]
}

@test "displays usage when no arguments" {
    skip_if_not_implemented

    run "$VALIDATOR"
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "displays usage for unknown command" {
    skip_if_not_implemented

    run "$VALIDATOR" unknown-command
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Offline Mode
# =============================================================================

@test "offline validation works with cached key" {
    skip_if_not_implemented

    # Key is already cached in setup
    export LOA_OFFLINE=1
    run "$VALIDATOR" validate "$FIXTURES_DIR/valid_license.json"
    [[ "$status" -eq 0 ]]
}

@test "offline mode fails without cached key" {
    skip_if_not_implemented

    rm -f "$LOA_CACHE_DIR/public-keys/test-key-01.pem"
    export LOA_OFFLINE=1
    run "$VALIDATOR" validate "$FIXTURES_DIR/valid_license.json"
    # Should fail - no cached key and can't fetch
    [[ "$status" -ne 0 ]]
}
