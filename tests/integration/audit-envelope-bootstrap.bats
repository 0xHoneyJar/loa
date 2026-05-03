#!/usr/bin/env bats
# =============================================================================
# tests/integration/audit-envelope-bootstrap.bats
#
# cycle-098 Sprint 1 review remediation — IMP-003 #1.
#
# When LOA_AUDIT_SIGNING_KEY_ID is set but the key file does not exist (e.g.,
# bootstrap-pending state), audit signing must exit 78 (EX_CONFIG) so callers
# can distinguish "operator hasn't bootstrapped keys yet" from generic errors.
#
# The error stderr message must include [BOOTSTRAP-PENDING] for operator triage.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    SIGNING_HELPER="$PROJECT_ROOT/.claude/scripts/lib/audit-signing-helper.py"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -f "$SIGNING_HELPER" ]] || skip "audit-signing-helper.py not present"

    if ! python3 -c "import cryptography" 2>/dev/null; then
        skip "python cryptography not installed"
    fi

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/test.jsonl"
    KEY_DIR="$TEST_DIR/audit-keys-empty"
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"

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
    export LOA_AUDIT_KEY_DIR="$KEY_DIR"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        find "$TEST_DIR" -type d -empty -delete 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE LOA_AUDIT_KEY_DIR LOA_AUDIT_SIGNING_KEY_ID
}

# -----------------------------------------------------------------------------
# IMP-003 #1: missing key → exit 78
# -----------------------------------------------------------------------------

@test "bootstrap: signing helper exits 78 when key file is missing" {
    run python3 "$SIGNING_HELPER" sign --key-id missing-writer --key-dir "$KEY_DIR"
    [[ "$status" -eq 78 ]]
    [[ "$output" == *"BOOTSTRAP-PENDING"* ]] || [[ "$output" == *"private key not found"* ]]
}

@test "bootstrap: error message hints at runbook location" {
    run python3 "$SIGNING_HELPER" sign --key-id missing-writer --key-dir "$KEY_DIR"
    [[ "$output" == *"audit-keys-bootstrap"* ]]
}

@test "bootstrap: audit_emit propagates non-zero when signing fails (key missing)" {
    export LOA_AUDIT_SIGNING_KEY_ID="missing-writer"
    source "$AUDIT_ENVELOPE"
    # audit_emit calls _audit_sign_stdin which invokes the helper. Helper exits 78.
    # audit_emit should propagate non-zero (it returns 1 on signing failure today;
    # whichever non-zero is fine — the contract is that the chain doesn't get a
    # bad entry).
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -ne 0 ]]
    # The log file must NOT exist (or be empty) when signing failed.
    if [[ -f "$LOG" ]]; then
        [[ ! -s "$LOG" ]]
    fi
}
