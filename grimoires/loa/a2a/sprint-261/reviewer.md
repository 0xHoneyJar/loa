# Sprint 261 (local sprint-4) — implementation report (lead) — COMPLETE (halted on the v2 read DEC-0592, resumed under DEC-0593 option (a), H1 established DEC-0597)

**Sprint:** sprint-261 · **Cycle:** cycle-130-ablation-2.0 · **Branch:** feature/cycle-130-ablation-2.0 · **Base:** 4434d450 (Sprint 260 complete) · **Scope:** DEC-0559 (operator option 1), re-scoped by DEC-0564/0565 · **Implementers (Opus 5.5):** K (per-type caps, `../loa-wt-s4k`), K2 (bats on v2 ids), D2/E2 (round-1 v2 tasks), D3/E3/F3 (round-2 swap tasks), fairness reviewers R1/R2/R3 (one per task after two six-task reviewers stalled), C (KF-048 credential fix), R1/R2/R3 (row writer 1.2, report 1.1.0/1.2.0 for Sprint 262), G/G2 (graders 1.2.12/1.2.13), P/P2 (codex pre-flight rounds) · **Lead:** Tasks 4.1, 4.5–4.9, the runner `--types` fix, graders 1.2.10/1.2.11, BARE bounds, two brief/criterion corrections · **Reports:** `reviewer-k.md`, `reviewer-d2.md`, `reviewer-e2.md`, plus the round-2 authors' reports under `~/.cache/loa/cycle-130/reports/s4-{d3,e3,f3}.md` (copied at close), `smoke-v2.md`, `self-check-image-v2.log`.

## Executive Summary

Sprint 261 tried to build a suite on which the bare arm does not saturate, and could not within the pre-registered bar. A hardness criterion was written before any task (NOTES 2026-10-16T22:00:49Z, DEC-0566): a build task enters suite v2 only if a0_bare's pass rate over two calibration trials is ≤ 0.5, with the twelve together ≤ 0.75 and at least six below 1.0, at most two authoring rounds. Round 1 (twelve tasks by D2/E2, 3–8 files, references 82–341 lines) read 1.0 on eleven of twelve; round 2 (ten spec-conformance tasks at 600–1,500 lines with oracle suites and 40-constraint refactors, by D3/E3/F3) read 1.0 on nineteen of twenty trials. Every author's blind self-solve agreed. No build task entered the batch (DEC-0590). The per-type run caps (DEC-0567) were built and proven: the review-catch cap fits (A1 median 14.62 ≤ 15.00 on the two PRs that P1 had cut at USD 12), the build cap would bind (round-2 A1 refactor run cap failure at 15.75 in AUDIT). The batch `priority-v2-p1` therefore runs the measurable half of the operator's rerun — a0_bare and a1_full on the four review-catch tasks at three trials — under a fresh pre-registration (2026-10-17T18:40:55Z, DEC-0591); H1 is read on the catch rate, and the pass-rate H1 and the A4 sensitivity are "not testable on suite v2".

Harness defects found and fixed on the way: `run-ablation.sh --types` was a dead branch that failed every typed batch (b5cf34cf, RAB-27); A0's BARE budget did not grow with the v2 IMPLEMENT bounds (task bounds BARE 80 min / 190 turns, DEC-0580); grader 1.2.10's `--import-mode=importlib` broke sibling imports and was replaced by 1.2.11's targeted basename-collision guard (DEC-0585, DEC-0589, AG-35).

## AC Verification

