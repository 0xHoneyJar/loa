#!/usr/bin/env bats
# =============================================================================
# tests/integration/beads-health-repair-flow.bats — cycle-105 sprint-1 T1.4
# =============================================================================
# Integration tests for the beads-health.sh --repair flag wired to the
# tools/beads-migration-repair.sh tool. Covers BHRF-T1..T4 per SDD §6.3.
#
# Isolation: every test materializes a fresh BEADS_DIR via mktemp and
# uses LOA_BEADS_DIR env override so the operator's real .beads/ is
# never touched.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    HEALTH="$PROJECT_ROOT/.claude/scripts/beads/beads-health.sh"
    FIX="$PROJECT_ROOT/tests/fixtures/beads-migration"
    [[ -x "$HEALTH" ]] || skip "beads-health.sh not executable"
    [[ -d "$FIX" ]] || skip "fixture corpus missing"
    command -v sqlite3 >/dev/null 2>&1 || skip "sqlite3 not on PATH"

    SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/bhrf-XXXXXX")"
    chmod 700 "$SCRATCH"
    export LOA_BEADS_DIR="$SCRATCH/.beads"
    mkdir -p "$LOA_BEADS_DIR"
}

teardown() {
    [[ -n "${SCRATCH:-}" && -d "$SCRATCH" ]] && rm -rf "$SCRATCH"
    unset LOA_BEADS_DIR
}

_load_fixture() {
    sqlite3 "$LOA_BEADS_DIR/beads.db" < "$FIX/$1-db.sql"
}

_classify_marked_at() {
    sqlite3 "$LOA_BEADS_DIR/beads.db" "PRAGMA table_info(dirty_issues);" 2>/dev/null \
        | awk -F'|' '$2 == "marked_at" {
            if ($4 == "1" && $5 != "") print "healthy"
            else if ($4 == "1" && $5 == "") print "dirty"
            else print "other"
          }'
}

# ---- BHRF-T1: dirty + --repair → HEALTHY ---------------------------------

@test "BHRF-T1: dirty db + beads-health.sh --repair → post-status HEALTHY" {
    _load_fixture "dirty"
    [ "$(_classify_marked_at)" = "dirty" ]

    run "$HEALTH" --quick --repair
    # Exit code may be 4 (DEGRADED — jsonl-stale) or 0 (HEALTHY).
    # The contract is that dirty_issues_migration flips to ok.
    [ "$(_classify_marked_at)" = "healthy" ]
}

# ---- BHRF-T2: healthy + --repair → no-op ---------------------------------

@test "BHRF-T2: healthy db + beads-health.sh --repair → no-op, still HEALTHY" {
    _load_fixture "healthy"
    [ "$(_classify_marked_at)" = "healthy" ]

    run "$HEALTH" --quick --repair
    # The wired path only dispatches to the repair tool when
    # dirty_issues_migration == "needs_repair" OR --force is set. With a
    # healthy fixture, the dispatch is skipped entirely (correct no-op).
    # The contract is just: schema stays healthy + script doesn't error
    # on the dirty_issues_migration axis.
    [ "$(_classify_marked_at)" = "healthy" ]
    # No "MIGRATION BUG" recommendation should appear on a clean db.
    [[ "$output" != *"MIGRATION BUG"* ]]
}

# ---- BHRF-T3: dry-run pass-through ---------------------------------------

@test "BHRF-T3: dirty db + --repair --dry-run → status still needs_repair" {
    _load_fixture "dirty"
    [ "$(_classify_marked_at)" = "dirty" ]

    run "$HEALTH" --quick --repair --dry-run
    # Schema unchanged because --dry-run.
    [ "$(_classify_marked_at)" = "dirty" ]
    # And the dry-run path emits the SQL preview.
    [[ "$output" == *"DRY-RUN"* ]] || [[ "$output" == *"Would execute"* ]]
}

# ---- BHRF-T4: --json output shape ----------------------------------------

@test "BHRF-T4: dirty db + --repair --json → JSON status flips dirty_issues_migration=ok" {
    _load_fixture "dirty"

    run "$HEALTH" --quick --repair --json
    # Extract the JSON block (it lives after the repair tool's stderr).
    # The JSON object should contain dirty_issues_migration:ok post-repair.
    [[ "$output" == *'"dirty_issues_migration": "ok"'* ]]
    [ "$(_classify_marked_at)" = "healthy" ]
}

# ---- BHRF-T5: --force pass-through on healthy db -------------------------

@test "BHRF-T5: healthy db + --repair --force → re-runs repair without complaint" {
    _load_fixture "healthy"

    run "$HEALTH" --quick --repair --force
    [ "$(_classify_marked_at)" = "healthy" ]
}
