#!/usr/bin/env bats
# =============================================================================
# tests/integration/scheduled-cycle-lib-signed-mode.bats
#
# cycle-098 Sprint H1 (closes #713). End-to-end happy path for L3 with
# Ed25519 signing enabled. Sprint 3 BATS suites all run with
# LOA_AUDIT_VERIFY_SIGS=0 + unset LOA_AUDIT_SIGNING_KEY_ID; this file
# exercises the signed code path so a regression that drops signing
# propagation through cycle_invoke ships red.
#
# Coverage:
#   - cycle.start signed
#   - cycle.phase × 5 all signed
#   - cycle.complete signed
#   - audit_verify_chain validates the full multi-event chain
#   - Tampered chain fails verification
#   - cycle.error path also signs
# =============================================================================

load_fixtures() {
    # shellcheck source=../lib/signing-fixtures.sh
    source "${BATS_TEST_DIRNAME}/../lib/signing-fixtures.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    L3_LIB="${REPO_ROOT}/.claude/scripts/lib/scheduled-cycle-lib.sh"
    AUDIT_ENVELOPE="${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    [[ -f "$L3_LIB" ]] || skip "scheduled-cycle-lib.sh not present"
    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    load_fixtures
    signing_fixtures_setup --strict --key-id "test-cycle-writer"

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
schedule_id: test-h1-signed
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

    export LOA_CYCLES_LOG="$LOG_FILE"
    export LOA_L3_LOCK_DIR="$LOCK_DIR"
    export LOA_L3_LOCK_TIMEOUT_SECONDS=2
    export LOA_L3_PHASE_PATH_ALLOWED_PREFIXES="$TEST_DIR"
    export LOA_L3_TEST_NOW="2026-05-04T15:00:00.000000Z"

    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    # shellcheck source=/dev/null
    source "$L3_LIB"
}

teardown() {
    if declare -f signing_fixtures_teardown >/dev/null 2>&1; then
        signing_fixtures_teardown
    fi
    unset LOA_CYCLES_LOG LOA_L3_LOCK_DIR LOA_L3_LOCK_TIMEOUT_SECONDS \
          LOA_L3_PHASE_PATH_ALLOWED_PREFIXES LOA_L3_TEST_NOW
}

# -----------------------------------------------------------------------------
# All cycle events sign
# -----------------------------------------------------------------------------

@test "L3 signed-mode: cycle_invoke emits 7 signed envelopes (start + 5 phase + complete)" {
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-signed-1"
    [ "$status" -eq 0 ]
    [ -f "$LOG_FILE" ]
    local n_total n_signed
    n_total="$(jq -sr '. | length' "$LOG_FILE")"
    n_signed="$(jq -sr '[.[] | select(.signature != null and .signing_key_id != null)] | length' "$LOG_FILE")"
    [ "$n_total" -eq 7 ]
    [ "$n_signed" -eq 7 ]
}

@test "L3 signed-mode: each event_type carries the test signing_key_id" {
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-signed-2"
    local distinct
    distinct="$(jq -sr '[.[] | .signing_key_id] | unique | join(",")' "$LOG_FILE")"
    [ "$distinct" = "test-cycle-writer" ]
}

@test "L3 signed-mode: signatures are base64-formatted" {
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-signed-3"
    while IFS= read -r sig; do
        [[ "$sig" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]
    done < <(jq -sr '.[] | .signature' "$LOG_FILE")
}

# -----------------------------------------------------------------------------
# Chain validates
# -----------------------------------------------------------------------------

@test "L3 signed-mode: audit_verify_chain validates the full cycle chain" {
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-signed-4"
    run audit_verify_chain "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "L3 signed-mode: chain still validates across multiple cycles" {
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-multi-1"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-multi-2"
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-multi-3"
    run audit_verify_chain "$LOG_FILE"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Tamper detection
# -----------------------------------------------------------------------------

@test "L3 signed-mode: stripping signature from cycle.complete → chain FAILS" {
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-strip-1"
    # Strip signature from the final cycle.complete line (line 7).
    local tmp
    tmp="${TEST_DIR}/strip-tampered.jsonl"
    {
        sed -n '1,6p' "$LOG_FILE"
        sed -n '7p' "$LOG_FILE" | jq -c 'del(.signature)'
    } > "$tmp"
    run audit_verify_chain "$tmp"
    [ "$status" -ne 0 ]
}

@test "L3 signed-mode: cycle.phase payload tamper detected by SIGNATURE (chain-repaired)" {
    # Sprint H1 review HIGH-1: chain-repair isolates signature as the gate.
    cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-payload-tamper"
    local tmp="${TEST_DIR}/payload-chain-repaired.jsonl"
    # Line 3 is cycle.phase (decider) per the cycle_invoke event ordering.
    signing_fixtures_tamper_with_chain_repair \
        "$LOG_FILE" 3 '.payload.duration_seconds = 9999' "$tmp"
    LOA_AUDIT_VERIFY_SIGS=0 run audit_verify_chain "$tmp"
    [ "$status" -eq 0 ]
    LOA_AUDIT_VERIFY_SIGS=1 run audit_verify_chain "$tmp"
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Error-path also signs
# -----------------------------------------------------------------------------

@test "L3 signed-mode: cycle.error event is also signed" {
    cat > "${TEST_DIR}/dispatcher.sh" <<'EOF'
#!/usr/bin/env bash
exit 13
EOF
    chmod +x "${TEST_DIR}/dispatcher.sh"
    run cycle_invoke "$SCHEDULE_YAML" --cycle-id "h1-signed-error"
    [ "$status" -eq 1 ]
    run jq -sr '.[] | select(.event_type == "cycle.error") | .signature' "$LOG_FILE"
    [ -n "$output" ]
    [ "$output" != "null" ]
    run audit_verify_chain "$LOG_FILE"
    [ "$status" -eq 0 ]
}
