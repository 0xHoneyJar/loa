#!/usr/bin/env bats
# =============================================================================
# tests/integration/trust-grant-and-override.bats
#
# cycle-098 Sprint 4B — FR-L4-2 (only configured transitions allowed) and
# FR-L4-3 (recordOverride auto-drop + cooldown enforced).
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
    T0: { description: "no autonomy" }
    T1: { description: "read-only" }
    T2: { description: "routine" }
    T3: { description: "full" }
  transition_rules:
    - from: T0
      to: T1
      requires: operator_grant
      id: T0_to_T1
    - from: T1
      to: T2
      requires: operator_grant
      id: T1_to_T2
    - from: T2
      to: T3
      requires: operator_grant
      id: T2_to_T3
    - from: T2
      to: T1
      via: auto_drop_on_override
    - from: T3
      to: T1
      via: auto_drop_on_override
    - from: any
      to_lower: true
      via: auto_drop_on_override
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
# FR-L4-2: trust_grant — only configured transitions allowed
# =============================================================================

@test "FR-L4-2: initial T0->T1 grant succeeds (matches T0_to_T1 rule)" {
    source "$LIB"
    run trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "alignment-validated" --operator "deep-name"
    [[ "$status" -eq 0 ]] || {
        echo "$output"
        return 1
    }
    [[ -f "$LOA_TRUST_LEDGER_FILE" ]]
    grep -F '"event_type":"trust.grant"' "$LOA_TRUST_LEDGER_FILE"

    run trust_query "flatline" "merge_main" "deep-name"
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
}

@test "FR-L4-2: arbitrary jump T0->T3 is REJECTED (no rule matches)" {
    source "$LIB"
    run trust_grant "flatline" "merge_main" "deep-name" "T3" --reason "yolo" --operator "deep-name"
    [[ "$status" -eq 3 ]]
    [[ ! -f "$LOA_TRUST_LEDGER_FILE" ]] || {
        if grep -F '"event_type":"trust.grant"' "$LOA_TRUST_LEDGER_FILE" 2>/dev/null; then
            echo "trust.grant emitted despite rejection"
            return 1
        fi
    }
}

@test "FR-L4-2: chained T0->T1->T2 grants both succeed" {
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "step2" --operator "deep-name"
    run trust_query "flatline" "merge_main" "deep-name"
    echo "$output" | jq -e '.tier == "T2"' >/dev/null
    echo "$output" | jq -e '.transition_history | length == 2' >/dev/null
}

@test "FR-L4-2: re-granting current tier is rejected (no-op)" {
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    run trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "again" --operator "deep-name"
    [[ "$status" -eq 3 ]]
}

@test "trust_grant: missing --reason rejected with exit 2" {
    source "$LIB"
    run trust_grant "flatline" "merge_main" "deep-name" "T1" --operator "deep-name"
    [[ "$status" -eq 2 ]]
}

@test "trust_grant: missing positional rejected with exit 2" {
    source "$LIB"
    run trust_grant "flatline" "merge_main" "deep-name" --reason "r" --operator "o"
    [[ "$status" -eq 2 ]]
}

@test "trust_grant: oversize reason rejected" {
    source "$LIB"
    local big
    big="$(printf 'a%.0s' {1..5000})"
    run trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "$big" --operator "deep-name"
    [[ "$status" -eq 2 ]]
}

@test "trust_grant: --force routes to trust.force_grant (Sprint 4C wired)" {
    # Pinned at 4B: --force was a stub returning 99. Sprint 4C activated the
    # real path; this test documents the transition. The detailed exception
    # behavior is covered by tests/integration/trust-chain-and-force-grant.bats.
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "step2" --operator "deep-name"
    trust_record_override "flatline" "merge_main" "deep-name" "decision-x" "override"
    run trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "rerise" --force --operator "deep-name"
    [[ "$status" -eq 0 ]]
    grep -F '"event_type":"trust.force_grant"' "$LOA_TRUST_LEDGER_FILE"
}

@test "trust_grant: writes payload that matches trust-grant schema (jq shape)" {
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "validated" --operator "deep-name"
    local entry
    entry="$(grep -F '"event_type":"trust.grant"' "$LOA_TRUST_LEDGER_FILE" | head -n 1)"
    echo "$entry" | jq -e '.payload.scope == "flatline"' >/dev/null
    echo "$entry" | jq -e '.payload.from_tier == null' >/dev/null
    echo "$entry" | jq -e '.payload.to_tier == "T1"' >/dev/null
    echo "$entry" | jq -e '.payload.transition_rule_id == "T0_to_T1"' >/dev/null
}

@test "trust_grant: ledger sealed -> rejected with exit 1" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.disable","ts_utc":"2026-05-02T00:00:00.000Z","prev_hash":"GENESIS","payload":{"operator":"o","reason":"sealed","sealed_at":"2026-05-02T00:00:00.000Z"}}
EOF
    run trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "r" --operator "deep-name"
    [[ "$status" -eq 1 ]]
}

# =============================================================================
# FR-L4-3: trust_record_override — auto-drop + cooldown enforced
# =============================================================================

@test "FR-L4-3: override drops T2->T1 per explicit rule" {
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "step2" --operator "deep-name"
    run trust_record_override "flatline" "merge_main" "deep-name" "decision-1" "panel decision overridden"
    [[ "$status" -eq 0 ]] || {
        echo "$output"
        return 1
    }
    run trust_query "flatline" "merge_main" "deep-name"
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
    echo "$output" | jq -e '.in_cooldown_until != null' >/dev/null
}

