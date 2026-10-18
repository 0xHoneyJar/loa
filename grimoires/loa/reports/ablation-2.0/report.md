# Loa 2.0 component ablation — report

- report schema_version 1; ablation-report.py 1.2.0
- suite: `evals/suites/ablation-2.0.yaml` (name ablation-2.0, suite_version 2)
- row suite_version: 1, 2
  - suite_version 2 (primary: the main sections): 33 rows; batches priority-v2-p1, priority-v2-p1b; suite manifest sha256 ddd200b313c5c02353abdc829d3a3a6c78f52b9118da2cf0da8c1eb21ae788c7
  - suite_version 1 (reported separately, never pooled): 132 rows; batches priority-p1; suite manifest sha256 30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba
- source commit(s): ba11b860e4b3d2112bf010c8f056d7e7bb521dde
- suite manifest sha256: 30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba, ddd200b313c5c02353abdc829d3a3a6c78f52b9118da2cf0da8c1eb21ae788c7
- image digest(s): sha256:4e37cb5fd4d85c3231b3ef11a0d6179b5a5452bc024c23a26a1bea2668e86f5f
- cli_version(s): 2.1.299
- batches:
  - `priority-p1`: 132 rows, shuffle_seed 20261015, pre_registration_ref NOTES.md § Batch plan — cycle-130 ablation (Task 3.4) — 2026-10-15T10:26:23Z, source_commit ba11b860e4b3d2112bf010c8f056d7e7bb521dde, image_digest sha256:4e37cb5fd4d85c3231b3ef11a0d6179b5a5452bc024c23a26a1bea2668e86f5f, cli_version 2.1.299
  - `priority-v2-p1`: 24 rows, shuffle_seed 20261015, pre_registration_ref NOTES.md § Re-pre-registration — cycle-130 ablation, suite v2 batch priority-v2-p1 — 2026-10-17T18:40:55Z, source_commit ba11b860e4b3d2112bf010c8f056d7e7bb521dde, image_digest sha256:4e37cb5fd4d85c3231b3ef11a0d6179b5a5452bc024c23a26a1bea2668e86f5f, cli_version 2.1.299
  - `priority-v2-p1b`: 9 rows, shuffle_seed 20261015, pre_registration_ref NOTES.md § Re-pre-registration addendum — cycle-130 ablation, supplementary batch priority-v2-p1b — 2026-10-18T06:07:55Z, source_commit ba11b860e4b3d2112bf010c8f056d7e7bb521dde, image_digest sha256:4e37cb5fd4d85c3231b3ef11a0d6179b5a5452bc024c23a26a1bea2668e86f5f, cli_version 2.1.299
- rows read: 165 from `grimoires/loa/reports/ablation-2.0/runs.jsonl`; 0 listed and never decided; 0 duplicate run_id rows dropped
- bootstrap: 10000 resamples, level 0.90, seed 20261015; exclusion statuses contaminated, degraded, infrastructure_error, interrupted, transport_error; degraded rows excluded: true

## Decisions

| component | arm | n pairs | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] (defects) | cost Δ % | wall-clock Δ % | excluded share | decision | rule matched | rows |
|---|---|---|---|---|---|---|---|---|---|---|
| A2 | `a2_no_sprint_plan` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | **Not run (cut) — est. USD 398 for P2 (A2 + A3: 24 + 24 build + 12 review runs); projected spend after P1 + P2 ≈ 1,103 of 1,500** | --cuts: P2 (A2 and A3 build trials 3 → 2, review 3; batch-plan.md rung 2, est. USD 398) was never launched: the P1 reads halted the cycle on suite v1 (DEC-0558) and the operator chose the suite v2 rerun of A0/A1/A4 over P2 (DEC-0559, DEC-0543); on suite v2 no build task met the hardness bar (DEC-0590), so A2 had no admissible task | 0 (§ Rows per cell) |
| A3 | `a3_one_voice` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | **Not run (cut) — P2 est. USD 398 shared with A2; review-catch half ≈ 12 × 11.6 ≈ USD 140 at the v2 A1 actuals** | --cuts: same as A2: P2 never launched (DEC-0558, DEC-0559, DEC-0543); its review-catch half (3 trials × 4 PRs) was not re-planned on suite v2 because the v2 budget went to the A0/A1 review-catch read and its KF-048 rerun | 0 (§ Rows per cell) |
| A4 | `a4_no_gates` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | **no rows** | no rows for this arm | 0 (§ Rows per cell) |
| A5 | `a5_no_flatline` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | **Not run (cut) — 36 × 5.77 ≈ USD 208 at the smoke unit cost vs ≈ 147 headroom before the reserve** | --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A5 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A5 | 0 (§ Rows per cell) |
| A6 | `a6_one_window` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | **Not run (cut) — 36 × 7.64 ≈ USD 275 at the smoke unit cost vs ≈ 147 headroom before the reserve** | --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A6 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A6 | 0 (§ Rows per cell) |
| A7 | `a7_effort_medium` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | **Not run (cut) — 36 × 5.57 + 12 × 6.19 ≈ USD 275 at the smoke unit cost; fallback 2 × 2 ≈ USD 158; vs ≈ 147 headroom before the reserve** | --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7; first in the priority list had the reserve been released to the arms, DEC-0398): at the smoke unit cost A7 exceeded the headroom before the reserve; the reserve went to the suite v2 rerun (DEC-0559); the reduced-trial fallback (2 build, 2 review ≈ USD 158) was not taken | 0 (§ Rows per cell) |
| A8 | `a8_no_ceremonies` | — | — | — | — | — | — | **component-absent** | no /meeting command, skill or sosyete config key at 4d69c3c4 (grep -rli sosyete .claude/ docs/; ls .claude/commands .claude/skills) | 0 |

