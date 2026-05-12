# Cycle-105 SDD: beads_rust migration recovery

> **Status**: draft (awaiting sprint-plan + implementation)
> **Predecessor**: `prd.md`
> **Cycle**: cycle-105-beads-recovery
> **Created**: 2026-05-12

---

## 1. Architecture overview

```
                        ┌──────────────────────────────────┐
                        │ Operator runs `br ready`/`br...`  │
                        │ ↓                                  │
                        │ beads_rust attempts schema migr.  │
                        │ ↓                                  │
                        │ FAILS: marked_at NOT NULL no DFLT │
                        └────────────────┬──────────────────┘
                                         │
                                         ▼
   .claude/scripts/beads/beads-health.sh ─┐
        check_dirty_issues_migration()    │ (DETECTION — already exists)
                                          │ status=needs_repair
                                          ▼
   ╔══════════════════════════════════════════════════════════╗
   ║ NEW: tools/beads-migration-repair.sh                     ║
   ║   1. Snapshot .beads/beads.db → .beads/_backup-<ts>/     ║
   ║   2. sqlite3 ALTER TABLE / UPDATE to seal the gap         ║
   ║   3. Re-run PRAGMA check to verify HEALTHY               ║
   ║   4. On failure: restore from snapshot                   ║
   ╚══════════════════════════════════════════════════════════╝
                                          │
                                          ▼
                           beads-health.sh --repair
                           (orchestrator wraps the repair tool)
                                          │
                                          ▼
                                  HEALTHY status,
                                  br commands work again
```

The detection layer already exists (`check_dirty_issues_migration` in
beads-health.sh:171). Cycle-105 adds the REPAIR layer and wires it into
the existing health check via a new `--repair` flag.

## 2. Detection — already implemented (no changes needed)

Per `.claude/scripts/beads/beads-health.sh:171-208`:

```bash
# PRAGMA table_info row format: cid|name|type|notnull|dflt_value|pk
# Bug shape: marked_at row with notnull=1 AND empty dflt_value.
row=$(sqlite3 "${db_path}" "PRAGMA table_info(dirty_issues);")
# parse → CHECKS["dirty_issues_migration"]="needs_repair"
# return 3 → MIGRATION_NEEDED status
```

Cycle-105 keeps this detection unchanged. It's the load-bearing input
to the repair flow.

## 3. Repair tool — `tools/beads-migration-repair.sh`

### 3.1 Surface

```bash
tools/beads-migration-repair.sh [--db <path>] [--dry-run] [--force] [--no-backup]
```

| Flag | Default | Effect |
|------|---------|--------|
| `--db <path>` | `.beads/beads.db` | Override target database |
| `--dry-run` | (off) | Print the SQL that would run; touch nothing |
| `--force` | (off) | Run repair even when status is already HEALTHY |
| `--no-backup` | (off) | Skip backup creation. **Discouraged**; only for ephemeral CI fixtures |

Exit codes:

| Code | Meaning |
|------|---------|
| 0 | Repair completed successfully (or no-op when already HEALTHY) |
| 1 | Repair failed; database restored from backup |
| 2 | Bad arguments / IO error |
| 3 | Database is in an unrecoverable state (e.g., dirty_issues table missing entirely); operator action required |

### 3.2 Repair SQL

The bug class is `marked_at` declared NOT NULL with no DEFAULT — making
any INSERT into `dirty_issues` that doesn't explicitly set `marked_at`
fail. The fix is SQLite-supported via `ALTER TABLE ... ADD COLUMN` /
`UPDATE` semantics, but SQLite doesn't allow `ALTER COLUMN` directly.
The standard workaround is the "create new + copy + swap" pattern:

```sql
BEGIN TRANSACTION;

-- 1. Backfill any existing NULL marked_at values with CURRENT_TIMESTAMP
UPDATE dirty_issues
   SET marked_at = CURRENT_TIMESTAMP
 WHERE marked_at IS NULL;

-- 2. Create the corrected table with a default
CREATE TABLE dirty_issues_v2 (
    issue_id   INTEGER PRIMARY KEY,
    marked_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 3. Copy data
INSERT INTO dirty_issues_v2 (issue_id, marked_at)
SELECT issue_id, marked_at FROM dirty_issues;

-- 4. Swap
DROP TABLE dirty_issues;
ALTER TABLE dirty_issues_v2 RENAME TO dirty_issues;

COMMIT;
```

**Why not use `ALTER TABLE ADD COLUMN`?** Because the column already
exists; we need to change its constraint. SQLite's `ALTER COLUMN`
doesn't support adding DEFAULT to an existing column. The
recreate-and-swap is the canonical SQLite migration pattern.

### 3.3 Idempotency + safety

The repair tool MUST be safe to re-run on already-healed databases:

1. **Pre-flight check** — invoke `beads-health.sh --quick --json`; if
   `dirty_issues_migration` is `"ok"` AND `--force` is NOT set, exit 0
   with a no-op log line.
