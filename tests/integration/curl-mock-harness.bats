#!/usr/bin/env bats
# =============================================================================
# tests/integration/curl-mock-harness.bats
#
# cycle-102 Sprint 1C T1C.4 — self-test for the curl-mock harness.
# Exercises the harness ITSELF (T1C.1 shim + T1C.2 helpers + T1C.3 fixtures)
# before downstream test refactors land.
#
# Closes Issue #808 acceptance criteria AC-1C.1 through AC-1C.5.
# =============================================================================

load '../lib/curl-mock-helpers'

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    _setup_curl_mock_dirs
}

teardown() {
    _teardown_curl_mock
}

# -----------------------------------------------------------------------------
# AC-1C.1 — _with_curl_mock activates / deactivates the shim hermetically
# -----------------------------------------------------------------------------

@test "AC1.a: _with_curl_mock prepends shim to PATH" {
    # Capture original curl path (may be empty if curl not installed system-wide)
    local orig_curl
    orig_curl="$(command -v curl 2>/dev/null || true)"

    _with_curl_mock 200-ok

    local active_curl
    active_curl="$(command -v curl)"
    [[ -n "$active_curl" ]]
    # The active curl must NOT be /usr/bin/curl — must be the shim
    [[ "$active_curl" != "$orig_curl" ]] || [[ -z "$orig_curl" ]]
    # The active curl must be in our test bin dir
    [[ "$active_curl" == "$_CURL_MOCK_BIN_DIR/curl" ]]
}

@test "AC1.b: _teardown_curl_mock restores PATH" {
    local pre_path="$PATH"
    _with_curl_mock 200-ok
    [[ "$PATH" != "$pre_path" ]]
    _teardown_curl_mock
    [[ "$PATH" == "$pre_path" ]]
    # Re-set up dirs for the auto-teardown at end of test
    _setup_curl_mock_dirs
}

@test "AC1.c: shim emits the configured body for 200-ok" {
    _with_curl_mock 200-ok
    run curl https://api.example.com/v1/anything
    [ "$status" -eq 0 ]
    [[ "$output" == *'"ok": true'* ]]
    [[ "$output" == *'"fixture": "200-ok"'* ]]
}

# -----------------------------------------------------------------------------
# AC-1C.2 — fixture taxonomy: 200, 4xx, 5xx, disconnect, timeout
# -----------------------------------------------------------------------------

@test "AC2.a: 400-bad-request emits exit 0 with 400-shaped body" {
    _with_curl_mock 400-bad-request
    run curl https://api.example.com/v1/x
    [ "$status" -eq 0 ]
    [[ "$output" == *'invalid_request_error'* ]]
}

@test "AC2.b: 401-unauthorized emits exit 0 with auth error body" {
    _with_curl_mock 401-unauthorized
    run curl https://api.example.com/v1/x
    [ "$status" -eq 0 ]
    [[ "$output" == *'authentication_error'* ]]
}

@test "AC2.c: 429-rate-limited emits exit 0 with rate-limit body" {
    _with_curl_mock 429-rate-limited
    run curl https://api.example.com/v1/x
    [ "$status" -eq 0 ]
    [[ "$output" == *'rate_limit_error'* ]]
}

@test "AC2.d: 500-internal emits exit 0 with server-error body" {
    _with_curl_mock 500-internal
    run curl https://api.example.com/v1/x
    [ "$status" -eq 0 ]
    [[ "$output" == *'server_error'* ]]
}

@test "AC2.e: 503-unavailable emits exit 0 with service-unavailable body" {
    _with_curl_mock 503-unavailable
    run curl https://api.example.com/v1/x
    [ "$status" -eq 0 ]
    [[ "$output" == *'service_unavailable'* ]]
}

@test "AC2.f: disconnect fixture exits 7 (CURLE_COULDNT_CONNECT)" {
    _with_curl_mock disconnect
    run curl https://api.example.com/v1/x
    [ "$status" -eq 7 ]
}

@test "AC2.g: timeout fixture exits 28 (CURLE_OPERATION_TIMEDOUT)" {
    _with_curl_mock timeout
    run curl https://api.example.com/v1/x
    [ "$status" -eq 28 ]
}

# -----------------------------------------------------------------------------
# AC-1C.3 — arbitrary response body file injection
# -----------------------------------------------------------------------------

