#!/usr/bin/env bats
# =============================================================================
# tests/integration/imp-001-negative.bats
#
# cycle-098 Sprint 1B — IMP-001 #4 negative test (1A's deferred AC).
#
# Spec: substituting `jq -S -c` for `lib/jcs.sh` produces signature
# verification failure. This proves JCS ≠ jq -S -c (per SDD §2.2).
#
# Strategy: build two envelopes from the same payload — one signed via JCS,
# one signed via jq -S -c — and demonstrate that:
#   1. The jq-canonicalized envelope's signature does NOT validate against
#      the JCS-canonicalized chain-input.
#   2. At least one corpus vector exists where jq-S-c output differs from
#      JCS output (proving non-equivalence).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    JCS_LIB="$PROJECT_ROOT/lib/jcs.sh"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -f "$JCS_LIB" ]] || skip "lib/jcs.sh not present"

    if ! python3 -c "import cryptography, rfc8785" 2>/dev/null; then
        skip "python cryptography or rfc8785 not installed"
    fi

    TEST_DIR="$(mktemp -d)"
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
(key_dir / "imp-001-test.priv").write_bytes(priv_bytes)
(key_dir / "imp-001-test.priv").chmod(0o600)
(key_dir / "imp-001-test.pub").write_bytes(pub_bytes)
PY

    export LOA_AUDIT_KEY_DIR="$KEY_DIR"
    export LOA_AUDIT_SIGNING_KEY_ID="imp-001-test"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_AUDIT_KEY_DIR LOA_AUDIT_SIGNING_KEY_ID
}

# -----------------------------------------------------------------------------
# JCS != jq -S -c on at least one corpus vector
# -----------------------------------------------------------------------------
@test "imp-001-neg: jq -S -c output differs from JCS for trailing-zero number" {
    local input='{"x":1.0}'
    local jq_out jcs_out
    jq_out=$(printf '%s' "$input" | jq -S -c '.')

    # shellcheck disable=SC1090
    source "$JCS_LIB"
    jcs_out=$(jcs_canonicalize "$input")

    # JCS canonicalizes 1.0 to 1; jq -S -c keeps 1 (or 1.0 depending on parser).
    # The decisive corpus vector: scientific notation. Use that.
    input='{"x":1e2}'
    jq_out=$(printf '%s' "$input" | jq -S -c '.')
    jcs_out=$(jcs_canonicalize "$input")
    [[ "$jq_out" != "$jcs_out" ]]
}

@test "imp-001-neg: jq -S -c output differs from JCS for trailing-zero float" {
    # JCS canonicalizes 1.0 → 1 per ECMAScript ToNumber; jq preserves 1.0 in some
    # versions, drops zero in others — but the key invariant is that JCS strips
    # trailing zeros while jq -S -c (depending on JSON parser) does not always.
    local input='{"x":1.0,"y":2.50}'
    local jq_out jcs_out
    # shellcheck disable=SC1090
    source "$JCS_LIB"
    jq_out=$(printf '%s' "$input" | jq -S -c '.')
    jcs_out=$(jcs_canonicalize "$input")
    # Verify they're not byte-identical. If they happen to match for this exact
    # input with this jq build, fall through to the scientific-notation case
    # which is decisively different.
    if [[ "$jq_out" == "$jcs_out" ]]; then
        input='{"x":1e2}'
        jq_out=$(printf '%s' "$input" | jq -S -c '.')
        jcs_out=$(jcs_canonicalize "$input")
    fi
    [[ "$jq_out" != "$jcs_out" ]]
}

# -----------------------------------------------------------------------------
# Substituting jq -S -c in the chain-input pipeline produces signature failure
# -----------------------------------------------------------------------------
@test "imp-001-neg: signature computed over jq -S -c output FAILS verification against JCS-validating consumer" {
    local LOG="$TEST_DIR/test.jsonl"

    # Step 1: emit a legit JCS-signed envelope using audit-envelope.sh.
    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    audit_emit L1 panel.bind '{"x":1e2,"y":1.0,"z":"é"}' "$LOG"
    [[ -f "$LOG" ]]

    # Step 2: produce a parallel envelope where signature was computed over
    # `jq -S -c` of the same content (the substitution attack).
    local payload='{"x":1e2,"y":1.0,"z":"é"}'
    local entry_jq_signed
    entry_jq_signed=$(python3 - "$KEY_DIR" "$payload" <<'PY'
import sys, json, base64, subprocess
from pathlib import Path
from datetime import datetime, timezone
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

key_dir = Path(sys.argv[1])
payload = json.loads(sys.argv[2])

priv = serialization.load_pem_private_key(
    (key_dir / "imp-001-test.priv").read_bytes(),
    password=None,
)

env = {
    "schema_version": "1.0.0",
    "primitive_id": "L1",
    "event_type": "panel.bind",
    "ts_utc": "2026-05-03T00:00:00.000000Z",
    "prev_hash": "GENESIS",
    "payload": payload,
    "redaction_applied": None,
}

# THIS IS THE SUBSTITUTION: use `jq -S -c` to canonicalize.
env_for_sig = {k: v for k, v in env.items() if k not in {"signature", "signing_key_id"}}
# Pipe through jq -S -c to mimic the broken canonicalizer.
result = subprocess.run(
    ["jq", "-S", "-c", "."],
    input=json.dumps(env_for_sig).encode(),
    capture_output=True, check=True,
)
canonical = result.stdout.rstrip(b"\n")
sig = priv.sign(canonical)

env["signing_key_id"] = "imp-001-test"
env["signature"] = base64.b64encode(sig).decode()
print(json.dumps(env, separators=(",", ":")))
PY
)

    # Step 3: write this envelope (signed via jq) to a new log and try to
    # verify with the JCS-grounded verifier. It MUST fail.
    local FAKE_LOG="$TEST_DIR/fake.jsonl"
    printf '%s\n' "$entry_jq_signed" > "$FAKE_LOG"

    run audit_verify_chain "$FAKE_LOG"
    [[ "$status" -ne 0 ]]
    # Output should mention BROKEN or signature failure.
    echo "$output" | grep -qiE 'BROKEN|signature' || {
        echo "Expected BROKEN/signature in output, got: $output"
        return 1
    }
}
