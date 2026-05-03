#!/usr/bin/env bats
# =============================================================================
# scheduled-cycle-lib-3A.bats — L3 scheduled-cycle-template Sprint 3A
#
# Covers:
#   - 5 per-event-type schemas exist and are valid
#   - cycle_invoke happy path (cycle.start + 5×cycle.phase + cycle.complete)
#   - cycle_id is content-addressed (same schedule + dc → same id)
#   - dispatch_contract_hash deterministic
#   - dry-run mode (cycle.start only)
#   - per-phase error (any phase) emits cycle.phase[error] + cycle.error;
#       subsequent phases not invoked (FR-L3-3 + FR-L3-4)
#   - phases_completed correctly populated on partial failure
#   - cycle_replay reassembles CycleRecord per SDD §5.5.3
#   - cycle_idempotency_check (FR-L3-2)
#   - schedule yaml validation (missing required fields)
#   - schedule_id regex enforcement
# =============================================================================

load_lib() {
    # shellcheck source=/dev/null
    source "${BATS_TEST_DIRNAME}/../../.claude/scripts/lib/scheduled-cycle-lib.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    LOG_FILE="${TEST_DIR}/cycles.jsonl"
    SCHEDULE_YAML="${TEST_DIR}/schedule.yaml"

    # 5 mock phase scripts that emit a known marker to stdout.
    for phase in reader decider dispatcher awaiter logger; do
        local p="${TEST_DIR}/${phase}.sh"
        cat > "$p" <<EOF
#!/usr/bin/env bash
echo "{\"phase\":\"${phase}\",\"cycle_id\":\"\$1\"}"
exit 0
EOF
        chmod +x "$p"
    done

    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: test-cycle-3a
schedule: "0 3 * * *"
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
    export LOA_L3_TEST_NOW="2026-05-04T12:00:00.000000Z"
    unset LOA_AUDIT_SIGNING_KEY_ID
    export LOA_AUDIT_VERIFY_SIGS=0
    export REPO_ROOT TEST_DIR LOG_FILE SCHEDULE_YAML
}

teardown() {
    rm -rf "$TEST_DIR"
}

# -----------------------------------------------------------------------------
# Schema sanity
# -----------------------------------------------------------------------------
@test "schemas: all 5 cycle-event payload schemas exist and are valid JSON" {
    local schema_dir="${REPO_ROOT}/.claude/data/trajectory-schemas/cycle-events"
    local s
    for s in cycle-start cycle-phase cycle-complete cycle-error cycle-lock-failed; do
        [ -f "${schema_dir}/${s}.payload.schema.json" ]
        run jq empty "${schema_dir}/${s}.payload.schema.json"
        [ "$status" -eq 0 ]
    done
}

@test "schemas: cycle-start requires cycle_id, schedule_id, dispatch_contract_hash" {
    local schema="${REPO_ROOT}/.claude/data/trajectory-schemas/cycle-events/cycle-start.payload.schema.json"
    run jq -e '.required | contains(["cycle_id","schedule_id","dispatch_contract_hash"])' "$schema"
    [ "$status" -eq 0 ]
}

@test "schemas: cycle-phase enum covers all 5 phases" {
    local schema="${REPO_ROOT}/.claude/data/trajectory-schemas/cycle-events/cycle-phase.payload.schema.json"
    run jq -er '.properties.phase.enum | sort | join(",")' "$schema"
    [ "$status" -eq 0 ]
    [ "$output" = "awaiter,decider,dispatcher,logger,reader" ]
}

# -----------------------------------------------------------------------------
# Hash + cycle_id determinism
# -----------------------------------------------------------------------------
@test "_l3_compute_dispatch_contract_hash: deterministic for same JSON input" {
    load_lib
    local dc='{"reader":"a","decider":"b","dispatcher":"c","awaiter":"d","logger":"e"}'
    local h1 h2
    h1="$(_l3_compute_dispatch_contract_hash "$dc")"
    h2="$(_l3_compute_dispatch_contract_hash "$dc")"
    [ "$h1" = "$h2" ]
    # Sha256 hex
    [[ "$h1" =~ ^[0-9a-f]{64}$ ]]
}

@test "_l3_compute_cycle_id: deterministic for same schedule_id + dc_hash + ts_bucket" {
    load_lib
    local id1 id2
    id1="$(_l3_compute_cycle_id "schedX" "$(printf 'a%.0s' {1..64})" "2026-05-04T12:00Z")"
    id2="$(_l3_compute_cycle_id "schedX" "$(printf 'a%.0s' {1..64})" "2026-05-04T12:00Z")"
    [ "$id1" = "$id2" ]
}

