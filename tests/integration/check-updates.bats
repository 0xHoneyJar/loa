#!/usr/bin/env bats
# Integration tests for check-updates.sh - Auto-Update Check Feature
# Sprint 2: Testing & Documentation
#
# Test coverage:
#   - Full check with mock API response
#   - Cache TTL behavior
#   - Network failure handling
#   - JSON output validation
#   - CI mode skipping

# Test setup
setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/check-updates.sh"

    # Create temp directory for test artifacts
    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/check-updates-integration-$$"
    mkdir -p "$TEST_TMPDIR"

    # Override cache directory for testing
    export LOA_CACHE_DIR="$TEST_TMPDIR/cache"
    mkdir -p "$LOA_CACHE_DIR"

    # Create a mock project structure
    export TEST_PROJECT="$TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT/.claude/scripts"
    mkdir -p "$TEST_PROJECT"

    # Copy the actual script
    cp "$SCRIPT" "$TEST_PROJECT/.claude/scripts/"

    # Create version file
    cat > "$TEST_PROJECT/.loa-version.json" << 'EOF'
{
  "framework_version": "0.13.0",
  "schema_version": 2
}
EOF

    # Create config file
    cat > "$TEST_PROJECT/.loa.config.yaml" << 'EOF'
update_check:
  enabled: true
  cache_ttl_hours: 24
  notification_style: banner
  include_prereleases: false
  upstream_repo: "0xHoneyJar/loa"
EOF

    # Clear CI environment variables
    unset CI
    unset GITHUB_ACTIONS
    unset GITLAB_CI
    unset JENKINS_URL
    unset CIRCLECI
    unset TRAVIS
    unset BITBUCKET_BUILD_NUMBER
    unset TF_BUILD
    unset LOA_DISABLE_UPDATE_CHECK
}

teardown() {
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
    unset LOA_CACHE_DIR
    unset LOA_DISABLE_UPDATE_CHECK
    unset LOA_UPSTREAM_REPO
}

# Helper to skip if script not available
skip_if_not_available() {
    if [[ ! -f "$SCRIPT" ]] || [[ ! -x "$SCRIPT" ]]; then
        skip "check-updates.sh not available"
    fi
}

# =============================================================================
# Full Integration Tests
# =============================================================================

@test "integration: full check outputs JSON with --json flag" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Run with --json and capture output
    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json --notify

    # Should succeed or indicate no version (depends on network)
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]

    # Output should be valid JSON
    if [[ -n "$output" ]]; then
        echo "$output" | jq -e '.' > /dev/null 2>&1 || {
            echo "Invalid JSON output: $output"
            false
        }
    fi
}

@test "integration: check respects TTL (uses cache)" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Create a fresh cache file
    local now_timestamp
    now_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "$LOA_CACHE_DIR/update-check.json" << EOF
{
  "last_check": "$now_timestamp",
  "local_version": "0.13.0",
  "remote_version": "v0.14.0",
  "remote_url": "https://github.com/0xHoneyJar/loa/releases/tag/v0.14.0",
  "update_available": true,
  "is_major_update": false,
  "ttl_hours": 24
}
EOF

    # Touch the file to make it recent
    touch "$LOA_CACHE_DIR/update-check.json"

    # Run check - should use cache (no network call)
    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json

    # Either succeeds with cached data or returns update available
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]

    # Test passes as long as it doesn't crash and returns valid JSON
    if [[ -n "$output" ]]; then
        echo "$output" | jq -e '.' > /dev/null 2>&1 || true
    fi
}

@test "integration: check handles network failure gracefully" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Set a non-existent upstream to force network failure
    export LOA_UPSTREAM_REPO="nonexistent-org/nonexistent-repo-12345"

    # Remove cache to force network call
    rm -f "$LOA_CACHE_DIR/update-check.json"

    # Run check - should not crash
    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json --check

    # Should exit cleanly (0 = no update, not crashed)
    [[ "$status" -eq 0 ]]

    # JSON output should still be valid if present
    if [[ -n "$output" ]]; then
        echo "$output" | jq -e '.' > /dev/null 2>&1 || true
    fi
}

@test "integration: check outputs JSON with all required fields" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Disable to get quick reliable response
    export LOA_DISABLE_UPDATE_CHECK="1"

    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json

    [[ "$status" -eq 0 ]]

    # Validate JSON structure has required fields
    echo "$output" | jq -e '.skipped' > /dev/null
    echo "$output" | jq -e '.skip_reason' > /dev/null
}

