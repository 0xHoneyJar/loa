#!/usr/bin/env bats
# =============================================================================
# tests/integration/trust-cypherpunk-remediation.bats
#
# cycle-098 Sprint 4 — remediation tests for the cypherpunk audit findings
# (CRIT-1, CRIT-2, HIGH-1, HIGH-2, HIGH-3, HIGH-4, HIGH-6, MED-2, MED-3, MED-4).
#
# Each test exercises the attack the original review described and verifies
# the patched lib refuses the attack (or honors the documented contract).
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
    - { from: T3, to: T1, via: auto_drop_on_override }
    - { from: T1, to: T0, via: auto_drop_on_override }
  cooldown_seconds: 604800
EOF
    unset LOA_TRUST_DEFAULT_TIER LOA_TRUST_COOLDOWN_SECONDS
    unset LOA_TRUST_REQUIRE_KNOWN_ACTOR LOA_TRUST_EMIT_QUERY_EVENTS
    unset LOA_TRUST_TEST_NOW LOA_TRUST_TEST_MODE
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE LOA_TRUST_CONFIG_FILE LOA_TRUST_LEDGER_FILE
    unset LOA_TRUST_DEFAULT_TIER LOA_TRUST_COOLDOWN_SECONDS
    unset LOA_TRUST_REQUIRE_KNOWN_ACTOR LOA_TRUST_EMIT_QUERY_EVENTS
    unset LOA_TRUST_TEST_NOW LOA_TRUST_TEST_MODE
}

# =============================================================================
# CRIT-1: seal bypass via terminal [CHAIN-BROKEN] marker
# =============================================================================

@test "CRIT-1: sealed ledger followed by [CHAIN-BROKEN] marker is correctly detected as sealed" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.disable","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"operator":"o","reason":"sealed","sealed_at":"2026-05-01T00:00:00.000Z"}}
[CHAIN-BROKEN at=2026-05-02T00:00:00.000Z primitive=L4]
EOF
    # Pre-fix: tail|jq saw a marker line, returned "" event_type, sealed=false
    # Post-fix: scan all non-marker lines for trust.disable, sealed=true
    if ! _l4_ledger_is_sealed "$LOA_TRUST_LEDGER_FILE"; then
        echo "FAIL: marker after seal hid the seal"
        return 1
    fi
    # Subsequent grants must reject (exit 3).
    run trust_grant "f" "m" "deep-name" "T1" --reason "post-seal" --operator "deep-name"
    [[ "$status" -eq 3 ]]
}

@test "CRIT-1: sealed ledger followed by [CHAIN-RECOVERED ...] marker is sealed" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.disable","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"operator":"o","reason":"sealed","sealed_at":"2026-05-01T00:00:00.000Z"}}
[CHAIN-GAP-RECOVERED-FROM-GIT commit=abc123]
[CHAIN-RECOVERED source=git_history commit=abc123]
EOF
    _l4_ledger_is_sealed "$LOA_TRUST_LEDGER_FILE"
    run trust_record_override "f" "m" "deep-name" "decision-x" "post-seal override"
    [[ "$status" -eq 3 ]]
}

# =============================================================================
# CRIT-2: cooldown_until forgery — clamp to [ts_utc, ts_utc + max_cooldown_seconds]
# =============================================================================

@test "CRIT-2: forged cooldown_until far-future is clamped to ts_utc + max_cooldown_seconds" {
    source "$LIB"
    # Inject an auto_drop entry with cooldown_until = year 9999 (DoS attempt).
    # max_cooldown_seconds=7776000 (90d). ts_utc=2026-05-01 -> clamp to 2026-07-30.
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-04-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"f","capability":"m","actor":"deep-name","from_tier":null,"to_tier":"T2","operator":"deep-name","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.auto_drop","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"x","payload":{"scope":"f","capability":"m","actor":"deep-name","from_tier":"T2","to_tier":"T1","decision_id":"d-1","reason":"override","cooldown_until":"9999-12-31T23:59:59.000Z","cooldown_seconds":604800}}
EOF
    LOA_TRUST_TEST_MODE=1 LOA_TRUST_TEST_NOW="2026-06-01T00:00:00.000Z" \
        run trust_query "f" "m" "deep-name"
    [[ "$status" -eq 0 ]]
    # in_cooldown_until is clamped to 2026-07-30 (90d from auto_drop ts_utc).
    local until
    until="$(echo "$output" | jq -r '.in_cooldown_until')"
    [[ "$until" == "2026-07-30T00:00:00.000Z" ]] || {
        echo "expected clamp to 2026-07-30, got: $until"
        return 1
    }
}

