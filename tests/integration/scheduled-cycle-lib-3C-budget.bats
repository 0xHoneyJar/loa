#!/usr/bin/env bats
# =============================================================================
# scheduled-cycle-lib-3C-budget.bats — Sprint 3C
#
# Covers FR-L3-6: L2 budget pre-check (compose-when-available per CC-9) before
# reader phase. Verdicts allow/warn-90 proceed; halt-100/halt-uncertainty halt
# with cycle.error{error_phase=pre_check, error_kind=budget_halt}. When L2 is
# disabled, cycle proceeds with budget_pre_check=null in cycle.start.
# =============================================================================

load_lib() {
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/scheduled-cycle-lib.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cycles.jsonl"
    BUDGET_LOG="${TEST_DIR}/cost-budget-events.jsonl"
    LOCK_DIR="${TEST_DIR}/.run/cycles"
    SCHEDULE_YAML="${TEST_DIR}/schedule.yaml"
    OBSERVER="${TEST_DIR}/observer.sh"
    OBSERVER_OUT="${TEST_DIR}/observer-out.json"

    mkdir -p "$LOCK_DIR"

    for phase in reader decider dispatcher awaiter logger; do
        cat > "${TEST_DIR}/${phase}.sh" <<EOF
#!/usr/bin/env bash
echo "{\"phase\":\"${phase}\"}"
exit 0
EOF
        chmod +x "${TEST_DIR}/${phase}.sh"
    done

    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-3c
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
  budget_estimate_usd: 5.00
  timeout_seconds: 60
EOF

    # Mock billing observer reads from OBSERVER_OUT.
    cat > "$OBSERVER" <<'EOF'
#!/usr/bin/env bash
out="${OBSERVER_OUT:-}"
if [[ -n "$out" && -f "$out" ]]; then
    cat "$out"
else
    echo '{"_unreachable": true}'
fi
EOF
    chmod +x "$OBSERVER"

    export LOA_CYCLES_LOG="$LOG_FILE"
    export LOA_L3_LOCK_DIR="$LOCK_DIR"
    export LOA_L3_LOCK_TIMEOUT_SECONDS=2

    # L2 wiring (only used by tests that opt in via LOA_L3_BUDGET_PRECHECK_ENABLED).
    export LOA_BUDGET_LOG="$BUDGET_LOG"
    export LOA_BUDGET_OBSERVER_CMD="$OBSERVER"
    export OBSERVER_OUT
    export LOA_BUDGET_DAILY_CAP_USD="50.00"
    export LOA_BUDGET_DRIFT_THRESHOLD="5.0"
    export LOA_BUDGET_FRESHNESS_SECONDS="300"
    export LOA_BUDGET_STALE_HALT_PCT="75"
    export LOA_BUDGET_CLOCK_TOLERANCE="60"
    export LOA_BUDGET_LAG_HALT_SECONDS="300"

    export LOA_L3_TEST_NOW="2026-05-04T14:00:00.000000Z"
    export LOA_BUDGET_TEST_NOW="$LOA_L3_TEST_NOW"
    export LOA_L3_PHASE_PATH_ALLOWED_PREFIXES="$TEST_DIR"
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0

    export REPO_ROOT TEST_DIR LOG_FILE BUDGET_LOG SCHEDULE_YAML
}

teardown() {
    rm -rf "$TEST_DIR"
}

set_observer_usage() {
    echo "{\"usd_used\": $1, \"billing_ts\": \"$LOA_L3_TEST_NOW\"}" > "$OBSERVER_OUT"
}

# -----------------------------------------------------------------------------
# L2 disabled → no budget check
# -----------------------------------------------------------------------------
@test "L2 disabled (default): cycle.start.budget_pre_check is null; cycle proceeds" {
    load_lib
    unset LOA_L3_BUDGET_PRECHECK_ENABLED
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-disabled"
    [ "$status" -eq 0 ]
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.budget_pre_check' "$LOG_FILE"
    [ "$output" = "null" ]
    # No budget log file written either.
    [ ! -f "$BUDGET_LOG" ] || [ "$(jq -sr '. | length' "$BUDGET_LOG")" = "0" ]
}

# -----------------------------------------------------------------------------
# L2 enabled, verdict=allow → proceed
# -----------------------------------------------------------------------------
@test "FR-L3-6: L2 enabled + verdict=allow → cycle.start.budget_pre_check.verdict=allow + 5 phases run" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    set_observer_usage 5.00   # 5/50 = 10%; estimate=5 → projected 10/50=20% → allow
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-allow"
    [ "$status" -eq 0 ]
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.budget_pre_check.verdict' "$LOG_FILE"
    [ "$output" = "allow" ]
    # cycle.complete present
    run jq -sr '[.[] | select(.event_type == "cycle.complete")] | length' "$LOG_FILE"
    [ "$output" = "1" ]
}

@test "FR-L3-6: L2 enabled + verdict=allow records usd_estimate and checked_at in cycle.start" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    set_observer_usage 5.00
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-allow-fields"
    # Numeric comparison via jq tonumber — robust against 5 vs 5.0 vs 5.00.
    run jq -sr '.[] | select(.event_type == "cycle.start") | (.payload.budget_pre_check.usd_estimate | tonumber == 5)' "$LOG_FILE"
    [ "$output" = "true" ]
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.budget_pre_check.checked_at' "$LOG_FILE"
    [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+\.[0-9]+Z$ ]]
}

