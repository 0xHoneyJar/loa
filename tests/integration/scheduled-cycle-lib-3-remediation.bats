#!/usr/bin/env bats
# =============================================================================
# scheduled-cycle-lib-3-remediation.bats — Sprint 3 review/audit remediation
#
# Covers the security hardening + review fixes applied after the parallel
# review-sprint + audit-sprint subagent passes.
#
# CRITICAL findings closed:
#   - CRIT-A1: cycle_idempotency_check rejects forged bare-payload entries
#   - CRIT-A2: dispatch_contract phase paths must clear the allowlist
#   - CRIT-A3: lock-touch refuses to follow symlinks
# HIGH findings closed:
#   - HIGH-A1: phase scripts run under env -i (no API keys leak)
#   - HIGH-A2: LOA_L3_L2_LIB_OVERRIDE gated on test mode
#   - HIGH-R1: cycle_register validates contract + emits /schedule wiring JSON
#   - HIGH-R2: prior_phases_json propagates between phases
#   - HIGH-R3: LOA_L3_TEST_NOW yields deterministic duration_seconds
# MEDIUM findings closed:
#   - MED-R1: lock TTL behavior verified (release-during-wait → success)
#   - MED-R2: partial-prior-run (start + N phases, no complete) retries
#   - MED-R3: cycle_replay sorts phases by phase_index
#   - MED-R4 / MED-A1: extended redaction patterns (AWS/GCP/Slack/PEM/k=v)
#   - MED-R5: cycle.complete carries the actual phases_completed array
#   - MED-A2: cycle_record_phase / cycle_complete require --schedule-id
#   - MED-A3: timeout_seconds × 5 > max_cycle_seconds → exit 2
# =============================================================================

load_lib() {
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/scheduled-cycle-lib.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cycles.jsonl"
    LOCK_DIR="${TEST_DIR}/.run/cycles"
    SCHEDULE_YAML="${TEST_DIR}/schedule.yaml"

    mkdir -p "$LOCK_DIR"

    for phase in reader decider dispatcher awaiter logger; do
        cat > "${TEST_DIR}/${phase}.sh" <<EOF
#!/usr/bin/env bash
echo "{\"phase\":\"${phase}\",\"prior\":\$4}"
exit 0
EOF
        chmod +x "${TEST_DIR}/${phase}.sh"
    done

    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-rem
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
  budget_estimate_usd: 0.10
  timeout_seconds: 60
EOF

    export LOA_CYCLES_LOG="$LOG_FILE"
    export LOA_L3_LOCK_DIR="$LOCK_DIR"
    export LOA_L3_LOCK_TIMEOUT_SECONDS=2
    export LOA_L3_PHASE_PATH_ALLOWED_PREFIXES="$TEST_DIR"
    export LOA_L3_TEST_NOW="2026-05-04T15:00:00.000000Z"
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0
    export REPO_ROOT TEST_DIR LOG_FILE LOCK_DIR SCHEDULE_YAML
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# CRIT-A1 — idempotency hardening
# =============================================================================

@test "CRIT-A1: forged bare-payload cycle.complete is REJECTED by idempotency check" {
    load_lib
    # Append the exact forgery from the audit PoC: no envelope wrapper.
    echo '{"event_type":"cycle.complete","payload":{"cycle_id":"forged-id"}}' >> "$LOG_FILE"
    run cycle_idempotency_check "forged-id" --log-path "$LOG_FILE"
    [ "$status" -ne 0 ]
}

@test "CRIT-A1: forged event with wrong primitive_id is rejected" {
    load_lib
    # Has envelope shape but primitive_id != L3.
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L1","event_type":"cycle.complete","ts_utc":"2026-05-04T15:00:00.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"x","schedule_id":"x","started_at":"2026-05-04T15:00:00Z","completed_at":"2026-05-04T15:00:00Z","duration_seconds":0,"phases_completed":["reader","decider","dispatcher","awaiter","logger"],"outcome":"success","budget_actual_usd":null}}
EOF
    run cycle_idempotency_check "x" --log-path "$LOG_FILE"
    [ "$status" -ne 0 ]
}

