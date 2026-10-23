# Reviewer concerns — sprint-1 (PR: sprint-262, ablation-row.sh 1.2 + ablation-report.py 1.2.0)

Scope: pr/head.diff — evals/harness/ablation-row.sh, evals/harness/ablation-report.py,
evals/tests/ablation-row.bats, evals/tests/ablation-report.bats,
evals/tests/fixtures/ablation-report/gen-fixtures.py.

Verified so far (reviewer, local): gen-fixtures.py generates all 11 scenarios; every scenario's rows
pass `ablation-row.sh --validate --allow-ungraded` (including `present`); the head report runs on all
11 scenarios against a synthetic suite and reproduces every planted figure the new bats assert
(H1 d = 0.444444, shares 0.750 / 0.333, precision 0.647059 / 0.545455, budget-matched 0.75 / 0.9375,
batch record tallies).

Concerns to pressure-test:

1. `batch_record` grader_versions sort key (ablation-report.py ~1081-1082) mixes int and str tokens
   (`int(p) if p.isdigit() else p`); two grader_version strings whose token types differ at one
   position (e.g. "2.0.0" beside "2.0.0-rc.5", or "1.2.11" beside "1.2.11a") raise TypeError and
   abort the whole report with a traceback — contradicting "never fatal" for the batch record.
2. `version_key` (~825-836) unifies 1, 1.0 and "1" but keeps the string "2.0" as its own version
   key, and maps a non-integer float (2.5) to None (treated as "no suite_version"). Rows whose
   suite_version came through as a "2.0" string would form a separate never-pooled version.
3. `batch_record` counts every run dir matching `<task>-t<n>[-r<k>]` for one row, so a cell with
   both `rc-01-t1` and `rc-01-t1-r2` dirs is tallied twice; grader-version counts can exceed
   trials_rowed.
4. AR-20 (`ablation-report.bats`) validates the new scenarios' rows with ablation-row.sh --validate
   but leaves `present` out of the loop although its rows validate.
5. Stale file header in ablation-report.bats ("writes four scenarios") after 11 scenarios.
6. budget_matched docs say "a task whose a0 rows carry none → rate fallback" but the code falls back
   when any a0 row lacks ids (mixed ids/rate on one task).
7. ablation-row.sh: validation error for `["d2", 3]` reads "has type array, want a list of
   non-empty strings|null" — element-level cause not named.
8. assess(): the degradation guard reads before no_pair, so an arm whose cells are all excluded for
   a non-degradation reason (ungraded) reads "inconclusive by degradation" on the H1/A4 line.
9. Security surface: batch_record joins row `arm` into a path under the manifest dir and reads
   grade.json there (symlinks refused); row arm is not grammar-checked by the report (row.sh does).

Please look for: logic errors in the H1/A4 read order (assess/h1a4), the partition by suite_version
(partition/version_key), the degenerate flag (compare), precision/budget-matched arithmetic
(arm_metrics/budget_matched), jq edge cases in ablation-row.sh (defects_missed/regressions_final_green
and the --validate clauses), and any test that asserts the wrong value.
