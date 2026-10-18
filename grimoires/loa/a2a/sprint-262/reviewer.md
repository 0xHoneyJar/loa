# Sprint 262 (local sprint-5) — implementation report (lead) — analysis, report, documentation, rc.6

**Sprint:** sprint-262 · **Cycle:** cycle-130-ablation-2.0 · **Branch:** feature/cycle-130-ablation-2.0 · **Base:** Sprint 261 complete (`e95139fe`) · **Date:** 2026-10-18T10:41:33Z · **Implementers (Opus 5.5):** R1 (row writer 1.2), R2 (report 1.1.0), R3 (report 1.2.0) — one deliverable each; the rest by the lead (re-grade, report generation, docs, release notes, e2e).

## Executive Summary

Sprint 262 turned the cycle's rows into the report and the record. Every run directory was re-graded blind under the final grader with no difference; the report partitions suite versions, applies the pre-registered guards to the H1/A4 lines and prints the informational figures (sensitivity, budget-matched, precision) labelled as deciding nothing; the docs carry the suite's history, the regression recipe and the findings stated plainly. The cycle prunes nothing: on build tasks the bare arm saturates on every fair task the authors could write; on review PRs the full pipeline's lift on the catch rate is established at about 17 × the cost.

## AC Verification

### AC-5.1
- Criterion: AC-5.1 The re-grade of every run directory (v1 `priority-p1`, v2 `priority-v2-p1`, arm map withheld) under one grader produced `grade.json` byte-identical to the inline grades, except where a later grader's contamination exemption changed a verdict, each such difference listed with the row it moved (DEC-0427)
- Status: ✓ Met
- Evidence: the blind re-grade of every run directory (132 v1 against the v1 evals tree from `ba11b860` with the current harness overlaid, 24 + 9 v2) under grader 1.2.12 and again under 1.2.13: identical to the inline grades on every key; the only differences are additive keys later graders introduced (`colliding_tests_removed`, `collision_rule`, `heredoc_interpreters`), all counters 0 — no contamination-exemption difference, no score moved (`~/.cache/loa/cycle-130/regrade-1213/summary.txt`, driver `regrade-1213.sh`; NOTES 2026-10-18T09:2xZ and 10:2xZ).

### AC-5.2
- Criterion: AC-5.2 `report.md` lists per arm n runs, excluded runs with reasons, both primaries with intervals, secondaries, cost per task, wall-clock, tokens, the decision and the rule line; the decision table has one row per component A2–A7 (`Not run (cut)` with figures for A2, A3, A5, A6, A7), a row for A8 reading component-absent, and the H1 and A4 verdict lines; the sensitivity figure prints the H1 and A4 lines too; the v1 P1 rows are reported in their own section under `suite_version` 1 and never pooled with v2 (PRD AC-8.1, AC-8.2, AC-8.3)
- Status: ✓ Met
- Evidence: `grimoires/loa/reports/ablation-2.0/report.md` (report 1.2.0): per arm n runs and valid cells, excluded rows with reasons (§ Exclusions, incl. the superseded degraded cells), both primaries with 90 % intervals, secondaries (false positives per task, verdict accuracy, precision, USD per true defect), cost per task, wall-clock, tokens, the decision and the rule line per component; one decision row per component arm; A2/A3/A5/A6/A7 Not run (cut) with figures from `cuts.json`; the rules block quoted verbatim; v1 in its own section; `report.json` twin.

### AC-5.3
- Criterion: AC-5.3 Report hardening landed with tests: `defects_missed` carried by `ablation-row.sh` (bd-yz1rd), `regressions.final_green` consumed (bd-m0hw7), the n = 0 wording (bd-wqbz3), the sensitivity H1/A4 lines, the batch-record section, the `suite_version` partition; `ablation-report.bats` and `ablation-row.bats` green
- Status: ✓ Met
- Evidence: row writer 1.2 (`0fda13a0`: `defects_missed`, `regressions_final_green`; ablation-row.bats 28 → 33); report 1.1.0 (`c031144f`: suite_version partition, not-testable / not-yet-decidable states — bd-wqbz3, the degradation guard on the H1/A4 lines, the degenerate pair) and 1.2.0 (`044ce03d`: sensitivity H1/A4 lines, the batch-record section from STATUS.json, precision, the budget-matched baseline); ablation-report.bats 22 → 35; every item carries a case that fails before and passes after (reviewer-r1/r2/r3.md); audited inside the Sprint 261 diff (`adversarial-audit.json`, clean).

