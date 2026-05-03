#!/usr/bin/env bats
# =============================================================================
# tests/unit/trust-store-root-of-trust.bats
#
# cycle-098 Sprint 1B — root_signature verification on trust-store.
# Per SDD §1.9.3.1 SKP-001: trust-store updates require maintainer offline
# root key signature; runtime verification rejects unsigned trust-store changes.
#
# Tests:
#   - Well-formed signed trust-store validates against pinned pubkey
#   - Trust-store with tampered signature fails closed
#   - Trust-store with signature signed by wrong key fails closed
#   - Pinned pubkey path missing → BLOCKER + halt
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    if ! python3 -c "import cryptography" 2>/dev/null; then
        skip "python cryptography not installed"
    fi

    TEST_DIR="$(mktemp -d)"
    PINNED_PUBKEY="$TEST_DIR/pinned-root-pubkey.txt"
    TRUST_STORE="$TEST_DIR/trust-store.yaml"

    # Generate two keypairs:
    #   root_priv (matches pinned pubkey) — legit signer
    #   imposter_priv — used to test signature failures
    python3 - "$TEST_DIR" <<'PY'
import sys, os
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

td = Path(sys.argv[1])
for tag in ["root", "imposter"]:
    priv = ed25519.Ed25519PrivateKey.generate()
    pub_pem = priv.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    priv_pem = priv.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    (td / f"{tag}.pub").write_bytes(pub_pem)
    (td / f"{tag}.priv").write_bytes(priv_pem)

# The pinned pubkey is the root pubkey.
import shutil
shutil.copy(td / "root.pub", td / "pinned-root-pubkey.txt")
PY

    export LOA_PINNED_ROOT_PUBKEY_PATH="$PINNED_PUBKEY"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_PINNED_ROOT_PUBKEY_PATH
}

# Helper: create trust-store signed by <signer-priv>.
_sign_trust_store() {
    local out_path="$1"
    local signer_priv="$2"
    python3 - "$out_path" "$signer_priv" <<'PY'
import sys, json, base64, hashlib
from pathlib import Path
from datetime import datetime, timezone
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

out = Path(sys.argv[1])
signer_priv_path = Path(sys.argv[2])

priv = serialization.load_pem_private_key(signer_priv_path.read_bytes(), password=None)
pub_pem = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
).decode()

# Trust-store core (the part that gets signed).
# Sprint 1.5 (#695 F9): schema_version is included in the signed payload to
# defeat downgrade-rollback attacks. Must match the YAML schema_version field.
core = {
    "schema_version": "1.0",
    "keys": [],
    "revocations": [],
    "trust_cutoff": {"default_strict_after": "2026-05-02T00:00:00Z"},
}

# Canonicalize core via JCS-ish (sorted keys, no whitespace) for the signed bytes.
import rfc8785
core_bytes = rfc8785.dumps(core)
sig_bytes = priv.sign(core_bytes)
sig_b64 = base64.b64encode(sig_bytes).decode()

# Compose YAML (we hand-write to keep field order stable).
yaml_text = f"""---
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: |
{chr(10).join("    " + line for line in pub_pem.strip().split(chr(10)))}
  signed_at: "2026-05-03T00:00:00Z"
  signature: "{sig_b64}"
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2026-05-02T00:00:00Z"
"""
out.write_text(yaml_text)
PY
}

# -----------------------------------------------------------------------------
# Well-formed signed trust-store validates
# -----------------------------------------------------------------------------
@test "trust-store-root: legitimately signed trust-store validates against pinned pubkey" {
    _sign_trust_store "$TRUST_STORE" "$TEST_DIR/root.priv"
    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Tampered signature fails closed
# -----------------------------------------------------------------------------
@test "trust-store-root: tampered signature fails verification" {
    _sign_trust_store "$TRUST_STORE" "$TEST_DIR/root.priv"
    # Corrupt the signature line.
    sed -i.bak 's/signature: "/signature: "AAAA/' "$TRUST_STORE"

    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# Wrong key fails closed
# -----------------------------------------------------------------------------
@test "trust-store-root: signature by imposter key (not pinned root) fails" {
    _sign_trust_store "$TRUST_STORE" "$TEST_DIR/imposter.priv"
    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'ROOT-PUBKEY-DIVERGENCE|signature|verification' || {
        echo "Expected divergence/verification error in output, got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Missing pinned pubkey halts
# -----------------------------------------------------------------------------
@test "trust-store-root: missing pinned pubkey path emits BLOCKER" {
    _sign_trust_store "$TRUST_STORE" "$TEST_DIR/root.priv"
    export LOA_PINNED_ROOT_PUBKEY_PATH="$TEST_DIR/nonexistent.pub"
    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# Missing root_signature field fails closed
# -----------------------------------------------------------------------------
@test "trust-store-root: trust-store without root_signature fails" {
    cat > "$TRUST_STORE" <<'YAML'
---
schema_version: "1.0"
keys: []
revocations: []
trust_cutoff:
  default_strict_after: "2026-05-02T00:00:00Z"
YAML
    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -ne 0 ]]
}
