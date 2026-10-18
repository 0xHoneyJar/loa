# Sprint 260 — Task 3.3: frozen-suite calibration smoke (lead, 2026-10-15)

**Batch:** `evals/results/ablation-2.0/calib-frozen-01/` (`MANIFEST.json`, `STATUS.json`, `run.log`, `driver.log`, `spend.txt`; rows as first graded in `evals/results/ablation-2.0/runs.jsonl` (grader 1.2.0), re-graded rows in `calib-frozen-01/rows-regraded.jsonl` (grader 1.2.2)). A non-smoke batch so the DEC-0435 hard gate ran (gate hashes in `MANIFEST.json.gate`); its rows live outside the tracked `runs.jsonl` and decide nothing (DEC-0428).
**Command:** `run-ablation.sh --source-commit ba11b860 --arms a0_bare,a1_full,a2_no_sprint_plan,a3_one_voice,a4_no_gates,a5_no_flatline,a6_one_window,a7_effort_medium --tasks bugfix-01,review-02 --trials-build 1 --trials-review 1 --results-root evals/results/ablation-2.0 --batch calib-frozen-01 --max-usd 100 --concurrency 3 --pre-registration-ref "NOTES.md § Pre-registration — cycle-130 ablation — 2026-10-15T07:13:29Z"` (dry run, then `--detach`); harness commit `c02d12bb`, grader 1.2.0 at run time; CLI 2.1.299 in `loa-ablation:258` (id `4e37cb5f…`); suite manifest `30e1f2ad…`.
**Outcome:** 12 trials planned (4 applicability refusals: A2, A4, A5, A6 on the review-catch task, DEC-0405), 12 rowed, 0 retries, 0 cap failures, 0 paused arms, 0 drift; wall-clock 08:33 → 09:52 UTC (79 min at concurrency 3); batch spend USD 66.28 (cap 100). Every arm's took-effect evidence OK (`took-effect.sh` on all 12 run dirs, rerun by the lead: 12 × `arm <id>: OK`).

## Rows (grader 1.2.2, re-graded from the run directories; no agent re-run)

| arm | task | status | pass | catch | FP | verdict acc. | USD | min |
|---|---|---|---|---|---|---|---|---|
| a0_bare | bugfix-01 | completed | 1.00 | — | — | — | 0.10 | 1 |
| a0_bare | review-02 | completed | — | 0.667 | 4 | — | 0.25 | 1 |
| a1_full | bugfix-01 | completed | 1.00 | — | — | true | 8.63 | 27 |
| a1_full | review-02 | completed | — | 1.000 | 26 | true | 8.21 | 22 |
| a2_no_sprint_plan | bugfix-01 | completed | 1.00 | — | — | true | 4.53 | 15 |
| a3_one_voice | bugfix-01 | completed | 1.00 | — | — | true | 7.92 | 21 |
| a3_one_voice | review-02 | completed | — | 1.000 | 38 | true | 8.30 | 30 |
| a4_no_gates | bugfix-01 | completed | 1.00 | — | — | — (no gate) | 3.17 | 8 |
| a5_no_flatline | bugfix-01 | completed | 1.00 | — | — | true | 5.77 | 17 |
| a6_one_window | bugfix-01 | completed | 1.00 | — | — | true | 7.64 | 23 |
| a7_effort_medium | bugfix-01 | completed | 1.00 | — | — | true | 5.57 | 18 |
| a7_effort_medium | review-02 | completed | — | 1.000 | 25 | true | 6.19 | 21 |

Every arm took effect (A0: no `.claude/`, no system prompt, no audit rows; A2: no PLAN record; A3: one voice planned in both envelopes; A4: no gate phases, enforce env false; A5: no Flatline MODELINV rows with `sprint.md` present; A6: one implementer session across PLAN/IMPLEMENT/FIX, gates in separate sessions; A7: `--effort medium` on every phase, skill `effort:` lines stripped; all: integrity clean). The gate model (Fable 5.1 for REVIEW/AUDIT) answered on every gated run: the gate-model contingency is not needed.

## Reads

- **Cap fit (PRD FR-7: A1 median cost per build run vs USD 9).** One A1 build run at USD 8.63 → fits, with 4 % headroom; the per-run cap of USD 12 held on every run (max observed 8.63). The smoke covered a bug-fix task; feature-build tasks carry a 60-turn IMPLEMENT bound and may cost more. No shrinking of the tasks; cap failures, if any, score 0 as pre-registered and the sensitivity figure shows their weight.
- **Contamination scan calibration (DEC-0540, DEC-0541).** Under grader 1.2.0, 10 of 12 rows read `contaminated`: Loa slash commands in report text (`/review-sprint sprint-1`) matched as absolute paths (outside_path), the reviewing skill's `git log --oneline --all` matched `git_history`, then prose inside a heredoc (`/arithmetic/quote-parity`), `ls ~/.cargo/bin` inside the container (whose home is an allowed root) and a sed address range (`/,/`). None reached hidden material. Grader 1.2.1/1.2.2 (committed `2ef83aa8`, `ae9df520`, tests AG-10/AG-11 extended) count history probes as telemetry, treat one-component words as command tokens unless they name root/home/mnt/media/srv, strip heredoc bodies before the path-word scan (the hidden/suite/repo scans still read them) and flag `~/` in host mode only. Re-graded: 0 of 12 contaminated. The `hidden`, suite-path, repo-name and two-component outside-path patterns stand; the scan remains a lower bound (D-4.7).
- **Difficulty signal.** Every arm solved `bugfix-01` (25/25 hidden tests), including A0 in one minute for USD 0.10; the review-catch task was caught 3/3 by every Loa arm and 2/3 by A0. On this task pair the suite does not separate the arms; H1 (A1 beats A0 on a primary with the interval excluding zero) is at risk if the sixteen tasks behave like `bugfix-01`. This is a legitimate pre-registered outcome ("H1 fails → halt before promotion, the operator decides") and no task is changed after the smoke (the suite is frozen; a post-hoc hardening would be the thing pre-registration forbids). The priority batch will tell; the A4 sensitivity rule guards the same risk.
- **False positives on review-catch.** The Loa arms flag 25–38 regions on `pr-08` against a key of 3 defects (A0: 4). `false_positives` is a secondary metric; the catch rate is the primary. Recorded for the report.
- **Costs per arm (one build run):** A0 0.10, A4 3.17, A2 4.53, A7 5.57, A5 5.77, A6 7.64, A3 7.92, A1 8.63; per review run: A0 0.25, A7 6.19, A1 8.21, A3 8.30. These are the `est_next` seeds for `batch-plan.md`.

## Decisions carried to `batch-plan.md`

The smoke actuals replace the planning `cost_hint` (build 7, review 8) with per-arm figures; the priority batch is split into two batches so that the cut ladder's rung 2 (A2 and A3 build trials 3 → 2, DEC-0397) is applied up front, because the full priority plan at 3 trials (est. USD 1,078) exceeds the batch ceiling the DEC-0429 formula gives today (USD 1,039). See `batch-plan.md`.