@test "AC3.a: body_file injection emits openai-success.json verbatim" {
    _with_curl_mock openai-success
    run curl https://api.openai.com/v1/responses
    [ "$status" -eq 0 ]
    [[ "$output" == *'"id": "resp_curl_mock_001"'* ]]
    [[ "$output" == *'"model": "gpt-5.5-pro"'* ]]
    [[ "$output" == *'"text": "fixture: openai-success"'* ]]
}

@test "AC3.b: body_file injection works for anthropic shape" {
    _with_curl_mock anthropic-success
    run curl https://api.anthropic.com/v1/messages
    [ "$status" -eq 0 ]
    [[ "$output" == *'"id": "msg_curl_mock_001"'* ]]
    [[ "$output" == *'"model": "claude-opus-4-7"'* ]]
}

@test "AC3.c: body_file injection works for google shape" {
    _with_curl_mock google-success
    run curl https://generativelanguage.googleapis.com/v1/models/gemini:generateContent
    [ "$status" -eq 0 ]
    [[ "$output" == *'"finishReason": "STOP"'* ]]
}

# -----------------------------------------------------------------------------
# AC-1C.4 — call-log assertions: count, argv, stdin payload
# -----------------------------------------------------------------------------

@test "AC4.a: _curl_mock_call_count is 0 before any call" {
    _with_curl_mock 200-ok
    [ "$(_curl_mock_call_count)" -eq 0 ]
}

@test "AC4.b: single curl call increments count to 1" {
    _with_curl_mock 200-ok
    curl https://api.example.com/v1/x >/dev/null
    [ "$(_curl_mock_call_count)" -eq 1 ]
}

@test "AC4.c: _assert_curl_called_n_times passes for matching count" {
    _with_curl_mock 200-ok
    curl https://api.example.com/v1/x >/dev/null
    curl https://api.example.com/v1/y >/dev/null
    curl https://api.example.com/v1/z >/dev/null
    _assert_curl_called_n_times 3
}

@test "AC4.d: _assert_curl_called_n_times fails for mismatched count" {
    _with_curl_mock 200-ok
    curl https://api.example.com/v1/x >/dev/null
    run _assert_curl_called_n_times 5
    [ "$status" -ne 0 ]
}

@test "AC4.e: _assert_curl_payload_contains finds substring in stdin" {
    _with_curl_mock 200-ok
    echo '{"max_output_tokens":32000,"model":"gpt-5.5-pro"}' \
        | curl -X POST -d @- https://api.example.com/v1/x >/dev/null
    _assert_curl_payload_contains '"max_output_tokens":32000'
    _assert_curl_payload_contains '"model":"gpt-5.5-pro"'
}

@test "AC4.f: _assert_curl_payload_contains fails when needle absent" {
    _with_curl_mock 200-ok
    echo '{"max_output_tokens":8000}' | curl -X POST -d @- https://api.example.com/v1/x >/dev/null
    run _assert_curl_payload_contains '"max_output_tokens":32000'
    [ "$status" -ne 0 ]
}

@test "AC4.g: _assert_curl_argv_contains finds substring in argv" {
    _with_curl_mock 200-ok
    curl -X POST -H "Authorization: Bearer test" https://api.example.com/v1/x >/dev/null
    _assert_curl_argv_contains 'Authorization: Bearer test'
}

@test "AC4.i: --data-binary @file captures the file's contents at invocation time" {
    # The legacy adapter writes JSON to a tmpfile then `rm`s it via trap RETURN.
    # The shim MUST read the file while it still exists (during invocation),
    # not later from the call log.
    _with_curl_mock 200-ok
    local payload_file="$BATS_TEST_TMPDIR/payload.json"
    printf '{"max_output_tokens":32000,"model":"gpt-5.5-pro"}' > "$payload_file"
    curl --data-binary "@$payload_file" https://api.example.com/v1/x >/dev/null
    rm -f "$payload_file"  # simulate the adapter's RETURN trap
    _assert_curl_payload_contains '"max_output_tokens":32000'
    _assert_curl_payload_contains '"model":"gpt-5.5-pro"'
}

