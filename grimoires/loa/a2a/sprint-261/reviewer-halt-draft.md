# Sprint 261 (local sprint-4) — implementation report (lead) — HALTED on the v2 read (DEC-0592)

**Sprint:** sprint-261 · **Cycle:** cycle-130-ablation-2.0 · **Branch:** feature/cycle-130-ablation-2.0 · **Base:** 4434d450 (Sprint 260 complete) · **Scope:** DEC-0559 (operator option 1), re-scoped by DEC-0564/0565 · **Implementers (Opus 5.5):** K (per-type caps, `../loa-wt-s4k`), K2 (bats on v2 ids), D2/E2 (round-1 v2 tasks), D3/E3/F3 (round-2 swap tasks), fairness reviewers R1/R2/R3 (one per task after two six-task reviewers stalled), H2 started for Sprint 262 · **Lead:** Tasks 4.1, 4.5–4.9, the runner `--types` fix, graders 1.2.10/1.2.11, BARE bounds, two brief/criterion corrections · **Reports:** `reviewer-k.md`, `reviewer-d2.md`, `reviewer-e2.md`, plus the round-2 authors' reports under `~/.cache/loa/cycle-130/reports/s4-{d3,e3,f3}.md` (copied at close), `smoke-v2.md`, `self-check-image-v2.log`.

## Executive Summary

Sprint 261 tried to build a suite on which the bare arm does not saturate, and could not within the pre-registered bar. A hardness criterion was written before any task (NOTES 2026-10-16T22:00:49Z, DEC-0566): a build task enters suite v2 only if a0_bare's pass rate over two calibration trials is ≤ 0.5, with the twelve together ≤ 0.75 and at least six below 1.0, at most two authoring rounds. Round 1 (twelve tasks by D2/E2, 3–8 files, references 82–341 lines) read 1.0 on eleven of twelve; round 2 (ten spec-conformance tasks at 600–1,500 lines with oracle suites and 40-constraint refactors, by D3/E3/F3) read 1.0 on nineteen of twenty trials. Every author's blind self-solve agreed. No build task entered the batch (DEC-0590). The per-type run caps (DEC-0567) were built and proven: the review-catch cap fits (A1 median 14.62 ≤ 15.00 on the two PRs that P1 had cut at USD 12), the build cap would bind (round-2 A1 refactor run cap failure at 15.75 in AUDIT). The batch `priority-v2-p1` therefore runs the measurable half of the operator's rerun — a0_bare and a1_full on the four review-catch tasks at three trials — under a fresh pre-registration (2026-10-17T18:40:55Z, DEC-0591); H1 is read on the catch rate, and the pass-rate H1 and the A4 sensitivity are "not testable on suite v2".

Harness defects found and fixed on the way: `run-ablation.sh --types` was a dead branch that failed every typed batch (b5cf34cf, RAB-27); A0's BARE budget did not grow with the v2 IMPLEMENT bounds (task bounds BARE 80 min / 190 turns, DEC-0580); grader 1.2.10's `--import-mode=importlib` broke sibling imports and was replaced by 1.2.11's targeted basename-collision guard (DEC-0585, DEC-0589, AG-35).

## AC Verification

### AC-4.1
- Criterion: the hardness criterion and the caps timestamped in NOTES before the first v2 task; the re-pre-registration entry timestamped before the first priority-v2-p1 row; smoke rows decide nothing
- Status: ✓ Met
- Evidence: NOTES § "Sprints 261/262 re-scoped (Step B); suite v2 hardness criterion and per-type caps PRE-REGISTERED" 2026-10-16T22:00:49Z (DEC-0566, DEC-0567) precedes every v2 task file (D2/E2 dispatched after it; their worktrees cut at 4c279606); NOTES § "Re-pre-registration — cycle-130 ablation, suite v2 batch priority-v2-p1 — 2026-10-17T18:40:55Z" precedes the batch launch 18:41:24Z and is its `pre_registration_ref`; the calibration rows live in `evals/results/ablation-2.0/runs.jsonl`, never the tracked file.

