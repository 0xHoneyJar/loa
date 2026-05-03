#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-envelope-signing.bats
#
# cycle-098 Sprint 1B — Ed25519 signing wired into audit envelope.
# Exercises sign-verify cycle: write 3 entries with signing → verify chain
# validates signatures → tampered entry fails verification.
#
# AC sources:
#   - SDD §1.9.3.1 Ed25519 Key Lifecycle (verification on read)
#   - NFR-Sec1: signed envelope, per-writer key + canonical serialization
#   - Sprint 1B handoff: signing_key_id + signature populated
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    PYTHON_ADAPTER_DIR="$PROJECT_ROOT/.claude/adapters"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -d "$PYTHON_ADAPTER_DIR/loa_cheval" ]] || skip "loa_cheval not present"

    # Tests need cryptography for keypair generation.
    if ! python3 -c "import cryptography" 2>/dev/null; then
        skip "python cryptography not installed"
    fi

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/test.jsonl"

    # Generate an Ed25519 test keypair (unencrypted, for ease of test).
    KEY_DIR="$TEST_DIR/audit-keys"
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    python3 - "$KEY_DIR" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

key_dir = Path(sys.argv[1])
priv = ed25519.Ed25519PrivateKey.generate()

priv_bytes = priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
)
pub_bytes = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)
(key_dir / "test-writer-1.priv").write_bytes(priv_bytes)
(key_dir / "test-writer-1.priv").chmod(0o600)
(key_dir / "test-writer-1.pub").write_bytes(pub_bytes)
PY

    export LOA_AUDIT_KEY_DIR="$KEY_DIR"
    export LOA_AUDIT_SIGNING_KEY_ID="test-writer-1"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_AUDIT_KEY_DIR LOA_AUDIT_SIGNING_KEY_ID
}

# -----------------------------------------------------------------------------
# Sign on emit
# -----------------------------------------------------------------------------
@test "audit-signing-bash: emitted envelope contains signature + signing_key_id" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ -f "$LOG" ]]
    local sig kid
    sig=$(jq -r '.signature // empty' < "$LOG")
    kid=$(jq -r '.signing_key_id // empty' < "$LOG")
    [[ -n "$sig" ]]
    [[ "$kid" == "test-writer-1" ]]
}

@test "audit-signing-bash: signature is valid base64" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    local sig
    sig=$(jq -r '.signature' < "$LOG")
    # base64 decode + verify length is 64 bytes (Ed25519 signature is 64 bytes)
    local decoded_len
    decoded_len=$(printf '%s' "$sig" | python3 -c 'import base64,sys; print(len(base64.b64decode(sys.stdin.read())))')
    [[ "$decoded_len" -eq 64 ]]
}

# -----------------------------------------------------------------------------
# Verify chain validates signatures
# -----------------------------------------------------------------------------
@test "audit-signing-bash: verify_chain validates signatures on intact log" {
    for i in 1 2 3; do
        audit_emit L1 panel.bind "{\"decision_id\":\"d-$i\"}" "$LOG"
    done
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 3 entries"* ]]
}

@test "audit-signing-bash: verify_chain detects tampered signature" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"

    # Replace line 2's signature with a fake one (still valid base64 of 64 bytes).
    local fake_sig
    fake_sig=$(python3 -c 'import base64; print(base64.b64encode(b"\x00"*64).decode())')
    local tampered
    tampered=$(sed -n '2p' "$LOG" | jq -c --arg s "$fake_sig" '.signature = $s')
    {
        sed -n '1p' "$LOG"
        printf '%s\n' "$tampered"
        sed -n '3p' "$LOG"
    } > "$LOG.tmp"
    mv "$LOG.tmp" "$LOG"

    run audit_verify_chain "$LOG"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'BROKEN|signature' || {
        echo "Expected BROKEN or signature failure in output, got: $output"
        return 1
    }
}

@test "audit-signing-bash: verify_chain detects payload tampering via signature mismatch" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"

    # Tamper with line 2 payload but keep signature.
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
}

# -----------------------------------------------------------------------------
# Cross-adapter compatibility (R15) — bash signs, Python verifies and vice versa.
# -----------------------------------------------------------------------------
@test "audit-signing-cross: Python verifies bash-signed log" {
    for i in 1 2 3; do
        audit_emit L1 panel.bind "{\"decision_id\":\"d-$i\"}" "$LOG"
    done
    run env PYTHONPATH="$PYTHON_ADAPTER_DIR" \
        LOA_AUDIT_KEY_DIR="$KEY_DIR" \
        LOA_AUDIT_SIGNING_KEY_ID=test-writer-1 \
        python3 -c "
import sys
from loa_cheval.audit_envelope import audit_verify_chain
ok, msg = audit_verify_chain('$LOG')
print(msg)
sys.exit(0 if ok else 1)
"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 3 entries"* ]]
}

@test "audit-signing-cross: bash verifies Python-signed log" {
    run env PYTHONPATH="$PYTHON_ADAPTER_DIR" \
        LOA_AUDIT_KEY_DIR="$KEY_DIR" \
        LOA_AUDIT_SIGNING_KEY_ID=test-writer-1 \
        python3 -c "
from loa_cheval.audit_envelope import audit_emit
for i in range(3):
    audit_emit('L1', 'panel.bind', {'decision_id': f'd-{i}'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 3 entries"* ]]
}
