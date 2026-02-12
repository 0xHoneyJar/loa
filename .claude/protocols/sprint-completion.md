# Sprint Completion Lifecycle

**Version:** 1.0.0
**Status:** Active
**Updated:** 2026-02-12

---

## Overview

Sprint completion follows a strict implement → review → audit → complete pipeline. Each gate must pass before the next can execute. The `COMPLETED` marker file is the authoritative signal that a sprint has cleared all quality gates.

## State Transitions

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  IMPLEMENT   │───>│   REVIEW     │───>│   AUDIT      │───>│  COMPLETED   │
│ /implement   │    │ /review-sprint│   │ /audit-sprint │    │  COMPLETED   │
│ sprint-N     │    │ sprint-N     │    │ sprint-N     │    │  marker file │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                         │                    │
                         │  Changes Required  │  Changes Required
                         └────────────────────┘
                              ↓
                         Back to IMPLEMENT
```

## COMPLETED Marker

**File**: `grimoires/loa/a2a/sprint-N/COMPLETED`

**Created by**: The `audit-sprint` skill (`skills/auditing-security/`) upon APPROVED verdict.

**Detection**: `golden-path.sh` checks for this marker via:

```bash
_gp_sprint_is_complete() {
    local sprint_id="$1"
    local sprint_dir="${_GP_A2A_DIR}/${sprint_id}"
    [[ -f "${sprint_dir}/COMPLETED" ]]
}
```

## Detection Functions

### `golden_detect_sprint()`

Finds the first incomplete sprint by iterating sprint-1 through sprint-N:

```
for each sprint-N:
  if COMPLETED marker missing → return "sprint-N"
if all complete → return ""
```

### `golden_detect_review_target()`

Finds the first sprint needing review:

```
for each sprint-N:
  skip if COMPLETED
  if sprint dir exists (work started) → return "sprint-N"
return ""
```

### `_gp_sprint_is_reviewed()`

A sprint is considered reviewed if:
1. It has already been audited (audit implies review passed), OR
2. `engineer-feedback.md` exists AND contains no "Changes Required", "Findings", or "Issues" sections

### `_gp_sprint_is_audited()`

A sprint is audited if `auditor-sprint-feedback.md` exists and contains "APPROVED".

## A2A Directory Structure

```
grimoires/loa/a2a/sprint-N/
├── engineer-feedback.md        # /review-sprint output
├── auditor-sprint-feedback.md  # /audit-sprint output
├── COMPLETED                   # Marker file (created on audit approval)
└── ... (other sprint artifacts)
```

## Ledger Integration

When a Sprint Ledger exists (`grimoires/loa/ledger.json`):

- Local sprint IDs (sprint-1, sprint-2) map to global IDs via the ledger
- `/implement`, `/review-sprint`, and `/audit-sprint` all resolve local → global IDs
- The `COMPLETED` marker uses the local sprint directory structure
- Ledger sprint entries track status independently (but should be consistent)

## Run Mode Integration

In `/run sprint-plan`, the completion lifecycle runs autonomously:

1. `/implement sprint-N` executes tasks
2. `/review-sprint sprint-N` validates implementation
3. `/audit-sprint sprint-N` performs security audit
4. If audit APPROVED → COMPLETED marker created → next sprint
5. If audit/review fails → cycle back to implement (circuit breaker limits retries)

## Cross-References

| Resource | Purpose |
|----------|---------|
| `.claude/scripts/golden-path.sh` | State detection functions |
| `.claude/protocols/run-mode.md` | Autonomous execution lifecycle |
| `skills/reviewing-code/SKILL.md` | Review gate details |
| `skills/auditing-security/SKILL.md` | Audit gate details |
