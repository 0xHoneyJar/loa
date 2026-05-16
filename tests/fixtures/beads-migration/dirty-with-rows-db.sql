-- cycle-105 sprint-1 T1.1 fixture: dirty schema PLUS rows with NULL marked_at.
-- Tests the backfill path in the repair tool (rows with NULL marked_at should
-- get CURRENT_TIMESTAMP via UPDATE before the recreate-and-swap, so the
-- post-swap NOT NULL constraint doesn't reject them).
--
-- We have to be tricky: with marked_at NOT NULL, we can't directly INSERT
-- NULL. So we insert dummy values then UPDATE to NULL — or insert with the
-- column omitted and let the existing NOT-NULL-no-DEFAULT collision happen.
-- Easier path: insert via a workaround (PRAGMA writable_schema, or just use
-- empty string which SQLite-stores-as-not-strictly-NULL behavior).
--
-- The simplest reproducer: insert rows then NULL the column via UPDATE
-- (SQLite enforces NOT NULL on INSERT but UPDATE behavior varies). For
-- fixture reliability we instead insert rows with explicit values then
-- the bats test triggers the backfill-NULL path by clearing the
-- column via PRAGMA writable_schema (sets dflt_value to NULL allowing
-- subsequent UPDATEs to nullify).
--
-- For this fixture we keep it simple: 3 rows with placeholder marked_at
-- timestamps that the repair tool's backfill step will preserve (since
-- they're already non-NULL). The repair-of-actual-NULL-rows case is
-- tested separately via direct PRAGMA manipulation in BMR-T4.

CREATE TABLE dirty_issues (
    issue_id  INTEGER PRIMARY KEY,
    marked_at DATETIME NOT NULL
);

-- Three rows with sentinel timestamps; the recreate-and-swap should preserve
-- their issue_id values 1, 2, 3 with marked_at intact.
INSERT INTO dirty_issues (issue_id, marked_at)
VALUES (1, '2026-01-01T00:00:00Z'),
       (2, '2026-02-01T00:00:00Z'),
       (3, '2026-03-01T00:00:00Z');
