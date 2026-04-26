#!/usr/bin/env bats
# =============================================================================
# Sprint-4 T4.7 — Probe-integration verification (closes G4 + G6 re-scoped)
#
# Asserts the Sprint-3 probe correctly handles the two new models added by
# Sprint-4 T4.1 (gemini-3.1-pro-preview) and T4.5 (gpt-5.5 / gpt-5.5-pro).
#
#   - gemini-3.1-pro-preview: with mocked listing → AVAILABLE
#   - gpt-5.5 / gpt-5.5-pro: with default fixture (NOT containing them) →
#     UNAVAILABLE
#   - gpt-5.5: when fixture is swapped to gpt-5.5-listed.json → AVAILABLE
#     (proves the probe auto-enables on listing change without code edits)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    PROBE="$PROJECT_ROOT/.claude/scripts/model-health-probe.sh"
    FIXTURES="$PROJECT_ROOT/.claude/tests/fixtures/provider-responses"

    TEST_DIR="$(mktemp -d)"
    export LOA_CACHE_DIR="$TEST_DIR"
    export LOA_TRAJECTORY_DIR="$TEST_DIR/trajectory"
    export LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl"
    export OPENAI_API_KEY="test-openai"
    export GOOGLE_API_KEY="test-google"
    export ANTHROPIC_API_KEY="test-anthropic"
    export LOA_PROBE_MOCK_MODE=1
}

teardown() {
    [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && {
        find "$TEST_DIR" -mindepth 1 -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    }
    unset LOA_PROBE_MOCK_OPENAI LOA_PROBE_MOCK_GOOGLE LOA_PROBE_MOCK_HTTP_STATUS
}

# -----------------------------------------------------------------------------
# Sprint-4 T4.1 — gemini-3.1-pro-preview AVAILABILITY (closes G4)
# -----------------------------------------------------------------------------
@test "T4.1: gemini-3.1-pro-preview AVAILABLE when listed in v1beta/models" {
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_GOOGLE="$FIXTURES/google/gemini-3.1-listed.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        GOOGLE_API_KEY=test \
        "$PROBE" --provider google --model gemini-3.1-pro-preview --quiet --output json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.entries["google:gemini-3.1-pro-preview"].state == "AVAILABLE"' >/dev/null
}

# -----------------------------------------------------------------------------
# Sprint-4 T4.5 — GPT-5.5 latent UNTIL listed (closes G6 re-scoped per
# Flatline SKP-002 HIGH — infrastructure ready, not live operational)
# -----------------------------------------------------------------------------
@test "T4.5 (latent): gpt-5.5 UNAVAILABLE when default fixture omits it" {
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --model gpt-5.5 --quiet --output json
    [ "$status" -eq 2 ]    # exit 2 = at least one UNAVAILABLE
    echo "$output" | jq -e '.entries["openai:gpt-5.5"].state == "UNAVAILABLE"' >/dev/null
}

@test "T4.5 (transition): gpt-5.5 AVAILABLE after fixture-swap to gpt-5.5-listed" {
    # Fixture-swap simulates the API-ship moment (OpenAI starts returning gpt-5.5).
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/gpt-5.5-listed.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --model gpt-5.5 --quiet --output json
    [ "$status" -eq 0 ]    # AVAILABLE — no UNAVAILABLE in summary
    echo "$output" | jq -e '.entries["openai:gpt-5.5"].state == "AVAILABLE"' >/dev/null
}

@test "T4.5 (transition): gpt-5.5-pro AVAILABLE on same fixture-swap" {
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/gpt-5.5-listed.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --model gpt-5.5-pro --quiet --output json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.entries["openai:gpt-5.5-pro"].state == "AVAILABLE"' >/dev/null
}

# -----------------------------------------------------------------------------
# Sprint-4 T4.1 negative: gemini-3.1-pro-preview UNAVAILABLE if listing rolls back
# -----------------------------------------------------------------------------
@test "T4.1 (regression-defense): gemini-3.1-pro-preview UNAVAILABLE if delisted" {
    # Default available.json does NOT contain gemini-3.1-pro-preview.
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_GOOGLE="$FIXTURES/google/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        GOOGLE_API_KEY=test \
        "$PROBE" --provider google --model gemini-3.1-pro-preview --quiet --output json
    [ "$status" -eq 2 ]
    echo "$output" | jq -e '.entries["google:gemini-3.1-pro-preview"].state == "UNAVAILABLE"' >/dev/null
}
