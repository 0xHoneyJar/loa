-- cycle-105 sprint-1 T1.1 fixture: dirty_issues table is missing entirely.
-- Repair tool MUST refuse with exit 3 (unrecoverable) — operator action
-- required, not a state the repair pattern is designed to heal.

CREATE TABLE issues (
    id INTEGER PRIMARY KEY,
    title TEXT
);
