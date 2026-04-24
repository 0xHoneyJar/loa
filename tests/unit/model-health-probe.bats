#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/model-health-probe.sh — cycle-093 sprint-3A
# Covers: state machine, provider adapters (SKP-001 fix), cache patterns,
#         PID sentinel, --canary mode, LOA_PROBE_LEGACY_BEHAVIOR fallback.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    PROBE="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"
    FIXTURES="$PROJECT_ROOT/.claude/tests/fixtures/provider-responses"

    # Isolated cache + trajectory + audit log for each test (Bridgebuilder F-002)
    TEST_DIR="$(mktemp -d)"
    export LOA_CACHE_DIR="$TEST_DIR"
    export LOA_TRAJECTORY_DIR="$TEST_DIR/trajectory"
    export LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl"
    export OPT_CACHE_PATH=""

    # Stub API keys so the "missing key" early-return doesn't fire in tests
    export OPENAI_API_KEY="test-openai"
    export GOOGLE_API_KEY="test-google"
    export ANTHROPIC_API_KEY="test-anthropic"

    # Default: mock mode on
    export LOA_PROBE_MOCK_MODE=1

    # Source the script functions (without running main)
    # shellcheck disable=SC1090
    eval "$(sed 's|^if \[\[ "${BASH_SOURCE\[0\]}" == "${0}" \]\]; then$|if false; then|' "$PROBE")"

    # Override trajectory dir so test writes stay in TEST_DIR
    TRAJECTORY_DIR="$TEST_DIR/trajectory"
    AUDIT_LOG="$TEST_DIR/audit.jsonl"
    CACHE_PATH_DEFAULT="$TEST_DIR/model-health-cache.json"
}

teardown() {
    rm -rf "$TEST_DIR"
    unset LOA_PROBE_MOCK_MODE LOA_PROBE_MOCK_HTTP_STATUS
    unset LOA_PROBE_MOCK_OPENAI LOA_PROBE_MOCK_GOOGLE LOA_PROBE_MOCK_ANTHROPIC
    unset LOA_PROBE_LEGACY_BEHAVIOR
}

# -----------------------------------------------------------------------------
# State machine (§3.2)
# -----------------------------------------------------------------------------
@test "state machine: UNKNOWN + ok -> AVAILABLE" {
    run _transition UNKNOWN ok
    [ "$output" = "AVAILABLE" ]
}

@test "state machine: UNKNOWN + hard_404 -> UNAVAILABLE" {
    run _transition UNKNOWN hard_404
    [ "$output" = "UNAVAILABLE" ]
}

@test "state machine: UNKNOWN + model_field_400 -> UNAVAILABLE" {
    run _transition UNKNOWN model_field_400
    [ "$output" = "UNAVAILABLE" ]
}

@test "state machine: UNKNOWN + transient -> UNKNOWN" {
    run _transition UNKNOWN transient
    [ "$output" = "UNKNOWN" ]
}

@test "state machine: UNKNOWN + auth -> UNKNOWN" {
    run _transition UNKNOWN auth
    [ "$output" = "UNKNOWN" ]
}

@test "state machine: AVAILABLE + ok -> AVAILABLE" {
    run _transition AVAILABLE ok
    [ "$output" = "AVAILABLE" ]
}

@test "state machine: AVAILABLE + hard_404 -> UNAVAILABLE (recovery)" {
    run _transition AVAILABLE hard_404
    [ "$output" = "UNAVAILABLE" ]
}

@test "state machine: AVAILABLE + transient -> UNKNOWN" {
    run _transition AVAILABLE transient
    [ "$output" = "UNKNOWN" ]
}

@test "state machine: UNAVAILABLE + ok -> AVAILABLE (flip-flop recovery)" {
    run _transition UNAVAILABLE ok
    [ "$output" = "AVAILABLE" ]
}

@test "state machine: UNAVAILABLE + transient -> UNKNOWN (emit UNKNOWN, retain UNAVAILABLE in cache)" {
    run _transition UNAVAILABLE transient
    [ "$output" = "UNKNOWN" ]
}

@test "state machine: UNAVAILABLE + hard_404 -> UNAVAILABLE" {
    run _transition UNAVAILABLE hard_404
    [ "$output" = "UNAVAILABLE" ]
}

@test "state machine: schema_mismatch signal always biases to UNKNOWN" {
    run _transition AVAILABLE schema_mismatch
    [ "$output" = "UNKNOWN" ]
    run _transition UNAVAILABLE schema_mismatch
    [ "$output" = "UNKNOWN" ]
    run _transition UNKNOWN schema_mismatch
    [ "$output" = "UNKNOWN" ]
}