### AC-4.2
- Criterion: `run-ablation.sh --dry-run` on suite v2 prints the per-type caps and writes them, `suite_version: 2`, the v2 manifest hash and the pin into MANIFEST; bats cover dispatch, reservation and assumed charges per type; the hard gate still requires sixteen REVIEW.md and 36 PASS lines
- Status: ✓ Met
- Evidence: `grimoires/loa/reports/ablation-2.0/batches/priority-v2-p1/MANIFEST.json` (`caps.run_usd_by_type {build 15, review-catch 20}`, `suite_version 2`, `suite_manifest_sha256 ddd200b3…`, `source_commit ba11b860…`, gate 36 PASS lines and 16 REVIEW.md); `evals/tests/run-ablation.bats` RAB-22 … RAB-26 (implementer K), RAB-27 (`--types`), RAB-3 (hard gate); 386/386 at bde0c22e.

### AC-4.3
- Criterion: every v2 build task meets the authoring constraints, red at base and green at reference in the image, fairness PASS
- Status: ✓ Met (with recorded deviations from authoring targets)
- Evidence: `self-check-image-v2.log` 36/36 PASS on the frozen suite (ddd200b3…, grader 1.2.11); sixteen `REVIEW.md` PASS (per-task Opus reviewers; refactor-v2-03, bugfix-v2-01 and bugfix-v2-07 each passed on a second review after a fix — DEC-0581, DEC-0587); `validate-suite.sh --smoke` OK 18. Reference sizes exceed the 80–200-line target on several round-2 tasks (up to 1,323 changed lines for the refactors; module splits count moved lines twice) and refactor tasks touch up to 21 files — targets, not criteria (NOTES 2026-10-16T22:00:49Z), recorded in the authors' DECISION bullets.

### AC-4.4
- Criterion: the calibration smoke's a0 pass rates satisfy the criterion, or every swap round and the final read are recorded; A1's cap-fit read or the recorded adjustment
- Status: ✓ Met (the second branch: the criterion failed and every round and read is recorded)
- Evidence: `smoke-v2.md` (round 1 `calib-v2-01a`: mean 0.958, 1 of 12 below 1.0; round 2 `calib-v2-02a`: 19 of 20 trials at 1.0, the twelve mean 0.956, two below 1.0, one ≤ 0.5; cap-fit `calib-v2-01b`: review-catch median 14.62 ≤ 15.00 fits, build median 12.45 > 11.25 on round-1 tasks; `calib-v2-02b` refactor-v2-05 cap failure at 15.75); DEC-0584, DEC-0586, DEC-0590.

### AC-4.5
- Criterion: every priority-v2-p1 row carries attempts/retry_reason, suite_version 2, the v2 manifest hash, cap_phase when capped; outage reruns; contaminated rows hand-read; no dissent during the batch; spend posted; total ≤ USD 1,500
- Status: ✓ Met (the rows); ◐ nine a1_full cells degraded by a credential failure (KF-048)
- Evidence: 24 rows in `grimoires/loa/reports/ablation-2.0/runs.jsonl` (batch `priority-v2-p1`), each with `attempts 1`, `retry_reason null`, `suite_version 2`, `suite_manifest_sha256 ddd200b3…`; no cap failure, no transport row, no outage, no contamination; STATUS `complete`, spent USD 142.49; batch window 18:41:24Z–20:48:53Z with no dissent run (the last Sprint 260 dissent ended 23:0xZ on 16 Oct; none started since); spend post NOTES 2026-10-17T21:1xZ: USD 1,050.84 of 1,500. Nine a1_full rows are `degraded` (the OpenAI dissent voice failed with `401 refresh_token_reused` in every container; the companion answered) — excluded pairwise as pre-registered.

### AC-4.6
- Criterion: `reads-v2.md` records H1 and A4 with intervals and the action
- Status: ✓ Met
- Evidence: `grimoires/loa/a2a/sprint-261/reads-v2.md`: H1 on the catch rate inconclusive by degradation (a1_full excluded share 0.75 > 0.25; the residual single-task interval +0.133 [+0.133, +0.133] is degenerate) → **not established → halt** (DEC-0592); the pass-rate H1 and A4 not testable on suite v2 (no admissible build task) → no pruning of A4; the sensitivity figure with degraded rows included +0.298 [+0.208, +0.392] (decides nothing); the operator's options (a)–(d).
