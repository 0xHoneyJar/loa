#!/usr/bin/env bats
# Integration tests for mock_server.py
# Validates that the mock server correctly simulates registry API
#
# Requirements: curl, python3, jq
# Skip tests automatically if curl is not available

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    MOCK_SERVER="$FIXTURES_DIR/mock_server.py"
    MOCK_PORT=18765  # Use non-standard port to avoid conflicts
    MOCK_URL="http://127.0.0.1:$MOCK_PORT"

    # Check for required commands
    if ! command -v curl &>/dev/null; then
        export SKIP_INTEGRATION="curl not found"
        return 0
    fi

    if ! command -v python3 &>/dev/null; then
        export SKIP_INTEGRATION="python3 not found"
        return 0
    fi

    # Start mock server in background
    python3 "$MOCK_SERVER" --port "$MOCK_PORT" &
    MOCK_PID=$!

    # Wait for server to start (max 5 seconds)
    for i in {1..50}; do
        if curl -s "$MOCK_URL/v1/health" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
}

# Helper to skip if integration env not available
skip_if_missing_deps() {
    if [[ -n "${SKIP_INTEGRATION:-}" ]]; then
        skip "$SKIP_INTEGRATION"
    fi
}

teardown() {
    # Kill mock server
    if [[ -n "${MOCK_PID:-}" ]]; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
}

# =============================================================================
# Health Endpoint
# =============================================================================

@test "health endpoint returns 200" {
    skip_if_missing_deps
    run curl -s -w "%{http_code}" -o /dev/null "$MOCK_URL/v1/health"
    [[ "$output" == "200" ]]
}

@test "health endpoint returns healthy status" {
    skip_if_missing_deps
    result=$(curl -s "$MOCK_URL/v1/health" | jq -r '.status')
    [[ "$result" == "healthy" ]]
}

# =============================================================================
# Public Keys Endpoint
# =============================================================================

@test "public-keys endpoint returns test key" {
    skip_if_missing_deps
    run curl -s -w "%{http_code}" -o /dev/null "$MOCK_URL/v1/public-keys/test-key-01"
    [[ "$output" == "200" ]]
}

@test "public-keys returns RS256 algorithm" {
    skip_if_missing_deps
    result=$(curl -s "$MOCK_URL/v1/public-keys/test-key-01" | jq -r '.algorithm')
    [[ "$result" == "RS256" ]]
}

@test "public-keys returns PEM formatted key" {
    skip_if_missing_deps
    result=$(curl -s "$MOCK_URL/v1/public-keys/test-key-01" | jq -r '.public_key')
    [[ "$result" == *"BEGIN PUBLIC KEY"* ]]
}

@test "public-keys returns 404 for unknown key" {
    skip_if_missing_deps
    run curl -s -w "%{http_code}" -o /dev/null "$MOCK_URL/v1/public-keys/unknown-key"
    [[ "$output" == "404" ]]
}

# =============================================================================
# Skills Endpoints
# =============================================================================

@test "skills metadata endpoint returns skill data" {
    skip_if_missing_deps
    run curl -s -w "%{http_code}" -o /dev/null "$MOCK_URL/v1/skills/test-vendor/valid-skill"
    [[ "$output" == "200" ]]
}

@test "skills metadata returns correct slug" {
    skip_if_missing_deps
    result=$(curl -s "$MOCK_URL/v1/skills/test-vendor/valid-skill" | jq -r '.slug')
    [[ "$result" == "test-vendor/valid-skill" ]]
}

@test "skills content endpoint returns tarball" {
    skip_if_missing_deps
    # Should return a gzip file
    content_type=$(curl -s -I "$MOCK_URL/v1/skills/test-vendor/valid-skill/content" | grep -i content-type | tr -d '\r')
    [[ "$content_type" == *"application/gzip"* ]] || [[ "$content_type" == *"application/octet-stream"* ]]
}

@test "skills returns 404 for unknown skill" {
    skip_if_missing_deps
    run curl -s -w "%{http_code}" -o /dev/null "$MOCK_URL/v1/skills/unknown/nonexistent"
    [[ "$output" == "404" ]]
}

# =============================================================================
# Packs Endpoints
# =============================================================================

@test "packs metadata endpoint returns pack data" {
    skip_if_missing_deps
    run curl -s -w "%{http_code}" -o /dev/null "$MOCK_URL/v1/packs/test-vendor/starter-pack"
    [[ "$output" == "200" ]]
}

@test "packs metadata includes skills list" {
    skip_if_missing_deps
    result=$(curl -s "$MOCK_URL/v1/packs/test-vendor/starter-pack" | jq '.skills | length')
    [[ "$result" -gt 0 ]]
}

@test "packs returns 404 for unknown pack" {
    skip_if_missing_deps
    run curl -s -w "%{http_code}" -o /dev/null "$MOCK_URL/v1/packs/unknown/nonexistent"
    [[ "$output" == "404" ]]
}

# =============================================================================
# License Validation Endpoint
# =============================================================================

@test "license validation accepts valid token" {
    skip_if_missing_deps
    # Read a valid license token from fixtures
    token=$(jq -r '.token' "$FIXTURES_DIR/valid_license.json")

    result=$(curl -s -X POST "$MOCK_URL/v1/licenses/validate" \
        -H "Content-Type: application/json" \
        -d "{\"token\": \"$token\"}" | jq -r '.valid')

    [[ "$result" == "true" ]]
}

@test "license validation rejects expired token" {
    skip_if_missing_deps
    # Read an expired license token from fixtures
    token=$(jq -r '.token' "$FIXTURES_DIR/expired_license.json")

    result=$(curl -s -X POST "$MOCK_URL/v1/licenses/validate" \
        -H "Content-Type: application/json" \
        -d "{\"token\": \"$token\"}" | jq -r '.valid')

    [[ "$result" == "false" ]]
}

@test "license validation rejects tampered token" {
    skip_if_missing_deps
    # Read the invalid signature license
    token=$(jq -r '.token' "$FIXTURES_DIR/invalid_signature_license.json")

    result=$(curl -s -X POST "$MOCK_URL/v1/licenses/validate" \
        -H "Content-Type: application/json" \
        -d "{\"token\": \"$token\"}" | jq -r '.error')

    [[ "$result" == "INVALID_SIGNATURE" ]]
}

@test "license validation returns skill info for valid token" {
    skip_if_missing_deps
    token=$(jq -r '.token' "$FIXTURES_DIR/valid_license.json")

    result=$(curl -s -X POST "$MOCK_URL/v1/licenses/validate" \
        -H "Content-Type: application/json" \
        -d "{\"token\": \"$token\"}" | jq -r '.skill')

    [[ "$result" == "test-vendor/valid-skill" ]]
}
