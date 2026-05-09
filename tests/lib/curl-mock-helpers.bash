#!/usr/bin/env bash
# =============================================================================
# tests/lib/curl-mock-helpers.bash — bats helpers for curl-mock harness
# =============================================================================
#
# cycle-102 Sprint 1C T1C.2 (Issue #808). Provides hermetic activation +
# assertion helpers for the tests/lib/curl-mock.sh shim.
#
# Usage from a bats test:
#
#   load '../lib/curl-mock-helpers'
#
#   setup() {
#       _setup_curl_mock_dirs
#   }
#
#   teardown() {
#       _teardown_curl_mock
#   }
#
#   @test "adapter binds max_output_tokens correctly" {
#       _with_curl_mock 200-ok
#       run my-adapter --provider openai --model gpt-5.5-pro
#       [ "$status" -eq 0 ]
#       _assert_curl_called_n_times 1
#       _assert_curl_payload_contains '"max_output_tokens":32000'
#   }
#
# Hermetic teardown: explicit if/then/fi block, returns 0 — avoids the
# `&&`-chained pattern that bit Sprint 1A's `ff26be2d` (BATS marks tests
# 'not ok' when teardown's && short-circuits while skip is in effect).
# =============================================================================

# -----------------------------------------------------------------------------
# Internal: locate paths
# -----------------------------------------------------------------------------

_curl_mock_repo_root() {
    # bats sets BATS_TEST_FILENAME to the test file path; walk up to find
    # the repo root (containing tests/lib/curl-mock.sh).
    local d="${BATS_TEST_DIRNAME:-$PWD}"
    while [[ "$d" != "/" && -n "$d" ]]; do
        if [[ -f "$d/tests/lib/curl-mock.sh" ]]; then
            printf '%s' "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done
    printf 'curl-mock-helpers: cannot locate repo root from %s\n' "${BATS_TEST_DIRNAME:-$PWD}" >&2
    return 1
}

_curl_mock_shim_path() {
    local root
    root="$(_curl_mock_repo_root)" || return 1
    printf '%s/tests/lib/curl-mock.sh' "$root"
}

_curl_mock_fixtures_dir() {
    local root
    root="$(_curl_mock_repo_root)" || return 1
    printf '%s/tests/fixtures/curl-mocks' "$root"
}

# -----------------------------------------------------------------------------
# Setup / teardown — call from bats setup()/teardown()
# -----------------------------------------------------------------------------

_setup_curl_mock_dirs() {
    # Create per-test scratch space. BATS_TEST_TMPDIR is set by bats.
    : "${BATS_TEST_TMPDIR:?BATS_TEST_TMPDIR not set — must run under bats}"
    _CURL_MOCK_BIN_DIR="$BATS_TEST_TMPDIR/curl-mock-bin"
    _CURL_MOCK_LOG_PATH="$BATS_TEST_TMPDIR/curl-mock-calls.jsonl"
    mkdir -p "$_CURL_MOCK_BIN_DIR"
    : > "$_CURL_MOCK_LOG_PATH"
    _CURL_MOCK_ORIG_PATH="$PATH"
    return 0
}

_teardown_curl_mock() {
    # Restore PATH if it was modified
    if [[ -n "${_CURL_MOCK_ORIG_PATH:-}" ]]; then
        export PATH="$_CURL_MOCK_ORIG_PATH"
    fi
    unset LOA_CURL_MOCK_FIXTURE LOA_CURL_MOCK_CALL_LOG LOA_CURL_MOCK_DEBUG
    unset _CURL_MOCK_BIN_DIR _CURL_MOCK_LOG_PATH _CURL_MOCK_ORIG_PATH
    # bats teardown convention: explicit return 0 to avoid && short-circuit
    return 0
}

# -----------------------------------------------------------------------------
# Activation: _with_curl_mock <fixture-name>
#
# fixture-name is resolved against tests/fixtures/curl-mocks/ — strip
# any .yaml extension; we add it back. Absolute paths are honored as-is.
# -----------------------------------------------------------------------------

