#!/usr/bin/env bats
# =============================================================================
# tests/unit/graduated-trust-lib-defaults.bats
#
# cycle-098 Sprint 4A — config getters, validators, and defaults for the L4
# graduated-trust library. Pre-trust_query plumbing.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/graduated-trust-lib.sh"

    [[ -f "$LIB" ]] || skip "graduated-trust-lib.sh not present"

    # Use a private trust-store so audit_emit doesn't reach the real one.
    TEST_DIR="$(mktemp -d)"
    TEST_TRUST_STORE="$TEST_DIR/trust-store.yaml"
    cat > "$TEST_TRUST_STORE" <<'EOF'
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: ""
  signed_at: ""
  signature: ""
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2099-01-01T00:00:00Z"
EOF
    export LOA_TRUST_STORE_FILE="$TEST_TRUST_STORE"

    # Per-test private config, ledger, etc.
    TEST_CONFIG="$TEST_DIR/.loa.config.yaml"
    TEST_LEDGER="$TEST_DIR/trust-ledger.jsonl"
    export LOA_TRUST_CONFIG_FILE="$TEST_CONFIG"
    export LOA_TRUST_LEDGER_FILE="$TEST_LEDGER"
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

# -----------------------------------------------------------------------------
# Validators
# -----------------------------------------------------------------------------

@test "validator: rejects empty token" {
    source "$LIB"
    run _l4_validate_token "" "scope"
    [[ "$status" -ne 0 ]]
}

@test "validator: rejects shell metacharacter" {
    source "$LIB"
    for bad in 'a$b' 'a`b' 'a;b' 'a&b' 'a|b' 'a(b' 'a)b' 'a{b' 'a<b' 'a"b' "a'b"; do
        run _l4_validate_token "$bad" "scope"
        [[ "$status" -ne 0 ]] || {
            echo "did not reject: $bad"
            return 1
        }
    done
}

@test "validator: rejects whitespace and control bytes" {
    source "$LIB"
    for bad in 'a b' $'a\tb' $'a\nb' $'a\rb'; do
        run _l4_validate_token "$bad" "scope"
        [[ "$status" -ne 0 ]] || {
            echo "did not reject (whitespace/control)"
            return 1
        }
    done
}

@test "validator: rejects '..' (charclass dot-dot bypass defense)" {
    source "$LIB"
    run _l4_validate_token "scope..pwn" "scope"
    [[ "$status" -ne 0 ]]
    run _l4_validate_token ".." "scope"
    [[ "$status" -ne 0 ]]
    run _l4_validate_token "a/../b" "scope"
    [[ "$status" -ne 0 ]]
}

@test "validator: rejects URL-shape (cycle-099 #761 pattern)" {
    source "$LIB"
    run _l4_validate_token "http://example.com/scope" "scope"
    [[ "$status" -ne 0 ]]
    run _l4_validate_token "//pasted-leak" "scope"
    [[ "$status" -ne 0 ]]
    run _l4_validate_token "?q=secret" "scope"
    [[ "$status" -ne 0 ]]
}

@test "validator: accepts canonical scope/capability/actor" {
    source "$LIB"
    for ok in 'flatline' 'merge_main' 'deep-name' 'core/auth' 'agent.deploy' 'org:repo'; do
        run _l4_validate_token "$ok" "scope"
        [[ "$status" -eq 0 ]] || {
            echo "should have accepted: $ok"
            return 1
        }
    done
}

@test "validator: rejects oversize token (>256 chars)" {
    source "$LIB"
    local big
    big="$(printf 'a%.0s' {1..300})"
    run _l4_validate_token "$big" "scope"
    [[ "$status" -ne 0 ]]
}

@test "tier validator: accepts T0/T1/T2/T3 + custom names; rejects shell metas" {
    source "$LIB"
    for ok in T0 T1 T2 T3 trusted apprentice; do
        run _l4_validate_tier "$ok" "tier"
        [[ "$status" -eq 0 ]]
    done
    for bad in 'T0;rm' 'T0$' '' '  '; do
        run _l4_validate_tier "$bad" "tier"
        [[ "$status" -ne 0 ]]
    done
}

