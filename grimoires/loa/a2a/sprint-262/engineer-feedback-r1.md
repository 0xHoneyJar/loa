# Sprint 262 review — round 1 (cycle-130 Sprint 5, "Analysis, report, documentation, rc.6") — CHANGES_REQUIRED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-18 (2026-10-18T10:55:22Z)
**Implementation:** the Sprint 262 work on `feature/cycle-130-ablation-2.0` up to `82c5cd7d`: row writer 1.2 (`0fda13a0`, R1), report 1.1.0 (`c031144f`, R2) and 1.2.0 (`044ce03d`, R3), the blind re-grade (Task 5.1), `report.md`/`report.json` with `cuts.json` (`38169bb8`, `498f72ed`), the suite README (`e37215e5`, `9d1b2a26`, `2161d2c3`), CHANGELOG entries (`38169bb8`, `9e6ffa11`), the rc.6 release notes (`54632fc6`), DEC-0600 (`82c5cd7d`); records `reviewer.md`, `e2e.md`, `reviewer-r1/r2/r3.md`.
**Dissent:** `adversarial-review.json` (run 1 of ≤ 3, `--type review`, the Sprint 262 diff `4434d450..82c5cd7d` over the report and row-writer code, their bats and fixtures, CHANGELOG, the suite README, report.md, cuts.json and the rc.6 notes — 2,481 lines): two voices (`gpt-5.5-pro`, `claude-headless`; 2 of 2), five findings — 3 BLOCKING, 2 ADVISORY — all five accepted (none rejected); severities set by the lead below. All five are in `ablation-report.py`; none touches a decision or a number of the shipped report (verified: the real rows carry integer `suite_version`s and dotted-numeric grader versions, every row has a version, and the tally defect is presentation-only).
**Local checks:** `evals/tests/` 431/431 on `e95139fe` (the Sprint 262 code was also inside the Sprint 261 audit diff: `a2a/sprint-261/adversarial-audit.json` clean); `validate-ac-verification.sh` exit 0 on `reviewer.md` (AC-5.1 … AC-5.8 verbatim); the real-data report regenerated after each report version with the H1/A4 lines unchanged.

## Findings

### MEDIUM-1 — the batch-record grader-version tally can abort the whole report (DISS-001 + DISS-C-002; CONFIRMED, latent)
`batch_record()` sorts the tally with a key that mixes `int` and `str` segments; two grader versions whose dotted segments differ in kind (`1.2.0` vs `1.2.0-rc1`) raise `TypeError`, which is not a `Fail`, so neither `report.md` nor the JSON twin is written — in a section the header calls never fatal. Every real grader version is dotted-numeric, so the shipped report is unaffected. **Required:** a type-stable key and a never-fatal wrapper (an unsorted tally plus a note on any exception).

### MEDIUM-2 — the grader tally attributes every matching directory to every row (DISS-002; CONFIRMED)
Directories are matched by task and trial, so each rerun attempt is counted for each row and attempts without a grade read `n/a` — the shipped `priority-p1` record says `n/a ×134` beside 132 rows. Presentation only (no decision reads it), but the record must be exact. **Required:** resolve each row to its own directory once (by `run_id`, with the highest `-r<k>` sibling when rerun) and count it once; `priority-p1` must read 132 directories with the inline versions the blind re-grade confirmed (1.2.2 × 7, 1.2.3 × 38, 1.2.4 × 85, 1.2.5 × 2).

### MEDIUM-3 — `version_key()` treats a non-integer `suite_version` as absent (DISS-C-001; CONFIRMED, latent)
A float such as `2.1` falls through to `None` and the row is merged into the other version or aborts the report as "has no suite_version"; `--suite-version 2.0` cannot select version 2. The suite file is `ablation-2.0.yaml` and a 2.x bump is plausible. **Required:** canonical keys for every real number, booleans and blanks absent, the flag normalised with the same rule, stable ordering of mixed keys.

### LOW-1 — `partition()` hard-fails on version-less rows that never reach a decision (DISS-C-003; CONFIRMED, latent)
Smoke and unbatched rows carry `suite_version: null`; one such legacy row in a two-version rows file blocks the report with exit 2 and no override. The tracked rows file has none; the smoke rows live in their own files. **Required:** exit 2 only for a version-less row that would be scored; list the others under the primary version as never decided with the reason.

## What was verified as sound
- The shipped report's decisions: suite v2 H1 established (+0.263 [+0.158, +0.386]), A4 not testable, the five cuts with figures, v1 in its own section — the same numbers under report 1.1.0 and 1.2.0 (R2's and R3's old-vs-new proofs), and the reads-v2.md figures reproduced.
- The docs: the suite README's version table (v1 retired; v2 round 1 retired with no rows; the frozen v2 with its ids, 282 files, grader at the freeze), the task-id line, the regression recipe (dry run → detach → report; the hard gate, the per-type caps, the codex pre-flight); CHANGELOG § Unreleased with the Sprint 261/262 entries and a Fixed list that names every defect found this cycle; the rc.6 notes state the findings plainly and link the report, the reads and the rows.
- Task 5.1: 165 run directories re-graded blind under 1.2.12 and 1.2.13, identical on every key.
- Task 5.4: no pruning made (DEC-0600); AC-5.8 not applicable; the floor and profile suites untouched and green.
- e2e.md: G-1 … G-6 with evidence; G-6's dry run against `9e6ffa11` passed the hard gate and the codex pre-flight.

## Acceptance criteria (AC-5.1 … AC-5.8)
Walked verbatim in `reviewer.md` (validator exit 0): 5.1, 5.2, 5.3, 5.4, 5.6, 5.7 met; 5.5 partially met (bd-2txz1 and bd-yzzb9 commented with the cycle's reading rather than closed: no build-side arm read exists to close them on; bd-j4lwr commented with what landed; bd-8o5rx closed on the Sprint 259 evidence); 5.8 not applicable (no pruning). Pending the round-2 fix for 5.3's "with tests".

## Verdict

CHANGES_REQUIRED — fix MEDIUM-1 … MEDIUM-3 and LOW-1 as report 1.2.1 with tests that fail before and pass after; the shipped report must come out identical on every decision key; then round 2 (dissent run 2 on the fix diff).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":3,"low":1},"excluded":0,"sprint_id":"sprint-262","ts":"2026-10-18T10:55:22Z"} -->
