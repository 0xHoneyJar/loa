#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-trust-store-auto-verify.bats
#
# cycle-098 Sprint 1.5 hardening — issue #690 (L1 audit MED-2).
#
# audit_trust_store_verify exists and works (5/5 tests in
# trust-store-root-of-trust.bats) but is NOT invoked automatically from
# audit_verify_chain or audit_emit. Once an operator populates trust-store.yaml
# (post-bootstrap), runtime auto-verify becomes critical: an attacker who
# tampers trust-store.yaml (adds malicious writer pubkey + signs entries with
# the corresponding private key) is undetected at runtime.
#
# This test exercises:
#   1. BOOTSTRAP-PENDING: empty keys + empty signature → reads/writes permitted
#   2. VERIFIED: legitimately signed trust-store + populated keys → permitted
#   3. INVALID: tampered trust-store (non-empty keys, missing/bad signature)
#      → audit_emit + audit_verify_chain refuse with [TRUST-STORE-INVALID]
#   4. mtime cache invalidation: change trust-store mtime → re-verify on next call
#   5. No trust-store file (graceful fallback to BOOTSTRAP-PENDING)
#
# Acceptance criteria from issue #690:
#   - audit_verify_chain auto-calls audit_trust_store_verify once per process
#   - Trust-store substitution test: tamper trust-store.yaml; chain ops fail
#   - BOOTSTRAP-PENDING state still permits reads/writes (graceful fallback)
#   - Cached verify result invalidated on trust-store mtime change
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    PYTHON_ADAPTER_DIR="$PROJECT_ROOT/.claude/adapters"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -d "$PYTHON_ADAPTER_DIR/loa_cheval" ]] || skip "loa_cheval not present"
    if ! python3 -c "import cryptography, yaml, rfc8785" 2>/dev/null; then
        skip "python cryptography + yaml + rfc8785 required"
    fi

    TEST_DIR="$(mktemp -d)"
    PINNED_PUBKEY="$TEST_DIR/pinned-root-pubkey.txt"
    LOG="$TEST_DIR/test.jsonl"

    # Generate root + imposter keypairs (mirrors trust-store-root-of-trust.bats).
    python3 - "$TEST_DIR" <<'PY'
import sys
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

import shutil
shutil.copy(td / "root.pub", td / "pinned-root-pubkey.txt")
PY

    export LOA_PINNED_ROOT_PUBKEY_PATH="$PINNED_PUBKEY"
    export PYTHONPATH="$PYTHON_ADAPTER_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_PINNED_ROOT_PUBKEY_PATH LOA_TRUST_STORE_FILE PYTHONPATH
}

# Helper: write a BOOTSTRAP-PENDING trust-store (empty keys + empty signature).
_bootstrap_pending_trust_store() {
    local out_path="$1"
    cat > "$out_path" <<'EOF'
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
}

# Helper: write a legitimately signed trust-store with NO populated keys.
_signed_empty_trust_store() {
    local out_path="$1"
    local signer_priv="$2"
    python3 - "$out_path" "$signer_priv" <<'PY'
import sys, base64
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
import rfc8785

out = Path(sys.argv[1])
priv = serialization.load_pem_private_key(Path(sys.argv[2]).read_bytes(), password=None)
pub_pem = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
).decode()

# Sprint 1.5 (#695 F9): schema_version IS in the signed payload.
core = {
    "schema_version": "1.0",
    "keys": [],
    "revocations": [],
    "trust_cutoff": {"default_strict_after": "2026-05-02T00:00:00Z"},
}
sig_b64 = base64.b64encode(priv.sign(rfc8785.dumps(core))).decode()

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

# Helper: write a legitimately signed trust-store WITH a populated key.
_signed_populated_trust_store() {
    local out_path="$1"
    local signer_priv="$2"
    python3 - "$out_path" "$signer_priv" <<'PY'
import sys, base64
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization
import rfc8785

out = Path(sys.argv[1])
priv = serialization.load_pem_private_key(Path(sys.argv[2]).read_bytes(), password=None)
pub_pem = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
).decode()

# Generate a writer key and add to populated trust-store.
writer = ed25519.Ed25519PrivateKey.generate()
writer_pub_pem = writer.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
).decode()

keys = [{
    "writer_id": "test-writer-1",
    "operator_id": "test-operator",
    "pubkey_pem": writer_pub_pem,
    "valid_from": "2026-05-03T00:00:00Z",
    "valid_until": None,
}]

# Sprint 1.5 (#695 F9): schema_version IS in the signed payload.
core = {
    "schema_version": "1.0",
    "keys": keys,
    "revocations": [],
    "trust_cutoff": {"default_strict_after": "2026-05-02T00:00:00Z"},
}
sig_b64 = base64.b64encode(priv.sign(rfc8785.dumps(core))).decode()

# Hand-write YAML to keep field order stable.
def _yaml_indent(s, n=4):
    return chr(10).join((" " * n) + line for line in s.strip().split(chr(10)))

yaml_text = f"""---
schema_version: "1.0"
root_signature:
  algorithm: ed25519
  signer_pubkey: |
{_yaml_indent(pub_pem)}
  signed_at: "2026-05-03T00:00:00Z"
  signature: "{sig_b64}"
keys:
  - writer_id: "test-writer-1"
    operator_id: "test-operator"
    pubkey_pem: |
{_yaml_indent(writer_pub_pem, 6)}
    valid_from: "2026-05-03T00:00:00Z"
    valid_until: null
revocations: []
trust_cutoff:
  default_strict_after: "2026-05-02T00:00:00Z"
"""
out.write_text(yaml_text)
PY
}

