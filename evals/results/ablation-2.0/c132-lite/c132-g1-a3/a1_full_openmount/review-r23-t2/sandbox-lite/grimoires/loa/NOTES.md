# NOTES

## Session Continuity

- 2026-10-22 audit (sprint-1, task review-r23): `/audit-sprint sprint-1` run on the frozen PR in `pr/`. Prerequisite deviation: the review gate said CHANGES REQUIRED, the task instructions directed the audit to run anyway. Output: `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md` (CHANGES_REQUIRED; 0 critical / 8 high / 7 medium / 10 low). Working file: `grimoires/loa/a2a/audits/2026-10-22/SECURITY_ANALYSIS_TODO.md`; findings JSONL beside it. Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` (gpt-5.5-pro + claude-headless, 8 findings, 0 rejected). PoC scripts under `.run/tmp/poc/`.
- Environment facts that matter for re-runs: python3 is 3.11.2 (no `tarfile.data_filter`), bats is `/usr/local/bin/bats`, docker and `patch` are not installed, `br` is not installed.

## Learnings
- [2026-10-22T00:45:33Z] [auditing-security] Python-in-heredoc harness scripts (exec python3 -I - <<'PY') can be unit-exercised by slicing the heredoc body into a scratch module and exec-ing it with sys.argv set to the wrapper's positional args; used here for the grader reproductions under .run/tmp/poc/.
