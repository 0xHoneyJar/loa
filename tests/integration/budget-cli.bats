#!/usr/bin/env bats
# =============================================================================
# budget-cli.bats — Sprint 2D
#
# Integration tests for the operator CLI wrapper over the L2 lib.
# Covers: verdict / usage / record / reconcile subcommands end-to-end.
# =============================================================================

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

    CLI="${REPO_ROOT}/.claude/scripts/budget/budget-cli.sh"
    chmod +x "$CLI" 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_DIR"
}

set_observer() {
    echo "$1" > "$OBSERVER_OUT"
}

# -----------------------------------------------------------------------------
# verdict subcommand
# -----------------------------------------------------------------------------
@test "cli verdict: returns allow when usage is low" {
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run "$CLI" verdict 1.00
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "allow" ]]
}

@test "cli verdict: exits 1 on halt-100" {
    set_observer '{"usd_used": 49.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run "$CLI" verdict 2.00
    [[ "$status" -eq 1 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "halt-100" ]]
}

@test "cli verdict: --provider scopes per-provider counter" {
    "$CLI" record 10.00 --provider openai >/dev/null
    set_observer '{"usd_used": 0.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run "$CLI" verdict 1.00 --provider anthropic
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.verdict')" == "allow" ]]
    [[ "$(echo "$output" | tail -1 | jq -r '.provider')" == "anthropic" ]]
}

# -----------------------------------------------------------------------------
# usage subcommand
# -----------------------------------------------------------------------------
@test "cli usage: returns state JSON without writing audit log" {
    "$CLI" record 7.50 --provider aggregate >/dev/null
    local pre_lines
    pre_lines="$(wc -l < "$LOG_FILE")"
    set_observer '{"usd_used": 7.50, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run "$CLI" usage
    [[ "$status" -eq 0 ]]
    [[ "$(echo "$output" | jq -r '.daily_cap_usd')" == "50.00" || "$(echo "$output" | jq -r '.daily_cap_usd')" == "50" ]]
    # No new envelope written.
    [[ "$(wc -l < "$LOG_FILE")" -eq "$pre_lines" ]]
}

# -----------------------------------------------------------------------------
# record subcommand
# -----------------------------------------------------------------------------
@test "cli record: appends budget.record_call envelope" {
    run "$CLI" record 1.42 --provider anthropic --model-id claude-opus-4-7
    [[ "$status" -eq 0 ]]
    local last_line
    last_line="$(tail -1 "$LOG_FILE")"
    [[ "$(echo "$last_line" | jq -r '.event_type')" == "budget.record_call" ]]
    [[ "$(echo "$last_line" | jq -r '.payload.actual_usd')" == "1.42" ]]
    [[ "$(echo "$last_line" | jq -r '.payload.model_id')" == "claude-opus-4-7" ]]
}

# -----------------------------------------------------------------------------
# reconcile subcommand
# -----------------------------------------------------------------------------
@test "cli reconcile: emits BLOCKER on drift > threshold" {
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":30.0,"usd_used_post":30.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    set_observer '{"usd_used": 20.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run "$CLI" reconcile
    [[ "$status" -eq 1 ]]
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.payload.blocker')" == "true" ]]
}

@test "cli reconcile: --force-reason captured in audit envelope" {
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":5.0,"usd_used_post":5.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run "$CLI" reconcile --force-reason "operator review 2026-05-04"
    [[ "$status" -eq 0 ]]
    local last_line
    last_line="$(tail -1 "$LOG_FILE")"
    [[ "$(echo "$last_line" | jq -r '.payload.force_reconcile')" == "true" ]]
}

# -----------------------------------------------------------------------------
# Error handling
# -----------------------------------------------------------------------------
@test "cli unknown subcommand: exits 2 with error" {
    run "$CLI" frobnicate
    [[ "$status" -eq 2 ]]
    [[ "$output" =~ "unknown subcommand" ]]
}

@test "cli no args: prints help and exits 0" {
    run "$CLI"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Subcommands:" ]]
}

# -----------------------------------------------------------------------------
# Composition with protected-class router
# -----------------------------------------------------------------------------
@test "protected-class router: 'budget.cap_increase' is registered as protected" {
    source "${REPO_ROOT}/.claude/scripts/lib/protected-class-router.sh"
    run is_protected_class "budget.cap_increase"
    [[ "$status" -eq 0 ]]  # exit 0 = matched
}

# -----------------------------------------------------------------------------
# Schema registry consistency — every emitted event has a corresponding schema
# -----------------------------------------------------------------------------
@test "schema registry: all 6 budget event-type schemas present" {
    local schema_dir="${REPO_ROOT}/.claude/data/trajectory-schemas/budget-events"
    [[ -d "$schema_dir" ]]
    [[ -f "${schema_dir}/budget-allow.payload.schema.json" ]]
    [[ -f "${schema_dir}/budget-warn-90.payload.schema.json" ]]
    [[ -f "${schema_dir}/budget-halt-100.payload.schema.json" ]]
    [[ -f "${schema_dir}/budget-halt-uncertainty.payload.schema.json" ]]
    [[ -f "${schema_dir}/budget-reconcile.payload.schema.json" ]]
    [[ -f "${schema_dir}/budget-record-call.payload.schema.json" ]]
}

@test "schema registry: every schema is valid JSON" {
    local schema_dir="${REPO_ROOT}/.claude/data/trajectory-schemas/budget-events"
    for schema in "$schema_dir"/*.schema.json; do
        run jq empty "$schema"
        [[ "$status" -eq 0 ]]
    done
}
