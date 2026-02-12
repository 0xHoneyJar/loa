# Bug Lifecycle Protocol

**Version:** 1.0.0
**Status:** Active
**Updated:** 2026-02-12

---

## Overview

Bug mode provides a separate lifecycle from the standard sprint workflow. Bugs bypass PRD/SDD gates (they're fixing observed failures, not building new features) and follow a dedicated state machine with strict transition rules.

## State Machine

```
                ┌──────────┐
                │  TRIAGE  │
                └────┬─────┘
                     │
                     ▼
              ┌──────────────┐
         ┌───>│ IMPLEMENTING │<───┐
         │    └──────┬───────┘    │
         │           │            │
         │           ▼            │
         │    ┌──────────────┐    │
         │    │  REVIEWING   │────┘ (rework)
         │    └──────┬───────┘
         │           │
         │           ▼
         │    ┌──────────────┐
         └────│  AUDITING    │
  (rework)    └──────┬───────┘
                     │
                     ▼
              ┌──────────────┐
              │  COMPLETED   │ (terminal)
              └──────────────┘

  Any state ──────> HALTED (terminal)
```

## Valid Transitions

| From | To | Guard Condition |
|------|----|-----------------|
| TRIAGE | IMPLEMENTING | Triage handoff contract exists (`triage.md`) |
| IMPLEMENTING | REVIEWING | Fix committed, tests written and passing |
| REVIEWING | IMPLEMENTING | Review found required changes (rework loop) |
| REVIEWING | AUDITING | Review passed, no required changes |
| AUDITING | IMPLEMENTING | Audit found security issues (rework loop) |
| AUDITING | COMPLETED | Audit approved |
| ANY | HALTED | Manual halt or circuit breaker triggered |

## Terminal States

- **COMPLETED**: Bug fix verified and approved. No transitions out.
- **HALTED**: Bug abandoned or blocked. No transitions out.

Neither COMPLETED nor HALTED bugs trigger `bug_active` state in the golden path.

## Transition Validation

`golden_validate_bug_transition()` in `golden-path.sh` enforces the transition table:

```bash
golden_validate_bug_transition() {
    local current="$1" proposed="$2"

    # HALTED is always valid from any state
    [[ "$proposed" == "HALTED" ]] && return 0

    # Terminal states block all transitions
    [[ "$current" == "COMPLETED" || "$current" == "HALTED" ]] && return 1

    case "$current" in
        TRIAGE)       [[ "$proposed" == "IMPLEMENTING" ]] ;;
        IMPLEMENTING) [[ "$proposed" == "REVIEWING" ]] ;;
        REVIEWING)    [[ "$proposed" == "IMPLEMENTING" || "$proposed" == "AUDITING" ]] ;;
        AUDITING)     [[ "$proposed" == "IMPLEMENTING" || "$proposed" == "COMPLETED" ]] ;;
        *)            return 1 ;;
    esac
}
```

## State File

**Path**: `.run/bugs/{bug_id}/state.json`

```json
{
  "bug_id": "bug-20260212-abc123",
  "state": "IMPLEMENTING",
  "bug_title": "Login fails with special characters",
  "created_at": "2026-02-12T10:00:00Z",
  "updated_at": "2026-02-12T11:30:00Z"
}
```

## TOCTOU-Safe Detection

Bug detection uses hash-based verification to prevent time-of-check/time-of-use races:

1. `golden_detect_active_bug()` returns `bug_id:state_hash`
2. `golden_parse_bug_id()` extracts the bug_id
3. `golden_verify_bug_state()` re-checks the hash before acting

```bash
# Detection
active_ref=$(golden_detect_active_bug)
bug_id=$(golden_parse_bug_id "$active_ref")
state_hash="${active_ref#*:}"

# ... time passes, state may change ...

# Verification before action
if golden_verify_bug_state "$bug_id" "$state_hash"; then
    # Safe to act — state unchanged
else
    # State changed — re-detect
fi
```

## Active Bug Detection

`golden_detect_active_bug()` scans `.run/bugs/*/state.json` for any bug NOT in COMPLETED or HALTED state. When multiple active bugs exist, the most recently modified takes priority.

## Bug Journey Visualization

When a bug is active, the golden path journey bar switches to the bug lifecycle:

```
/triage ━━━━━ /fix ●━━━━━ /review ─━━━━━ /close ─
```

Position mapping (`_gp_bug_journey_position()`):

| State | Position |
|-------|----------|
| TRIAGE | triage |
| IMPLEMENTING | fix |
| REVIEWING | review |
| AUDITING | review |
| COMPLETED | close |
| HALTED | fix |

## Golden Path Integration

Bug mode overrides normal workflow state:

- `golden_detect_workflow_state()` returns `bug_active` when any active bug exists (priority 1, checked before all other states)
- `golden_suggest_command()` returns `/build` for active bugs
- `golden_menu_options()` shows bug-specific actions: "Fix bug: {title}", "Return to feature sprint"
- `golden_resolve_truename("build")` routes to `/implement sprint-bug-N` for bug micro-sprints

## Micro-Sprint

Each bug gets its own micro-sprint:

- **Sprint file**: `grimoires/loa/a2a/bug-{id}/sprint.md`
- **Sprint ID**: `sprint-bug-N` (bypasses `_gp_validate_sprint_id()` via early return)
- **Detection**: `golden_detect_micro_sprint()` checks if sprint file exists

## Cross-References

| Resource | Purpose |
|----------|---------|
| `.claude/scripts/golden-path.sh` | State machine, detection, journey |
| `skills/bug-triaging/SKILL.md` | Triage workflow details |
| `.claude/protocols/sprint-completion.md` | Standard sprint lifecycle |
| `.claude/data/constraints.json` | Bug eligibility rules |
