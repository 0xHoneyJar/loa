#!/usr/bin/env bats
# =============================================================================
# tests/integration/cost-budget-enforcer-signed-mode.bats
#
# cycle-098 Sprint H1 (closes #706). End-to-end happy path for L2 with
# Ed25519 signing enabled. The Sprint 2 unit + state-machine test suites all
# run with LOA_AUDIT_VERIFY_SIGS=0 for envelope-construction determinism;
# this file exercises the signed code path so a regression that drops
# LOA_AUDIT_SIGNING_KEY_ID propagation through the L2 lib ships red.
#
# Coverage:
#   - budget_verdict writes a SIGNED envelope (signature + signing_key_id)
#   - budget_record_call writes a SIGNED envelope
#   - budget_reconcile writes a SIGNED envelope
#   - audit_verify_chain validates the full multi-event chain
#   - Tampering one entry's signature → audit_verify_chain fails
# =============================================================================

load_fixtures() {
    # shellcheck source=../lib/signing-fixtures.sh
    source "${BATS_TEST_DIRNAME}/../lib/signing-fixtures.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    L2_LIB="${REPO_ROOT}/.claude/scripts/lib/cost-budget-enforcer-lib.sh"
    AUDIT_ENVELOPE="${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    [[ -f "$L2_LIB" ]] || skip "cost-budget-enforcer-lib.sh not present"
    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    load_fixtures
    signing_fixtures_setup --strict --key-id "test-budget-writer"

    BUDGET_LOG="${TEST_DIR}/cost-budget-events.jsonl"
    OBSERVER="${TEST_DIR}/observer.sh"
    OBSERVER_OUT="${TEST_DIR}/observer-out.json"

    cat > "$OBSERVER" <<'EOF'
#!/usr/bin/env bash
out="${OBSERVER_OUT:-}"
[[ -n "$out" && -f "$out" ]] && cat "$out" || echo '{"_unreachable":true}'
EOF
    chmod +x "$OBSERVER"
    echo '{"usd_used": 5.00, "billing_ts": "2026-05-04T15:00:00.000000Z"}' > "$OBSERVER_OUT"

    export LOA_BUDGET_LOG="$BUDGET_LOG"
    export LOA_BUDGET_OBSERVER_CMD="$OBSERVER"
    export OBSERVER_OUT
    export LOA_BUDGET_DAILY_CAP_USD="50.00"
    export LOA_BUDGET_FRESHNESS_SECONDS="300"
    export LOA_BUDGET_STALE_HALT_PCT="75"
    export LOA_BUDGET_CLOCK_TOLERANCE="60"
    export LOA_BUDGET_LAG_HALT_SECONDS="300"
    # Disable drift BLOCKER for these tests. Reason: the legitimate per-
    # provider drift between observer ($5.00 aggregate) and post-record_call
    # counter (per-provider, partial) would otherwise fire as a BLOCKER and
    # halt budget_reconcile before the test can verify the SIGNED envelope
    # was emitted. The reconciliation state machine itself is exhaustively
    # covered by tests/unit/cost-budget-enforcer-state-machine.bats in
    # unsigned mode. Setting effectively-infinite (999999%) makes the intent
    # unambiguous to future maintainers (vs the prior magic "1000").
    # If LOA_BUDGET_DRIFT_THRESHOLD is removed, expect budget_reconcile to
    # exit non-zero with a "drift_pct >>> threshold" BLOCKER.
    export LOA_BUDGET_DRIFT_THRESHOLD="999999"
    export LOA_BUDGET_TEST_NOW="2026-05-04T15:00:00.000000Z"

    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    # shellcheck source=/dev/null
    source "$L2_LIB"
}

teardown() {
    if declare -f signing_fixtures_teardown >/dev/null 2>&1; then
        signing_fixtures_teardown
    fi
    unset LOA_BUDGET_LOG LOA_BUDGET_OBSERVER_CMD LOA_BUDGET_DAILY_CAP_USD \
          LOA_BUDGET_FRESHNESS_SECONDS LOA_BUDGET_STALE_HALT_PCT \
          LOA_BUDGET_CLOCK_TOLERANCE LOA_BUDGET_LAG_HALT_SECONDS \
          LOA_BUDGET_TEST_NOW OBSERVER_OUT
}

# -----------------------------------------------------------------------------
# Sign-on-emit
# -----------------------------------------------------------------------------

