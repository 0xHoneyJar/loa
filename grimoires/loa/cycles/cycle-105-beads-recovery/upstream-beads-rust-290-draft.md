# Draft comment for Dicklesworthstone/beads_rust#290

> **Status**: draft — operator to post on the upstream repo.
> Loa-side issue #661 has been commented (cycle-105 sprint-2 T2.5).
> Upstream repo is outside `0xHoneyJar/*` so this is left for the
> operator's discretion.

---

## Loa-side reproducer + workaround tool

Following up on this issue from the Loa side (downstream tracker at 0xHoneyJar/loa#661). We shipped a Loa-side migration repair tool in our cycle-105 (2026-05-12) that heals the dirty-db state without modifying beads_rust:

**Bug shape** (from PRAGMA inspection):
```
sqlite> PRAGMA table_info(dirty_issues);
0|issue_id|INTEGER|0||1
1|marked_at|DATETIME|1||0    -- notnull=1, dflt_value='' (empty)
```

**Repair pattern** (SQLite recreate-and-swap; SQLite has no ALTER COLUMN):
```sql
BEGIN TRANSACTION;
UPDATE dirty_issues SET marked_at = CURRENT_TIMESTAMP WHERE marked_at IS NULL;
CREATE TABLE dirty_issues_v2 (
    issue_id  INTEGER PRIMARY KEY,
    marked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO dirty_issues_v2 (issue_id, marked_at)
SELECT issue_id, marked_at FROM dirty_issues;
DROP TABLE dirty_issues;
ALTER TABLE dirty_issues_v2 RENAME TO dirty_issues;
COMMIT;
```

Verified across beads_rust 0.2.4 + 0.2.6. After the repair, the column shape becomes `notnull=1, dflt_value=CURRENT_TIMESTAMP` and `br ready` / `br create` / `br sync` succeed.

**Proposed upstream fix**: include the DEFAULT clause in the migration. The migration SQL is presumably under `migrations/` in the beads_rust repo; happy to send a PR if you want.

Tool: https://github.com/0xHoneyJar/loa/blob/main/tools/beads-migration-repair.sh

Downstream tracker: https://github.com/0xHoneyJar/loa/issues/661
