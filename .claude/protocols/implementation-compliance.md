# Implementation Compliance Protocol

## Purpose

Pre-implementation checklist ensuring all prerequisites are met before writing application code. This protocol is referenced by CLAUDE.loa.md, simstim-workflow, autonomous-agent, and implementing-tasks skills.

## Pre-Implementation Checklist

| # | Check | Required? | How to Verify |
|---|-------|-----------|---------------|
<!-- @constraint-generated: start pre_implementation_checklist | hash:a68704dfe60c93f4 -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
| 1 | Sprint plan exists | ALWAYS | `test -f grimoires/loa/sprint.md` |
| 2 | Beads tasks created | When beads HEALTHY | `br list` shows sprint tasks |
| 3 | No unaddressed audit feedback | ALWAYS | Check `auditor-sprint-feedback.md` |
| 4 | No unaddressed review feedback | ALWAYS | Check `engineer-feedback.md` |
| 5 | On feature branch | ALWAYS | `git branch --show-current` is not main/master |
| 6 | Using /run or /bug (not direct /implement) | For autonomous/simstim | /run wraps implement+review+audit |
<!-- @constraint-generated: end pre_implementation_checklist -->
## Error Codes

| Violation | Error Code |
|-----------|------------|
| No sprint plan | LOA-E110 |
| Direct implementation | LOA-E111 |
| Missing beads tasks | LOA-E112 |
| Skipped review/audit | LOA-E113 |
| Wrong task tracker | LOA-E114 |

## Task Tracking Decision Tree

```
Is beads available? (br --version)
├─ YES → Use br commands for ALL sprint task tracking
│        TaskCreate only for session progress display
│
└─ NO  → Use markdown tracking in NOTES.md
          TaskCreate acceptable as fallback
```

## Enforcement Layers

This protocol is enforced at 4 levels:

1. **CLAUDE.loa.md** — "Process Compliance" section (loaded every session)
2. **SKILL.md `<constraints>`** — Phase enforcement (loaded per skill)
3. **This protocol** — Referenced checklist (loaded on demand)
4. **Error codes** — Diagnostic codes (surfaced by /loa doctor, scripts)

## Related

- CLAUDE.loa.md → Process Compliance section
- `.claude/protocols/beads-preflight.md` → Beads health checking
- `.claude/protocols/run-mode.md` → /run lifecycle
- `.claude/data/error-codes.json` → Error code registry
