# tasks/ — the calibration (bare arm only)

Batch `bv-o55b` (loa-smol `runs/build-variance/bv-o55b/`, rows in `runs/build-variance/runs.jsonl`): arm a0_bare (Opus 5.5, the suite default BARE model, effort high), one trial per task, egress blocked, image `loa-ablation:259`, cap USD 15, one container at a time. The suite's MANIFEST.sha256 at the batch's pre-flight was `2ef9f39e73d4a4df75561f16a152687c6495ca95c3ef8c8d6fcbbe9e43b0ccdd` (REVIEW.md placeholders; see the suite README). The rows were graded by `ablation-grade.sh --suite-file evals/suites/ablation-2.0-v3.yaml` (`--resume --rerow` after the grader learnt the flag). Written 2026-10-26.

The rule: a task stays in the suite only when the bare arm failed at least one hidden test in calibration (hidden-test pass rate below 1.000 on a valid cell).

| task | status | hidden passed/total | pass rate | cost USD | wall min | verdict | failed cases |
|---|---|---|---|---|---|---|---|
| bugfix-v3-01 | completed | 63/63 | 1.0000 | 0.40 | 3.5 | dropped (bare arm 1.000) |  |
| bugfix-v3-02 | completed | 7/7 | 1.0000 | 0.15 | 0.7 | dropped (bare arm 1.000) |  |
| bugfix-v3-03 | completed | 9/9 | 1.0000 | 0.33 | 1.8 | dropped (bare arm 1.000) |  |
| bugfix-v3-04 | completed | 51/51 | 1.0000 | 0.76 | 10.6 | dropped (bare arm 1.000) |  |
| bugfix-v3-05 | completed | 40/41 | 0.9756 | 0.52 | 3.5 | kept |  |
| bugfix-v3-06 | completed | 38/39 | 0.9744 | 0.45 | 3.5 | kept |  |
| bugfix-v3-07 | completed | 36/37 | 0.9730 | 0.57 | 3.0 | kept |  |
| bugfix-v3-08 | completed | 50/51 | 0.9804 | 0.45 | 3.3 | kept |  |

- Kept (4): bugfix-v3-05, bugfix-v3-06, bugfix-v3-07, bugfix-v3-08
- Dropped (4): bugfix-v3-01, bugfix-v3-02, bugfix-v3-03, bugfix-v3-04

Spend on the batch's rows: USD 3.63; metered in `.run/cost-ledger.jsonl` under trace ids `repair-build-bv-o55b-…`.
