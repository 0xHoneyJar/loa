# Sprint 262 R3 report — ablation-report.py presentation items (report 1.2.0)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s5r3` (branch `wt/cycle-130-s5r3`, base c031144f). Patch `~/.cache/loa/cycle-130/patches/s5-r3.patch` (+ `.stat`). No decision, H1/A4 state or existing number changes (AR-1 … AR-30 green; AR-35 pins it).

## What was built
- `evals/harness/ablation-report.py:126` header block "Presentation items" documents all four; VERSION 1.1.0 → 1.2.0 (:174).
- **Sensitivity H1/A4 lines.** `Analysis(..., include_degraded=True)` (:448) gives a third Analysis (cap failures excluded, degraded rows included). The H1/A4 logic moved verbatim from `analyse()` into `h1a4()` (:898), used for the main read and for the sensitivity read. `render_h1a4()` (:1226) prints both, the sensitivity pair prefixed `sensitivity (decides nothing): ` and suffixed `(cap failures excluded, degraded rows included)`, under `### H1 and A4 lines, sensitivity (…; decides nothing)` after the component table (`render_sens()` :1164). Every non-primary suite version section now also gets its own sensitivity table and lines.
- **Batch record.** `batch_record()` (:992) and `render_batches()` (:1122) produce `## Batch record` (before Method): one row per manifest's batch, grouped by suite version (manifest suite_version, else the rows').
- **Precision / cost per true defect.** These figures are added in `arm_metrics()` (:761) and rendered as a line in the per-arm detail of arms that have review-catch rows.
- **Budget-matched baseline.** `budget_matched()` (:937), `render_budget()` (:1087) and `budget_json()` (:1116) produce `## Budget-matched baseline (suite_version N; informational, decides nothing)` after the sensitivity figure. Each other version section gets its own copy.
- `evals/tests/fixtures/ablation-report/gen-fixtures.py:295` adds the `present` scenario. It plants review rows, STATUS.json and run dirs with grade.json. `write()` now takes extra files.
- `evals/tests/ablation-report.bats` adds AR-31 … AR-35.

## JSON additions
- `sensitivity.h1` and `sensitivity.a4` have the same keys as top-level `h1`/`a4`; their `line` is prefixed. `sensitivity.treatment` is also added. `sensitivity.label` and `rows` are unchanged.
- `by_suite_version[N].sensitivity` holds `{treatment, h1, a4, rows}`.
- `batches[]` entries: `{batch, suite_version, smoke, status_file, status_note, state, trials_planned, trials_rowed, spend{rows_usd, ledger_usd, spent_usd, max_usd}, extra_models{id: {runs, output_tokens}}, rerowed, rerowed_tally{"from→to": n}, rerun, rerun_tally, drift_cleared, outage_history, cuts[], paused_arms[], grader_versions{ver: n}, run_dirs_missing}`.
- `arms.<arm>` gains `precision`, `usd_per_true_defect`, `true_defects`, `flagged_regions` and `precision_rows`. These are null for arms without review rows.
- `budget_matched` (primary version) and `by_suite_version[N].budget_matched` hold `{suite_version, available, label, tasks[{task_id, a0_trials, a1_trials, a0_union, a0_cost_sum, a1_mean, a1_cost_mean, diff, method, reason}], a0_union_mean, a1_mean, diff_mean, a0_cost_sum_mean, a1_cost_mean, note}`.

## Tests (each new case fails on the c031144f script, passes after)
- AR-31 checks the sensitivity H1/A4 lines per version: prefix, label, the v1 section, `sensitivity.h1.state`, and the same key shape as `h1`. On the degraded scenario the main H1 reads inconclusive by degradation while the sensitivity H1 is established.
- AR-32 checks the batch record from a planted STATUS.json: rerowed/rerun tallies, outage, drift, cut, paused arm and extra model. It also checks the grader tally `1.2.5 ×1, 1.2.11 ×1, n/a ×1` and missing run dirs counted. A batch without STATUS.json reads "no STATUS.json". Nothing is written beside the manifests.
- AR-33 checks precision and cost per true defect: a0 with false positives gives 0.647059 and USD 0.545455. a1 with none gives 1.0 and USD 2.222222. a3 with zero caught gives null and null. A build-only arm gives null.
- AR-34 checks the budget-matched baseline. On rc-01 the a0 union is 1.0 while no single a0 trial exceeds 0.5. rc-02 has no ids and reads "rate fallback". The means are 0.75 and 0.9375, and the note says three a0 trials cost USD 3.00 vs one a1 trial USD 10.00. The v1 section reads "not available".
- AR-35 checks that the new keys are present on five scenarios, the main H1 stays inconclusive by degradation, and the a3 decision is unchanged.
- One existing literal was updated. In AR-26, `! grep -qF 'H1: established'` became `! grep -qF '**H1: established**'`. The new sensitivity line legitimately contains "H1: established" on the degraded scenario. The negated check still pins the main line.

