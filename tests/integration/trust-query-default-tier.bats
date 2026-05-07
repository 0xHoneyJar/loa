#!/usr/bin/env bats
# =============================================================================
# tests/integration/trust-query-default-tier.bats
#
# cycle-098 Sprint 4A — FR-L4-1: First query for any (scope, capability, actor)
# returns default_tier.
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

    export LOA_TRUST_CONFIG_FILE="$TEST_DIR/.loa.config.yaml"
    export LOA_TRUST_LEDGER_FILE="$TEST_DIR/trust-ledger.jsonl"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: true
  default_tier: T0
  tier_definitions:
    T0:
      description: "no autonomy"
    T1:
      description: "read-only"
    T2:
      description: "routine mutations"
    T3:
      description: "full"
  transition_rules:
    - from: T0
      to: T1
      requires: operator_grant
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
# FR-L4-1 happy path: empty ledger → default_tier
# =============================================================================

@test "FR-L4-1: empty ledger -> trust_query returns default_tier" {
    source "$LIB"
    run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T0"' >/dev/null
    echo "$output" | jq -e '.transition_history == []' >/dev/null
    echo "$output" | jq -e '.in_cooldown_until == null' >/dev/null
    echo "$output" | jq -e '.auto_raise_eligible == false' >/dev/null
}

@test "FR-L4-1: empty ledger + custom default_tier -> returns custom default" {
    source "$LIB"
    cat > "$LOA_TRUST_CONFIG_FILE" <<'EOF'
graduated_trust:
  enabled: true
  default_tier: T1
EOF
    run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
}

@test "FR-L4-1: missing ledger file (first install) -> returns default_tier" {
    source "$LIB"
    rm -f "$LOA_TRUST_LEDGER_FILE"
    run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T0"' >/dev/null
}

@test "FR-L4-1: response shape carries scope/capability/actor verbatim" {
    source "$LIB"
    run trust_query "core/auth" "rotate_credentials" "alice@example"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.scope == "core/auth"' >/dev/null
    echo "$output" | jq -e '.capability == "rotate_credentials"' >/dev/null
    echo "$output" | jq -e '.actor == "alice@example"' >/dev/null
}

# =============================================================================
# Input validation: bad input rejected with exit 2
# =============================================================================

@test "trust_query: missing argument -> exit 2" {
    source "$LIB"
    run trust_query "scope-only"
    [[ "$status" -eq 2 ]]
}

@test "trust_query: shell metacharacter in scope -> exit 2" {
    source "$LIB"
    run trust_query 'scope$EVIL' "merge_main" "deep-name"
    [[ "$status" -eq 2 ]]
}

@test "trust_query: dot-dot in actor -> exit 2 (charclass-bypass defense)" {
    source "$LIB"
    run trust_query "scope" "capability" "deep-name/../etc/passwd"
    [[ "$status" -eq 2 ]]
}

@test "trust_query: URL-shape in actor -> exit 2 (#761 pattern)" {
    source "$LIB"
    run trust_query "scope" "capability" "https://leak.example/secret"
    [[ "$status" -eq 2 ]]
}

# =============================================================================
# Ledger walking: pre-existing entries projected into transition_history
# =============================================================================

@test "trust_query: pre-existing trust.grant entry surfaces in transition_history" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":null,"to_tier":"T1","operator":"deep-name","reason":"alignment-validated"}}
EOF
    run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
    echo "$output" | jq -e '.transition_history | length == 1' >/dev/null
    echo "$output" | jq -e '.transition_history[0].transition_type == "initial"' >/dev/null
    echo "$output" | jq -e '.transition_history[0].to_tier == "T1"' >/dev/null
}

@test "trust_query: only entries matching scope/capability/actor included" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":null,"to_tier":"T1","operator":"deep-name","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-05-01T01:00:00.000Z","prev_hash":"x","payload":{"scope":"deploy","capability":"prod","actor":"deep-name","from_tier":null,"to_tier":"T2","operator":"deep-name","reason":"r"}}
EOF
    run trust_query "flatline" "merge_main" "deep-name"
    echo "$output" | jq -e '.transition_history | length == 1' >/dev/null
    echo "$output" | jq -e '.tier == "T1"' >/dev/null

    run trust_query "deploy" "prod" "deep-name"
    echo "$output" | jq -e '.transition_history | length == 1' >/dev/null
    echo "$output" | jq -e '.tier == "T2"' >/dev/null
}

