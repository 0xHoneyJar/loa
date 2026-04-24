#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/model-health-probe.sh — hard-stop budget semantics
# Task 3A.hardstop_tests (Flatline IMP-006) — cycle-093 sprint-3A
# Each budget breach MUST exit 5 AND emit telemetry to .run/trajectory/ first.
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
    export LOA_PROBE_MOCK_HTTP_STATUS=200
    export LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json"
    export LOA_PROBE_MOCK_GOOGLE="$FIXTURES/google/available.json"
    export LOA_PROBE_MOCK_ANTHROPIC="$FIXTURES/anthropic/available.json"
}

teardown() {
    rm -rf "$TEST_DIR"
    unset LOA_PROBE_MAX_PROBES LOA_PROBE_MAX_COST_CENTS LOA_PROBE_INVOCATION_TIMEOUT
    unset LOA_PROBE_MOCK_MODE LOA_PROBE_MOCK_HTTP_STATUS
    unset LOA_PROBE_MOCK_OPENAI LOA_PROBE_MOCK_GOOGLE LOA_PROBE_MOCK_ANTHROPIC
    unset LOA_TRAJECTORY_DIR LOA_AUDIT_LOG
}

# Find the probe-<date>.jsonl file under the hermetic $TEST_DIR trajectory (Bridgebuilder F8)
_latest_trajectory_for_probe() {
    local dir="$TEST_DIR/trajectory"
    local today
    today="$(date -u +%Y-%m-%d)"
    echo "$dir/probe-$today.jsonl"
}

# -----------------------------------------------------------------------------
# Hard-stop: max_probes_per_run
# -----------------------------------------------------------------------------
@test "hardstop: LOA_PROBE_MAX_PROBES=0 -> exit 5 before any probe" {
    run env LOA_PROBE_MAX_PROBES=0 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet
    [ "$status" -eq 5 ]
}

@test "hardstop: max_probes emits telemetry entry 'budget_hardstop' with kind=max_probes" {
    run env LOA_PROBE_MAX_PROBES=0 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet
    [ "$status" -eq 5 ]

    local traj
    traj="$(_latest_trajectory_for_probe)"
    [ -f "$traj" ]
    # Last budget_hardstop entry should mention max_probes
    run jq -c 'select(.event == "budget_hardstop" and .payload.kind == "max_probes")' "$traj"
    [ -n "$output" ]
}

# -----------------------------------------------------------------------------
# Hard-stop: cost cap
# -----------------------------------------------------------------------------
@test "hardstop: LOA_PROBE_MAX_COST_CENTS=0 -> exit 5 before any probe" {
    run env LOA_PROBE_MAX_COST_CENTS=0 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet
    [ "$status" -eq 5 ]
}

@test "hardstop: cost cap emits telemetry entry 'budget_hardstop' with kind=max_cost_cents" {
    run env LOA_PROBE_MAX_COST_CENTS=0 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet
    [ "$status" -eq 5 ]
    local traj
    traj="$(_latest_trajectory_for_probe)"
    run jq -c 'select(.event == "budget_hardstop" and .payload.kind == "max_cost_cents")' "$traj"
    [ -n "$output" ]
}

# -----------------------------------------------------------------------------
# Hard-stop: invocation timeout
# -----------------------------------------------------------------------------
@test "hardstop: LOA_PROBE_INVOCATION_TIMEOUT=0 -> exit 5 on first budget check" {
    run env LOA_PROBE_INVOCATION_TIMEOUT=0 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet
    [ "$status" -eq 5 ]
}

@test "hardstop: invocation timeout emits telemetry entry with kind=invocation_timeout" {
    run env LOA_PROBE_INVOCATION_TIMEOUT=0 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet
    [ "$status" -eq 5 ]
    local traj
    traj="$(_latest_trajectory_for_probe)"
    run jq -c 'select(.event == "budget_hardstop" and .payload.kind == "invocation_timeout")' "$traj"
    [ -n "$output" ]
}

# -----------------------------------------------------------------------------
# Hardstop ordering — max_probes hit first if both cost and probes at 0
# (probes checked first in _check_all_budgets)
# -----------------------------------------------------------------------------
@test "hardstop: probes-check runs before cost-check (deterministic ordering)" {
    run env LOA_PROBE_MAX_PROBES=0 \
        LOA_PROBE_MAX_COST_CENTS=0 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --quiet
    [ "$status" -eq 5 ]
    local traj
    traj="$(_latest_trajectory_for_probe)"
    # The FIRST budget_hardstop entry should be max_probes (not cost)
    run jq -c 'select(.event == "budget_hardstop") | .payload.kind' "$traj"
    # First match should be "max_probes"
    [[ "$(echo "$output" | head -1)" == '"max_probes"' ]]
}

# -----------------------------------------------------------------------------
# Default budgets don't falsely trigger on a normal single-model probe
# -----------------------------------------------------------------------------
@test "hardstop: defaults allow a normal single-model probe to complete" {
    run env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test \
        "$PROBE" --provider openai --model gpt-5.3-codex --quiet --output json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.entries["openai:gpt-5.3-codex"].state == "AVAILABLE"' >/dev/null
}