@test "CRIT-2: forged cooldown_until in the past (epoch) is clamped to ts_utc (cannot pre-expire)" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-04-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"f","capability":"m","actor":"deep-name","from_tier":null,"to_tier":"T2","operator":"deep-name","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.auto_drop","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"x","payload":{"scope":"f","capability":"m","actor":"deep-name","from_tier":"T2","to_tier":"T1","decision_id":"d-1","reason":"override","cooldown_until":"1970-01-01T00:00:00.000Z","cooldown_seconds":604800}}
EOF
    # Now=2026-05-02 — clamped cooldown ends at ts_utc=2026-05-01, so already
    # expired; in_cooldown_until is null (cooldown over). Attacker DID NOT
    # nullify cooldown beyond what they could already do (the actual cooldown
    # starts at the auto_drop ts_utc and lasts at least 0 seconds — clamp to
    # ts_utc means "cooldown was zero seconds" which is the safest the lib
    # can guarantee for a forged past timestamp).
    LOA_TRUST_TEST_MODE=1 LOA_TRUST_TEST_NOW="2026-05-02T00:00:00.000Z" \
        run trust_query "f" "m" "deep-name"
    [[ "$status" -eq 0 ]]
    # in_cooldown_until is null because clamped value (2026-05-01) < now.
    echo "$output" | jq -e '.in_cooldown_until == null' >/dev/null
}

@test "CRIT-2: legitimate cooldown_until (within max ceiling) is honored" {
    source "$LIB"
    LOA_TRUST_TEST_MODE=1 LOA_TRUST_TEST_NOW="2026-05-01T00:00:00.000Z" \
        trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    LOA_TRUST_TEST_MODE=1 LOA_TRUST_TEST_NOW="2026-05-01T00:00:00.000Z" \
        trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    LOA_TRUST_TEST_MODE=1 LOA_TRUST_TEST_NOW="2026-05-01T00:00:00.000Z" \
        trust_record_override "f" "m" "deep-name" "d-1" "override"
    # cooldown=604800s=7d, ts=2026-05-01, until=2026-05-08 -> within 90d cap, honored.
    LOA_TRUST_TEST_MODE=1 LOA_TRUST_TEST_NOW="2026-05-04T00:00:00.000Z" \
        run trust_query "f" "m" "deep-name"
    local until
    until="$(echo "$output" | jq -r '.in_cooldown_until')"
    [[ "$until" == "2026-05-08T00:00:00.000Z" ]]
}

# =============================================================================
# HIGH-1: walk_ledger filters marker lines + bubbles parse errors
# =============================================================================

@test "HIGH-1: trust_query handles ledger with [CHAIN-BROKEN] markers gracefully" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"f","capability":"m","actor":"deep-name","from_tier":null,"to_tier":"T1","operator":"deep-name","reason":"r"}}
[CHAIN-BROKEN at=2026-05-02T00:00:00.000Z primitive=L4]
EOF
    run trust_query "f" "m" "deep-name"
    [[ "$status" -eq 0 ]]
    # Tier should be T1 from the valid entry; markers are filtered.
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
    echo "$output" | jq -e '.transition_history | length == 1' >/dev/null
}

# =============================================================================
# HIGH-2: chain-integrity required for writes
# =============================================================================

@test "HIGH-2: trust_grant refuses to append on broken chain (multi-entry tamper)" {
    source "$LIB"
    # Single-entry tamper isn't detectable by chain-walk (entry 0's prev_hash
    # is always GENESIS); need at least 2 entries so the prev_hash linkage
    # exists and breaks under tamper.
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    python3 - "$LOA_TRUST_LEDGER_FILE" <<'PY'
import json, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
obj = json.loads(lines[0])
obj["payload"]["reason"] = "tampered"
lines[0] = json.dumps(obj, separators=(",", ":"))
open(path, "w").write("\n".join(lines) + "\n")
PY
    run trust_grant "f" "m" "deep-name" "T3" --reason "should-refuse" --operator "deep-name"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"chain integrity broken"* ]] || [[ "$output" == *"trust_recover_chain"* ]]
}

