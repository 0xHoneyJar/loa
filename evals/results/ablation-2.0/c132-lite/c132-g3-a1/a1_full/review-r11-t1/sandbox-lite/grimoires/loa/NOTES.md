# NOTES

## Session Continuity

- 2026-10-22 /review-sprint sprint-1 (task review-r11): CHANGES_REQUIRED written to a2a/sprint-1/engineer-feedback.md (2 high: cheval.py:2119 walk gate vs count_tokens; BB config.ts:172 alias default). Workspace checkout is LATER than the PR (cycle-127/129 refs); adapter-level pytest not runnable on a head overlay — reviewed by reading.
- 2026-10-22 /audit-sprint sprint-1 (task review-r11): CHANGES_REQUIRED written to a2a/sprint-1/auditor-sprint-feedback.md (critical 0 / high 2 / medium 6 / low 8; excluded 0, excluded_confirmed 0). Highs confirmed: cheval.py:2119 walk gate re-estimates after count_tokens; BB config.ts:172 `opus` alias unresolved by getTokenBudget (no alias table at head; the later checkout adds GENERATED_MODEL_ALIASES). New security medium: provider error numbers persisted as an input bound with no plausibility check (cheval.py:2005, ceiling.py:122). Dissent: 2 voices reviewed, 5 findings (3 M / 2 L), no rejected payloads, not degraded. Phase 0 gate: review was CHANGES REQUIRED, audit run on operator instruction. No COMPLETED marker. known-failures.md unreadable on this mount.
