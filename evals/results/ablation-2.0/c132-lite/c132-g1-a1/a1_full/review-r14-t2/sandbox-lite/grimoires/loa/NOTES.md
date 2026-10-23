# NOTES

## Session Continuity

- 2026-10-21 /review-sprint sprint-1 (task review-r14): CHANGES_REQUIRED written to a2a/sprint-1/engineer-feedback.md and review.md; dissent envelope a2a/sprint-1/adversarial-review.json (clean, 0 rejected). Key: implement-gate.sh:128 opt-in allows on model-authored active_skill; catalog long_context inconsistency; check-permissions universal rule; model-adapter mktemp under set -e; Agent Teams table unregenerated (10,715 B > 10,240).
- 2026-10-21 /audit-sprint sprint-1 (task review-r14): CHANGES_REQUIRED written to a2a/sprint-1/auditor-sprint-feedback.md (critical 0 / high 2 / medium 5 / low 10, excluded 0, excluded_confirmed 0); dissent envelope a2a/sprint-1/adversarial-audit.json (clean, 4 findings, 0 rejected, companion succeeded). Ran despite review not "All good" per task directive. New vs review: `{"decision":"ask"}` is not a PreToolUse decision (docs: hookSpecificOutput.permissionDecision) → fence never asks, raised to HIGH; `Bash(:*)` → bare `*` key aliases the all-elements subscript. Working files: a2a/audits/2026-10-21/{SECURITY_ANALYSIS_TODO.md,findings.jsonl}.
