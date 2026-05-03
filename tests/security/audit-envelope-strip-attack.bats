#!/usr/bin/env bats
# =============================================================================
# tests/security/audit-envelope-strip-attack.bats
#
# cycle-098 Sprint 1 review remediation — F1 (BLOCKER).
#
# Threat model: an attacker with repository write access could rewrite history
# by stripping `signature` and `signing_key_id` fields from previously signed
# entries. Pre-fix, audit_verify_chain only validates signatures when BOTH
# fields are present; the chain-input excludes them — so a stripped entry
# preserves prev_hash continuity and the chain still passes verification.
#
# This violates NFR-Sec1 (author-authenticated audit log).
#
# Fix: post-trust-cutoff entries (ts_utc >= trust_cutoff.default_strict_after)
# REQUIRE both `signature` and `signing_key_id` fields. Verification fails
# with [STRIP-ATTACK-DETECTED] if either is missing on such entries.
#
# Both bash + Python adapters MUST enforce identically (R15 behavior identity).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    PYTHON_ADAPTER_DIR="$PROJECT_ROOT/.claude/adapters"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -d "$PYTHON_ADAPTER_DIR/loa_cheval" ]] || skip "loa_cheval not present"

    # Tests need cryptography + jsonschema for keypair generation + verification.
    if ! python3 -c "import cryptography, jsonschema" 2>/dev/null; then
        skip "python cryptography or jsonschema not installed"
    fi

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/strip-attack.jsonl"

    # Generate an Ed25519 test keypair.
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
(key_dir / "test-writer-strip.priv").write_bytes(priv_bytes)
(key_dir / "test-writer-strip.priv").chmod(0o600)
(key_dir / "test-writer-strip.pub").write_bytes(pub_bytes)
PY

    # Trust-store with cutoff in the past so all entries are post-cutoff.
    TS="$TEST_DIR/trust-store.yaml"
    cat > "$TS" <<EOF
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: ""
  signed_at: ""
  signature: ""
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2020-01-01T00:00:00Z"
EOF

    export LOA_AUDIT_KEY_DIR="$KEY_DIR"
    export LOA_AUDIT_SIGNING_KEY_ID="test-writer-strip"
    export LOA_TRUST_STORE_FILE="$TS"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_AUDIT_KEY_DIR LOA_AUDIT_SIGNING_KEY_ID LOA_TRUST_STORE_FILE
}

# -----------------------------------------------------------------------------
# F1 strip attack — bash
# -----------------------------------------------------------------------------

@test "strip-attack-bash: chain valid before tampering (baseline)" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 3 entries"* ]]
}

@test "strip-attack-bash: stripping signature alone is detected post-cutoff" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"

    # Strip `signature` field from line 2 only.
    local stripped
    stripped="$(sed -n '2p' "$LOG" | jq -c 'del(.signature)')"
    {
        sed -n '1p' "$LOG"
        printf '%s\n' "$stripped"
        sed -n '3p' "$LOG"
    } > "${LOG}.tmp"
    mv "${LOG}.tmp" "$LOG"

    run audit_verify_chain "$LOG"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"STRIP-ATTACK-DETECTED"* ]] || [[ "$output" == *"missing signature"* ]] || [[ "$output" == *"signature required"* ]]
}

@test "strip-attack-bash: stripping signing_key_id alone is detected post-cutoff" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"

    # Strip `signing_key_id` field from line 2 only.
    local stripped
    stripped="$(sed -n '2p' "$LOG" | jq -c 'del(.signing_key_id)')"
    {
        sed -n '1p' "$LOG"
        printf '%s\n' "$stripped"
        sed -n '3p' "$LOG"
    } > "${LOG}.tmp"
    mv "${LOG}.tmp" "$LOG"

    run audit_verify_chain "$LOG"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"STRIP-ATTACK-DETECTED"* ]] || [[ "$output" == *"signing_key_id"* ]] || [[ "$output" == *"signature required"* ]]
}

@test "strip-attack-bash: stripping BOTH signature and signing_key_id is detected post-cutoff" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"

    # Strip BOTH fields from line 2.
    local stripped
    stripped="$(sed -n '2p' "$LOG" | jq -c 'del(.signature, .signing_key_id)')"
    {
        sed -n '1p' "$LOG"
        printf '%s\n' "$stripped"
        sed -n '3p' "$LOG"
    } > "${LOG}.tmp"
    mv "${LOG}.tmp" "$LOG"

    # CRITICAL: pre-fix this passes (the vulnerability). Post-fix it must fail.
    run audit_verify_chain "$LOG"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"STRIP-ATTACK-DETECTED"* ]] || [[ "$output" == *"signature required"* ]]
}

@test "strip-attack-bash: pre-cutoff entries grandfathered (no failure when unsigned)" {
    # Grandfather: ts_utc < cutoff means signing not required.
    cat > "$LOG" <<'EOF'
{"schema_version":"1.0.0","primitive_id":"L1","event_type":"panel.bind","ts_utc":"2019-01-01T00:00:00.000000Z","prev_hash":"GENESIS","payload":{"decision_id":"old"},"redaction_applied":null}
EOF

    run audit_verify_chain "$LOG"
    # An unsigned pre-cutoff entry should validate (chain only).
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# F1 strip attack — python
# -----------------------------------------------------------------------------

@test "strip-attack-python: stripping BOTH fields is detected post-cutoff" {
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"

    # Strip BOTH fields from line 2.
    local stripped
    stripped="$(sed -n '2p' "$LOG" | jq -c 'del(.signature, .signing_key_id)')"
    {
        sed -n '1p' "$LOG"
        printf '%s\n' "$stripped"
        sed -n '3p' "$LOG"
    } > "${LOG}.tmp"
    mv "${LOG}.tmp" "$LOG"

    export PYTHONPATH="$PYTHON_ADAPTER_DIR"
    export LOG_PATH="$LOG"
    run python3 -c '
import os, sys
from loa_cheval.audit_envelope import audit_verify_chain
ok, msg = audit_verify_chain(os.environ["LOG_PATH"])
print(msg)
sys.exit(0 if ok else 1)
'
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"STRIP-ATTACK-DETECTED"* ]] || [[ "$output" == *"signature required"* ]]
}

@test "strip-attack-python: pre-cutoff grandfathered (no failure when unsigned)" {
    cat > "$LOG" <<'EOF'
{"schema_version":"1.0.0","primitive_id":"L1","event_type":"panel.bind","ts_utc":"2019-01-01T00:00:00.000000Z","prev_hash":"GENESIS","payload":{"decision_id":"old"},"redaction_applied":null}
EOF

    export PYTHONPATH="$PYTHON_ADAPTER_DIR"
    export LOG_PATH="$LOG"
    run python3 -c '
import os, sys
from loa_cheval.audit_envelope import audit_verify_chain
ok, msg = audit_verify_chain(os.environ["LOG_PATH"])
print(msg)
sys.exit(0 if ok else 1)
'
    [[ "$status" -eq 0 ]]
}
