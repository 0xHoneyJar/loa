#!/usr/bin/env bash
# =============================================================================
# tools/beads-migration-repair.sh
# =============================================================================
# cycle-105 sprint-1 T1.2 — Loa-side workaround for KF-005:
# beads_rust 0.2.1..0.2.6 migration failure
#   `NOT NULL constraint failed: dirty_issues.marked_at`
#
# The upstream bug declares `dirty_issues.marked_at` NOT NULL with no DEFAULT,
# making any INSERT that doesn't explicitly set the column fail. Upstream
# issues filed:
#   - https://github.com/Dicklesworthstone/beads_rust/issues/290
#   - https://github.com/0xHoneyJar/loa/issues/661
#
# This tool heals dirty .beads/beads.db files in-place via the canonical
# SQLite recreate-and-swap pattern (since SQLite has no ALTER COLUMN):
#
#   1. Pre-flight: confirm the schema actually matches the bug shape
#   2. Snapshot: copy .beads/beads.db → .beads/_backup-<ISO8601>.db
#   3. Repair: BEGIN TRANSACTION;
#        UPDATE dirty_issues SET marked_at = CURRENT_TIMESTAMP
#               WHERE marked_at IS NULL;
#        CREATE TABLE dirty_issues_v2 (
#            issue_id  INTEGER PRIMARY KEY,
#            marked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP);
#        INSERT INTO dirty_issues_v2 SELECT * FROM dirty_issues;
#        DROP TABLE dirty_issues;
#        ALTER TABLE dirty_issues_v2 RENAME TO dirty_issues;
#      COMMIT;
#   4. Post-flight: verify the new PRAGMA matches the HEALTHY shape;
#      restore from snapshot on failure
#   5. Log: append a JSONL line to .beads/_repair-history.jsonl
#
# Idempotent: pre-flight no-ops on HEALTHY status unless --force.
# Refuses to mutate unrecognized schemas (extra columns, missing table)
# with exit 3.
#
# Usage:
#   tools/beads-migration-repair.sh                     # repair .beads/beads.db
#   tools/beads-migration-repair.sh --db <path>         # target a different db
#   tools/beads-migration-repair.sh --dry-run           # print SQL, touch nothing
#   tools/beads-migration-repair.sh --force             # re-run on healthy db
#   tools/beads-migration-repair.sh --no-backup         # skip backup (CI fixtures only)
#   tools/beads-migration-repair.sh --json              # JSONL outcome to stdout
#   tools/beads-migration-repair.sh --help
#
# Exit codes:
#   0  repair completed (or no-op when already HEALTHY)
#   1  repair failed; database restored from backup
#   2  bad arguments / I/O error
#   3  unrecognized schema; operator action required
#
# Tested by tests/unit/beads-migration-repair.bats (BMR-T1..T10).
# =============================================================================

set -euo pipefail

# ---- defaults -------------------------------------------------------------

DB_PATH=".beads/beads.db"
DRY_RUN=0
FORCE=0
NO_BACKUP=0
JSON_OUT=0

# ---- arg parse -----------------------------------------------------------

usage() {
    sed -n '/^# Usage:/,/^# Tested by/p' "$0" | sed 's/^# \?//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)
            [[ $# -ge 2 ]] || { echo "ERROR: --db requires a path" >&2; exit 2; }
            DB_PATH="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --force)    FORCE=1; shift ;;
        --no-backup) NO_BACKUP=1; shift ;;
        --json)     JSON_OUT=1; shift ;;
        --help|-h)  usage; exit 0 ;;
        *)          echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# ---- pre-flight checks ---------------------------------------------------

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "ERROR: sqlite3 not on PATH" >&2
    exit 2
fi

if [[ ! -f "$DB_PATH" ]]; then
    echo "ERROR: database not found at $DB_PATH" >&2
    exit 2
fi

# ---- schema inspection ---------------------------------------------------

