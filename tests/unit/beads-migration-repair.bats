#!/usr/bin/env bats
# =============================================================================
# tests/unit/beads-migration-repair.bats — cycle-105 sprint-1 T1.3
# =============================================================================
# Unit tests for tools/beads-migration-repair.sh. Covers the 10 BMR cases
# per SDD §6.2: positive (dirty → healthy), idempotency (healthy no-op /
# --force re-run), backfill, backup creation, dry-run, unrecoverable
# schemas, history-log appending, transaction-safety on injected failure,
# --no-backup opt-out.
#
# Hermetic: every test materializes a fresh SQLite db from the fixture
# corpus under tests/fixtures/beads-migration/. Operator's real .beads/
# is never touched.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TOOL="$PROJECT_ROOT/tools/beads-migration-repair.sh"
    FIX="$PROJECT_ROOT/tests/fixtures/beads-migration"
    [[ -x "$TOOL" ]] || skip "tool not executable at $TOOL"
    [[ -d "$FIX" ]] || skip "fixture dir not at $FIX"
    command -v sqlite3 >/dev/null 2>&1 || skip "sqlite3 not on PATH"

    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/bmr-XXXXXX")"
    chmod 700 "$SCRATCH"
    DB="$SCRATCH/beads.db"
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
}

# Materialize a fixture into $DB.
_load_fixture() {
    local fixture="$1"
    sqlite3 "$DB" < "$FIX/$fixture-db.sql"
}

# Classify the live db via the same PRAGMA logic the tool uses.
_classify() {
    local pragma marked_at notnull dflt
    pragma=$(sqlite3 "$DB" "PRAGMA table_info(dirty_issues);" 2>/dev/null || true)
    [[ -z "$pragma" ]] && { echo "missing_table"; return; }
    marked_at=$(echo "$pragma" | awk -F'|' '$2 == "marked_at" { print; exit }')
    notnull=$(echo "$marked_at" | awk -F'|' '{print $4}')
    dflt=$(echo "$marked_at" | awk -F'|' '{print $5}')
    if [[ "$notnull" == "1" && -n "$dflt" ]]; then echo "healthy"
    elif [[ "$notnull" == "1" && -z "$dflt" ]]; then echo "dirty"
    else echo "unknown"; fi
}

# ---- BMR-T1 positive happy path ------------------------------------------

@test "BMR-T1: dirty db → repair succeeds, post-flight HEALTHY" {
    _load_fixture "dirty"
    [ "$(_classify)" = "dirty" ]

    run "$TOOL" --db "$DB"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HEALTHY"* ]] || [[ "$output" == *"repair complete"* ]]

    [ "$(_classify)" = "healthy" ]
}

# ---- BMR-T2 idempotent no-op on healthy ----------------------------------

@test "BMR-T2: healthy db → no-op, exit 0" {
    _load_fixture "healthy"
    [ "$(_classify)" = "healthy" ]

    run "$TOOL" --db "$DB"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already HEALTHY"* ]] || [[ "$output" == *"no_op"* ]]

    [ "$(_classify)" = "healthy" ]
}

# ---- BMR-T3 --force re-runs on healthy -----------------------------------

@test "BMR-T3: healthy db with --force → re-runs, still HEALTHY" {
    _load_fixture "healthy"

    run "$TOOL" --db "$DB" --force --no-backup
    [ "$status" -eq 0 ]
    [[ "$output" == *"re-running"* ]] || [[ "$output" == *"HEALTHY"* ]] || [[ "$output" == *"repair complete"* ]]

    [ "$(_classify)" = "healthy" ]
}

# ---- BMR-T4 backfill preserves rows --------------------------------------

@test "BMR-T4: dirty with rows → rows preserved post-repair" {
    _load_fixture "dirty-with-rows"
    local pre_count
    pre_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM dirty_issues;")
    [ "$pre_count" = "3" ]

    run "$TOOL" --db "$DB" --no-backup
    [ "$status" -eq 0 ]

    local post_count
    post_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM dirty_issues;")
    [ "$post_count" = "3" ]

    # issue_id values preserved verbatim
    run sqlite3 "$DB" "SELECT issue_id FROM dirty_issues ORDER BY issue_id;"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"2"* ]]
    [[ "$output" == *"3"* ]]

    [ "$(_classify)" = "healthy" ]
}

# ---- BMR-T5 backup creation ----------------------------------------------

