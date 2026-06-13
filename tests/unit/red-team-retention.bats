#!/usr/bin/env bats
# =============================================================================
# tests/unit/red-team-retention.bats — sprint-bug-210 / #1025 sweep leg 2
#
# red-team-retention.sh previously had ZERO tests. The KF-004-class defect
# pinned here: a corrupt rt-*-result.json yielded empty timestamp via the
# `jq … || echo` swallow, the purge loop silently SKIPPED the file, and
# expired RESTRICTED red-team material was retained indefinitely past policy.
#
# Post-fix contract (most-restrictive disposition, per the sprint-bug-208
# audit recommendation; quarantine rejected — see triage.md):
#   - unparseable result JSON → treat as RESTRICTED, age by file mtime
#   - expired → purged with siblings + audit PARSE-FAILURE/PURGED entries
#   - young   → retained with loud WARN (still counts as degraded run)
#   - any conservative disposition → exit 3 (documented)
#   - --dry-run never deletes; reports WOULD-disposition
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    export TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/red-team-retention-test-$$"
    mkdir -p "$TEST_TMPDIR/.claude/scripts" "$TEST_TMPDIR/.run/red-team"
    cp "$PROJECT_ROOT/.claude/scripts/red-team-retention.sh" "$TEST_TMPDIR/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/compat-lib.sh" "$TEST_TMPDIR/.claude/scripts/"
    chmod +x "$TEST_TMPDIR/.claude/scripts/red-team-retention.sh"
    RT="$TEST_TMPDIR/.run/red-team"
    AUDIT="$TEST_TMPDIR/.run/red-team-audit.log"
    SCRIPT="$TEST_TMPDIR/.claude/scripts/red-team-retention.sh"
    REAL_DATE="$(command -v date)"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

_old_date() { date -u -d "60 days ago" +%Y-%m-%dT%H:%M:%SZ; }

@test "KF-004 guard: corrupt result + aged mtime → purged, audited, exit 3 (T-B1)" {
    printf 'not json at all' > "$RT/rt-aaa-result.json"
    printf 'sibling report' > "$RT/rt-aaa-report.md"
    touch -d "60 days ago" "$RT/rt-aaa-result.json"
    run "$SCRIPT"
    [ "$status" -eq 3 ]
    [ ! -f "$RT/rt-aaa-result.json" ]
    [ ! -f "$RT/rt-aaa-report.md" ]
    grep -qi "PARSE-FAILURE" "$AUDIT"
    grep -qi "PURGED" "$AUDIT"
}

@test "KF-004 guard: corrupt result + young mtime → retained with loud WARN, exit 3 (T-B2)" {
    printf '{broken' > "$RT/rt-bbb-result.json"
    run "$SCRIPT"
    [ "$status" -eq 3 ]
    [ -f "$RT/rt-bbb-result.json" ]
    grep -qi "PARSE-FAILURE" "$AUDIT"
}

@test "regression pin: valid RESTRICTED expired → purged, exit 0 (T-B3)" {
    cat > "$RT/rt-ccc-result.json" <<EOF
{"run_id": "rt-ccc", "timestamp": "$(_old_date)", "classification": "RESTRICTED"}
EOF
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -f "$RT/rt-ccc-result.json" ]
    grep -q "PURGED: rt-ccc" "$AUDIT"
}

@test "KF-004 guard: valid JSON missing timestamp → conservative disposition, loud, exit 3 (T-B4)" {
    # Pre-fix: silently skipped forever (indefinite retention). Post-fix:
    # mtime-age fallback under the most-restrictive classification.
    printf '{"run_id": "rt-ddd", "classification": "INTERNAL"}' > "$RT/rt-ddd-result.json"
    touch -d "60 days ago" "$RT/rt-ddd-result.json"
    run "$SCRIPT"
    [ "$status" -eq 3 ]
    # 60d > 30d RESTRICTED limit (conservative) → purged despite INTERNAL claim
    [ ! -f "$RT/rt-ddd-result.json" ]
    grep -qiE "conservative|no usable timestamp|PARSE-FAILURE" "$AUDIT"
}

@test "KF-004 guard: --dry-run with corrupt file → no deletion, WOULD-disposition reported (T-B5)" {
    printf 'garbage' > "$RT/rt-eee-result.json"
    touch -d "60 days ago" "$RT/rt-eee-result.json"
    run "$SCRIPT" --dry-run
    [ "$status" -eq 3 ]
    [ -f "$RT/rt-eee-result.json" ]
    [[ "$output" == *"WOULD PURGE"* ]]
}

