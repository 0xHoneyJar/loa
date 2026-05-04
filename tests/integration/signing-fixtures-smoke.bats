#!/usr/bin/env bats
# =============================================================================
# tests/integration/signing-fixtures-smoke.bats
#
# Smoke-tests for tests/lib/signing-fixtures.sh — confirms the shared helper
# emits a working trust-store + key-pair such that audit_emit can sign and
# audit_verify_chain accepts the result.
# =============================================================================

load_fixtures() {
    # shellcheck source=../lib/signing-fixtures.sh
    source "${BATS_TEST_DIRNAME}/../lib/signing-fixtures.sh"
}

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    AUDIT_ENVELOPE="${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
}

teardown() {
    if declare -f signing_fixtures_teardown >/dev/null 2>&1; then
        signing_fixtures_teardown
    fi
}

@test "fixtures: --strict mode generates keypair + trust-store + exports env" {
    load_fixtures
    signing_fixtures_setup --strict
    [[ -d "$TEST_DIR" ]]
    [[ -d "$KEY_DIR" ]]
    [[ -f "$KEY_DIR/test-writer.priv" ]]
    [[ -f "$KEY_DIR/test-writer.pub" ]]
    [[ -f "$LOA_TRUST_STORE_FILE" ]]
    [[ "$LOA_AUDIT_SIGNING_KEY_ID" = "test-writer" ]]
    [[ "$LOA_AUDIT_VERIFY_SIGS" = "1" ]]
    # priv key mode 0600
    local priv_mode
    priv_mode="$(stat -c '%a' "$KEY_DIR/test-writer.priv" 2>/dev/null || stat -f '%A' "$KEY_DIR/test-writer.priv")"
    [[ "$priv_mode" = "600" || "$priv_mode" = "0600" ]]
}

@test "fixtures: --strict mode trust-store yaml is parseable + has cutoff" {
    load_fixtures
    signing_fixtures_setup --strict
    if command -v yq >/dev/null 2>&1; then
        local cutoff
        cutoff="$(yq -r '.trust_cutoff.default_strict_after' "$LOA_TRUST_STORE_FILE")"
        [[ "$cutoff" = "2020-01-01T00:00:00Z" ]]
        # Trust-store stays BOOTSTRAP-PENDING (empty keys[]); pubkey resolution
        # falls through to KEY_DIR (the documented test path).
        local n_keys
        n_keys="$(yq -r '.keys | length' "$LOA_TRUST_STORE_FILE")"
        [[ "$n_keys" = "0" ]]
    else
        skip "yq not present"
    fi
}

@test "fixtures: --strict mode end-to-end audit_emit + audit_verify_chain happy path" {
    load_fixtures
    signing_fixtures_setup --strict
    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    local log="${TEST_DIR}/sign-smoke.jsonl"
    audit_emit L1 panel.bind '{"decision_id":"smoke-1"}' "$log"
    audit_emit L1 panel.bind '{"decision_id":"smoke-2"}' "$log"
    audit_emit L1 panel.bind '{"decision_id":"smoke-3"}' "$log"
    [[ -f "$log" ]]
    # All 3 envelopes must carry signature + signing_key_id
    local n_signed
    n_signed="$(jq -sr '[.[] | select(.signature != null and .signing_key_id != null)] | length' "$log")"
    [[ "$n_signed" = "3" ]]
    # Chain verifies
    run audit_verify_chain "$log"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK"* ]]
}

@test "fixtures: --bootstrap mode permits unsigned writes" {
    load_fixtures
    signing_fixtures_setup --bootstrap
    [[ -z "${LOA_AUDIT_VERIFY_SIGS:-}" ]]
    if command -v yq >/dev/null 2>&1; then
        local n_keys
        n_keys="$(yq -r '.keys | length' "$LOA_TRUST_STORE_FILE")"
        [[ "$n_keys" = "0" ]]
    fi
}

@test "fixtures: register_extra_key adds a second key + works for second writer" {
    load_fixtures
    signing_fixtures_setup --strict
    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    local log="${TEST_DIR}/multi-writer.jsonl"
    audit_emit L1 panel.bind '{"decision_id":"alice-1"}' "$log"
    # Register and switch to a second key.
    signing_fixtures_register_extra_key "writer-bob" >/dev/null
    LOA_AUDIT_SIGNING_KEY_ID="writer-bob" audit_emit L1 panel.bind '{"decision_id":"bob-1"}' "$log"
    # Both entries verify.
    run audit_verify_chain "$log"
    [[ "$status" -eq 0 ]]
    # Verify the writer_ids differ.
    local n_distinct
    n_distinct="$(jq -sr '[.[] | .signing_key_id] | unique | length' "$log")"
    [[ "$n_distinct" = "2" ]]
}

