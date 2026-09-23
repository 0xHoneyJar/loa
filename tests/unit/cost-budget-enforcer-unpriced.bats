#!/usr/bin/env bats
# =============================================================================
# tests/unit/cost-budget-enforcer-unpriced.bats — cycle-125 Sprint 4 (PRD FR-5,
# SDD §1.6, Flatline SKP-019): the enforcer never certifies "under budget"
# while the cost ledger's unpriced share exceeds 5 %; an unavailable report
# is reported as unknown and does not block. Harness mirrors
# cost-budget-enforcer-state-machine.bats (controlled clock, no observer).
# =============================================================================

load_lib() {
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/cost-budget-enforcer-lib.sh"
}

setup() {
    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cost-budget-events.jsonl"
    export LOA_BUDGET_LOG="$LOG_FILE"
    unset LOA_BUDGET_OBSERVER_CMD
    export LOA_BUDGET_DAILY_CAP_USD="50.00"
    export LOA_BUDGET_DRIFT_THRESHOLD="5.0"
    export LOA_BUDGET_FRESHNESS_SECONDS="300"
    export LOA_BUDGET_STALE_HALT_PCT="75"
    export LOA_BUDGET_CLOCK_TOLERANCE="60"
    export LOA_BUDGET_LAG_HALT_SECONDS="300"
    export LOA_BUDGET_TEST_NOW="2026-05-04T12:00:00.000000Z"
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0
    REPORT="${TEST_DIR}/report.json"
    export LOA_BUDGET_COST_REPORT_JSON="$REPORT"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "UP-1 unpriced share above 5 % → halt-uncertainty with reason unpriced_share and the share in the diagnostic (exit 1)" {
    load_lib
    echo '{"total_micro_usd": 1000, "entry_count": 10, "unpriced_rows": 2, "unpriced_share": 0.2}' > "$REPORT"
    run budget_verdict "5.00"
    [[ "$status" -eq 1 ]]
    last="$(echo "$output" | tail -1)"
    [[ "$(echo "$last" | jq -r '.verdict')" == "halt-uncertainty" ]]
    [[ "$(echo "$last" | jq -r '.uncertainty_reason')" == "unpriced_share" ]]
    [[ "$(echo "$last" | jq -r '.diagnostic.unpriced_share')" == "0.2" ]]
    [[ "$(echo "$last" | jq -r '.diagnostic.unpriced_rows')" == "2" ]]
    [[ "$(echo "$last" | jq -r '.diagnostic.threshold')" == "0.05" ]]
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.event_type')" == "budget.halt_uncertainty" ]]
}

@test "UP-2 unpriced share at or below 5 % → allow, and the allow payload carries the share" {
    load_lib
    echo '{"total_micro_usd": 1000, "entry_count": 100, "unpriced_rows": 5, "unpriced_share": 0.05}' > "$REPORT"
    run budget_verdict "5.00"
    [[ "$status" -eq 0 ]]
    last="$(echo "$output" | tail -1)"
    [[ "$(echo "$last" | jq -r '.verdict')" == "allow" ]]
    [[ "$(echo "$last" | jq -r '.unpriced_share')" == "0.05" ]]
}

@test "UP-3 an unavailable or malformed cost report does not block: allow with unpriced_share null" {
    load_lib
    rm -f "$REPORT"
    run budget_verdict "5.00"
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "allow" ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.unpriced_share')" == "null" ]]
    echo 'not json' > "$REPORT"
    run budget_verdict "5.00"
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.unpriced_share')" == "null" ]]
}

@test "UP-4 the unpriced guard runs after the hard caps: a halt-100 stays halt-100 even with a clean ledger" {
    load_lib
    echo '{"unpriced_rows": 0, "unpriced_share": 0}' > "$REPORT"
    export LOA_BUDGET_DAILY_CAP_USD="1.00"
    run budget_verdict "5.00"
    [[ "$status" -eq 1 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "halt-100" ]]
}

@test "UP-5 the report seam is bats-gated: the production path calls cost-report.sh --json (which exists and answers with unpriced_share)" {
    load_lib
    run bash -c "unset BATS_TEST_FILENAME BATS_VERSION; source '${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/cost-budget-enforcer-lib.sh'; _l2_unpriced_share_json"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e 'has("unpriced_share") and has("unpriced_rows")' >/dev/null
}
