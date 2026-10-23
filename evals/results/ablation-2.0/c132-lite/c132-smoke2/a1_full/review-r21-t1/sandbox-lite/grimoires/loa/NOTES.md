# NOTES

## Session Continuity

- 2026-10-21 — `/review-sprint sprint-1` (task review-r21, PR sprint-257 / cycle-129, 80 files) complete. Verdict APPROVED
  (0 critical, 0 high, 3 medium, 9 low) in `grimoires/loa/a2a/sprint-1/engineer-feedback.md`; mirror in `review.md`.
  Verified: 123 pytest passed, 45 bats ok / 1 skip, dist manifest hashes match. Dissent refused `budget_exceeded`
  (955c > 200c, gpt-5.5-pro on a 680 KB diff) and was recorded as the fallback envelope — re-run before COMPLETED.
  Follow-up worth a task: provider-level `dispatch_group` honoured by planners but not by cheval request-time rules / MODELINV.

- 2026-10-21 — `/audit-sprint sprint-1` (task review-r21) complete. Verdict APPROVED (0 critical, 0 high, 5 medium, 9 low; excluded_confirmed 0) in `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md`; verdict-derive consistent. New vs review: MED-001 probe `--provider <configured>` runs the probe host allowlist so an https declared provider is ENDPOINT-NOT-ALLOWED; MED-002 Bridgebuilder trusted config gates the plan only — cheval dispatch reads the working-tree .loa.config.yaml. Audit dissent refused `budget_exceeded` (955c > 200c) → fallback recorded in adversarial-audit.json (no metadata.model): COMPLETED marker NOT written; re-run the dissent with an admitted budget/primary first.

## Learnings
- [2026-10-21T13:15:00Z] [reviewing-code] Eval sandbox: adversarial-review.sh is mode 0644 (exit 126 Permission denied) — invoke it as 'bash .claude/scripts/adversarial-review.sh …'. A 680 KB diff with primary gpt-5.5-pro estimates 955c against budget_cents 200 (status budget_exceeded, exit 4) and the cycle-129 script does not read budget_scale: diff; record it with --record-fallback budget_exceeded --reason "<its stdout line>" --since <run-started time> (--reason is mandatory; the call exits 2 without it) and proceed single-model; the same gate refuses the audit dissent identically. → skills-pending/learning-20261021-dissent-budget-fallback
- [2026-10-21T13:15:00Z] [reviewing-code] Running a PR's own tests in the eval layout: pytest for .claude/adapters/tests resolves REPO_ROOT through symlinks, so the PR's .loa.config.yaml.example must be copied to the real workspace root (remove it afterwards); bats suites run from a scratch root holding tests/ plus a .claude symlink to the workspace framework. → skills-pending/learning-20261021-eval-test-staging
- [2026-10-21T13:15:00Z] [reviewing-code] When the workspace .claude/ files are byte-identical to pr/head (cmp the touched scripts), untouched helpers and callers can be grepped there and the PR's Python/bats tests executed against the head framework instead of reviewing the diff blind. → skills-pending/learning-20261021-workspace-matches-head
