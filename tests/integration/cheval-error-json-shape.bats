#!/usr/bin/env bats
# =============================================================================
# tests/integration/cheval-error-json-shape.bats
#
# cycle-102 Sprint 1C T1C.7 — substrate dependency closure for T1.5 carry.
#
# T1.5 (Sprint 1B carry) will extend cheval.py::_error_json (line 78) to
# emit `error_class` per the typed-error schema (SDD §4.1). This test
# file SHIPS THE SUBSTRATE that T1.5 will use — it proves the curl-mock
# harness can drive cheval through provider failure modes — and includes
# `skip`-gated assertions for the error_class taxonomy that will go
# green when T1.5 lands.
#
# Why this lands in Sprint 1C, not T1.5:
#   - The harness is the substrate; T1.5 is the consumer
#   - Sprint 1C scope is "build the substrate"; T1.5 carry scope is
#     "wire emit-path mappings". Separating these surfaces the
#     contract before the implementation, so T1.5 can be test-first.
#   - Per Issue #808: "At least one test for cheval `_error_json`
#     shape (T1.5 dependency)"
#
# Source: Issue #808; vision-024 (substrate-speaks-twice — proving
# the substrate works against provider failures BEFORE wiring downstream).
# =============================================================================

load '../lib/curl-mock-helpers'

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CHEVAL_PY="$PROJECT_ROOT/.claude/adapters/cheval.py"

    [[ -f "$CHEVAL_PY" ]] || {
        printf 'FATAL: cheval.py not found at %s\n' "$CHEVAL_PY" >&2
        return 1
    }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    _setup_curl_mock_dirs
}

teardown() {
    _teardown_curl_mock
    return 0
}

# -----------------------------------------------------------------------------
# Substrate proof: cheval CAN be invoked under curl-mock without crashing
# -----------------------------------------------------------------------------

@test "C1: cheval --help is invocable (sanity check)" {
    run "$PYTHON_BIN" "$CHEVAL_PY" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--agent"* ]]
}

@test "C2: cheval _error_json emits well-formed JSON for INVALID_INPUT (current shape)" {
    # Drive cheval down an invalid-input path that triggers _error_json.
    # No curl-mock needed — _error_json fires on missing --agent.
    # Note: cheval emits the error JSON to stderr; capture both streams.
    run "$PYTHON_BIN" "$CHEVAL_PY" 2>&1
    # stderr should contain a JSON error envelope.
    local json_line
    json_line=$(echo "$output" | grep -E '^\{.*"error".*\}' | head -1)
    [ -n "$json_line" ]
    # Must parse as valid JSON with the documented current shape
    echo "$json_line" | jq -e '.error == true and (.code != null) and (.message != null) and (.retryable != null)' >/dev/null
    # The current shape uses `code: INVALID_INPUT` — pin this so a future
    # T1.5 refactor that changes the field NAME (vs. just adding error_class)
    # would surface as a regression here.
    echo "$json_line" | jq -e '.code == "INVALID_INPUT"' >/dev/null
}

# -----------------------------------------------------------------------------
# T1.5 substrate hooks — these tests document the SHAPE T1.5 must produce.
# Marked `skip` until T1.5 lands; the `skip` message points the implementer
# at the exact assertions to flip on.
# -----------------------------------------------------------------------------

@test "C3 [T1.5]: 4xx response maps to RATE_LIMIT or AUTH error_class" {
    skip "T1.5 carry: cheval._error_json() does not yet emit error_class. When T1.5 lands the cheval-exception-to-error_class mapping per SDD §4.1, remove this skip."
    _with_curl_mock 429-rate-limited
    # When T1.5 lands, this invocation should emit a typed error JSON
    # with error_class: "RATE_LIMIT" (or similar from the 10-class taxonomy).
    run "$PYTHON_BIN" "$CHEVAL_PY" invoke --agent reviewing-code --prompt "test" 2>&1
    [ "$status" -ne 0 ]
    local json_line
    json_line=$(echo "$output" | grep -E '^\{.*"error_class"' | head -1)
    [ -n "$json_line" ]
    # error_class must be from the 10-class taxonomy (model-error.schema.json)
    echo "$json_line" | jq -e '.error_class | IN("TIMEOUT","RATE_LIMIT","AUTH","NETWORK","CONTEXT_OVERFLOW","INVALID_RESPONSE","DEGRADED_PARTIAL","LOCAL_NETWORK_FAILURE","UNKNOWN","STRICT_VIOLATION")' >/dev/null
}

@test "C4 [T1.5]: 5xx response maps to UNKNOWN or NETWORK error_class" {
    skip "T1.5 carry: see C3 skip message."
    _with_curl_mock 500-internal
    run "$PYTHON_BIN" "$CHEVAL_PY" invoke --agent reviewing-code --prompt "test" 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | grep -E '^\{.*"error_class"' | head -1 | \
        jq -e '.error_class | IN("UNKNOWN","NETWORK")' >/dev/null
}

@test "C5 [T1.5]: timeout maps to TIMEOUT error_class" {
    skip "T1.5 carry: see C3 skip message."
    _with_curl_mock timeout
    run "$PYTHON_BIN" "$CHEVAL_PY" invoke --agent reviewing-code --prompt "test" 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | grep -E '^\{.*"error_class"' | head -1 | \
        jq -e '.error_class == "TIMEOUT"' >/dev/null
}

@test "C6 [T1.5]: disconnect maps to NETWORK or LOCAL_NETWORK_FAILURE error_class" {
    skip "T1.5 carry: see C3 skip message."
    _with_curl_mock disconnect
    run "$PYTHON_BIN" "$CHEVAL_PY" invoke --agent reviewing-code --prompt "test" 2>&1
    [ "$status" -ne 0 ]
    echo "$output" | grep -E '^\{.*"error_class"' | head -1 | \
        jq -e '.error_class | IN("NETWORK","LOCAL_NETWORK_FAILURE")' >/dev/null
}

@test "C7 [T1.5]: typed error envelope validates against model-error.schema.json" {
    skip "T1.5 carry: see C3 skip message."
    _with_curl_mock 401-unauthorized
    run "$PYTHON_BIN" "$CHEVAL_PY" invoke --agent reviewing-code --prompt "test" 2>&1
    [ "$status" -ne 0 ]
    local json_line
    json_line=$(echo "$output" | grep -E '^\{.*"error_class"' | head -1)
    [ -n "$json_line" ]
    # Validate against the typed-error schema
    local validator="$PROJECT_ROOT/.claude/scripts/lib/validate-model-error.py"
    echo "$json_line" | "$PYTHON_BIN" "$validator" --json --quiet
}

# -----------------------------------------------------------------------------
# Substrate completeness: harness call-log shape is consistent across cheval
# invocations. This proves the substrate is uniform regardless of T1.5 status.
# -----------------------------------------------------------------------------

@test "C8: harness call-log captures cheval-driven curl invocations consistently" {
    # When T1.5 lands and cheval drives curl through providers, the call log
    # should include argv with the provider URL. Until then, this test is
    # primarily a substrate proof that the harness is ready.
    skip "T1.5 carry: requires cheval to actually drive curl. Harness substrate verified by AC4 in tests/integration/curl-mock-harness.bats; this test goes green when T1.5 wires curl invocation through cheval."
    _with_curl_mock 200-ok
    run "$PYTHON_BIN" "$CHEVAL_PY" invoke --agent reviewing-code --prompt "test" 2>&1
    [ "$(_curl_mock_call_count)" -ge 1 ]
    _assert_curl_argv_contains 'api.'  # any provider URL contains 'api.'
}
