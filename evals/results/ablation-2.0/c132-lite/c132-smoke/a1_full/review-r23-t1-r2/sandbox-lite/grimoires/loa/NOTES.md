# NOTES

## Session Continuity

- 2026-10-21 /review-sprint sprint-1 (task review-r23): CHANGES_REQUIRED, 4 high / 8 medium / 12 low. Feedback: grimoires/loa/a2a/sprint-1/engineer-feedback.md. Dissent envelope: a2a/sprint-1/adversarial-review.json (2 voices, 9 advisory, 0 rejected).
- Host facts that mattered: python 3.11.2 (no tarfile.data_filter), no GNU patch, TMPDIR=/workspace/.eval/tmp (inside the checkout), pytest 9.0.2 present; the evals/ tree the bats suites need is not in this workspace.
- known-failures.md is missing (hook warning at session start); triaged without it.
- 2026-10-21 /audit-sprint sprint-1 (task review-r23): CHANGES_REQUIRED, 0 critical / 7 high / 11 medium / 16 low, excluded_confirmed 0. Feedback: grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md. Ran on orchestrator instruction although the review was not "All good" (deviation recorded in the report). Dissent: a2a/sprint-1/adversarial-audit.json (2 voices, consensus, 8 findings, 0 rejected, not degraded). New beyond the review: grader opens any path a test line names (FIFO/`/dev/zero` hang, reproduced); hidden-test result forgeable by one printed summary line (reproduced); remove_path chmods through agent symlinks onto host dirs (reproduced); host executor runs sandbox code as the operator; seeder drops +x from fixture files (reproduced). `br` not installed; beads steps skipped. findings.jsonl: a2a/audits/2026-10-21/.