@test "trust_query: cooldown derived from auto_drop event when within window" {
    source "$LIB"
    # auto_drop at 2026-05-01; cooldown 7d -> 2026-05-08; now is 2026-05-03 (within)
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-04-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":null,"to_tier":"T2","operator":"deep-name","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.auto_drop","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"x","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":"T2","to_tier":"T1","decision_id":"d-1","reason":"override","cooldown_until":"2026-05-08T00:00:00.000Z","cooldown_seconds":604800}}
EOF
    LOA_TRUST_TEST_NOW="2026-05-03T00:00:00.000Z" run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
    # in_cooldown_until is the auto_drop's ts + cooldown_seconds (computed by lib)
    echo "$output" | jq -e '.in_cooldown_until != null' >/dev/null
}

@test "trust_query: cooldown null when window has elapsed" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-04-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":null,"to_tier":"T2","operator":"deep-name","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.auto_drop","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"x","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":"T2","to_tier":"T1","decision_id":"d-1","reason":"override","cooldown_until":"2026-05-08T00:00:00.000Z","cooldown_seconds":604800}}
EOF
    LOA_TRUST_TEST_NOW="2026-06-01T00:00:00.000Z" run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.in_cooldown_until == null' >/dev/null
}

@test "trust_query: force_grant clears cooldown" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-04-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":null,"to_tier":"T2","operator":"deep-name","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.auto_drop","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"x","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":"T2","to_tier":"T1","decision_id":"d-1","reason":"override","cooldown_until":"2026-05-08T00:00:00.000Z","cooldown_seconds":604800}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.force_grant","ts_utc":"2026-05-02T00:00:00.000Z","prev_hash":"y","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":"T1","to_tier":"T2","operator":"deep-name","reason":"emergency","cooldown_remaining_seconds_at_grant":518400,"cooldown_until_at_grant":"2026-05-08T00:00:00.000Z"}}
EOF
    LOA_TRUST_TEST_NOW="2026-05-03T00:00:00.000Z" run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T2"' >/dev/null
    echo "$output" | jq -e '.in_cooldown_until == null' >/dev/null
}

@test "trust_query: TrustResponse schema validates" {
    if ! command -v ajv >/dev/null 2>&1; then
        skip "ajv not installed"
    fi
    source "$LIB"
    run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    local resp_file
    resp_file="$(mktemp)"
    printf '%s' "$output" > "$resp_file"
    run ajv validate \
        -s "$PROJECT_ROOT/.claude/data/trajectory-schemas/trust-events/trust-response.schema.json" \
        -d "$resp_file" --strict=false
    rm -f "$resp_file"
    [[ "$status" -eq 0 ]] || {
        echo "ajv: $output"
        return 1
    }
}

# =============================================================================
# Optional query event emission
# =============================================================================

@test "trust_query: LOA_TRUST_EMIT_QUERY_EVENTS=1 appends a trust.query entry" {
    source "$LIB"
    LOA_TRUST_EMIT_QUERY_EVENTS=1 run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    [[ -f "$LOA_TRUST_LEDGER_FILE" ]]
    grep -F '"event_type":"trust.query"' "$LOA_TRUST_LEDGER_FILE"
    # Ensure no stray query events when flag is OFF
    rm -f "$LOA_TRUST_LEDGER_FILE"
    run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    [[ ! -f "$LOA_TRUST_LEDGER_FILE" ]] || {
        if grep -F '"event_type":"trust.query"' "$LOA_TRUST_LEDGER_FILE" 2>/dev/null; then
            echo "trust.query emitted with flag off"
            return 1
        fi
    }
}

# =============================================================================
# Sealed ledger: reads still return last-known-tier per PRD §849
# =============================================================================

@test "trust_query: sealed ledger ([L4-DISABLED]) still returns last-known-tier" {
    source "$LIB"
    cat > "$LOA_TRUST_LEDGER_FILE" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.grant","ts_utc":"2026-05-01T00:00:00.000Z","prev_hash":"GENESIS","payload":{"scope":"flatline","capability":"merge_main","actor":"deep-name","from_tier":null,"to_tier":"T2","operator":"deep-name","reason":"r"}}
{"schema_version":"1.1.0","primitive_id":"L4","event_type":"trust.disable","ts_utc":"2026-05-02T00:00:00.000Z","prev_hash":"x","payload":{"operator":"deep-name","reason":"sealed","sealed_at":"2026-05-02T00:00:00.000Z"}}
EOF
    run trust_query "flatline" "merge_main" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T2"' >/dev/null
}

# =============================================================================
# Operator-identity gate
# =============================================================================

@test "trust_query: LOA_TRUST_REQUIRE_KNOWN_ACTOR=1 rejects unknown actor" {
    source "$LIB"
    # operator-identity needs OPERATORS.md; we rely on the existing one in the
    # repo. With an obviously-fake actor, this should reject.
    LOA_TRUST_REQUIRE_KNOWN_ACTOR=1 run trust_query "flatline" "merge_main" "definitely-not-an-operator-xyz123"
    [[ "$status" -eq 2 ]]
}