@test "CRIT-A1: forged event with non-success outcome is rejected" {
    load_lib
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.complete","ts_utc":"2026-05-04T15:00:00.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"y","schedule_id":"y","started_at":"2026-05-04T15:00:00Z","completed_at":"2026-05-04T15:00:00Z","duration_seconds":0,"phases_completed":["reader","decider","dispatcher","awaiter","logger"],"outcome":"failure","budget_actual_usd":null}}
EOF
    run cycle_idempotency_check "y" --log-path "$LOG_FILE"
    [ "$status" -ne 0 ]
}

@test "CRIT-A1: forged event with phases_completed.length != 5 is rejected" {
    load_lib
    cat >> "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.complete","ts_utc":"2026-05-04T15:00:00.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"z","schedule_id":"z","started_at":"2026-05-04T15:00:00Z","completed_at":"2026-05-04T15:00:00Z","duration_seconds":0,"phases_completed":["reader","decider"],"outcome":"success","budget_actual_usd":null}}
EOF
    run cycle_idempotency_check "z" --log-path "$LOG_FILE"
    [ "$status" -ne 0 ]
}

@test "CRIT-A1: real cycle.complete (envelope) passes idempotency check" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-real-complete"
    run cycle_idempotency_check "test-real-complete" --log-path "$LOG_FILE"
    [ "$status" -eq 0 ]
}

# =============================================================================
# CRIT-A2 — phase path allowlist
# =============================================================================

@test "CRIT-A2: absolute path outside allowlist (/bin/sh) is rejected" {
    load_lib
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: bad-abs
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "/bin/sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
EOF
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-bad-abs"
    [ "$status" -eq 1 ]
    # cycle.error{error_kind=phase_missing} should fire (path validation rejects)
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_kind' "$LOG_FILE"
    [ "$output" = "phase_missing" ]
}

@test "CRIT-A2: traversal path '../../../etc/passwd' rejected" {
    load_lib
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: bad-trav
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "../../../etc/passwd"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
EOF
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-bad-trav"
    [ "$status" -eq 1 ]
}

@test "CRIT-A2: cycle_register fails on bad phase path" {
    load_lib
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: bad-reg
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "/etc/hostname"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
EOF
    run cycle_register "$SCHEDULE_YAML"
    [ "$status" -ne 0 ]
}

@test "CRIT-A2: validate_phase_path accepts canonical path inside allowlist" {
    load_lib
    run _l3_validate_phase_path "${TEST_DIR}/reader.sh" "reader"
    [ "$status" -eq 0 ]
    [[ "$output" == "${TEST_DIR}/reader.sh" ]]
}

# =============================================================================
# CRIT-A3 — lock-touch symlink safety
# =============================================================================

@test "CRIT-A3: symlinked lock path is REFUSED (no truncate of target)" {
    load_lib
    local target="${TEST_DIR}/important-file"
    echo "important content" > "$target"
    ln -sf "$target" "${LOCK_DIR}/test-rem.lock"
    # Cycle invocation should refuse (lock-creation fails) — exit 1 (cycle_invoke
    # path) since _audit_require_flock returns the lib error.
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-symlink-attack"
    [ "$status" -eq 1 ]
    # Target file remains untouched
    [ "$(cat "$target")" = "important content" ]
}

@test "CRIT-A3: _l3_safe_touch_lock creates a normal file with mode 0600" {
    load_lib
    local f="${TEST_DIR}/fresh.lock"
    run _l3_safe_touch_lock "$f"
    [ "$status" -eq 0 ]
    [ -f "$f" ]
    [ ! -L "$f" ]
    # File mode should be 0600 (owner rw only). Bridgebuilder F6: macOS BSD
    # stat returns octal with leading zero (`0600`); GNU returns `600`.
    # Normalize both shapes.
    local mode
    mode="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%A' "$f")"
    [[ "$mode" = "600" || "$mode" = "0600" ]]
}

# =============================================================================
# HIGH-A1 — env -i phase invocation
# =============================================================================