**H1: established** — a1_full − a0_bare: hidden_test_pass_rate: not testable on suite_version 2 — no admissible task, defect_catch_rate +0.263 [+0.158, +0.386] (n = 19 defects). Rule (rules.h1): "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"

**A4 sensitivity: not testable on suite_version 2 — no admissible build task** — a4_no_gates − a1_full: hidden_test_pass_rate: not testable on suite_version 2 — no admissible task. Rule (rules.a4_sensitivity): "a4_no_gates worse than a1_full on hidden_test_pass_rate with the interval excluding zero, else harden tasks before acting on other arms"

Expected false positives at level 0.90 over 6 components: 6 × (1 − 0.90) / 2 = 0.3 one-sided per direction (0.6 in either direction); no multiple-comparison correction is applied (multiple_comparisons: none).

## Per-arm detail

### A0 `a0_bare`

- runs: 12 (completed 12); degraded rows 0; valid cells 12
- excluded cells: 0 of 12 (share 0.000)
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: 0.668
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- false positives per review-catch task: review-01 1.667, review-02 4.000, review-03 14.667, review-04 21.333
- precision (informational, decides nothing): 0.199 = true defects 31 / flagged regions 156 (defects caught + false positives over 12 valid review-catch rows); cost per true defect caught: USD 0.27
- cost per task USD 0.704, per run USD 0.704; wall-clock per run 2.8 min; tokens in/out per run 34 / 12660

### A1 `a1_full`

- runs: 21 (completed 21); degraded rows 9; valid cells 12
- excluded cells: 0 of 12 (share 0.000)
  - `priority-v2-p1-a1_full-review-01-t1` review-01 t1: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-01-t1
  - `priority-v2-p1-a1_full-review-01-t2` review-01 t2: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-01-t2
  - `priority-v2-p1-a1_full-review-01-t3` review-01 t3: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-01-t3
  - `priority-v2-p1-a1_full-review-02-t1` review-02 t1: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-02-t1
  - `priority-v2-p1-a1_full-review-02-t2` review-02 t2: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-02-t2
  - `priority-v2-p1-a1_full-review-02-t3` review-02 t3: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-02-t3
  - `priority-v2-p1-a1_full-review-03-t1` review-03 t1: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-03-t1
  - `priority-v2-p1-a1_full-review-03-t2` review-03 t2: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-03-t2
  - `priority-v2-p1-a1_full-review-03-t3` review-03 t3: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-03-t3
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: 0.854
- secondaries: verdict accuracy 0.917 (review 0.917, audit 0.917); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- false positives per review-catch task: review-01 23.667, review-02 23.000, review-03 42.333, review-04 39.333
- precision (informational, decides nothing): 0.107 = true defects 46 / flagged regions 431 (defects caught + false positives over 12 valid review-catch rows); cost per true defect caught: USD 3.04
- cost per task USD 11.639, per run USD 11.639; wall-clock per run 28.8 min; tokens in/out per run 1551 / 98854

### A2 `a2_no_sprint_plan`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — est. USD 398 for P2 (A2 + A3: 24 + 24 build + 12 review runs); projected spend after P1 + P2 ≈ 1,103 of 1,500; rule: --cuts: P2 (A2 and A3 build trials 3 → 2, review 3; batch-plan.md rung 2, est. USD 398) was never launched: the P1 reads halted the cycle on suite v1 (DEC-0558) and the operator chose the suite v2 rerun of A0/A1/A4 over P2 (DEC-0559, DEC-0543); on suite v2 no build task met the hardness bar (DEC-0590), so A2 had no admissible task
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

### A3 `a3_one_voice`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
- defect_catch_rate vs a1_full: d [lo, hi] = no pair; n = 0 defects over 0 tasks; MDE n/a; bootstrap half-width n/a
  - also_report (tasks, decides nothing): d [lo, hi] = no pair; n = 0 tasks
  - left the pair: review-01 (no row in a3_one_voice)
  - left the pair: review-02 (no row in a3_one_voice)
  - left the pair: review-03 (no row in a3_one_voice)
  - left the pair: review-04 (no row in a3_one_voice)
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — P2 est. USD 398 shared with A2; review-catch half ≈ 12 × 11.6 ≈ USD 140 at the v2 A1 actuals; rule: --cuts: same as A2: P2 never launched (DEC-0558, DEC-0559, DEC-0543); its review-catch half (3 trials × 4 PRs) was not re-planned on suite v2 because the v2 budget went to the A0/A1 review-catch read and its KF-048 rerun
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

### A4 `a4_no_gates`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **no rows**; rule: no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

### A5 `a5_no_flatline`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — 36 × 5.77 ≈ USD 208 at the smoke unit cost vs ≈ 147 headroom before the reserve; rule: --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A5 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A5
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

### A6 `a6_one_window`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — 36 × 7.64 ≈ USD 275 at the smoke unit cost vs ≈ 147 headroom before the reserve; rule: --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A6 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A6
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

### A7 `a7_effort_medium`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
- defect_catch_rate vs a1_full: d [lo, hi] = no pair; n = 0 defects over 0 tasks; MDE n/a; bootstrap half-width n/a
  - also_report (tasks, decides nothing): d [lo, hi] = no pair; n = 0 tasks
  - left the pair: review-01 (no row in a7_effort_medium)
  - left the pair: review-02 (no row in a7_effort_medium)
  - left the pair: review-03 (no row in a7_effort_medium)
  - left the pair: review-04 (no row in a7_effort_medium)
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — 36 × 5.57 + 12 × 6.19 ≈ USD 275 at the smoke unit cost; fallback 2 × 2 ≈ USD 158; vs ≈ 147 headroom before the reserve; rule: --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7; first in the priority list had the reserve been released to the arms, DEC-0398): at the smoke unit cost A7 exceeded the headroom before the reserve; the reserve went to the suite v2 rerun (DEC-0559); the reduced-trial fallback (2 build, 2 review ≈ USD 158) was not taken
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

