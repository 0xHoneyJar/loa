# Cycle-105 PRD: beads_rust migration recovery

> **Status**: draft (PRD-only; awaiting /architect for SDD)
> **Cycle**: cycle-105-beads-recovery
> **Created**: 2026-05-12
> **Source**: KF-005 (grimoires/loa/known-failures.md), 3+ recurrences across cycles 102/103/104

---

## 1. Problem statement

Beads task tracking is the "EXPECTED DEFAULT" per CLAUDE.md Beads-First
Architecture v1.29.0. In practice it has been broken for every operator
upgrade path since beads_rust 0.2.1. Three independent migration
attempts (0.2.1 → 0.2.4 → 0.2.6) all fail with the same SQLite error:

```
run_migrations failed:
  Database(Internal("VDBE halted with code 19:
  NOT NULL constraint failed: dirty_issues.marked_at"))
```

Symptom: every `br` command (ready / create / update / sync) errors out;
`beads-health.sh --quick --json` returns `MIGRATION_NEEDED`. Operators
fall back to markdown task tracking (sprint.md checkboxes + reviewer.md
tables) and pass `git commit --no-verify` to bypass the beads pre-commit
hook.

Upstream issue [Dicklesworthstone/beads_rust#290](https://github.com/Dicklesworthstone/beads_rust/issues/290)
was filed 2026-05-11; no fix lands as of cycle-104 close. Downstream
Loa #661 was closed 2026-05-02 but the regression-on-dirty-database
class remained unfixed.

## 2. Cycle goals

| ID | Goal | Acceptance |
|----|------|-----------|
| G1 | **Stop the bleed** — Loa-side workaround makes `br` migration-resilient | Operator-fresh `br sync` on a known-dirty `.beads/` database succeeds OR falls back cleanly to markdown without the migration error surfacing in CI / pre-commit |
| G2 | **Pre-flight repair tool** — a Loa-side migration repair that closes the `dirty_issues.marked_at NOT NULL` gap locally | `tools/beads-migration-repair.sh` (or similar) takes a dirty .beads/ db and produces a healed db; idempotent; reversible |
| G3 | **Refresh upstream evidence** — append-only KF-005 attempts row with the cycle-105 fix-or-confirm-regression evidence | KF-005 row 5+ records the cycle-105 outcome with PR # / commit SHA; Loa #661 reopened OR updated with regression note |
| G4 | **CI gate** — pre-commit / beads-health hook never silently lets a broken migration through | `beads-health.sh --json` in CI fails with explicit `MIGRATION_NEEDED` annotation when applicable, never warns-and-passes |

## 3. Non-goals

- Re-implementing beads_rust in another language. The upstream tool is correct in scope; the fix is migration-side.
- Forking beads_rust. We collaborate with the upstream maintainer; the Loa-side workaround is a bridge until upstream lands the fix.
- Replacing markdown fallback. Markdown stays as the final safety net — beads becomes additive once it works.

## 4. Architecture sketch (informs /architect)

Three Loa-side surfaces touch beads:

| Surface | Current behavior | Cycle-105 target |
|---------|------------------|------------------|
| `.claude/scripts/beads/beads-health.sh` | Returns `MIGRATION_NEEDED` on dirty db; operator must intervene | Add a `--repair` flag that attempts the migration-repair flow; fall back to markdown on irrecoverable state |
| `.claude/protocols/beads-preflight.md` | Document-only protocol; operator follows manually | Wire to the health check's `--repair` flag; auto-attempt repair at workflow boundary |
| `.claude/hooks/pre-commit/beads-task-sync.sh` (or equivalent) | Bypassed via `--no-verify` | Tolerate `MIGRATION_NEEDED` state without blocking commit; surface in CI not in dev |

## 5. Sprint shape (informs /sprint-plan)

Estimated 2 sprints, 8-12 tasks total:

### Sprint 1 — Reproduce + investigate + Loa-side workaround
- T1.1 Pin the exact failure shape via a fresh `.beads/` corpus reproduction
- T1.2 Inspect beads_rust source for the migration SQL; characterize the bug class
- T1.3 Build `tools/beads-migration-repair.sh` that patches `marked_at` defaults
- T1.4 Bats coverage for the repair tool (positive + negative controls)
- T1.5 Wire repair tool into `beads-health.sh --repair` flag
- T1.6 Update `.claude/protocols/beads-preflight.md` to reference the repair flow

### Sprint 2 — CI gate + upstream collaboration + KF-005 closure
- T2.1 `beads-health.sh --json` CI annotation behavior
- T2.2 Pre-commit hook tolerance (don't block on MIGRATION_NEEDED; defer to CI)
- T2.3 Refresh KF-005 attempts row with cycle-105 evidence
- T2.4 File reproducer to upstream beads_rust#290 (Loa-shipped, operator-publishable)
- T2.5 Reopen Loa #661 with the regression note (or close-as-superseded by #290)

## 6. Acceptance criteria (informs /architect AC table)

| AC | Statement |
|----|-----------|
| AC-1 | `.claude/scripts/beads/beads-health.sh --repair` on a known-dirty fixture db produces an HEALTHY status |
| AC-2 | Bats coverage: positive control (dirty → healed), negative control (already-clean → no-op), failure mode (unrecoverable → markdown fallback signal) |
| AC-3 | Pre-commit hook does not exit non-zero on `MIGRATION_NEEDED` state; CI annotation includes the operator-facing remediation hint |
| AC-4 | KF-005 attempts row 5+ records the cycle-105 outcome with file:line citations |
| AC-5 | Loa #661 + beads_rust #290 cross-linked from KF-005 and the cycle-105 archive |

## 7. Risk register

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|-----------|--------|-----------|
| R1 | Upstream beads_rust ships a fix during cycle-105, making the Loa-side workaround vestigial | Medium | Low | Workaround is intentionally narrow: it heals the dirty-db state, then defers to beads_rust normal operation. A fixed upstream release just means the heal step is a no-op |
| R2 | The dirty-db state has more than one root cause; healing `marked_at` exposes a different downstream failure | Medium | Medium | T1.1 reproduction is structured as a corpus walk: heal → run health → if HEALTHY, done; if a different error, document and recurse |
| R3 | Operator's existing markdown fallback regresses when beads is re-enabled | Low | Medium | Sprint 2 explicitly tests that markdown fallback continues to work even when beads is healed — beads is additive, never authoritative |
| R4 | Repair tool corrupts a healthy database that wasn't actually dirty | Low | High | Tool is idempotent + reversible (creates a `.beads/_backup-<ts>` before mutation); refuses to operate on `HEALTHY` status |

## 8. Definition of done (cycle exit)

- [ ] All G1-G4 goals met per AC table
- [ ] Sprint 1 + Sprint 2 merged to main
- [ ] KF-005 status flipped from `DEGRADED-ACCEPTED` to either `RESOLVED-VIA-WORKAROUND` (Loa-side) or `RESOLVED-UPSTREAM` (if beads_rust lands the fix during the cycle)
- [ ] Operator can run `br ready` on a fresh repo init without manual intervention
- [ ] Beads-First architecture claim in CLAUDE.md is now empirically true (not aspirational)

## 9. Budget

- Engineering: 2-3 days operator-time across 2 sprints
- Live-API: **$0** (this is a local-tooling cycle; no model calls needed)
- Operator coordination: 1 round-trip with upstream beads_rust maintainer (optional, async)

## 10. Predecessor + successor

- **Predecessor**: cycle-104-multi-model-stabilization (archived 2026-05-12; v1.152.0). Cycle-105 has no functional dependency on cycle-104; it's an independent operational-debt cycle that has been deferred for ~3 cycles already.
- **Successor**: TBD per operator. With beads working, future cycles can use beads for task tracking as designed instead of the markdown fallback.

---

🤖 Generated as cycle-105 kickoff PRD, 2026-05-12. Next step: `/architect` to produce the SDD.
