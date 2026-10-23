# Product Requirements Document: The conclusive review-catch answer (cycle-132)

**Version:** 1.0
**Date:** 2026-10-21
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-21, quoted verbatim in the brief; the interview phases were answered from that instruction, the cycle-131 archive and a direct read of the harness, grader, fixtures and record branches; every operator-level choice is tagged `[ASSUMPTION decision]` with its DEC row)
**Brief:** `grimoires/loa/context/cycle-132-brief.md` (the operator's instruction verbatim; the lead's raw-material map and design proposals)
**Prior measurement this cycle settles:** `grimoires/loa/reports/ablation-2.0/analysis.md` §§1–10 (cycle-130 report, deep analysis, cycle-131 addendum); the 63 run directories on `record/cycle-130-analysis` and `record/cycle-131-honest-measurement`
**Cycle:** `cycle-132-conclusive-review-catch` (ledger, active); **branch:** `feature/cycle-132-conclusive-review-catch` from `main 16e0b48b` (the /bug micro-sprints sprint-bug-266/267/268 precede it on `fix/cycle-132-bugs`)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

> Sources: discovering-requirements/resources/templates/prd-template.md:10-24 (section order)

---

## Executive Summary

Two cycles measured whether Loa's review pipeline catches more planted defects than one bare model session. Cycle-130 read +0.263 on four PRs; the deep analysis found half of it in the grader's ruler and part in an answer-key leak; cycle-131 closed the leak, kept the ruler, ran a bare-Fable control and priced the audit gate and the dissent on two PRs, with intervals too wide to act on. The question the maintainer actually has is sharper and still open: **does the review pipeline catch more real defects per dollar than a bare model given the same dollars, on PRs it has not seen?**