## Exclusions

| run_id | arm | task | trial | status | reason |
|---|---|---|---|---|---|
| `priority-v2-p1-a1_full-review-01-t1` | `a1_full` | review-01 | 1 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-01-t1 |
| `priority-v2-p1-a1_full-review-01-t2` | `a1_full` | review-01 | 2 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-01-t2 |
| `priority-v2-p1-a1_full-review-01-t3` | `a1_full` | review-01 | 3 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-01-t3 |
| `priority-v2-p1-a1_full-review-02-t1` | `a1_full` | review-02 | 1 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-02-t1 |
| `priority-v2-p1-a1_full-review-02-t2` | `a1_full` | review-02 | 2 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-02-t2 |
| `priority-v2-p1-a1_full-review-02-t3` | `a1_full` | review-02 | 3 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-02-t3 |
| `priority-v2-p1-a1_full-review-03-t1` | `a1_full` | review-03 | 1 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-03-t1 |
| `priority-v2-p1-a1_full-review-03-t2` | `a1_full` | review-03 | 2 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-03-t2 |
| `priority-v2-p1-a1_full-review-03-t3` | `a1_full` | review-03 | 3 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed; superseded by priority-v2-p1b-a1_full-review-03-t3 |

### Cap failures (scored 0 on every applicable primary; the sensitivity figure excludes them)

- none

### Rows listed, never decided

None.

## Cuts

- `a2_no_sprint_plan`: Not run (cut) — reason: P2 (A2 and A3 build trials 3 → 2, review 3; batch-plan.md rung 2, est. USD 398) was never launched: the P1 reads halted the cycle on suite v1 (DEC-0558) and the operator chose the suite v2 rerun of A0/A1/A4 over P2 (DEC-0559, DEC-0543); on suite v2 no build task met the hardness bar (DEC-0590), so A2 had no admissible task; figure: est. USD 398 for P2 (A2 + A3: 24 + 24 build + 12 review runs); projected spend after P1 + P2 ≈ 1,103 of 1,500 (--cuts)
- `a3_one_voice`: Not run (cut) — reason: same as A2: P2 never launched (DEC-0558, DEC-0559, DEC-0543); its review-catch half (3 trials × 4 PRs) was not re-planned on suite v2 because the v2 budget went to the A0/A1 review-catch read and its KF-048 rerun; figure: P2 est. USD 398 shared with A2; review-catch half ≈ 12 × 11.6 ≈ USD 140 at the v2 A1 actuals (--cuts)
- `a5_no_flatline`: Not run (cut) — reason: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A5 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A5; figure: 36 × 5.77 ≈ USD 208 at the smoke unit cost vs ≈ 147 headroom before the reserve (--cuts)
- `a6_one_window`: Not run (cut) — reason: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A6 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A6; figure: 36 × 7.64 ≈ USD 275 at the smoke unit cost vs ≈ 147 headroom before the reserve (--cuts)
- `a7_effort_medium`: Not run (cut) — reason: pre-declared Not run (cut) in batch-plan.md (Task 3.7; first in the priority list had the reserve been released to the arms, DEC-0398): at the smoke unit cost A7 exceeded the headroom before the reserve; the reserve went to the suite v2 rerun (DEC-0559); the reduced-trial fallback (2 build, 2 review ≈ USD 158) was not taken; figure: 36 × 5.57 + 12 × 6.19 ≈ USD 275 at the smoke unit cost; fallback 2 × 2 ≈ USD 158; vs ≈ 147 headroom before the reserve (--cuts)
- cut ladder (suite): A5, A6, A7 not run; A2 and A3 build trials 3 -> 2; A3 review-catch trials 3 -> 2

## Sensitivity figure: sensitivity (cap failures excluded) — no decision uses this

| component | arm | n pairs | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] (defects) | cost Δ % | wall-clock Δ % | excluded share | predicate outcome (not used) |
|---|---|---|---|---|---|---|---|---|
| A2 | `a2_no_sprint_plan` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | no rows |
| A3 | `a3_one_voice` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | no rows |
| A4 | `a4_no_gates` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | no rows |
| A5 | `a5_no_flatline` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | no rows |
| A6 | `a6_one_window` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | no rows |
| A7 | `a7_effort_medium` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | no rows |

### H1 and A4 lines, sensitivity (cap failures excluded, degraded rows included; decides nothing)

**sensitivity (decides nothing): H1: established** — a1_full − a0_bare: hidden_test_pass_rate: not testable on suite_version 2 — no admissible task, defect_catch_rate +0.263 [+0.158, +0.386] (n = 19 defects) (cap failures excluded, degraded rows included). Rule (rules.h1): "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"

**sensitivity (decides nothing): A4 sensitivity: not testable on suite_version 2 — no admissible build task** — a4_no_gates − a1_full: hidden_test_pass_rate: not testable on suite_version 2 — no admissible task (cap failures excluded, degraded rows included). Rule (rules.a4_sensitivity): "a4_no_gates worse than a1_full on hidden_test_pass_rate with the interval excluding zero, else harden tasks before acting on other arms"

## Budget-matched baseline (suite_version 2; informational, decides nothing)

