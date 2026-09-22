# run-mode Bug Run Mode (`/run --bug`)

Autonomous bug fixing with triage → implement → review → audit cycle.

## Bug Run Loop

```
/run --bug "description"
       ▼
  TRIAGE       Invoke bug-triaging skill → triage.md, micro-sprint
       ▼
  IMPLEMENT    /implement sprint-bug-{N}   (test-first: write test → fix → verify)
       ▼
  REVIEW       /review-sprint sprint-bug-{N}   — findings → back to IMPLEMENT
       ▼
  AUDIT        /audit-sprint sprint-bug-{N}    — findings → back to IMPLEMENT
       ▼
  COMPLETE     COMPLETED marker + draft PR
```

## Bug Run Execution

1. **Pre-flight**: same as standard run (config check, ICE, permissions).
2. **Branch**: create `bugfix/{bug_id}` via ICE.
3. **Triage**: invoke `/bug` with the description or `--from-issue N` (passes the issue number to
   bug-triaging). Produces `triage.md` and a micro-sprint under `grimoires/loa/a2a/bug-{id}/`.
4. **High-risk check**: read `risk_level` from bug state. If `high` and `--allow-high` not set →
   HALT: "High-risk area detected (auth/payment/migration). Use --allow-high to proceed."
5. **Implementation loop**: same shape as the standard main loop but with the bug-scoped circuit
   breaker (below), targeting `sprint-bug-{N}`.
6. **Completion**: draft PR with confidence signals (below).

## Bug-Scoped Circuit Breaker

Tighter limits (bug scope is smaller), stored in `.run/bugs/{bug_id}/circuit-breaker.json`
(namespaced per bug):

| Trigger | Limit | Rationale |
|---------|-------|-----------|
| Same Issue | 3 cycles | Bug fix shouldn't need >3 review cycles |
| No Progress | 5 cycles | If no file changes, bug may be misdiagnosed |
| Cycle Limit | 10 total | Reduced from 20 (smaller scope) |
| Timeout | 2 hours | Reduced from 8 (smaller scope) |

## Bug State File

Per-bug namespaced state in `.run/bugs/{bug_id}/state.json`:
→ verbatim block: `resources/state-schemas.md` §bug-state-schema

## Bug PR Creation (Confidence Signals)

On completion, create a draft PR via ICE:
→ verbatim block: `resources/render-templates.md` §bug-pr-body
Bug PRs are always draft and never auto-merged — ICE never creates a ready-for-review PR — so
human approval is required before merging.

## High-Risk Area Detection

Triage checks suspected files against the high-risk keyword list (auth/payment/migration/secrets classes); autonomous mode HALTs on `high` without `--allow-high`; interactive mode warns and asks. Full keyword list + mode table: → `resources/render-templates.md` §high-risk-area-detection.