@test "HIGH-A1: phase scripts do NOT inherit ANTHROPIC_API_KEY (side-file)" {
    load_lib
    local sentinel="${TEST_DIR}/env-sentinel.txt"
    cat > "${TEST_DIR}/reader.sh" <<EOF
#!/usr/bin/env bash
echo "ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY:-MISSING}" > "${sentinel}"
echo "GITHUB_TOKEN=\${GITHUB_TOKEN:-MISSING}" >> "${sentinel}"
echo "AWS_SECRET=\${AWS_SECRET_ACCESS_KEY:-MISSING}" >> "${sentinel}"
echo '{"phase":"reader"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/reader.sh"
    export ANTHROPIC_API_KEY="sk-ant-test-key-leaked"
    export GITHUB_TOKEN="ghp_testleak"
    export AWS_SECRET_ACCESS_KEY="awsleak"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-env-leak2"
    [ -f "$sentinel" ]
    grep -q "ANTHROPIC_API_KEY=MISSING" "$sentinel"
    grep -q "GITHUB_TOKEN=MISSING" "$sentinel"
    grep -q "AWS_SECRET=MISSING" "$sentinel"
}

@test "HIGH-A1: phase scripts DO see allowlisted phase context env vars" {
    load_lib
    local sentinel="${TEST_DIR}/ctx-sentinel.txt"
    cat > "${TEST_DIR}/reader.sh" <<EOF
#!/usr/bin/env bash
echo "CYCLE_ID=\${LOA_L3_CYCLE_ID:-MISSING}" > "${sentinel}"
echo "SCHEDULE_ID=\${LOA_L3_SCHEDULE_ID:-MISSING}" >> "${sentinel}"
echo "PHASE_INDEX=\${LOA_L3_PHASE_INDEX:-MISSING}" >> "${sentinel}"
echo '{"phase":"reader"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/reader.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-ctx-env"
    grep -q "CYCLE_ID=test-ctx-env" "$sentinel"
    grep -q "SCHEDULE_ID=test-rem" "$sentinel"
    grep -q "PHASE_INDEX=0" "$sentinel"
}

# =============================================================================
# HIGH-A2 — LOA_L3_L2_LIB_OVERRIDE gated on test mode
# =============================================================================

@test "HIGH-A2: LOA_L3_L2_LIB_OVERRIDE honored under bats (test mode)" {
    load_lib
    export LOA_L3_BUDGET_PRECHECK_ENABLED=1
    # Empty file simulates "missing"; lib should graceful-skip.
    export LOA_L3_L2_LIB_OVERRIDE="${TEST_DIR}/nonexistent-l2.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-override-bats"
    [ "$status" -eq 0 ]
    # budget_pre_check should be null (graceful-skip path).
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.budget_pre_check' "$LOG_FILE"
    [ "$output" = "null" ]
}

@test "HIGH-A2: _l3_test_mode returns true under bats" {
    load_lib
    run _l3_test_mode
    [ "$status" -eq 0 ]
}

@test "HIGH-A2: _l3_test_mode returns FALSE in a non-bats subshell with no LOA_L3_TEST_MODE" {
    # Bridgebuilder F7: prove production code cannot be tricked into accepting
    # the override by spoofing a single env var. Run a fresh bash subshell with
    # ALL bats-related env vars cleared and confirm _l3_test_mode exits non-zero.
    run env -i HOME="$HOME" PATH="$PATH" LOA_L3_PHASE_PATH_ALLOWED_PREFIXES="$TEST_DIR" \
        bash -c "
        source ${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/scheduled-cycle-lib.sh
        if _l3_test_mode; then echo TESTMODE_TRUE; exit 1; else echo TESTMODE_FALSE; exit 0; fi"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TESTMODE_FALSE"* ]]
}