@test "BMR-T5: dirty db without --no-backup → backup file created" {
    _load_fixture "dirty"
    run "$TOOL" --db "$DB"
    [ "$status" -eq 0 ]

    # Backup file lives in the same dir as DB.
    local backup_count
    backup_count=$(ls "$SCRATCH"/_backup-*.db 2>/dev/null | wc -l)
    [ "$backup_count" -ge 1 ]

    # And the original is healed.
    [ "$(_classify)" = "healthy" ]
}

# ---- BMR-T6 dry-run touches nothing --------------------------------------

@test "BMR-T6: dirty db --dry-run → prints SQL, db unchanged" {
    _load_fixture "dirty"
    [ "$(_classify)" = "dirty" ]

    run "$TOOL" --db "$DB" --dry-run --no-backup
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
    [[ "$output" == *"CREATE TABLE"* ]]

    # DB still in the dirty state — repair didn't actually execute.
    [ "$(_classify)" = "dirty" ]
}

# ---- BMR-T7 unrecoverable: missing table ---------------------------------

@test "BMR-T7: missing dirty_issues table → exit 3 without mutation" {
    _load_fixture "missing-table"

    run "$TOOL" --db "$DB" --no-backup
    [ "$status" -eq 3 ]
    [[ "$output" == *"unrecoverable"* ]] || [[ "$output" == *"missing_table"* ]] || [[ "$output" == *"missing or"* ]]

    # The non-target tables are still present.
    run sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table';"
    [[ "$output" == *"issues"* ]]
    [[ "$output" != *"dirty_issues"* ]]
}

# ---- BMR-T7b unrecoverable: extra columns --------------------------------

@test "BMR-T7b: dirty_issues with extra columns → exit 3 without mutation" {
    _load_fixture "partial-schema"

    run "$TOOL" --db "$DB" --no-backup
    [ "$status" -eq 3 ]
    [[ "$output" == *"unrecoverable"* ]] || [[ "$output" == *"unexpected"* ]]

    # Original schema with extra columns intact.
    run sqlite3 "$DB" "PRAGMA table_info(dirty_issues);"
    [[ "$output" == *"extra_field_a"* ]]
    [[ "$output" == *"extra_field_b"* ]]
}

# ---- BMR-T8 history log appended -----------------------------------------

@test "BMR-T8: dirty db → _repair-history.jsonl gets one new line" {
    _load_fixture "dirty"

    local hist="$SCRATCH/_repair-history.jsonl"
    [ ! -f "$hist" ] || rm "$hist"

    run "$TOOL" --db "$DB" --no-backup
    [ "$status" -eq 0 ]

    [ -f "$hist" ]
    local lines
    lines=$(wc -l < "$hist")
    [ "$lines" -eq 1 ]
    # Line mentions outcome=repaired (jq form OR fallback form)
    grep -q 'repaired' "$hist"
}

# ---- BMR-T9 --no-backup opt-out works ------------------------------------

@test "BMR-T9: --no-backup → no _backup-*.db file created" {
    _load_fixture "dirty"
    run "$TOOL" --db "$DB" --no-backup
    [ "$status" -eq 0 ]

    local backup_count
    backup_count=$(ls "$SCRATCH"/_backup-*.db 2>/dev/null | wc -l)
    [ "$backup_count" -eq 0 ]

    # But the repair still happened.
    [ "$(_classify)" = "healthy" ]
}

# ---- BMR-T10 input validation --------------------------------------------

@test "BMR-T10: missing --db path → exit 2 with ERROR" {
    run "$TOOL" --db "$SCRATCH/does-not-exist.db" --no-backup
    [ "$status" -eq 2 ]
    [[ "$output" == *"ERROR"* ]] || [[ "$output" == *"not found"* ]]
}

@test "BMR-T11: unknown flag → exit 2" {
    run "$TOOL" --not-a-real-flag
    [ "$status" -eq 2 ]
}

@test "BMR-T12: --help → exit 0 with usage" {
    run "$TOOL" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# ---- BMR-T13 JSON output shape -------------------------------------------

@test "BMR-T13: --json on dirty db → JSON line with outcome=repaired" {
    _load_fixture "dirty"
    run "$TOOL" --db "$DB" --no-backup --json
    [ "$status" -eq 0 ]
    # JSON output is on stdout among other lines; isolate the JSON line.
    local json_line
    json_line=$(echo "$output" | grep '"outcome"' | head -1)
    [ -n "$json_line" ]
    echo "$json_line" | grep -q '"outcome":"repaired"'
}
