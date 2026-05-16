-- cycle-105 sprint-1 T1.1 fixture: a properly-migrated schema.
-- marked_at has a CURRENT_TIMESTAMP default; PRAGMA notnull=1 + dflt populated.
-- The repair tool MUST recognize this as already-healthy and no-op.

CREATE TABLE dirty_issues (
    issue_id  INTEGER PRIMARY KEY,
    marked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