_with_curl_mock() {
    local fixture="$1"
    if [[ -z "${_CURL_MOCK_BIN_DIR:-}" ]]; then
        printf '_with_curl_mock: must call _setup_curl_mock_dirs in setup() first\n' >&2
        return 1
    fi

    # Resolve fixture path
    local fixture_path
    if [[ "$fixture" == /* ]]; then
        fixture_path="$fixture"
    else
        local fixtures_dir
        fixtures_dir="$(_curl_mock_fixtures_dir)" || return 1
        # Try with and without .yaml suffix
        if [[ -f "$fixtures_dir/${fixture}.yaml" ]]; then
            fixture_path="$fixtures_dir/${fixture}.yaml"
        elif [[ -f "$fixtures_dir/$fixture" ]]; then
            fixture_path="$fixtures_dir/$fixture"
        else
            printf '_with_curl_mock: fixture not found: %s (looked in %s)\n' \
                "$fixture" "$fixtures_dir" >&2
            return 1
        fi
    fi

    # Install shim symlink
    local shim
    shim="$(_curl_mock_shim_path)" || return 1
    ln -sf "$shim" "$_CURL_MOCK_BIN_DIR/curl"

    # Prepend bin dir to PATH (only once per test)
    case ":$PATH:" in
        *":$_CURL_MOCK_BIN_DIR:"*) ;;
        *) export PATH="$_CURL_MOCK_BIN_DIR:$PATH" ;;
    esac

    export LOA_CURL_MOCK_FIXTURE="$fixture_path"
    export LOA_CURL_MOCK_CALL_LOG="$_CURL_MOCK_LOG_PATH"
    return 0
}

# -----------------------------------------------------------------------------
# Assertions
# -----------------------------------------------------------------------------

_curl_mock_call_log_path() {
    printf '%s' "$_CURL_MOCK_LOG_PATH"
}

_curl_mock_call_count() {
    # Count non-empty lines. Use awk (exit 0 even on empty input) instead of
    # `grep -c` which exits 1 on zero matches AND prints "0", causing
    # `grep -c ... || printf '0'` to emit two zeros.
    if [[ ! -f "$_CURL_MOCK_LOG_PATH" ]]; then
        printf '0'
        return 0
    fi
    awk 'NF { n++ } END { print n+0 }' "$_CURL_MOCK_LOG_PATH"
}

_assert_curl_called_n_times() {
    local expected="$1"
    local actual
    actual="$(_curl_mock_call_count)"
    if [[ "$actual" != "$expected" ]]; then
        printf '_assert_curl_called_n_times: expected %s, got %s\n' "$expected" "$actual" >&2
        printf '  call log: %s\n' "$_CURL_MOCK_LOG_PATH" >&2
        if [[ -f "$_CURL_MOCK_LOG_PATH" ]]; then
            printf '  contents:\n' >&2
            sed 's/^/    /' "$_CURL_MOCK_LOG_PATH" >&2
        fi
        return 1
    fi
    return 0
}

_assert_curl_payload_contains() {
    # Asserts the substring appears in stdin payload of AT LEAST ONE call.
    local needle="$1"
    if [[ ! -f "$_CURL_MOCK_LOG_PATH" ]] || [[ ! -s "$_CURL_MOCK_LOG_PATH" ]]; then
        printf '_assert_curl_payload_contains: no calls recorded\n' >&2
        return 1
    fi
    # Use jq to extract stdin per call, grep for needle
    if command -v jq >/dev/null 2>&1; then
        if jq -r '.stdin' "$_CURL_MOCK_LOG_PATH" | grep -qF -- "$needle"; then
            return 0
        fi
    else
        # Fallback: substring in any line of the log
        if grep -qF -- "$needle" "$_CURL_MOCK_LOG_PATH"; then
            return 0
        fi
    fi
    printf '_assert_curl_payload_contains: needle not found: %s\n' "$needle" >&2
    printf '  call log: %s\n' "$_CURL_MOCK_LOG_PATH" >&2
    if [[ -f "$_CURL_MOCK_LOG_PATH" ]]; then
        printf '  contents:\n' >&2
        sed 's/^/    /' "$_CURL_MOCK_LOG_PATH" >&2
    fi
    return 1
}

_assert_curl_payload_field() {
    # Assert a JSON field has an exact value in at least one call's stdin
    # payload. Whitespace-insensitive (handles pretty-printed and minified
    # JSON uniformly). Uses jq.
    #
    #   _assert_curl_payload_field max_output_tokens 32000
    #   _assert_curl_payload_field model '"gpt-5.5-pro"'   # quote string values
    #
    # Searches recursively — any depth in the JSON tree matches. For nested
    # paths use _assert_curl_payload_jq for full jq expression power.
    local field="$1"
    local expected="$2"
    if [[ ! -f "$_CURL_MOCK_LOG_PATH" ]] || [[ ! -s "$_CURL_MOCK_LOG_PATH" ]]; then
        printf '_assert_curl_payload_field: no calls recorded\n' >&2
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        printf '_assert_curl_payload_field: jq required\n' >&2
        return 2
    fi
    local found
    found=$(jq -r --arg field "$field" --argjson expected "$expected" '
        .stdin
        | (try fromjson catch null)
        | select(. != null)
        | [.. | objects | to_entries[] | select(.key == $field) | .value]
        | any(. == $expected)
    ' "$_CURL_MOCK_LOG_PATH" 2>/dev/null | grep -q true && echo "true" || echo "false")
    if [[ "$found" == "true" ]]; then
        return 0
    fi
    printf '_assert_curl_payload_field: field %s != %s in any call\n' "$field" "$expected" >&2
    printf '  call log: %s\n' "$_CURL_MOCK_LOG_PATH" >&2
    if [[ -f "$_CURL_MOCK_LOG_PATH" ]]; then
        printf '  recorded payloads:\n' >&2
        jq -r '.stdin | (try fromjson catch .) | tostring' "$_CURL_MOCK_LOG_PATH" 2>/dev/null \
            | sed 's/^/    /' >&2
    fi
    return 1
}

_assert_curl_argv_contains() {
    # Asserts the substring appears in argv of AT LEAST ONE call.
    local needle="$1"
    if [[ ! -f "$_CURL_MOCK_LOG_PATH" ]] || [[ ! -s "$_CURL_MOCK_LOG_PATH" ]]; then
        printf '_assert_curl_argv_contains: no calls recorded\n' >&2
        return 1
    fi
    if command -v jq >/dev/null 2>&1; then
        if jq -r '.argv | join(" ")' "$_CURL_MOCK_LOG_PATH" | grep -qF -- "$needle"; then
            return 0
        fi
    else
        if grep -qF -- "$needle" "$_CURL_MOCK_LOG_PATH"; then
            return 0
        fi
    fi
    printf '_assert_curl_argv_contains: needle not found in any argv: %s\n' "$needle" >&2
    return 1
}