# -----------------------------------------------------------------------------
# Config getters
# -----------------------------------------------------------------------------

@test "config: default_tier falls back to T0 when not configured" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
EOF
    run _l4_get_default_tier
    [[ "$status" -eq 0 ]]
    [[ "$output" == "T0" ]]
}

@test "config: default_tier honors operator config" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
  default_tier: T1
EOF
    run _l4_get_default_tier
    [[ "$status" -eq 0 ]]
    [[ "$output" == "T1" ]]
}

@test "config: default_tier env override beats operator config" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
  default_tier: T1
EOF
    LOA_TRUST_DEFAULT_TIER="T2" run _l4_get_default_tier
    [[ "$output" == "T2" ]]
}

@test "config: cooldown_seconds defaults to 7 days (604800)" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
EOF
    run _l4_get_cooldown_seconds
    [[ "$output" == "604800" ]]
}

@test "config: cooldown_seconds honors operator config" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
  cooldown_seconds: 3600
EOF
    run _l4_get_cooldown_seconds
    [[ "$output" == "3600" ]]
}

@test "config: cooldown_seconds rejects non-integer (falls back to default)" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
  cooldown_seconds: "abc; rm -rf /"
EOF
    run _l4_get_cooldown_seconds
    # Stderr-error logged AND fallback printed; assert the stdout line.
    echo "$output" | grep -qx "604800"
}

@test "config: tier_definitions returns JSON object (or {} when missing)" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
  tier_definitions:
    T0:
      description: "no autonomy"
    T1:
      description: "read-only"
EOF
    run _l4_get_tier_definitions
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.T0.description == "no autonomy"' >/dev/null
    echo "$output" | jq -e '.T1.description == "read-only"' >/dev/null
}

@test "config: transition_rules returns JSON array (or [] when missing)" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
  transition_rules:
    - from: T0
      to: T1
      requires: operator_grant
EOF
    run _l4_get_transition_rules
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e 'length == 1' >/dev/null
    echo "$output" | jq -e '.[0].from == "T0"' >/dev/null
}

@test "_l4_enabled: false when config absent" {
    source "$LIB"
    rm -f "$TEST_CONFIG"
    if _l4_enabled; then
        echo "should be disabled when config missing"
        return 1
    fi
}

@test "_l4_enabled: true when graduated_trust.enabled=true" {
    source "$LIB"
    cat > "$TEST_CONFIG" <<'EOF'
graduated_trust:
  enabled: true
EOF
    _l4_enabled
}

# -----------------------------------------------------------------------------
# Sealing detection
# -----------------------------------------------------------------------------

@test "sealing: empty/missing ledger returns not-sealed" {
    source "$LIB"
    rm -f "$TEST_LEDGER"
    if _l4_ledger_is_sealed "$TEST_LEDGER"; then
        echo "missing ledger should not be sealed"
        return 1
    fi
}

@test "sealing: last entry trust.disable returns sealed" {
    source "$LIB"
    cat > "$TEST_LEDGER" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"s","capability":"c","actor":"a","from_tier":null,"to_tier":"T1","operator":"o","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.disable","ts_utc":"2026-05-02T00:00:00.000Z","prev_hash":"abc","payload":{"operator":"o","reason":"sealed","sealed_at":"2026-05-02T00:00:00.000Z"}}
EOF
    _l4_ledger_is_sealed "$TEST_LEDGER"
}

@test "sealing: last entry NOT trust.disable returns not-sealed" {
    source "$LIB"
    cat > "$TEST_LEDGER" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"s","capability":"c","actor":"a","from_tier":null,"to_tier":"T1","operator":"o","reason":"r"}}
EOF
    if _l4_ledger_is_sealed "$TEST_LEDGER"; then
        echo "single non-disable entry should not be sealed"
        return 1
    fi
}
