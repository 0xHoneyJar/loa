#!/usr/bin/env bats
# =============================================================================
# audit-snapshot.bats — Sprint 2C
#
# Daily snapshot writer for L1/L2 chain-critical UNTRACKED logs (RPO 24h
# per SDD §3.4.4 ↔ §3.7 reconciliation).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    TEST_DIR="$(mktemp -d)"
    LOGS_DIR="${TEST_DIR}/logs"
    ARCHIVE_DIR="${TEST_DIR}/archive"
    POLICY="${TEST_DIR}/retention-policy.yaml"
    mkdir -p "$LOGS_DIR" "$ARCHIVE_DIR"

    # Minimal policy for tests: L1 + L2 chain-critical, L3 not.
    cat > "$POLICY" <<'YAML'
schema_version: "1.0"
primitives:
  L1:
    log_basename: "panel-decisions.jsonl"
    chain_critical: true
    git_tracked: false
  L2:
    log_basename: "cost-budget-events.jsonl"
    chain_critical: true
    git_tracked: false
  L3:
    log_basename: "cycles.jsonl"
    chain_critical: false
    git_tracked: false
  L4:
    log_basename: "trust-ledger.jsonl"
    chain_critical: true
    git_tracked: true
YAML

    SNAPSHOT_SCRIPT="${REPO_ROOT}/.claude/scripts/audit/audit-snapshot.sh"
    INSTALL_SCRIPT="${REPO_ROOT}/.claude/scripts/audit/audit-snapshot-install.sh"
    chmod +x "$SNAPSHOT_SCRIPT" "$INSTALL_SCRIPT" 2>/dev/null || true

    export LOA_AUDIT_VERIFY_SIGS=0
    export LOA_AUDIT_SNAPSHOT_TEST_DAY="2026-05-04"
    unset LOA_AUDIT_SIGNING_KEY_ID

    # Seed L1 + L2 logs with a couple of envelopes each (chain-intact).
    write_envelope() {
        local file="$1"
        local pid="$2"
        local etype="$3"
        local ts="$4"
        local prev="$5"
        local payload="$6"
        printf '%s\n' "$(jq -nc \
            --arg pid "$pid" --arg et "$etype" --arg ts "$ts" --arg ph "$prev" \
            --argjson payload "$payload" \
            '{schema_version:"1.1.0",primitive_id:$pid,event_type:$et,ts_utc:$ts,prev_hash:$ph,payload:$payload,redaction_applied:null}')" \
            >> "$file"
    }
    L1_LOG="${LOGS_DIR}/panel-decisions.jsonl"
    L2_LOG="${LOGS_DIR}/cost-budget-events.jsonl"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Helper: produce a 2-entry chain-intact JSONL log.
seed_chain() {
    local file="$1"
    local pid="$2"
    # Compute a realistic prev_hash for entry 2.
    source "${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    # Entry 1.
    local e1_payload='{"foo":"bar"}'
    local e1
    e1="$(jq -nc \
        --arg pid "$pid" --arg et "test.event" --arg ts "2026-05-04T10:00:00.000000Z" \
        --argjson p "$e1_payload" \
        '{schema_version:"1.1.0",primitive_id:$pid,event_type:$et,ts_utc:$ts,prev_hash:"GENESIS",payload:$p,redaction_applied:null}')"
    printf '%s\n' "$e1" > "$file"
    local hash2
    hash2="$(_audit_chain_input "$e1" | _audit_sha256)"
    local e2_payload='{"foo":"baz"}'
    local e2
    e2="$(jq -nc \
        --arg pid "$pid" --arg et "test.event" --arg ts "2026-05-04T10:01:00.000000Z" \
        --arg ph "$hash2" --argjson p "$e2_payload" \
        '{schema_version:"1.1.0",primitive_id:$pid,event_type:$et,ts_utc:$ts,prev_hash:$ph,payload:$p,redaction_applied:null}')"
    printf '%s\n' "$e2" >> "$file"
}

# -----------------------------------------------------------------------------
# snapshot writer
# -----------------------------------------------------------------------------
@test "snapshot: writes <date>-L1.jsonl.gz and <date>-L2.jsonl.gz from logs" {
    seed_chain "$L1_LOG" L1
    seed_chain "$L2_LOG" L2

    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR"
    [[ "$status" -eq 0 ]]
    [[ -f "${ARCHIVE_DIR}/2026-05-04-L1.jsonl.gz" ]]
    [[ -f "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" ]]
}

@test "snapshot: archive content gunzip-equal to source log" {
    seed_chain "$L2_LOG" L2
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR" --primitive L2
    [[ "$status" -eq 0 ]]
    diff <(gzip -dc "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz") "$L2_LOG"
}

@test "snapshot: idempotent — same UTC day re-run does not overwrite" {
    seed_chain "$L2_LOG" L2
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR" --primitive L2
    [[ "$status" -eq 0 ]]
    local mtime1
    mtime1="$(stat -c '%Y' "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" 2>/dev/null || stat -f '%m' "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz")"
    sleep 1
    # Append a new entry — re-run should NOT overwrite (idempotent same-day).
    seed_chain "$L2_LOG" L2  # appends another two entries, log now has 4 lines (chain breaks; that's OK for this test)
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR" --primitive L2
    [[ "$status" -eq 0 ]]
    local mtime2
    mtime2="$(stat -c '%Y' "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" 2>/dev/null || stat -f '%m' "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz")"
    [[ "$mtime1" -eq "$mtime2" ]]
}

