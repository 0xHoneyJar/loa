# NOTES

## Session Continuity

### 2026-10-21 — /audit-sprint sprint-1 (task review-r27)
- Audit written: `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md` — CHANGES_REQUIRED (0 critical, 3 high, 7 medium, 8 low; excluded 0 / excluded_confirmed 0).
- Prerequisite deviation: review verdict was CHANGES_REQUIRED, not "All good"; audit ran on the task's explicit instruction.
- Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (gpt-5.5-pro clean; claude-headless 4 findings; 0 rejected; not degraded).
- Observed in this harness: Claude Code marks `for … do diff …; done` and `sdiff` results `is_error` with "Exit code 1" + full output; a bare `diff`/`diff -u`/`git diff --no-index` is not flagged. Relevant to `ablation-grade.sh:2390`.
- `grimoires/loa/known-failures.md` is absent (hook warning); `br` not installed (beads steps skipped).