# -----------------------------------------------------------------------------
# L2 enabled, verdict=warn-90 → proceed
# -----------------------------------------------------------------------------
@test "FR-L3-6: L2 enabled + verdict=warn-90 → cycle proceeds; verdict recorded" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    # cap=50, used=44, est=5 → projected 49/50 = 98% → warn-90
    set_observer_usage 44.00
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-warn"
    [ "$status" -eq 0 ]
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.budget_pre_check.verdict' "$LOG_FILE"
    [ "$output" = "warn-90" ]
    run jq -sr '[.[] | select(.event_type == "cycle.complete")] | length' "$LOG_FILE"
    [ "$output" = "1" ]
}

# -----------------------------------------------------------------------------
# L2 enabled, verdict=halt-100 → halt
# -----------------------------------------------------------------------------
@test "FR-L3-6: L2 enabled + verdict=halt-100 → cycle.error{error_phase=pre_check, error_kind=budget_halt}" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    # cap=50, used=49 + est=5 → projected 54/50 = 108% → halt-100
    set_observer_usage 49.00
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-halt100"
    [ "$status" -eq 1 ]
    # Only cycle.start + cycle.error (no phases ran)
    run jq -sr '[.[] | select(.event_type == "cycle.phase")] | length' "$LOG_FILE"
    [ "$output" = "0" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_phase' "$LOG_FILE"
    [ "$output" = "pre_check" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_kind' "$LOG_FILE"
    [ "$output" = "budget_halt" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.budget_pre_check.verdict' "$LOG_FILE"
    [ "$output" = "halt-100" ]
}

@test "FR-L3-6: L2 halt-100 cycle.error has phases_completed=[]" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    set_observer_usage 49.00
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-halt100-phases" || true
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.phases_completed | length' "$LOG_FILE"
    [ "$output" = "0" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.outcome' "$LOG_FILE"
    [ "$output" = "failure" ]
}

# -----------------------------------------------------------------------------
# L2 enabled, verdict=halt-uncertainty → halt
# -----------------------------------------------------------------------------
@test "FR-L3-6: L2 enabled + halt-uncertainty (clock_drift) → cycle.error budget_halt" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    # halt-uncertainty:clock_drift fires when |sys_clock - billing_ts| exceeds
    # LOA_BUDGET_CLOCK_TOLERANCE (default 60s). Use billing_ts 5 min in the
    # future relative to LOA_L3_TEST_NOW (delta=300s > 60s).
    local future_ts="2026-05-04T14:05:00.000000Z"
    echo "{\"usd_used\": 5.00, \"billing_ts\": \"$future_ts\"}" > "$OBSERVER_OUT"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-halt-unc"
    [ "$status" -eq 1 ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_kind' "$LOG_FILE"
    [ "$output" = "budget_halt" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.budget_pre_check.verdict' "$LOG_FILE"
    [ "$output" = "halt-uncertainty" ]
}

# -----------------------------------------------------------------------------
# Idempotency interaction with halt
# -----------------------------------------------------------------------------
@test "FR-L3-6: budget halt does NOT mark cycle as completed (subsequent runs retry)" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    set_observer_usage 49.00
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-retry-after-halt" || true
    # Drop usage to 5, retry.
    set_observer_usage 5.00
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-retry-after-halt"
    [ "$status" -eq 0 ]
    run jq -sr '[.[] | select(.event_type == "cycle.complete") | .payload.cycle_id]' "$LOG_FILE"
    [[ "$output" == *"test-3c-retry-after-halt"* ]]
}

# -----------------------------------------------------------------------------
# Lock + budget interaction
# -----------------------------------------------------------------------------
@test "FR-L3-6: lock acquired BEFORE budget pre-check (lock contention has priority)" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    set_observer_usage 49.00
    # Hold the lock externally → cycle.lock_failed should fire BEFORE any budget call.
    local lock_file="${LOCK_DIR}/test-3c.lock"
    : > "$lock_file"
    flock -x "$lock_file" -c "sleep 5" &
    local holder_pid=$!
    sleep 0.3
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-lock-vs-budget" 2>/dev/null || true
    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true
    # Only cycle.lock_failed; no cycle.start, no cycle.error[pre_check].
    run jq -sr '.[] | .event_type' "$LOG_FILE"
    [ "$output" = "cycle.lock_failed" ]
}

# -----------------------------------------------------------------------------
# Compose gracefully when L2 lib unavailable (compose-when-available)
# -----------------------------------------------------------------------------
@test "L2 enabled but no L2 lib reachable → graceful skip with warning (cycle proceeds)" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    # Override L2 path resolution to a missing file.
    export LOA_L3_L2_LIB_OVERRIDE="${TEST_DIR}/missing-l2.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-no-l2"
    [ "$status" -eq 0 ]
    # cycle.start.budget_pre_check is null because L2 unreachable.
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.budget_pre_check' "$LOG_FILE"
    [ "$output" = "null" ]
}

# -----------------------------------------------------------------------------
# Zero/null budget_estimate skips check even when L2 enabled
# -----------------------------------------------------------------------------
@test "L2 enabled but budget_estimate_usd=0 → no L2 call; budget_pre_check=null" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-3c-zero
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
  budget_estimate_usd: 0
  timeout_seconds: 60
EOF
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3c-zero-est"
    [ "$status" -eq 0 ]
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.budget_pre_check' "$LOG_FILE"
    [ "$output" = "null" ]
    [ ! -f "$BUDGET_LOG" ] || [ "$(jq -sr '. | length' "$BUDGET_LOG")" = "0" ]
}