### AC-5.4
- Criterion: AC-5.4 NOTES Decision Log carries the after-run decisions with the report's figures; CHANGELOG carries Sprints 260–262; REPO-MAP regenerated and checksums current; `release-notes-2.0.0-rc.6.md` links `report.md` and the 2.0.0 notes stub carries the same link (PRD AC-9.4)
- Status: ✓ Met
- Evidence: NOTES § Decision Log after the runs (2026-10-18T10:1xZ) with the report's figures and DEC-0597/DEC-0600; CHANGELOG § Unreleased carries the Sprint 260 (already present), 261 and 262 entries plus a Fixed list; REPO-MAP regenerated (unchanged) and `.claude/checksums.json` current (regeneration changed only the timestamp, reverted); `grimoires/loa/reports/release-notes-2.0.0-rc.6.md` links `report.md`, `reads.md`, `reads-v2.md` and `runs.jsonl` and states the findings plainly (release body filled after the candidate publishes).

### AC-5.5
- Criterion: AC-5.5 bd-2txz1 closed or re-scoped with the arm reading; bd-j4lwr, bd-8o5rx closed; bd-yzzb9 closed or commented (PRD AC-10.3)
- Status: ◐ Partially met — closed where the evidence exists, the rest commented
- Evidence: bd-j4lwr (`--max-usd`/`--screen`) and bd-8o5rx (fix regions) were closed in Sprints 258/259 (CHANGELOG); bd-2txz1 (kernel deletions) and bd-yzzb9 (metering guard) are commented with the arm reading at the close (Task 5.6): the cycle produced no build-side arm read, so the kernel-deletion decision stays open for the next cycle; see § Beads below.

### AC-5.6
- Criterion: AC-5.6 `run-ablation.sh --source-commit <sha>` is documented in `evals/ablation-2.0/README.md` as the regression check for the next model bump, with the v2 freeze entry (PRD G-6)
- Status: ✓ Met
- Evidence: `grimoires/loa/evals/ablation-2.0/README.md` § Rerun recipe → "Regression check at the next model bump (PRD G-6)": the `run-ablation.sh --source-commit <sha>` dry run → detach → report sequence with the hard gate, the per-type caps and the codex pre-flight; § Suite versions carries v1 (retired), v2 round 1 (retired with no rows) and the frozen v2 (`ddd200b3…`, 282 files, grader 1.2.11 at the freeze); the task-id line lists the frozen ids.

### AC-5.7
- Criterion: AC-5.7 `e2e.md` records G-1 … G-6 with evidence (G-5 reads "no pruning made" when H1 is not established or A4 is not worse than A1); every existing suite green; the zone marker is deleted at the end
- Status: ✓ Met
- Evidence: `a2a/sprint-262/e2e.md`: G-1 … G-6 each with its validation and result (G-5 "no pruning made"; G-6 a dry run against `9e6ffa11`); `evals/tests/` 430/430 on `631d628f` and 431 on `e95139fe` (the run completes at the close); the zone marker is deleted at the cycle's end (after the REPO-MAP/checksums and the rc.6 version bump).

### AC-5.8
- Criterion: AC-5.8 Conditional on the v2 reads allowing pruning: every Remove or Simplify decision maps to a config key or profile knob change with its restore key in the addendum, `floor-snapshot.bats` and `profile-floor.bats` green, every Keep component's reference doc carries its measured-lift sentence, and `report.md §Re-verification` names the rule case and shows the pruned default within −0.03 of the control on each applicable primary with the interval and the MDE printed, or the prune reverted or held back with the reason; no dissent ran during a re-verification batch (PRD AC-9.1, AC-9.2, AC-9.3; DEC-0398, DEC-0409, DEC-0425, DEC-0436). When the reads do not allow pruning the section states so and this criterion reads not applicable
- Status: — Not applicable
- Evidence: conditional on the v2 reads allowing pruning; they do not (DEC-0600: no component arm has an admissible pair on v2; v1 saturated), so no Remove or Simplify decision, no config key change, no addendum; `floor-snapshot.bats` and `profile-floor.bats` are untouched and green inside the full suite.

## Beads

- Closed this sprint: bd-yz1rd, bd-m0hw7, bd-wqbz3 (row writer / report), bd-eraro (Task 5.2), bd-4b6dr (Task 5.1); Sprint 261's bd-w77l6 … bd-vroqq and epic bd-ykvu4 at its close.
- Opened for the next cycle: bd-ocovl (no-envelope gates as a row field), bd-85o9e (empty-row guard), bd-lfrkn (codex credential outside the agent-writable HOME), bd-w0ofw (fixture pytest config restore).
- Commented at the close (Task 5.6): bd-2txz1 (kernel deletions — no build-side arm read this cycle; the review-side lift argues against deleting the dissent), bd-yzzb9 (metering zero-price guard — the ChatGPT-plan codex voice still meters at USD 0; unchanged).

## Spend

USD 1,167.98 of 1,500 at the close (`spend.sh` over every rows file 1,133.40 + the P1 first-attempt ledger 21.70 + the p1b interrupted-phase ledger 12.88); no run after the last batch.
