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

@test "fixtures: teardown removes TEST_DIR and unsets env" {
    load_fixtures
    signing_fixtures_setup --strict
    local td="$TEST_DIR"
    signing_fixtures_teardown
    [[ ! -d "$td" ]] || [[ -z "$(ls -A "$td" 2>/dev/null)" ]]
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

@test "fixtures: --cutoff in future suppresses post-cutoff strip-attack gate" {
    # Sprint H1 review MEDIUM (smoke #7 expansion): observed effect of cutoff.
    # With cutoff in 2099, an unsigned entry written after VERIFY_SIGS=1 set
    # is still pre-cutoff (any real-world ts_utc < 2099) — strip-attack gate
    # does NOT fire. Confirms the cutoff plumbing actually wires through.
    load_fixtures
    signing_fixtures_setup --strict --cutoff "2099-01-01T00:00:00Z"
    # shellcheck source=/dev/null
    source "$AUDIT_ENVELOPE"
    local log="${TEST_DIR}/precutoff.jsonl"
    audit_emit L1 panel.bind '{"decision_id":"d-pre"}' "$log"
    # Strip the signature to simulate the strip attack.
    local stripped="${TEST_DIR}/stripped.jsonl"
    jq -c 'del(.signature, .signing_key_id)' "$log" > "$stripped"
    # With cutoff in future, the strip-attack gate is dormant — chain validates.
    LOA_AUDIT_VERIFY_SIGS=1 run audit_verify_chain "$stripped"
    [ "$status" -eq 0 ]
}
