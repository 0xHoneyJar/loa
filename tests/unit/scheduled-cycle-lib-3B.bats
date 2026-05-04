#!/usr/bin/env bats
# =============================================================================
# scheduled-cycle-lib-3B.bats — L3 Sprint 3B
#
# Covers FR-L3-2 (idempotency wired into cycle_invoke), FR-L3-4 (subsequent
# cycles unaffected by errors), FR-L3-5 (concurrency lock + cycle.lock_failed),
# and per-phase timeout enforcement.
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
echo "{\"phase\":\"${phase}\"}"
exit 0
EOF
        chmod +x "${TEST_DIR}/${phase}.sh"
    done

    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-3b
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
    export LOA_L3_LOCK_TIMEOUT_SECONDS=1
    export LOA_L3_TEST_NOW="2026-05-04T13:00:00.000000Z"
    export LOA_L3_PHASE_PATH_ALLOWED_PREFIXES="$TEST_DIR"
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0
    export REPO_ROOT TEST_DIR LOG_FILE LOCK_DIR SCHEDULE_YAML
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# Lock acquired + released (FR-L3-5)
# -----------------------------------------------------------------------------
@test "FR-L3-5: lock file created at .run/cycles/<schedule_id>.lock" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-lock-1"
    [ -f "${LOCK_DIR}/test-3b.lock" ]
}

@test "FR-L3-5: lock released after happy-path cycle (next invocation succeeds)" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-rel-1"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-rel-2"
    [ "$status" -eq 0 ]
}

@test "FR-L3-5: lock released after error cycle (next invocation succeeds)" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
exit 11
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-rel-err-1" || true
    # Restore happy dispatcher.
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"phase":"dispatcher"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-rel-err-2"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Lock contention emits cycle.lock_failed (FR-L3-5)
# -----------------------------------------------------------------------------
@test "FR-L3-5: lock contention emits cycle.lock_failed and exits 4" {
    load_lib
    # Hold the lock file from an external process for 5 seconds.
    local lock_file="${LOCK_DIR}/test-3b.lock"
    : > "$lock_file"
    flock -x "$lock_file" -c "sleep 5" &
    local holder_pid=$!
    # Give holder time to acquire.
    sleep 0.3
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-contend"
    local cycle_status="$status"
    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true
    [ "$cycle_status" -eq 4 ]
    [ -f "$LOG_FILE" ]
    run jq -sr '.[] | .event_type' "$LOG_FILE"
    [ "$output" = "cycle.lock_failed" ]
}

@test "FR-L3-5: cycle.lock_failed payload includes schedule_id, lock_path, cycle_id" {
    load_lib
    local lock_file="${LOCK_DIR}/test-3b.lock"
    : > "$lock_file"
    flock -x "$lock_file" -c "sleep 5" &
    local holder_pid=$!
    sleep 0.3
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-contend-payload" 2>/dev/null || true
    kill "$holder_pid" 2>/dev/null || true
    wait "$holder_pid" 2>/dev/null || true
    run jq -sr '.[0] | .payload.schedule_id' "$LOG_FILE"
    [ "$output" = "test-3b" ]
    run jq -sr '.[0] | .payload.cycle_id' "$LOG_FILE"
    [ "$output" = "test-3b-contend-payload" ]
    run jq -sr '.[0] | .payload.lock_path' "$LOG_FILE"
    [[ "$output" == *"test-3b.lock"* ]]
}

# -----------------------------------------------------------------------------
# Idempotency wired into cycle_invoke (FR-L3-2)
# -----------------------------------------------------------------------------
@test "FR-L3-2: second cycle_invoke with same cycle_id is no-op (idempotent)" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-idem"
    local first_lines
    first_lines="$(wc -l < "$LOG_FILE")"
    [ "$first_lines" -eq 7 ]  # cycle.start + 5 cycle.phase + cycle.complete
    # Second invocation with same cycle_id.
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-idem"
    [ "$status" -eq 0 ]
    local second_lines
    second_lines="$(wc -l < "$LOG_FILE")"
    [ "$second_lines" -eq "$first_lines" ]   # No new events written
}

