#!/usr/bin/env bats
# =============================================================================
# cost-budget-enforcer-reconciliation-cron.bats — Sprint 2B
#
# Integration tests for the L2 reconciliation cron entrypoint + install helper.
# Covers idempotent re-runs, billing-API 429 deferral, and crontab integration.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cost-budget-events.jsonl"
    OBSERVER="${TEST_DIR}/observer.sh"
    OBSERVER_OUT="${TEST_DIR}/observer-out.json"
    RECONCILE_LOCK="${TEST_DIR}/budget-reconcile.lock"

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
    # Sprint H2 (#708 F-005): observer allowlist scoped to TEST_DIR.
    export LOA_BUDGET_OBSERVER_ALLOWED_PREFIXES="$TEST_DIR"
    export OBSERVER_OUT
    export LOA_BUDGET_DAILY_CAP_USD="50.00"
    export LOA_BUDGET_DRIFT_THRESHOLD="5.0"
    export LOA_BUDGET_RECONCILE_LOCK="$RECONCILE_LOCK"
    export LOA_BUDGET_TEST_NOW="2026-05-04T12:00:00.000000Z"
    export LOA_AUDIT_VERIFY_SIGS=0
    unset LOA_AUDIT_SIGNING_KEY_ID

    CRON_SCRIPT="${REPO_ROOT}/.claude/scripts/budget/budget-reconcile-cron.sh"
    INSTALL_SCRIPT="${REPO_ROOT}/.claude/scripts/budget/budget-reconcile-install.sh"
    chmod +x "$CRON_SCRIPT" "$INSTALL_SCRIPT" 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_DIR"
}

set_observer() {
    echo "$1" > "$OBSERVER_OUT"
}

# -----------------------------------------------------------------------------
# Cron entrypoint behavior
# -----------------------------------------------------------------------------
@test "cron entry: aggregate provider, no drift, OK status" {
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    # Pre-load matching counter.
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":5.0,"usd_used_post":5.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    run "$CRON_SCRIPT"
    [[ "$status" -eq 0 ]]
    # Reconcile event appended.
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.event_type')" == "budget.reconcile" ]]
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.payload.blocker')" == "false" ]]
}

@test "cron entry: BLOCKER on drift > threshold; exits 1" {
    set_observer '{"usd_used": 20.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":30.0,"usd_used_post":30.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    run "$CRON_SCRIPT"
    [[ "$status" -eq 1 ]]  # blocker
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.payload.blocker')" == "true" ]]
}

@test "cron entry: defer on observer _defer signal (rate-limited); no event emitted" {
    set_observer '{"_defer": true, "_reason": "rate_limited"}'
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":5.0,"usd_used_post":5.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    local pre_count
    pre_count="$(wc -l < "$LOG_FILE")"
    run "$CRON_SCRIPT"
    # Cron exits 0 — defer is not a blocker.
    [[ "$status" -eq 0 ]]
    # No new envelope appended.
    [[ "$(wc -l < "$LOG_FILE")" -eq "$pre_count" ]]
}

@test "cron entry: dry-run prints intent, no audit log writes" {
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    [[ ! -f "$LOG_FILE" || "$(wc -l < "$LOG_FILE")" -eq 0 ]]
    run "$CRON_SCRIPT" --dry-run
    [[ "$status" -eq 0 ]]
    [[ ! -f "$LOG_FILE" ]] || [[ "$(wc -l < "$LOG_FILE")" -eq 0 ]]
}

@test "cron entry: --provider scopes to single provider" {
    set_observer '{"usd_used": 0.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    run "$CRON_SCRIPT" --provider anthropic
    [[ "$status" -eq 0 ]]
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.payload.provider')" == "anthropic" ]]
}

@test "cron entry: --force-reason captures operator audit context" {
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":5.0,"usd_used_post":5.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    run "$CRON_SCRIPT" --force-reason "operator audit 2026-05-04 incident #FOO"
    [[ "$status" -eq 0 ]]
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.payload.force_reconcile')" == "true" ]]
    [[ "$(tail -1 "$LOG_FILE" | jq -r '.payload.operator_reason')" == "operator audit 2026-05-04 incident #FOO" ]]
}

