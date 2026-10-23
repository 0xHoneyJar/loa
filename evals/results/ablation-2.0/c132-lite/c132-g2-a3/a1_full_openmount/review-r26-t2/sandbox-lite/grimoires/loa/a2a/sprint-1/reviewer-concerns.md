# Reviewer concerns — sprint-1 (PR: sprint-262 ablation-row.sh 1.2 / ablation-report.py 1.2.0)

Scope: evals/harness/ablation-report.py (+589 lines), evals/harness/ablation-row.sh, the two bats files, gen-fixtures.py.

Verified by running the head test suites against a reconstructed suite file (the real evals/suites/ablation-2.0.yaml is not in the PR): ablation-report.bats 33/35 pass; AR-33 and AR-34 fail only under jq 1.6 (they compare `"\(1.0)"` to the literal `1.0`, which jq prints as `1` before 1.7). The computed numbers match the expectations.

Concerns found so far (please attack or confirm):

1. `partition()` (ablation-report.py ~843-861) picks the primary suite_version as the highest key over ALL rows, including rows that never enter a decision (smoke batches, rows whose batch has no manifest, non-applicable arms). Reproduced: a smoke batch (manifest smoke: true) tagged suite_version 3 beside decided rows at suite_version 1 makes 3 the primary; every component reads "no rows", H1 reads "not yet decidable (no pair)", `--partial` exits 1, and the real rows are pushed to the "reported separately" section.
2. `version_key()` (~825-836) leaves a string "1.0" as "1.0" (docstring says 1, 1.0 and "1" are one version) and `version_order()` ranks every non-digit string above every number, so one stray row with suite_version "1.0" or "v2" becomes the primary version with no rows. Row writer allows string suite_version (`need("suite_version"; ["number","string","null"])`).
3. `render_batches()` (~1122-1162) interpolates STATUS.json `trials_planned` raw into a markdown table cell (other cells go through md_cell); a string with `|` shifts the columns.
4. `batch_record()` is ~95 lines; `build()` remains ~260 lines.
5. `budget_matched()` header says rate fallback applies when a task's a0 rows "carry none" of the ids, but the code falls back when ANY a0 row lacks ids.
6. Tests AR-33/AR-34 depend on jq ≥ 1.7 number-literal preservation.

Please look especially at: assess()/h1a4() ordering (not_testable → degradation → degenerate → no_pair → tested), the degenerate rule in compare() (single task, no ids ⇒ zero-variance), the budget-matched union math, the row writer's jq for defects_missed / regressions_final_green and its --validate clauses, and any path-handling in batch_record() (arm/task names from rows used in os.path.join under the manifest dir, read-only).