@test "_l3_compute_cycle_id: differs on different ts_bucket" {
    load_lib
    local id1 id2
    id1="$(_l3_compute_cycle_id "schedX" "deadbeef" "2026-05-04T12:00Z")"
    id2="$(_l3_compute_cycle_id "schedX" "deadbeef" "2026-05-04T13:00Z")"
    [ "$id1" != "$id2" ]
}

# -----------------------------------------------------------------------------
# cycle_invoke happy path
# -----------------------------------------------------------------------------
@test "FR-L3-3: cycle_invoke runs all 5 phases in order on happy path" {
    load_lib
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-happy"
    [ "$status" -eq 0 ]
    [ -f "$LOG_FILE" ]
    # Expect 1 cycle.start + 5 cycle.phase + 1 cycle.complete = 7 events.
    local n_lines
    n_lines="$(wc -l < "$LOG_FILE")"
    [ "$n_lines" -eq 7 ]
    # Check event_type ordering.
    run jq -sr '.[] | .event_type' "$LOG_FILE"
    [ "$status" -eq 0 ]
    local expected
    expected=$'cycle.start\ncycle.phase\ncycle.phase\ncycle.phase\ncycle.phase\ncycle.phase\ncycle.complete'
    [ "$output" = "$expected" ]
}

@test "FR-L3-3: phase order is reader → decider → dispatcher → awaiter → logger" {
    load_lib
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-order"
    [ "$status" -eq 0 ]
    run jq -sr '.[] | select(.event_type == "cycle.phase") | .payload.phase' "$LOG_FILE"
    [ "$status" -eq 0 ]
    local expected=$'reader\ndecider\ndispatcher\nawaiter\nlogger'
    [ "$output" = "$expected" ]
}

@test "cycle_invoke: phase_index is 0..4 in order" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-idx"
    run jq -sr '.[] | select(.event_type == "cycle.phase") | .payload.phase_index' "$LOG_FILE"
    [ "$status" -eq 0 ]
    local expected=$'0\n1\n2\n3\n4'
    [ "$output" = "$expected" ]
}

@test "cycle_invoke: cycle.start and cycle.complete reference the same cycle_id" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-cid"
    local start_cid complete_cid
    start_cid="$(jq -sr '.[] | select(.event_type == "cycle.start") | .payload.cycle_id' "$LOG_FILE")"
    complete_cid="$(jq -sr '.[] | select(.event_type == "cycle.complete") | .payload.cycle_id' "$LOG_FILE")"
    [ "$start_cid" = "test-cycle-cid" ]
    [ "$complete_cid" = "test-cycle-cid" ]
}

@test "cycle_invoke: dispatch_contract_hash recorded in cycle.start" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-dch"
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.dispatch_contract_hash' "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
}

@test "cycle_invoke: schedule_cron forwarded into cycle.start payload" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-cron"
    run jq -sr '.[] | select(.event_type == "cycle.start") | .payload.schedule_cron' "$LOG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "0 3 * * *" ]
}

# -----------------------------------------------------------------------------
# dry-run
# -----------------------------------------------------------------------------
@test "cycle_invoke --dry-run: emits cycle.start only, no phases or complete" {
    load_lib
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-dry" --dry-run
    [ "$status" -eq 0 ]
    [ -f "$LOG_FILE" ]
    local n_lines
    n_lines="$(wc -l < "$LOG_FILE")"
    [ "$n_lines" -eq 1 ]
    run jq -sr '.[] | .event_type' "$LOG_FILE"
    [ "$output" = "cycle.start" ]
    run jq -sr '.[] | .payload.dry_run' "$LOG_FILE"
    [ "$output" = "true" ]
}