## bats counts
- `ablation-report.bats` was 30/30 before and is 35/35 after.
- whole `evals/tests/`: 414/414 after, 0 failures (not run before the change; 5 of the 414 are the new AR-31 … AR-35)

## Real-data smoke (read-only)
- Input: a snapshot copy of `runs.jsonl` (156 rows; v2 rows partly re-rowed with `defects_missed` at the time) and `--manifests …/ablation-2.0/batches`.
- Output went to `/tmp/r3real.xohC/report.{md,json}`. Exit 0. The main H1 still reads inconclusive_by_degradation.

```
### H1 and A4 lines, sensitivity (suite_version 2, primary)
**sensitivity (decides nothing): H1: established** — a1_full − a0_bare: hidden_test_pass_rate: not testable on suite_version 2 — no admissible task, defect_catch_rate +0.298 [+0.175, +0.421] (n = 19 defects) (cap failures excluded, degraded rows included).
**sensitivity (decides nothing): A4 sensitivity: not testable on suite_version 2 — no admissible build task** — a4_no_gates − a1_full: hidden_test_pass_rate: not testable on suite_version 2 — no admissible task (cap failures excluded, degraded rows included).
### the same, suite_version 1 section
**sensitivity (decides nothing): H1: not established — halt before promotion** — a1_full − a0_bare: hidden_test_pass_rate 0.000 [0.000, 0.000] (n = 12 tasks), defect_catch_rate inconclusive by degradation (a1_full excluded share 0.417 > 0.25); remaining pairs +0.394 [+0.271, +0.517] (n = 11 defects) (cap failures excluded, degraded rows included).
**sensitivity (decides nothing): A4 sensitivity: fails — harden tasks before acting on other arms** — a4_no_gates − a1_full: hidden_test_pass_rate 0.000 [0.000, 0.000] (n = 12 tasks) (cap failures excluded, degraded rows included).
### Batch record
| `priority-p1` | complete | 132 / 132 | 592.43 / 21.70 / 614.13 / 799.00 | global.anthropic.claude-haiku-4-5-20251001-v1:0: runs 1, output tokens 516 | 11 (contaminated→cap_failure ×3, contaminated→completed ×7, infrastructure_error→completed ×1) | 67 (transport_error→cap_failure ×3, transport_error→completed ×63, transport_error→contaminated ×1) | 1 | 0 | reason max_usd, at_trial 120, spent 1044.674677, max 1039 | none | 1.2.2 ×7, 1.2.3 ×38, 1.2.4 ×85, 1.2.5 ×2, n/a ×134 |
| `priority-v2-p1` | complete | 24 / 24 | 142.49 / 0.00 / 142.49 / 531.00 | none | 24 (completed→completed ×24) | 0 | 0 | 0 | none | none | 1.2.11 ×24 |
| `priority-v2-p1b` | running | 9 / 0 | 0.00 / 0.00 / 0.00 / 389.00 | none | 0 | 0 | 0 | 0 | none | none | n/a |
### precision (per-arm detail; v2 a0_bare, a1_full; v1 a0_bare, a1_full)
- 0.199 = true defects 31 / flagged regions 156 (over 12 valid review-catch rows); cost per true defect caught: USD 0.27
- 0.078 = true defects 10 / flagged regions 128 (over 3 valid review-catch rows); cost per true defect caught: USD 3.54
- 0.179 = true defects 26 / flagged regions 145 (over 12 valid review-catch rows); cost per true defect caught: USD 0.30
- 0.058 = true defects 18 / flagged regions 313 (over 10 valid review-catch rows); cost per true defect caught: USD 6.00
### Budget-matched baseline (suite_version 2)
| review-01 | 3 | 1.000 | 0.64 | 0 | n/a | n/a | n/a | defect union; no valid a1_full trial |
| review-02 | 3 | 1.000 | 0.69 | 0 | n/a | n/a | n/a | defect union; no valid a1_full trial |
| review-03 | 3 | 0.375 | 3.79 | 0 | n/a | n/a | n/a | defect union; no valid a1_full trial |
| review-04 | 3 | 0.600 | 3.32 | 3 | 0.667 | 11.80 | +0.067 | defect union |
- task mean (tasks with both arms): a0_bare union 0.600, a1_full per-trial 0.667, a1 − a0 union +0.067
- matched cost: 3 a0_bare trials cost USD 3.32 vs one a1_full trial USD 11.80 (task means over 1 task)
### Budget-matched baseline (suite_version 1)
| review-01 | 3 | 1.000 | 0.66 | 2 | 1.000 | 9.52 | 0.000 | rate fallback |
| review-02 | 3 | 0.667 | 0.60 | 3 | 1.000 | 9.30 | +0.333 | rate fallback |
| review-03 | 3 | 0.375 | 3.78 | 2 | 0.000 | 13.55 | -0.375 | rate fallback |
| review-04 | 3 | 0.600 | 2.66 | 3 | 0.200 | 11.30 | -0.400 | rate fallback |
- task mean (tasks with both arms): a0_bare union 0.660, a1_full per-trial 0.550, a1 − a0 union -0.110
- matched cost: 3 a0_bare trials cost USD 1.93 vs one a1_full trial USD 10.92 (task means over 4 tasks)
```