This cycle answers it the way a consortium of staff engineers would accept. Phase 0 spends no model money: it goes back to the raw material (the 63 run directories, the fixtures and their fix commits, the review feedback behind every label, the dissent envelopes, the cost ledgers and the post-merge issue history), re-derives the ground truth per defect from fix commits and incidents with two blind annotators (kappa reported, adjudicated, label source stored; the old labels frozen as a sensitivity set), sizes the study by simulation (the number of PRs for a ten-point minimum detectable effect, fixtures dated after the models' availability, contamination exposure recorded), writes and hashes a pre-registration (primary statistic, cluster-by-PR bootstrap, mixed-effects model, permutation test, a group-sequential stopping rule with yes/no/futile boundaries, the sensitivity list, a placebo that must read zero, the budget cap with the spend-based halt), runs the analysis on shuffled-arm placebo data first and commits that output, and puts the plan itself through a dissent review. Phase 1 runs four arms on the unseen corpus — bare, bare compute-matched (the same dollars as the full pipeline, union of findings), review-only and full — with the open mount as the positive control and grader 1.3.1 as the mechanical primary validated against a blind judge. Phase 2 takes only the pre-registered reads, then the sensitivities, and states whether the stopping rule fired. Phase 3 proves the result: an independent reproduction from a fresh clone of the record branch (byte-identical grades, rows and reads; a sampled live rerun), the placebo and positive-control results, the judge agreement and both dissent records; then the normal review, audit, Bridgebuilder, merge, record branch and archive. Nothing shipped by default changes; v2.0.0-rc.7 is held until the reads land, and the changelog says so.

> Sources: cycle-132-brief.md § The operator's instruction, § Objective; analysis.md § ELI5, §10 ELI5, §10.7, §10.8; c131-reads.md § Main read

---

## Problem Statement

### The Problem

Loa justifies a review pipeline that costs ten to twenty times a bare model call with catch-rate numbers measured on four to six PRs, two of them read twice, against labels that came from the pipeline's own review feedback, with 90 % intervals that straddle every actionable threshold. The maintainer cannot tell a downstream team whether the pipeline is worth its dollars, and the per-dollar question — the one a consortium would ask — has never been posed: the bare arm always ran once, at a fifteenth of the pipeline's cost.

### User Pain Points

- The cycle-131 reads are honest and inconclusive: "R1 insufficient / investigate (Δ +0.067 [−0.017, +0.150])", "R3 insufficient / inconclusive", "R4 insufficient (2 valid cells)" (`c131-reads.md`); only R5 (the model does not explain the lift) is a finding. A maintainer who reads §10.8 learns what to run next, not what to do.
- Every label in `evals/fixtures/review-prs/labels/pr-11 … 18.tsv` has `label_source: review | audit | bridgebuilder` — the pipeline's own findings. Recall against them is recall against what the pipeline found at the time; a bare arm cannot be credited for a real defect the pipeline missed.
- The 63 run directories exist (36 cycle-130 + 27 cycle-131) but the figures everyone quotes come from `rows.jsonl` and report tables; nobody has re-derived them from the transcripts, envelopes and cost ledgers in one pass under one rule.
- The bare arm has only ever run once per trial (USD 1–5) against a pipeline run (USD 11–24). "Catch per dollar" was reported as a frontier figure (analysis.md §4), never tested.
- Decisions were pre-registered per batch in NOTES but the analysis code was never run on placebo data first, never carried a mixed-effects or permutation read, and had no stopping rule — a reader cannot tell a null from an underpowered design (DEC-0650 is exactly that confusion).
- The pipeline has never been evaluated on a PR it had not already been tuned against: pr-05/08 are synthetic plants, pr-12/13/17/18 were read in cycle-130 and again in cycle-131.

### Current State

- Harness: `evals/harness/pipeline-run.sh` runs one task under one arm (review-catch: REVIEW → AUDIT, or one BARE session when `loa_mount: false`); `run-ablation.sh` plans arm × task × trial, grades (`ablation-grade.sh` + `recall-vs-defects.sh` 1.3.1, rule `pm3_or_same_function`, decision statistic `recall_pm3` per DEC-0638), rows (`ablation-row.sh` 1.4), reports (`ablation-report.py` 1.3). The closed mount (`lib/sandbox-mount.sh overlay_answer_paths`, took-effect `oracle_closed`) is live; the open mount survives as `a1_full_openmount` (eval-only). Arms declared: `a0_bare`, `a0_bare_fable`, `a1_full`, `a1_review_only`, `a1_no_dissent`, `a1_full_openmount`, the build-task arms.
- Corpus: 8 record fixtures (pr-11 … pr-18; `record-pairs.tsv` sprints 247–254) seeded by `seed-corpus-from-record.sh` from the round-1 review and audit feedback on record branches; curated multi-site anchors in `manifests/pr-NN.json` (cycle-131 Task 1.5, DEC-0626), originals in `manifests/v1/`. Unseen: pr-11 (5 defects, head 2026-09-25), pr-14 (2), pr-15 (3), pr-16 (4; one smoke run). Never seeded: sprints 255–265 (feedback files and fix commits on `record/cycle-129-a2a`, `record/cycle-130-a2a`, `record/cycle-131-honest-measurement`; heads 2026-10-14 … 10-20).
- Reads: `reads-c131.py` (seed 20261015; defect-level paired bootstrap, 10,000 resamples, 90 %; cluster bootstrap by PR descriptive only); no mixed-effects, permutation, placebo or stopping-rule code exists.
- Infrastructure: Docker image `loa-ablation:258` (Claude Code 2.1.299 inside), codex credential valid to 2026-10-28T04:44Z, Bedrock bearer key set; per-run cap USD 30 and task bounds REVIEW 50 / AUDIT 40 min on the large PRs (DEC-0640, DEC-0645).
- Spend history: cycle-130 ≈ USD 1,281 of 1,500; cycle-131 ≈ USD 443 of 500; `a1_full` ≈ USD 17–24 per run on 2–4 k-line diffs with the diff-scaled dissent, `a0_bare` ≈ USD 1.0–1.8, `a1_review_only` ≈ 11, `a1_full_openmount` ≈ 19.

### Desired State

One tracked report answers the question with: recall at matched spend with a 95 % cluster-by-PR interval, a mixed-effects estimate and a permutation p, precision and cost per extra defect with intervals, the cost-matched comparison, the stopping-rule outcome, the placebo (zero) and positive-control (positive) results, the grader–judge agreement, the annotator kappa, and a reproduction report from a fresh clone that matched every grade, row and read byte for byte — all under a pre-registration whose hash sits in the batch manifest and whose dissent review precedes the first row.

> Sources: c131-reads.md § Main read, § Row inventory; analysis.md §§1, 4, 8, 10.3-10.8; evals/fixtures/review-prs/record-pairs.tsv; labels/pr-17.tsv header; evals/suites/ablation-2.0.yaml arms; ~/.cache/loa/cycle-131/scripts/reads-c131.py; NOTES 2026-10-20T04:02:26Z (DEC-0648), DEC-0650; spend.sh; known-failures.md KF-048, KF-049, KF-051

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Ground truth re-derived per defect from fix commits and incidents | every corpus fixture has a v2 manifest whose defects carry `label_source ∈ {fix-commit, incident}`, two annotator ids and an adjudication record; Cohen's kappa on the hunk-level defect/not decision is reported per fixture and pooled; the cycle-131 curated manifests and the v1 originals are frozen, unchanged, as sensitivity sets | `manifests/pr-NN.json` schema check; `a2a/sprint-1/annotation/result.md`; `git diff --stat` of the frozen sets empty |
| G-2 | A powered design | the power simulation names N (PRs) for MDE 0.10, α 0.05 two-sided, power ≥ 0.80 under the cluster-by-PR test, from the 63 existing runs; every selected fixture records `post_cutoff` and a contamination note | `a2a/sprint-1/power/power.md` + `power.json`; fixture.yaml fields |
| G-3 | A hashed pre-registration, placebo first, dissent before any run | `PREREGISTRATION.md` sha256 recorded in the batch MANIFEST and NOTES before the first Phase 1 row; the analysis code's placebo run on the 63 existing runs committed before any Phase 1 spend and reading Δ within the pre-registered zero band; the Flatline dissent record of the pre-registration dated before the first row | MANIFEST.json `preregistration_sha256`; `a2a/sprint-1/placebo-existing.md`; `a2a/sprint-1/flatline-prereg.json` |
| G-4 | The arms run on the unseen corpus | per selected PR: `a1_full` × 2, `a0_bare_matched` × 2 (k sessions each; BARE-1 is single bare), `a1_review_only` × 2; `a1_full_openmount` × 2 on the first PR group; every row passes its took-effect rules; grader 1.3.1 primary; judge agreement reported on the stratified sample | batch rows `c132-rows.jsonl`; `a2a/sprint-2/judge/result.md` |
| G-5 | Only the pre-registered reads, then sensitivities; the stopping rule stated | the report carries recall, precision, cost per extra defect and the cost-matched comparison, each with intervals (95 % cluster-by-PR bootstrap; 90 % beside), the mixed-effects estimate, the permutation p, the look-by-look boundary table and a sentence saying whether a boundary fired and why | `reports/review-catch-c132/report.md` §§ Reads, § Stopping rule; DEC rows per read |
| G-6 | Proof | an Opus 5.5 subagent reproduces every grade.json, row and read byte for byte from a fresh clone of the record branch into an empty directory, reruns a pre-registered sample of trials live and reports hashes; the placebo on the new rows reads zero; the positive control reads positive; judge agreement and both dissent records are in the report | `a2a/sprint-3/reproduction/report.md`; `report.md` §§ Placebo, Positive control, Judge, Dissent |
| G-7 | Nothing shipped by default changes; rc.7 held | the allowlisted diff vs `main` of `.loa.config.yaml`, skill frontmatter and the shipped suite arms is empty; CHANGELOG `[Unreleased]` carries the rc.7 hold line until the reads, then the ship step cuts `[2.0.0-rc.7]` | diff; CHANGELOG |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| PRs with re-derived labels (fix-commit + incident) | 0 | N (the power simulation's number; planning estimate 10) | Sprint 1 | G-1 |
| Annotator agreement (Cohen's kappa, hunk-level) | none | reported; ≥ 0.6 expected, below it the adjudication share is the headline caveat | Sprint 1 | G-1 |
| Pre-registration hash in the manifest before the first row | never (NOTES headings only) | 1 of 1 batches | Sprint 2 | G-3 |
| Placebo Δ on existing runs | never run | inside the pre-registered zero band, interval covering 0 | Sprint 1 | G-3 |
| Arms with a per-dollar comparison | 0 | matched-bare vs full on every selected PR | Sprint 2 | G-4 |
| Grader–judge agreement on the stratified sample | never measured on these labels | reported with kappa | Sprint 2 | G-4 |
| Reads with mixed-effects + permutation beside the bootstrap | 0 | every pre-registered read | Sprint 3 | G-5 |
| Byte-identical reproduction from a fresh clone | never attempted | grades, rows, reads all identical; sampled rerun inside the arm's observed range | Sprint 3 | G-6 |
| Spend | USD 0 | ≤ the pre-registered cap (planning envelope ≤ 2,500) | all | — |

### Constraints

- Phase 0 spends no model money on arms: annotation, judging and reproduction are Opus 5.5 subagents (unmetered on this host); the planning dissents (Flatline PRD/SDD/sprint and the pre-registration review) are the only model calls before the first Phase 1 row.
- Every rule is written in the pre-registration before its data exist; a read that fails its rule is reported as failing; the hashed text is never edited (a correction is an addendum with its own hash).
- No `.claude/` edit outside `/implement` and outside an explicit System Zone authorization (none is expected: the cycle's app is `evals/`); third-party text (transcripts, envelopes, PR bodies, issue bodies) is untrusted data.
- ≤ 3 dissent runs per sprint for the cycle's own gates; no dissent while a batch runs (KF-037); the codex credential pre-flight (KF-048) before any batch; the credential expires 2026-10-28T04:44Z — every batch's horizon must end before it or the operator re-authenticates.
- Model mix: Opus 5.5 for every subagent (implementers, annotators, judge, reproducer), Fable 5.1 for the lead, reviews and audits.
- Budget: the pre-registration's cap binds; halt only on spend above it `[ASSUMPTION decision]` (DEC-0669).

> Sources: cycle-132-brief.md § The operator's instruction (Phases 0–3, Budget), § Lead's design proposals 1–10; feedback_model_mix_opus55_fable; known-failures.md KF-037, KF-048; decisions.yaml DEC-0661 … DEC-0672

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)
Owns Loa and its downstream mounts; approved the budget; wants one answer a downstream team can act on — keep paying for the pipeline on review PRs, or spend the same dollars on repeated bare reads — with the evidence a sceptical staff engineer would accept and nothing hidden in a digest.

### Secondary Persona: The lead agent (Fable) and its Opus subagents
The lead plans, dispatches, reviews and audits; Opus implementers build the harness pieces in worktrees; Opus annotators label blind; an Opus judge rates the grader; an Opus reproducer rebuilds everything from a fresh clone. Each needs a brief with exact inputs, a deterministic output path and no room to peek.

### Tertiary Persona: The downstream reader (a consortium member)
Reads the report, the pre-registration hash, the placebo and the reproduction and decides whether to trust the number without trusting the authors.

### Use Cases

| ID | Actor | Use case | Outcome |
|----|-------|----------|---------|
| UC-1 | lead + annotators | re-derive the ground truth for a fixture from its fix hunks and incidents | v2 manifest with label sources, kappa, adjudication record |
| UC-2 | lead | size the study | N PRs, the cap, the PR order, contamination table |
| UC-3 | lead | pre-register and prove the analysis code on placebo data | hashed `PREREGISTRATION.md`, committed placebo output, dissent record |
| UC-4 | harness | run a compute-matched bare arm | k BARE sessions in one run, one graded union, one row |
| UC-5 | lead + judge | validate the grader | agreement and kappa on the stratified sample; judge-corrected sensitivities |
| UC-6 | lead | take the reads at each look | boundary table; YES / NO / FUTILE / continue; the final report |
| UC-7 | reproducer | reproduce from a fresh clone | hash table: grades, rows, reads identical; sampled rerun compared |
| UC-8 | maintainer | ship | review, audit, Bridgebuilder, merge, record branch, archive (with the fixed archive script); rc.7 cut after the reads |

> Sources: cycle-132-brief.md § Objective, § Sprint breakdown; cycle-131 prd.md § User Personas (pattern)

---

## Functional Requirements

### FR-1: Corpus — unseen fixtures with provenance (Phase 0)
**Priority:** Must Have
**Description:** Seed review-catch fixtures from the record branches for sprints 255 … 265 (`seed-corpus-from-record.sh` with new `record-pairs.tsv` rows: base = parent of the sprint's first implementation commit, head = the tree the round-1 review read, fix = the commit that closed the feedback; feedback files from the record branch — for 263–265 the files live under `a2a/sprint-1 … 3/`, so the seeder takes an explicit feedback path list). Keep the already-seeded unseen fixtures pr-14, pr-15, pr-16 and pr-11 (flagged borderline: head 2026-09-25, before Opus 5.5's catalog date 2026-10-05). Every fixture records in `fixture.yaml` an `exposure` block — `fable_5_1: post-cutoff` (knowledge cutoff June 2026) or `pre-cutoff`; `opus_5_5: unverified` (the vendor cutoff is not published; the catalog date 2026-10-05 is only an upper bound, so availability is **not** claimed as cutoff evidence); `retrieval: public-repository` (the fix commits sit on `main`; the sandbox has network, so retrieval exposure is controlled by the egress contamination class of FR-5, not assumed away) — and a `contamination_note`. The selected set and its seeded order come from the power simulation (FR-6) and are written in the pre-registration. `[ASSUMPTION decision]` (DEC-0668).
**Acceptance Criteria:**
- [ ] `record-pairs.tsv` carries one validated row per new sprint (commits resolve on the record branch; `--dry-run` passes) and the seeder accepts `--feedback` paths outside `a2a/sprint-<N>/` for the cycle-131 sprints.
- [ ] Each new fixture has `fixture.yaml`, `head.diff`, `PR.md`, `REVIEW-INSTRUCTIONS.md`, `AUDIT-INSTRUCTIONS.md`, `base/`, `head/`; its seeded labels (`label_source: review|audit|bridgebuilder`) are kept as the review-derived set, approved `pending` until FR-2 replaces the primary key.
- [ ] `fixture.yaml` of every corpus fixture (old and new) carries `post_cutoff` and `contamination_note`; a bats case checks the fields parse.
- [ ] `SHA256SUMS` refrozen; `seed-corpus-from-record.sh --check` passes; `evals/tests/` green.

### FR-2: Ground truth re-derived by two blind annotators (Phase 0)
**Priority:** Must Have
**Description:** For every selected fixture, generate deterministically (a harness script, no model) an **annotation packet**: the fix hunks of `head..fix` restricted to fixture files (each hunk with 12 lines of head-side context, the head-side line numbers, the hunk id), and an **incident packet**: post-merge issues whose body cites a fixture file, Bridgebuilder rounds on the sprint's PR, KF entries citing the files, and later `fix(...)` commits on `main` touching the head-changed files from the fix commit to the scan date (recorded; with their diffs). Neither packet contains any review or audit feedback, any arm output, or the old labels. **The construct, stated in the report:** the ground truth is the set of defects later *confirmed* by a fix or an incident — a lower bound on the real defects at head, because fix hunks answer the pipeline's own round-1 findings and incidents only capture what someone later noticed; recall is recall against confirmed defects. The one channel independent of both is the blind judge (FR-4): stray findings from any arm that the judge rates `real` enter a labelled sensitivity read in which they count as defects for every arm (post hoc, never primary) `[ASSUMPTION decision]` (D14). Two Opus 5.5 annotators, each with the same codebook, independently label every fix hunk `defect` (a behaviour the head code gets wrong: file, head-side anchor lines, one-sentence description, severity critical/high/medium/low, category) or `not-defect` (test, docs, refactor, style, follow-on to another hunk → the defect id it belongs to), and label every incident `defect-at-head` or `not-at-head`. The lead computes Cohen's kappa on the hunk-level defect/not decision (and on severity among agreed defects), adjudicates every disagreement with a written reason, merges same-defect hunks, and builds `manifests/pr-NN.json` v2: `defects[]` with `id`, `file`, `anchor_line`, `anchors[]`, `must_match` (a unique head line, else `@L<n>` via the sprint-bug-268 grammar), `severity`, `category`, `label_source: fix-commit | incident`, `annotators: [a, b]`, `agreement: agreed | adjudicated`, `adjudication_reason`; `fix_regions` as today. The cycle-131 curated manifests move to `manifests/c131/` and `manifests/v1/` stays; both frozen (byte-identical to `main`). `[ASSUMPTION decision]` (DEC-0664).
**Acceptance Criteria:**
- [ ] `evals/harness/annotation-packets.sh <fixture>` writes `packets/<fixture>/{hunks.md, incidents.md, codebook.md}` deterministically (a bats case pins the output on a synthetic fixture); the packets contain no string from the fixture's labels or feedback files (a bats case greps).
- [ ] `a2a/sprint-1/annotation/` holds both annotators' label files per fixture, `kappa.json` (per fixture and pooled, with the 2×2 tables), `adjudication.md` (every disagreement, the decision, the reason), and `result.md`.
- [ ] `manifests/pr-NN.json` v2 validates against `evals/harness/schemas/review-manifest.schema.json` (new; `label_source` enum, `annotators`, `agreement`); `--build-manifest` reproduces each v2 manifest byte for byte from `labels/pr-NN.tsv` (sprint-bug-268 rule); the frozen sets are untouched.
- [ ] `recall-vs-defects.sh` and `ablation-grade.sh` read v2 manifests unchanged (the key fields are a superset); grade.json gains `label_set: v2 | c131 | v1` from the task's `review_catch.manifest`.

### FR-3: The compute-matched bare arm (Phase 0 build, Phase 1 run)
**Priority:** Must Have
**Description:** Arm `a0_bare_matched` (`toggles: {loa_mount: false, bare_sessions: matched}`): `pipeline-run.sh` runs k independent BARE sessions (`BARE-1 … BARE-k`, the bare prompt and output contract of `a0_bare`, Opus 5.5 `--effort high`, each a fresh `claude -p` session with its own transcript, cost and stderr), where k comes from the suite-root task's `review_catch.bare_sessions_matched` — an integer the pre-registration fixes per PR **from the existing 63 runs before any Phase 1 spend**: `k_p = round(ĉ_full(L_p) / ĉ_bare(L_p))`, with `ĉ_arm(L)` a least-squares fit of per-run cost on diff lines over the cycle-130/131 rows and `L_p` the fixture's diff lines; floor 2, cap 30 (D18). The Phase 1 smoke reports the realized ratio per PR and never changes k; the realized spend ratio of every matched pair is reported, and the exact-dollar trim (FR-5) is the sensitivity for imbalance. **Models, stated:** `a1_full` and `a1_review_only` run the shipped gates — Fable 5.1 review and audit with the codex dissent — and `a0_bare_matched` runs Opus 5.5 at `--effort high` (the stronger bare model: cycle-131 R5 read bare-Fable 0.226 below bare-Opus 0.393), so the primary compares the shipped pipeline with the best bare option at equal dollars and the model confound works against the pipeline; a secondary arm `a0_bare_fable_matched` (k Fable 5.1 sessions at the same dollars, its own k from the Fable cost fit) gives the same-model comparison on every PR (D13). The grader concatenates the k outputs (session headers between them) into `grading/gates-combined.md` and grades the union under its existing `cited_region` dedupe; `grade.json` gains `bare_sessions: k` and per-session detected sets; `ablation-row.sh` writes `bare_sessions`, `phases[]` (k BARE entries with cost) and the summed `cost_usd`; took-effect rule `bare_sessions_matched` (exactly k BARE phases, no mount, all completed). The first session is the single-bare read: the grader also writes `recall_session1` (and precision) from BARE-1 alone. `[ASSUMPTION decision]` (DEC-0663).
**Acceptance Criteria:**
- [ ] `pipeline-run.sh --dry-run` on the arm prints k BARE phases; a stub-CLI bats case runs k = 3 and checks three transcripts, three `phases.jsonl` records, summed cost.
- [ ] `ablation-grade.sh` on a synthetic k = 3 run: the union credits a defect cited by any session once; a stray region cited by two sessions counts once; `recall_session1` equals the first session's own recall.
- [ ] `took-effect.sh bare_sessions_matched` passes on k phases, fails on k − 1 or on a mount; `ablation-row.sh --validate` accepts the row; `ablation-report.py` partitions `a0_bare_matched` by k.
- [ ] `validate-suite.sh` accepts the toggle and the task field; `evals/tests/` green with the new cases.

### FR-4: Grader validation by a blind judge (Phase 1)
**Priority:** Must Have
**Description:** After the batches, a harness script draws a stratified sample of grader decisions: for every (arm, PR) cell stratum, credited (finding, defect) pairs, non-credited near-misses (a citation within 20 lines of a labelled site), and far misses; plus stray findings (citations outside every window). The candidate universe is enumerated first and recorded: every (citation region, nearest labelled defect in the same file) pair, every labelled defect with no citation within 20 lines, and every stray region. Sample size: the smaller of all items or 10 per stratum, at least 150 items in total, seeded; the inclusion probability of each stratum (n_s / N_s) is recorded and every agreement estimate is inverse-probability weighted back to the universe (unweighted figures beside). `partially` counts as disagreement in the strict figure and as agreement in the lenient figure; both are reported. Packets are blind to arm, trial and grader decision and quote the finding text, the cited lines and the labelled defect's description and anchors. One Opus 5.5 judge rates each pair `describes | partially | does-not-describe` and each stray `real | style | wrong | not-a-finding` (the cycle-130 codebook). The lead reports agreement and Cohen's kappa (grader credit vs judge `describes`), the confusion table per stratum, and the judge-corrected recall and precision as sensitivities. `[ASSUMPTION decision]` (DEC-0667).
**Acceptance Criteria:**
- [ ] `evals/harness/judge-sample.sh <rows> <run dirs>` writes `judge/packets/*.md` and `judge/key.json` (outside the packets) deterministically from a seed; a bats case pins the strata counts on synthetic grades.
- [ ] `a2a/sprint-2/judge/result.md` reports n per stratum, agreement, kappa with its 95 % interval, the confusion table, and the corrected recall/precision per arm.
- [ ] The grader stays the primary in every read; the judge-corrected figures appear only under "Sensitivities".

### FR-5: Analysis code with placebo, mixed-effects, permutation and the stopping rule (Phase 0)
**Priority:** Must Have
**Description:** A stdlib Python module `evals/analysis/c132/` with a CLI `reads-c132.py` that reads rows + grade.json files and writes `reads.md` + `reads.json`: (a) the primary statistic Δ = recall(a1_full) − recall(a0_bare_matched) at matched spend — **estimand and pairing, fixed:** the unit is the PR × trial pair (both arms' cells of the same PR and trial index); Δ pools defects over all valid pairs (Σ caught / Σ defects per arm, each pair contributing its own caught counts), the PR-weighted mean of per-pair Δ is reported beside; a paired bootstrap resamples PRs with replacement (all their pairs travel together; 10,000; seed in the pre-registration; 95 % percentile interval, 90 % beside) and the defect-level paired bootstrap of cycle-130/131 is a descriptive comparison; (b) a linear mixed-effects model on cell recall with a PR random intercept fitted by REML (Newton on the one variance ratio; Wald 95 % interval on the arm effect) — the defect-level logistic GLMM is out of scope for stdlib and is named as the limitation; (c) a permutation test that swaps the two arms' cells within each PR × trial pair (10,000 permutations, two-sided p); (d) secondary reads: recall and precision per arm with intervals, cost per extra defect (full vs single bare BARE-1; full vs matched), the exact-dollar trim (the largest m ≤ k sessions whose summed cost ≤ the paired full run's cost), review-only vs full; (e) the group-sequential rule: three looks after the PR groups; the information fraction at look k is the estimated information ratio `t_k = SE²_planned-final / SE²_k` (the planned final SE from the power simulation), not the PR count; Lan–DeMets O'Brien–Fleming α-spending (two-sided 0.05) gives the YES boundary on `z_yes = Δ̂/SE` and a one-sided 0.025 spending gives the NO boundary on `z_no = (MDE − Δ̂)/SE`; **the outcomes partition** (D16): YES when z_yes crosses and the interval is not entirely below the MDE; NO when z_no crosses and z_yes has not; SMALL when both cross (a real but sub-actionable lift); FUTILE when the conditional power of reaching YES and of reaching NO at the final look are both below 0.20 (non-binding); otherwise CONTINUE; **the boundaries are simulation-calibrated**: the power simulation (FR-6) runs this complete procedure under Δ = 0 and inflates the boundary constant until the empirical type-I error is ≤ 0.05, and the calibrated constants are what the pre-registration hashes; the final report prints the naive interval and the repeated confidence interval at the stopping look (`Δ̂ ± b_k·SE`); the look table carries t, boundaries, z, conditional power and the decision; (f) the placebo is a distribution (D17): 200 seeded within-PR arm-label shuffles, each through the primary read; pass when at most 8 % of the shuffles' 95 % intervals exclude 0 and the mean |Δ| is below 0.03 — run on the 63 existing rows in Phase 0 and committed, run again on the new rows before the real read; (g) validity: a cell is valid when `status = completed`, every took-effect rule true, `contaminated` null (including the new **network-egress class**: any Bash `git fetch|clone|pull|ls-remote`, `gh api|pr|issue|repo`, `curl|wget|python urllib|requests` reaching `github.com`, `raw.githubusercontent.com` or `api.github.com`, and any WebFetch/WebSearch input naming the repository — bd-eriso — D15), `oracle_exposed_defects` empty (except the open-mount arm), no `refusal_fallbacks` (KF-051) — excluded cells reported; pairwise exclusion; the 25 % guard marks the read inconclusive-by-degradation; **no replacement trials** (an excluded cell stays excluded); (h) cost reads are given twice: on the valid pairs and on **all spend** (every dollar of every attempt per arm, failed and excluded runs included), and the all-spend figure is the headline cost per extra defect. `[ASSUMPTION decision]` (DEC-0662, DEC-0665).
**Acceptance Criteria:**
- [ ] Unit tests (`evals/tests/analysis-c132.bats` or `python3 -m unittest` under `evals/analysis/c132/tests/`) cover: bootstrap reproducibility by seed; REML on a textbook two-group example within 1e-6 of the known answer; permutation p on a constructed case; OBF boundaries at (1/3, 2/3, 1) equal to the published values within 0.01 (two-sided 0.05: 3.71, 2.51, 1.99); placebo on shuffled synthetic data covers 0; the validity filter.
- [ ] `reads-c132.py --placebo --rows <63 existing rows>` output committed as `a2a/sprint-1/placebo-existing.md` + `.json` before any Phase 1 row; Δ inside the band.
- [ ] `reads-c132.py --look <n>` writes the boundary table and the decision; `--final` writes every pre-registered read, then the sensitivities, byte-identical across two runs.

### FR-6: Power simulation and the number of PRs (Phase 0)
**Priority:** Must Have
**Description:** From the 63 existing runs (grade.json per-defect detected sets of `a0_bare` and `a1_full` on pr-05, 08, 12, 13, 17, 18 at pin-appropriate labels), estimate per-defect catch probabilities for bare and full; model the matched arm as k bare draws — independent (P = 1 − (1 − p)^k) as the main model and, as a sensitivity, correlated within defect (a latent-variable model with intra-defect correlation ρ ∈ {0.3, 0.6}: sessions tend to miss the same defects) — with k from the cost fit of FR-3; estimate between-PR variance of Δ; simulate 2,000 studies per N ∈ {6, 8, 10, 12} PRs (bounded by the 15 candidate fixtures) × 2 trials under **the complete pre-registered procedure** (three looks, the YES/NO/SMALL/FUTILE partition, the cluster-by-PR bootstrap SE) with a true effect of exactly the MDE (0.10) and of 0; report power (share reaching YES) and the empirical type-I error (share reaching YES under Δ = 0) per N, calibrate the boundary constant so the latter is ≤ 0.05, and choose the smallest N with power ≥ 0.80; report sensitivity to the between-PR SD (×0.5, ×1.5), to k (±3) and to ρ. Price the cap: N × (full 2 × 22 + matched-Opus 2 × 22 + matched-Fable 2 × 22 + review-only 2 × 12 + smoke 24) + open-mount 2 × 20 × |G1| + judge/reproduction reruns 80 + dissents 60, × 1.25 contingency, rounded up to USD 50. **Affordable-N rule, deterministic:** if the chosen N's cap exceeds the planning envelope (USD 2,500), N becomes the largest value in the grid whose cap fits, and the pre-registration states the power achieved at that N. `[ASSUMPTION decision]` (DEC-0662, DEC-0669).
**Acceptance Criteria:**
- [ ] `evals/analysis/c132/power.py` is deterministic by seed and writes `a2a/sprint-1/power/power.md` + `power.json` with the per-N table, the chosen N, the cap and the sensitivity tables.
- [ ] The candidate-fixture table (date, defects, post-cutoff flag, contamination note, seeded order) is in `power.md`; the selection fills N from post-cutoff fixtures first, pr-11 last and flagged.
- [ ] A bats/unittest case reproduces the chosen N from a frozen copy of the inputs.

### FR-7: The hashed pre-registration and its dissent review (Phase 0)
**Priority:** Must Have
**Description:** `grimoires/loa/evals/ablation-2.0-c132/PREREGISTRATION.md` (tracked) states: the question; the corpus (fixtures, order, groups G1–G3); arms and k per PR; the primary statistic, intervals and tests (FR-5 a–c); the secondary reads; the stopping rule and its boundaries; the validity and exclusion rules; the placebo band; the positive-control requirement (FR-8); the judge protocol; the sensitivity list (frozen c131 labels, v1 labels, judge-corrected, exact-dollar trim, 90 % interval, leave-one-PR-out, pr-11 in/out, degraded/contaminated excluded); the budget cap and the spend-based halt; the seed. Its sha256 is written to NOTES (dated heading) and passed to `run-ablation.sh --pre-registration-file` (new flag; the runner records `preregistration_sha256` in MANIFEST.json and refuses a `--resume` whose file hash differs). Before any Phase 1 row, a Flatline dissent review of the pre-registration (`flatline-orchestrator.sh --doc PREREGISTRATION.md --phase spec --autonomous`) is run and recorded; blockers are integrated into the text before hashing (the hash is of the final text). `[ASSUMPTION decision]` (DEC-0665).
**Acceptance Criteria:**
- [ ] `run-ablation.sh --pre-registration-file F` records `preregistration_sha256` and `preregistration_path` in MANIFEST.json; `--resume` with a changed file exits 2 (bats).
- [ ] NOTES carries the heading `### Pre-registration — cycle-132 … — <ts>` with the hash before the first Phase 1 row; `a2a/sprint-1/flatline-prereg.json` + the integration note precede it.
- [ ] The hashed text is never edited afterwards; a correction is `PREREGISTRATION-addendum-N.md` with its own hash in NOTES.

### FR-8: Phase 1 batches with interim looks (Sprint 2)
**Priority:** Must Have
**Description:** Pin = the Sprint 2 start commit (DEC-0672). Smoke first (one `a1_full` and one single BARE per selected PR under the closed mount; `oracle_closed` must hold on every PR; the realized cost ratio recorded beside the pre-registered k, which it never changes). Then the batches in the pre-registered PR groups: for every PR `a1_full` × 2, `a0_bare_matched` × 2, `a0_bare_fable_matched` × 2 (secondary, D13), `a1_review_only` × 2; on G1 only `a1_full_openmount` × 2 (positive control, DEC-0666: pass when the point estimate of open − closed on G1's pairs is above 0 **and** the oracle detector shows exposure in at least one open run — the mechanism — with the 90 % interval reported; no exposure in any open run reads "control not exercised", not "failed"). After each group the lead runs `reads-c132.py --look n`; YES, NO or SMALL at a boundary stops the batches (the remaining groups are not run; the report says so); FUTILE stops them too and is reported as such. **The cap is enforced before launch:** the runner's `--max-usd` reservation rule (spent + in-flight reservations + the next unit's estimate must stay under the cap) governs every unit, so the worst overshoot is bounded by concurrency × the per-unit cap (3 × 30 = USD 90) and is stated in the pre-registration; a group that the cap cuts ends partial and is reported as such (there is no "never cut within a started group" exception). Concurrency 3, `--run-cap 30`, bounds REVIEW 50 / AUDIT 40 min, `--allow-partial`, eval config variant (`budget_scale: diff`, max 600 c), codex pre-flight before every batch, no dissent of any gate during a batch. Spend is posted to NOTES after every batch. The judge sample (FR-4) is drawn after the last batch.
**Acceptance Criteria:**
- [ ] `grimoires/loa/evals/ablation-2.0-c132/` suite root: one review-catch task per selected PR with bounds, `review_catch.bare_sessions_matched`, `review_catch.manifest` (v2), frozen `MANIFEST.sha256`, image self-check log.
- [ ] Smoke rows decide nothing; the k table and the `oracle_closed` evidence per PR are in NOTES before the first batch row.
- [ ] Batch rows land in `evals/results/ablation-2.0/c132-g1 … g3/` and the tracked `grimoires/loa/reports/review-catch-c132/rows.jsonl`; every row at the pin; refusal fallbacks and contaminations reported per row.
- [ ] The look reads and the boundary decisions are in NOTES with timestamps; the batches stop at a fired boundary or at the cap.

### FR-9: Reads and the report (Phase 2, Sprint 3)
**Priority:** Must Have
**Description:** `reads-c132.py --final` writes the pre-registered reads first (primary Δ with the 95 % cluster-by-PR interval, the REML estimate and Wald interval, the permutation p; recall, precision, cost per extra defect, the cost-matched comparison and the exact-dollar trim, each with intervals; the look table and the plain statement of whether a boundary fired and why), then the sensitivities in the pre-registered order. The report `grimoires/loa/reports/review-catch-c132/report.md` opens with an ELI5 (≤ 300 words), states the answer in one sentence with its interval, and carries the placebo (existing and new rows), the positive control, the annotator kappa, the judge agreement, the spend table, the honest caveats, and pointers to the dissent records. `analysis.md` gains a short §11 pointer. Each read is a DEC row. `[ASSUMPTION decision]` (DEC-0671).
**Acceptance Criteria:**
- [ ] `reports/review-catch-c132/{report.md, reads.md, reads.json, rows.jsonl, power.md, PREREGISTRATION-sha256.txt}` tracked; `reads.md` byte-identical across two runs of the script.
- [ ] Every figure in `report.md` is reproduced by `reads-c132.py` (no hand-typed numbers; a bats case diffs the report's tables against `reads.md`).
- [ ] DEC rows for the primary read, each secondary read, the stopping-rule outcome and the placebo/positive-control verdicts.

### FR-10: Proof — reproduction, controls, dissent records (Phase 3, Sprint 3)
**Priority:** Must Have
**Description:** An Opus 5.5 reproducer, from a fresh `git clone` of the record branch into an empty directory (no access to the lead's working tree), follows `reports/review-catch-c132/REPRODUCE.md`: re-run `ablation-grade.sh` over every recorded run directory (grade.json byte-identical to the recorded one, `--allow-partial`, container executor), `ablation-row.sh` over every grade (rows byte-identical), `reads-c132.py --final` (reads.md byte-identical), and the placebo; then rerun live a pre-registered sample of 3 cells (one per arm family, seeded; ≈ USD 60) and report their grades against the arm's recorded range; write `a2a/sprint-3/reproduction/report.md` with a hash table. The report embeds the positive-control read, both placebo reads, the judge agreement, the plan-stage dissent records (Flatline PRD/SDD/sprint runs and the pre-registration review) and the final review/audit dissent envelopes.
**Acceptance Criteria:**
- [ ] `REPRODUCE.md` lists exact commands, expected hashes and the sample; the reproducer's report shows every hash equal and the rerun grades inside the recorded arm range (or the discrepancy named).
- [ ] `report.md` § Proof links the reproduction report, the positive control, the placebos, the judge result and the dissent records by path.

### FR-11: Harness follow-ups and the release hold
**Priority:** Should Have
**Description:** The open grader/harness follow-up beads enter Sprint 1 as tasks (DEC-0658): bd-9zmfn (`false_positives` / `findings_refuted` computed under the same rule as the recall — **Must Have**, since precision is a headline read; "document the inconsistency" is not an acceptable close), bd-eriso (the contamination scan covers WebFetch/WebSearch tool inputs — folded into the egress class of FR-5), bd-56nn6 (pre-launch `mount_cheval=ok|broken:<reason>` evidence line), bd-jszcp (`dissent_absent_reason: disabled` from harness-owned evidence), bd-st02i (`--batch-context` argv flag instead of the inheritable env var), bd-gdl5s (toggle vocabulary exposed from `lib/sandbox-mount.sh` or a parity bats case). CHANGELOG `[Unreleased]` gains, at the top, the line that v2.0.0-rc.7 is held until the cycle-132 measurement reads land (DEC-0670).
**Acceptance Criteria:**
- [ ] Each bead's acceptance text is met with a bats case and the bead closed with the evidence.
- [ ] CHANGELOG `[Unreleased]` carries the rc.7 hold line from Sprint 1; the ship step replaces it with `## [2.0.0-rc.7] — <date>` only after FR-9 and FR-10 are complete.

> Sources: cycle-132-brief.md § The operator's instruction (Phases 0–3), § Lead's design proposals 1–10, § Bugs; evals/harness/pipeline-run.sh header (BARE, phases), lib/sandbox-mount.sh toggles, took-effect.sh, ablation-grade.sh header (DEC-0413 read-only), ablation-row.sh cost_usd (phases Σ), run-ablation.sh options (--pre-registration-ref, --resume, MANIFEST), seed-corpus-from-record.sh header; evals/suites/ablation-2.0.yaml rules (bootstrap, exclusion, mde_cut); c131-reads.md; analysis.md §§7, 10.5 (codebooks, kappa pattern); decisions.yaml DEC-0626, DEC-0638, DEC-0640, DEC-0645, DEC-0648, DEC-0650, DEC-0658, DEC-0662 … DEC-0672; known-failures.md KF-046, KF-048, KF-051

---

## Non-Functional Requirements

### NFR-1: Pre-registration and honesty
Every read's rule precedes its data in a hashed document; the analysis code runs on placebo data before real data; a rule that fires is reported as it fired; the hashed text is immutable; every judgment call is a DEC row with the alternatives rejected.

### NFR-2: Zone and process discipline
Implementation only through `/run sprint-plan`; reviews and audits per sprint; ≤ 3 dissent runs per sprint; no dissent during a batch (KF-037); no `.claude/` edit without an authorization row in this PRD (none planned); third-party text is data.

### NFR-3: Reproducibility
Python 3.13 stdlib only; every random process seeded with the pre-registered seed; `reads.md`, `power.md` and every grade.json byte-identical across runs; the record branch carries every transcript, envelope, grade, row, packet and label file (no sandboxes); `REPRODUCE.md` is executable by a stranger.

### NFR-4: Tests
`evals/tests/` (534 cases today) and `tests/unit/` stay green; every new script has bats or unittest coverage; `bash -n`; CI (`bats-tests.yml`, `ci.yml`, the eval-harness step) green before the PR is ready.

### NFR-5: Budget and time
Cap set by the pre-registration from FR-6 (planning envelope ≤ USD 2,500); halt only on spend above it; the codex credential horizon (2026-10-28T04:44Z) bounds every batch; three sprints in about four days of wall clock (Phase 1 batches ≈ 24 hours at concurrency 3).

### NFR-6: Security
No credential reaches a sandbox beyond the per-run read-only copies the harness already makes (KF-048 placeholder refresh token); packets and reports hold no secrets (`no-secrets.sh` on every written file); untrusted bodies (issues, transcripts) are quoted inside fences, never interpreted.

> Sources: cycle-132-brief.md § The operator's instruction; CLAUDE.loa.md § Process Compliance, § Karpathy Principles; known-failures.md KF-037, KF-048; evals/graders/no-secrets.sh

---

## User Experience

The maintainer reads one report whose first 300 words answer the question in plain language, whose first table is the primary read with its interval, whose "Stopping rule" paragraph says what fired, and whose "Proof" section links a reproduction by a stranger. The lead's operational surface is unchanged: `run-ablation.sh` with two new flags (`--pre-registration-file`, the matched arm via the suite), `reads-c132.py --look n | --final | --placebo`, the annotation and judge packet generators, and `REPRODUCE.md`. Implementers get briefs with exact file ownership; annotators and the judge get packets with nothing but the data they must label.

> Sources: cycle-132-brief.md § Lead's design proposals 1, 6, 8; analysis.md § ELI5 (pattern)

---

## Technical Considerations

### Architecture (for the SDD)
- `evals/harness/pipeline-run.sh`: the `bare_sessions: matched` toggle → k BARE phases; per-session transcripts, costs, `phases.jsonl` records; evidence `bare_sessions=k`.
- `evals/harness/lib/sandbox-mount.sh`: toggle vocabulary gains `bare_sessions`; bd-gdl5s exposes the vocabulary.
- `evals/harness/took-effect.sh`: rule `bare_sessions_matched`.
- `evals/harness/ablation-grade.sh` + `evals/graders/recall-vs-defects.sh` (1.3.2): union grading over k sessions, `recall_session1`, `label_set`, v2 manifest fields; invariants of DEC-0413 kept (reads only the run dir, task and key).
- `evals/harness/ablation-row.sh` (1.5): `bare_sessions`, `label_set`, per-phase costs; `ablation-report.py` (1.4): partitions by k and label set.
- `evals/harness/run-ablation.sh`: `--pre-registration-file`, `preregistration_sha256` in MANIFEST, resume check; `--batch-context` (bd-st02i).
- `evals/harness/seed-corpus-from-record.sh`: explicit `--feedback` paths for a2a dirs that are not `sprint-<N>`; `fixture.yaml` provenance fields; v2 manifest schema and `--build-manifest` support for the new fields (on top of sprint-bug-268's `@L<n>` and `--sync-labels`).
- New: `evals/harness/annotation-packets.sh`, `evals/harness/judge-sample.sh`, `evals/analysis/c132/{reads-c132.py, power.py, stats.py, tests/}`, `grimoires/loa/evals/ablation-2.0-c132/{PREREGISTRATION.md, tasks/, MANIFEST.sha256, README.md}`, `grimoires/loa/reports/review-catch-c132/`, `evals/harness/schemas/review-manifest.schema.json`.

### System Zone authorization (explicit, cycle-level)
None. The cycle edits `evals/`, `grimoires/`, `CHANGELOG.md` and, at the ship step only, the release-metadata files `.loa-version.json`, the README version pin and `grimoires/loa/reports/release-notes-2.0.0-rc.7.md` (Flatline sprint review SKP-001; DEC-0707). If a `.claude/` change becomes necessary (for example `adversarial-review.sh`), it needs a PRD amendment with its own DEC row before any implementer touches it.

### Pin
One pin for every arm: the first commit of Sprint 2 (after Sprint 1's harness changes land and are reviewed). Cycle-130/131 rows feed the power simulation and the Phase 0 placebo only (DEC-0672).

### Dependencies
Docker 26 and image `loa-ablation:258` (Claude Code 2.1.299 inside — recorded in every row); codex CLI credential valid to 2026-10-28T04:44Z (operator re-auth if a batch's horizon passes it); AWS Bedrock bearer key; Python 3.13 (stdlib); bats 1.13; yq v4; jq 1.6; `gh` (read-only for the incident packets).

### Constraints inherited
Grader invariants (DEC-0413); exclusion mode pairwise with the 25 % guard; the closed mount on every mounted arm except the open-mount control; eval config variant (`budget_scale: diff`, max 600 c) for the dissent-enabled arms; task bounds REVIEW 50 / AUDIT 40 min and run cap USD 30 on large PRs; refusal-fallback rows excluded from the primary (KF-051); KF-046 class 7 exemptions and the declared scratch-directory shapes (S3) for the contamination scan.

> Sources: evals/harness/*.sh headers; evals/suites/ablation-2.0.yaml; decisions.yaml DEC-0413, DEC-0640, DEC-0645, DEC-0672; known-failures.md KF-046, KF-048, KF-051; cycle-131 prd.md § Technical Considerations (pattern)

---

## Scope & Prioritization

### MVP (this cycle)
FR-1 … FR-10 in full (the operator's specification) and FR-11.

### Explicitly out of scope
- Changing any shipped default, cap, arm, model or skill text (G-7). The report may propose; the operator decides afterwards.
- Re-reading or rewriting the cycle-130/131 reads; they stand as recorded.
- A defect-level logistic GLMM (stdlib cannot fit it reliably; named as a limitation) and any dependency beyond stdlib.
- Build-task arms, the Flatline knowledge tiers, model retargeting, new fixtures of synthetic planted defects.

### Priority order under a lower cap
If the pre-registered cap binds: the runner's reservation rule stops launches; the pre-registered launch order within a group is `a1_full`, `a0_bare_matched`, `a1_review_only`, `a0_bare_fable_matched`, then the open-mount control, so a cut group loses the secondary arms first; a cut cell is reported, never back-filled, and no third trials are run.

> Sources: cycle-132-brief.md § Out of scope, § Lead's design proposals 10; DEC-0665, DEC-0666, DEC-0669

---

## Success Criteria

- The report answers the question in one sentence with a 95 % cluster-by-PR interval, a REML estimate and a permutation p, on labels re-derived blind with a reported kappa, on PRs the pipeline had not been evaluated on, at matched dollars.
- The pre-registration hash is in the batch manifest and NOTES before the first row; the placebo on the existing runs is committed before any Phase 1 spend and reads zero; the plan's dissent review precedes the first row.
- The positive control reads positive; the placebo on the new rows reads zero; the grader–judge agreement and kappa are reported.
- A stranger reproduced every grade, row and read byte for byte from a fresh clone and reran a sample live.
- The stopping rule's outcome is stated plainly; spend never exceeded the cap; nothing shipped by default changed; rc.7 was held until the reads and cut only after the proof.
- Every judgment call is a DEC row with the alternatives rejected; review, audit, Bridgebuilder, merge, record branch and archive (through the fixed archive script) are complete.

> Sources: cycle-132-brief.md § The operator's instruction; § Goals & Success Metrics above

---

## Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Annotator kappa low (< 0.6) — the ground truth is contested | medium | high | the codebook is tested on one fixture first and revised before the blind run; adjudication share and kappa are headline caveats; the review-derived labels remain a sensitivity set |
| Power simulation names an N the budget cannot afford | medium | high | report the achievable power at the affordable N and pre-register that N with its power; the stopping rule still governs |
| Codex credential expires mid-batch (2026-10-28) | low | medium | pre-flight horizon check before each batch (KF-048); batches scheduled to finish by 10-27; operator re-auth note |
| Fable refusal fallbacks (KF-051) remove cells | low | medium | excluded from the primary, counted; a third trial on an affected PR if the cap allows |
| Contamination-scan false positives (KF-046, recurrence 10) | medium | medium | scratch-directory shapes declared in the pre-registration (S3 class); hand-read of every contaminated row before the final read |
| k sessions make matched runs long (k ≈ 13 × 5 min) | high | low | sequential sessions within one run; concurrency 3 across runs; batches planned at ≈ 24 h |
| The positive control does not read positive | low | high | the apparatus read is void and the report says so; the oracle detector output is examined before any other read |
| Grader–judge agreement low | medium | medium | the judge-corrected sensitivities become the headline caveat; the grader stays primary as pre-registered |
| Record-branch feedback for sprints 263–265 lives under `a2a/sprint-1..3/` | certain | low | the seeder's explicit `--feedback` paths (FR-1) |
| Harness changes shift earlier rows | certain | low | one pin; earlier rows never pooled (DEC-0672) |

> Sources: known-failures.md KF-046, KF-048, KF-051; c131-reads.md § Row inventory; analysis.md §10.7

---

## Timeline & Milestones

| Sprint | Global | Phase | Deliverables | Exit |
|--------|--------|-------|--------------|------|
| 1 | 266* | Phase 0 (no arm spend) | FR-1 corpus + provenance; FR-2 annotation + kappa + v2 manifests; FR-3 matched arm; FR-5 analysis code + placebo on existing runs; FR-6 power + N + cap; FR-7 pre-registration hashed + dissent; FR-11 follow-ups + rc.7 hold line | `evals/tests/` green; placebo committed; pre-registration hash in NOTES; Flatline record |
| 2 | 267* | Phase 1 | FR-8 smoke, k table, G1 (+ open-mount control), look 1, G2, look 2, G3, look 3 (or stop); FR-4 judge sample | rows at the pin; look decisions in NOTES; spend posts |
| 3 | 268* | Phases 2–3 + ship | FR-9 reads + report; FR-10 reproduction + proof; CHANGELOG rc.7; PR; review; audit; Bridgebuilder; merge; record branch; archive | report tracked; reproduction report; merged |

\* global ids are allocated by the ledger at sprint planning (the /bug micro-sprints took sprint-bug-266 … 268; the cycle's sprints follow).

> Sources: cycle-132-brief.md § Sprint breakdown; ledger.json (next_sprint_number)

---

## Appendix

### A. Glossary
- **Matched spend / compute-matched** — the bare arm given the same dollars as a full pipeline run: k independent bare sessions whose findings are unioned (DEC-0663).
- **Label source** — where a defect's existence comes from: `fix-commit` (a hunk of head..fix), `incident` (a post-merge issue, Bridgebuilder round, KF entry or later fix), `review` (the pipeline's own round-1 feedback; frozen sensitivity sets).
- **Look** — an interim read after a PR group under the group-sequential rule; **boundary** — the z threshold a look must cross for YES or NO.
- **Placebo** — the analysis run with arm labels shuffled within PR; must read zero.
- **Positive control** — the open-mount arm, a known inflation, which must read positive.
- **Pin** — the one source commit every Phase 1 cell runs.

### B. Source documents
- `grimoires/loa/context/cycle-132-brief.md` (the operator's instruction verbatim; the raw-material map)
- `grimoires/loa/reports/ablation-2.0/{analysis.md, c131-reads.md, c131-rows.jsonl, regrade-c131/rows.jsonl, runs.jsonl}`; the archive `grimoires/loa/archive/cycle-131-honest-measurement/`
- Record branches `record/cycle-130-analysis` (replication-01 runs, analysis scripts), `record/cycle-131-honest-measurement` (27 runs, a2a records), `record/cycle-12{6,7,8,9}-a2a`, `record/cycle-130-a2a` (feedback and fix commits for the fixture candidates)
- `grimoires/loa/known-failures.md` KF-037, KF-046, KF-048, KF-049, KF-050, KF-051; `grimoires/loa/decisions.yaml` DEC-0597 … DEC-0672
- the harness and suite files named in § Technical Considerations

### C. Interview record (unattended)
Phases 1–7 were answered from the operator's instruction (quoted verbatim in the brief), the cycle-131 archive and a direct read of the code; no question was asked of the operator; every operator-level choice is listed in E.

### D. Open questions for the operator (non-blocking)
- If the power simulation's N costs more than the planning envelope, should the cycle run at the affordable N and report its power, or wait? (Default taken: run at the affordable N, pre-registered with its power.)
- Should the report's recommendation, if YES, propose making the review pipeline default on review PRs for downstream mounts? (Out of scope to change; the report may propose.)

### E. Decisions taken on the operator's behalf
- **D1** [ASSUMPTION decision] (DEC-0661) — unattended planning from the instruction and the inventoried harness; no `/ride`.
- **D2** [ASSUMPTION decision] (DEC-0662) — primary statistic Δ recall at matched spend; 95 % cluster-by-PR bootstrap (90 % beside); MDE 0.10; α 0.05; power 0.80.
- **D3** [ASSUMPTION decision] (DEC-0663) — the matched arm is a harness arm (k BARE sessions, union graded); BARE-1 is the single-bare read.
- **D4** [ASSUMPTION decision] (DEC-0664) — ground truth from fix hunks and incidents by two blind Opus annotators; hunk-level kappa; lead adjudicates; cycle-131 and v1 labels frozen as sensitivities.
- **D5** [ASSUMPTION decision] (DEC-0665) — three looks by PR group, Lan–DeMets O'Brien–Fleming boundaries for YES/NO, non-binding futility; halt at a boundary or above the cap.
- **D6** [ASSUMPTION decision] (DEC-0666) — open-mount positive control on G1 only; must read positive or the apparatus read is void.
- **D7** [ASSUMPTION decision] (DEC-0667) — grader 1.3.1 primary; blind judge on a stratified sample; agreement and kappa reported; judge-corrected figures are sensitivities.
- **D8** [ASSUMPTION decision] (DEC-0668) — corpus from unseen record fixtures and new fixtures seeded from sprints 255–265; N from the power simulation; pr-11 flagged.
- **D9** [ASSUMPTION decision] (DEC-0669) — planning envelope ≤ USD 2,500; the binding cap set by the pre-registration before any Phase 1 spend; halt only above it.
- **D10** [ASSUMPTION decision] (DEC-0670) — rc.7 held until the reads; cut at ship after the proof; CHANGELOG says so.
- **D11** [ASSUMPTION decision] (DEC-0671) — a standalone report directory with a pointer from analysis.md.
- **D12** [ASSUMPTION decision] (DEC-0672) — one pin (the Sprint 2 start commit); earlier rows feed only power and placebo.
- **D13** [ASSUMPTION decision] (DEC-0686) — `a0_bare_fable_matched` as a secondary arm on every PR: same model, same dollars; the arms' models are stated in FR-3.
- **D14** [ASSUMPTION decision] (DEC-0688) — the ground-truth construct is "defects confirmed by a fix or an incident"; incidents run to the scan date; judge-confirmed real strays are a labelled sensitivity.
- **D15** [ASSUMPTION decision] (DEC-0689) — a network-egress contamination class (incl. WebFetch/WebSearch inputs, bd-eriso).
- **D16** [ASSUMPTION decision] (DEC-0690) — outcomes YES / NO / SMALL / FUTILE / CONTINUE; repeated confidence intervals beside naive ones; simulation-calibrated boundaries; information fraction by SE ratio.
- **D17** [ASSUMPTION decision] (DEC-0687) — the placebo is a distribution of 200 shuffles with a calibration criterion.
- **D18** [ASSUMPTION decision] (DEC-0691) — k per PR from the existing 63 runs before the hash; the smoke verifies; realized ratio and exact-dollar trim reported.
- The bug-phase decisions DEC-0656 … DEC-0660 (order of work; bd-jm55c premise; archive-cycle defaults; labels grammar; follow-up beads routing) precede this PRD and are referenced by FR-11.

### F. Flatline integration (PRD review, 2026-10-21T00:57–01:06Z)
Two voices (claude-headless = Fable 5.1, gpt-5.5 via codex), 24 blockers (3 CRITICAL, 21 HIGH), cross-scoring degraded (KF-041 shape: 0 % agreement, no consensus tiers; `verdict_quality` DEGRADED, cost 0 cents reported); the raw reviews were read in full and integrated by judgment (DEC-0685). Record: `grimoires/loa/a2a/flatline/prd-review-c132.json`.

**Adopted (FR text amended):** the YES/NO overlap → the YES/NO/SMALL/FUTILE/CONTINUE partition, repeated confidence intervals and simulation-calibrated boundaries (opus SKP-001, SKP-002, gpt SKP-003, SKP-006 → D16, FR-5/FR-6); k from the existing runs before the hash, realized ratio and exact-dollar trim reported (gpt SKP-004, SKP-015, opus SKP-004 → D18, FR-3); the arms' models stated and a same-model matched arm added (opus SKP-002 → D13, FR-3/FR-8); the ground-truth construct stated, incidents to the scan date, judge-confirmed strays as a sensitivity (gpt SKP-001, SKP-010 → D14, FR-2); a network-egress contamination class incl. WebFetch inputs (gpt SKP-003, SKP-014, bd-eriso → D15, FR-5); the placebo as a 200-shuffle distribution (SKP-008 → D17, FR-5); the estimand and pairing fixed (SKP-016 → FR-5 a); the judge universe, inclusion probabilities, weights and partial handling (SKP-018 → FR-4); cost on all spend beside valid pairs, no replacement trials, 25 % guard semantics (SKP-022 → FR-5 g/h); the cap enforced before launch by the reservation rule with the stated overshoot bound, the "never cut a started group" exception dropped (SKP-023 → FR-8, § Scope); the positive-control contrast, mechanism check and "not exercised" outcome (SKP-024 → FR-8); N bounded by the 15 candidates, the deterministic affordable-N rule, the correlated-sessions sensitivity, the full-procedure simulation (SKP-005, SKP-006, SKP-007, SKP-030 → FR-6); exposure fields replace "post-cutoff by availability" (SKP-013 → FR-1); bd-9zmfn as Must Have (SKP-020 → FR-11); record-branch secret scan and `no-secrets.sh` over packets and reports (SKP-029 → NFR-6).

**Not adopted, with reasons:** replacing grader 1.3.1 as the primary (SKP-020) — the ruler was adjudicated in cycle-131 (DEC-0638); the judge measures it (FR-4). A model-driven defect hunt as a label source (implied by SKP-001/010) — another arm in disguise (D14 rationale). An egress proxy (SKP-003/014) — infrastructure this cycle cannot build and validate before Phase 1 (D15 rationale). Fixing N without simulation (SKP-007's budget arithmetic) — the affordable-N rule answers it deterministically.

> Sources: decisions.yaml DEC-0656 … DEC-0672; cycle-132-brief.md
