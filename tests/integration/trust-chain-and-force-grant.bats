#!/usr/bin/env bats
# =============================================================================
# tests/integration/trust-chain-and-force-grant.bats
#
# cycle-098 Sprint 4C — chain integrity (FR-L4-5), reconstruction (FR-L4-7),
# force-grant exception (FR-L4-8), auto-raise stub (FR-L4-4).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/graduated-trust-lib.sh"
    [[ -f "$LIB" ]] || skip "graduated-trust-lib.sh not present"

    TEST_DIR="$(mktemp -d)"
    TEST_TRUST_STORE="$TEST_DIR/trust-store.yaml"
    cat > "$TEST_TRUST_STORE" <<'EOF'
schema_version: "1.0"
root_signature: { algorithm: ed25519, signer_pubkey: "", signed_at: "", signature: "" }
keys: []
revocations: []
trust_cutoff: { default_strict_after: "2099-01-01T00:00:00Z" }
EOF
    export LOA_TRUST_STORE_FILE="$TEST_TRUST_STORE"

    export LOA_TRUST_CONFIG_FILE="$TEST_DIR/.loa.config.yaml"
    export LOA_TRUST_LEDGER_FILE="$TEST_DIR/trust-ledger.jsonl"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: true
  default_tier: T0
  tier_definitions:
    T0: { description: "no" }
    T1: { description: "ro" }
    T2: { description: "routine" }
    T3: { description: "full" }
  transition_rules:
    - { from: T0, to: T1, requires: operator_grant, id: T0_to_T1 }
    - { from: T1, to: T2, requires: operator_grant, id: T1_to_T2 }
    - { from: T2, to: T3, requires: operator_grant, id: T2_to_T3 }
    - { from: T2, to: T1, via: auto_drop_on_override }
  cooldown_seconds: 604800
EOF
    unset LOA_TRUST_DEFAULT_TIER LOA_TRUST_COOLDOWN_SECONDS
    unset LOA_TRUST_REQUIRE_KNOWN_ACTOR LOA_TRUST_EMIT_QUERY_EVENTS
    unset LOA_TRUST_TEST_NOW
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE LOA_TRUST_CONFIG_FILE LOA_TRUST_LEDGER_FILE
    unset LOA_TRUST_DEFAULT_TIER LOA_TRUST_COOLDOWN_SECONDS
    unset LOA_TRUST_REQUIRE_KNOWN_ACTOR LOA_TRUST_EMIT_QUERY_EVENTS
    unset LOA_TRUST_TEST_NOW
}

# =============================================================================
# FR-L4-5: trust_verify_chain
# =============================================================================

@test "FR-L4-5: empty/missing ledger -> trust_verify_chain exit 2" {
    source "$LIB"
    rm -f "$LOA_TRUST_LEDGER_FILE"
    run trust_verify_chain
    [[ "$status" -eq 2 ]]
}

@test "FR-L4-5: clean grant chain validates" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    run trust_verify_chain
    [[ "$status" -eq 0 ]]
}

@test "FR-L4-5: tampering DETECTABLE — flipping a payload byte breaks verification" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    # Tamper: rewrite the first entry's reason field.
    python3 - "$LOA_TRUST_LEDGER_FILE" <<'PY'
import json, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
obj = json.loads(lines[0])
obj["payload"]["reason"] = "tampered"
lines[0] = json.dumps(obj, separators=(",", ":"))
open(path, "w").write("\n".join(lines) + "\n")
PY
    run trust_verify_chain
    [[ "$status" -ne 0 ]]
}

@test "FR-L4-5: tampering DETECTABLE — flipping a prev_hash byte breaks the chain" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    python3 - "$LOA_TRUST_LEDGER_FILE" <<'PY'
import json, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
obj = json.loads(lines[1])
ph = obj["prev_hash"]
# Flip first hex character.
flipped = ("0" if ph[0] != "0" else "1") + ph[1:]
obj["prev_hash"] = flipped
lines[1] = json.dumps(obj, separators=(",", ":"))
open(path, "w").write("\n".join(lines) + "\n")
PY
    run trust_verify_chain
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# FR-L4-7: trust_recover_chain (TRACKED log path)
# =============================================================================

