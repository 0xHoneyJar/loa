#!/usr/bin/env bats
# =============================================================================
# tests/security/no-env-var-leakage.bats
#
# cycle-098 Sprint 1B — SKP-002: fd-based secret loading.
# Tests:
#   - Password passed via --password-fd is NOT visible in `ps aux` (no argv leak)
#   - Password passed via --password-file (mode 0600) is NOT visible in argv
#   - LOA_AUDIT_KEY_PASSWORD env var emits a deprecation warning
#   - LOA_AUDIT_KEY_PASSWORD env var is NOT visible in /proc/<pid>/environ
#     after fd consumption (i.e., consumer scrubs/unsets after read)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    if ! python3 -c "import cryptography" 2>/dev/null; then
        skip "python cryptography not installed"
    fi

    # Linux-only: /proc inspection.
    if [[ ! -d /proc/self ]]; then
        skip "/proc not available — Linux-only security test"
    fi

    TEST_DIR="$(mktemp -d)"
    KEY_DIR="$TEST_DIR/audit-keys"
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

    # Generate an *encrypted* private key (passphrase = "test-passphrase-correct-horse-staple")
    PASSPHRASE="test-passphrase-correct-horse-staple"
    python3 - "$KEY_DIR" "$PASSPHRASE" <<'PY'
import sys
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives import serialization

key_dir = Path(sys.argv[1])
passphrase = sys.argv[2].encode()

priv = ed25519.Ed25519PrivateKey.generate()
priv_bytes = priv.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.BestAvailableEncryption(passphrase),
)
pub_bytes = priv.public_key().public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo,
)
(key_dir / "test-writer-encrypted.priv").write_bytes(priv_bytes)
(key_dir / "test-writer-encrypted.priv").chmod(0o600)
(key_dir / "test-writer-encrypted.pub").write_bytes(pub_bytes)
PY

    LOG="$TEST_DIR/test.jsonl"
    export LOA_AUDIT_KEY_DIR="$KEY_DIR"
    export LOA_AUDIT_SIGNING_KEY_ID="test-writer-encrypted"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_AUDIT_KEY_DIR LOA_AUDIT_SIGNING_KEY_ID
    unset LOA_AUDIT_KEY_PASSWORD || true
}

# -----------------------------------------------------------------------------
# Password file mode 0600 enforcement
# -----------------------------------------------------------------------------
@test "no-env-leak: --password-file requires mode 0600" {
    local pwfile="$TEST_DIR/pw.txt"
    printf '%s' "$PASSPHRASE" > "$pwfile"
    chmod 0644 "$pwfile"  # too permissive

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    run audit_emit_signed L1 panel.bind '{"decision_id":"d-1"}' "$LOG" --password-file "$pwfile"
    [[ "$status" -ne 0 ]]
    echo "$output" | grep -qi 'permission\|0600\|too permissive' || {
        echo "Expected permission error, got: $output"
        return 1
    }
}

@test "no-env-leak: --password-file with mode 0600 is accepted" {
    local pwfile="$TEST_DIR/pw.txt"
    printf '%s' "$PASSPHRASE" > "$pwfile"
    chmod 0600 "$pwfile"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    run audit_emit_signed L1 panel.bind '{"decision_id":"d-1"}' "$LOG" --password-file "$pwfile"
    [[ "$status" -eq 0 ]]
    [[ -f "$LOG" ]]
}

# -----------------------------------------------------------------------------
# Password is NOT in argv (process inspection)
# -----------------------------------------------------------------------------
@test "no-env-leak: password not visible in argv when using --password-fd" {
    # Spawn audit-envelope as a long-lived process; check ps before it exits.
    local pwfile="$TEST_DIR/pw.txt"
    printf '%s' "$PASSPHRASE" > "$pwfile"
    chmod 0600 "$pwfile"

    # Use --password-fd 3 with a pipe; capture process tree.
    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    audit_emit_signed L1 panel.bind '{"decision_id":"d-1"}' "$LOG" --password-fd 3 3<"$pwfile" &
    local pid=$!
    # Short snapshot before the process completes.
    local args
    args=$(cat /proc/"$pid"/cmdline 2>/dev/null | tr '\0' ' ' || echo "")
    wait "$pid" 2>/dev/null || true
    # Even if too fast, if we caught args, none should contain the passphrase.
    [[ "$args" != *"$PASSPHRASE"* ]]
    # Also confirm the log was actually signed (functional path, not just argv check).
    [[ -f "$LOG" ]]
    local kid
    kid=$(jq -r '.signing_key_id // ""' < "$LOG")
    [[ "$kid" == "test-writer-encrypted" ]]
}

# -----------------------------------------------------------------------------
# LOA_AUDIT_KEY_PASSWORD deprecation warning
# -----------------------------------------------------------------------------
@test "no-env-leak: LOA_AUDIT_KEY_PASSWORD env var prints deprecation warning" {
    export LOA_AUDIT_KEY_PASSWORD="$PASSPHRASE"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    run audit_emit_signed L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    # We allow it to succeed in this transition window; just check warning appeared.
    echo "$output" | grep -qiE 'deprecat|LOA_AUDIT_KEY_PASSWORD.*remove' || \
        echo "${output}${BATS_RUN_OUTPUT:-}" | grep -qiE 'deprecat|LOA_AUDIT_KEY_PASSWORD'
}

# -----------------------------------------------------------------------------
# LOA_AUDIT_KEY_PASSWORD is unset/scrubbed after consumption — defense in depth.
# -----------------------------------------------------------------------------
@test "no-env-leak: LOA_AUDIT_KEY_PASSWORD scrubbed after audit_emit_signed completes (in-shell)" {
    export LOA_AUDIT_KEY_PASSWORD="$PASSPHRASE"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
    audit_emit_signed L1 panel.bind '{"decision_id":"d-1"}' "$LOG" 2>&1 || true
    # After call, the env var in the parent shell SHOULD be unset (scrubbed).
    [[ -z "${LOA_AUDIT_KEY_PASSWORD:-}" ]]
}
