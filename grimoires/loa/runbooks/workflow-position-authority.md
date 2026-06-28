# Runbook — Workflow Position Authority (filesystem wins; `.run` position is a cache)

**Status:** Contract / runbook (precursor to Sprint 7's reconcile implementation).
**Cycle:** OKF/ICM adoption (2026-06-28). **Source:** PR #1155 analysis (rec #8) + grounding brief.

## The precedence rule
For **where a workflow is** (its position in plan→implement→review→audit→deploy), the **filesystem is authoritative**:

| Authoritative for POSITION (filesystem) | Derived cache (reconcile before trust) | First-class state (no filesystem analog) |
|---|---|---|
| `grimoires/loa/a2a/**/COMPLETED` markers | `.run/sprint-plan-state.json` → `state`, `sprints.current`, `sprints.completed`, `sprints.list[].status` | `.run/circuit-breaker*.json` trigger counts |
| auditor `APPROVED` in `auditor-sprint-feedback.md` | | `cycle_count`, `max_cycles`, `timeout` |
| presence of `prd.md` / `sdd.md` / `sprint.md` | | post-compact recovery counters |

- `golden-path.sh` is **already** file-presence-authoritative for sprint/plan position (`_gp_sprint_is_complete` / `_gp_sprint_is_audited` read markers, never `.run/sprint-plan-state.json`; it reads other `.run/` files only for bug-lifecycle and bridge-loop state, which are not plan→audit position) — this runbook generalizes that to the resume paths.
- The `.run` **position** fields are a *derived cache*: they may be stale (documented `RUNNING`-while-committed drift) and MUST be reconciled against the filesystem before any decision that trusts them (e.g. run-mode's `state==RUNNING → "resume, do NOT ask"`).
- The `.run` **autonomy counters** (circuit-breaker trigger history, cycle counts, timeouts) are NOT position and have no filesystem analog — they remain first-class state and MUST NOT be demoted or rebuilt from presence.

## Reconcile-before-trust (Sprint 7 implements)
Run-mode / simstim resume MUST call a reconciliation that cross-checks `COMPLETED`/`APPROVED` markers against the cached position and rewrites the cache (`git_inferred: true`) on mismatch **before** acting on `state==RUNNING`. Precedent: `simstim-orchestrator.sh --sync-run-mode` (extend it to use markers, not just commit-counting). A mandatory drift-repro test pins: cache says RUNNING/0-completed while markers show all sprints complete → resolver reports complete (filesystem wins) and counters are preserved untouched.

## Related defect
`next-bug-sprint-id.sh` must derive the next id from `ledger.global_sprint_counter + 1` (+ correctly-anchored dir scan + cycle claims), NOT from an in-file markdown body grep (which harvested a stray `sprint-bug-622` token → wrong `next=623`). Fixed in Sprint 7 with a regression test.
