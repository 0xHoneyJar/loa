-- cycle-105 sprint-1 T1.1 fixture: dirty_issues exists but with extra columns
-- that the repair pattern's CREATE/INSERT/SWAP doesn't know about. The tool
-- MUST refuse with exit 3 rather than silently dropping the extra columns.

CREATE TABLE dirty_issues (
    issue_id  INTEGER PRIMARY KEY,
    marked_at DATETIME NOT NULL,
    -- Unexpected extra columns the repair tool can't reason about safely:
    extra_field_a TEXT,
    extra_field_b INTEGER
);
