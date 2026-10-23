# Reviewer concerns — sprint-1 (PR: sprint-260 batch runner, report, grader calibration)

Scope: pr/head.diff (17 files). New: evals/harness/run-ablation.sh, evals/harness/ablation-report.py,
evals/harness/lib/arms-common.sh, tests and stubs. Modified: ablation-grade.sh (grader 1.2.1–1.2.5),
ablation-row.sh (DEC-0545 degraded rule), run-arms.sh (helpers extracted to the lib), suite yaml.

## Findings so far (reviewer's own, for the dissenter to confirm or challenge)

1. HIGH — ablation-grade.sh HEREDOC regex (`<<-?\s*(['"]?)(\w+)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)`, re.S)
   backtracks exponentially when a `<<WORD` opener has no terminator line: measured 3 s at 22 lines,
   doubling per line. Any Bash tool_use with a `<<` token (here-string `<<<'X'`, a C/C++/Python shift,
   an unterminated heredoc) plus ~30 newlines hangs the grader; the runner's watchdog only covers the
   pipeline process group (the .pgid file is removed before post_run), so the trial job never returns
   and the batch stalls.
2. HIGH/MEDIUM — ablation-report.py per-defect catch-rate unit: reads `defects_missed` or `recall.missed`,
   but ablation-row.sh never emits either (it writes defects_seeded/caught/rate/flags only, while the
   grader does compute recall.missed). Every production review-catch row takes the "rate" fallback,
   i.e. the task-level diff replicated n_defects times — pseudo-replication that narrows the bootstrap
   interval by ~sqrt(n). The decision predicates read lo/hi.
3. MEDIUM — grader heredoc strip also removes commands fed to interpreters (`python3 - <<'PY' …
   open('/home/operator/x') … PY`, `bash <<EOF … EOF`): a real outside reach inside such a body is no
   longer a contamination hit.
4. MEDIUM — grader 1.2.4 `"=" in w` and `w.startswith("/.")` exemptions: `/./home/operator/x`,
   `/../root/x` and any path containing `=` are now skipped before normpath; untested true-positive side.
5. MEDIUM — run-ablation.sh append_and_validate validates the WHOLE rows file after each append: a
   pre-existing invalid row from another batch fails this batch (exit 3) after the row is already
   appended.
6. LOW — run-ablation.sh numeric env/args with leading zeros (`--seed 007`, LOA_ABLATION_RETRY_WAIT_S=0120)
   pass the regexes but break `jq --argjson` in write_manifest.
7. LOW — run-ablation.sh post_run rows ANY non-zero grader exit as infrastructure_error (header says exit 2);
   grader exit 1 is only the self-check FAIL mode so currently harmless.
8. LOW — run-arms.sh refactor: ARM_SUM/ARM_N replaced by est_record keyed by arm; behaviour equivalent
   on reading; run-arms.bats not in the diff (claimed golden check).

## Areas I want a second opinion on
- run-ablation.sh resume reconciliation (RERUN_LIST / DONE_LIST / SPENT) and the --rerun replace path.
- run-ablation.sh watchdog/process-group handling under setsid, and lock/cleanup ordering.
- ablation-report.py decide() ordering vs the suite's rules.predicates text; bootstrap/MDE math.
- Any false negative introduced by grader 1.2.1–1.2.5 beyond those above.