@test "state machine: unknown signal biases to UNKNOWN (safety default)" {
    run _transition AVAILABLE weird_signal
    [ "$output" = "UNKNOWN" ]
}

# -----------------------------------------------------------------------------
# Cache patterns (§3.5–§3.6)
# -----------------------------------------------------------------------------
@test "cache: cold-start returns empty shell with schema_version" {
    OPT_CACHE_PATH="$TEST_DIR/cold.json"
    run _cache_read
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.schema_version == "1.0"' >/dev/null
    echo "$output" | jq -e '.entries == {}' >/dev/null
}

@test "cache: atomic write persists entry readable after" {
    OPT_CACHE_PATH="$TEST_DIR/probe.json"
    local entry='{"state":"AVAILABLE","confidence":"high","reason":"test","http_status":200,"latency_ms":42,"probed_at":"2026-04-24T00:00:00Z","ttl_seconds":86400,"last_known_good_at":"2026-04-24T00:00:00Z"}'
    run _cache_merge_entry openai gpt-test "$entry"
    [ "$status" -eq 0 ]
    run _cache_read
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.entries["openai:gpt-test"].state == "AVAILABLE"' >/dev/null
}

@test "cache: schema mismatch discarded -> empty shell returned" {
    OPT_CACHE_PATH="$TEST_DIR/stale.json"
    printf '{"schema_version":"0.9","entries":{"openai:old":{"state":"AVAILABLE"}}}\n' > "$OPT_CACHE_PATH"
    local out
    out="$(_cache_read 2>/dev/null)"
    echo "$out" | jq -e '.schema_version == "1.0"' >/dev/null
    echo "$out" | jq -e '.entries == {}' >/dev/null
}

@test "cache: corrupt JSON on read retries then cold-starts" {
    OPT_CACHE_PATH="$TEST_DIR/corrupt.json"
    printf 'not valid json {{{\n' > "$OPT_CACHE_PATH"
    local out
    out="$(_cache_read 2>/dev/null)"
    echo "$out" | jq -e '.schema_version == "1.0"' >/dev/null
    echo "$out" | jq -e '.entries == {}' >/dev/null
}

@test "cache: invalidate with argument removes only target entry" {
    OPT_CACHE_PATH="$TEST_DIR/multi.json"
    local a b
    a='{"state":"AVAILABLE","reason":"a"}'
    b='{"state":"AVAILABLE","reason":"b"}'
    _cache_merge_entry openai a "$a"
    _cache_merge_entry openai b "$b"
    _cache_invalidate a
    run _cache_read
    echo "$output" | jq -e '.entries["openai:a"] == null' >/dev/null
    echo "$output" | jq -e '.entries["openai:b"].reason == "b"' >/dev/null
}

@test "cache: invalidate with no arg wipes everything" {
    OPT_CACHE_PATH="$TEST_DIR/wipe.json"
    _cache_merge_entry openai x '{"state":"AVAILABLE"}'
    _cache_invalidate
    run _cache_read
    echo "$output" | jq -e '.entries == {}' >/dev/null
}

# -----------------------------------------------------------------------------
# PID sentinel (§3.6 Pattern 3)
# -----------------------------------------------------------------------------
@test "pid sentinel: stale pid file is cleaned (dead pid)" {
    local sentinel
    sentinel="$(_bg_probe_sentinel_path openai)"
    mkdir -p "$(dirname "$sentinel")"
    # Write a definitely-dead PID
    echo "99999999" > "$sentinel"
    # kill -0 on a dead pid should report it as dead; _spawn should clean up
    # We cannot actually verify bg-spawn here without integration, but the
    # cleanup path is deterministic: after _spawn_bg_probe_if_none_running
    # for a dead sentinel, the sentinel file should NOT still contain 99999999.
    # We run the function in a subshell that immediately exits to avoid actual spawn.
    LOA_PROBE_MOCK_MODE=1 \
        bash -c 'cd '"$PROJECT_ROOT"'; \
            eval "$(sed '"'"'s|^if \[\[ \"${BASH_SOURCE\[0\]}\" == \"${0}\" \]\]; then$|if false; then|'"'"' '"$PROBE"')"; \
            LOA_CACHE_DIR='"$TEST_DIR"' _spawn_bg_probe_if_none_running openai' &
    wait
    # Sentinel may be replaced with new PID or removed. Either way, 99999999 should be gone.
    if [[ -f "$sentinel" ]]; then
        run cat "$sentinel"
        [ "$output" != "99999999" ]
    fi
}