@test "snapshot: dry-run writes nothing" {
    seed_chain "$L2_LOG" L2
    run "$SNAPSHOT_SCRIPT" --dry-run --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR"
    [[ "$status" -eq 0 ]]
    [[ ! -f "${ARCHIVE_DIR}/2026-05-04-L1.jsonl.gz" ]]
    [[ ! -f "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" ]]
}

@test "snapshot: refuses broken chain — emits ERROR, exit non-zero" {
    # L2 log with mismatched prev_hash on entry 2.
    cat > "$L2_LOG" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"test.event","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"foo":"bar"},"redaction_applied":null}
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"test.event","ts_utc":"2026-05-04T10:01:00.000000Z","prev_hash":"deadbeef","payload":{"foo":"baz"},"redaction_applied":null}
EOF
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR" --primitive L2
    [[ "$status" -eq 1 ]]
    [[ ! -f "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" ]]
}

@test "snapshot: skips primitive whose source log is missing" {
    seed_chain "$L1_LOG" L1
    # No L2 log seeded.
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR"
    [[ "$status" -eq 0 ]]
    [[ -f "${ARCHIVE_DIR}/2026-05-04-L1.jsonl.gz" ]]
    [[ ! -f "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" ]]
}

@test "snapshot: skips primitives with chain_critical=false (L3)" {
    # Seed an L3 log; should be ignored by the snapshot writer.
    L3_LOG="${LOGS_DIR}/cycles.jsonl"
    seed_chain "$L3_LOG" L3
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR"
    [[ "$status" -eq 0 ]]
    [[ ! -f "${ARCHIVE_DIR}/2026-05-04-L3.jsonl.gz" ]]
}

@test "snapshot: skips primitives with git_tracked=true (L4)" {
    L4_LOG="${LOGS_DIR}/trust-ledger.jsonl"
    seed_chain "$L4_LOG" L4
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR"
    [[ "$status" -eq 0 ]]
    [[ ! -f "${ARCHIVE_DIR}/2026-05-04-L4.jsonl.gz" ]]
}

@test "snapshot: --primitive L1 only writes L1 archive even when L2 also has log" {
    seed_chain "$L1_LOG" L1
    seed_chain "$L2_LOG" L2
    run "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR" --primitive L1
    [[ "$status" -eq 0 ]]
    [[ -f "${ARCHIVE_DIR}/2026-05-04-L1.jsonl.gz" ]]
    [[ ! -f "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" ]]
}

# -----------------------------------------------------------------------------
# Recovery integration: snapshot → audit_recover_chain restore
# -----------------------------------------------------------------------------
@test "recovery: audit_recover_chain reads our snapshot and restores chain" {
    seed_chain "$L2_LOG" L2
    "$SNAPSHOT_SCRIPT" --policy "$POLICY" --logs-dir "$LOGS_DIR" --archive-dir "$ARCHIVE_DIR" --primitive L2 >/dev/null
    [[ -f "${ARCHIVE_DIR}/2026-05-04-L2.jsonl.gz" ]]

    # Corrupt the rolling log: tamper with entry 2's prev_hash (chain breaks).
    cat > "$L2_LOG" <<'EOF'
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"test.event","ts_utc":"2026-05-04T10:00:00.000000Z","prev_hash":"GENESIS","payload":{"foo":"bar"},"redaction_applied":null}
{"schema_version":"1.1.0","primitive_id":"L2","event_type":"test.event","ts_utc":"2026-05-04T10:01:00.000000Z","prev_hash":"deadbeef","payload":{"foo":"baz"},"redaction_applied":null}
EOF

    # Invoke audit_recover_chain — chain is broken, should locate snapshot and restore.
    source "${REPO_ROOT}/.claude/scripts/audit-envelope.sh"
    LOA_AUDIT_ARCHIVE_DIR="$ARCHIVE_DIR" run audit_recover_chain "$L2_LOG"
    [[ "$status" -eq 0 ]]

    # Restored log should contain recovery markers.
    grep -q "CHAIN-RECOVERED source=snapshot_archive" "$L2_LOG"
    grep -q "CHAIN-GAP-RESTORED-FROM-SNAPSHOT-RPO-24H" "$L2_LOG"
}

# -----------------------------------------------------------------------------
# Install helper
# -----------------------------------------------------------------------------
@test "snapshot install: 'show' produces expected cron line at 04:00 UTC default" {
    run "$INSTALL_SCRIPT" show
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"0 4 * * *"* ]]
    [[ "$output" =~ "loa-cycle098-audit-snapshot" ]]
    [[ "$output" =~ "audit-snapshot.sh" ]]
}

@test "snapshot install: respects configured cron_expression" {
    local config
    config="${TEST_DIR}/loa.config.yaml"
    cat > "$config" <<'EOF'
audit_snapshot:
  cron_expression: "30 3 * * *"
EOF
    LOA_BUDGET_CONFIG_FILE="$config" run "$INSTALL_SCRIPT" show
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"30 3 * * *"* ]]
}

@test "snapshot install: rejects malformed cron expression" {
    local config
    config="${TEST_DIR}/loa.config.yaml"
    cat > "$config" <<'EOF'
audit_snapshot:
  cron_expression: "not a cron"
EOF
    LOA_BUDGET_CONFIG_FILE="$config" run "$INSTALL_SCRIPT" show
    [[ "$status" -ne 0 ]]
}