### AC-4.1
- Criterion: AC-4.1 The hardness criterion (a0_bare's calibration pass rate ≤ 0.5 on each task over 2 trials; the twelve together a0_bare mean ≤ 0.75 with at least six tasks below 1.0; a failing task is swapped, at most two authoring rounds; the reference still passes the hidden tests; the fixture suite green at base and reference) and the caps (build USD 15, review-catch USD 20; cap fit: A1's median cost per run on the smoke ≤ 0.75 × the type's cap, else the tasks shrink or the cap rises before the re-pre-registration) are timestamped in NOTES before the first v2 task is authored; the re-pre-registration entry (suite_version 2 and its manifest hash, the caps, the hardness result, the rules unchanged, the H1/A4 halt conditions, trials per cell, `--max-usd`, the MDE from P1's paired variance, the breaker, the outage clause, A2/A3/A5/A6/A7 pre-declared `Not run (cut)` with figures) is timestamped before the first `priority-v2-p1` row; smoke rows decide nothing (DEC-0428, DEC-0559)
- Status: ✓ Met
- Evidence: NOTES § "Sprints 261/262 re-scoped (Step B); suite v2 hardness criterion and per-type caps PRE-REGISTERED" 2026-10-16T22:00:49Z (DEC-0566, DEC-0567) precedes every v2 task file (D2/E2 dispatched after it; their worktrees cut at 4c279606); NOTES § "Re-pre-registration — cycle-130 ablation, suite v2 batch priority-v2-p1 — 2026-10-17T18:40:55Z" precedes the batch launch 18:41:24Z and is its `pre_registration_ref`; the calibration rows live in `evals/results/ablation-2.0/runs.jsonl`, never the tracked file.

### AC-4.2
- Criterion: AC-4.2 `run-ablation.sh --dry-run` on suite v2 prints the plan with the per-type caps and writes `MANIFEST.json` with `caps.run_usd_by_type`, `suite_version: 2`, the v2 manifest hash and `source_commit ba11b860`; `run-ablation.bats` covers the per-type cap on dispatch (`--max-run-usd` per task type), on the in-flight reservation and on the assumed charge; the hard gate still requires sixteen `REVIEW.md` files and 36 PASS lines
- Status: ✓ Met
- Evidence: `grimoires/loa/reports/ablation-2.0/batches/priority-v2-p1/MANIFEST.json` (`caps.run_usd_by_type {build 15, review-catch 20}`, `suite_version 2`, `suite_manifest_sha256 ddd200b3…`, `source_commit ba11b860…`, gate 36 PASS lines and 16 REVIEW.md); `evals/tests/run-ablation.bats` RAB-22 … RAB-26 (implementer K), RAB-27 (`--types`), RAB-3 (hard gate); 386/386 at bde0c22e.

### AC-4.3
- Criterion: AC-4.3 Every v2 build task: the reference touches 3–6 files and is 80–200 lines; hidden tests exercise interactions and edge cases the brief does not spell out, red at base and green at reference inside `loa-ablation:258` (`--self-check` logged); `regression_command` green at both ends; `grader_protected` covers every file under `fixture/tests/`; no cache directory in the fixture; no `hidden` token in agent-facing text (TASK.md, fixture, brief); bounds `{max_turns: {IMPLEMENT: 80}, timeout_min: {IMPLEMENT: 35}}`; `validate-suite.sh` valid; `freeze.sh --check` OK; a `REVIEW.md` PASS by an Opus reviewer who did not author the task (DEC-0435)
- Status: ✓ Met (with recorded deviations from authoring targets)
- Evidence: `self-check-image-v2.log` 36/36 PASS on the frozen suite (ddd200b3…, grader 1.2.11); sixteen `REVIEW.md` PASS (per-task Opus reviewers; refactor-v2-03, bugfix-v2-01 and bugfix-v2-07 each passed on a second review after a fix — DEC-0581, DEC-0587); `validate-suite.sh --smoke` OK 18. Reference sizes exceed the 80–200-line target on several round-2 tasks (up to 1,323 changed lines for the refactors; module splits count moved lines twice) and refactor tasks touch up to 21 files — targets, not criteria (NOTES 2026-10-16T22:00:49Z), recorded in the authors' DECISION bullets.

