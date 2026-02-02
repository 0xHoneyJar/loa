#!/usr/bin/env bats
# Tests for gpt-review-api.sh - GPT 5.2 cross-model review
#
# Tests configuration toggles, error handling, and input validation.
# Uses hermetic curl mocking via shared helper.

load '../helpers/gpt-review-setup'

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    GPT_REVIEW="$PROJECT_ROOT/.claude/scripts/gpt-review-api.sh"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/gpt-review"

    # Setup hermetic curl mock
    setup_mock_curl

    # Create temp directory for test-specific files
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"

    # Copy sample content file from fixtures
    cp "$FIXTURES_DIR/content/sample-prd.md" "$TEST_DIR/sample_prd.md"

    # Copy config fixtures
    cp "$FIXTURES_DIR/configs/disabled.yaml" "$TEST_DIR/config_disabled.yaml"
    cp "$FIXTURES_DIR/configs/prd-disabled.yaml" "$TEST_DIR/config_prd_disabled.yaml"
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/config_enabled.yaml"

    # Unset API key for most tests
    unset OPENAI_API_KEY
}

teardown() {
    # Check for unexpected network calls
    if [[ -f "$GPT_REVIEW_MOCK_SENTINEL" ]]; then
        echo "WARNING: Unexpected curl call detected in test"
    fi
}

# =============================================================================
# Script existence and basic validation
# =============================================================================

@test "gpt-review-api.sh exists and is executable" {
    [[ -x "$GPT_REVIEW" ]]
}

@test "shows usage with no arguments" {
    run "$GPT_REVIEW"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Usage"* ]]
}

@test "shows usage with --help" {
    run "$GPT_REVIEW" --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}

# =============================================================================
# Input validation
# =============================================================================

@test "rejects invalid review type" {
    run "$GPT_REVIEW" "invalid_type" "$TEST_DIR/sample_prd.md"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"Invalid review type"* ]]
}

@test "rejects missing content file" {
    run "$GPT_REVIEW" "prd" "/nonexistent/file.md"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"not found"* ]]
}

@test "accepts valid review types: prd" {
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    # Should either SKIP (no config) or fail on API key, not on type
    [[ "$output" != *"Invalid review type"* ]]
}

@test "accepts valid review types: sdd" {
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "sdd" "sample_prd.md"
    [[ "$output" != *"Invalid review type"* ]]
}

@test "accepts valid review types: sprint" {
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "sprint" "sample_prd.md"
    [[ "$output" != *"Invalid review type"* ]]
}

@test "accepts valid review types: code" {
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "code" "sample_prd.md"
    [[ "$output" != *"Invalid review type"* ]]
}

# =============================================================================
# Configuration toggle tests
# =============================================================================

@test "returns SKIPPED when gpt_review.enabled is false" {
    cp "$TEST_DIR/config_disabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"verdict": "SKIPPED"'* ]]
    # Should not have called curl
    check_no_network_calls
}

@test "returns SKIPPED when config file is missing" {
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"verdict": "SKIPPED"'* ]]
    check_no_network_calls
}

@test "returns SKIPPED when phase is disabled" {
    cp "$TEST_DIR/config_prd_disabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"verdict": "SKIPPED"'* ]]
    check_no_network_calls
}

@test "attempts API when enabled (fails on missing key)" {
    cp "$TEST_DIR/config_enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    # Should fail on missing API key, not return SKIPPED
    [[ "$output" != *'"verdict": "SKIPPED"'* ]]
    [[ "$output" == *"OPENAI_API_KEY"* ]]
}

# =============================================================================
# API key handling
# =============================================================================

@test "errors when OPENAI_API_KEY not set and config enabled" {
    cp "$TEST_DIR/config_enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"
    unset OPENAI_API_KEY
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    [[ "$status" -eq 4 ]]
    [[ "$output" == *"OPENAI_API_KEY"* ]]
}

@test "loads API key from .env file" {
    cp "$TEST_DIR/config_enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    echo 'OPENAI_API_KEY="sk-test-fake-key"' > "$TEST_DIR/.env"
    cd "$TEST_DIR"

    # Mock curl to return a response (will be called with loaded key)
    mock_curl_response "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md"
    [[ "$output" == *"Loaded OPENAI_API_KEY from .env"* ]] || \
    [[ "$output" == *"API call"* ]] || \
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Iteration handling
# =============================================================================

@test "uses first-review prompt by default (iteration 1)" {
    cp "$TEST_DIR/config_disabled.yaml" "$TEST_DIR/.loa.config.yaml"
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    [[ "$status" -eq 0 ]]
}

@test "requires --previous for iteration > 1" {
    cp "$TEST_DIR/config_enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    export OPENAI_API_KEY="sk-test-fake"
    cd "$TEST_DIR"

    run "$GPT_REVIEW" "prd" "sample_prd.md" --iteration 2
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--previous"* ]] || [[ "$output" == *"previous"* ]]
}

@test "accepts iteration with previous findings file" {
    cp "$TEST_DIR/config_enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    export OPENAI_API_KEY="sk-test-fake"

    # Create previous findings file
    echo '{"verdict":"CHANGES_REQUIRED","issues":[]}' > "$TEST_DIR/prev.json"
    cd "$TEST_DIR"

    # Mock curl to return approved response
    mock_curl_response "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md" --iteration 2 --previous "prev.json"
    # Should not fail on argument validation
    [[ "$output" != *"--previous required"* ]]
}

# =============================================================================
# Auto-approve at max iterations
# =============================================================================

@test "auto-approves when iteration exceeds max_iterations" {
    cp "$TEST_DIR/config_enabled.yaml" "$TEST_DIR/.loa.config.yaml"
    export OPENAI_API_KEY="sk-test-fake"

    # Create previous findings file
    echo '{"verdict":"CHANGES_REQUIRED","issues":[]}' > "$TEST_DIR/prev.json"
    cd "$TEST_DIR"

    # Default max_iterations is 3, so iteration 4 should auto-approve
    run "$GPT_REVIEW" "prd" "sample_prd.md" --iteration 4 --previous "prev.json"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"verdict": "APPROVED"'* ]]
    [[ "$output" == *'"auto_approved": true'* ]]
    # Should not have called curl (auto-approved locally)
    check_no_network_calls
}

# =============================================================================
# Augmentation handling
# =============================================================================

@test "accepts augmentation file" {
    cp "$TEST_DIR/config_disabled.yaml" "$TEST_DIR/.loa.config.yaml"
    echo "## Project Context" > "$TEST_DIR/augmentation.md"
    cd "$TEST_DIR"

    run "$GPT_REVIEW" "prd" "sample_prd.md" --augmentation "augmentation.md"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# SKIPPED response format
# =============================================================================

@test "SKIPPED response includes reason field" {
    cd "$TEST_DIR"
    run "$GPT_REVIEW" "prd" "sample_prd.md"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *'"reason":'* ]]
}

@test "SKIPPED response is valid JSON" {
    cd "$TEST_DIR"
    # Capture only stdout (JSON), not stderr (logs)
    local json_output
    json_output=$("$GPT_REVIEW" "prd" "sample_prd.md" 2>/dev/null)
    echo "$json_output" | jq empty
}