@test "fixtures: register_extra_key (default) writes KEY_DIR only — trust-store untouched" {
    # Sprint H1 review HIGH-2 fix: default behavior is honest about what it
    # does — only generates keypair files in KEY_DIR. The pubkey resolution
    # fallback in audit-envelope.sh handles multi-writer chains via KEY_DIR.
    load_fixtures
    signing_fixtures_setup --strict
    if command -v yq >/dev/null 2>&1; then
        local pre_count post_count
        pre_count="$(yq -r '.keys | length' "$LOA_TRUST_STORE_FILE")"
        [[ "$pre_count" = "0" ]]
        signing_fixtures_register_extra_key "extra-writer-default" >/dev/null
        post_count="$(yq -r '.keys | length' "$LOA_TRUST_STORE_FILE")"
        # Trust-store keys[] still empty (default mode).
        [[ "$post_count" = "0" ]]
    else
        signing_fixtures_register_extra_key "extra-writer-default" >/dev/null
    fi
    # KEY_DIR file present.
    [[ -f "$KEY_DIR/extra-writer-default.priv" ]]
    [[ -f "$KEY_DIR/extra-writer-default.pub" ]]
}

@test "fixtures: register_extra_key --update-trust-store appends to .keys[] (BOOTSTRAP-PENDING transition)" {
    # Opt-in flag: appends to trust-store keys[]. Trips BOOTSTRAP-PENDING →
    # NEEDS_VERIFY. Without a properly-signed root_signature this makes
    # subsequent audit_emit calls fail with [TRUST-STORE-INVALID] — caller's
    # responsibility to handle. Smoke just verifies the registration write.
    load_fixtures
    signing_fixtures_setup --strict
    if ! command -v yq >/dev/null 2>&1; then skip "yq not present"; fi
    local pre_count post_count
    pre_count="$(yq -r '.keys | length' "$LOA_TRUST_STORE_FILE")"
    [[ "$pre_count" = "0" ]]
    signing_fixtures_register_extra_key "extra-writer-trusted" --update-trust-store >/dev/null
    post_count="$(yq -r '.keys | length' "$LOA_TRUST_STORE_FILE")"
    [[ "$post_count" = "1" ]]
    local writer_id
    writer_id="$(yq -r '.keys[0].writer_id' "$LOA_TRUST_STORE_FILE")"
    [[ "$writer_id" = "extra-writer-trusted" ]]
    local has_pem
    has_pem="$(yq -r '.keys[0].pubkey_pem | test("BEGIN PUBLIC KEY")' "$LOA_TRUST_STORE_FILE")"
    [[ "$has_pem" = "true" ]]
}

@test "fixtures: --update-trust-store cache-invalidation actually flips audit-envelope state" {
    # Sprint H1 review MEDIUM (H1-cache-invalidation-private-state):
    # signing_fixtures_register_extra_key clears the audit-envelope private
    # cache vars by direct assignment. If those vars are ever renamed in
    # audit-envelope.sh, our invalidation silently no-ops. This test catches
    # the drift by ASSERTING the trust-store status genuinely flips from
    # BOOTSTRAP-PENDING to a non-BOOTSTRAP state after --update-trust-store.
    load_fixtures
    signing_fixtures_setup --strict
    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    # Pre-state: BOOTSTRAP-PENDING.
    local pre
    pre="$(_audit_trust_store_status)"
    [[ "$pre" = "BOOTSTRAP-PENDING" ]]
    # Register with trust-store update.
    signing_fixtures_register_extra_key "extra-cache-test" --update-trust-store >/dev/null
    # Post-state: audit-envelope must have observed the change. Either VERIFIED
    # (won't happen — no signed root_sig) or INVALID (expected) — both prove
    # the cache invalidation actually flipped status away from
    # BOOTSTRAP-PENDING. If our private-var clear silently no-ops, this test
    # would still see BOOTSTRAP-PENDING and fail.
    local post
    post="$(_audit_trust_store_status)"
    [[ "$post" != "BOOTSTRAP-PENDING" ]]
}

@test "fixtures: teardown removes TEST_DIR and unsets env" {
    load_fixtures
    signing_fixtures_setup --strict
    local td="$TEST_DIR"
    signing_fixtures_teardown
    # rm -rf cleanup → dir must be gone (was weakened with `|| ls -A` before;
    # that hid teardown gaps per review iter-1 H1-teardown-find-vs-rm).
    [[ ! -d "$td" ]]
    [[ -z "${LOA_AUDIT_KEY_DIR:-}" ]]
    [[ -z "${LOA_AUDIT_SIGNING_KEY_ID:-}" ]]
    [[ -z "${LOA_TRUST_STORE_FILE:-}" ]]
    [[ -z "${LOA_AUDIT_VERIFY_SIGS:-}" ]]
}

