# NOTES

## Session Continuity

- 2026-10-21 `/audit-sprint sprint-1` (task review-r22): audited `pr/head.diff` (Sprint 258). Verdict CHANGES_REQUIRED (0C/6H/5M/8L; excluded 0, excluded_confirmed 0). Feedback: `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md`; recon + findings.jsonl: `a2a/audits/2026-10-21/`; dissent envelope: `a2a/sprint-1/adversarial-audit.json` (2/2 voices, 6 findings, 0 rejected). New vs review: HIGH-001 `lib/sandbox-mount.sh:513` runs the mounted tree's update-beads-state.sh on the host when br is absent. Phase 0 prerequisite (review approved) was not met; ran on operator instruction. jq 1.6 and no br on this host.
- 2026-10-21 `/review-sprint sprint-1` (task review-r22): reviewed `pr/head.diff` (Sprint 258). Verdict CHANGES_REQUIRED (5 high). Feedback: `grimoires/loa/a2a/sprint-1/engineer-feedback.md`; brief-shaped list: `review.md`. Dissent envelope: `a2a/sprint-1/adversarial-review.json` (2/2 voices, DISS-001 blocking confirmed). Verification used a merged tree (workspace `.claude/` + PR head) under `.eval/tmp/`; `/tmp` is noexec and jq is 1.6 on this host.

## Learnings

- [2026-10-21T14:52:00Z] [auditing-security] auditing-security: the eval.yml grader trust-boundary scan matches `source` lines only; `bash "$ws/.claude/..."` on a script copied from the mounted tree evades it. When auditing harness code, grep for bash/python execution of sandbox or prompt-tree paths, not just source lines (found in sandbox-mount.sh init_sandbox_beads, Sprint 258 audit). → skills-pending/learning-20261021T1452-tb-exec