@test "pid sentinel: sentinel path scoped per-provider" {
    local p1 p2
    p1="$(_bg_probe_sentinel_path openai)"
    p2="$(_bg_probe_sentinel_path anthropic)"
    [ "$p1" != "$p2" ]
    [[ "$p1" =~ openai ]]
    [[ "$p2" =~ anthropic ]]
}

# -----------------------------------------------------------------------------
# Provider adapters — fixture-driven (§3.3)
# -----------------------------------------------------------------------------
@test "openai probe: model present in listing -> AVAILABLE" {
    LOA_PROBE_MOCK_HTTP_STATUS=200
    LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json"
    _probe_openai gpt-5.3-codex
    [ "$PROBE_STATE" = "AVAILABLE" ]
    [ "$PROBE_ERROR_CLASS" = "ok" ]
}

@test "openai probe: model absent from listing -> UNAVAILABLE" {
    LOA_PROBE_MOCK_HTTP_STATUS=200
    LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/unavailable.json"
    _probe_openai gpt-5.3-codex
    [ "$PROBE_STATE" = "UNAVAILABLE" ]
    [ "$PROBE_ERROR_CLASS" = "listing_miss" ]
}

@test "openai probe: 401 auth error -> UNKNOWN" {
    LOA_PROBE_MOCK_HTTP_STATUS=401
    _probe_openai gpt-5.3-codex
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "auth" ]
}