@test "FR-L3-2: second cycle_invoke with different cycle_id runs fresh" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-fresh-1"
    local first_lines
    first_lines="$(wc -l < "$LOG_FILE")"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-fresh-2"
    local second_lines
    second_lines="$(wc -l < "$LOG_FILE")"
    [ "$second_lines" -eq "$((first_lines + 7))" ]
}

@test "FR-L3-2: idempotency check is on cycle.complete only (errored runs are retried)" {
    load_lib
    cat > "${TEST_DIR}/awaiter.sh" <<'EOF'
#!/usr/bin/env bash
exit 9
EOF
    chmod +x "${TEST_DIR}/awaiter.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-retry" || true
    local first_lines
    first_lines="$(wc -l < "$LOG_FILE")"
    # Restore happy awaiter
    cat > "${TEST_DIR}/awaiter.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"phase":"awaiter"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/awaiter.sh"
    # Same cycle_id should run fresh because last attempt errored.
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-retry"
    [ "$status" -eq 0 ]
    local second_lines
    second_lines="$(wc -l < "$LOG_FILE")"
    [ "$second_lines" -gt "$first_lines" ]
}

# -----------------------------------------------------------------------------
# FR-L3-4: subsequent cycles after error are unaffected
# -----------------------------------------------------------------------------
@test "FR-L3-4: cycle after error runs fresh; original error preserved in log" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
exit 11
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-err-prior" || true
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo '{"phase":"dispatcher"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-err-fresh"
    [ "$status" -eq 0 ]
    # Prior error event preserved.
    local n_err
    n_err="$(jq -sr '[.[] | select(.event_type == "cycle.error") | .payload.cycle_id] | length' "$LOG_FILE")"
    [ "$n_err" -eq 1 ]
    # Fresh cycle.complete present for the second cycle_id.
    local n_complete
    n_complete="$(jq -sr '[.[] | select(.event_type == "cycle.complete") | .payload.cycle_id] | length' "$LOG_FILE")"
    [ "$n_complete" -eq 1 ]
}

# -----------------------------------------------------------------------------
# Per-phase timeout (FR-L3-3 + IMP)
# -----------------------------------------------------------------------------
@test "per-phase timeout: phase exceeding timeout → outcome=timeout, exit_code=124" {
    load_lib
    # Configure a 1-second per-phase timeout.
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-3b-to
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
  timeout_seconds: 1
EOF
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
sleep 5
echo '{"phase":"dispatcher"}'
exit 0
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    # Bump real-time clock; tests cannot use TEST_NOW for sleep enforcement.
    unset LOA_L3_TEST_NOW
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-to-cycle"
    [ "$status" -eq 1 ]
    # Last cycle.phase should have outcome=timeout.
    run jq -sr '[.[] | select(.event_type == "cycle.phase")] | last | .payload.outcome' "$LOG_FILE"
    [ "$output" = "timeout" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_kind' "$LOG_FILE"
    [ "$output" = "phase_timeout" ]
}

@test "per-phase timeout: timeout phase records exit_code=124 and timeout_seconds in event" {
    load_lib
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-3b-to2
schedule: "*/5 * * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
  timeout_seconds: 1
EOF
    cat > "${TEST_DIR}/awaiter.sh" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
    chmod +x "${TEST_DIR}/awaiter.sh"
    unset LOA_L3_TEST_NOW
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-to2-cycle" || true
    run jq -sr '[.[] | select(.event_type == "cycle.phase")] | last | .payload.exit_code' "$LOG_FILE"
    [ "$output" = "124" ]
    run jq -sr '[.[] | select(.event_type == "cycle.phase")] | last | .payload.timeout_seconds' "$LOG_FILE"
    [ "$output" = "1" ]
}

# -----------------------------------------------------------------------------
# Lock dir creation
# -----------------------------------------------------------------------------
@test "FR-L3-5: missing .run/cycles/ dir is auto-created on first invocation" {
    load_lib
    rm -rf "$LOCK_DIR"
    # Override LOA_L3_LOCK_DIR to a still-missing directory.
    export LOA_L3_LOCK_DIR="${TEST_DIR}/.run/cycles-fresh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-3b-mkdir"
    [ "$status" -eq 0 ]
    [ -d "$LOA_L3_LOCK_DIR" ]
}
