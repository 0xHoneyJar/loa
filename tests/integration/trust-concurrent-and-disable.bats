#!/usr/bin/env bats
# =============================================================================
# tests/integration/trust-concurrent-and-disable.bats
#
# cycle-098 Sprint 4D — concurrency safety (FR-L4-6: runtime + cron + CLI
# flock-based serialization) and trust_disable seal semantics.
#
# The concurrency tests fork N parallel writers all aiming the same
# (scope, capability, actor) triple and verify:
#   - the chain remains valid (audit_verify_chain passes)
#   - all transitions are recorded (no lost writes)
#   - the resolved final tier is consistent regardless of dispatch order
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    LIB="$PROJECT_ROOT/.claude/scripts/lib/graduated-trust-lib.sh"
    [[ -f "$LIB" ]] || skip "graduated-trust-lib.sh not present"

    if ! command -v flock >/dev/null 2>&1; then
        skip "flock not in PATH (concurrency tests require flock)"
    fi

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
  cooldown_seconds: 1   # short for tests; cooldown not the concurrency invariant
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
# FR-L4-6: concurrent writes preserve chain integrity
# =============================================================================

@test "FR-L4-6: 8 parallel trust_grant writers (initial T0->T1) — chain remains valid" {
    source "$LIB"
    # First writer wins; others see the new state and reject as no-op (exit 3).
    # The contract under test: NO chain corruption regardless of who wins.
    local pids=()
    for i in 1 2 3 4 5 6 7 8; do
        ( source "$LIB"; trust_grant "scope-c" "cap-c" "actor-c" "T1" --reason "race$i" --operator "deep-name" >/dev/null 2>&1 || true ) &
        pids+=("$!")
    done
    for p in "${pids[@]}"; do wait "$p" || true; done

    # Exactly one trust.grant entry (the winner).
    local n
    n="$(grep -cF '"event_type":"trust.grant"' "$LOA_TRUST_LEDGER_FILE")"
    [[ "$n" == "1" ]] || {
        echo "expected 1 trust.grant entry, got $n"
        return 1
    }

    # Chain valid.
    run trust_verify_chain
    [[ "$status" -eq 0 ]] || {
        echo "chain verify failed after parallel writes:"
        echo "$output"
        cat "$LOA_TRUST_LEDGER_FILE" >&3 2>/dev/null || true
        return 1
    }

    # Tier resolves to T1.
    run trust_query "scope-c" "cap-c" "actor-c"
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
}

@test "FR-L4-6: parallel writers across different (scope,cap,actor) — all complete; chain valid" {
    source "$LIB"
    local pids=()
    for i in 1 2 3 4 5 6 7 8 9 10; do
        ( source "$LIB"
          trust_grant "scope-$i" "cap-$i" "actor-$i" "T1" \
              --reason "parallel" --operator "deep-name" >/dev/null 2>&1
        ) &
        pids+=("$!")
    done
    for p in "${pids[@]}"; do wait "$p"; done

    local n
    n="$(grep -cF '"event_type":"trust.grant"' "$LOA_TRUST_LEDGER_FILE")"
    [[ "$n" == "10" ]] || {
        echo "expected 10 entries, got $n"
        return 1
    }
    run trust_verify_chain
    [[ "$status" -eq 0 ]]
}

@test "FR-L4-6: mixed grant + record_override + force_grant in parallel — chain valid" {
    source "$LIB"
    # Pre-populate to T2 so override has a tier to drop from.
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"

    local pids=()
    for i in 1 2 3; do
        ( source "$LIB"
          # Different actors so no false-positive collisions.
          trust_grant "f" "m" "actor-A-$i" "T1" \
              --reason "from-runtime-$i" --operator "deep-name" >/dev/null 2>&1 || true
        ) &
        pids+=("$!")
    done
    for i in 1 2 3; do
        ( source "$LIB"
          trust_record_override "f" "m" "deep-name" "decision-$i" "override-$i" >/dev/null 2>&1 || true
        ) &
        pids+=("$!")
    done
    for i in 1 2; do
        ( source "$LIB"
          trust_grant "f" "m" "actor-B-$i" "T1" \
              --reason "from-cli-$i" --operator "deep-name" --force >/dev/null 2>&1 || true
        ) &
        pids+=("$!")
    done
    for p in "${pids[@]}"; do wait "$p"; done

    run trust_verify_chain
    [[ "$status" -eq 0 ]] || {
        echo "$output"
        return 1
    }
}