# -----------------------------------------------------------------------------
# Per-phase error handling (FR-L3-4)
# -----------------------------------------------------------------------------
@test "FR-L3-4: reader phase failure → cycle.error with outcome=failure (no later phases)" {
    load_lib
    # Make reader fail
    cat > "${TEST_DIR}/reader.sh" <<'EOF'
#!/usr/bin/env bash
echo "reader stderr msg" >&2
exit 5
EOF
    chmod +x "${TEST_DIR}/reader.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-reader-fail"
    [ "$status" -eq 1 ]
    # Events: cycle.start + cycle.phase(reader) + cycle.error = 3
    local n_lines
    n_lines="$(wc -l < "$LOG_FILE")"
    [ "$n_lines" -eq 3 ]
    run jq -sr '.[] | .event_type' "$LOG_FILE"
    local expected=$'cycle.start\ncycle.phase\ncycle.error'
    [ "$output" = "$expected" ]
    # cycle.phase outcome is error
    run jq -sr '.[] | select(.event_type == "cycle.phase") | .payload.outcome' "$LOG_FILE"
    [ "$output" = "error" ]
    # cycle.error has outcome=failure (no phases completed before error)
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.outcome' "$LOG_FILE"
    [ "$output" = "failure" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_phase' "$LOG_FILE"
    [ "$output" = "reader" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_kind' "$LOG_FILE"
    [ "$output" = "phase_error" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.exit_code' "$LOG_FILE"
    [ "$output" = "5" ]
}

@test "FR-L3-4: dispatcher (mid-pipeline) failure → outcome=partial; phases_completed=[reader,decider]" {
    load_lib
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
echo "dispatcher boom" >&2
exit 11
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-disp-fail"
    [ "$status" -eq 1 ]
    # Events: start + phase(reader) + phase(decider) + phase(dispatcher) + error = 5
    local n_lines
    n_lines="$(wc -l < "$LOG_FILE")"
    [ "$n_lines" -eq 5 ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.outcome' "$LOG_FILE"
    [ "$output" = "partial" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.phases_completed | join(",")' "$LOG_FILE"
    [ "$output" = "reader,decider" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_phase' "$LOG_FILE"
    [ "$output" = "dispatcher" ]
}

@test "FR-L3-4: error diagnostic captured from phase stderr (truncated/redacted)" {
    load_lib
    cat > "${TEST_DIR}/awaiter.sh" <<'EOF'
#!/usr/bin/env bash
echo "stderr line A" >&2
echo "stderr line B with sk-fakekey00000000000000000000abcd" >&2
exit 7
EOF
    chmod +x "${TEST_DIR}/awaiter.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-diag" || true
    local diag
    diag="$(jq -sr '.[] | select(.event_type == "cycle.error") | .payload.diagnostic' "$LOG_FILE")"
    [[ "$diag" == *"stderr line A"* ]]
    [[ "$diag" == *"[REDACTED]"* ]]
    # sk- pattern should NOT survive
    [[ "$diag" != *"sk-fakekey00000000000000000000abcd"* ]]
}

@test "missing phase script → cycle.error with error_kind=phase_missing" {
    load_lib
    rm "${TEST_DIR}/dispatcher.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-missing"
    [ "$status" -eq 1 ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_kind' "$LOG_FILE"
    [ "$output" = "phase_missing" ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .payload.error_phase' "$LOG_FILE"
    [ "$output" = "dispatcher" ]
}

# -----------------------------------------------------------------------------
# cycle_idempotency_check (FR-L3-2)
# -----------------------------------------------------------------------------
@test "FR-L3-2: cycle_idempotency_check returns 0 when cycle.complete is present" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-idem-yes"
    run cycle_idempotency_check "test-cycle-idem-yes" --log-path "$LOG_FILE"
    [ "$status" -eq 0 ]
}

@test "FR-L3-2: cycle_idempotency_check returns 1 when cycle.complete is absent" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-idem-no" --dry-run
    run cycle_idempotency_check "test-cycle-idem-no" --log-path "$LOG_FILE"
    [ "$status" -eq 1 ]
}

@test "FR-L3-2: cycle_idempotency_check returns 1 when log file missing" {
    load_lib
    run cycle_idempotency_check "any-cycle" --log-path "${TEST_DIR}/nonexistent.jsonl"
    [ "$status" -eq 1 ]
}

@test "FR-L3-2: cycle_idempotency_check returns 1 when error event but no complete" {
    load_lib
    cat > "${TEST_DIR}/logger.sh" <<'EOF'
#!/usr/bin/env bash
exit 9
EOF
    chmod +x "${TEST_DIR}/logger.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-err-only" || true
    run cycle_idempotency_check "test-cycle-err-only" --log-path "$LOG_FILE"
    [ "$status" -eq 1 ]
}

# -----------------------------------------------------------------------------
# cycle_replay (FR-L3-7)
# -----------------------------------------------------------------------------
@test "FR-L3-7: cycle_replay reassembles CycleRecord with all 5 phases on success" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-replay"
    run cycle_replay "$LOG_FILE" --cycle-id "test-cycle-replay"
    [ "$status" -eq 0 ]
    run jq -r '.outcome' <<<"$output"
    [ "$output" = "success" ]
    run jq -r '.phases | length' <<<"$(cycle_replay "$LOG_FILE" --cycle-id "test-cycle-replay")"
    [ "$output" = "5" ]
}

@test "FR-L3-7: cycle_replay reassembles partial record on phase failure" {
    load_lib
    cat > "${TEST_DIR}/awaiter.sh" <<'EOF'
#!/usr/bin/env bash
exit 13
EOF
    chmod +x "${TEST_DIR}/awaiter.sh"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-replay-partial" || true
    local rec
    rec="$(cycle_replay "$LOG_FILE" --cycle-id "test-cycle-replay-partial")"
    run jq -r '.outcome' <<<"$rec"
    [ "$output" = "partial" ]
    run jq -r '.phases | length' <<<"$rec"
    [ "$output" = "4" ]
}

@test "FR-L3-7: cycle_replay returns array of all cycles when --cycle-id absent" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-multi-1"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-cycle-multi-2"
    run cycle_replay "$LOG_FILE"
    [ "$status" -eq 0 ]
    local cnt
    cnt="$(jq '. | length' <<<"$output")"
    [ "$cnt" -eq 2 ]
}

# -----------------------------------------------------------------------------
# Schedule yaml validation
# -----------------------------------------------------------------------------
@test "_l3_parse_schedule_yaml: rejects missing schedule_id" {
    load_lib
    echo 'schedule: "0 3 * * *"
dispatch_contract:
  reader: x
  decider: x
  dispatcher: x
  awaiter: x
  logger: x' > "$SCHEDULE_YAML"
    run _l3_parse_schedule_yaml "$SCHEDULE_YAML"
    [ "$status" -ne 0 ]
}

@test "_l3_parse_schedule_yaml: rejects missing dispatch_contract.dispatcher" {
    load_lib
    echo 'schedule_id: t1
schedule: "0 3 * * *"
dispatch_contract:
  reader: x
  decider: x
  awaiter: x
  logger: x' > "$SCHEDULE_YAML"
    run _l3_parse_schedule_yaml "$SCHEDULE_YAML"
    [ "$status" -ne 0 ]
}

@test "cycle_invoke: rejects bad schedule_id" {
    load_lib
    cat > "$SCHEDULE_YAML" <<EOF
schedule_id: "BAD ID with spaces!"
schedule: "0 3 * * *"
dispatch_contract:
  reader: "${TEST_DIR}/reader.sh"
  decider: "${TEST_DIR}/decider.sh"
  dispatcher: "${TEST_DIR}/dispatcher.sh"
  awaiter: "${TEST_DIR}/awaiter.sh"
  logger: "${TEST_DIR}/logger.sh"
EOF
    run cycle_invoke "$SCHEDULE_YAML"
    [ "$status" -eq 2 ]
}

@test "cycle_invoke: nonexistent yaml path → exit 2" {
    load_lib
    run cycle_invoke "/nonexistent/path/schedule.yaml"
    [ "$status" -eq 2 ]
}

# -----------------------------------------------------------------------------
# Schema validation refuses bad payloads
# -----------------------------------------------------------------------------
@test "_l3_validate_payload: rejects missing required field" {
    load_lib
    run _l3_validate_payload "cycle.start" '{"cycle_id":"x"}'
    [ "$status" -ne 0 ]
}

@test "_l3_validate_payload: accepts well-formed cycle.start" {
    load_lib
    local p
    p='{"cycle_id":"abc","schedule_id":"sched1","dispatch_contract_hash":"'"$(printf '%064s' '0' | tr ' ' '0')"'","timeout_seconds":60,"started_at":"2026-05-04T12:00:00.000000Z"}'
    run _l3_validate_payload "cycle.start" "$p"
    [ "$status" -eq 0 ]
}

@test "_l3_validate_payload: rejects bad cycle.phase phase enum" {
    load_lib
    local p='{"cycle_id":"x","schedule_id":"y","phase":"bogus","phase_index":0,"started_at":"2026-05-04T12:00:00.000000Z","completed_at":"2026-05-04T12:00:01.000000Z","duration_seconds":1,"outcome":"success"}'
    run _l3_validate_payload "cycle.phase" "$p"
    [ "$status" -ne 0 ]
}

@test "FR-L3-7: log uses audit envelope schema (chain hash present)" {
    load_lib
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "test-chain"
    run jq -sr '.[0] | .prev_hash' "$LOG_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "GENESIS" ]
    # Subsequent entries have non-GENESIS prev_hash.
    run jq -sr '.[1] | .prev_hash' "$LOG_FILE"
    [[ "$output" =~ ^[0-9a-f]{64}$ ]]
}