@test "FR-L4-7: recovery on already-valid chain is a no-op (exit 0)" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    run trust_recover_chain
    [[ "$status" -eq 0 ]]
}

@test "FR-L4-7: recovery from git history rebuilds tampered log (TRACKED-path)" {
    source "$LIB"
    # Create an isolated git repo to simulate the TRACKED log path.
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@test"
    git config user.name "test"
    mkdir -p subrepo/.run
    cd subrepo
    git init -q
    git config user.email "test@test"
    git config user.name "test"
    export LOA_TRUST_LEDGER_FILE="$TEST_DIR/subrepo/.run/trust-ledger.jsonl"
    cp "$LOA_TRUST_CONFIG_FILE" "$TEST_DIR/subrepo/.loa.config.yaml"
    export LOA_TRUST_CONFIG_FILE="$TEST_DIR/subrepo/.loa.config.yaml"

    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    git add .run/trust-ledger.jsonl .loa.config.yaml
    git commit -q -m "initial trust-ledger"

    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    git add .run/trust-ledger.jsonl
    git commit -q -m "T2 grant"

    # Tamper the local file.
    python3 - "$LOA_TRUST_LEDGER_FILE" <<'PY'
import json, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
obj = json.loads(lines[0])
obj["payload"]["reason"] = "tampered"
lines[0] = json.dumps(obj, separators=(",", ":"))
open(path, "w").write("\n".join(lines) + "\n")
PY

    run trust_verify_chain
    [[ "$status" -ne 0 ]]

    run trust_recover_chain
    [[ "$status" -eq 0 ]] || {
        echo "$output"
        cat "$LOA_TRUST_LEDGER_FILE" >&3 2>/dev/null || true
        return 1
    }

    run trust_verify_chain
    [[ "$status" -eq 0 ]]

    # BB iter-1 F6 (confidence 0.85): verify recovery actually pulled the
    # original committed content from git — not just re-hashed the tampered
    # local file in place. The original entry's reason was "s1"; tamper made
    # it "tampered". Post-recovery, "s1" must be restored.
    grep -F '"reason":"s1"' "$LOA_TRUST_LEDGER_FILE"
    if grep -F '"reason":"tampered"' "$LOA_TRUST_LEDGER_FILE" 2>/dev/null; then
        echo "recovery left tampered content in place"
        return 1
    fi
}

# =============================================================================
# FR-L4-8: trust_grant --force (force-grant exception)
# =============================================================================

@test "FR-L4-8: --force succeeds during cooldown; emits trust.force_grant" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    LOA_TRUST_TEST_NOW="2026-05-01T00:00:00.000Z" \
        trust_record_override "f" "m" "deep-name" "d-1" "override"
    # Mid-cooldown: 2026-05-04 is well before 2026-05-08 (auto_drop + 7d).
    LOA_TRUST_TEST_NOW="2026-05-04T00:00:00.000Z" \
        run trust_grant "f" "m" "deep-name" "T2" --reason "emergency rerise" --operator "operator-2" --force
    [[ "$status" -eq 0 ]] || {
        echo "$output"
        return 1
    }

    grep -F '"event_type":"trust.force_grant"' "$LOA_TRUST_LEDGER_FILE"

    # tier should now be T2 (force_grant cleared cooldown)
    LOA_TRUST_TEST_NOW="2026-05-04T00:00:00.000Z" run trust_query "f" "m" "deep-name"
    echo "$output" | jq -e '.tier == "T2"' >/dev/null
    echo "$output" | jq -e '.in_cooldown_until == null' >/dev/null
}