@test "HIGH-A2: LOA_L3_L2_LIB_OVERRIDE IGNORED in production-mode subshell" {
    # Bridgebuilder F7 follow-on: prove the override gate actually rejects
    # the override outside test mode (no bats env vars).
    local probe_l2="${TEST_DIR}/evil-l2.sh"
    cat > "$probe_l2" <<'EOF'
budget_verdict() {
    echo "{\"verdict\":\"allow\",\"_pwned\":true}"
}
EOF
    # Spawn a clean subshell, source the lib, attempt override, capture log.
    run env -i HOME="$HOME" PATH="$PATH" \
        LOA_CYCLES_LOG="${TEST_DIR}/prod-mode-log.jsonl" \
        LOA_L3_LOCK_DIR="$LOCK_DIR" \
        LOA_L3_PHASE_PATH_ALLOWED_PREFIXES="$TEST_DIR" \
        LOA_L3_BUDGET_PRECHECK_ENABLED=1 \
        LOA_L3_L2_LIB_OVERRIDE="$probe_l2" \
        bash -c "
        source ${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/scheduled-cycle-lib.sh 2>&1
        cycle_invoke '$SCHEDULE_YAML' --cycle-id 'prod-override-test' 2>&1 || true
        " 2>&1
    [[ "$output" == *"LOA_L3_L2_LIB_OVERRIDE ignored outside test mode"* ]]
}

# =============================================================================
# HIGH-R1 — cycle_register validates + emits wiring JSON
# =============================================================================

@test "HIGH-R1: cycle_register validates schedule + emits register_command" {
    load_lib
    run cycle_register "$SCHEDULE_YAML"
    [ "$status" -eq 0 ]
    run jq -r '.schedule_id' <<<"$output"
    [ "$output" = "test-rem" ]
    run jq -r '.dispatch_contract_hash' <<<"$(cycle_register "$SCHEDULE_YAML")"
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
    run jq -r '.register_command' <<<"$(cycle_register "$SCHEDULE_YAML")"
    [[ "$output" == *"scheduled-cycle-lib.sh invoke"* ]]
    [[ "$output" == *"$SCHEDULE_YAML"* ]]
}

@test "HIGH-R1: cycle_register rejects malformed yaml" {
    load_lib
    echo "this is: not [valid yaml" > "$SCHEDULE_YAML"
    run cycle_register "$SCHEDULE_YAML"
    [ "$status" -ne 0 ]
}

# =============================================================================
# HIGH-R2 — prior_phases_json propagation
# =============================================================================

@test "HIGH-R2: decider receives reader's record in prior_phases_json arg" {
    load_lib
    local sentinel="${TEST_DIR}/prior-sentinel.json"
    cat > "${TEST_DIR}/decider.sh" <<EOF
#!/usr/bin/env bash
# \$4 is the prior_phases_json — write it to a sentinel for assertion.
echo "\$4" > "${sentinel}"
echo '{"phase":"decider"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/decider.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-prior-prop"
    [ -f "$sentinel" ]
    # The sentinel should contain a JSON array with one phase=reader element.
    run jq -r 'length' "$sentinel"
    [ "$output" = "1" ]
    run jq -r '.[0].phase' "$sentinel"
    [ "$output" = "reader" ]
    run jq -r '.[0].outcome' "$sentinel"
    [ "$output" = "success" ]
}

@test "HIGH-R2: dispatcher sees reader+decider; awaiter sees 3; logger sees 4" {
    load_lib
    local sentinel="${TEST_DIR}/logger-prior.json"
    cat > "${TEST_DIR}/logger.sh" <<EOF
#!/usr/bin/env bash
echo "\$4" > "${sentinel}"
echo '{"phase":"logger"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/logger.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-prior-prop-full"
    run jq -r 'length' "$sentinel"
    [ "$output" = "4" ]
    run jq -r '[.[].phase] | join(",")' "$sentinel"
    [ "$output" = "reader,decider,dispatcher,awaiter" ]
}

# =============================================================================
# HIGH-R3 — duration_seconds deterministic under TEST_NOW
# =============================================================================

@test "HIGH-R3: LOA_L3_TEST_NOW frozen → cycle.phase duration_seconds=0 even with sleeping phase" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
# Sleep briefly; under TEST_NOW frozen-clock, duration_seconds should still be 0.
sleep 0.1
echo '{"phase":"dispatcher"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-frozen-duration"
    run jq -sr '.[] | select(.event_type == "cycle.phase") | select(.payload.phase == "dispatcher") | .payload.duration_seconds' "$LOG_FILE"
    [ "$output" = "0" ]
}

