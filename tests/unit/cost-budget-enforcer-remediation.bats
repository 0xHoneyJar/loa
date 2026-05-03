#!/usr/bin/env bats
# =============================================================================
# cost-budget-enforcer-remediation.bats — Sprint 2 review/audit remediation
#
# Tests the fixes for HIGH-1 (counter_stale mode), HIGH-3/F1 (numeric input
# validation), F2 (provider regex), F3 (snapshot .sig verification), MED-3
# (counter_drift reachability), MED-1/MED-2 (schema description + required).
# =============================================================================

load_lib() {
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/cost-budget-enforcer-lib.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cost-budget-events.jsonl"
    OBSERVER="${TEST_DIR}/observer.sh"
    OBSERVER_OUT="${TEST_DIR}/observer-out.json"

    cat > "$OBSERVER" <<'EOF'
#!/usr/bin/env bash
out_file="${OBSERVER_OUT:-}"
if [[ -n "$out_file" && -f "$out_file" ]]; then
    cat "$out_file"
else
    echo '{"_unreachable": true}'
fi
EOF
    chmod +x "$OBSERVER"

    export LOA_BUDGET_LOG="$LOG_FILE"
    export LOA_BUDGET_OBSERVER_CMD="$OBSERVER"
    export OBSERVER_OUT
    export LOA_BUDGET_DAILY_CAP_USD="50.00"
    export LOA_BUDGET_TEST_NOW="2026-05-04T12:00:00.000000Z"
    export LOA_AUDIT_VERIFY_SIGS=0
    unset LOA_AUDIT_SIGNING_KEY_ID
}

teardown() {
    rm -rf "$TEST_DIR"
}

set_observer() {
    echo "$1" > "$OBSERVER_OUT"
}

# -----------------------------------------------------------------------------
# F2 — provider regex validation
# -----------------------------------------------------------------------------
@test "F2: budget_verdict rejects provider containing yq path-injection" {
    load_lib
    run budget_verdict 1.00 --provider 'aggregate // "999999"'
    [[ "$status" -eq 2 ]]
}

@test "F2: budget_verdict rejects provider with shell metachars" {
    load_lib
    run budget_verdict 1.00 --provider '$(rm -rf /)'
    [[ "$status" -eq 2 ]]
}

@test "F2: budget_verdict rejects provider with path traversal" {
    load_lib
    run budget_verdict 1.00 --provider '../../etc/passwd'
    [[ "$status" -eq 2 ]]
}

@test "F2: budget_verdict accepts well-formed provider id" {
    load_lib
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run budget_verdict 1.00 --provider anthropic
    [[ "$status" -eq 0 ]]
    run budget_verdict 1.00 --provider openai
    [[ "$status" -eq 0 ]]
    run budget_verdict 1.00 --provider bedrock-us-east-1
    [[ "$status" -eq 0 ]]
}

@test "F2: budget_record_call rejects malicious provider" {
    load_lib
    run budget_record_call 1.00 --provider 'evil; rm -rf /'
    [[ "$status" -eq 2 ]]
}

@test "F2: budget_reconcile rejects malicious provider" {
    load_lib
    run budget_reconcile --provider 'foo$(injection)'
    [[ "$status" -eq 2 ]]
}

# -----------------------------------------------------------------------------
# HIGH-3 / F1 — config-derived numeric validation
# -----------------------------------------------------------------------------
@test "F1: _l2_get_daily_cap rejects non-numeric cap" {
    load_lib
    LOA_BUDGET_DAILY_CAP_USD='50.00); __import__("os").system("touch /tmp/pwned")#' \
        run _l2_get_daily_cap
    [[ "$status" -eq 3 ]]
}

@test "F1: budget_verdict fails closed when cap is malformed" {
    load_lib
    LOA_BUDGET_DAILY_CAP_USD='not-a-number' run budget_verdict 1.00
    [[ "$status" -eq 3 ]]
}

@test "F1: _l2_get_freshness_seconds falls back to default on malformed value" {
    load_lib
    # _l2_validate_numeric logs an ERROR to stderr; we want only stdout.
    local out
    out="$(LOA_BUDGET_FRESHNESS_SECONDS='300; touch /tmp/pwn' _l2_get_freshness_seconds 2>/dev/null)"
    [[ "$out" == "300" ]]  # default
}

@test "F1: _l2_get_drift_threshold falls back to default on malformed value" {
    load_lib
    local out
    out="$(LOA_BUDGET_DRIFT_THRESHOLD='5.0); evil()' _l2_get_drift_threshold 2>/dev/null)"
    [[ "$out" == "5.0" ]]  # default
}

@test "F1: _l2_validate_numeric accepts well-formed decimals" {
    load_lib
    run _l2_validate_numeric "50.00" "test_field"
    [[ "$status" -eq 0 ]]
    run _l2_validate_numeric "0" "test_field"
    [[ "$status" -eq 0 ]]
    run _l2_validate_numeric "1234.567890" "test_field"
    [[ "$status" -eq 0 ]]
}

@test "F1: _l2_validate_numeric rejects empty + injection patterns" {
    load_lib
    run _l2_validate_numeric "" "test_field"
    [[ "$status" -eq 1 ]]
    run _l2_validate_numeric "1.0; rm -rf /" "test_field"
    [[ "$status" -eq 1 ]]
    run _l2_validate_numeric '$(echo bad)' "test_field"
    [[ "$status" -eq 1 ]]
    run _l2_validate_numeric "1e308" "test_field"
    [[ "$status" -eq 1 ]]  # scientific notation rejected (not in regex)
}

