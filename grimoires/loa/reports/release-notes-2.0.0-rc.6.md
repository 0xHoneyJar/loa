# Release notes: v2.0.0-rc.6 (pre-release) — Loa 2.0 component ablation

Prepared 2026-10-18 by the cycle-130 lead for the post-merge pipeline, which fills the "Release body" section from the merge and finalises the CHANGELOG heading. The full release note is the CHANGELOG `## [Unreleased]` section at the merge (cycle-130, sprints 258–262); this file states the findings plainly and links the report.

## What was measured (PRD G-1, G-2)

A frozen task suite with hidden tests graded outside the agent tree, nine pre-registered arms (bare Claude Code at effort high; full Loa at v2.0.0-rc.5 pinned at `ba11b860`; seven component ablations), one container executor per run, pre-registered decision rules (0.03 points on the primaries, 15 % on cost, paired bootstrap 10,000 at 90 %, pairwise exclusion of degraded runs with a 25 % guard), a blind mechanical grader (1.2.13 at the close; every run directory re-graded under it is identical to its inline grade), and the running spend posted after every batch (USD 1,167.98 of the USD 1,500 cap).

Report: `grimoires/loa/reports/ablation-2.0/report.md` (JSON twin beside it); reads: `grimoires/loa/a2a/sprint-260/reads.md` (suite v1), `grimoires/loa/a2a/sprint-261/reads-v2.md` (suite v2); rows: `grimoires/loa/reports/ablation-2.0/runs.jsonl` (165 rows, `suite_version` 1 and 2, never pooled).

## The findings, plainly

- **Build tasks: no measurable benefit of Loa at this scale.** Suite v1's twelve build tasks saturated at 1.000 on every arm (bare, full, no gates). Suite v2's authors (three Opus 5.5 agents, two pre-registered rounds, seventeen designs: 600–1,500-line fixtures, 30–60 hidden cases including oracle conformance, 40-constraint refactors) could not produce a fair, fully specified build task that bare Opus 5.5 at effort high fails: 30 of 32 calibration trials scored 1.0. The pre-registered hardness criterion failed twice, so no build task entered a v2 batch and the pass-rate primary is "not testable on suite_version 2". The A4 sensitivity (no gates vs full) is therefore not testable either, and **no pruning was made** (G-5 reads "no pruning made").
- **Review PRs: a lift at a cost.** On the four review-catch PRs (seeded defects, three trials per cell, twelve valid cells per arm after the KF-048 rerun), the full pipeline (two review gates, each with a two-voice dissent) catches more seeded defects than one bare pass: `defect_catch_rate` +0.263 [+0.158, +0.386] on 19 defects — H1 established under the pre-registered rules. The lift sits on the large PR (18 of 24 defects against 6 of 24) and is absent on the two small ones (9 of 9 both). The cost: USD 11.64 per run against 0.70 (≈ 17 ×), 28.8 minutes against 2.8, two to fourteen times the false positives per task, precision per flagged region 0.107 against 0.199 (USD 3.04 per true defect against 0.27). **Budget-matched (informational, decides nothing):** three bare passes per task, taking the union of their catches, reach 0.744 against the pipeline's 0.854 per trial (+0.110 for the pipeline) at USD 2.11 against 11.64 — three bare passes for a fifth of the cost close less than half of the gap on the large PR and none of it on the small ones.
- **A disclosure.** Four of the twelve valid pipeline cells ran a gate with no dissent envelope at all (the framework's own dissent budget gate refused the largest diff three times; one dissent run hit its 420 s wall-clock cap); the row writer cannot flag that shape (bead bd-ocovl), and both are the pinned framework's behaviour rather than an infrastructure failure, so the pre-registered read stands. Treating those four cells as degraded would make the read "inconclusive by degradation" (excluded share 0.333); the direction of the effect holds under every reading.
- **Infrastructure findings that shaped the harness** (all fixed in this release): the ablation containers consumed the host's single-use Codex refresh token (KF-048; nine cells degraded, rerun under a pre-registered addendum); a copy without the refresh-token key logs the codex CLI out (recurrence 2); the batch pre-flight now refuses a token that would expire inside the batch; grader 1.2.10's `--import-mode=importlib` broke sibling imports; 1.2.11's collision cleanup could delete an agent's production module (never happened in a recorded row; 1.2.12/1.2.13 use pytest's own collision rules).

## What ships in rc.6

The ablation harness (`evals/harness/run-ablation.sh`, `pipeline-run.sh`, `ablation-grade.sh` 1.2.13, `ablation-row.sh` 1.2, `ablation-report.py` 1.2.0, `spend.sh`, `took-effect.sh`, `freeze.sh`, `validate-suite.sh`), the frozen suite v2 (`grimoires/loa/evals/ablation-2.0/`, `MANIFEST.sha256` sha256 `ddd200b3…`, 282 files) with its README (suite versions, the regression-check recipe for the next model bump — PRD G-6), the tracked-tree integrity manifest and mount-scoped `check-loa.sh` (#1267, G-3), 430 bats cases under `evals/tests/`. No framework default changes: every component keeps its current posture; the measured lift on review PRs and the saturation on build tasks are recorded for the next cycle's decision rather than acted on by this one.

## Cycle ratio (PRD FR-10 convention, from cycle-129)

`tools/cycle-ratio.sh --from 252501b4 --to <cycle head> --sprint-plan grimoires/loa/sprint.md`: kinds mechanical 28 · judgment 19 · operator 0; volume: script lines changed 34,348 (`*.sh *.py *.ts *.js`) · prose bytes changed 409,797 (`*.md`) · model calls 25 (MODELINV rows on the host between the two commits' timestamps; the container runs are metered in `runs.jsonl`, USD 1,133.40 of runs).

## Toward 2.0.0

rc.6 is the sixth release candidate of the 2.0.0 line (rc.1 model-generation floor, rc.2 friction floor, rc.3 operator decisions, rc.4 decision surfaces, rc.5 earned guards and open voices, rc.6 the component ablation). The promotion to `## [2.0.0]` is the operator's call after the rc soak; the 2.0.0 notes will link each rc's notes file under `grimoires/loa/reports/` and this report. Nothing in rc.6 changes a framework default, so the soak measures stability, not behaviour.

## Release body (as published)

Published 2026-10-18 from the verified candidate (tag `v2.0.0-rc.6` at `4628f763`, the post-merge pipeline's `chore(ledger): archive cycle-130-ablation-2.0 after merge` commit on top of the PR #1283 merge `dfc47772`; pre-release; release id 416489275; candidate sha256 `7dfcb108…` approved and verified in an isolated clone; notification comment 6250934727 on PR #1283). Record branch: `record/cycle-130-a2a` (`d3a1eab2`: the merged tree plus the a2a records of sprints 258–262, the continuation prompts, NOTES and its archive).

## Release v2.0.0-rc.6

- Merge pull request #1283 from 0xHoneyJar/feature/cycle-130-ablation-2.0 — cycle-130 "Loa 2.0 component ablation" (sprints 258–262): the ablation harness, the frozen suite v2, the blind grader 1.2.13, the report, and the findings above. No framework default changes.