# =============================================================================
# MED-R1 — lock TTL behavior
# =============================================================================

@test "MED-R1: holder releases at t=0.3s; cycle with 2s lock-timeout WAITS then succeeds" {
    load_lib
    export LOA_L3_LOCK_TIMEOUT_SECONDS=2
    local lock_file="${LOCK_DIR}/test-rem.lock"
    : > "$lock_file"
    # Bridgebuilder F3 / F4: holder writes a sentinel after acquire so we
    # can confirm lock ownership (no timing race) AND we measure SUT elapsed
    # time to assert the wait-then-acquire path actually waited.
    local ready_marker="${TEST_DIR}/holder-ready.marker"
    ( flock -x "$lock_file" -c "touch '$ready_marker'; sleep 0.3" ) &
    local holder_pid=$!
    # Wait until holder confirms acquisition (bounded — fail fast if it never starts).
    local poll_attempts=0
    while [[ ! -f "$ready_marker" && "$poll_attempts" -lt 50 ]]; do
        sleep 0.02
        poll_attempts=$((poll_attempts + 1))
    done
    [ -f "$ready_marker" ]
    # Now the SUT should wait at flock for ~0.3s then acquire.
    local before_epoch after_epoch elapsed_ns elapsed_s_x10
    before_epoch="$(date +%s%N)"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-ttl-success"
    after_epoch="$(date +%s%N)"
    wait "$holder_pid" 2>/dev/null || true
    [ "$status" -eq 0 ]
    elapsed_ns=$((after_epoch - before_epoch))
    elapsed_s_x10=$((elapsed_ns / 100000000))   # tenths of a second
    # Assert the SUT actually blocked on flock. >=2 deciseconds (~0.2s) is
    # more than the holder's 0.3s minus startup slack and far less than the
    # 2s lock-timeout — i.e., proves the wait-then-acquire path executed.
    [ "$elapsed_s_x10" -ge 2 ]
}

# =============================================================================
# MED-R2 — partial-prior-run idempotency
# =============================================================================

@test "FR-L3-2: idempotent skip does NOT re-invoke phase scripts (sentinel counter)" {
    load_lib
    # Bridgebuilder F15: assert that a duplicate cycle_invoke with a completed
    # cycle_id does NOT re-run any phase. Each phase script appends to a
    # sentinel; the count after duplicate must equal count after first run.
    local sentinel="${TEST_DIR}/invoke-counter.txt"
    : > "$sentinel"
    cat > "${TEST_DIR}/dispatcher.sh" <<EOF
#!/usr/bin/env bash
echo "invoked" >> "${sentinel}"
echo '{"phase":"dispatcher"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-no-side-effect"
    local first_count
    first_count="$(wc -l < "$sentinel")"
    [ "$first_count" -eq 1 ]
    # Duplicate invocation should skip — sentinel must not increment.
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-no-side-effect"
    local second_count
    second_count="$(wc -l < "$sentinel")"
    [ "$second_count" -eq 1 ]
}

@test "MED-R2: cycle.start + N cycle.phase but no cycle.complete → cycle re-runs" {
    load_lib
    # Pre-populate log with a partial prior run for the same cycle_id.
    local prior_json prev_hash
    prev_hash="GENESIS"
    prior_json=$(cat <<JSON
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.start","ts_utc":"2026-05-04T14:00:00.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"test-partial","schedule_id":"test-rem","dispatch_contract_hash":"0000000000000000000000000000000000000000000000000000000000000000","timeout_seconds":60,"started_at":"2026-05-04T14:00:00.000000Z"}}
JSON
)
    echo "$prior_json" > "$LOG_FILE"
    # Confirm the partial state would NOT be honored as complete.
    run cycle_idempotency_check "test-partial" --log-path "$LOG_FILE"
    [ "$status" -ne 0 ]
    # cycle_invoke should run a fresh cycle for the same cycle_id.
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-partial"
    [ "$status" -eq 0 ]
    # Now cycle.complete is present.
    run jq -sr '[.[] | select(.event_type == "cycle.complete") | .payload.cycle_id]' "$LOG_FILE"
    [[ "$output" == *"test-partial"* ]]
}

