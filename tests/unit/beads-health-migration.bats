#!/usr/bin/env bats
# =============================================================================
# beads-health-migration.bats — Tests for migration-bug pre-flight (Issue #661)
# =============================================================================
# sprint-bug-128. Validates that beads-health.sh detects the upstream
# beads_rust 0.2.1 migration bug (dirty_issues.marked_at NOT NULL without
# DEFAULT) via non-mutating sqlite3 PRAGMA inspection and reports
# MIGRATION_NEEDED with a structured diagnostic.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export SCRIPT="$PROJECT_ROOT/.claude/scripts/beads/beads-health.sh"

    # Hermetic temp project root — beads-health resolves PROJECT_ROOT/.beads
    export TMPDIR_TEST="$(mktemp -d)"
    export PROJECT_ROOT_TEST="$TMPDIR_TEST/repo"
    mkdir -p "$PROJECT_ROOT_TEST/.beads"
    export DB="$PROJECT_ROOT_TEST/.beads/beads.db"

    # Build a minimal sqlite DB with the required `issues.owner` column so
    # check_schema passes; we then layer the dirty_issues table state on top.
    sqlite3 "$DB" <<'SQL'
CREATE TABLE issues (id TEXT PRIMARY KEY, owner TEXT);
INSERT INTO issues VALUES ('test', 'me');
SQL
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# =========================================================================
# BHM-T1: bug pattern detected → MIGRATION_NEEDED + diagnostic
# =========================================================================

@test "BHM-T1: dirty_issues.marked_at NOT NULL with no DEFAULT → MIGRATION_NEEDED" {
    # Create the buggy schema: marked_at NOT NULL with no DEFAULT
    sqlite3 "$DB" <<'SQL'
CREATE TABLE dirty_issues (id INTEGER PRIMARY KEY, marked_at TEXT NOT NULL);
SQL

    run env PROJECT_ROOT="$PROJECT_ROOT_TEST" "$SCRIPT" --quick --json
    [[ "$output" == *"MIGRATION_NEEDED"* ]]
    [[ "$output" == *"dirty_issues_migration"* ]]
    [[ "$output" == *"needs_repair"* ]]
    [[ "$output" == *"Issue #661"* ]] || [[ "$output" == *"issues/661"* ]]
}

# =========================================================================
# BHM-T2: fixed schema (NOT NULL with DEFAULT) → no false positive
# =========================================================================

@test "BHM-T2: dirty_issues.marked_at NOT NULL WITH DEFAULT → ok (no false positive)" {
    sqlite3 "$DB" <<'SQL'
CREATE TABLE dirty_issues (id INTEGER PRIMARY KEY, marked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
SQL

    run env PROJECT_ROOT="$PROJECT_ROOT_TEST" "$SCRIPT" --quick --json
    [[ "$output" != *"needs_repair"* ]]
    [[ "$output" != *"MIGRATION BUG DETECTED"* ]]
}

# =========================================================================
# BHM-T3: nullable column → no false positive
# =========================================================================

@test "BHM-T3: dirty_issues.marked_at nullable → ok (no false positive)" {
    sqlite3 "$DB" <<'SQL'
CREATE TABLE dirty_issues (id INTEGER PRIMARY KEY, marked_at TEXT);
SQL

    run env PROJECT_ROOT="$PROJECT_ROOT_TEST" "$SCRIPT" --quick --json
    [[ "$output" != *"needs_repair"* ]]
}

# =========================================================================
# BHM-T4: missing dirty_issues table → ok (older schema)
# =========================================================================

@test "BHM-T4: no dirty_issues table → ok (older schema, no bug)" {
    # No dirty_issues table at all
    run env PROJECT_ROOT="$PROJECT_ROOT_TEST" "$SCRIPT" --quick --json
    [[ "$output" != *"needs_repair"* ]]
}

# =========================================================================
# BHM-T5: structured diagnostic includes workaround + tracking link
# =========================================================================

@test "BHM-T5: diagnostic includes workaround and tracking link" {
    sqlite3 "$DB" <<'SQL'
CREATE TABLE dirty_issues (id INTEGER PRIMARY KEY, marked_at TEXT NOT NULL);
SQL

    run env PROJECT_ROOT="$PROJECT_ROOT_TEST" "$SCRIPT" --quick --json
    [[ "$output" == *"git commit --no-verify"* ]]
    [[ "$output" == *"install-beads-precommit"* ]]
    [[ "$output" == *"github.com/0xHoneyJar/loa/issues/661"* ]]
}