Per review-catch task: the union of the defects any valid a0_bare trial caught (a defect counts once caught by any trial; "rate fallback" is the best trial's rate where the rows carry no per-defect ids), against a1_full's mean per-trial catch rate. Nothing here feeds a decision.

| task | a0_bare trials | a0_bare union catch rate | a0_bare summed cost USD | a1_full trials | a1_full mean per-trial catch rate | a1_full mean cost USD | a1 − a0 union | method |
|---|---|---|---|---|---|---|---|---|
| review-01 | 3 | 1.000 | 0.64 | 3 | 1.000 | 9.08 | 0.000 | defect union |
| review-02 | 3 | 1.000 | 0.69 | 3 | 1.000 | 8.63 | 0.000 | defect union |
| review-03 | 3 | 0.375 | 3.79 | 3 | 0.750 | 17.05 | +0.375 | defect union |
| review-04 | 3 | 0.600 | 3.32 | 3 | 0.667 | 11.80 | +0.067 | defect union |

- task mean (tasks with both arms): a0_bare union 0.744, a1_full per-trial 0.854, a1 − a0 union +0.110
- matched cost: 3 a0_bare trials cost USD 2.11 vs one a1_full trial USD 11.64 (task means over 4 tasks)

## Rows per cell

### H1 a1_full − a0_bare — defect_catch_rate

| task | diff | arm rows | control rows |
|---|---|---|---|
| review-01 | 0.000 | `priority-v2-p1b-a1_full-review-01-t1…t3` | `priority-v2-p1-a0_bare-review-01-t1…t3` |
| review-02 | +0.111 | `priority-v2-p1b-a1_full-review-02-t1…t3` | `priority-v2-p1-a0_bare-review-02-t1…t3` |
| review-03 | +0.500 | `priority-v2-p1b-a1_full-review-03-t1…t3` | `priority-v2-p1-a0_bare-review-03-t1…t3` |
| review-04 | +0.133 | `priority-v2-p1-a1_full-review-04-t1…t3` | `priority-v2-p1-a0_bare-review-04-t1…t3` |

## Suite version 1 (batches: priority-p1) — reported separately, never pooled

The rows of suite_version 1 only (132 rows; suite manifest sha256 30e1f2ad7015590227e9cc2fa25ca791e31867fec65289e4a41554e9e53357ba); the same rules, cuts and seed; no figure here is pooled with suite_version 2.

### Decisions (suite_version 1)

| component | arm | n pairs | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] (defects) | cost Δ % | wall-clock Δ % | excluded share | decision | rule matched | rows |
|---|---|---|---|---|---|---|---|---|---|---|
| A2 | `a2_no_sprint_plan` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | **Not run (cut) — est. USD 398 for P2 (A2 + A3: 24 + 24 build + 12 review runs); projected spend after P1 + P2 ≈ 1,103 of 1,500** | --cuts: P2 (A2 and A3 build trials 3 → 2, review 3; batch-plan.md rung 2, est. USD 398) was never launched: the P1 reads halted the cycle on suite v1 (DEC-0558) and the operator chose the suite v2 rerun of A0/A1/A4 over P2 (DEC-0559, DEC-0543); on suite v2 no build task met the hardness bar (DEC-0590), so A2 had no admissible task | 0 (§ Rows per cell) |
| A3 | `a3_one_voice` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | **Not run (cut) — P2 est. USD 398 shared with A2; review-catch half ≈ 12 × 11.6 ≈ USD 140 at the v2 A1 actuals** | --cuts: same as A2: P2 never launched (DEC-0558, DEC-0559, DEC-0543); its review-catch half (3 trials × 4 PRs) was not re-planned on suite v2 because the v2 budget went to the A0/A1 review-catch read and its KF-048 rerun | 0 (§ Rows per cell) |
| A4 | `a4_no_gates` | 12 tasks | +0.028 [0.000, +0.083] | n/a (build-only) | -70.2 % | -72.0 % | 0.000 (0/36) | **Remove** | remove: every applicable primary has d >= -0.03 and (c <= -15 or w <= -15) (c = -70.2, w = -72.0) | 36 (§ Rows per cell) |
| A5 | `a5_no_flatline` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | **Not run (cut) — 36 × 5.77 ≈ USD 208 at the smoke unit cost vs ≈ 147 headroom before the reserve** | --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A5 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A5 | 0 (§ Rows per cell) |
| A6 | `a6_one_window` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | **Not run (cut) — 36 × 7.64 ≈ USD 275 at the smoke unit cost vs ≈ 147 headroom before the reserve** | --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A6 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A6 | 0 (§ Rows per cell) |
| A7 | `a7_effort_medium` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | **Not run (cut) — 36 × 5.57 + 12 × 6.19 ≈ USD 275 at the smoke unit cost; fallback 2 × 2 ≈ USD 158; vs ≈ 147 headroom before the reserve** | --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7; first in the priority list had the reserve been released to the arms, DEC-0398): at the smoke unit cost A7 exceeded the headroom before the reserve; the reserve went to the suite v2 rerun (DEC-0559); the reduced-trial fallback (2 build, 2 review ≈ USD 158) was not taken | 0 (§ Rows per cell) |
| A8 | `a8_no_ceremonies` | — | — | — | — | — | — | **component-absent** | no /meeting command, skill or sosyete config key at 4d69c3c4 (grep -rli sosyete .claude/ docs/; ls .claude/commands .claude/skills) | 0 |

**H1: not established — halt before promotion** — a1_full − a0_bare: hidden_test_pass_rate -0.028 [-0.083, 0.000] (n = 12 tasks), defect_catch_rate -0.096 [-0.188, +0.007] (n = 19 defects). Rule (rules.h1): "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"

