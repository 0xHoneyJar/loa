#!/usr/bin/env bats
# =============================================================================
# tests/unit/trust-store-signed-payload-scope.bats
#
# cycle-098 Sprint 1.5 hardening — issue #695 F9.
#
# Bridgebuilder iter-1 of PR #693 surfaced that the trust-store signed payload
# (`{keys, revocations, trust_cutoff}`) excluded `schema_version`. Anything
# outside the signed envelope is attacker-controlled. Schema version often
# gates parser behavior — leaving it unsigned is a classic downgrade vector
# (cf. TLS version rollback, JWT alg confusion).
#
# Decision (Option 1 — security tightening): include `schema_version` in the
# signed payload. This removes the downgrade attack surface entirely.
#
# Acceptance criteria:
#   - Decision documented (Option 1: include in signature)
#   - Negative test: schema_version tampering → trust-store verify fails
#   - SDD §1.9.3.1 updated to make signed-payload boundary explicit
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    if ! python3 -c "import cryptography, yaml, rfc8785" 2>/dev/null; then
        skip "python cryptography + yaml + rfc8785 required"
    fi

    TEST_DIR="$(mktemp -d)"
    PINNED_PUBKEY="$TEST_DIR/pinned-root-pubkey.txt"
    TRUST_STORE="$TEST_DIR/trust-store.yaml"

    python3 - "$TEST_DIR" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

td = Path(sys.argv[1])
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
(td / "root.pub").write_bytes(pub_pem)
(td / "root.priv").write_bytes(priv_pem)
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

# Sign a trust-store with `schema_version` INCLUDED in signed payload.
_sign_with_schema_version() {
    local out_path="$1"
    local signer_priv="$2"
    local schema_v="${3:-1.0}"
    python3 - "$out_path" "$signer_priv" "$schema_v" <<'PY'
import sys, base64
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
import rfc8785

out = Path(sys.argv[1])
priv = serialization.load_pem_private_key(Path(sys.argv[2]).read_bytes(), password=None)
schema_v = sys.argv[3]
pub_pem = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
).decode()

# F9: schema_version IS part of the signed core (Option 1 — security tightening).
core = {
    "schema_version": schema_v,
    "keys": [],
    "revocations": [],
    "trust_cutoff": {"default_strict_after": "2026-05-02T00:00:00Z"},
}
sig_b64 = base64.b64encode(priv.sign(rfc8785.dumps(core))).decode()

yaml_text = f"""---
schema_version: "{schema_v}"
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
# Positive: schema_version IS in signed payload → legitimate sig validates
# -----------------------------------------------------------------------------
@test "f9: legitimately signed trust-store (schema_version in signed payload) validates" {
    _sign_with_schema_version "$TRUST_STORE" "$TEST_DIR/root.priv" "1.0"
    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Negative: tamper schema_version (downgrade attack) → verification fails
# -----------------------------------------------------------------------------
@test "f9: tampered schema_version (downgrade attack) fails verification" {
    _sign_with_schema_version "$TRUST_STORE" "$TEST_DIR/root.priv" "1.0"

    # Attacker swaps schema_version "1.0" → "0.9" (rollback to permissive parser).
    sed -i.bak 's/^schema_version: "1.0"$/schema_version: "0.9"/' "$TRUST_STORE"
    rm -f "$TRUST_STORE.bak"

    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -ne 0 ]]
    # Bridgebuilder F8: tightened to the exact failure token emitted by
    # audit-signing-helper.py:cmd_trust_store_verify (`InvalidSignature` →
    # "root_signature does NOT verify"). Permissive `verify|signature|...` regex
    # caught hypothetical success banners; this assertion is now load-bearing.
    echo "$output" | grep -q 'root_signature does NOT verify' || {
        echo "Expected 'root_signature does NOT verify' marker in output, got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Negative: schema_version tampering inside YAML (top-level) detected
# -----------------------------------------------------------------------------
@test "f9: tampered schema_version forward-version (e.g. 1.0 → 2.0) fails verification" {
    _sign_with_schema_version "$TRUST_STORE" "$TEST_DIR/root.priv" "1.0"

    # Attacker bumps schema_version to a future incompatible version.
    sed -i.bak 's/^schema_version: "1.0"$/schema_version: "2.0"/' "$TRUST_STORE"
    rm -f "$TRUST_STORE.bak"

    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# F2 (bridgebuilder): cross-adapter parity. The trust-store signed payload
# (now {schema_version, keys, revocations, trust_cutoff} per F9) MUST be
# byte-identical across adapters. Both bash and Python adapters delegate
# verification to audit-signing-helper.py so this test guards against future
# drift if a Python-only signing path is introduced.
# -----------------------------------------------------------------------------
@test "f9-parity: bash adapter verifies trust-store signed via fixture (Python)" {
    _sign_with_schema_version "$TRUST_STORE" "$TEST_DIR/root.priv" "1.0"
    # Bash adapter path: source audit-envelope.sh and call audit_trust_store_verify.
    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -eq 0 ]]
}

@test "f9-parity: Python adapter verifies trust-store signed via fixture" {
    _sign_with_schema_version "$TRUST_STORE" "$TEST_DIR/root.priv" "1.0"

    # Python adapter path: import loa_cheval and call audit_trust_store_verify.
    PYTHON_ADAPTER_DIR="$(cd "$BATS_TEST_FILENAME" && cd ../../../.claude/adapters && pwd 2>/dev/null || \
                          cd "$(dirname "$BATS_TEST_FILENAME")/../../.claude/adapters" && pwd)"
    [[ -d "$PYTHON_ADAPTER_DIR/loa_cheval" ]] || skip "loa_cheval adapter not found"

    run env PYTHONPATH="$PYTHON_ADAPTER_DIR" \
        LOA_PINNED_ROOT_PUBKEY_PATH="$LOA_PINNED_ROOT_PUBKEY_PATH" \
        python3 -c "
import sys
from loa_cheval.audit_envelope import audit_trust_store_verify
ok, msg = audit_trust_store_verify('$TRUST_STORE')
print(msg)
sys.exit(0 if ok else 1)
"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Defensive: missing schema_version in YAML body (but present in signed payload)
# fails — schema_version MUST be present and consistent.
# -----------------------------------------------------------------------------
@test "f9: trust-store missing schema_version field fails verification" {
    _sign_with_schema_version "$TRUST_STORE" "$TEST_DIR/root.priv" "1.0"

    # Strip schema_version line from the YAML body.
    sed -i.bak '/^schema_version: /d' "$TRUST_STORE"
    rm -f "$TRUST_STORE.bak"

    run audit_trust_store_verify "$TRUST_STORE"
    [[ "$status" -ne 0 ]]
}
