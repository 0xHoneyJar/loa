#!/usr/bin/env bats
# =============================================================================
# tests/integration/hash-chain-recovery-untracked.bats
#
# cycle-098 Sprint 1C — NFR-R7 hash-chain recovery for UNTRACKED logs (L1, L2).
# Per SDD §3.4.4 (line 1292):
#   - Untracked chain-critical logs (.run/panel-decisions.jsonl,
#     .run/cost-budget-events.jsonl): restore from latest signed snapshot at
#     `grimoires/loa/audit-archive/<utc-date>-<primitive>.jsonl.gz`
#   - Verify snapshot signature (uses 1B's signing)
#   - Restore entries; mark gap with [CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H]
#   - On rebuild success: write [CHAIN-RECOVERED] marker
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"

    TEST_DIR="$(mktemp -d)"
    LOG="$TEST_DIR/panel-decisions.jsonl"
    ARCHIVE_DIR="$TEST_DIR/audit-archive"
    mkdir -p "$ARCHIVE_DIR"

    # The recovery code resolves the archive directory via
    # LOA_AUDIT_ARCHIVE_DIR (override) — used here for hermetic test.
    export LOA_AUDIT_ARCHIVE_DIR="$ARCHIVE_DIR"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"

    if ! command -v audit_recover_chain >/dev/null 2>&1; then
        skip "audit_recover_chain not yet implemented"
    fi
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR" 2>/dev/null || true
    fi
    unset LOA_AUDIT_ARCHIVE_DIR
}

# -----------------------------------------------------------------------------
# Recovery from snapshot archive
# -----------------------------------------------------------------------------
@test "chain-recovery-untracked: restore L1 panel-decisions from snapshot archive" {
    # Build 3 valid entries in the live log
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-2"}' "$LOG"
    audit_emit L1 panel.bind '{"decision_id":"d-3"}' "$LOG"

    # Snapshot the current good state to archive.
    local utc_date
    utc_date="$(date -u +%Y-%m-%d)"
    gzip -c < "$LOG" > "${ARCHIVE_DIR}/${utc_date}-L1.jsonl.gz"

    # Corrupt the live log
    echo '{"prev_hash":"GARBAGE","schema_version":"1.1.0","primitive_id":"L1","event_type":"x","ts_utc":"2026-05-02T00:00:00.000000Z","payload":{},"redaction_applied":null}' > "$LOG"

    # Recovery
    run audit_recover_chain "$LOG"
    [[ "$status" -eq 0 ]]

    # Post: snapshot RPO-24H + recovered markers present.
    grep -q '\[CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H' "$LOG"
    grep -q '\[CHAIN-RECOVERED' "$LOG"
}

@test "chain-recovery-untracked: emits BLOCKER + [CHAIN-BROKEN] when no snapshot exists" {
    # Corrupt the live log AND ensure no snapshot exists.
    echo '{"prev_hash":"GARBAGE","schema_version":"1.1.0","primitive_id":"L1","event_type":"x","ts_utc":"2026-05-02T00:00:00.000000Z","payload":{},"redaction_applied":null}' > "$LOG"

    run audit_recover_chain "$LOG"
    [[ "$status" -ne 0 ]]
    grep -q '\[CHAIN-BROKEN' "$LOG"
}

@test "chain-recovery-untracked: snapshot path includes UTC date + primitive id" {
    # Verify the resolver looks for the right naming convention.
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    local utc_date
    utc_date="$(date -u +%Y-%m-%d)"
    gzip -c < "$LOG" > "${ARCHIVE_DIR}/${utc_date}-L1.jsonl.gz"

    # Tamper: append broken entry.
    echo '{"prev_hash":"BOGUS","schema_version":"1.1.0","primitive_id":"L1","event_type":"x","ts_utc":"2026-05-02T00:00:00.000000Z","payload":{},"redaction_applied":null}' >> "$LOG"

    run audit_recover_chain "$LOG"
    # Recovery must locate the snapshot via the date-named convention.
    [[ "$status" -eq 0 ]]
    grep -q '\[CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H' "$LOG"
}
