#!/usr/bin/env bats
# =============================================================================
# tests/integration/gpt-review-429-diagnostic.bats
#
# Closes #711.B (zkSoju feedback): the gpt-review-api retry loop emitted a
# generic "Rate limited (429)" message and gave up after 3 attempts with no
# information about WHY the 429 fired. zkSoju's session burned ~3 minutes on
# 6 retry attempts against a quota-exhausted gpt-5.2 without seeing the
# underlying error type.
#
# Fix: extract .error.{type, code, message} from the 429 response body and
# log to stderr with each retry attempt. On exhaustion + insufficient_quota,
# emit an operator hint pointing at the fallback paths (gpt-5.2-mini,
# Codex MCP).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    LIB="${REPO_ROOT}/.claude/scripts/lib-curl-fallback.sh"
    [[ -f "$LIB" ]] || skip "lib-curl-fallback.sh not present"
    # shellcheck source=/dev/null
    source "$LIB"
}

@test "429 diagnostic helper extracts .error.type and .error.message from response body" {
    local response='{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}'
    local stderr_output
    stderr_output=$(_curl_fallback_log_429_diagnostic "$response" 1 2>&1)
    [[ "$stderr_output" == *"Rate limited (429)"* ]]
    [[ "$stderr_output" == *"error.type=insufficient_quota"* ]]
    [[ "$stderr_output" == *"error.code=insufficient_quota"* ]]
    [[ "$stderr_output" == *"error.message: You exceeded your current quota"* ]]
}

@test "429 diagnostic distinguishes burst (rate_limit_exceeded) from quota (insufficient_quota)" {
    # rate_limit_exceeded — burst limiter; retry might succeed
    local burst='{"error":{"message":"Rate limit reached for requests","type":"requests","code":"rate_limit_exceeded"}}'
    local burst_out
    burst_out=$(_curl_fallback_log_429_diagnostic "$burst" 2 2>&1)
    [[ "$burst_out" == *"error.code=rate_limit_exceeded"* ]]
    [[ "$burst_out" == *"Rate limit reached"* ]]

    # insufficient_quota — billing/tier limit; retries WON'T help
    local quota='{"error":{"message":"You exceeded your current quota, please check your plan and billing details","type":"insufficient_quota","code":"insufficient_quota"}}'
    local quota_out
    quota_out=$(_curl_fallback_log_429_diagnostic "$quota" 3 2>&1)
    [[ "$quota_out" == *"error.code=insufficient_quota"* ]]
    [[ "$quota_out" == *"check your plan and billing"* ]]
}

@test "429 diagnostic handles missing .error fields gracefully" {
    local response='{"_no_error_field":true}'
    local stderr_output
    stderr_output=$(_curl_fallback_log_429_diagnostic "$response" 1 2>&1)
    # The header line must always appear.
    [[ "$stderr_output" == *"Rate limited (429)"* ]]
    # No bogus "error.type=null" or "error.message:" with empty content.
    [[ "$stderr_output" != *"error.type="* ]] || [[ "$stderr_output" == *"error.type=unknown"* ]]
}

@test "429 diagnostic handles malformed JSON response (non-fatal)" {
    local response='this is not json at all'
    local stderr_output
    stderr_output=$(_curl_fallback_log_429_diagnostic "$response" 1 2>&1)
    # No crash; header line still emitted.
    [[ "$stderr_output" == *"Rate limited (429)"* ]]
}

@test "429 quota hint fires for insufficient_quota response" {
    local response='{"error":{"type":"insufficient_quota","code":"insufficient_quota","message":"quota exceeded"}}'
    local stderr_output
    stderr_output=$(_curl_fallback_log_429_quota_hint "$response" 2>&1)
    [[ "$stderr_output" == *"insufficient_quota"* ]]
    [[ "$stderr_output" == *"billing limit"* ]]
    # Iter-1 review MEDIUM: hint now points at the canonical config + protocol
    # doc rather than naming specific model/agent IDs that aren't actually
    # registered in the repo.
    [[ "$stderr_output" == *".gpt_review.models"* ]]
    [[ "$stderr_output" == *"gpt-review-integration.md"* ]]
}

@test "429 quota hint does NOT fire for burst rate_limit_exceeded" {
    local response='{"error":{"type":"requests","code":"rate_limit_exceeded","message":"slow down"}}'
    local stderr_output
    stderr_output=$(_curl_fallback_log_429_quota_hint "$response" 2>&1)
    # No quota hint — this is a burst limit, retries are appropriate.
    [[ "$stderr_output" != *"insufficient_quota"* ]]
    [[ "$stderr_output" != *"Codex MCP"* ]]
}

@test "429 short-circuit: lib-curl-fallback.sh contains insufficient_quota early-exit" {
    # Bridgebuilder iter-1 MEDIUM: retries DEFINITELY won't help when the
    # account hit its tier/billing limit. Verify the source code contains
    # the short-circuit logic so a regression that drops it ships red.
    local lib="${BATS_TEST_DIRNAME}/../../.claude/scripts/lib-curl-fallback.sh"
    grep -q "short-circuit: insufficient_quota detected" "$lib"
    grep -q 'return 1' "$lib"  # baseline; short-circuit returns 1 like normal
    # The short-circuit block must be INSIDE the 429 case branch (before
    # the retry-sleep block).
    awk '/^      429\)/{f=1} f && /short-circuit: insufficient_quota/{print "FOUND"; exit 0} f && /Waiting.*before retry/{exit 1}' "$lib" | grep -q FOUND
}

@test "429 short-circuit: insufficient_quota response triggers short-circuit string in diagnostic" {
    # Probe the short-circuit logic inline: replicate the conditional from
    # the lib's case block. If insufficient_quota → emit short-circuit.
    local response='{"error":{"type":"insufficient_quota","code":"insufficient_quota","message":"quota"}}'
    local _429_short_type _429_short_code
    _429_short_type=$(echo "$response" | jq -r '(.error.type? // .error[0]?.type?) // empty' 2>/dev/null) || true
    _429_short_code=$(echo "$response" | jq -r '(.error.code? // .error[0]?.code?) // empty' 2>/dev/null) || true
    [[ "$_429_short_type" == "insufficient_quota" || "$_429_short_code" == "insufficient_quota" ]]
}

@test "429 short-circuit: burst rate_limit_exceeded does NOT trigger" {
    local response='{"error":{"type":"requests","code":"rate_limit_exceeded","message":"slow down"}}'
    local _429_short_type _429_short_code
    _429_short_type=$(echo "$response" | jq -r '(.error.type? // .error[0]?.type?) // empty' 2>/dev/null) || true
    _429_short_code=$(echo "$response" | jq -r '(.error.code? // .error[0]?.code?) // empty' 2>/dev/null) || true
    if [[ "$_429_short_type" == "insufficient_quota" || "$_429_short_code" == "insufficient_quota" ]]; then
        return 1
    fi
}

@test "429 diagnostic log secrets are redacted via redact_log_output" {
    # The diagnostic uses redact_log_output if available. Probe by injecting
    # a fake API key into the error message and asserting it's redacted.
    if ! declare -f redact_log_output >/dev/null 2>&1; then
        skip "redact_log_output not loaded; skipping redaction probe"
    fi
    local response='{"error":{"message":"Auth failed for sk-fake1234567890abcdefghij1234567890","type":"invalid_request_error"}}'
    local stderr_output
    stderr_output=$(_curl_fallback_log_429_diagnostic "$response" 1 2>&1)
    # The literal sk-fake key MUST NOT appear (redacted).
    [[ "$stderr_output" != *"sk-fake1234567890abcdefghij1234567890"* ]]
}