# Returns one of: healthy | dirty | dirty_with_extras | missing_table | unknown
_classify_schema() {
    local db="$1"

    # Does the dirty_issues table exist?
    local exists
    exists=$(sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name='dirty_issues';" 2>/dev/null || true)
    if [[ -z "$exists" ]]; then
        echo "missing_table"
        return
    fi

    # Read PRAGMA. Row format: cid|name|type|notnull|dflt_value|pk
    local pragma
    pragma=$(sqlite3 "$db" "PRAGMA table_info(dirty_issues);" 2>/dev/null || true)

    # Build a sorted column-name list. We expect exactly 2 columns: issue_id + marked_at.
    local columns
    columns=$(echo "$pragma" | awk -F'|' '{print $2}' | sort | tr '\n' ',' | sed 's/,$//')
    if [[ "$columns" != "issue_id,marked_at" ]]; then
        echo "dirty_with_extras"
        return
    fi

    # Inspect the marked_at column specifically.
    local marked_at_row notnull dflt
    marked_at_row=$(echo "$pragma" | awk -F'|' '$2 == "marked_at" { print; exit }')
    notnull=$(echo "$marked_at_row" | awk -F'|' '{print $4}')
    dflt=$(echo "$marked_at_row" | awk -F'|' '{print $5}')

    # HEALTHY = notnull=1 AND dflt non-empty (CURRENT_TIMESTAMP literal).
    # DIRTY   = notnull=1 AND dflt empty.
    # Anything else is unknown (e.g., notnull=0 means the bug never existed
    # in the operator's schema).
    if [[ "$notnull" == "1" && -n "$dflt" ]]; then
        echo "healthy"
    elif [[ "$notnull" == "1" && -z "$dflt" ]]; then
        echo "dirty"
    else
        echo "unknown"
    fi
}

# ---- repair SQL ----------------------------------------------------------

readonly REPAIR_SQL=$(cat <<'SQL'
BEGIN TRANSACTION;

-- 1. Backfill any existing NULL marked_at values with CURRENT_TIMESTAMP.
--    (Pre-repair, the NOT NULL constraint would have rejected NULL inserts,
--    but PRAGMA writable_schema + UPDATE can technically introduce them;
--    defense-in-depth backfill.)
UPDATE dirty_issues
   SET marked_at = CURRENT_TIMESTAMP
 WHERE marked_at IS NULL;

-- 2. Create the corrected table.
CREATE TABLE dirty_issues_v2 (
    issue_id  INTEGER PRIMARY KEY,
    marked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Copy data.
INSERT INTO dirty_issues_v2 (issue_id, marked_at)
SELECT issue_id, marked_at FROM dirty_issues;

-- 4. Swap.
DROP TABLE dirty_issues;
ALTER TABLE dirty_issues_v2 RENAME TO dirty_issues;

COMMIT;
SQL
)

# ---- history log --------------------------------------------------------

_log_history() {
    local outcome="$1"
    local pre_status="$2"
    local post_status="$3"
    local rows="$4"
    local backup="$5"
    local duration_ms="$6"

    local hist_path
    hist_path="$(dirname "$DB_PATH")/_repair-history.jsonl"

    local ts
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Write atomically: jq builds, append to file.
    if command -v jq >/dev/null 2>&1; then
        local line
        line=$(jq -nc \
            --arg ts "$ts" \
            --arg ver "cycle-105-T1.2" \
            --arg db "$DB_PATH" \
            --arg pre "$pre_status" \
            --arg post "$post_status" \
            --arg outcome "$outcome" \
            --arg backup "$backup" \
            --argjson rows "$rows" \
            --argjson duration_ms "$duration_ms" \
            '{
                timestamp: $ts,
                tool_version: $ver,
                db_path: $db,
                pre_status: $pre,
                post_status: $post,
                rows_affected: $rows,
                backup_path: $backup,
                outcome: $outcome,
                duration_ms: $duration_ms
            }')
        printf '%s\n' "$line" >> "$hist_path"
    else
        # jq not available — write a less-structured but parseable line.
        printf '%s outcome=%s pre=%s post=%s rows=%s backup=%s duration_ms=%s\n' \
            "$ts" "$outcome" "$pre_status" "$post_status" "$rows" "$backup" "$duration_ms" \
            >> "$hist_path"
    fi
}

# ---- main flow ----------------------------------------------------------

START_MS=$(date +%s%3N 2>/dev/null || echo 0)
PRE_STATUS=$(_classify_schema "$DB_PATH")

# Decision table per pre_status
case "$PRE_STATUS" in
    missing_table|dirty_with_extras|unknown)
        echo "ERROR: schema state '$PRE_STATUS' is unrecoverable by automated repair." >&2
        echo "  - dirty_issues table missing or has unexpected columns." >&2
        echo "  - Operator action required: inspect $DB_PATH with sqlite3 and decide." >&2
        echo "  - See https://github.com/0xHoneyJar/loa/issues/661 for context." >&2
        _log_history "unrecognized_schema" "$PRE_STATUS" "$PRE_STATUS" 0 "" 0 || true
        if [[ "$JSON_OUT" -eq 1 ]]; then
            printf '{"outcome":"unrecognized_schema","pre_status":"%s","post_status":"%s"}\n' \
                "$PRE_STATUS" "$PRE_STATUS"
        fi
        exit 3
        ;;
    healthy)
        if [[ "$FORCE" -eq 0 ]]; then
            echo "OK: database already HEALTHY (marked_at has DEFAULT). No action taken."
            echo "  Pass --force to re-run repair anyway." >&2
            _log_history "no_op_already_healthy" "$PRE_STATUS" "$PRE_STATUS" 0 "" 0 || true
            if [[ "$JSON_OUT" -eq 1 ]]; then
                printf '{"outcome":"no_op_already_healthy","pre_status":"healthy","post_status":"healthy"}\n'
            fi
            exit 0
        fi
        echo "INFO: --force set; re-running repair on already-healthy database."
        ;;
    dirty)
        # The case we're built for. Proceed.
        ;;