### AC-4.4
- Criterion: AC-4.4 On the frozen v2 set the calibration smoke's a0_bare pass rates satisfy the pre-registered criterion, or every swap round and the final read are recorded in `smoke-v2.md`; A1's median cost per run on the smoke ≤ 0.75 × the type's cap, or the recorded adjustment and its re-pre-registration
- Status: ✓ Met (the second branch: the criterion failed and every round and read is recorded)
- Evidence: `smoke-v2.md` (round 1 `calib-v2-01a`: mean 0.958, 1 of 12 below 1.0; round 2 `calib-v2-02a`: 19 of 20 trials at 1.0, the twelve mean 0.956, two below 1.0, one ≤ 0.5; cap-fit `calib-v2-01b`: review-catch median 14.62 ≤ 15.00 fits, build median 12.45 > 11.25 on round-1 tasks; `calib-v2-02b` refactor-v2-05 cap failure at 15.75); DEC-0584, DEC-0586, DEC-0590.

### AC-4.5
- Criterion: AC-4.5 Every `priority-v2-p1` row carries `attempts`/`retry_reason`, `suite_version` 2, the v2 manifest hash and `cap_phase` when capped; cap failures are `cap_failure`; outage rows are rerun by `--resume --rerun-status`; contaminated rows are hand-read (KF-046) and, when the hit is an idiom, the grader is bumped and the row re-rowed; no dissent run started while the batch ran (timestamps in the sprint report); spend posted after the batch from `spend.sh`; the cycle total ≤ USD 1,500 (PRD G-4)
- Status: ✓ Met — the nine a1_full cells degraded by the credential failure (KF-048) were re-run as `priority-v2-p1b` under a pre-registered addendum (NOTES 2026-10-18T06:07:55Z, DEC-0595) and every valid row supersedes its degraded cell
- Evidence: 24 rows in `grimoires/loa/reports/ablation-2.0/runs.jsonl` (batch `priority-v2-p1`), each with `attempts 1`, `retry_reason null`, `suite_version 2`, `suite_manifest_sha256 ddd200b3…`; no cap failure, no transport row, no outage, no contamination; STATUS `complete`, spent USD 142.49; batch window 18:41:24Z–20:48:53Z with no dissent run (the last Sprint 260 dissent ended 23:0xZ on 16 Oct; none started since); spend post NOTES 2026-10-17T21:1xZ: USD 1,050.84 of 1,500. Nine a1_full rows are `degraded` (the OpenAI dissent voice failed with `401 refresh_token_reused` in every container; the companion answered) — excluded pairwise as pre-registered.