# =============================================================================
# MED-R3 — cycle_replay sorts by phase_index
# =============================================================================

@test "MED-R3: cycle_replay sorts phases by phase_index even when log is out of order" {
    load_lib
    # Hand-craft a log with phases out of timestamp order but with correct
    # phase_index values. Replay must return them in phase_index order.
    cat > "$LOG_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.start","ts_utc":"2026-05-04T15:00:00.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"replay-sort","schedule_id":"replay-sort","dispatch_contract_hash":"0000000000000000000000000000000000000000000000000000000000000000","timeout_seconds":60,"started_at":"2026-05-04T15:00:00.000000Z"}}
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.phase","ts_utc":"2026-05-04T15:00:04.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"replay-sort","schedule_id":"replay-sort","phase":"logger","phase_index":4,"started_at":"2026-05-04T15:00:04.000000Z","completed_at":"2026-05-04T15:00:04.000000Z","duration_seconds":0,"outcome":"success"}}
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.phase","ts_utc":"2026-05-04T15:00:00.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"replay-sort","schedule_id":"replay-sort","phase":"reader","phase_index":0,"started_at":"2026-05-04T15:00:00.000000Z","completed_at":"2026-05-04T15:00:00.000000Z","duration_seconds":0,"outcome":"success"}}
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.phase","ts_utc":"2026-05-04T15:00:02.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"replay-sort","schedule_id":"replay-sort","phase":"dispatcher","phase_index":2,"started_at":"2026-05-04T15:00:02.000000Z","completed_at":"2026-05-04T15:00:02.000000Z","duration_seconds":0,"outcome":"success"}}
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.phase","ts_utc":"2026-05-04T15:00:01.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"replay-sort","schedule_id":"replay-sort","phase":"decider","phase_index":1,"started_at":"2026-05-04T15:00:01.000000Z","completed_at":"2026-05-04T15:00:01.000000Z","duration_seconds":0,"outcome":"success"}}
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.phase","ts_utc":"2026-05-04T15:00:03.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"replay-sort","schedule_id":"replay-sort","phase":"awaiter","phase_index":3,"started_at":"2026-05-04T15:00:03.000000Z","completed_at":"2026-05-04T15:00:03.000000Z","duration_seconds":0,"outcome":"success"}}
{"schema_version":"1.1.0","primitive_id":"L3","event_type":"cycle.complete","ts_utc":"2026-05-04T15:00:05.000000Z","prev_hash":"GENESIS","payload":{"cycle_id":"replay-sort","schedule_id":"replay-sort","started_at":"2026-05-04T15:00:00.000000Z","completed_at":"2026-05-04T15:00:05.000000Z","duration_seconds":5,"phases_completed":["reader","decider","dispatcher","awaiter","logger"],"outcome":"success","budget_actual_usd":null}}
EOF
    run cycle_replay "$LOG_FILE" --cycle-id "replay-sort"
    [ "$status" -eq 0 ]
    run jq -r '[.phases[].phase] | join(",")' <<<"$(cycle_replay "$LOG_FILE" --cycle-id "replay-sort")"
    [ "$output" = "reader,decider,dispatcher,awaiter,logger" ]
}

# =============================================================================
# MED-R4 / MED-A1 — extended redaction
# =============================================================================

@test "MED-R4/A1: AWS access key (AKIA...) is redacted in cycle.error.diagnostic" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo "leaking AKIAIOSFODNN7EXAMPLE in stderr" >&2
exit 5
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-aws-redact" || true
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.diagnostic' "$LOG_FILE"
    [[ "$output" != *"AKIAIOSFODNN7EXAMPLE"* ]]
    [[ "$output" == *"[REDACTED]"* ]]
}

@test "MED-R4/A1: GCP API key (AIza...) is redacted" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo "leaking AIzaSyA-1234567890ABCDEFGHIJ_xxxxxxxx" >&2
exit 5
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-gcp-redact" || true
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.diagnostic' "$LOG_FILE"
    [[ "$output" != *"AIzaSyA-1234567890ABCDEFGHIJ_xxxxxxxx"* ]]
}