**A4 sensitivity: fails — harden tasks before acting on other arms** — a4_no_gates − a1_full: hidden_test_pass_rate +0.028 [0.000, +0.083] (n = 12 tasks). Rule (rules.a4_sensitivity): "a4_no_gates worse than a1_full on hidden_test_pass_rate with the interval excluding zero, else harden tasks before acting on other arms"

### Per-arm detail (suite_version 1)

#### A0 `a0_bare`

- runs: 48 (completed 48); degraded rows 0; valid cells 48
- excluded cells: 0 of 48 (share 0.000)
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): 1.000; defect_catch_rate: 0.545
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run 0.000; churn diff_lines 93.556, files_changed 2.944 per run
- false positives per review-catch task: review-01 2.667, review-02 4.667, review-03 16.667, review-04 15.667
- precision (informational, decides nothing): 0.179 = true defects 26 / flagged regions 145 (defects caught + false positives over 12 valid review-catch rows); cost per true defect caught: USD 0.30
- cost per task USD 0.252, per run USD 0.252; wall-clock per run 1.1 min; tokens in/out per run 15 / 5466

#### A1 `a1_full`

- runs: 48 (cap_failure 6, completed 42); degraded rows 4; valid cells 44
- excluded cells: 4 of 48 (share 0.083)
  - `priority-p1-a1_full-bugfix-02-t3` bugfix-02 t3: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed
  - `priority-p1-a1_full-refactor-02-t3` refactor-02 t3: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed
  - `priority-p1-a1_full-review-01-t3` review-01 t3: degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed
  - `priority-p1-a1_full-review-03-t3` review-03 t3: degraded: audit envelope 1 of 4 voices completed
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): 0.972; defect_catch_rate: 0.550
- secondaries: verdict accuracy 0.932 (review 0.273, audit 0.930); regressions per run 0.000; churn diff_lines 167.706, files_changed 3.853 per run
- false positives per review-catch task: review-01 23.500, review-02 25.333, review-03 37.000, review-04 32.667
- precision (informational, decides nothing): 0.058 = true defects 18 / flagged regions 313 (defects caught + false positives over 10 valid review-catch rows); cost per true defect caught: USD 6.00
- cost per task USD 10.019, per run USD 9.946; wall-clock per run 29.1 min; tokens in/out per run 1164 / 77223

#### A2 `a2_no_sprint_plan`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
  - left the pair: bugfix-01 (no row in a2_no_sprint_plan)
  - left the pair: bugfix-02 (no row in a2_no_sprint_plan)
  - left the pair: bugfix-03 (no row in a2_no_sprint_plan)
  - left the pair: bugfix-04 (no row in a2_no_sprint_plan)
  - left the pair: feature-01 (no row in a2_no_sprint_plan)
  - left the pair: feature-02 (no row in a2_no_sprint_plan)
  - left the pair: feature-03 (no row in a2_no_sprint_plan)
  - left the pair: feature-04 (no row in a2_no_sprint_plan)
  - left the pair: refactor-01 (no row in a2_no_sprint_plan)
  - left the pair: refactor-02 (no row in a2_no_sprint_plan)
  - left the pair: refactor-03 (no row in a2_no_sprint_plan)
  - left the pair: refactor-04 (no row in a2_no_sprint_plan)
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — est. USD 398 for P2 (A2 + A3: 24 + 24 build + 12 review runs); projected spend after P1 + P2 ≈ 1,103 of 1,500; rule: --cuts: P2 (A2 and A3 build trials 3 → 2, review 3; batch-plan.md rung 2, est. USD 398) was never launched: the P1 reads halted the cycle on suite v1 (DEC-0558) and the operator chose the suite v2 rerun of A0/A1/A4 over P2 (DEC-0559, DEC-0543); on suite v2 no build task met the hardness bar (DEC-0590), so A2 had no admissible task
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

#### A3 `a3_one_voice`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
  - left the pair: bugfix-01 (no row in a3_one_voice)
  - left the pair: bugfix-02 (no row in a3_one_voice)
  - left the pair: bugfix-03 (no row in a3_one_voice)
  - left the pair: bugfix-04 (no row in a3_one_voice)
  - left the pair: feature-01 (no row in a3_one_voice)
  - left the pair: feature-02 (no row in a3_one_voice)
  - left the pair: feature-03 (no row in a3_one_voice)
  - left the pair: feature-04 (no row in a3_one_voice)
  - left the pair: refactor-01 (no row in a3_one_voice)
  - left the pair: refactor-02 (no row in a3_one_voice)
  - left the pair: refactor-03 (no row in a3_one_voice)
  - left the pair: refactor-04 (no row in a3_one_voice)
- defect_catch_rate vs a1_full: d [lo, hi] = no pair; n = 0 defects over 0 tasks; MDE n/a; bootstrap half-width n/a
  - also_report (tasks, decides nothing): d [lo, hi] = no pair; n = 0 tasks
  - left the pair: review-01 (no row in a3_one_voice)
  - left the pair: review-02 (no row in a3_one_voice)
  - left the pair: review-03 (no row in a3_one_voice)
  - left the pair: review-04 (no row in a3_one_voice)
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — P2 est. USD 398 shared with A2; review-catch half ≈ 12 × 11.6 ≈ USD 140 at the v2 A1 actuals; rule: --cuts: same as A2: P2 never launched (DEC-0558, DEC-0559, DEC-0543); its review-catch half (3 trials × 4 PRs) was not re-planned on suite v2 because the v2 budget went to the A0/A1 review-catch read and its KF-048 rerun
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

#### A4 `a4_no_gates`