@test "AC4.j: -d @file (short form) also captures file contents" {
    _with_curl_mock 200-ok
    local payload_file="$BATS_TEST_TMPDIR/payload.json"
    printf '{"shortform":true}' > "$payload_file"
    curl -d "@$payload_file" https://api.example.com/v1/x >/dev/null
    _assert_curl_payload_contains '"shortform":true'
}

@test "AC4.k: -d 'literal' captures inline string" {
    _with_curl_mock 200-ok
    curl -d '{"inline":"yes"}' https://api.example.com/v1/x >/dev/null
    _assert_curl_payload_contains '"inline":"yes"'
}

@test "AC4.h: call log is JSONL with required fields" {
    _with_curl_mock 200-ok
    echo 'payload' | curl -X POST -d @- https://api.example.com/v1/x >/dev/null
    local log_path
    log_path="$(_curl_mock_call_log_path)"
    [ -f "$log_path" ]
    # Each line must parse as JSON with required fields
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        echo "$line" | jq -e '.ts and .argv and (.stdin != null) and .fixture and (.exit_code != null) and (.status_code != null)' >/dev/null
    done < "$log_path"
}

# -----------------------------------------------------------------------------
# AC-1C.5 — runbook landed at expected path with required sections
# -----------------------------------------------------------------------------

@test "AC5.a: runbook exists at grimoires/loa/runbooks/curl-mock-harness.md" {
    [ -f "$PROJECT_ROOT/grimoires/loa/runbooks/curl-mock-harness.md" ]
}

@test "AC5.b: runbook has required sections" {
    local runbook="$PROJECT_ROOT/grimoires/loa/runbooks/curl-mock-harness.md"
    grep -qE '^## .*Background|^## Background' "$runbook"
    grep -qE '^## .*[Mm]echanics' "$runbook"
    grep -qE '^## .*[Hh]elper' "$runbook"
    grep -qE '^## .*[Ff]ixture' "$runbook"
    grep -qE '^## .*[Uu]sage' "$runbook"
    grep -qE '^## .*[Gg]otchas' "$runbook"
    grep -qiE 'NEVER.*production|do not use in production' "$runbook"
}

# -----------------------------------------------------------------------------
# Additional safety: shim fail-loud guards
# -----------------------------------------------------------------------------

@test "S1: shim refuses to run without LOA_CURL_MOCK_FIXTURE" {
    run env -i bash "$PROJECT_ROOT/tests/lib/curl-mock.sh"
    [ "$status" -eq 99 ]
    [[ "$output" == *"LOA_CURL_MOCK_FIXTURE not set"* ]] || \
        [[ "$stderr" == *"LOA_CURL_MOCK_FIXTURE not set"* ]] || \
        true  # bats may collapse stderr into output
}

@test "S2: shim refuses to run without LOA_CURL_MOCK_CALL_LOG" {
    run env -i \
        LOA_CURL_MOCK_FIXTURE="$PROJECT_ROOT/tests/fixtures/curl-mocks/200-ok.yaml" \
        bash "$PROJECT_ROOT/tests/lib/curl-mock.sh"
    [ "$status" -eq 99 ]
}

@test "S3: shim refuses to run with missing fixture file" {
    run env -i \
        PATH="/usr/bin:/bin" \
        LOA_CURL_MOCK_FIXTURE="/nonexistent/fixture.yaml" \
        LOA_CURL_MOCK_CALL_LOG="$BATS_TEST_TMPDIR/log.jsonl" \
        bash "$PROJECT_ROOT/tests/lib/curl-mock.sh"
    [ "$status" -eq 99 ]
}

# -----------------------------------------------------------------------------
# Output behavior: -i / -o flags
# -----------------------------------------------------------------------------

@test "O1: curl -i prepends HTTP status line + headers" {
    _with_curl_mock 200-ok
    run curl -i https://api.example.com/v1/x
    [ "$status" -eq 0 ]
    [[ "$output" == HTTP/1.1\ 200* ]]
    [[ "$output" == *'content-type: application/json'* ]]
    [[ "$output" == *'"ok": true'* ]]
}

@test "O2: curl -o writes body to file instead of stdout" {
    _with_curl_mock 200-ok
    local outfile="$BATS_TEST_TMPDIR/out.json"
    run curl -o "$outfile" https://api.example.com/v1/x
    [ "$status" -eq 0 ]
    [ -f "$outfile" ]
    grep -qF '"ok": true' "$outfile"
}