@test "openai probe: 503 transient -> UNKNOWN" {
    LOA_PROBE_MOCK_HTTP_STATUS=503
    _probe_openai gpt-5.3-codex
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

@test "openai probe: 429 rate-limit -> UNKNOWN (transient)" {
    LOA_PROBE_MOCK_HTTP_STATUS=429
    _probe_openai gpt-5.3-codex
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

@test "openai probe: schema mismatch -> UNKNOWN (contract-version guard)" {
    LOA_PROBE_MOCK_HTTP_STATUS=200
    # Write a body missing the expected 'data' array
    local bogus="$TEST_DIR/bogus.json"
    printf '{"object":"list","models":[]}\n' > "$bogus"
    LOA_PROBE_MOCK_OPENAI="$bogus"
    _probe_openai gpt-5.3-codex
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "schema_mismatch" ]
}

@test "google probe: model present in listing -> AVAILABLE" {
    LOA_PROBE_MOCK_HTTP_STATUS=200
    LOA_PROBE_MOCK_GOOGLE="$FIXTURES/google/available.json"
    _probe_google gemini-2.5-flash
    [ "$PROBE_STATE" = "AVAILABLE" ]
}

@test "google probe: NOT_FOUND body pattern -> UNAVAILABLE" {
    LOA_PROBE_MOCK_HTTP_STATUS=404
    LOA_PROBE_MOCK_GOOGLE="$FIXTURES/google/unavailable.json"
    _probe_google gemini-nonexistent
    [ "$PROBE_STATE" = "UNAVAILABLE" ]
    [ "$PROBE_ERROR_CLASS" = "hard_404" ]
}

@test "google probe: 503 transient -> UNKNOWN" {
    LOA_PROBE_MOCK_HTTP_STATUS=503
    _probe_google gemini-2.5-flash
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

# -----------------------------------------------------------------------------
# SKP-001 — Anthropic ambiguous-4xx regression test (the core fix)
# -----------------------------------------------------------------------------
@test "SKP-001 fix: anthropic 400 without 'model' in error message -> UNKNOWN (not AVAILABLE)" {
    LOA_PROBE_MOCK_HTTP_STATUS=400
    LOA_PROBE_MOCK_ANTHROPIC="$FIXTURES/anthropic/ambiguous-400.json"
    _probe_anthropic claude-opus-4-7
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [[ "$PROBE_REASON" == *"SKP-001"* ]]
}

@test "SKP-001 fix: anthropic 400 WITH 'model' in error message -> UNAVAILABLE" {
    LOA_PROBE_MOCK_HTTP_STATUS=400
    LOA_PROBE_MOCK_ANTHROPIC="$FIXTURES/anthropic/unavailable.json"
    _probe_anthropic claude-opus-nonexistent
    [ "$PROBE_STATE" = "UNAVAILABLE" ]
    [ "$PROBE_ERROR_CLASS" = "model_field_400" ]
}

@test "anthropic probe: 200 OK -> AVAILABLE" {
    LOA_PROBE_MOCK_HTTP_STATUS=200
    LOA_PROBE_MOCK_ANTHROPIC="$FIXTURES/anthropic/available.json"
    _probe_anthropic claude-opus-4-7
    [ "$PROBE_STATE" = "AVAILABLE" ]
}

@test "anthropic probe: 529 overloaded -> UNKNOWN transient" {
    LOA_PROBE_MOCK_HTTP_STATUS=529
    _probe_anthropic claude-opus-4-7
    [ "$PROBE_STATE" = "UNKNOWN" ]
    [ "$PROBE_ERROR_CLASS" = "transient" ]
}

# -----------------------------------------------------------------------------
# --canary non-blocking smoke mode (Flatline SKP-002)
# -----------------------------------------------------------------------------
@test "canary: returns exit 0 even when a model is UNAVAILABLE" {
    # Set up fixture that yields UNAVAILABLE for openai:gpt-5.3-codex
    LOA_PROBE_MOCK_HTTP_STATUS=200
    LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/unavailable.json"
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/unavailable.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --model gpt-5.3-codex --canary --quiet --output json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.exit_code == 0' >/dev/null
    echo "$output" | jq -e '.summary.unavailable >= 1' >/dev/null
}

@test "canary: no --canary flag -> exit 2 on UNAVAILABLE (baseline)" {
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/unavailable.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --model gpt-5.3-codex --quiet --output json
    [ "$status" -eq 2 ]
}

# -----------------------------------------------------------------------------
# LOA_PROBE_LEGACY_BEHAVIOR=1 emergency fallback (Flatline SKP-002)
# -----------------------------------------------------------------------------
@test "legacy-behavior fallback: LOA_PROBE_LEGACY_BEHAVIOR=1 forces AVAILABLE for all models" {
    run env LOA_PROBE_LEGACY_BEHAVIOR=1 \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet --output json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.summary.unavailable == 0' >/dev/null
    echo "$output" | jq -e '.summary.unknown == 0' >/dev/null
    echo "$output" | jq -e '.summary.available > 0' >/dev/null
    # Every entry should have AVAILABLE
    echo "$output" | jq -e '[.entries[] | .state] | all(. == "AVAILABLE")' >/dev/null
}

@test "legacy-behavior fallback: emits mandatory audit-log entry" {
    run env LOA_PROBE_LEGACY_BEHAVIOR=1 \
        LOA_CACHE_DIR="$TEST_DIR" \
        LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --model gpt-5.3-codex --quiet --output json
    [ "$status" -eq 0 ]
    # Hermetic audit log check via LOA_AUDIT_LOG override (Bridgebuilder F-002)
    [ -f "$TEST_DIR/audit.jsonl" ]
    grep -q 'probe_legacy_bypass' "$TEST_DIR/audit.jsonl"
}

# -----------------------------------------------------------------------------
# CLI contract — exit codes (§6.1)
# -----------------------------------------------------------------------------
@test "cli: --help exits 0 and shows usage" {
    run "$PROBE" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"model-health-probe.sh"* ]]
}

@test "cli: --version exits 0 and prints version" {
    run "$PROBE" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"1.0.0"* ]]
}

@test "cli: unknown flag exits 64" {
    run "$PROBE" --bogus-flag
    [ "$status" -eq 64 ]
}

@test "cli: invalid --provider value exits 64" {
    run "$PROBE" --provider acme
    [ "$status" -eq 64 ]
}

@test "cli: invalid --output value exits 64" {
    run "$PROBE" --output xml
    [ "$status" -eq 64 ]
}

@test "cli: --dry-run completes without HTTP calls" {
    unset LOA_PROBE_MOCK_MODE
    run env LOA_CACHE_DIR="$TEST_DIR" \
        "$PROBE" --dry-run --output json --quiet
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.summary.unknown >= 1' >/dev/null
    # Every entry should show reason "dry-run"
    echo "$output" | jq -e '[.entries[] | .reason] | all(. == "dry-run")' >/dev/null
}

@test "cli: --invalidate with no arg wipes cache" {
    OPT_CACHE_PATH="$TEST_DIR/inv.json"
    _cache_merge_entry openai z '{"state":"AVAILABLE"}'
    run env LOA_CACHE_DIR="$TEST_DIR" "$PROBE" --invalidate
    [ "$status" -eq 0 ]
    # Default cache path (under LOA_CACHE_DIR) should now be empty-shelled
    run cat "$TEST_DIR/model-health-cache.json"
    echo "$output" | jq -e '.entries == {}' >/dev/null
}