- runs: 36 (completed 36); degraded rows 0; valid cells 36
- excluded cells: 0 of 36 (share 0.000)
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): 1.000; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = +0.028 [0.000, +0.083]; n = 12 tasks over 12 tasks; MDE 0.081; bootstrap half-width 0.042
  - pairwise drop: `priority-p1-a4_no_gates-bugfix-02-t3` (a4_no_gates, bugfix-02 t3)
  - pairwise drop: `priority-p1-a4_no_gates-refactor-02-t3` (a4_no_gates, refactor-02 t3)
- cost Δ -70.2 %, wall-clock Δ -72.0 % over 12 paired tasks
- decision: **Remove**; rule: remove: every applicable primary has d >= -0.03 and (c <= -15 or w <= -15) (c = -70.2, w = -72.0)
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run 0.000; churn diff_lines 152.972, files_changed 3.278 per run
- cost per task USD 2.880, per run USD 2.880; wall-clock per run 8.0 min; tokens in/out per run 34 / 14528

#### A5 `a5_no_flatline`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
  - left the pair: bugfix-01 (no row in a5_no_flatline)
  - left the pair: bugfix-02 (no row in a5_no_flatline)
  - left the pair: bugfix-03 (no row in a5_no_flatline)
  - left the pair: bugfix-04 (no row in a5_no_flatline)
  - left the pair: feature-01 (no row in a5_no_flatline)
  - left the pair: feature-02 (no row in a5_no_flatline)
  - left the pair: feature-03 (no row in a5_no_flatline)
  - left the pair: feature-04 (no row in a5_no_flatline)
  - left the pair: refactor-01 (no row in a5_no_flatline)
  - left the pair: refactor-02 (no row in a5_no_flatline)
  - left the pair: refactor-03 (no row in a5_no_flatline)
  - left the pair: refactor-04 (no row in a5_no_flatline)
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — 36 × 5.77 ≈ USD 208 at the smoke unit cost vs ≈ 147 headroom before the reserve; rule: --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A5 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A5
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

#### A6 `a6_one_window`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
  - left the pair: bugfix-01 (no row in a6_one_window)
  - left the pair: bugfix-02 (no row in a6_one_window)
  - left the pair: bugfix-03 (no row in a6_one_window)
  - left the pair: bugfix-04 (no row in a6_one_window)
  - left the pair: feature-01 (no row in a6_one_window)
  - left the pair: feature-02 (no row in a6_one_window)
  - left the pair: feature-03 (no row in a6_one_window)
  - left the pair: feature-04 (no row in a6_one_window)
  - left the pair: refactor-01 (no row in a6_one_window)
  - left the pair: refactor-02 (no row in a6_one_window)
  - left the pair: refactor-03 (no row in a6_one_window)
  - left the pair: refactor-04 (no row in a6_one_window)
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — 36 × 7.64 ≈ USD 275 at the smoke unit cost vs ≈ 147 headroom before the reserve; rule: --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7): at the smoke unit cost A6 exceeded the headroom before the reserve; the reserve was later released to the suite v2 rerun (DEC-0559), not to A6
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

#### A7 `a7_effort_medium`

- runs: 0 (none); degraded rows 0; valid cells 0
- excluded cells: 0 of 0
- applicable primaries: hidden_test_pass_rate, defect_catch_rate
- hidden_test_pass_rate (task-mean of trial means, cap failures 0): n/a; defect_catch_rate: n/a
- hidden_test_pass_rate vs a1_full: d [lo, hi] = no pair; n = 0 tasks over 0 tasks; MDE n/a; bootstrap half-width n/a
  - left the pair: bugfix-01 (no row in a7_effort_medium)
  - left the pair: bugfix-02 (no row in a7_effort_medium)
  - left the pair: bugfix-03 (no row in a7_effort_medium)
  - left the pair: bugfix-04 (no row in a7_effort_medium)
  - left the pair: feature-01 (no row in a7_effort_medium)
  - left the pair: feature-02 (no row in a7_effort_medium)
  - left the pair: feature-03 (no row in a7_effort_medium)
  - left the pair: feature-04 (no row in a7_effort_medium)
  - left the pair: refactor-01 (no row in a7_effort_medium)
  - left the pair: refactor-02 (no row in a7_effort_medium)
  - left the pair: refactor-03 (no row in a7_effort_medium)
  - left the pair: refactor-04 (no row in a7_effort_medium)
- defect_catch_rate vs a1_full: d [lo, hi] = no pair; n = 0 defects over 0 tasks; MDE n/a; bootstrap half-width n/a
  - also_report (tasks, decides nothing): d [lo, hi] = no pair; n = 0 tasks
  - left the pair: review-01 (no row in a7_effort_medium)
  - left the pair: review-02 (no row in a7_effort_medium)
  - left the pair: review-03 (no row in a7_effort_medium)
  - left the pair: review-04 (no row in a7_effort_medium)
- cost Δ n/a, wall-clock Δ n/a over 0 paired tasks
- decision: **Not run (cut)** — 36 × 5.57 + 12 × 6.19 ≈ USD 275 at the smoke unit cost; fallback 2 × 2 ≈ USD 158; vs ≈ 147 headroom before the reserve; rule: --cuts: pre-declared Not run (cut) in batch-plan.md (Task 3.7; first in the priority list had the reserve been released to the arms, DEC-0398): at the smoke unit cost A7 exceeded the headroom before the reserve; the reserve went to the suite v2 rerun (DEC-0559); the reduced-trial fallback (2 build, 2 review ≈ USD 158) was not taken
- predicate outcome before the cut/power state: no rows; no rows for this arm
- secondaries: verdict accuracy n/a (review n/a, audit n/a); regressions per run n/a; churn diff_lines n/a, files_changed n/a per run
- cost per task USD n/a, per run USD n/a; wall-clock per run n/a; tokens in/out per run n/a / n/a

