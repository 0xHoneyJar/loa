-- cycle-105 sprint-1 T1.1 fixture: the KF-005 bug shape.
-- dirty_issues.marked_at is declared NOT NULL with NO DEFAULT.
-- This matches the beads_rust 0.2.1-0.2.6 migration failure that
-- beads-health.sh:171 detects via PRAGMA table_info.
--
-- Materialize into a fresh db with:
--   sqlite3 .beads/beads.db < dirty-db.sql

CREATE TABLE dirty_issues (
    issue_id  INTEGER PRIMARY KEY,
    marked_at DATETIME NOT NULL
);
