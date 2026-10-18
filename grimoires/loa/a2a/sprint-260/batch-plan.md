# Sprint 260 — Task 3.4: budget calibration and batch plan (lead, 2026-10-15)

Inputs: `smoke.md` (calibration actuals), `spend.sh` at 2026-10-15T10:35Z: **cycle spend USD 174.79** (runs 145.36 = Sprint 258 smoke 79.08 + calibration 66.28; ledger 29.43 = dissent runs), cap 1,500, reserve 250 (DEC-0398), per-run cap 12. Pre-registration: `NOTES.md § Pre-registration — cycle-130 ablation — 2026-10-15T07:13:29Z` and its addendum 08:03:32Z; this plan is the second NOTES entry (DEC-0428) and precedes the first priority-batch row.

## Unit costs from the smoke (one trial each; the `est_next` seeds)

| arm | build run (USD) | review run (USD) | applicable |
|---|---|---|---|
| a0_bare | 0.10 | 0.25 | all |
| a1_full | 8.63 | 8.21 | all |
| a2_no_sprint_plan | 4.53 | — | build |
| a3_one_voice | 7.92 | 8.30 | all |
| a4_no_gates | 3.17 | — | build |
| a5_no_flatline | 5.77 | — | build |
| a6_one_window | 7.64 | — | build |
| a7_effort_medium | 5.57 | 6.19 | all |

Suite: 12 build tasks (4 bug-fix, 4 refactor, 4 feature-build), 4 review-catch tasks.

## Projection of the priority arms at the planning rung (3 build, 3 review trials)

| arm | build runs | USD | review runs | USD | total |
|---|---|---|---|---|---|
| a0_bare | 36 | 3.6 | 12 | 3.0 | 6.6 |
| a1_full | 36 | 310.7 | 12 | 98.5 | 409.2 |
| a2_no_sprint_plan | 36 | 163.1 | — | — | 163.1 |
| a3_one_voice | 36 | 285.1 | 12 | 99.6 | 384.7 |
| a4_no_gates | 36 | 114.1 | — | — | 114.1 |
| **sum** | 180 | | 36 | | **1,077.7** |

Batch ceiling by the DEC-0429 formula: `--max-usd` = 1,500 − 174.79 − 250 − 3 × 12 = **1,039.21**. The planning rung does not fit by USD 38; the ladder's rung 2 (A2 and A3 build trials 3 → 2; A0, A1, A4 keep 3; DEC-0397) applies before the first row.

## Chosen rung and batches (pre-registered here)

- **Rung 2.** A0, A1, A4: 3 build trials; A0, A1: 3 review trials; A2, A3: 2 build trials; A3: 3 review trials (rung 3 — A3 review 3 → 2 — not needed).
- The runner takes per-type trial counts per batch, so the rung is two sequential batches with the same pre-registration reference and seed:
  - **P1** `--arms a0_bare,a1_full,a4_no_gates --trials-build 3 --trials-review 3` → 36 + 36 + 36 build + 12 + 12 review = 132 runs, est. **USD 530** (A4 refused on review-catch by applicability).
  - **P2** `--arms a2_no_sprint_plan,a3_one_voice --trials-build 2 --trials-review 3` → 24 + 24 build + 12 review = 60 runs, est. **USD 398**.
  - Total est. USD 928; projected spend after both ≈ 1,103; headroom before the reserve ≈ 147.
- **`--max-usd`:** P1 launches at 1,039 (the formula today); P2 launches at `1,500 − spend after P1 − 250 − 36` recomputed from `spend.sh` (expected ≈ 509). Both under `--concurrency 3`. Every cut names its reason and figure in `STATUS.json.cuts[]` and in NOTES.
- **Wall-clock:** build runs 8–27 min (median ≈ 18), review runs 1–30 min (median ≈ 21); P1 ≈ 132 × 18 / 3 ≈ 13 h, P2 ≈ 60 × 18 / 3 ≈ 6 h at concurrency 3.
- **Arms beyond A0–A4 (Task 3.7):** at the smoke unit costs A7 (36 × 5.57 + 12 × 6.19 ≈ 275), A5 (36 × 5.77 ≈ 208) and A6 (36 × 7.64 ≈ 275) each exceed the ≈ 147 that remains before the reserve; they are **pre-declared `Not run (cut)`** with these figures unless the P1/P2 actuals come in lower (recomputed after P2) or the reserve is released (DEC-0398: when the re-verification needs no run, decided in Sprint 261 — then A7 first, per the priority list). A reduced-trial A7 (2 build, 2 review ≈ 158) is the fallback considered at that point, recorded as rung 2 for A7.
- **Minimum detectable effect:** not estimable from the smoke (one build task, one trial per arm: no between-task variance). The pre-registered rule (an arm whose MDE at affordable trials exceeds 0.10 is pre-declared Inconclusive-by-power and not run) therefore applies to A5/A6/A7 using the paired-difference variance of P1 (A4 − A1 and A0 − A1 over the 12 build tasks) once P1 has one trial block per task; A0, A1 and A4 run regardless (H1 and the A4 sensitivity rest on them) and A2, A3 run as the priority components. The report prints the MDE per arm with its decision (`ablation-report.py`).
- **Contingencies restated:** cap fit held (A1 8.63 < 9); the gate model answered on every gated run; cap failures score 0; a transport failure retries once; a took-effect miss pauses the arm until `--resume --clear-arm` after the cause is read; no dissent run while a batch runs (KF-037); harness files are not edited while a batch runs; a provider outage → `--resume`, never a parallel batch.
- **Difficulty caveat (from the smoke):** every arm solved `bugfix-01`; if the twelve build tasks are all solved by every arm, the pass-rate primary cannot separate the arms and H1 rests on the catch rate and on the four feature-build tasks' outcomes. Recorded, not acted on (the suite is frozen).

## Batch commands (dry run, then `--detach`)

```
evals/harness/run-ablation.sh --source-commit ba11b860 --arms a0_bare,a1_full,a4_no_gates \
  --trials-build 3 --trials-review 3 --concurrency 3 --max-usd 1039 --batch priority-p1 \
  --pre-registration-ref "NOTES.md § Batch plan — cycle-130 ablation (Task 3.4) — <ts>" --dry-run
evals/harness/run-ablation.sh --source-commit ba11b860 --arms a2_no_sprint_plan,a3_one_voice \
  --trials-build 2 --trials-review 3 --concurrency 3 --max-usd <recomputed> --batch priority-p2 \
  --pre-registration-ref "NOTES.md § Batch plan — cycle-130 ablation (Task 3.4) — <ts>" --dry-run
```
Rows go to the tracked `grimoires/loa/reports/ablation-2.0/runs.jsonl`; batch files under `grimoires/loa/reports/ablation-2.0/batches/<batch>/` (run directories ignored by the batch's `.gitignore`).
