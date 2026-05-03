#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-envelope-concurrent-write.bats
#
# cycle-098 Sprint 1 review remediation — F3 (CC-3 violation).
#
# audit-envelope.sh:443 documented "callers should hold a flock" but L1's
# panel_log_* functions never acquired one. CC-3 explicitly requires flock
# for L1's audit log. Concurrent writers between `_audit_compute_prev_hash`
# and `>>` append can interleave, corrupting the chain.
#
# Fix: move flock acquisition INTO `audit_emit` so ALL callers benefit
# automatically. Lock file at <log_path>.lock.
#
# This test forks 5 concurrent writers and asserts all 5 entries land in the
# chain, with prev_hash continuity intact. Pre-fix: race conditions cause
# missing entries or broken chain. Post-fix: deterministic.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    command -v flock >/dev/null 2>&1 || skip "flock required for this test"

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/concurrent.jsonl"

    # Permissive trust-store (F1 isolation).
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
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE
}

# -----------------------------------------------------------------------------
# F3: 5 concurrent writers must produce 5 entries, all chain-valid.
# -----------------------------------------------------------------------------

@test "concurrent-write: 5 forked writers all land + chain remains valid" {
    local N=5
    local i
    local pids=()
    for i in $(seq 1 $N); do
        bash -c "
            source '$AUDIT_ENVELOPE'
            export LOA_TRUST_STORE_FILE='$LOA_TRUST_STORE_FILE'
            audit_emit L1 panel.bind '{\"decision_id\":\"d-$i\"}' '$LOG' >/dev/null 2>&1
        " &
        pids+=($!)
    done
    # Wait for all writers.
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # All 5 entries should be present.
    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq "$N" ]]

    # Chain must validate.
    source "$AUDIT_ENVELOPE"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK $N entries"* ]]
}

@test "concurrent-write: 10 forked writers all land + chain remains valid (stress)" {
    local N=10
    local i
    local pids=()
    for i in $(seq 1 $N); do
        bash -c "
            source '$AUDIT_ENVELOPE'
            export LOA_TRUST_STORE_FILE='$LOA_TRUST_STORE_FILE'
            audit_emit L1 panel.bind '{\"decision_id\":\"d-$i\"}' '$LOG' >/dev/null 2>&1
        " &
        pids+=($!)
    done
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq "$N" ]]

    source "$AUDIT_ENVELOPE"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK $N entries"* ]]
}

@test "concurrent-write: lock file is created at <log_path>.lock" {
    source "$AUDIT_ENVELOPE"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ -f "${LOG}.lock" ]]
}
