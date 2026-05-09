#!/usr/bin/env bats
# =============================================================================
# tests/integration/model-adapter-call-shape.bats
#
# cycle-102 Sprint 1C T1C.5 — execution-level proof of model-adapter.sh.legacy
# call_*_api functions' payload bindings.
#
# Replaces (semantically; not by deletion) the awk-brace-counter static-grep
# approach in tests/unit/model-adapter-max-output-tokens.bats:F10a/F10b/F10c
# that DISS-002 BLOCKING flagged (sprint-1B-verify cross-model review).
#
# Why this is stronger than the static-grep tests:
#   - awk brace-counter mis-counts braces in heredocs / string literals /
#     comments. F10 in the unit file documents this explicitly as a known
#     limitation. Execution-level proof avoids the counter entirely.
#   - The unit tests assert "this function definition LOOKS LIKE it binds
#     the helper output to the payload field". The execution tests assert
#     "calling this function DOES bind the helper output to the actual
#     curl payload curl would have sent." Different (and stronger) claim.
#
# Sources: Issue #808; BB iter-4 REFRAME-1 (sprint-1A); BB iter-2 REFRAME-2
# (sprint-1B, vision-024); DISS-002 BLOCKING; vision-019/023.
# =============================================================================

load '../lib/curl-mock-helpers'

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LEGACY_ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh.legacy"

    [[ -f "$LEGACY_ADAPTER" ]] || {
        printf 'FATAL: legacy adapter not found at %s\n' "$LEGACY_ADAPTER" >&2
        return 1
    }

    # Sourcable copy: drop the trailing `main "$@"` invocation so
    # sourcing the file doesn't trigger CLI logic. Symlink the helpers
    # so source paths resolve correctly when SCRIPT_DIR is computed
    # from the test-tmpdir copy.
    SOURCABLE_DIR="$BATS_TEST_TMPDIR/adapter-src"
    mkdir -p "$SOURCABLE_DIR"
    ln -sf "$PROJECT_ROOT/.claude/scripts/bash-version-guard.sh" "$SOURCABLE_DIR/"
    ln -sf "$PROJECT_ROOT/.claude/scripts/time-lib.sh" "$SOURCABLE_DIR/"
    ln -sf "$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh" "$SOURCABLE_DIR/"
    sed '$d' "$LEGACY_ADAPTER" > "$SOURCABLE_DIR/model-adapter.sh.legacy"
    SOURCABLE_ADAPTER="$SOURCABLE_DIR/model-adapter.sh.legacy"

    # _lookup_max_output_tokens reads $SCRIPT_DIR/../defaults/model-config.yaml.
    # SCRIPT_DIR resolves to $SOURCABLE_DIR ($BATS_TEST_TMPDIR/adapter-src),
    # so the helper looks for $BATS_TEST_TMPDIR/defaults/model-config.yaml.
    # Symlink the real config into that path so per-model lookups resolve.
    mkdir -p "$BATS_TEST_TMPDIR/defaults"
    ln -sf "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
        "$BATS_TEST_TMPDIR/defaults/model-config.yaml"

    _setup_curl_mock_dirs
}

teardown() {
    _teardown_curl_mock
    if [[ -n "${SOURCABLE_DIR:-}" ]] && [[ -d "$SOURCABLE_DIR" ]]; then
        rm -rf "$SOURCABLE_DIR"
    fi
    return 0
}

# Helper: invoke a call_*_api function in a subshell with curl-mock active
# and the legacy adapter sourced. Returns the function's stdout to caller.
# Requires: _with_curl_mock <fixture> already invoked.
_invoke_call_api() {
    local fnname="$1"
    shift
    # Subshell containment: source pollution stays in the subshell; the
    # curl-mock call log is on the filesystem so writes persist.
    (
        # shellcheck disable=SC1090
        source "$SOURCABLE_ADAPTER" >/dev/null 2>&1
        "$fnname" "$@"
    )
}

# -----------------------------------------------------------------------------
# F10a-mock: call_openai_api binds max_output_tokens via real curl payload
# -----------------------------------------------------------------------------

@test "F10a-mock: call_openai_api with gpt-5.5-pro emits max_output_tokens=32000 in real payload (closes DISS-002)" {
    _with_curl_mock openai-success
    output="$(_invoke_call_api call_openai_api gpt-5.5-pro "sys prompt" "user prompt" 30 "test-key" 2>&1)"
    [ -n "$output" ]
    _assert_curl_called_n_times 1
    _assert_curl_payload_field max_output_tokens 32000
    _assert_curl_payload_field model '"gpt-5.5-pro"'
}

@test "F10a-mock: call_openai_api routes non-reasoning model to chat/completions endpoint" {
    _with_curl_mock openai-success
    # gpt-5.2 doesn't match *codex* or gpt-5.5* — routes to chat/completions
    # which uses a different payload shape (no max_output_tokens field).
    # Pin the routing decision: argv must contain the chat/completions URL.
    output="$(_invoke_call_api call_openai_api gpt-5.2 "sys" "user" 30 "test-key" 2>&1)" || true
    _assert_curl_called_n_times 1
    _assert_curl_argv_contains 'api.openai.com/v1/chat/completions'
}

# -----------------------------------------------------------------------------
# F10b-mock: call_anthropic_api binds max_tokens
# -----------------------------------------------------------------------------

@test "F10b-mock: call_anthropic_api with claude-opus-4-7 emits max_tokens=32000 in real payload (closes DISS-002)" {
    _with_curl_mock anthropic-success
    output="$(_invoke_call_api call_anthropic_api claude-opus-4-7 "sys prompt" "user prompt" 30 "test-key" 2>&1)"
    [ -n "$output" ]
    _assert_curl_called_n_times 1
    _assert_curl_payload_field max_tokens 32000
    _assert_curl_payload_field model '"claude-opus-4-7"'
}