@test "fixtures: custom --key-id and --cutoff honored" {
    load_fixtures
    signing_fixtures_setup --strict --key-id "custom-writer" --cutoff "2025-06-15T00:00:00Z"
    [[ "$LOA_AUDIT_SIGNING_KEY_ID" = "custom-writer" ]]
    [[ -f "$KEY_DIR/custom-writer.priv" ]]
    if command -v yq >/dev/null 2>&1; then
        local cutoff
        cutoff="$(yq -r '.trust_cutoff.default_strict_after' "$LOA_TRUST_STORE_FILE")"
        [[ "$cutoff" = "2025-06-15T00:00:00Z" ]]
    fi
}

@test "fixtures: inject_chain_valid_envelope appends entry that audit_verify_chain accepts" {
    # Sprint H2 closure of #708 F-006: chain-valid envelope injection helper.
    # Forensic-failure tests need to write payload-anomalous entries that the
    # chain validates (so detection logic, not chain-hash, must catch them).
    load_fixtures
    signing_fixtures_setup --strict
    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    local log="${TEST_DIR}/anomaly-fixture.jsonl"
    audit_emit L2 budget.record_call '{"actual_usd":1.00,"provider":"anthropic","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"counter_after_usd":1.00,"recorded_at":"2026-05-04T12:00:00.000000Z"}' "$log"
    # Anomaly: actual_usd negative (would never happen via API but is a
    # detection target for L2 counter_inconsistent).
    signing_fixtures_inject_chain_valid_envelope "$log" L2 budget.record_call \
        '{"actual_usd":-50.00,"provider":"anthropic","utc_day":"2026-05-04","cycle_id":null,"model_id":null,"counter_after_usd":-49.00,"recorded_at":"2026-05-04T12:01:00.000000Z"}'
    # Chain validates (this is the property — broken fixtures from prior
    # tests would fail audit_verify_chain BEFORE detection logic ran).
    LOA_AUDIT_VERIFY_SIGS=1 run audit_verify_chain "$log"
    [ "$status" -eq 0 ]
    # Both entries present + signed.
    local n_total n_signed
    n_total="$(jq -sr '. | length' "$log")"
    n_signed="$(jq -sr '[.[] | select(.signature != null)] | length' "$log")"
    [ "$n_total" -eq 2 ]
    [ "$n_signed" -eq 2 ]
    # Anomaly preserved (not normalized away).
    local last_actual
    last_actual="$(jq -sr '.[-1] | .payload.actual_usd' "$log")"
    [ "$last_actual" = "-50" ] || [ "$last_actual" = "-50.00" ]
}

@test "fixtures: chain-repair tamper helper makes signature the SOLE failure mode" {
    # Sprint H1 review HIGH-1: prior payload-tamper tests caught regressions
    # via prev_hash chain-hash, NOT via signature verification — they would
    # pass against a buggy verifier. This smoke test proves the chain-repair
    # helper isolates signature as the gate: VERIFY_SIGS=1 fails, VERIFY_SIGS=0
    # passes.
    load_fixtures
    signing_fixtures_setup --strict
    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    local log="${TEST_DIR}/sig-only.jsonl"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$log"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$log"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$log"

    # Baseline: chain valid in both modes.
    LOA_AUDIT_VERIFY_SIGS=1 run audit_verify_chain "$log"
    [ "$status" -eq 0 ]
    LOA_AUDIT_VERIFY_SIGS=0 run audit_verify_chain "$log"
    [ "$status" -eq 0 ]

    # Tamper line 2 payload + repair chain.
    local tampered="${TEST_DIR}/tampered-chain-repaired.jsonl"
    signing_fixtures_tamper_with_chain_repair \
        "$log" 2 '.payload.decision_id = "tampered-id"' "$tampered"

    # VERIFY_SIGS=0 should PASS (chain hashes were repaired; signature ignored).
    LOA_AUDIT_VERIFY_SIGS=0 run audit_verify_chain "$tampered"
    [ "$status" -eq 0 ]

    # VERIFY_SIGS=1 should FAIL (signature on line 2 mismatches the new payload).
    LOA_AUDIT_VERIFY_SIGS=1 run audit_verify_chain "$tampered"
    [ "$status" -ne 0 ]
}

# NOTE: The "--cutoff in future pins pre-cutoff behavior" test was REMOVED
# in iter-2 review remediation (REFRAME). Reasoning: the test pinned
# audit-envelope.sh behavior (pre-cutoff strip-attack tolerance) that the
# review itself flagged as questionable security policy. Pinning that
# behavior in the FIXTURE-LIB smoke is the wrong owner — if it's worth
# pinning, it belongs in tests/integration/audit-envelope-* where the
# hardening logic lives. The cutoff yaml-field write is already covered by
# smoke #2 ("trust-store yaml is parseable + has cutoff").