2. **Snapshot** — before any mutation, copy `.beads/beads.db` to
   `.beads/_backup-<ISO8601>.db`. Operator can rollback by replacing
   `beads.db` with the backup.
3. **Transactional repair** — entire SQL block wrapped in
   `BEGIN TRANSACTION; ... COMMIT;`. SQLite ensures atomicity.
4. **Post-flight verify** — after COMMIT, re-run the same PRAGMA check
   that beads-health.sh uses. If `notnull=1 AND dflt_value=''` still
   holds, restore from backup and exit 1.
5. **Refuse unrecognizable schemas** — if `dirty_issues` doesn't exist
   OR has unexpected columns, exit 3 without modification (operator
   action required).

### 3.4 Logging

Repair tool writes a structured JSONL line to
`.beads/_repair-history.jsonl` per invocation:

```jsonc
{
  "timestamp": "2026-05-12T07:00:00Z",
  "tool_version": "cycle-105-T1.3",
  "db_path": ".beads/beads.db",
  "pre_status": "needs_repair",   // or "ok"
  "post_status": "ok",            // or "needs_repair" on failed repair
  "rows_affected": 4,             // dirty_issues row count
  "backup_path": ".beads/_backup-20260512T070000Z.db",
  "outcome": "repaired",          // or "no_op_already_healthy", "failed_restored", "unrecognized_schema"
  "duration_ms": 42
}
```

## 4. `beads-health.sh --repair` integration

Wrap the repair tool from inside the health check:

```bash
beads-health.sh --repair          # detect; if needs_repair → invoke repair tool
beads-health.sh --repair --json   # JSON output of the full flow
beads-health.sh --repair --dry-run  # pass-through to repair tool's --dry-run
```

Behavior:

1. Run all existing health checks (binary present, .beads/ exists, schema compatible, dirty_issues migration).
2. If `dirty_issues_migration == "needs_repair"`:
   - Invoke `tools/beads-migration-repair.sh` (with --dry-run / --force pass-through).
   - On exit 0: re-run health check; exit with the new status.
   - On exit non-zero: surface the repair tool's diagnostic; exit non-zero.
3. If `dirty_issues_migration == "ok"`: exit with the existing status (no-op).

## 5. Pre-commit hook behavior

Current state: pre-commit hook (likely `.claude/hooks/pre-commit/beads-task-sync.sh`)
calls `beads-health.sh --quick` and exits non-zero on MIGRATION_NEEDED,
forcing operators to use `--no-verify`.

Cycle-105 target: pre-commit hook detects MIGRATION_NEEDED + emits a
WARNING + suggests `tools/beads-migration-repair.sh` BUT exits 0 (does
not block the commit). The "hard fail" moves from pre-commit (operator's
hot path) to CI (operator-async).

| Layer | MIGRATION_NEEDED behavior |
|-------|--------------------------|
| Pre-commit hook | WARN + exit 0; suggest repair tool |
| CI workflow | FAIL with explicit `MIGRATION_NEEDED` annotation; suggest repair tool |
| `beads-preflight.md` protocol | Document the auto-repair path |

## 6. Test strategy

### 6.1 Fixture corpus

`tests/fixtures/beads-migration/` (new dir):

| Fixture | Schema state | Expected outcome |
|---------|-------------|------------------|
| `dirty-db.sql` | dirty_issues with marked_at NOT NULL + no default | Repair succeeds; verifies notnull cleared |
| `healthy-db.sql` | dirty_issues with proper DEFAULT | No-op (already_healthy) |
| `missing-table-db.sql` | dirty_issues missing entirely | exit 3 unrecoverable |
| `partial-schema-db.sql` | dirty_issues with extra columns | exit 3 unrecoverable |
| `dirty-with-rows-db.sql` | dirty_issues with NULL marked_at rows | Rows backfilled to CURRENT_TIMESTAMP |