@test "F10b-mock: call_anthropic_api with claude-sonnet-4-6 emits configured max_tokens" {
    _with_curl_mock anthropic-success
    output="$(_invoke_call_api call_anthropic_api claude-sonnet-4-6 "sys" "user" 30 "test-key" 2>&1)"
    [ -n "$output" ]
    _assert_curl_called_n_times 1
    _assert_curl_payload_field model '"claude-sonnet-4-6"'
    # Assert max_tokens is at least 1024 (any sensible default would be ≥1k)
    local max_tok
    max_tok=$(jq -r '.stdin | fromjson | .max_tokens' "$_CURL_MOCK_LOG_PATH" | head -1)
    [[ -n "$max_tok" && "$max_tok" -ge 1024 ]]
}

# -----------------------------------------------------------------------------
# F10c-mock: call_google_api binds maxOutputTokens
# -----------------------------------------------------------------------------

@test "F10c-mock: call_google_api with gemini-3.1-pro-preview emits maxOutputTokens=32000 in real payload (closes DISS-002)" {
    _with_curl_mock google-success
    output="$(_invoke_call_api call_google_api gemini-3.1-pro-preview "sys prompt" "user prompt" 30 "test-key" 2>&1)"
    [ -n "$output" ]
    _assert_curl_called_n_times 1
    # Google adapter pretty-prints JSON; field-level check is whitespace-insensitive.
    _assert_curl_payload_field maxOutputTokens 32000
}

# -----------------------------------------------------------------------------
# Helper-invocation proof: substituting _lookup_max_output_tokens with a
# sentinel proves the function actually invokes the helper at runtime
# (replaces F10d static-grep "function body contains _lookup_max_output_tokens").
# -----------------------------------------------------------------------------

@test "F10d-mock: call_openai_api invokes _lookup_max_output_tokens at runtime (sentinel substitution)" {
    _with_curl_mock openai-success
    # Override _lookup_max_output_tokens with a sentinel value before sourcing
    # to prove the function actually CALLS the helper (vs. hardcoding the value).
    output="$(
        # shellcheck disable=SC1090
        source "$SOURCABLE_ADAPTER" >/dev/null 2>&1
        _lookup_max_output_tokens() { echo 99999; }
        # BB iter-1 F11 closure: dropped `export -f ... 2>/dev/null || true`
        # which masked override failure. Now assert the override took before
        # invoking the call_*_api function — sentinel only valid if observable.
        [[ "$(_lookup_max_output_tokens openai gpt-5.5-pro 8000)" == "99999" ]]
        call_openai_api gpt-5.5-pro "sys" "user" 30 "test-key" 2>&1
    )"
    _assert_curl_called_n_times 1
    _assert_curl_payload_field max_output_tokens 99999
}

@test "F10d-mock: call_anthropic_api invokes _lookup_max_output_tokens at runtime" {
    _with_curl_mock anthropic-success
    output="$(
        # shellcheck disable=SC1090
        source "$SOURCABLE_ADAPTER" >/dev/null 2>&1
        _lookup_max_output_tokens() { echo 99999; }
        # BB iter-1 F11 closure: dropped `export -f ... 2>/dev/null || true`
        # which masked override failure. Now assert the override took before
        # invoking the call_*_api function — sentinel only valid if observable.
        [[ "$(_lookup_max_output_tokens openai gpt-5.5-pro 8000)" == "99999" ]]
        call_anthropic_api claude-opus-4-7 "sys" "user" 30 "test-key" 2>&1
    )"
    _assert_curl_called_n_times 1
    _assert_curl_payload_field max_tokens 99999
}

@test "F10d-mock: call_google_api invokes _lookup_max_output_tokens at runtime" {
    _with_curl_mock google-success
    output="$(
        # shellcheck disable=SC1090
        source "$SOURCABLE_ADAPTER" >/dev/null 2>&1
        _lookup_max_output_tokens() { echo 99999; }
        # BB iter-1 F11 closure: dropped `export -f ... 2>/dev/null || true`
        # which masked override failure. Now assert the override took before
        # invoking the call_*_api function — sentinel only valid if observable.
        [[ "$(_lookup_max_output_tokens openai gpt-5.5-pro 8000)" == "99999" ]]
        call_google_api gemini-3.1-pro-preview "sys" "user" 30 "test-key" 2>&1
    )"
    _assert_curl_called_n_times 1
    _assert_curl_payload_field maxOutputTokens 99999
}

# -----------------------------------------------------------------------------
# vision-019/023 anti-silent-degradation pin: the post-T1.9 invariant
# -----------------------------------------------------------------------------

@test "vision-019: gpt-5.5-pro at 30s timeout still emits 32000 max_output_tokens (NEVER 8000)" {
    _with_curl_mock openai-success
    output="$(_invoke_call_api call_openai_api gpt-5.5-pro "sys" "user" 30 "test-key" 2>&1)"
    _assert_curl_called_n_times 1
    # The bug class: gpt-5.5-pro returning empty content because budget
    # starvation. Pin: payload MUST emit the 32K configured value, not
    # the 8000 fallback. If this regresses, vision-019/023 returns.
    _assert_curl_payload_field max_output_tokens 32000
    # Negative control: ensure the 8000 default is NOT in the payload
    if jq -e '.stdin | fromjson | .max_output_tokens == 8000' "$_CURL_MOCK_LOG_PATH" >/dev/null 2>&1; then
        printf 'vision-019 REGRESSION: max_output_tokens=8000 in payload for gpt-5.5-pro\n' >&2
        return 1
    fi
}