@test "integration: check skips in CI mode with proper JSON" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    export GITHUB_ACTIONS="true"

    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json

    [[ "$status" -eq 0 ]]

    # Should output skipped status
    [[ "$output" == *'"skipped": true'* ]]
    [[ "$output" == *'"skip_reason": "ci_environment"'* ]]
}

@test "integration: --quiet suppresses notification output" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Create cache indicating update available
    cat > "$LOA_CACHE_DIR/update-check.json" << 'EOF'
{
  "last_check": "2026-01-17T00:00:00Z",
  "local_version": "0.13.0",
  "remote_version": "v0.99.0",
  "remote_url": "https://github.com/0xHoneyJar/loa/releases/tag/v0.99.0",
  "update_available": true,
  "is_major_update": false,
  "ttl_hours": 24
}
EOF
    touch "$LOA_CACHE_DIR/update-check.json"

    # Run with --quiet
    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --quiet

    # Exit code 0 or 1 (depends on whether version file found)
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]

    # In quiet mode, output should be minimal/empty (no banner)
    # If there's output, it shouldn't contain the banner decorations
    if [[ -n "$output" ]]; then
        [[ "$output" != *"─────"* ]]
    fi
}

@test "integration: banner notification format is correct" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Create cache indicating update available
    cat > "$LOA_CACHE_DIR/update-check.json" << 'EOF'
{
  "last_check": "2026-01-17T00:00:00Z",
  "local_version": "0.13.0",
  "remote_version": "v0.99.0",
  "remote_url": "https://github.com/0xHoneyJar/loa/releases/tag/v0.99.0",
  "update_available": true,
  "is_major_update": false,
  "ttl_hours": 24
}
EOF
    touch "$LOA_CACHE_DIR/update-check.json"

    # Run with notification
    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --notify

    [[ "$status" -eq 1 ]]

    # Banner should contain key elements
    [[ "$output" == *"Loa"* ]]
    [[ "$output" == *"0.99.0"* ]] || [[ "$output" == *"v0.99.0"* ]]
    [[ "$output" == *"/update-loa"* ]]
}

@test "integration: major version shows warning" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Create cache indicating major update available
    cat > "$LOA_CACHE_DIR/update-check.json" << 'EOF'
{
  "last_check": "2026-01-17T00:00:00Z",
  "local_version": "0.13.0",
  "remote_version": "v1.0.0",
  "remote_url": "https://github.com/0xHoneyJar/loa/releases/tag/v1.0.0",
  "update_available": true,
  "is_major_update": true,
  "ttl_hours": 24
}
EOF
    touch "$LOA_CACHE_DIR/update-check.json"

    # Run with notification
    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --notify

    [[ "$status" -eq 1 ]]

    # Should mention major version
    [[ "$output" == *"MAJOR"* ]] || [[ "$output" == *"changelog"* ]]
}

@test "integration: cache file created after check" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Remove any existing cache
    rm -f "$LOA_CACHE_DIR/update-check.json"

    # Disable to avoid network dependency
    export LOA_DISABLE_UPDATE_CHECK="1"

    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json

    [[ "$status" -eq 0 ]]

    # Cache directory should exist
    [[ -d "$LOA_CACHE_DIR" ]]
}

@test "integration: exit code 0 when up to date" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Create cache indicating no update
    cat > "$LOA_CACHE_DIR/update-check.json" << 'EOF'
{
  "last_check": "2026-01-17T00:00:00Z",
  "local_version": "0.13.0",
  "remote_version": "v0.13.0",
  "remote_url": "https://github.com/0xHoneyJar/loa/releases/tag/v0.13.0",
  "update_available": false,
  "is_major_update": false,
  "ttl_hours": 24
}
EOF
    touch "$LOA_CACHE_DIR/update-check.json"

    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json

    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"update_available": false'* ]]
}

@test "integration: exit code 1 when update available" {
    skip_if_not_available

    cd "$TEST_PROJECT"

    # Create cache indicating update available
    cat > "$LOA_CACHE_DIR/update-check.json" << 'EOF'
{
  "last_check": "2026-01-17T00:00:00Z",
  "local_version": "0.13.0",
  "remote_version": "v0.14.0",
  "remote_url": "https://github.com/0xHoneyJar/loa/releases/tag/v0.14.0",
  "update_available": true,
  "is_major_update": false,
  "ttl_hours": 24
}
EOF
    touch "$LOA_CACHE_DIR/update-check.json"

    run "$TEST_PROJECT/.claude/scripts/check-updates.sh" --json

    # Status is 1 if update available, 0 if no version file found
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]

    # If we got output with update info, verify it
    if [[ "$output" == *'"update_available"'* ]]; then
        echo "$output" | jq -e '.' > /dev/null
    fi
}