@test "L2 signed-mode: budget_verdict emits SIGNED envelope" {
    run budget_verdict "1.50"
    [ "$status" -eq 0 ]
    [ -f "$BUDGET_LOG" ]
    run jq -sr '.[] | select(.event_type == "budget.allow") | .signature' "$BUDGET_LOG"
    [ -n "$output" ]
    [ "$output" != "null" ]
    [[ "$output" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]
    run jq -sr '.[] | select(.event_type == "budget.allow") | .signing_key_id' "$BUDGET_LOG"
    [ "$output" = "test-budget-writer" ]
}

@test "L2 signed-mode: budget_record_call emits SIGNED envelope" {
    run budget_record_call "0.75" --provider "anthropic"
    [ "$status" -eq 0 ]
    run jq -sr '.[] | select(.event_type == "budget.record_call") | .signature' "$BUDGET_LOG"
    [ -n "$output" ]
    [ "$output" != "null" ]
    run jq -sr '.[] | select(.event_type == "budget.record_call") | .signing_key_id' "$BUDGET_LOG"
    [ "$output" = "test-budget-writer" ]
}

@test "L2 signed-mode: budget_reconcile emits SIGNED envelope" {
    # Need at least one record_call so reconcile has counter state.
    budget_record_call "5.00" --provider "anthropic"
    run budget_reconcile --provider "anthropic"
    [ "$status" -eq 0 ]
    run jq -sr '.[] | select(.event_type == "budget.reconcile") | .signature' "$BUDGET_LOG"
    [ -n "$output" ]
    [ "$output" != "null" ]
    run jq -sr '.[] | select(.event_type == "budget.reconcile") | .signing_key_id' "$BUDGET_LOG"
    [ "$output" = "test-budget-writer" ]
}

# -----------------------------------------------------------------------------
# Multi-event chain validates
# -----------------------------------------------------------------------------

@test "L2 signed-mode: audit_verify_chain validates verdict + record_call + reconcile chain" {
    budget_verdict "2.50"
    budget_record_call "2.50" --provider "anthropic"
    budget_verdict "1.00"
    budget_record_call "1.00" --provider "openai"
    budget_reconcile --provider "anthropic"
    run audit_verify_chain "$BUDGET_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "L2 signed-mode: every L2 entry on chain carries signature + signing_key_id" {
    budget_verdict "1.00"
    budget_record_call "1.00"
    budget_reconcile
    local n_total n_signed
    n_total="$(jq -sr '[.[] | select(.primitive_id == "L2")] | length' "$BUDGET_LOG")"
    n_signed="$(jq -sr '[.[] | select(.primitive_id == "L2") | select(.signature != null and .signing_key_id != null)] | length' "$BUDGET_LOG")"
    [ "$n_total" -eq "$n_signed" ]
    [ "$n_signed" -ge 3 ]
}

# -----------------------------------------------------------------------------
# Tamper detection
# -----------------------------------------------------------------------------

@test "L2 signed-mode: stripping signature from one entry → chain verification FAILS" {
    budget_verdict "1.00"
    budget_record_call "1.00"
    budget_verdict "0.50"
    # Strip signature from line 2 only.
    local stripped tmp
    tmp="${TEST_DIR}/tampered.jsonl"
    {
        sed -n '1p' "$BUDGET_LOG"
        sed -n '2p' "$BUDGET_LOG" | jq -c 'del(.signature)'
        sed -n '3p' "$BUDGET_LOG"
    } > "$tmp"
    run audit_verify_chain "$tmp"
    [ "$status" -ne 0 ]
}

@test "L2 signed-mode: payload tamper detected by SIGNATURE (chain-repaired test isolates the gate)" {
    # Sprint H1 review HIGH-1: prior payload-tamper tests caught regressions
    # via prev_hash chain-hash, NOT signature verification — they would pass
    # against a buggy verifier that always returns 0. The chain-repair helper
    # repairs prev_hashes after tampering so the chain-hash check passes;
    # signature mismatch becomes the SOLE failure mode.
    budget_verdict "1.00"
    budget_record_call "1.00"
    budget_verdict "0.50"
    local tmp="${TEST_DIR}/payload-chain-repaired.jsonl"
    signing_fixtures_tamper_with_chain_repair \
        "$BUDGET_LOG" 2 '.payload.actual_usd = 999999' "$tmp"
    # VERIFY_SIGS=0: chain hashes were repaired → verify SUCCEEDS (proves the
    # chain-hash check is satisfied; signature is now the only gate).
    LOA_AUDIT_VERIFY_SIGS=0 run audit_verify_chain "$tmp"
    [ "$status" -eq 0 ]
    # VERIFY_SIGS=1: signature on line 2 mismatches the new payload → FAILS.
    LOA_AUDIT_VERIFY_SIGS=1 run audit_verify_chain "$tmp"
    [ "$status" -ne 0 ]
}
