# Cycle-105 Sprint Plan: beads_rust migration recovery

> **Status**: draft (awaiting implementation)
> **Predecessors**: `prd.md`, `sdd.md`
> **Cycle**: cycle-105-beads-recovery
> **Created**: 2026-05-12
> **Local sprint IDs**: sprint-1, sprint-2 (global IDs 154, 155 per ledger `next_sprint_number=154`)

---

## 1. Sprint shape

| Sprint | Theme | Tasks | Live API | Days |
|--------|-------|-------|---------|------|
| Sprint 1 | Repair tool + bats coverage | 6 | $0 | 1-2 |
| Sprint 2 | CI gate + protocol + KF-005 closure | 5 | $0 | 1 |

**Total**: 11 tasks across 2 sprints; ~2-3 days operator-time.

**Sequencing**: Sprint 1 must land before Sprint 2 (Sprint 2 wires the repair tool into the pre-commit + CI surfaces; tool must exist first).

---

## 2. Sprint 1 — Repair tool + bats coverage

**Goal**: G1 + G2 from PRD §2 — `tools/beads-migration-repair.sh` exists, heals dirty `.beads/` databases, has bats coverage with positive + negative + idempotency controls.

### Tasks

- [ ] **T1.1** Build fixture corpus under `tests/fixtures/beads-migration/`. 5 fixtures per SDD §6.1:
    - `dirty-db.sql` — marked_at NOT NULL with no DEFAULT
    - `healthy-db.sql` — proper DEFAULT CURRENT_TIMESTAMP
    - `missing-table-db.sql` — dirty_issues missing entirely
    - `partial-schema-db.sql` — dirty_issues with extra columns
    - `dirty-with-rows-db.sql` — dirty + NULL marked_at rows
    Each fixture is a `.sql` script that `bats setup()` materializes into a fresh SQLite db. → **[G1, G2]**

- [ ] **T1.2** Implement `tools/beads-migration-repair.sh` per SDD §3.2 (recreate-and-swap SQL), §3.3 (idempotency + safety), §3.4 (history log). All four exit codes (0/1/2/3) honored. → **[G2]**

- [ ] **T1.3** Bats unit tests `tests/unit/beads-migration-repair.bats` — BMR-T1 through BMR-T10 per SDD §6.2. All 10 tests must be green. → **[G2]**

- [ ] **T1.4** Bats integration tests `tests/integration/beads-health-repair-flow.bats` — BHRF-T1 through BHRF-T4 per SDD §6.3. Exercises `beads-health.sh --repair` end-to-end. → **[G1]**

- [ ] **T1.5** Wire `--repair` flag into `beads-health.sh` per SDD §4. Pass-through for `--dry-run` / `--force` / `--json`. → **[G1]**

- [ ] **T1.6** Sanity-test against the operator's real-world dirty database: copy `.beads/beads.db` to a scratch dir, run repair on the COPY, verify HEALTHY status post-repair. Operator's live db untouched until they explicitly run repair on it. → **[G1]**

### Sprint 1 exit

- All BMR-T1..10 green
- All BHRF-T1..4 green
- Scratch-dir sanity test on operator's real dirty db passes
- `beads-health.sh --repair` is a documented surface
- No regressions in existing bats / pytest suites

---

## 3. Sprint 2 — CI gate + protocol + KF-005 closure

**Goal**: G3 + G4 from PRD §2 — CI gate tightened, pre-commit hook tolerance landed, KF-005 row updated, upstream coordinated.

### Tasks

- [ ] **T2.1** Update pre-commit hook (`.claude/hooks/pre-commit/beads-task-sync.sh` or equivalent) to WARN-not-FAIL on MIGRATION_NEEDED. Hook emits the repair-tool suggestion + the `--no-verify` immediate fallback; exits 0. → **[G4]**

- [ ] **T2.2** Update `.claude/protocols/beads-preflight.md` to document the auto-repair flow. Add the `beads-health.sh --repair` invocation as the canonical first-action when MIGRATION_NEEDED surfaces. → **[G1, G4]**

- [ ] **T2.3** New CI workflow `.github/workflows/beads-health-gate.yml` per SDD §7. Runs the BMR + BHRF bats coverage on every PR that touches beads scripts / fixtures / workflows. Fails CI on regressions. → **[G4]**

- [ ] **T2.4** Update KF-005 attempts row in `grimoires/loa/known-failures.md` — append cycle-105 outcome row. Update status header from `DEGRADED-ACCEPTED` to either `RESOLVED-VIA-WORKAROUND` (Loa-side fix landed) or `RESOLVED-UPSTREAM` if beads_rust shipped the fix during cycle-105. → **[G3]**

- [ ] **T2.5** File reproducer + workaround link to upstream beads_rust#290 (Loa-shipped). Update Loa #661 with the cycle-105 evidence (Loa-side workaround landed; deferring hard close to upstream landing the actual fix). → **[G3]**

### Sprint 2 exit

- Pre-commit hook tolerates MIGRATION_NEEDED with WARN
- `beads-preflight.md` references the repair flow
- CI workflow green on the new fixtures
- KF-005 status flipped + attempts row updated
- Upstream coordinated (beads_rust#290 + Loa #661)

---

## 4. Acceptance criteria (per PRD §6)

| AC | Sprint | Closing evidence |
|----|--------|-----------------|
| AC-1 | Sprint 1 (T1.5) | `beads-health.sh --repair` on dirty fixture → HEALTHY |
| AC-2 | Sprint 1 (T1.3) | BMR-T1..T10 all green; positive + negative + idempotency controls present |
| AC-3 | Sprint 2 (T2.1) | Pre-commit hook exits 0 on MIGRATION_NEEDED; CI annotation includes remediation hint |
| AC-4 | Sprint 2 (T2.4) | KF-005 attempts row 5+ with cycle-105 outcome |
| AC-5 | Sprint 2 (T2.5) | Loa #661 + beads_rust #290 cross-linked from KF-005 |

---

## 5. Dependencies

- **Inbound**: cycle-105 PRD merged (PR #854 ✓) + cycle-104 archived (operator-local ✓)
- **Live API**: $0 across both sprints (local tooling cycle)
- **CLI binaries**: sqlite3 must be on PATH (CI runner default; verify in T1.2)
- **Outbound**: With beads working post-cycle-105, future cycles can adopt beads task tracking as designed; CLAUDE.md Beads-First v1.29.0 becomes empirically true rather than aspirational.

---

## 6. Risk register (refined from SDD §9)

| ID | Sprint affected | Mitigation |
|----|-----------------|-----------|
| R1 | Either | Idempotency makes upstream-fix-landing a no-op event |
| R2 | Sprint 1 (T1.1, T1.2) | 5-fixture corpus probes 5 schema states; unrecognized exits 3 |
| R3 | Sprint 2 (T2.2) | Protocol explicitly documents markdown fallback as the safety net |
| R4 | Sprint 1 (T1.2) | Pre-flight check + backup before any mutation; refuses HEALTHY without --force |
| R5 | Either | SQLite features used are 3.25+; CI confirms version at workflow startup |

---

## 7. Definition of done (cycle exit)

- [ ] All 11 tasks shipped
- [ ] AC-1..AC-5 all closed
- [ ] KF-005 status flipped
- [ ] CLAUDE.md Beads-First architecture claim is empirically true
- [ ] Operator can run `br ready` on a fresh repo init without manual intervention
- [ ] Sprint 1 + Sprint 2 PRs merged to main

---

🤖 Generated as cycle-105 sprint plan, 2026-05-12. Next step: `/run sprint-1` autonomous loop over T1.1-T1.6.
