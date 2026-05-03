#!/usr/bin/env bats
# =============================================================================
# tests/integration/hash-chain-recovery-tracked.bats
#
# cycle-098 Sprint 1C — NFR-R7 hash-chain recovery for TRACKED logs (L4, L6).
# Per SDD §3.4.4 (line 1292):
#   - Tracked logs (L4 trust-ledger.jsonl, L6 INDEX.md): rebuild from
#     `git log -p <log_file>`
#   - Locate most recent valid chain state
#   - Mark broken segment with [CHAIN-GAP-RECOVERED-FROM-GIT]
#   - On rebuild success: write [CHAIN-RECOVERED] marker; resume normal chain
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    # Build a hermetic git repo so we can simulate the tracked-log path.
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"

    LOG="$TEST_DIR/trust-ledger.jsonl"

    # F1 isolation: permissive trust-store so unsigned 1C-style writes pass.
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

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"

    # Sprint 1C function must exist.
    if ! command -v audit_recover_chain >/dev/null 2>&1; then
        skip "audit_recover_chain not yet implemented"
    fi
}

teardown() {
    cd /
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR" 2>/dev/null || true
    fi
    unset LOA_TRUST_STORE_FILE
}

# Helper: emit an entry and commit it.
_emit_and_commit() {
    local payload="$1"
    audit_emit L4 trust.transition "$payload" "$LOG"
    git add "$LOG"
    git -c commit.gpgsign=false commit -q -m "ledger entry: $payload" --no-verify
}

# -----------------------------------------------------------------------------
# Recovery from git history when the file is corrupted
# -----------------------------------------------------------------------------
@test "chain-recovery-tracked: rebuild L4 ledger after deletion using git history" {
    _emit_and_commit '{"scope":"s1","tier":"verified"}'
    _emit_and_commit '{"scope":"s2","tier":"verified"}'
    _emit_and_commit '{"scope":"s3","tier":"verified"}'

    # Pre-conditions: 3 entries, chain is valid.
    [[ "$(wc -l < "$LOG")" -eq 3 ]]
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]

    # Corrupt: append a tampered entry that breaks the chain.
    printf '{"schema_version":"1.1.0","primitive_id":"L4","event_type":"x","ts_utc":"2026-05-02T00:00:00.000000Z","prev_hash":"BOGUS","payload":{},"redaction_applied":null}\n' >> "$LOG"

    # Verify breaks
    run audit_verify_chain "$LOG"
    [[ "$status" -ne 0 ]]

    # Recover from git history
    run audit_recover_chain "$LOG"
    [[ "$status" -eq 0 ]]

    # Post-conditions: log should have a [CHAIN-GAP-RECOVERED-FROM-GIT] marker
    # AND a [CHAIN-RECOVERED] marker.
    grep -q '\[CHAIN-GAP-RECOVERED-FROM-GIT' "$LOG"
    grep -q '\[CHAIN-RECOVERED' "$LOG"
}

@test "chain-recovery-tracked: rebuilt log re-validates after recovery" {
    _emit_and_commit '{"scope":"s1","tier":"verified"}'
    _emit_and_commit '{"scope":"s2","tier":"verified"}'
    _emit_and_commit '{"scope":"s3","tier":"verified"}'

    # Tamper: replace last line with garbage
    head -n 2 "$LOG" > "${LOG}.tmp"
    echo '{"prev_hash":"GARBAGE","schema_version":"1.1.0","primitive_id":"L4","event_type":"x","ts_utc":"2026-05-02T00:00:00.000000Z","payload":{},"redaction_applied":null}' >> "${LOG}.tmp"
    mv "${LOG}.tmp" "$LOG"

    # Recover
    audit_recover_chain "$LOG"

    # The recovered chain should now validate (skipping markers).
    run audit_verify_chain "$LOG"
    [[ "$status" -eq 0 ]]
}

@test "chain-recovery-tracked: emits BLOCKER + [CHAIN-BROKEN] when no valid git state" {
    # No commits; nothing in git history. Make a corrupt file with no recovery path.
    echo "garbage" > "$LOG"

    run audit_recover_chain "$LOG"
    # Recovery fails — exit non-zero, [CHAIN-BROKEN] marker written.
    [[ "$status" -ne 0 ]]
    grep -q '\[CHAIN-BROKEN' "$LOG"
}
