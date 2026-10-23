# Release notes: v2.0.0-rc.7 (pre-release) — the conclusive review-catch answer (cycle-132)

Prepared 2026-10-23 by the cycle-132 lead for the post-merge pipeline, which fills the "Release body" section from the merge and finalises the CHANGELOG heading. The full release note is the CHANGELOG `## [Unreleased]` section at the merge; this file states the measurement's answer and its caveats in plain words. **Nothing shipped by default changes in rc.7** (PRD G-7): the release carries the measurement harness, the bug fixes of the three `/bug` micro-sprints, and the report.

## What was measured (PRD G-1 … G-6)

Fourteen record fixtures the pipeline had never reviewed (real pull requests with their real fix commits), a defect key re-derived by two blind annotators from fix commits and post-merge incidents (pooled hunk-verdict kappa 0.88, lead adjudication), a hashed pre-registration (primary statistic, cluster-by-PR bootstrap, mixed-effects and permutation reads, a three-look group-sequential stopping rule, a placebo that must read zero, a positive control, a binding cap), four arms — bare Opus 5.5, a compute-matched bundle of bare Opus 5.5 sessions, a compute-matched bundle of bare Fable 5.1 sessions, review-only and the full pipeline — plus the open-mount positive control, a blind judge on a stratified sample of grader verdicts, and an independent reproduction from a fresh clone of the record branch.

Report: `grimoires/loa/reports/review-catch-c132/report.md` (reads, rows, power, registration hashes, judge, placebo, spend and the reproduction beside it).

## The findings, plainly

- **Primary (registered):** the full pipeline caught about ten points more of the labelled defects than the same-dollar bundle of bare Opus 5.5 sessions (defect-weighted recall 0.65 against 0.55 on ten valid PRs), with a 95 % cluster-t interval from about −0.09 to +0.29. The pre-registered stopping rule did not fire; the final look reads **INCONCLUSIVE**, and the full arm lost eleven of twenty-eight planned cells to exposure and contamination, so the read is inconclusive by degradation.
- **Per dollar:** the pipeline caught 0.41 labelled defects per USD against 0.29 for the matched bundle, and it caught seventeen more defects while spending less — the matched bundle is dominated.
- **Review alone catches fewer than review plus audit** (−0.12, interval excluding zero). **Against bare Fable 5.1 sessions at the same dollars the pipeline wins by a third of the key** (+0.33, interval excluding zero).
- **Controls:** the positive control passes (open mount above closed mount with oracle exposure in nine open runs); the placebo fails its calibration band on these rows as it did on the 63 pre-existing rows, so the decision rests on the simulation-calibrated boundary and the permutation test (p 0.37), as pre-specified.
- **The structural limitation:** nine PRs modify Loa's own `.claude/` files, and the pinned pipeline reads its own fixed copies while reviewing them; such runs are oracle-exposed and excluded from the primary. Re-including them raises the estimate and moves the interval off zero — the registration refused to make that the primary, and so does the report.
- **The judge:** about one credited citation in five describes the labelled defect, in every arm alike (kappa with the grader 0.20); the mechanical grader stays primary as registered, and the semantic question is open.

## What ships in rc.7

The measurement harness and analysis (`evals/analysis/c132/`, the review-catch suite root `grimoires/loa/evals/ablation-2.0-c132/`, grader 1.3.8, row writer 1.5, the seeder's `--feedback` provenance fields, the blind-session container role, the judge sampler), the three `/bug` fixes (archive-cycle cycle detection and its default deletion of tracked archives; the post-PR Flatline verdict read with stdin transport for the CLI Claude voice; labels files reproducing the curated manifests), and the report. No shipped default, cap, arm, model or skill text changed (the allowlisted diff against `main` is empty — PRD G-7).

## Toward 2.0.0

The rc line keeps soaking. The measurement's answer is "probably a little better per dollar, not proven at this corpus size": the next step the report proposes for the operator's decision is a corpus whose PRs do not touch the framework's own files, so that the structural limitation cannot cost a quarter of the primary arm.

## Release body (as published)

(filled by the post-merge pipeline from the merge commit)