### AC-4.6
- Criterion: AC-4.6 `reads-v2.md` records H1 (a1_full − a0_bare on either primary, interval excluding zero) and A4 (a4_no_gates − a1_full on the pass rate, interval excluding zero) with their intervals and the action; H1 fails → the halt is recorded (DEC row, NOTES, PR #1283 body) and the operator is reported to with options; A4 not worse than A1 → "no pruning of A4" recorded and the cycle continues to the report
- Status: ✓ Met (twice: the halt read, then the read after the supplementary batch)
- Evidence: `grimoires/loa/a2a/sprint-261/reads-v2.md`: H1 on the catch rate inconclusive by degradation (a1_full excluded share 0.75 > 0.25; the residual single-task interval +0.133 [+0.133, +0.133] is degenerate) → **not established → halt** (DEC-0592); the pass-rate H1 and A4 not testable on suite v2 (no admissible build task) → no pruning of A4; the sensitivity figure with degraded rows included +0.298 [+0.208, +0.392] (decides nothing); the operator's options (a)–(d).
  **After the supplementary batch** (`reads-v2.md` § After the supplementary batch, 2026-10-18T08:40Z): H1 on `defect_catch_rate` **established, +0.263 [+0.158, +0.386]** (19 defects; 12 valid a1_full cells vs 12 a0_bare; a1 excluded share 0; not degenerate — per-defect ids from `defects_missed`); the pass-rate H1 and A4 not testable on suite v2 → no pruning of A4 → the cycle continued (DEC-0597). Disclosed beside the read: four valid a1 cells ran a gate with no dissent envelope (budget_exceeded × 3, the 420 s cap × 1; bead bd-ocovl); the strict reading would be inconclusive by degradation (share 0.333) with the direction unchanged.

### AC-4.7
- Criterion: the harness changes of the sprint (per-type caps, `--types`, graders, the credential fix) carry tests that fail before and pass after; `evals/tests/` green
- Status: ✓ Met
- Evidence: RAB-22 … RAB-27 (caps, reservation, assumed charges, `--types`), RAB-28 … RAB-41 (the codex pre-flight: horizon, API-key mode, remaining trials, override, writer robustness, `rerun_pending`), pipeline-run.bats +4 (the credential copy, KF-048 both causes, the API-key knob), AG-35 … AG-44 (graders 1.2.11 → 1.2.13), ablation-row.bats 29–33, ablation-report.bats AR-23 … AR-35; `evals/tests/` 372 → 430 on `631d628f` (431 with the audit fix `e95139fe`); every implementer proved fails-before by swapping in the pre-fix script.

### AC-4.8
- Criterion: the credential failure (KF-048) is understood, fixed and proven live; the ledger entry carries both causes
- Status: ✓ Met
- Evidence: cause 1 (the host's single-use refresh token consumed by the first container to refresh) → the copy without the refresh token (`b4ef76bf`) → cause 2 found live on `priority-v2-p1b`'s first three trials (the codex CLI treats a missing key as logged out: `401 Missing bearer`, reproduced on the host both ways) → the placeholder value (`00ce0a5a`); the batch stopped on the pre-registered condition (USD 12.88 of REVIEW phases, no rows) and resumed; 9 of 9 rows with both voices on every REVIEW/AUDIT envelope but one (the 420 s cap, disclosed); KF-048 recurrence 2, attempt rows and reading guide for both causes; pre-flight 6 refuses a token that would expire inside the batch (`codex_token_exp`, `codex_preflight` in MANIFEST/STATUS).

### AC-4.9
- Criterion: the sprint's code passed review and audit with the dissent runs within the cap of three, and every run directory re-grades identically under the final grader
- Status: ✓ Met
- Evidence: dissent run 1 (review, 6 findings), run 2 (review on the fixes, 6 findings), run 3 (audit, 3 findings: one fixed `e95139fe`, one refuted with evidence, one bead) — twelve of twelve review findings accepted; review r3 APPROVED, audit APPROVED (`engineer-feedback.md`, `auditor-sprint-feedback.md`); the blind re-grade of 165 run directories under 1.2.12 and again under 1.2.13 identical to the inline grades on every key (`~/.cache/loa/cycle-130/regrade-1213/summary.txt`); the official image self-check 36/36 under 1.2.11, 1.2.12 and 1.2.13.

## Batches of the sprint

| batch | arms × tasks × trials | rows | USD | result |
|---|---|---|---|---|
| `calib-v2-01a`, `-01b`, `-02a`, `-02b` (calibration, `evals/results/`) | a0 × build tasks × 2; a1 cap-fit | 24 + 4 + 20 + 2 | ≈ 81 | the hardness criterion failed twice (DEC-0590); review-catch cap-fit holds |
| `priority-v2-p1` | a0_bare, a1_full × review-01 … 04 × 3 | 24 | 142.49 | nine a1 rows degraded by KF-048 → HALT (DEC-0592) |
| `priority-v2-p1b` | a1_full × review-01 … 03 × 3 | 9 (+ 3 interrupted REVIEW phases) | 104.26 + 12.88 | all valid, both voices; H1 established (DEC-0597) |

Spend at the close: USD 1,167.98 of 1,500 (`spend.sh` over every rows file 1,133.40 + the P1 first-attempt ledger 21.70 + the p1b interrupted-phase ledger 12.88).

## Decisions recorded

DEC-0566 … DEC-0591 (the suite v2 rounds, caps, criterion, batch), DEC-0592 (halt), DEC-0593 (option (a)), DEC-0594 (KF-048 fix design), DEC-0595 (the p1b addendum), DEC-0596 (the stop and the corrected copy), DEC-0597 (H1 established, no pruning), DEC-0598 (grader 1.2.12), DEC-0599 (grader 1.2.13). Beads opened for the next cycle: bd-ocovl (no-envelope gates), bd-85o9e (empty-row guard), bd-lfrkn (credential holder), bd-w0ofw (fixture pytest config restore).