### Exclusions

| run_id | arm | task | trial | status | reason |
|---|---|---|---|---|---|
| `priority-p1-a1_full-bugfix-02-t3` | `a1_full` | bugfix-02 | 3 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed |
| `priority-p1-a1_full-refactor-02-t3` | `a1_full` | refactor-02 | 3 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed |
| `priority-p1-a1_full-review-01-t3` | `a1_full` | review-01 | 3 | completed | degraded: review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed |
| `priority-p1-a1_full-review-03-t3` | `a1_full` | review-03 | 3 | cap_failure | degraded: audit envelope 1 of 4 voices completed |

#### Cap failures (scored 0 on every applicable primary; the sensitivity figure excludes them)

- `priority-p1-a1_full-bugfix-03-t2` (`a1_full`, bugfix-03 t2, cap_phase AUDIT, USD 12.15)
- `priority-p1-a1_full-review-03-t1` (`a1_full`, review-03 t1, cap_phase AUDIT, USD 14.12)
- `priority-p1-a1_full-review-03-t2` (`a1_full`, review-03 t2, cap_phase AUDIT, USD 12.98)
- `priority-p1-a1_full-review-04-t1` (`a1_full`, review-04 t1, cap_phase AUDIT, USD 12.10)
- `priority-p1-a1_full-review-04-t3` (`a1_full`, review-04 t3, cap_phase AUDIT, USD 12.25)

#### Rows listed, never decided

None.

### Sensitivity figure (suite_version 1): sensitivity (cap failures excluded) — no decision uses this

| component | arm | n pairs | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] (defects) | cost Δ % | wall-clock Δ % | excluded share | predicate outcome (not used) |
|---|---|---|---|---|---|---|---|---|
| A2 | `a2_no_sprint_plan` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | no rows |
| A3 | `a3_one_voice` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | no rows |
| A4 | `a4_no_gates` | 12 tasks | 0.000 [0.000, 0.000] | n/a (build-only) | -70.3 % | -72.2 % | 0.000 | Remove |
| A5 | `a5_no_flatline` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | no rows |
| A6 | `a6_one_window` | 0 tasks | no pair | n/a (build-only) | n/a | n/a | n/a | no rows |
| A7 | `a7_effort_medium` | 0 tasks, 0 defects | no pair | no pair | n/a | n/a | n/a | no rows |

#### H1 and A4 lines, sensitivity (cap failures excluded, degraded rows included; decides nothing)

**sensitivity (decides nothing): H1: not established — halt before promotion** — a1_full − a0_bare: hidden_test_pass_rate 0.000 [0.000, 0.000] (n = 12 tasks), defect_catch_rate inconclusive by degradation (a1_full excluded share 0.417 > 0.25); remaining pairs +0.394 [+0.271, +0.517] (n = 11 defects) (cap failures excluded, degraded rows included). Rule (rules.h1): "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"

**sensitivity (decides nothing): A4 sensitivity: fails — harden tasks before acting on other arms** — a4_no_gates − a1_full: hidden_test_pass_rate 0.000 [0.000, 0.000] (n = 12 tasks) (cap failures excluded, degraded rows included). Rule (rules.a4_sensitivity): "a4_no_gates worse than a1_full on hidden_test_pass_rate with the interval excluding zero, else harden tasks before acting on other arms"

### Budget-matched baseline (suite_version 1; informational, decides nothing)