# =============================================================================
# trust_disable seal semantics
# =============================================================================

@test "trust_disable: missing --reason rejected with exit 2" {
    source "$LIB"
    run trust_disable --operator "deep-name"
    [[ "$status" -eq 2 ]]
}

@test "trust_disable: missing --operator rejected with exit 2" {
    source "$LIB"
    run trust_disable --reason "rotating"
    [[ "$status" -eq 2 ]]
}

@test "trust_disable: oversize reason rejected" {
    source "$LIB"
    local big
    big="$(printf 'a%.0s' {1..5000})"
    run trust_disable --reason "$big" --operator "deep-name"
    [[ "$status" -eq 2 ]]
}

@test "trust_disable: writes trust.disable event and seals the ledger" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    run trust_disable --reason "rotating" --operator "deep-name"
    [[ "$status" -eq 0 ]]
    grep -F '"event_type":"trust.disable"' "$LOA_TRUST_LEDGER_FILE"

    # After seal: subsequent grants exit 1 (sealed); reads still work.
    run trust_grant "f" "m" "deep-name" "T2" --reason "after-seal" --operator "deep-name"
    [[ "$status" -eq 1 ]]
    run trust_query "f" "m" "deep-name"
    [[ "$status" -eq 0 ]]
    echo "$output" | jq -e '.tier == "T1"' >/dev/null
}

@test "trust_disable: re-disable on already-sealed ledger -> exit 3" {
    source "$LIB"
    trust_disable --reason "first" --operator "deep-name"
    run trust_disable --reason "second" --operator "deep-name"
    [[ "$status" -eq 3 ]]
}

@test "trust_disable: chain remains valid after seal" {
    source "$LIB"
    trust_grant "f" "m" "deep-name" "T1" --reason "s1" --operator "deep-name"
    trust_grant "f" "m" "deep-name" "T2" --reason "s2" --operator "deep-name"
    trust_disable --reason "rotate" --operator "deep-name"
    run trust_verify_chain
    [[ "$status" -eq 0 ]]
}

@test "trust_disable: shell-meta operator rejected (FR-L4-6 input pin)" {
    source "$LIB"
    run trust_disable --reason "r" --operator 'evil; rm -rf /'
    [[ "$status" -eq 2 ]]
}

# =============================================================================
# Lore + skill + CLAUDE.md presence (4D handoff invariants)
# =============================================================================

@test "4D handoff: graduated-trust SKILL.md exists" {
    [[ -f "$PROJECT_ROOT/.claude/skills/graduated-trust/SKILL.md" ]]
}

@test "4D handoff: lore patterns.yaml contains graduated-trust + auto-drop + cooldown" {
    grep -F 'id: graduated-trust' "$PROJECT_ROOT/grimoires/loa/lore/patterns.yaml"
    grep -F 'id: auto-drop' "$PROJECT_ROOT/grimoires/loa/lore/patterns.yaml"
    grep -F 'id: cooldown' "$PROJECT_ROOT/grimoires/loa/lore/patterns.yaml"
}

@test "4D handoff: CLAUDE.md has L4 Graduated-Trust Constraints section" {
    grep -F 'L4 Graduated-Trust' "$PROJECT_ROOT/.claude/loa/CLAUDE.loa.md"
    grep -F 'Graduated-Trust Constraints' "$PROJECT_ROOT/.claude/loa/CLAUDE.loa.md"
}