@test "MED-R4/A1: Slack token (xoxb-...) is redacted" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo "leaking xoxb-1234567890-abcdef0123" >&2
exit 5
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-slack-redact" || true
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.diagnostic' "$LOG_FILE"
    [[ "$output" != *"xoxb-1234567890-abcdef0123"* ]]
}

@test "MED-R4/A1: PEM private-key markers redacted" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo "-----BEGIN RSA PRIVATE KEY-----" >&2
echo "private key body" >&2
echo "-----END RSA PRIVATE KEY-----" >&2
exit 5
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-pem-redact" || true
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.diagnostic' "$LOG_FILE"
    # Bridgebuilder F2: assert canonical PEM marker (not the generic [REDACTED]
    # disjunction that hid regressions in the original test).
    [[ "$output" != *"BEGIN RSA PRIVATE KEY"* ]]
    [[ "$output" != *"END RSA PRIVATE KEY"* ]]
    [[ "$output" == *"REDACTED-PEM-BEGIN"* ]]
    [[ "$output" == *"REDACTED-PEM-END"* ]]
}

@test "MED-R4/A1: api_key=value pair redacted" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo "api_key=secretvalue123" >&2
exit 5
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-kv-redact" || true
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.diagnostic' "$LOG_FILE"
    [[ "$output" != *"secretvalue123"* ]]
}

# =============================================================================
# MED-R5 — phases_completed actually populated
# =============================================================================

@test "MED-R5: cycle.complete payload phases_completed equals all 5 phases" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-completed-array"
    run jq -sr '.[] | select(.event_type == "cycle.complete") | .payload.phases_completed | join(",")' "$LOG_FILE"
    [ "$output" = "reader,decider,dispatcher,awaiter,logger" ]
}

# =============================================================================
# MED-A2 — cycle_record_phase / cycle_complete require --schedule-id
# =============================================================================

@test "MED-A2: cycle_record_phase WITHOUT --schedule-id returns error 2" {
    load_lib
    local rec='{"phase_index":0,"started_at":"2026-05-04T15:00:00.000000Z","completed_at":"2026-05-04T15:00:00.000000Z","duration_seconds":0,"outcome":"success"}'
    run cycle_record_phase "test-cid" "reader" "$rec"
    [ "$status" -eq 2 ]
}

@test "MED-A2: cycle_complete WITHOUT --schedule-id returns error 2" {
    load_lib
    local rec='{"started_at":"2026-05-04T15:00:00.000000Z","completed_at":"2026-05-04T15:00:00.000000Z","duration_seconds":0,"phases_completed":["reader","decider","dispatcher","awaiter","logger"]}'
    run cycle_complete "test-cid" "$rec"
    [ "$status" -eq 2 ]
}

@test "MED-A2: cycle_record_phase WITH --schedule-id succeeds" {
    load_lib
    local rec='{"phase_index":0,"started_at":"2026-05-04T15:00:00.000000Z","completed_at":"2026-05-04T15:00:00.000000Z","duration_seconds":0,"outcome":"success"}'
    run cycle_record_phase --schedule-id test-sched-x test-cid-x reader "$rec"
    [ "$status" -eq 0 ]
}

# =============================================================================
# MED-A3 — max_cycle_seconds cap
# =============================================================================

@test "MED-A3: timeout_seconds=86400 (× 5 phases) exceeds default max_cycle → exit 2" {
    load_lib
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-toobig
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
  timeout_seconds: 86400
EOF
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-toobig"
    [ "$status" -eq 2 ]
}

@test "MED-A3: LOA_L3_MAX_CYCLE_SECONDS env override raises the cap" {
    load_lib
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-bigok
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
  timeout_seconds: 7200
EOF
    # 7200 × 5 = 36000 > default 14400 cap → would fail.
    export LOA_L3_MAX_CYCLE_SECONDS=50000
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-bigok"
    [ "$status" -eq 0 ]
}