esac

# ---- dry-run path -------------------------------------------------------

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[DRY-RUN] Would execute against $DB_PATH:"
    echo "----"
    echo "$REPAIR_SQL"
    echo "----"
    _log_history "dry_run" "$PRE_STATUS" "$PRE_STATUS" 0 "" 0 || true
    if [[ "$JSON_OUT" -eq 1 ]]; then
        printf '{"outcome":"dry_run","pre_status":"%s","post_status":"%s"}\n' \
            "$PRE_STATUS" "$PRE_STATUS"
    fi
    exit 0
fi

# ---- snapshot -----------------------------------------------------------

BACKUP_PATH=""
if [[ "$NO_BACKUP" -eq 0 ]]; then
    BACKUP_PATH="$(dirname "$DB_PATH")/_backup-$(date -u +%Y%m%dT%H%M%SZ).db"
    cp -a "$DB_PATH" "$BACKUP_PATH"
    echo "INFO: backup at $BACKUP_PATH"
else
    echo "WARNING: --no-backup; if repair fails the database is unrecoverable." >&2
fi

# ---- count rows for the history log -------------------------------------
ROW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM dirty_issues;" 2>/dev/null || echo 0)

# ---- execute repair -----------------------------------------------------

set +e
REPAIR_OUTPUT=$(sqlite3 "$DB_PATH" "$REPAIR_SQL" 2>&1)
REPAIR_EXIT=$?
set -e

if [[ "$REPAIR_EXIT" -ne 0 ]]; then
    echo "ERROR: repair SQL failed (exit $REPAIR_EXIT): $REPAIR_OUTPUT" >&2
    if [[ -n "$BACKUP_PATH" && -f "$BACKUP_PATH" ]]; then
        echo "INFO: restoring from backup $BACKUP_PATH" >&2
        cp -a "$BACKUP_PATH" "$DB_PATH"
    fi
    _log_history "failed_restored" "$PRE_STATUS" "dirty" "$ROW_COUNT" "$BACKUP_PATH" 0 || true
    if [[ "$JSON_OUT" -eq 1 ]]; then
        printf '{"outcome":"failed_restored","pre_status":"dirty","post_status":"dirty","backup_path":"%s"}\n' \
            "$BACKUP_PATH"
    fi
    exit 1
fi

# ---- post-flight verify -------------------------------------------------

POST_STATUS=$(_classify_schema "$DB_PATH")

END_MS=$(date +%s%3N 2>/dev/null || echo 0)
DURATION=$((END_MS - START_MS))

if [[ "$POST_STATUS" != "healthy" ]]; then
    echo "ERROR: repair ran but post-flight schema is '$POST_STATUS' (expected 'healthy')" >&2
    if [[ -n "$BACKUP_PATH" && -f "$BACKUP_PATH" ]]; then
        echo "INFO: restoring from backup $BACKUP_PATH" >&2
        cp -a "$BACKUP_PATH" "$DB_PATH"
    fi
    _log_history "failed_restored" "$PRE_STATUS" "$POST_STATUS" "$ROW_COUNT" "$BACKUP_PATH" "$DURATION" || true
    if [[ "$JSON_OUT" -eq 1 ]]; then
        printf '{"outcome":"failed_restored","pre_status":"%s","post_status":"%s","backup_path":"%s"}\n' \
            "$PRE_STATUS" "$POST_STATUS" "$BACKUP_PATH"
    fi
    exit 1
fi

echo "OK: repair complete. Schema now HEALTHY (marked_at has DEFAULT CURRENT_TIMESTAMP)."
echo "  Rows preserved: $ROW_COUNT"
[[ -n "$BACKUP_PATH" ]] && echo "  Backup: $BACKUP_PATH"

_log_history "repaired" "$PRE_STATUS" "$POST_STATUS" "$ROW_COUNT" "$BACKUP_PATH" "$DURATION" || true

if [[ "$JSON_OUT" -eq 1 ]]; then
    if command -v jq >/dev/null 2>&1; then
        jq -nc \
            --arg pre "$PRE_STATUS" \
            --arg post "$POST_STATUS" \
            --arg backup "$BACKUP_PATH" \
            --argjson rows "$ROW_COUNT" \
            --argjson duration_ms "$DURATION" \
            '{
                outcome: "repaired",
                pre_status: $pre,
                post_status: $post,
                rows_affected: $rows,
                backup_path: $backup,
                duration_ms: $duration_ms
            }'
    else
        printf '{"outcome":"repaired","pre_status":"%s","post_status":"%s","rows_affected":%d}\n' \
            "$PRE_STATUS" "$POST_STATUS" "$ROW_COUNT"
    fi
fi

exit 0