Per review-catch task: the union of the defects any valid a0_bare trial caught (a defect counts once caught by any trial; "rate fallback" is the best trial's rate where the rows carry no per-defect ids), against a1_full's mean per-trial catch rate. Nothing here feeds a decision.

| task | a0_bare trials | a0_bare union catch rate | a0_bare summed cost USD | a1_full trials | a1_full mean per-trial catch rate | a1_full mean cost USD | a1 − a0 union | method |
|---|---|---|---|---|---|---|---|---|
| review-01 | 3 | 1.000 | 0.66 | 2 | 1.000 | 9.52 | 0.000 | rate fallback |
| review-02 | 3 | 0.667 | 0.60 | 3 | 1.000 | 9.30 | +0.333 | rate fallback |
| review-03 | 3 | 0.375 | 3.78 | 2 | 0.000 | 13.55 | -0.375 | rate fallback |
| review-04 | 3 | 0.600 | 2.66 | 3 | 0.200 | 11.30 | -0.400 | rate fallback |

- task mean (tasks with both arms): a0_bare union 0.660, a1_full per-trial 0.550, a1 − a0 union -0.110
- matched cost: 3 a0_bare trials cost USD 1.93 vs one a1_full trial USD 10.92 (task means over 4 tasks)

## Batch record

From each batch's STATUS.json beside its MANIFEST.json (read-only) and the `grade.json` grader_version of its rows' run directories (`<batch>/<arm>/<task>-t<n>[-r<k>]`); a tally is `from→to ×n`.

### suite_version 1

| batch | state | trials planned / rowed | spend USD rows / ledger / spent / max | extra models | rerowed | rerun | drift cleared | outages | cuts | paused arms | grader versions |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `priority-p1` | complete | 132 / 132 | 592.43 / 21.70 / 614.13 / 799.00 | global.anthropic.claude-haiku-4-5-20251001-v1:0: runs 1, output tokens 516 | 11 (contaminated→cap_failure ×3, contaminated→completed ×7, infrastructure_error→completed ×1) | 67 (transport_error→cap_failure ×3, transport_error→completed ×63, transport_error→contaminated ×1) | 1 | 0 | reason max_usd, at_trial 120, spent 1044.674677, max 1039 | none | 1.2.2 ×7, 1.2.3 ×38, 1.2.4 ×85, 1.2.5 ×2, n/a ×134 |

### suite_version 2

| batch | state | trials planned / rowed | spend USD rows / ledger / spent / max | extra models | rerowed | rerun | drift cleared | outages | cuts | paused arms | grader versions |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `priority-v2-p1` | complete | 24 / 24 | 142.49 / 0.00 / 142.49 / 531.00 | none | 24 (completed→completed ×24) | 0 | 0 | 0 | none | none | 1.2.11 ×24 |
| `priority-v2-p1b` | complete | 9 / 9 | 104.26 / 0.00 / 104.26 / 376.00 | none | 0 | 0 | 0 | 0 | none | none | 1.2.11 ×9, n/a ×3 |

## Method

The pre-registered rules block of `evals/suites/ablation-2.0.yaml`, quoted verbatim:

```yaml
rules:   # D-A5: pre-registered, mirrored in NOTES
  threshold_points: 0.03
  cost_lower_pct: 15
  bootstrap: {resamples: 10000, level: 0.90, paired: true, units: {hidden_test_pass_rate: tasks, defect_catch_rate: defects}, also_report: {defect_catch_rate: tasks}}   # DEC-0399
  primaries_by_arm: {build_only: [hidden_test_pass_rate], all_types: [hidden_test_pass_rate, defect_catch_rate]}   # DEC-0400
  cap_failure: counts_as_failed            # 0 on each applicable primary (DEC-0393)
  exclusion: {statuses: [degraded, contaminated, interrupted], mode: pairwise, inconclusive_above_share: 0.25}
  sensitivity_figure: cap_failures_excluded  # printed, never decides
  multiple_comparisons: none                 # expected false positives at 0.90 over 6 components printed
  drift_guard: {cli_version: fixed_per_batch, model_ids: fixed_per_batch}   # DEC-0407
  order: trial_major_seeded_shuffle_within_block
  took_effect_per_trial: true                # a miss → infrastructure_error, arm paused until --clear-arm (DEC-0418)
  predicates:                                # DEC-0416, DEC-0393, DEC-0530; d = arm − A1 point estimate, [lo, hi] its 90 % interval, c/w = cost/wall-clock Δ %; evaluated in this order
    inconclusive_by_degradation: "the arm's excluded share > 0.25 (whatever its interval; DEC-0393)"
    investigate: "else any applicable primary has lo > 0"
    keep: "else any applicable primary has d < -0.03 and hi < 0"
    inconclusive: "else any applicable primary has d < -0.03, or no valid pair"
    remove: "else every applicable primary has d >= -0.03 and (c <= -15 or w <= -15)"
    simplify: "else (every applicable primary within -0.03, cost similar)"
  review_catch: {defect_counts_once_across_gates: true, false_positive_dedupe: cited_region, verdict_accurate_iff: "CHANGES_REQUIRED when the key holds a high or critical defect, APPROVED when none"}   # DEC-0420
  inconclusive_extension_trials: 2
  h1: "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"
  a4_sensitivity: "a4_no_gates worse than a1_full on hidden_test_pass_rate with the interval excluding zero, else harden tasks before acting on other arms"
  decision_states: [investigate, keep, inconclusive, remove, simplify, not_run_cut, inconclusive_by_power]
  mde_cut: 0.10   # sprint Task 3.4: an arm whose MDE at affordable trials exceeds this is pre-declared inconclusive_by_power and not run
```

- Pass rate: the unit is the task; a cell is one task-trial; a task's value is the mean of its valid trials (cap_failure scores 0); a trial excluded in either arm leaves both arms of that comparison (pairwise); a task with no valid cell in either arm leaves the pair and is listed.
- Catch rate: the unit is the defect (task × dK); a defect's value is the share of the arm's valid trials that caught it (ids from the row's defects_missed / recall.missed, else the row's defect_catch_rate for every defect of the task); the task-level figure is also reported and decides nothing.
- Interval: percentile bootstrap of the mean paired difference, 10000 resamples with replacement from random.Random(20261015) (one generator per interval), linear interpolation between order statistics, [lo, hi] at the 0.05 and 0.95 quantiles; d is the mean of the paired differences.
- c and w: (mean_arm − mean_a1) / mean_a1 × 100 over the per-task means of the paired cells (cost_usd, wall_clock_ms).
- MDE: (z(0.95) + z(0.90)) × sd(paired diffs) / sqrt(n); an arm whose predicates read remove or simplify with an MDE above mde_cut (0.1) reads Inconclusive-by-power.
- Predicates are evaluated in order on values rounded to 9 decimals, the degradation guard first (excluded share > 0.25 reads Inconclusive-by-degradation whatever the interval, DEC-0393), then investigate, keep, inconclusive (d < -0.03 or no valid pair), remove, simplify; Inconclusive-by-degradation is the inconclusive outcome whose excluded-share clause matched.
- Suite versions: rows of different suite_version values are never pooled; the main sections read the highest suite_version present (or --suite-version), every other version has its own section.
- H1 and A4 read each primary in order: not testable (no task of its type in either arm) → inconclusive by degradation (either arm's excluded share on that primary's task types > 0.25) → degenerate (a catch-rate pair from one task with no per-defect ids: zero variance by construction, read as no valid pair, also for the component decisions) → no pair → the interval. H1 is decided on the primaries left; with none, H1 reads inconclusive by degradation when every testable primary is, else not yet decidable.