@test "FR-L4-3: cooldown blocks regular trust_grant" {
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "step2" --operator "deep-name"
    trust_record_override "flatline" "merge_main" "deep-name" "decision-1" "override"
    # Cooldown active; T1 -> T2 grant should be blocked.
    run trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "rerise" --operator "deep-name"
    [[ "$status" -eq 3 ]]
    [[ "$output" == *"cooldown"* ]]
}

@test "FR-L4-3: cooldown_until = ts + cooldown_seconds (precise math)" {
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "step2" --operator "deep-name"
    LOA_TRUST_TEST_NOW="2026-05-01T00:00:00.000Z" \
        trust_record_override "flatline" "merge_main" "deep-name" "decision-1" "override"
    local entry
    entry="$(grep -F '"event_type":"trust.auto_drop"' "$LOA_TRUST_LEDGER_FILE" | head -n 1)"
    # Payload's cooldown_until should be 2026-05-01 + 7d = 2026-05-08T00:00:00.000Z.
    echo "$entry" | jq -e '.payload.cooldown_until == "2026-05-08T00:00:00.000Z"' >/dev/null
    echo "$entry" | jq -e '.payload.cooldown_seconds == 604800' >/dev/null
}

@test "FR-L4-3: re-override during cooldown is allowed (rolling cooldown)" {
    source "$LIB"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "step2" --operator "deep-name"
    LOA_TRUST_TEST_NOW="2026-05-01T00:00:00.000Z" \
        trust_record_override "flatline" "merge_main" "deep-name" "decision-1" "override-1"
    LOA_TRUST_TEST_NOW="2026-05-02T00:00:00.000Z" \
        run trust_record_override "flatline" "merge_main" "deep-name" "decision-2" "override-2"
    [[ "$status" -eq 0 ]]
    # Two auto_drop entries.
    [[ "$(grep -cF '"event_type":"trust.auto_drop"' "$LOA_TRUST_LEDGER_FILE")" == "2" ]]
}

@test "FR-L4-3: missing decision_id rejected with exit 2" {
    source "$LIB"
    run trust_record_override "flatline" "merge_main" "deep-name" "" "reason"
    [[ "$status" -eq 2 ]]
}

@test "FR-L4-3: decision_id with shell metacharacter rejected" {
    source "$LIB"
    run trust_record_override "flatline" "merge_main" "deep-name" 'd-1$EVIL`whoami`' "reason"
    [[ "$status" -eq 2 ]]
}

@test "FR-L4-3: when no auto_drop rule configured -> exit 3" {
    source "$LIB"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: true
  default_tier: T0
  tier_definitions:
    T0: { description: "no" }
    T1: { description: "y" }
  transition_rules:
    - from: T0
      to: T1
      requires: operator_grant
EOF
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    run trust_record_override "flatline" "merge_main" "deep-name" "d-1" "override"
    [[ "$status" -eq 3 ]]
    [[ "$output" == *"auto_drop_on_override"* ]]
}

@test "FR-L4-3: 'any/to_lower:true' rule resolves drop_to=default_tier when no explicit rule" {
    source "$LIB"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: true
  default_tier: T0
  tier_definitions:
    T0: { description: "no" }
    T1: { description: "y" }
  transition_rules:
    - from: T0
      to: T1
      requires: operator_grant
    - from: any
      to_lower: true
      via: auto_drop_on_override
EOF
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "step1" --operator "deep-name"
    run trust_record_override "flatline" "merge_main" "deep-name" "d-1" "override"
    [[ "$status" -eq 0 ]]
    run trust_query "flatline" "merge_main" "deep-name"
    echo "$output" | jq -e '.tier == "T0"' >/dev/null
}

@test "FR-L4-3: oversize reason rejected" {
    source "$LIB"
    local big
    big="$(printf 'a%.0s' {1..5000})"
    run trust_record_override "flatline" "merge_main" "deep-name" "d-1" "$big"
    [[ "$status" -eq 2 ]]
}

@test "FR-L4-3: ledger sealed -> override rejected with exit 3" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.disable","ts_utc":"2026-05-02T00:00:00.000Z","prev_hash":"GENESIS","payload":{"operator":"o","reason":"sealed","sealed_at":"2026-05-02T00:00:00.000Z"}}
EOF
    run trust_record_override "flatline" "merge_main" "deep-name" "d-1" "override"
    [[ "$status" -eq 3 ]]
}

# =============================================================================
# Hash-chain shape: 4B emits with audit_emit, so chain hashes must be valid.
# =============================================================================

@test "trust_grant + trust_record_override produce valid prev_hash chain" {
    source "$LIB"
    source "$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    trust_grant "flatline" "merge_main" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "flatline" "merge_main" "deep-name" "T2" --reason "s2" --operator "deep-name"
    trust_record_override "flatline" "merge_main" "deep-name" "d-1" "override"
    run audit_verify_chain "$LOA_TRUST_LEDGER_FILE"
    [[ "$status" -eq 0 ]] || {
        echo "audit_verify_chain rejected the chain produced by trust_grant + trust_record_override"
        echo "$output"
        return 1
    }
}