# -----------------------------------------------------------------------------
# Idempotency — repeated cron firings do not duplicate state errors
# -----------------------------------------------------------------------------
@test "cron entry: 3 sequential invocations append 3 reconcile events (chain intact)" {
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":5.0,"usd_used_post":5.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    run "$CRON_SCRIPT"; [[ "$status" -eq 0 ]]
    LOA_BUDGET_TEST_NOW="2026-05-04T12:01:00.000000Z" run "$CRON_SCRIPT"; [[ "$status" -eq 0 ]]
    LOA_BUDGET_TEST_NOW="2026-05-04T12:02:00.000000Z" run "$CRON_SCRIPT"; [[ "$status" -eq 0 ]]

    # 1 record_call + 3 reconcile = 4 lines.
    [[ "$(wc -l < "$LOG_FILE")" -eq 4 ]]
    # Chain still intact.
    source "${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    run audit_verify_chain "$LOG_FILE"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Install helper — show / status / install / uninstall
# -----------------------------------------------------------------------------
@test "install helper: 'show' prints the cron line that would be installed" {
    run "$INSTALL_SCRIPT" show
    [[ "$status" -eq 0 ]]
    # Line should contain the cron expression and the marker.
    [[ "$output" =~ "loa-cycle098-l2-reconcile" ]]
    [[ "$output" =~ "budget-reconcile-cron.sh" ]]
}

@test "install helper: respects configured interval_hours" {
    local config
    config="${TEST_DIR}/loa.config.yaml"
    cat > "$config" <<'EOF'
cost_budget_enforcer:
  reconciliation:
    interval_hours: 12
EOF
    LOA_BUDGET_CONFIG_FILE="$config" run "$INSTALL_SCRIPT" show
    [[ "$status" -eq 0 ]]
    # Cron expression for 12h cadence: "0 */12 * * *"
    [[ "$output" == *"0 */12 * * *"* ]]
}

@test "install helper: rejects invalid interval_hours" {
    local config
    config="${TEST_DIR}/loa.config.yaml"
    cat > "$config" <<'EOF'
cost_budget_enforcer:
  reconciliation:
    interval_hours: 99
EOF
    LOA_BUDGET_CONFIG_FILE="$config" run "$INSTALL_SCRIPT" show
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# Lock — concurrent invocations serialize via flock
# -----------------------------------------------------------------------------
@test "cron entry: concurrent invocations serialize (flock acquired)" {
    set_observer '{"usd_used": 5.00, "billing_ts": "2026-05-04T11:59:00.000000Z"}'
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"budget.record_call","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"actual_usd":5.0,"usd_used_post":5.0,"provider":"aggregate","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"verdict_ref":null},"redaction_applied":null}
EOF
    # Run 3 in parallel, all should complete. Sprint H2 closure of #708
    # F-003-cron: capture per-PID exit codes; the prior `wait $p1 $p2 $p3`
    # form ignored individual exit statuses, so a silent failure in one
    # actor would have left the test passing because the count happens to
    # still be 3 (e.g., from a re-emit). Now asserting all three returned 0.
    "$CRON_SCRIPT" &
    pid1=$!
    "$CRON_SCRIPT" &
    pid2=$!
    "$CRON_SCRIPT" &
    pid3=$!
    wait "$pid1"; local rc1=$?
    wait "$pid2"; local rc2=$?
    wait "$pid3"; local rc3=$?
    [[ "$rc1" -eq 0 ]]
    [[ "$rc2" -eq 0 ]]
    [[ "$rc3" -eq 0 ]]
    # 3 reconcile events appended (one per invocation, serialized).
    local reconcile_count
    reconcile_count="$(grep -c '"event_type":"budget.reconcile"' "$LOG_FILE" || true)"
    [[ "$reconcile_count" -eq 3 ]]
    # Chain still intact.
    source "${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    run audit_verify_chain "$LOG_FILE"
    [[ "$status" -eq 0 ]]
}
