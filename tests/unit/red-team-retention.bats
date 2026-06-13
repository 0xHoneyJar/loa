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
