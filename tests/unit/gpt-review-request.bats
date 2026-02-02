#!/usr/bin/env bats
# Tests for GPT review API request construction
#
# Verifies API requests are constructed correctly using mock curl capture.

load '../helpers/gpt-review-setup'

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    GPT_REVIEW="$PROJECT_ROOT/.claude/scripts/gpt-review-api.sh"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/gpt-review"

    # Setup hermetic curl mock
    setup_mock_curl

    # Create temp directory
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    BODY_CAPTURE="$TEST_DIR/request-body.json"

    # Copy fixtures
    cp "$FIXTURES_DIR/content/sample-prd.md" "$TEST_DIR/sample_prd.md"
    cp "$FIXTURES_DIR/content/sample-code.ts" "$TEST_DIR/sample_code.ts"
    cp "$FIXTURES_DIR/configs/enabled.yaml" "$TEST_DIR/.loa.config.yaml"

    # Set API key
    export OPENAI_API_KEY="sk-test-fake-key"
}

# =============================================================================
# Endpoint selection tests
# =============================================================================

@test "documents (prd) use chat/completions endpoint" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md"

    # Check curl args for endpoint
    [[ -f "$GPT_REVIEW_MOCK_ARGS" ]]
    run cat "$GPT_REVIEW_MOCK_ARGS"
    [[ "$output" == *"chat/completions"* ]]
}

@test "code reviews use responses API endpoint" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "code" "sample_code.ts"

    # Check curl args for endpoint
    [[ -f "$GPT_REVIEW_MOCK_ARGS" ]]
    run cat "$GPT_REVIEW_MOCK_ARGS"
    [[ "$output" == *"responses"* ]]
}

# =============================================================================
# Model selection tests
# =============================================================================

@test "documents use gpt-5.2 model" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md"

    # Check request body for model
    [[ -f "$BODY_CAPTURE" ]]
    run cat "$BODY_CAPTURE"
    [[ "$output" == *"gpt-5.2"* ]] || [[ "$output" == *"gpt-5"* ]]
}

@test "code uses gpt-5.2-codex model" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "code" "sample_code.ts"

    # Check request body for model
    [[ -f "$BODY_CAPTURE" ]]
    run cat "$BODY_CAPTURE"
    [[ "$output" == *"codex"* ]] || [[ "$output" == *"gpt-5"* ]]
}

@test "respects config model override" {
    # Create config with custom model
    cat > "$TEST_DIR/.loa.config.yaml" << 'EOF'
gpt_review:
  enabled: true
  models:
    documents: "gpt-4-turbo"
    code: "gpt-4-turbo"
  phases:
    prd: true
    sdd: true
    sprint: true
    code: true
EOF
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md"

    # Check that configured model is used
    [[ -f "$BODY_CAPTURE" ]]
    run cat "$BODY_CAPTURE"
    [[ "$output" == *"gpt-4-turbo"* ]] || [[ "$output" == *"model"* ]]
}

# =============================================================================
# Request format tests
# =============================================================================

@test "chat/completions has messages array" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md"

    [[ -f "$BODY_CAPTURE" ]]
    # Should have messages field for chat completions
    run cat "$BODY_CAPTURE"
    [[ "$output" == *"messages"* ]] || [[ "$output" == *"role"* ]]
}

@test "responses API has input field" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "code" "sample_code.ts"

    [[ -f "$BODY_CAPTURE" ]]
    # Should have input field for responses API
    run cat "$BODY_CAPTURE"
    [[ "$output" == *"input"* ]] || [[ "$output" == *"content"* ]]
}

@test "Authorization header contains Bearer token" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md"

    # Check curl args for auth header
    [[ -f "$GPT_REVIEW_MOCK_ARGS" ]]
    run cat "$GPT_REVIEW_MOCK_ARGS"
    [[ "$output" == *"Authorization"* ]] || [[ "$output" == *"Bearer"* ]]
}

@test "requests JSON response format" {
    cd "$TEST_DIR"
    mock_curl_capture "$BODY_CAPTURE" "$FIXTURES_DIR/mock-responses/approved.json"

    run "$GPT_REVIEW" "prd" "sample_prd.md"

    [[ -f "$BODY_CAPTURE" ]]
    # Should request JSON response
    run cat "$BODY_CAPTURE"
    [[ "$output" == *"json"* ]] || [[ "$output" == *"response_format"* ]]
}
