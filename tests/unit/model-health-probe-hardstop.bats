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

# -----------------------------------------------------------------------------
# G-1 (cycle-094): No-API-key probes do not consume budget
# Fork PRs without provider keys were tripping the cost hardstop after 5
# unmade probes. The probe must skip increments when ERROR_CLASS=auth + no HTTP.
# -----------------------------------------------------------------------------
@test "G-1: single no-API-key probe does NOT trigger any budget hardstop" {
    # No keys exported in this run on purpose. The setup() exports keys, so we
    # explicitly unset them via env -i and re-export only what's needed for
    # mock mode and hermetic test paths.
    run env -i \
        PATH="$PATH" HOME="$HOME" \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_CACHE_DIR="$TEST_DIR" \
        LOA_TRAJECTORY_DIR="$TEST_DIR/trajectory" \
        LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl" \
        PROJECT_ROOT="$PROJECT_ROOT" \
        "$PROBE" --provider openai --model gpt-5.3-codex --quiet --output json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.entries["openai:gpt-5.3-codex"].state == "UNKNOWN"' >/dev/null
    echo "$output" | jq -e '.entries["openai:gpt-5.3-codex"].reason | test("API_KEY")' >/dev/null
    # Trajectory must NOT contain a budget_hardstop event of any kind.
    local traj
    traj="$(_latest_trajectory_for_probe)"
    if [[ -f "$traj" ]]; then
        run jq -c 'select(.event == "budget_hardstop")' "$traj"
        [ -z "$output" ]
    fi
}

@test "G-1: full no-key registry probe does NOT trip 5-cent cost hardstop" {
    # The default openai provider has 4+ models. Without the G-1 guard, each
    # unmade probe would charge 1 cent; iterating through openai+google+anthropic
    # at default 5-cent cap would exit 5. With the guard: 0 increments, exit 0.
    local out
    out="$(env -i \
        PATH="$PATH" HOME="$HOME" \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_CACHE_DIR="$TEST_DIR" \
        LOA_TRAJECTORY_DIR="$TEST_DIR/trajectory" \
        LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl" \
        PROJECT_ROOT="$PROJECT_ROOT" \
        "$PROBE" --quiet --output json)"
    local rc=$?
    [ "$rc" -ne 5 ]
    # All probed entries should be UNKNOWN (no-key path)
    echo "$out" | jq -e '[.entries[] | select(.state == "UNKNOWN")] | length > 0' >/dev/null

    # N-3: verify the guard actually fired by checking the trajectory has NO
    # budget_hardstop event (the count would otherwise be > 0 by the time the
    # registry iterator reached its 6th openai model with the 1-cent-per-probe
    # increment unprotected by the guard).
    local traj
    traj="$(_latest_trajectory_for_probe)"
    if [[ -f "$traj" ]]; then
        run jq -c 'select(.event == "budget_hardstop")' "$traj"
        [ -z "$output" ]
    fi
}

@test "G-1: AC1-literal — summary.skipped:true when all probes skipped (no keys)" {
    # AC1 literal text: produces `summary.skipped: true` (or all-UNKNOWN for
    # partial keys). With zero keys set, both conditions hold.
    local out
    out="$(env -i \
        PATH="$PATH" HOME="$HOME" \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_CACHE_DIR="$TEST_DIR" \
        LOA_TRAJECTORY_DIR="$TEST_DIR/trajectory" \
        LOA_AUDIT_LOG="$TEST_DIR/audit.jsonl" \
        PROJECT_ROOT="$PROJECT_ROOT" \
        "$PROBE" --quiet --output json)"
    [ "$?" -eq 0 ]
    echo "$out" | jq -e '.summary.skipped == true' >/dev/null
    echo "$out" | jq -e '.summary.available == 0' >/dev/null
    echo "$out" | jq -e '.summary.unavailable == 0' >/dev/null
    echo "$out" | jq -e '.summary.unknown > 0' >/dev/null
}

@test "G-1: AC1-partial — summary.skipped:false when some probes consumed budget" {
    # With OPENAI_API_KEY set + valid mock response, probes go through.
    # summary.skipped must be false (not all-UNKNOWN).
    local out
    out="$(env LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=200 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test-openai \
        "$PROBE" --provider openai --model gpt-5.3-codex --quiet --output json)"
    [ "$?" -eq 0 ]
    echo "$out" | jq -e '.summary.skipped == false' >/dev/null
}

@test "G-1: 401 auth failure with HTTP=401 STILL consumes budget" {
    # Regression guard: a legitimate auth failure from the provider must
    # consume budget (HTTP_STATUS=401, ERROR_CLASS=auth). Only the no-network
    # path (HTTP=0/empty + ERROR_CLASS=auth) gets the free pass.
    # We set MAX_PROBES=1 so a second budget-pre-flight check after the first
    # probe must observe PROBES_USED=1 and trip exit 5 if the second model
    # is attempted. Since openai has multiple models, exit 5 confirms the
    # increment fired on the 401 path.
    run env LOA_PROBE_MAX_PROBES=1 \
        LOA_PROBE_MOCK_MODE=1 \
        LOA_PROBE_MOCK_HTTP_STATUS=401 \
        LOA_PROBE_MOCK_OPENAI="$FIXTURES/openai/available.json" \
        LOA_CACHE_DIR="$TEST_DIR" \
        OPENAI_API_KEY=test-bad-key \
        "$PROBE" --provider openai --quiet --output json
    [ "$status" -eq 5 ]
    local traj
    traj="$(_latest_trajectory_for_probe)"
    [ -f "$traj" ]
    run jq -c 'select(.event == "budget_hardstop" and .payload.kind == "max_probes")' "$traj"
    [ -n "$output" ]
}