@test "FR-L4-8: cooldown_remaining_seconds_at_grant accurately recorded" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    LOA_TRUST_TEST_NOW="2026-05-01T00:00:00.000Z" \
        trust_record_override "f" "m" "deep-name" "d-1" "override"
    # cooldown_until = 2026-05-08T00:00:00Z. now = 2026-05-04T00:00:00Z.
    # remaining = 4 days = 345600 seconds.
    LOA_TRUST_TEST_NOW="2026-05-04T00:00:00.000Z" \
        trust_grant "f" "m" "deep-name" "T2" --reason "emergency" --operator "operator-2" --force

    local entry
    entry="$(grep -F '"event_type":"trust.force_grant"' "$LOA_TRUST_LEDGER_FILE" | head -n 1)"
    echo "$entry" | jq -e '.payload.cooldown_remaining_seconds_at_grant == 345600' >/dev/null
    echo "$entry" | jq -e '.payload.cooldown_until_at_grant == "2026-05-08T00:00:00.000Z"' >/dev/null
    echo "$entry" | jq -e '.payload.reason == "emergency"' >/dev/null
}

@test "FR-L4-8: --force without active cooldown still emits trust.force_grant (with remaining=0)" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    # Force-grant from T1 to T2, no cooldown active.
    run trust_grant "f" "m" "deep-name" "T2" --reason "redundant force" --operator "operator-2" --force
    [[ "$status" -eq 0 ]]
    local entry
    entry="$(grep -F '"event_type":"trust.force_grant"' "$LOA_TRUST_LEDGER_FILE" | head -n 1)"
    echo "$entry" | jq -e '.payload.cooldown_remaining_seconds_at_grant == 0' >/dev/null
    echo "$entry" | jq -e '.payload.cooldown_until_at_grant == null' >/dev/null
}

@test "FR-L4-8: --force missing --reason -> exit 2" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    run trust_grant "f" "m" "deep-name" "T2" --operator "deep-name" --force
    [[ "$status" -eq 2 ]]
}

@test "FR-L4-8: --force on sealed ledger rejected (exit 3)" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.disable","ts_utc":"2026-05-02T00:00:00.000Z","prev_hash":"GENESIS","payload":{"operator":"o","reason":"sealed","sealed_at":"2026-05-02T00:00:00.000Z"}}
EOF
    run trust_grant "f" "m" "deep-name" "T1" --reason "r" --operator "operator-2" --force
    [[ "$status" -eq 3 ]]
}

@test "FR-L4-8: trust.force_grant is registered in protected-classes taxonomy" {
    source "$LIB"
    is_protected_class "trust.force_grant"
}

# =============================================================================
# FR-L4-4: auto-raise stub
# =============================================================================

@test "FR-L4-4: trust_auto_raise_check returns eligibility_required (FU-3 deferral)" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    run trust_auto_raise_check "f" "m" "deep-name" "T2"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.stub_outcome == "eligibility_required"' >/dev/null
    echo "$output" | jq -e '.current_tier == "T1"' >/dev/null
    echo "$output" | jq -e '.next_tier == "T2"' >/dev/null
}

@test "FR-L4-4: trust_auto_raise_check emits trust.auto_raise_eligible audit event" {
    source "$LIB"
    trust_auto_raise_check "f" "m" "deep-name" "T1"
    grep -F '"event_type":"trust.auto_raise_eligible"' "$LOA_TRUST_LEDGER_FILE"
    local entry
    entry="$(grep -F '"event_type":"trust.auto_raise_eligible"' "$LOA_TRUST_LEDGER_FILE" | head -n 1)"
    echo "$entry" | jq -e '.payload.stub_outcome == "eligibility_required"' >/dev/null
}

@test "FR-L4-4: missing argument rejected with exit 2" {
    source "$LIB"
    run trust_auto_raise_check "f" "m" "deep-name"
    [[ "$status" -eq 2 ]]
}

@test "FR-L4-4: invalid tier rejected with exit 2" {
    source "$LIB"
    run trust_auto_raise_check "f" "m" "deep-name" 'T1; rm -rf /'
    [[ "$status" -eq 2 ]]
}

@test "FR-L4-4: auto_raise_eligible does NOT silently raise the tier (informational only)" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "step1" --operator "deep-name"
    # Consult eligibility for T2 — must NOT ratchet tier from T1 to T2.
    trust_auto_raise_check "f" "m" "deep-name" "T2"
    run trust_query "f" "m" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
    # The auto_raise_eligible entry IS in the transition_history (audit trail)
    # but did not affect the resolved tier.
    echo "$output" | jq -e '[.transition_history[] | select(.transition_type == "auto_raise_eligible")] | length == 1' >/dev/null
}