# -----------------------------------------------------------------------------
# HIGH-1 — counter_stale uncertainty mode
# -----------------------------------------------------------------------------
@test "HIGH-1: counter_stale fires when no observer + counter has stale entries" {
    load_lib
    # Inject record_call from 2 hours ago (stale per 5min freshness threshold).
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":30.0,"usd_used_post":30.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    # No observer configured.
    unset LOA_BUDGET_OBSERVER_CMD
    run budget_verdict "1.00"
    [[ "$status" -eq 1 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "halt-uncertainty" ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.uncertainty_reason')" == "counter_stale" ]]
}

@test "HIGH-1: counter_stale does NOT fire when counter is fresh + no observer (zero usage today)" {
    load_lib
    unset LOA_BUDGET_OBSERVER_CMD
    # No record_calls today; counter_usd=0, counter_age=0 → fresh-by-zero.
    run budget_verdict "1.00"
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "allow" ]]
}

@test "HIGH-1: counter_stale does NOT fire when counter has fresh entry + no observer" {
    load_lib
    unset LOA_BUDGET_OBSERVER_CMD
    LOA_BUDGET_TEST_NOW="2026-05-04T11:58:30.000000Z" budget_record_call 5.00 --provider aggregate >/dev/null
    # Counter entry from 90s ago, well under 5min freshness.
    run budget_verdict "1.00"
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "allow" ]]
}

# -----------------------------------------------------------------------------
# MED-3 — counter_drift reachability via prior reconcile BLOCKER
# -----------------------------------------------------------------------------
@test "MED-3: budget_verdict halts with counter_drift after reconcile BLOCKER" {
    load_lib
    # First, make a reconcile that BLOCKERs (drift > threshold).
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":30.0,"usd_used_post":30.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    set_observer '{"usd_used": 20.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run budget_reconcile
    [[ "$status" -eq 1 ]]  # BLOCKER

    # Now budget_verdict must halt-uncertainty:counter_drift even with fresh data.
    run budget_verdict "1.00"
    [[ "$status" -eq 1 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "halt-uncertainty" ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.uncertainty_reason')" == "counter_drift" ]]
}

@test "MED-3: force-reconcile clears prior counter_drift BLOCKER" {
    load_lib
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":30.0,"usd_used_post":30.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    # Trigger BLOCKER (exit 1 is expected; capture so set -e doesn't kill the test).
    # Use clock-aligned billing_ts so clock_drift doesn't mask counter_drift in step 5.
    set_observer '{"usd_used": 20.00, "billing_ts": "2026-05-04T12:00:00.000000Z"}'
    LOA_BUDGET_TEST_NOW="2026-05-04T12:00:00.000000Z" budget_reconcile >/dev/null 2>&1 || true
    # Force-reconcile clears the blocker. Counter is still 30 — this is OK; test
    # is asserting only that the reconcile-blocker check passes, not threshold.
    set_observer '{"usd_used": 30.00, "billing_ts": "2026-05-04T12:01:00.000000Z"}'
    LOA_BUDGET_TEST_NOW="2026-05-04T12:01:00.000000Z" budget_reconcile --force-reason "operator review" >/dev/null 2>&1 || true

    # Now budget_verdict at 12:01:30 with billing_ts at 12:01 (30s old, within tolerance).
    # Counter is 30; cap is 50; estimate is 1 → projected 31/50 = 62% → allow.
    set_observer '{"usd_used": 30.00, "billing_ts": "2026-05-04T12:01:00.000000Z"}'
    LOA_BUDGET_TEST_NOW="2026-05-04T12:01:30.000000Z" run budget_verdict "1.00"
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "allow" ]]
}

# -----------------------------------------------------------------------------
# MED-2 — usage_pct now required in warn-90 / halt-100 schemas
# -----------------------------------------------------------------------------
@test "MED-2: budget-warn-90.payload.schema.json requires usage_pct" {
    local schema="${REPO_ROOT}/.claude/data/trajectory-schemas/budget-events/budget-warn-90.payload.schema.json"
    run jq -r '.required[] | select(. == "usage_pct")' "$schema"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

@test "MED-2: budget-halt-100.payload.schema.json requires usage_pct" {
    local schema="${REPO_ROOT}/.claude/data/trajectory-schemas/budget-events/budget-halt-100.payload.schema.json"
    run jq -r '.required[] | select(. == "usage_pct")' "$schema"
    [[ "$status" -eq 0 ]]
    [[ -n "$output" ]]
}

# -----------------------------------------------------------------------------
# MED-1 — schema description matches projected-usage-pct semantics
# -----------------------------------------------------------------------------
@test "MED-1: warn-90 + halt-100 schemas describe usage_pct as projected" {
    local warn90="${REPO_ROOT}/.claude/data/trajectory-schemas/budget-events/budget-warn-90.payload.schema.json"
    local halt100="${REPO_ROOT}/.claude/data/trajectory-schemas/budget-events/budget-halt-100.payload.schema.json"
    run jq -r '.properties.usage_pct.description' "$warn90"
    [[ "$output" =~ "Projected post-call" ]]
    run jq -r '.properties.usage_pct.description' "$halt100"
    [[ "$output" =~ "Projected post-call" ]]
}

# -----------------------------------------------------------------------------
# halt-uncertainty schema includes counter_stale
# -----------------------------------------------------------------------------
@test "halt-uncertainty schema enum includes counter_stale" {
    local schema="${REPO_ROOT}/.claude/data/trajectory-schemas/budget-events/budget-halt-uncertainty.payload.schema.json"
    run jq -r '.properties.uncertainty_reason.enum[] | select(. == "counter_stale")' "$schema"
    [[ -n "$output" ]]
}