@test "HIGH-2: trust_record_override refuses to append on broken chain" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    python3 - "$LOA_TRUST_LEDGER_FILE" <<'PY'
import json, sys
path = sys.argv[1]
lines = open(path).read().splitlines()
obj = json.loads(lines[0])
obj["payload"]["reason"] = "tampered"
lines[0] = json.dumps(obj, separators=(",", ":"))
open(path, "w").write("\n".join(lines) + "\n")
PY
    run trust_record_override "f" "m" "deep-name" "d-1" "should-refuse"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# HIGH-3: _l4_enabled gates writes
# =============================================================================

@test "HIGH-3: trust_grant refuses to write when graduated_trust.enabled=false" {
    source "$LIB"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: false
  default_tier: T0
  tier_definitions: { T0: {}, T1: {} }
  transition_rules:
    - { from: T0, to: T1, requires: operator_grant }
EOF
    run trust_grant "f" "m" "deep-name" "T1" --reason "r" --operator "deep-name"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"graduated_trust.enabled"* ]]
}

@test "HIGH-3: trust_record_override refuses to write when L4 disabled" {
    source "$LIB"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: false
EOF
    run trust_record_override "f" "m" "deep-name" "d-1" "r"
    [[ "$status" -eq 1 ]]
}

@test "HIGH-3: trust_disable refuses to write when L4 disabled" {
    source "$LIB"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: false
EOF
    run trust_disable --reason "r" --operator "deep-name"
    [[ "$status" -eq 1 ]]
}

@test "HIGH-3: trust_query is NOT gated on _l4_enabled (read still works)" {
    source "$LIB"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: false
EOF
    run trust_query "f" "m" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T0"' >/dev/null
}

# =============================================================================
# HIGH-6: --force requires --operator distinct from actor
# =============================================================================

@test "HIGH-6: --force without --operator is rejected" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    run trust_grant "f" "m" "deep-name" "T2" --reason "force-without-op" --force
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--operator"* ]]
}

@test "HIGH-6: --force with operator==actor is rejected" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    run trust_grant "f" "m" "deep-name" "T2" --reason "self-force" --operator "deep-name" --force
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"distinct from actor"* ]]
}

@test "HIGH-6: --force with distinct --operator succeeds" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    run trust_grant "f" "m" "deep-name" "T2" --reason "ok-force" --operator "operator-2" --force
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# MED-2: reason rejects JSONL field substrings + control bytes
# =============================================================================

@test "MED-2: reason containing event_type substring is rejected (grep-injection defense)" {
    source "$LIB"
    run trust_grant "f" "m" "deep-name" "T1" --reason 'foo "event_type": "bar"' --operator "deep-name"
    [[ "$status" -eq 2 ]]
}

@test "MED-2: reason containing newline is rejected" {
    source "$LIB"
    run trust_grant "f" "m" "deep-name" "T1" --reason $'line1\nline2' --operator "deep-name"
    [[ "$status" -eq 2 ]]
}

# =============================================================================
# MED-3: decision_id rejects HTML/markdown injection
# =============================================================================

@test "MED-3: decision_id with angle brackets is rejected" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    run trust_record_override "f" "m" "deep-name" '<script>alert(1)</script>' "override"
    [[ "$status" -eq 2 ]]
}

# =============================================================================
# MED-4: LOA_TRUST_TEST_NOW gated to test mode
# =============================================================================

@test "MED-4: LOA_TRUST_TEST_NOW outside test mode is ignored" {
    source "$LIB"
    # Unset BATS_TEST_DIRNAME to simulate non-test env; LOA_TRUST_TEST_MODE not set
    local now
    now="$(BATS_TEST_DIRNAME='' LOA_TRUST_TEST_NOW='1970-01-01T00:00:00.000Z' _l4_now_iso8601)"
    [[ "$now" != "1970-01-01T00:00:00.000Z" ]]
    # When TEST_MODE=1 is explicitly set, override IS honored
    now="$(LOA_TRUST_TEST_MODE=1 BATS_TEST_DIRNAME='' LOA_TRUST_TEST_NOW='1970-01-01T00:00:00.000Z' _l4_now_iso8601)"
    [[ "$now" == "1970-01-01T00:00:00.000Z" ]]
}
