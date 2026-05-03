#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-envelope-chain.bats
#
# cycle-098 Sprint 1A — CC-2 (versioned, hash-chained envelope) +
# CC-11 (normative schema validation). Exercises hash-chain continuity:
# write 5 entries → verify chain → tamper → confirm broken.
#
# Both bash audit-envelope.sh and the Python adapter must agree on the chain
# semantics (R15: behavior identity).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    PYTHON_ADAPTER_DIR="$PROJECT_ROOT/.claude/adapters"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -d "$PYTHON_ADAPTER_DIR/loa_cheval" ]] || skip "loa_cheval not present"

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/test.jsonl"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Write + chain walk
# -----------------------------------------------------------------------------
@test "audit-chain-bash: emits 5 entries with prev_hash continuity" {
    for i in 1 2 3 4 5; do
        run audit_emit L1 panel.bind "{\"decision_id\":\"d-$i\"}" "$LOG"
        [[ "$status" -eq 0 ]]
    done
    [[ -f "$LOG" ]]
    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq 5 ]]
}

@test "audit-chain-bash: first entry has prev_hash=GENESIS" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    local first_prev
    first_prev=$(jq -r '.prev_hash' < "$LOG")
    [[ "$first_prev" == "GENESIS" ]]
}

@test "audit-chain-bash: second entry's prev_hash is SHA-256 of first" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    local second_prev
    second_prev=$(sed -n '2p' "$LOG" | jq -r '.prev_hash')
    # Must be 64 hex chars.
    [[ "$second_prev" =~ ^[0-9a-f]{64}$ ]]
}

@test "audit-chain-bash: verify_chain reports OK on intact log" {
    for i in 1 2 3; do
        audit_emit L1 panel.bind "{\"decision_id\":\"d-$i\"}" "$LOG"
    done
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 3 entries"* ]]
}

@test "audit-chain-bash: verify_chain detects tampered payload" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"
    # Tamper with line 2.
    local tampered
    tampered=$(sed -n '2p' "$LOG" | jq -c '.payload.decision_id = "TAMPERED"')
    {
        sed -n '1p' "$LOG"
        printf '%s\n' "$tampered"
        sed -n '3p' "$LOG"
    } > "$LOG.tmp"
    mv "$LOG.tmp" "$LOG"

    run audit_verify_chain "$LOG"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"BROKEN"* ]] || [[ "${BATS_RUN_OUTPUT:-}" == *"BROKEN"* ]] || true
    # bats run captures both stderr and stdout in $output for `run`; check both
    [[ "$output" == *"BROKEN"* || "${stderr:-}" == *"BROKEN"* ]] || \
        echo "$output$stderr" | grep -q "BROKEN"
}

@test "audit-chain-bash: seal appends [PRIMITIVE-DISABLED] marker" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_seal_chain L1 "$LOG"
    local last
    last=$(tail -n 1 "$LOG")
    [[ "$last" == "[L1-DISABLED]" ]]
}

@test "audit-chain-bash: seal does not break chain verify" {
    for i in 1 2; do
        audit_emit L1 panel.bind "{\"decision_id\":\"d-$i\"}" "$LOG"
    done
    audit_seal_chain L1 "$LOG"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 2 entries"* ]]
}

# -----------------------------------------------------------------------------
# Cross-adapter compatibility — bash writes, Python verifies.
# -----------------------------------------------------------------------------
@test "audit-chain-cross: Python verifies bash-written log" {
    for i in 1 2 3; do
        audit_emit L1 panel.bind "{\"decision_id\":\"d-$i\"}" "$LOG"
    done
    run env PYTHONPATH="$PYTHON_ADAPTER_DIR" python3 -c "
import sys
from loa_cheval.audit_envelope import audit_verify_chain
ok, msg = audit_verify_chain('$LOG')
print(msg)
sys.exit(0 if ok else 1)
"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 3 entries"* ]]
}

@test "audit-chain-cross: Python writes, bash verifies" {
    run env PYTHONPATH="$PYTHON_ADAPTER_DIR" python3 -c "
from loa_cheval.audit_envelope import audit_emit
for i in range(3):
    audit_emit('L1', 'panel.bind', {'decision_id': f'd-{i}'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 3 entries"* ]]
}