@test "portability: valid timestamp parses without GNU date -d → not conservative (T-B6, DISS-002)" {
    # DISS-002: a -d-rejecting `date` (simulating macOS/BSD) must NOT push a
    # valid-timestamp report onto the conservative RESTRICTED-by-mtime path.
    # Pins that timestamp parsing routes through compat-lib _date_to_epoch
    # (GNU/BSD/perl tiers), not raw `date -d`.
    local shim="$TEST_TMPDIR/shim"
    mkdir -p "$shim"
    cat > "$shim/date" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == "-d" ]] && exit 1; done
exec "$REAL_DATE" "\$@"
EOF
    chmod +x "$shim/date"
    # Valid INTERNAL report, well within 90d retention → must RETAIN, exit 0,
    # and NOT be marked conservative (no PARSE-FAILURE/CONSERVATIVE audit).
    cat > "$RT/rt-fff-result.json" <<EOF
{"run_id": "rt-fff", "timestamp": "$("$REAL_DATE" -u -d "5 days ago" +%Y-%m-%dT%H:%M:%SZ)", "classification": "INTERNAL"}
EOF
    PATH="$shim:$PATH" run "$SCRIPT" --verbose
    [ "$status" -eq 0 ]
    [ -f "$RT/rt-fff-result.json" ]
    # A correctly-parsed valid timestamp triggers no conservative disposition
    # and no purge → audit() is never called → the audit log may not exist at
    # all. Either way, there must be zero CONSERVATIVE/PARSE-FAILURE entries.
    if [[ -f "$AUDIT" ]]; then
        ! grep -qiE "CONSERVATIVE|PARSE-FAILURE" "$AUDIT"
    fi
}

@test "dep-guard: missing compat-lib (jq_strict undefined) → abort exit 2, no purge (T-B7, DISS-001 iter-3)" {
    # A MISSING dependency must not be treated like a corrupt data file —
    # otherwise every report hits the conservative path and valid material is
    # mass-purged. Remove the co-located helper to simulate the broken env.
    rm -f "$TEST_TMPDIR/.claude/scripts/compat-lib.sh"
    cat > "$RT/rt-ggg-result.json" <<EOF
{"run_id": "rt-ggg", "timestamp": "$(_old_date)", "classification": "RESTRICTED"}
EOF
    run "$SCRIPT"
    [ "$status" -eq 2 ]
    # The aged-but-VALID report must survive a dependency failure
    [ -f "$RT/rt-ggg-result.json" ]
    [[ "$output" == *"dependencies unavailable"* || "$output" == *"FATAL"* ]]
}

@test "AUDIT-2: future timestamp → conservative RESTRICTED, not indefinite retention (T-B8)" {
    # A far-future .timestamp makes age negative → retained forever. Must be
    # treated as suspicious (conservative RESTRICTED + mtime age), exit 3.
    local future
    future=$(date -u -d "+5 years" +%Y-%m-%dT%H:%M:%SZ)
    cat > "$RT/rt-future-result.json" <<EOF
{"run_id": "rt-future", "timestamp": "$future", "classification": "RESTRICTED"}
EOF
    # mtime now → young → retained with WARN (not purged), but flagged conservative + exit 3
    run "$SCRIPT"
    [ "$status" -eq 3 ]
    grep -qiE "future|CONSERVATIVE" "$AUDIT"
    # A future-dated report aged by a recent mtime is young → retained, but no
    # longer via the silent negative-age path.
}

@test "AUDIT-secrets: unknown/mislabeled classification → conservative RESTRICTED (30d), not INTERNAL (90d) (T-B9)" {
    # A RESTRICTED report mislabeled PUBLIC/lowercase/trailing-space must NOT
    # win the longer 90d window. Default unknown classification → most-restrictive.
    # 45-day-old report: purged under 30d RESTRICTED, retained under 90d INTERNAL.
    local ts; ts=$(date -u -d "45 days ago" +%Y-%m-%dT%H:%M:%SZ)
    cat > "$RT/rt-mislabel-result.json" <<EOF
{"run_id": "rt-mislabel", "timestamp": "$ts", "classification": "PUBLIC"}
EOF
    run "$SCRIPT"
    # Purged → unknown classification was treated as RESTRICTED (30d), not INTERNAL (90d)
    [ ! -f "$RT/rt-mislabel-result.json" ]
    grep -q "PURGED: rt-mislabel" "$AUDIT"
}

@test "regression pin: explicit INTERNAL still gets 90d (not over-purged) (T-B10)" {
    local ts; ts=$(date -u -d "45 days ago" +%Y-%m-%dT%H:%M:%SZ)
    cat > "$RT/rt-internal-result.json" <<EOF
{"run_id": "rt-internal", "timestamp": "$ts", "classification": "INTERNAL"}
EOF
    run "$SCRIPT"
    # 45d < 90d INTERNAL → retained
    [ -f "$RT/rt-internal-result.json" ]
}
