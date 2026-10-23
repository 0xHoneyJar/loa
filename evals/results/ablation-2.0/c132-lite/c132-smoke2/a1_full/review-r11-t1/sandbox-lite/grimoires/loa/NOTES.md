# NOTES

## Learnings
- [review tooling] Frozen-PR test overlay + providers-package init bypass when the workspace drifted past the PR base → See `skills-pending/frozen-pr-head-overlay-tests`

## Session Continuity
- 2026-10-21 /review-sprint sprint-1 (task review-r11): CHANGES_REQUIRED (high 3: retry.py:495, cheval.py:2119, config.ts:172). Feedback: grimoires/loa/a2a/sprint-1/engineer-feedback.md; dissent envelope beside it; review.md at repo root per task-brief contract.
- 2026-10-21 /audit-sprint sprint-1 (task review-r11): CHANGES_REQUIRED (critical 0, high 3, medium 7, low 12; excluded_confirmed 0). HIGH-001 retry.py:495 reproduced by execution in the /tmp/headtree overlay; dissent `adversarial-audit.json` sole_voice claude-headless → DEGRADED_SECURITY_REVIEW. Prerequisite deviation: review gate was CHANGES_REQUIRED, audit run on task instruction; no COMPLETED marker. Feedback: grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md; findings.jsonl under a2a/audits/2026-10-21/; review.md at root extended with the audit's new findings.