# -----------------------------------------------------------------------------
# BOOTSTRAP-PENDING: empty keys + empty signature → reads/writes permitted
# -----------------------------------------------------------------------------
@test "auto-verify: BOOTSTRAP-PENDING permits audit_emit (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -eq 0 ]]
    [[ -f "$LOG" ]]
    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq 1 ]]
}

@test "auto-verify: BOOTSTRAP-PENDING permits audit_verify_chain (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"OK 2 entries"* ]]
}

@test "auto-verify: BOOTSTRAP-PENDING permits audit_emit (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"

    run python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# No trust-store file → BOOTSTRAP-PENDING (graceful fallback)
# -----------------------------------------------------------------------------
@test "auto-verify: missing trust-store file is treated as BOOTSTRAP-PENDING (bash)" {
    export LOA_TRUST_STORE_FILE="$TEST_DIR/nonexistent.yaml"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Tampered trust-store (substitution attack)
# -----------------------------------------------------------------------------
@test "auto-verify: trust-store substitution (signed by imposter) blocks audit_emit (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER, got: $output"
        return 1
    }
}

@test "auto-verify: trust-store substitution (signed by imposter) blocks audit_verify_chain (bash)" {
    # First write the log under a permissive bootstrap-pending trust-store.
    TS="$TEST_DIR/trust-store.yaml"
    _bootstrap_pending_trust_store "$TS"
    export LOA_TRUST_STORE_FILE="$TS"
    source "$AUDIT_ENVELOPE"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"

    # Now replace trust-store with imposter-signed populated trust-store.
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"

    # Ensure the cache is invalidated by mtime bump.
    touch -d "1 second" "$TS"

    # Fresh shell so cache is empty.
    run bash -c "
        source '$AUDIT_ENVELOPE'
        export LOA_TRUST_STORE_FILE='$TS'
        export LOA_PINNED_ROOT_PUBKEY_PATH='$LOA_PINNED_ROOT_PUBKEY_PATH'
        audit_verify_chain '$LOG' 2>&1
    "
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER, got: $output"
        return 1
    }
}

@test "auto-verify: trust-store substitution blocks audit_emit (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    run python3 -c "
import sys
from loa_cheval.audit_envelope import audit_emit
try:
    audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
    sys.exit(0)
except RuntimeError as e:
    print(f'BLOCKED: {e}')
    sys.exit(1)
"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER, got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Legitimately signed populated trust-store → audit_emit succeeds
# -----------------------------------------------------------------------------
@test "auto-verify: legitimately signed populated trust-store permits audit_emit (bash)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -eq 0 ]]
}

@test "auto-verify: legitimately signed populated trust-store permits audit_emit (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    run python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# mtime cache invalidation
# -----------------------------------------------------------------------------
@test "auto-verify: mtime change invalidates cache (bash, single-process)" {
    TS="$TEST_DIR/trust-store.yaml"
    # Start with valid signed trust-store.
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    source "$AUDIT_ENVELOPE"
    # First call: caches VERIFIED.
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"

    # Tamper trust-store: replace with imposter-signed populated trust-store.
    sleep 0.05  # ensure mtime changes (filesystem granularity)
    _signed_populated_trust_store "$TS" "$TEST_DIR/imposter.priv"
    touch "$TS"  # ensure mtime bumps even if writes too fast

    # Second call: cache should be invalidated; auto-verify should fire and FAIL.
    run audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER after mtime change, got: $output"
        return 1
    }
}

@test "auto-verify: mtime change invalidates cache (Python, single-process)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    # Single Python process: emit, tamper, emit again.
    run python3 -c "
import sys, time, os, subprocess
from pathlib import Path
from loa_cheval.audit_envelope import audit_emit

ts_path = '$TS'
log_path = '$LOG'

# 1. First emit: valid trust-store; should succeed.
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, log_path)

# 2. Tamper: replace with imposter-signed.
time.sleep(0.05)
subprocess.run(['bash', '-c', '''
$(declare -f _signed_populated_trust_store)
_signed_populated_trust_store \"\$1\" \"\$2\"
''', '_', ts_path, '$TEST_DIR/imposter.priv'], check=True, env={
    **os.environ,
    'PATH': os.environ.get('PATH', ''),
})
Path(ts_path).touch()

# 3. Second emit: should FAIL due to mtime cache invalidation.
try:
    audit_emit('L1', 'panel.bind', {'decision_id': 'd-2'}, log_path)
    print('UNEXPECTED: second emit succeeded')
    sys.exit(0)
except RuntimeError as e:
    print(f'BLOCKED: {e}')
    sys.exit(1)
"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qE 'TRUST-STORE-INVALID|ROOT-PUBKEY-DIVERGENCE' || {
        echo "Expected [TRUST-STORE-INVALID] BLOCKER after mtime change, got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Cache hit: same mtime → no re-verification (smoke test for caching presence)
# -----------------------------------------------------------------------------
@test "auto-verify: cached result reused within same process (Python)" {
    TS="$TEST_DIR/trust-store.yaml"
    _signed_populated_trust_store "$TS" "$TEST_DIR/root.priv"
    export LOA_TRUST_STORE_FILE="$TS"

    # Two emits in same Python process; both must succeed AND second must
    # be faster (or at least not slower than re-verify cost). We don't time;
    # we just verify both work.
    run python3 -c "
from loa_cheval.audit_envelope import audit_emit
audit_emit('L1', 'panel.bind', {'decision_id': 'd-1'}, '$LOG')
audit_emit('L1', 'panel.bind', {'decision_id': 'd-2'}, '$LOG')
audit_emit('L1', 'panel.bind', {'decision_id': 'd-3'}, '$LOG')
"
    [[ "$status" -eq 0 ]]
    local lines
    lines=$(wc -l < "$LOG")
    [[ "$lines" -eq 3 ]]
}