The fixtures are SQL files that the bats `setup()` materializes into a
fresh `.beads/beads.db` per test (operator's real db never touched).

### 6.2 Bats coverage

`tests/unit/beads-migration-repair.bats` (new):

- BMR-T1 positive: dirty-db → repair succeeds, post-flight HEALTHY
- BMR-T2 idempotent: healthy-db → no-op, exit 0
- BMR-T3 idempotent + force: healthy-db --force → re-runs, still HEALTHY
- BMR-T4 backfill: dirty-with-rows-db → existing NULL marked_at gets CURRENT_TIMESTAMP
- BMR-T5 backup: dirty-db → backup created at `.beads/_backup-<ts>.db`
- BMR-T6 dry-run: dirty-db --dry-run → prints SQL, db unchanged
- BMR-T7 unrecoverable: missing-table-db → exit 3 without mutation
- BMR-T8 history log: dirty-db → repair-history.jsonl appended with one line
- BMR-T9 transaction safety: simulate SQL failure mid-repair → backup auto-restored
- BMR-T10 --no-backup: opt-out works but emits a stderr warning

### 6.3 Integration tests

`tests/integration/beads-health-repair-flow.bats` (new):

- BHRF-T1: dirty-db + `beads-health.sh --repair` → HEALTHY
- BHRF-T2: healthy-db + `beads-health.sh --repair` → no-op, HEALTHY
- BHRF-T3: dirty-db + `beads-health.sh --repair --dry-run` → status still needs_repair
- BHRF-T4: dirty-db + `beads-health.sh --repair --json` → structured output includes pre/post status

### 6.4 Regression gate

`pytest` adapters suite + existing bats unchanged. Sprint exit:
- All BMR-T1..10 green
- All BHRF-T1..4 green
- `tests/unit/beads-health-monitor.bats` BHM-T1+BHM-T5 (currently FAILING in CI per KF-005) — verify they FLIP to PASS once repair runs against the BHM fixture

## 7. CI integration

New workflow `.github/workflows/beads-health-gate.yml` (or extend
existing if one exists):

```yaml
on:
  pull_request:
    paths:
      - '.claude/scripts/beads/**'
      - 'tools/beads-migration-repair.sh'
      - 'tests/fixtures/beads-migration/**'
      - 'tests/unit/beads-migration-repair.bats'
      - 'tests/integration/beads-health-repair-flow.bats'
      - '.github/workflows/beads-health-gate.yml'
  push:
    branches: [main]
    paths: (same)

jobs:
  beads-health:
    - Verify beads-health.sh + repair tool executable
    - Run bats coverage
    - Run integration tests
```

## 8. Upstream coordination

| Task | Audience | Outcome |
|------|----------|---------|
| File reproducer at Dicklesworthstone/beads_rust#290 | beads_rust maintainer | Add cycle-105 repair-flow evidence + propose the schema fix as PR |
| Update Loa #661 status | Loa maintainers | Mark as "Loa-side workaround landed in cycle-105"; defer hard close to upstream landing the actual fix |
| Add KF-005 attempts row | Loa contributors | Cycle-105 outcome documented for future cycles |

## 9. Risks (from PRD §7, refined)

| ID | Risk | Mitigation in this SDD |
|----|------|----------------------|
| R1 | Upstream lands a fix during cycle-105 | Repair tool is idempotent + no-op on healthy db; landing a fix just makes the heal step a no-op |
| R2 | Dirty-db has multiple root causes | Test corpus §6.1 covers 5 schema states; unrecognized exits 3 with operator action |
| R3 | Markdown fallback regresses when beads heals | Fallback is orthogonal — sprint.md checkboxes still authoritative; beads is additive |
| R4 | Repair corrupts a healthy db | Idempotency check §3.3 step 1 refuses to mutate HEALTHY state; --force is the explicit opt-in |
| R5 | SQLite version skew (3.x ALTER TABLE quirks) | The recreate-and-swap pattern uses only `CREATE TABLE`, `INSERT INTO ... SELECT`, `DROP TABLE`, `ALTER TABLE ... RENAME TO` — all standard SQLite 3 features available since 3.25 (we're on 3.40+) |

## 10. Q&A (SDD-time decisions)

**Q1: Why ALTER COLUMN via recreate-and-swap instead of `ALTER TABLE ALTER COLUMN`?**
A1: SQLite does not support `ALTER COLUMN`. The recreate-and-swap is the canonical pattern documented at https://www.sqlite.org/lang_altertable.html. Single transaction = atomic.

**Q2: Should the pre-commit hook run repair automatically?**
A2: No. Pre-commit hooks must be predictable and fast. The repair tool is an explicit operator action (or `beads-health.sh --repair` invocation). Pre-commit emits the WARN + suggests the tool; operator runs it once per dirty-db state.

**Q3: What about new operators who haven't hit the bug yet?**
A3: The repair tool's pre-flight check sees `dirty_issues_migration == "ok"` and exits no-op. There's no cost to running it preemptively. The protocol doc (T2.2) can recommend running it on `mount-loa` to seal fresh installs against the bug.

**Q4: Why is this Loa-side and not just "wait for upstream"?**
A4: Upstream issue beads_rust#290 was filed 2026-05-11 with no response. The cycle-102/103/104 cycles all hit this bug. Operator-time spent on `--no-verify` workarounds is real. The Loa-side workaround is a bridge, not a fork — when upstream lands the fix, the heal step becomes a no-op and the tool quietly retires.

**Q5: Risk of the repair removing data?**
A5: Zero, by design. The repair operates on the `dirty_issues` table only; `issue_id` is preserved as PRIMARY KEY; `marked_at` is backfilled (never overwritten). Backups guarantee rollback if anything unexpected happens.

---

🤖 Generated as cycle-105 SDD, 2026-05-12. Next step: `/sprint-plan` to break this into ~12 tasks across 2 sprints.
