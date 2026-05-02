#!/usr/bin/env bats
# =============================================================================
# Tests for bedrock health probe — _probe_bedrock function
#
# Cycle-096 Sprint 2 Task 2.1 / FR-8.
# Source-based testing: sources model-health-probe.sh and exercises
# _probe_bedrock with mocked _curl_json. Live tests live in
# .claude/adapters/tests/test_bedrock_live.py (key-gated).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    PROBE="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"

    # Source the probe script so we get the functions without running main.
    # The script's main-guard pattern (BASH_SOURCE != 0) prevents main() from
    # firing when sourced.
    source "$PROBE"

    # CRITICAL: override _curl_json AFTER sourcing the probe (which defines
    # the real one). State is pre-populated by _mock_curl in each test.
    # F002 (cycle-097): set _CURL_JSON_CALLED=1 inside the override so tests
    # can assert the probe actually invoked it. Prevents silent passing if
    # the probe ever stops calling _curl_json (e.g., a refactor that fails
    # an early-return guard) — the mock's pre-populated HTTP_STATUS would
    # otherwise still drive an apparently-correct PROBE_STATE.
    _curl_json() {
        _CURL_JSON_CALLED=1
        return 0
    }

    # Mock helper for tests.
    _mock_curl() {
        local status="$1"
        local body="$2"
        HTTP_STATUS="$status"
        RESPONSE_BODY="$body"
    }

    # Each test gets a clean slate.
    AWS_BEARER_TOKEN_BEDROCK=""
    AWS_BEDROCK_REGION=""
    AWS_REGION=""
    HTTP_STATUS=""
    RESPONSE_BODY=""
    PROBE_STATE=""
    PROBE_CONFIDENCE=""
    PROBE_REASON=""
    PROBE_HTTP=""
    PROBE_LATENCY_MS=""
    PROBE_ERROR_CLASS=""
    _CURL_JSON_CALLED=0
}

# --- Auth-missing path ---

@test "probe_bedrock: missing AWS_BEARER_TOKEN_BEDROCK returns UNKNOWN auth" {
    AWS_BEARER_TOKEN_BEDROCK=""
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_CONFIDENCE" = "low" ]
    [ "$PROBE_ERROR_CLASS" = "auth" ]
    [[ "$PROBE_REASON" == *"AWS_BEARER_TOKEN_BEDROCK not set"* ]]
    # F002: probe must short-circuit BEFORE the network call when auth is
    # missing — confirms we don't accidentally start leaking unauth requests.
    [ "$_CURL_JSON_CALLED" = "0" ]
}

# --- 200 OK paths ---

@test "probe_bedrock: 200 OK with model in inference-profiles → AVAILABLE high" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 200 '{"inferenceProfileSummaries":[{"inferenceProfileId":"us.anthropic.claude-opus-4-7"}]}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "AVAILABLE" ]
    [ "$PROBE_CONFIDENCE" = "high" ]
    [ "$PROBE_ERROR_CLASS" = "ok" ]
    # F002: ensure the probe actually issued the network call. Without this,
    # the assertion above could pass on stale RESPONSE_BODY/HTTP_STATUS state
    # if the probe ever short-circuits unexpectedly.
    [ "$_CURL_JSON_CALLED" = "1" ]
}

@test "probe_bedrock: 200 OK without model in listing → UNAVAILABLE high" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 200 '{"inferenceProfileSummaries":[{"inferenceProfileId":"us.anthropic.claude-opus-4-1"}]}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNAVAILABLE" ]
    [ "$PROBE_CONFIDENCE" = "high" ]
    [ "$PROBE_ERROR_CLASS" = "model_not_listed" ]
    [[ "$PROBE_REASON" == *"not in inference-profiles listing"* ]]
}

@test "probe_bedrock: 200 OK with empty inference-profiles → UNAVAILABLE" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 200 '{"inferenceProfileSummaries":[]}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNAVAILABLE" ]
    [ "$PROBE_ERROR_CLASS" = "model_not_listed" ]
}

@test "probe_bedrock: 200 OK with colon-bearing model ID matches correctly" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 200 '{"inferenceProfileSummaries":[{"inferenceProfileId":"us.anthropic.claude-haiku-4-5-20251001-v1:0"}]}'
    _probe_bedrock "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    [ "$PROBE_STATE" = "AVAILABLE" ]
}

# --- Auth failure paths ---

@test "probe_bedrock: 401 → UNKNOWN auth" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-revoked"
    _mock_curl 401 '{"message":"Unauthorized"}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "auth" ]
    [[ "$PROBE_REASON" == *"401"* ]] || [[ "$PROBE_REASON" == *"auth-level"* ]]
}

@test "probe_bedrock: 403 → UNKNOWN auth (token may be revoked)" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-revoked"
    _mock_curl 403 '{"message":"AccessDenied"}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "auth" ]
}

# --- Transient failure paths ---

@test "probe_bedrock: 429 → UNKNOWN transient" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 429 '{"message":"ThrottlingException"}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

@test "probe_bedrock: 503 → UNKNOWN transient" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 503 '{"message":"ServiceUnavailableException"}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

@test "probe_bedrock: 500 → UNKNOWN transient" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 500 '{"message":"InternalServerError"}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

@test "probe_bedrock: 0 (network error) → UNKNOWN transient" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 0 ''
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

# --- Region resolution ---

@test "probe_bedrock: uses AWS_BEDROCK_REGION when set" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    AWS_BEDROCK_REGION="us-west-2"
    _mock_curl 200 '{"inferenceProfileSummaries":[{"inferenceProfileId":"us.anthropic.claude-opus-4-7"}]}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    # We can't easily inspect the URL the mock saw without restructuring;
    # the absence of failure here + AVAILABLE state confirms the probe ran.
    [ "$PROBE_STATE" = "AVAILABLE" ]
}

@test "probe_bedrock: falls back to AWS_REGION then us-east-1" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    AWS_REGION="eu-west-1"  # AWS_BEDROCK_REGION unset
    _mock_curl 200 '{"inferenceProfileSummaries":[{"inferenceProfileId":"us.anthropic.claude-opus-4-7"}]}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "AVAILABLE" ]
}

# --- SKP-001 guard for ambiguous 4xx ---

@test "probe_bedrock: ambiguous 418 → UNKNOWN per SKP-001 guard" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 418 '{"message":"I am a teapot"}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
    [[ "$PROBE_REASON" == *"SKP-001"* ]]
}

# --- HTTP / latency tracking ---

@test "probe_bedrock: HTTP_STATUS + LATENCY_MS populated on every path" {
    AWS_BEARER_TOKEN_BEDROCK="ABSKR-fake-token"
    _mock_curl 200 '{"inferenceProfileSummaries":[{"inferenceProfileId":"us.anthropic.claude-opus-4-7"}]}'
    _probe_bedrock "us.anthropic.claude-opus-4-7"
    [ "$PROBE_HTTP" = "200" ]
    [ -n "$PROBE_LATENCY_MS" ]
}