## DECISION bullets
- DECISION: The sensitivity H1/A4 lines use a dedicated third Analysis with cap failures excluded and degraded rows always included, as the brief's parenthetical and reads-v2 specify. The existing sensitivity component table is unchanged: it still excludes degraded rows per `--exclude-degraded`, because changing it would change existing numbers. The lines' subsection heading and suffix name their treatment.
- DECISION: The H1/A4 code moved unchanged into `h1a4()` so the main and sensitivity reads share it. The main figures are byte-identical (AR-1 … AR-30).
- DECISION: The sensitivity table, lines and budget-matched section are rendered for every suite version. The primary version is in the main sections. Each other version gets them in its own section. Top-level JSON describes the primary version, and `by_suite_version[N]` holds each version.
- DECISION: The batch record covers every manifest found, including smoke batches (labelled) and batches with no rows. A symlinked STATUS.json, run dir or grade.json is not read. An unreadable STATUS.json reads "STATUS.json unreadable". Neither is fatal.
- DECISION: The grader tally counts each run directory matching `<task>-t<n>[-r<k>]` for each row of the batch, so reruns' earlier attempts count too. A directory without a readable grader_version counts as "n/a". A row with no matching directory adds to "no run dir ×N".
- DECISION: Precision counts the valid review-catch rows with a numeric defects_caught. A cap_failure counts 0 caught, matching its 0 score, but its cost and false positives count. A null false_positives counts 0.
- DECISION: The budget-matched baseline uses the main Analysis, with the pre-registered exclusions and degraded rows excluded. A task without valid trials in both arms is listed with its reason and left out of the means. The difference is a1 − a0 union, the H1 direction. The cost note uses task means of the summed a0 cost and the mean a1 cost.
- DECISION: Per-defect ids are d1 … dN through the existing `defect_vector()`. No task.yaml `defects[].id` read was added, because the report has no suite-root input and the real ids are d1 … dN. A task with any a0 row lacking ids falls back to the max rate for the whole task, labelled "rate fallback".
- DECISION: The report version is bumped to 1.2.0.

## Limitations
- The task.yaml `defects[].id` path is not implemented (see the DECISION above).
- The real-data numbers will move as the lead finishes re-rowing. priority-v2-p1b was mid-run at the smoke (STATUS.json state running, 9 planned, 0 rowed).

## Handoff
- Apply the patch with `git apply --index`. Only the three owned files and this report copy change.
- After the rerun batch lands, regenerate the report. The v2 budget-matched baseline then covers four tasks instead of one.
