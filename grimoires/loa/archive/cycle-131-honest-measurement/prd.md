# Product Requirements Document: Honest review-catch measurement — close the peek, fix the ruler, price the gates (cycle-131)

**Version:** 1.0
**Date:** 2026-10-19
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-19: "proceed as you suggest" on the cycle-130 deep analysis; the interview phases were answered from the operator's brief, the analysis and the tree; every operator-level choice is tagged `[ASSUMPTION decision]` with its DEC row)
**Brief:** `grimoires/loa/context/cycle-131-brief.md` (lead, 2026-10-19, from the operator's instruction)
**Analysis this cycle acts on:** `grimoires/loa/reports/ablation-2.0/analysis.md` (PR #1285, merged `e9a66e16`; working files on `record/cycle-130-analysis`)
**Cycle:** `cycle-131-honest-measurement` (ledger); **branch:** `feature/cycle-131-honest-measurement` from `main e9a66e16`

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

Cycle-130 shipped a read that the full Loa review pipeline catches more planted defects than one bare Opus 5.5 session (+0.263 [+0.158, +0.386] on `defect_catch_rate`, DEC-0597). The deep analysis that followed (PR #1285) found that about half of that gap is the grader's ±3-line citation window interacting with the bare arm's one-line-per-finding output contract; that one of twelve full runs took its catches from a copy of the fixed code the sandbox should never have held (KF-049); that the cross-model dissent is credited with zero citations in 36 runs and never ran at a review gate on three of six PRs; and that the audit gate is half a run's cost for a twentieth of its catch. The replication on two fresh PRs reproduced the lift (+0.452 with two scanner-false-positive rows read in) and reproduced the peek (two of six runs).

This cycle makes the measurement honest and then prices the two expensive gates against a control that separates the model from the pipeline. Sprint 1 changes the eval harness: the review-catch sandbox stops carrying any later-than-head copy of a PR-touched file, the grader credits a citation inside the labelled function, the runner accepts a partial suite root, the contamination scan stops firing on the PR's own repository name, and the dissent voices are asked for line anchors with a budget that lets them run on real-sized diffs. Sprint 2 adds three arms (bare Fable, review-gate-only, no-dissent review gate) and runs four pre-registered batches under the closed mount. Sprint 3 reads them under rules written before the rows exist and writes the addendum. No default changes in this cycle: every outcome is a proposal for the operator.

> Sources: cycle-131-brief.md §Objective, §The five changes, §Sprint breakdown; analysis.md §§2-9; sensitivities.md §1-2; replication.md §Reads

---

## Problem Statement

### The Problem

The number Loa uses to justify its review pipeline is measured by a harness that (i) lets the pipeline's reviewer read the fixed code, (ii) scores the two arms with a rule that favours the pipeline's output format, (iii) cannot credit the component it is supposed to price, and (iv) compares two different models while attributing the difference to the pipeline.

### User Pain Points

- The maintainer cannot tell how much of the shipped +0.263 is pipeline and how much is ruler, peek and model: "the two corrections together leave ≈ +0.115 pooled, all of it on pr-12" (sensitivities.md §3), and the replication's +0.452 falls to +0.333 with the peeked catches zeroed (replication.md §Reads).
- The dissent — the component the pricing question is about — "contributes 0 credited citations in every run" because "none of the 24 dissent envelopes … carries a numeric line anchor" (attribution.md §The structural fact first), and its budget gate "refused every review gate on pr-13, pr-17 and pr-18" (analysis.md §9 item 4).
- The replication could not run under the tracked runner: `freeze.sh --check` and the grader take no `--allow-partial`, so a two-task root fails the hard gate (DEC-0603); two of its rows read `contaminated` because the grader's `repo_name` scan fired on the PR's own `github.repository == '0xHoneyJar/loa'` clause (KF-046 recurrence 9).
- Every review-catch arm mounts the pinned framework at `/workspace/.claude` by `cp -a "$tree/.claude/." "$ws/.claude/"` (evals/harness/lib/sandbox-mount.sh:131), a later copy than every corpus PR's head; the bare arm mounts nothing (pipeline-run.sh:535 `loa_mount: false but the sandbox has .claude/`), so the arms differ in oracle access.

### Current State

- `evals/harness/pipeline-run.sh` materialises the sandbox: for review-catch tasks it copies `base head head.diff PR.md REVIEW-INSTRUCTIONS.md AUDIT-INSTRUCTIONS.md` into `pr/` (lines 503-505) and, when `loa_mount` is true, `mount_prompt_surface "$WS" "$SOURCE_TREE" -` copies the whole `.claude/` tree plus `CLAUDE.md` and `.loa.config.yaml` (lines 523-525; sandbox-mount.sh:125-136).
- `evals/graders/recall-vs-defects.sh` (1.2.0) detects a defect when a `path:line` citation "falls within ±3 of the manifest anchor — `anchor_line`, or any line in `anchors[]`"; `ablation-grade.sh` (1.2.13) reduces review.md, the two feedback files and the envelopes' `anchor`/`file:line` fields to `grading/gates-combined.md` and calls it.
- `evals/harness/took-effect.sh` evaluates per-trial rules (`no_dot_claude`, `all_phases_present`, `integrity_clean`, …); a miss pauses the arm (DEC-0418).
- `.claude/scripts/adversarial-review.sh` asks each voice for `"anchor": "file:symbol", "anchor_type": "function|hunk|line"` (line 1157) and the schema says "file:symbol_name preferred" (`.claude/schemas/adversarial-finding.schema.json:97-99`); `budget_cents` defaults to 150 (200 in the eval config) and the estimate for a 239 KB diff is 366 c, for a 125 KB diff 214 c (replication.md).
- `evals/harness/run-ablation.sh` pre-flight: `FREEZE_ARGS=(--check --root "$SUITE_ROOT" --suite-file "$SUITE_FILE")` (line 696) and the grader call at line 1242 carry no `--allow-partial`.
- The 36 review-catch run directories of cycle-130 (24 v2 valid cells, 12 replication) and the analysis scripts (`record/cycle-130-analysis`, `grimoires/loa/a2a/analysis-2026-10/scripts/`) exist and re-derive every grade.json exactly.

### Desired State

A review-catch measurement in which (1) no arm can see a later copy of the code under review and a grader-side check proves it per run, (2) a correct finding is credited wherever in the labelled function it is cited, (3) the dissent can run on real diffs and can be credited, (4) a bare-Fable arm separates the model from the pipeline, and (5) the audit gate and the dissent have pre-registered prices — all reported as an addendum beside the shipped read, with proposals, not changed defaults.

> Sources: analysis.md §§3, 5, 8, 9; sensitivities.md; attribution.md; replication.md; replication-driver-diff.md; KF-049, KF-046 (known-failures.md); evals/harness/pipeline-run.sh:503-545; evals/harness/lib/sandbox-mount.sh:125-136; evals/graders/recall-vs-defects.sh header; .claude/scripts/adversarial-review.sh:1157, :200; .claude/schemas/adversarial-finding.schema.json:97-110

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Close the peek: no review-catch sandbox holds a later-than-head copy of any PR-touched file, and the grader proves it per run | took-effect rule `oracle_closed` passes on every trial; grader field `oracle_exposed_defects` is `[]` on every row of every cycle-131 batch | smoke of all seven corpus PRs under the closed mount + the R1 A/B batch rows |
| G-2 | Fix the ruler: the grader credits a citation inside the labelled function; both rules reported side by side on every existing run | re-graded rows for the 36 cycle-130 runs carry `recall` (new) and `recall_pm3` (old); ≥ 80 % of the credits the new rule adds are adjudicated as the labelled defect by two labelers (kappa reported) | `ablation-grade.sh --rerow` over the run dirs; adjudication CSV |
| G-3 | Make the dissent measurable: voices cite lines and run on real-sized diffs | ≥ 80 % of dissent findings carry a numeric anchor on the smoke; `budget_exceeded` on 0 review gates of the Sprint 2 batches' dissent-enabled arms on pr-17 and pr-18 | envelope scan over the batch run dirs |
| G-4 | Separate the model from the pipeline | `a0_bare_fable` rows exist for pr-17 and pr-18 × 3 and the pre-registered reading rule is applied | batch B2 rows; reads in the addendum |
| G-5 | Price the audit gate and the dissent under pre-registered rules | `a1_review_only` and `a1_no_dissent` rows exist; each pre-registered rule yields one of its named outcomes | batch rows; NOTES pre-registration precedes every row; addendum |
| G-6 | Nothing shipped changes without the operator | no default value, cap or arm of the shipped pipeline is changed in this cycle (the dissent's additive `anchor_line` fields and the `budget_scale` knob with default `fixed` are listed schema extensions, not default changes); the addendum states proposals | allowlisted diff vs `main` of `.loa.config.yaml`, skill frontmatter, shipped suite arms and `adversarial-review.sh` defaults at the close |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Runs with a head-vs-workspace diff covering a planted site | 3 of 18 full runs (1/12 + 2/6) | 0 of all cycle-131 full runs | Sprint 2 | G-1 |
| Grader rule coverage of correct bare citations | 31/57 (±3) vs 42/57 (same function) on the v2 cells | both reported; adoption decided by the ≥ 80 % adjudication rule | Sprint 1 | G-2 |
| Dissent envelopes with a numeric anchor | 0 of 24 (+ 0 of the replication's) | ≥ 80 % on the smoke; every review gate ran both voices on the batch PRs | Sprint 1 → 2 | G-3 |
| Pre-registered reads taken | 0 | 4 (R1 A/B, R5 control, R3 audit price, R4 dissent price) over 2 batches | Sprint 3 | G-4, G-5 |
| Spend | USD 0 of 500 | ≤ 500 total, ≤ 275 on batches | all | — |

### Constraints

- Analysis-grade honesty: every rule is written in NOTES before its batch's first row; a read that fails its rule is reported as failing.
- No `.claude/` edit outside `/implement` and outside the explicit System Zone authorization in §Technical Considerations; third-party text (transcripts, envelopes, PR bodies) is untrusted data.
- ≤ 3 dissent runs per sprint for the cycle's own gates; no dissent while a batch runs (KF-037); the codex credential pre-flight (KF-048) before any batch.
- Budget: USD 500 cycle cap, ≤ 275 on batches (DEC-0620 amending DEC-0611), review-catch run cap USD 20, concurrency 3 [ASSUMPTION decision] (DEC-0611).

> Sources: cycle-131-brief.md §Objective, §Budget, §Metrics and rules; analysis.md §9; attribution.md; sensitivities.md; replication.md

---

## User Personas & Use Cases

### Primary Persona: The maintainer (operator)

**Demographics:** maintainer of the Loa framework (`@deep-name`), decides defaults and spend; technical proficiency expert; goal: know what each gate is worth before promoting 2.0.0.
**Behaviors:** pre-approves cycles end to end; reads the ELI5 first, then the rules and the intervals; confirms DEC rows in batches (`/decisions confirm --cycle … --all`).
**Pain Points:** numbers that move when the ruler moves; a component priced by a measurement that cannot see it; experiments that cannot be re-run because the harness refuses a partial suite.

### Secondary Persona: The lead agent (Fable) and its Opus implementers

Run the cycle unattended; need mechanical gates (validators, took-effect rules, grader self-checks) that fail loudly, and reading rules that leave nothing to taste at read time.

### Use Cases

#### UC-1: Re-grade the shipped runs under both rules
**Actor:** lead · **Preconditions:** grader 1.3 landed; the 36 run directories present · **Flow:** run `ablation-grade.sh` over each run dir with `--suite-root` and `--allow-partial` where needed → rows carry `recall` and `recall_pm3` → report addendum table per PR and arm → 20-packet adjudication of added credits · **Postconditions:** the shipped read is untouched; the addendum shows both rules · **Acceptance:** every re-derived old-rule value equals the stored grade.json; the adjudication CSV and kappa are in the a2a folder.

#### UC-2: Run a review-catch batch under the closed mount
**Actor:** lead · **Preconditions:** Sprint 1 merged into the cycle branch; pin recorded; pre-registration in NOTES; KF-048 pre-flight green · **Flow:** `run-ablation.sh … --suite-root <root> --allow-partial` dry run → `--detach` → watch → read · **Postconditions:** every row has `oracle_exposed_defects: []`, `took_effect` all true · **Acceptance:** a row with any exposed defect fails the batch's pre-registered validity check and is excluded pairwise, and the cause is recorded.

#### UC-3: Read a pre-registered price
**Actor:** lead · **Preconditions:** the batch complete · **Flow:** `ablation-report.py --partial` on the batch rows with the arm pair → the rule's outcome is one of its named branches → DEC row + addendum section · **Acceptance:** the outcome text matches the pre-registration verbatim.

> Sources: cycle-131-brief.md §The five changes; feedback_operator_collaboration_pattern (memory); analysis.md §9

---

## Functional Requirements

### FR-1: Closed mount for review-catch sandboxes (R1, bead bd-mlg9s, KF-049)
**Priority:** Must Have
**Description:** When a review-catch task mounts the framework, the sandbox must hold no copy of any *answer-bearing path* that is later than `pr/head`. Answer-bearing paths are (i) every path in `pr/head.diff`'s `diff --git` headers or present under `pr/head/` or `pr/base/`, and (ii) for record fixtures every path the fixture's `fix_commit` touched (read from `fixture.yaml` through `git show --stat`), including paths the PR did not touch. One globally recorded overlay policy applies to every mounted arm: the sandbox copy of each such path under `.claude/`, `CLAUDE.md` or `.loa.config.yaml` is replaced by the PR's `pr/base/` version (a path absent from `pr/base/` is removed); the alternative `head` policy exists only as a recorded fallback if the base policy breaks a gate on a corpus PR (the Sprint 1 smoke decides, DEC-0613). Consequence, disclosed per row: on a PR that touches a gate's own script or skill, that gate runs the PR's version of it (pr-12: `adversarial-review.sh`, `verdict-derive.sh`; pr-13: the `reviewing-code` skill and the session-start hook; pr-18: one allowlist line of the `reviewing-code` skill). The Sprint 2 batches therefore use pr-17 and pr-18, whose touched gate surface is a fence hook and one skill line, and leave pr-12 and pr-13 to the re-grade (Appendix F).
**Acceptance Criteria:**
- [ ] `sandbox-mount.sh overlay_answer_paths <ws> <mode>` is called from `pipeline-run.sh` for review-catch tasks after `mount_prompt_surface`, before `apply_arm_toggles` and the eval-config writes, and before `regen_sandbox_manifest` (so `integrity_clean` holds on the overlaid tree); `arm_evidence` records `mount_overlay=<mode>:<n paths>` and one `overlay_sha256=<path>=<sha>` line per path **before the first phase starts**; added, deleted, renamed and symlinked paths are handled explicitly (a symlink is never followed; a rename counts both names).
- [ ] `took-effect.sh` rule `oracle_closed`: (a) every answer-bearing path under the mount byte-equals its `pr/base/` (or `pr/head/`, per the recorded mode) version or is absent; (b) no regular file outside `pr/` is byte-equal to the pinned (later) version of an answer-bearing path (stray copies); (c) the post-run state of each overlaid path equals its pre-run `overlay_sha256` — a difference is reported as `mount_mutated=<path>` and fails the rule. The rule is on every mounted arm's `took_effect` list.
- [ ] `ablation-grade.sh` oracle detector: over the REVIEW/AUDIT transcripts, (a) a content diff (`diff`, `sdiff`, `comm`, `git diff --no-index`; not `-q`/`--brief`; not the word `head.diff`; not heredoc bodies) between a `pr/` operand and a workspace operand of an answer-bearing path whose printed ranges cover a planted site (±3) or whose output holds the site's `must_match` text, and (b) a read (`cat`, `sed`, `awk`, `grep`, `head`, `tail`, `less`, `python3`, the Read tool) of a workspace copy of an answer-bearing path whose tool result contains a line present in the pinned copy but absent from `pr/head` within ±3 lines of a planted site — write `grade.json.oracle_exposed_defects` (positions) and `oracle_exposed_events` ({phase, event, how: diff|read, path}); `ablation-row.sh` copies the list; the report excludes such rows pairwise under a labelled rule.
- [ ] Detector validation: run over the 36 cycle-130 review-catch run directories it flags exactly `priority-v2-p1-a1_full-review-04-t2`, `replication-01-a1_full-review-r17-t1` and `replication-01-a1_full-review-r18-t1` (the three runs the analysis found) and no bare run; a bats case pins this with trimmed transcript fixtures.
- [ ] bats cases: overlay applied and evidenced (added/deleted/renamed/symlink paths); `oracle_closed` passes under the overlay, fails on an unmodified mount, on a stray copy and on a mutated path; the detector flags a synthetic covering `diff` and a synthetic read of a later line, and ignores `diff -q` and `cat pr/head.diff`.
- [ ] A smoke run of `a1_full` on each of the seven corpus PRs under the closed mount completes both gates (`all_phases_present`) with `oracle_closed` true; the smoke records per PR which gate scripts ran at the PR's version.

### FR-2: Same-function citation rule and multi-site labels (R2, bead bd-5rmmf)
**Priority:** Must Have
**Description:** `recall-vs-defects.sh` 1.3 detects a defect when a citation (a) lies within ±3 lines of a site (unchanged) OR (b) any cited line lies inside the enclosing symbol of a site in the `head/` file — bash `name() {`/`function name`, python `def`, bats `@test`, markdown: the nearest preceding heading's section — with deterministic boundaries (the symbol runs from its definition line to the line before the next definition at the same or lower indentation; nested bash functions resolve to the innermost), a span cap (a symbol longer than 400 lines falls back to ±20 lines) and a range rule (a cited range wider than 25 lines credits only through its first line). Multi-site labels: the manifests gain every head line the human finding named, **derived blind from `label_source` and the record review text only**, never from any cycle-130 output, curated by the lead and re-approved; the original manifests are retained unchanged under `manifests/v1/`. Three results are computed on every grade: `recall_pm3_v1` (old rule, original anchors), `recall_pm3` (old rule, new anchors) and `recall` (new rule, new anchors), each with `detected`/`missed`, plus `credits_function_only` (defects credited by (b) and not by (a)). **The decision statistic for every cycle-131 read is `recall` (new rule, new anchors); `recall_pm3` and `recall_pm3_v1` are reported beside it.**
**Acceptance Criteria:**
- [ ] `recall-vs-defects.sh` 1.3.0 with the rule, the boundary semantics, the span cap and the range rule in its header; `details.rule`, `details.recall_pm3_v1`, `details.recall_pm3`, `details.detected_pm3*`, `details.missed_pm3*`, `details.credits_function_only`; `ablation-grade.sh` bumps `GRADER_VERSION` and writes the three; `ablation-row.sh` carries `defect_catch_rate`, `defect_catch_rate_pm3`, `defect_catch_rate_pm3_v1`, the three `defects_missed*` lists and `credits_function_only`; `ablation-report.py` reports all three with the decision statistic named.
- [ ] `evals/tests/eval-recall-grader.bats` cases: a citation 6 lines from the anchor inside the same function detected under (b) only; a citation in the next function 6 lines away detected under neither; nested function → innermost; a 500-line function → ±20 fallback; a 40-line cited range credits only its first line; markdown section rule; multi-site anchors credit any site; `recall_pm3_v1` uses `manifests/v1/`.
- [ ] The 36 cycle-130 review-catch run directories are re-graded under 1.3 into a **separate, versioned** rows file `evals/results/ablation-2.0/regrade-c131/rows.jsonl` (the shipped `runs.jsonl` and every stored `grade.json` are untouched); every `recall_pm3_v1` equals the stored `recall`; the addendum table shows the three per PR and arm with the finding volume and false-positive count beside recall.
- [ ] Adjudication (pre-registered protocol): the credits in `credits_function_only` across the 36 runs are deduplicated by (run, defect); 20 are sampled stratified by arm and PR (seed 20261015) and labelled blind by two Opus 5.5 sessions under a codebook ("the labelled defect" / "a different finding" / "unclear"; prompts recorded; independent); kappa reported; kappa < 0.6 triggers a third labeler and reconciliation; the rule is proposed for adoption iff ≥ 80 % of the sample is "the labelled defect" (denominator: the 20).

### FR-3: Harness follow-ups (beads bd-9lfns, bd-1ohfe, bd-ocovl)
**Priority:** Must Have
**Description:** (a) `run-ablation.sh --allow-partial` passes to the freeze check and to every grader call and is recorded in `MANIFEST.json`; (b) the contamination scan treats a repo-name token that occurs in `pr/head/**` or `head.diff` as PR content (KF-046 class 7); (c) `ablation-row.sh` records `dissent_absent_gates` (gates whose envelope `metadata.status` is `budget_exceeded`, `failed` or a record-fallback) and `ablation-report.py` prints a labelled sensitivity excluding those rows.
**Acceptance Criteria:**
- [ ] `run-ablation.sh --dry-run` on `grimoires/loa/evals/ablation-2.0-replication` passes the pre-flight with `--allow-partial` and refuses without it; MANIFEST records `allow_partial: true`.
- [ ] The two `replication-01` rows (`a1_full-review-r18-t2`, `-t3`) re-grade clean under the exemption (line-level: the matched line exists in the fixture's head tree or `head.diff`) into the versioned re-grade rows (the shipped rows untouched); the replication's pre-registered read is re-taken on six valid cells under the old rule and original anchors, with the oracle-exposed cells (`review-r17-t1`, `review-r18-t1`) excluded pairwise as a second line, and recorded as a DEC row beside DEC-0604 (the original outcome stays on record).
- [ ] bats cases for (a), (b), (c); `evals/tests/` green.

### FR-4: Dissent voices cite lines; the budget gate fits the diff (R4-i, bead bd-ba54i)
**Priority:** Must Have
**Description:** The adversarial review's finding contract asks each voice for a numeric anchor (`file:line` or `file:start-end`, `anchor_type: line`) beside the symbol anchor it gives today; `process_findings` records `anchor_line` / `anchor_line_end` when present and the envelope keeps `anchor_type`; the grader's envelope reduction already credits `file:line`. The budget gate gains a configurable scaling (`flatline_protocol.<gate>.budget_scale: fixed|diff`, default `fixed` — the shipped behaviour is unchanged): with `diff`, `budget_cents = min(max(budget_cents, ceil(estimate × 1.2)), budget_cents_max)` with `budget_cents_max` default 600, where `estimate` is the gate's own pre-dispatch estimate over the planned voices; a gate whose estimate exceeds `budget_cents_max` still refuses (`budget_exceeded`) and the row records it. In the evaluation config both voices run on the corpus diffs (66–239 KB; pr-13's 366 c and pr-18's 214 c fit under 600).
**Acceptance Criteria:**
- [ ] `.claude/scripts/adversarial-review.sh`: prompt and normaliser changes, `adversarial-finding.schema.json` gains `anchor_line`/`anchor_line_end` (optional integers); `verdict-derive.sh` unaffected; `tests/unit/adversarial-review-*.bats` cases for a numeric anchor parsed, a symbol-only anchor kept, and the scaled budget.
- [ ] `.loa.config.yaml.example` documents `budget_scale`; the eval config used by `pipeline-run.sh` sets `budget_scale: diff` for `code_review` and `security_audit`; the shipped default stays `fixed` (G-6).
- [ ] On the Sprint 2 smoke (pr-12, pr-13), the review-gate envelope shows `voices_succeeded: 2` and ≥ 80 % of findings carry a numeric anchor.

### FR-5: Three new arms
**Priority:** Must Have
**Description:** (a) `a0_bare_fable`: the bare arm's phases, prompt, tools, effort (`high`) and output contract with the BARE session on Fable 5.1 (`toggles: {loa_mount: false, bare_model: fable}`); (b) `a1_review_only`: `a1_full` with the review-catch phase set `[REVIEW]`; (c) `a1_no_dissent`: `a1_full` with the review gate's adversarial dissent disabled (`toggles: {dissent: false}` → `flatline_protocol.code_review.enabled: false` in the sandbox config) — the audit gate unchanged; (d) `a1_full_openmount` (eval-only, for B1): `a1_full` with the FR-1 overlay disabled (`toggles: {oracle_open: true}`), so the mount is the pinned later copy as in cycle-130. Models per phase, recorded in `pipeline.json` for every run: BARE = Opus 5.5 (`a0_bare`) or Fable 5.1 (`a0_bare_fable`); REVIEW and AUDIT = Fable 5.1; dissent primary = codex-headless, companion = claude-headless. Took-effect rules: `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope` (no `adversarial-review.json`, config shows the gate disabled), `oracle_open_recorded` (for (d): `arm_evidence` says `mount_overlay=none` and this rule replaces `oracle_closed`), plus `oracle_closed` (a–c) and `integrity_clean`.
**Acceptance Criteria:**
- [ ] Suite file `evals/suites/ablation-2.0.yaml` declares the four arms with `task_types: [review-catch]`, phases and took-effect rules; `validate-suite.sh` accepts it; `pipeline-run.sh` and `sandbox-mount.sh apply_arm_toggles` implement the toggles (`bare_model`, `dissent`, `oracle_open`); bats cases per toggle; `a1_full_openmount` is refused outside an evaluation batch (no production surface).
- [ ] One smoke trial per new arm on pr-12 completes with every took-effect rule true.

### FR-6: Pre-registered batches under the closed mount
**Priority:** Must Have
**Description:** Two batches, four reads. Every read is pre-registered in NOTES (a dated heading whose section text's sha256 goes into the DEC row and the batch MANIFEST) before the batch's first row. Common rules: all arms at one pin — the commit at which FR-1 … FR-5 are merged on the cycle branch, recorded in NOTES before B1's first row (DEC-0612); rows in `evals/results/ablation-2.0/<batch>/` (never pooled with cycle-130 rows); caps USD 20 per run, concurrency 3, the runner's seeded shuffle (20261015); the **unit** is the planted defect: for each defect the per-arm catch is its mean over the valid trials of that PR, the paired difference is taken per defect, and the 90 % interval is the percentile interval of 10,000 bootstrap resamples of the defects (the cycle-130 statistic); exclusion is per contrast and pairwise (a cell valid in both arms), a `degraded`, `contaminated`, `interrupted` or `oracle_exposed_defects ≠ []` row excludes its cell; the 25 % guard applies per arm per contrast (excluded cells ÷ planned cells); a contrast needs ≥ 4 valid cells or reads "insufficient"; the degenerate check stands; a 2-PR cluster bootstrap is printed as descriptive only. **Decision statistic: `recall` (new rule, new anchors); `recall_pm3` and `recall_pm3_v1` beside it.** Cost per run = the row's `cost_usd` (every phase's session cost plus every voice's ledger cost). Precision (planted ÷ flagged) and finding volume are reported for every arm.
- **B1 — oracle A/B (R1), `c131-b1-oracle-ab`:** `a1_full_openmount` × review-r17 (pr-17) × 3 against `a1_full` × review-r17 × 3 (the B2 cells, same pin). Read: Δ = closed − open on `recall`, 90 % interval over the 20 defects. Outcomes: interval entirely below 0 → "the oracle inflated the catch on pr-17"; interval includes 0 → "no measurable inflation on pr-17"; entirely above 0 → "investigate (the closed mount scored higher)". Secondary (descriptive): the open-mount rows' `oracle_exposed_defects` count.
- **B2 — control and prices, `c131-b2-control-prices`:** `a0_bare`, `a0_bare_fable`, `a1_full`, `a1_review_only`, `a1_no_dissent` × review-r17 (pr-17), review-r18 (pr-18) × 3. Reads, each on `recall` with its 90 % interval over the 28 defects, branches tested in order and the first true one taken:
  - **R5 (control):** let Δ₁ = bare-Fable − `a1_full`, Δ₀ = bare-Fable − `a0_bare`. (i) interval(Δ₁) within [−0.05, +0.05] and interval(Δ₀) entirely above +0.05 → "the model explains the lift; the pipeline's measurable contribution is at most 0.05"; (ii) interval(Δ₀) within [−0.05, +0.05] and interval(Δ₁) entirely below −0.05 → "the gates earn their cost; the model does not explain the lift"; (iii) neither → "between: report Δ₁ and Δ₀ with intervals; no attribution".
  - **R3 (audit gate price):** Δ = `a1_review_only` − `a1_full`; c = cost ratio (review-only ÷ full). (i) interval(Δ) entirely above −0.10 and c ≤ 0.60 → "propose: audit gate opt-in on review-only PRs"; (ii) interval(Δ) entirely below −0.05 → "keep the audit gate"; (iii) otherwise → "inconclusive".
  - **R4 (dissent price):** Δ = `a1_no_dissent` − `a1_full`. (i) interval(Δ) entirely above +0.08 → "investigate (the dissent lowers the catch)"; (ii) interval(Δ) entirely above −0.08 → "propose: dissent opt-in on review-catch gates"; (iii) interval(Δ) entirely below −0.08 → "keep the dissent"; (iv) otherwise → "inconclusive". Beside it: the numeric-anchor share of the `a1_full` envelopes and `dissent_absent_gates` per row (`a1_no_dissent` is scoped out of the "both voices ran" criterion).
**Acceptance Criteria:**
- [ ] Each batch's MANIFEST `pre_registration_ref` names a NOTES heading dated before its first row and carries the heading section's sha256; each rule's outcome is quoted verbatim in the addendum and a DEC row.
- [ ] Budget (DEC-0620): B1 ≈ USD 48 (3 open-mount runs at the pr-17 actual ≈ 16), B2 ≈ USD 220 (a0 6 × 1.4; a0F 6 × ≈ 3; a1_full 6 × ≈ 13; a1_review_only 6 × ≈ 7; a1_no_dissent 6 × ≈ 12); batch total ≤ USD 275; cycle total ≤ USD 500 (DEC-0611); spend posted in NOTES after each batch; the first cut if B1 overruns is `a1_review_only` on pr-18.
- [ ] Every row: `oracle_exposed_defects: []` (except the open-mount arm, where it is reported), took-effect all true, `dissent_absent_gates` recorded, models per phase recorded.

### FR-7: Addendum and records
**Priority:** Must Have
**Description:** `grimoires/loa/reports/ablation-2.0/analysis.md` gains §10 "cycle-131 addendum" (or a sibling `addendum-cycle-131.md` linked from it): the re-grade table (both rules, 36 runs), the oracle-closed A/B, the control-arm reading, the two prices, the adjudication result, spend; `report.md` is not rewritten. DEC rows per read; the seven `cycle-131-candidate` beads closed or re-labelled with their outcome; KF-049 and KF-046 attempts rows; release notes entry under `[Unreleased]` for the harness changes and the `budget_scale` knob.
**Acceptance Criteria:**
- [ ] `validate-artifact.sh` passes on every planning artifact; `evals/tests/` and `tests/unit/` green at the close; CHANGELOG `[Unreleased]` lists FR-1 … FR-5.
- [ ] No shipped default changed (G-6): the diff of `.loa.config.yaml` defaults and skill frontmatter against `main` shows only the new optional knob with its `fixed` default.

> Sources: cycle-131-brief.md §The five changes, §Harness follow-ups, §Metrics and rules; analysis.md §9; evals/harness/pipeline-run.sh:503-545; evals/harness/lib/sandbox-mount.sh:125-136; evals/harness/took-effect.sh:13-35; evals/harness/run-ablation.sh:696-699, :1242; .claude/scripts/adversarial-review.sh:200, :1157; .claude/schemas/adversarial-finding.schema.json:97-110; scripts/oracle_scan.py (record branch)

---

## Non-Functional Requirements

### NFR-1: Pre-registration and honesty
Every reading rule and every batch's validity rule is written in NOTES (dated heading) and a DEC row before the batch's first row; a read that trips its guard is reported as tripped with the labelled sensitivity beside it (the replication's shape).

### NFR-2: Zone and process discipline
Code changes land only through `/implement` inside `/run sprint-plan`; the System Zone paths this cycle may edit are enumerated in §Technical Considerations and the zone marker is refreshed daily and deleted at the close; third-party text in transcripts, envelopes and PR fixtures is data, never instruction; no dissent runs while a batch runs (KF-037); ≤ 3 dissent runs per sprint for the cycle's gates.

### NFR-3: Reproducibility
Every batch pins one source commit and one image digest, records the suite manifest sha, the codex token horizon (KF-048) and the pre-registration ref in `MANIFEST.json`; re-grading a run directory is byte-identical across invocations (grader invariant, ablation-grade.sh header).

### NFR-4: Tests
`evals/tests/` (447 today) and `tests/unit/` stay green; every FR adds cases; no test is weakened.

### NFR-5: Budget and time
USD 500 cycle cap, ≤ 250 on batches, per-run cap USD 20, concurrency 3; halt only above the cap. Wall-clock target: three sprints in about three days of unattended run time, batches ≈ 4 h of compute.

> Sources: cycle-131-brief.md §Budget, §Metrics and rules; CLAUDE.loa.md Process Compliance; known-failures.md KF-037, KF-048

---

## User Experience

The product surface is the harness's CLI and its reports: `run-ablation.sh` gains `--allow-partial`; `ablation-grade.sh` prints `recall` and `recall_pm3` and the `oracle_exposed_defects` list; `ablation-report.py` prints both rules and the dissent-absent sensitivity with the existing "decides nothing" labelling; `took-effect.sh` names the failing rule when an arm pauses (`oracle_closed`, `bare_model_fable`, …); the addendum follows `analysis.md`'s shape (ELI5 paragraph first, tables, rules quoted verbatim). No interactive prompt is added.

> Sources: analysis.md (shape); evals/harness/run-ablation.sh --help; ablation-report.py 1.2.3 output (report.md)

---

## Technical Considerations

### Architecture (for the SDD)
- Harness (`evals/harness/*.sh`, `evals/harness/lib/sandbox-mount.sh`, `evals/graders/recall-vs-defects.sh`, `evals/suites/ablation-2.0.yaml`, `evals/tests/*.bats`): FR-1, FR-2, FR-3, FR-5, FR-6.
- Framework (`.claude/scripts/adversarial-review.sh`, `.claude/schemas/adversarial-finding.schema.json`, `.claude/skills/{reviewing-code,auditing-security}/resources/ADVERSARIAL-REVIEW.md`, `.loa.config.yaml.example`, `tests/unit/adversarial-review-*.bats`): FR-4 only.
- Corpus (`evals/fixtures/review-prs/manifests/*.json`): FR-2 multi-site anchors; `SHA256SUMS` regenerated through `seed-corpus-from-record.sh`; every batch MANIFEST records the corpus hash.

### System Zone authorization (explicit, cycle-level)
This PRD authorizes edits, through `/implement` only, to: `.claude/scripts/adversarial-review.sh`, `.claude/schemas/adversarial-finding.schema.json`, `.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md`, `.claude/skills/auditing-security/resources/ADVERSARIAL-REVIEW.md`, and `.claude/checksums.json` regeneration. No other `.claude/` path. The zone marker `.run/zone-guard-authorization.json` is set by the run and deleted at the close.

### Pin
All cycle-131 arms run the Sprint 2 completion commit of `feature/cycle-131-honest-measurement` (the closed mount, grader 1.3, the dissent anchor/budget change landed) [ASSUMPTION decision] (DEC-0612); the image stays `loa-ablation:258` if the harness is bind-mounted from the source tree (the SDD confirms from `pipeline-run.sh`'s container invocation), else it is rebuilt and the digest recorded.

### Dependencies
Codex credential valid for the batch horizon (KF-048 pre-flight is in the runner); docker and `loa-ablation:258`; the 36 cycle-130 run directories (local; on the record branch minus sandboxes); `record/cycle-130-analysis` for the analysis scripts.

### Constraints inherited
`ablation-grade.sh` reads only the run directory, the task and the key (DEC-0413); the grader never reads `meta/`; smoke rows decide nothing (DEC-0428); the row writer derives `degraded` from `verdict_quality` (bd-ocovl adds the dissent-absent field rather than changing `degraded`).

> Sources: evals/harness/pipeline-run.sh:17, :232, :459, :523-545; evals/harness/lib/sandbox-mount.sh:125-170; evals/harness/ablation-grade.sh header (DEC-0413, DEC-0420); .claude/rules/zone-system.md; cycle-130-brief.md §Prerequisites

---

## Scope & Prioritization

### MVP (this cycle)
FR-1 … FR-7 as written; the three sprints of §Timeline.

### Explicitly out of scope
- Changing any shipped default (dissent on/off, audit gate on/off, budget) — proposals only (G-6).
- Build-task arms (A2, A4–A7) and the hidden-test primary; new corpus PRs; model retargeting; the `/review-sprint` skill's output format (bare and pipeline keep their contracts; the grader rule absorbs the difference).
- Routing small PRs to two bare passes (analysis.md §9 "Not recommended yet": needs two more small PRs first).

### Priority order under a lower cap
B1 (R1 A/B) → the control arm (R5) → `a1_review_only` (R3) → `a1_no_dissent` (R4); a lower cap cuts from the tail (DEC-0611).

> Sources: cycle-131-brief.md §Objective "Out of scope", §Budget; analysis.md §9

---

## Success Criteria

| ID | Criterion | Evidence |
|----|-----------|----------|
| SC-1 | Seven corpus PRs complete both gates under the closed mount with `oracle_closed` true and no grader oracle hit | Sprint 1 smoke log; bats |
| SC-2 | Grader 1.3 re-grades the 36 runs with every `recall_pm3` equal to the stored value; adjudication kappa and share reported | re-graded rows; `adjudication-cycle-131.csv` |
| SC-3 | Replication-01's pre-registered read re-taken on six valid cells after the KF-046 exemption | DEC row beside DEC-0604 |
| SC-4 | Dissent envelopes carry numeric anchors (≥ 80 %) and both voices ran at every review gate of B2's dissent-enabled arms (`a1_full`, `a1_review_only`, `a1_full_openmount` in B1) | envelope scan |
| SC-5 | Four pre-registered reads taken with outcomes quoted verbatim; spend ≤ caps | NOTES, DEC rows, addendum, `spend.sh` |
| SC-6 | No shipped default changed; `evals/tests/` and `tests/unit/` green; PR merged; record branch pushed | diff vs main; CI; `record/cycle-131-…` |

> Sources: Goals table above; cycle-131-brief.md §Sprint breakdown exits

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| The closed mount breaks the pipeline's own gates on PRs that touch pipeline scripts (pr-12: `adversarial-review.sh`; pr-13: the review skill) | the full arm cannot run on exactly the PRs that matter | the SDD picks the overlay mode per the smoke on all seven PRs before Sprint 2; if base-overlay breaks a gate, head-overlay is the fallback (the PR's own code, still no later copy); recorded as a DEC |
| The same-function rule credits unrelated findings | the new ruler over-credits both arms | both rules always reported; the ≥ 80 % adjudication rule gates adoption; the SDD caps the function span (e.g., a function longer than 400 lines falls back to ±20) |
| Dissent anchors change the voices' output quality | fewer or shallower findings | the symbol anchor stays required; the numeric anchor is additional; the smoke compares finding counts with cycle-130 envelopes |
| Budget scaling lets the dissent spend more per gate | cost per run rises | per-run cap USD 20 stands; `budget_scale` is `fixed` in the shipped default and `diff` only in the eval config |
| Bare-Fable costs more than planned (Fable output tokens) | B2 overruns | bare runs are ≈ USD 1–3 each; the batch cap and priority order cut the tail |
| Two different pins (cycle-130 vs cycle-131) tempt pooling | invalid comparison | rows live in separate results roots; the report partitions by pin; the addendum compares re-graded old cells to new cells per PR without pooling |
| KF-048 credential, KF-037 contention, KF-046 scan classes recur | degraded or excluded rows | runner pre-flight; no dissent during batches; the class-7 exemption; any new class read by hand and recorded |

> Sources: cycle-131-brief.md §Risks; known-failures.md KF-037/046/048/049; analysis.md §9

---

## Timeline & Milestones

| Sprint | Content | Exit |
|--------|---------|------|
| 1 — Measurement fixes | FR-1 closed mount + `oracle_closed` + grader oracle check; FR-2 grader 1.3 + manifests + re-grade + adjudication; FR-3 `--allow-partial`, KF-046 class 7 + re-row, `dissent_absent_gates`; FR-4 dissent anchors + `budget_scale` | tests green; 36 runs re-graded; smoke of the seven PRs under the closed mount; replication read re-taken |
| 2 — Arms and batches | FR-5 arms + took-effect; pin recorded; pre-registrations; smoke; B1 then B2 | all rows landed or cut with a reason; spend posted |
| 3 — Reads and addendum | FR-6 reads; FR-7 addendum, DEC rows, beads, CHANGELOG, release notes; PR; record branch | PR merged; record branch pushed; operator reminder for `/decisions confirm` |

> Sources: cycle-131-brief.md §Sprint breakdown

---

## Appendix

### A. Glossary
- **Oracle / the peek** — a copy of a PR-touched file in the sandbox that is later than `pr/head` and already holds the fix (KF-049).
- **The ruler** — the grader's citation rule (±3 lines of an anchor; cycle-131 adds "or inside the labelled function").
- **Price** — a pre-registered comparison of an arm without a component against `a1_full`, read as one of the rule's named outcomes.
- **Pin** — the source commit every arm of a batch runs.

### B. Source documents
- `grimoires/loa/context/cycle-131-brief.md` (the operator's instruction, encoded by the lead)
- `grimoires/loa/reports/ablation-2.0/analysis.md` §§1-9 and its working files on `record/cycle-130-analysis` (`attribution.md`, `sensitivities.md`, `false-positives.md`, `mechanism.md`, `replication.md`, `scripts/oracle_scan.py`)
- `grimoires/loa/known-failures.md` KF-046, KF-048, KF-049; `grimoires/loa/decisions.yaml` DEC-0597, DEC-0602 … DEC-0609
- the harness: `evals/harness/pipeline-run.sh`, `evals/harness/lib/sandbox-mount.sh`, `evals/harness/took-effect.sh`, `evals/harness/run-ablation.sh`, `evals/harness/ablation-grade.sh`, `evals/graders/recall-vs-defects.sh`, `evals/suites/ablation-2.0.yaml`

### C. Interview record (unattended)
Phases 1–7 were answered from the brief and the analysis; the operator's one input was "proceed as you suggest". No question was asked of the operator; every operator-level choice is listed in E.

### D. Open questions for the operator (non-blocking)
- Should `budget_scale: diff` become the shipped default once measured? (G-6 says not this cycle.)
- Is USD 500 the right cap? The batches run in priority order so a lower cap cuts the tail.

### F. Flatline integration (PRD review, 2026-10-19)
Two voices (codex-headless, claude-headless), 13 blockers and 55 items, cross-scoring degraded (KF-041 recurrence 6: `gpt_score` null on every item, agreement 0 %); read by judgment. Integrated (DEC-0621): a within-pin oracle A/B with an open-mount arm (SKP-001/002 gpt and opus IMP-001/002); answer-bearing paths include the fix commit's paths and stray copies are checked (SKP-002/003 opus, IMP-011); pre-run overlay evidence and `mount_mutated` (SKP-004); the read-exposure detector and its validation on the 36 known runs (SKP-003 gpt, IMP-003, opus IMP-009/010); the three-way re-grade into a versioned rows file with original manifests retained and blind anchor curation (SKP-007, IMP-002, IMP-021, opus IMP-013); interval-based, mutually exclusive, ordered pricing rules with the unit, pairing, exclusion, minimum cells and the pre-committed decision statistic (SKP-011/012/015, IMP-009/010/011/013, opus IMP-003/004/008/021/025); manifest regeneration after the overlay (SKP-004 gpt); per-row disclosure of the overlay mode and of gate scripts run at the PR's version, and the move of the batches to pr-17/pr-18 (SKP-001 opus, IMP-006/007/008); the `budget_scale` formula with a hard maximum (opus IMP-017, gpt IMP-023); the span cap, range rule and nested-function semantics in FR-2 (opus IMP-015/016, gpt IMP-016/017); the adjudication protocol with a kappa floor (gpt IMP-018/019, opus IMP-014); precision and finding volume beside recall (gpt IMP-028); models per phase recorded and the pin defined (gpt IMP-029, opus IMP-019/024); the class-7 exemption at line level (opus IMP-018, gpt IMP-020); the replication re-take with the oracle exclusion as a second line (opus IMP-012); content-addressed pre-registration (gpt IMP-030). Declined: adjudicating every function-rule credit (cost; the sample with a kappa floor stands); a formal non-inferiority design beyond the interval rules (the sample is what the budget buys; the rules say "inconclusive" honestly).

### E. Decisions taken on the operator's behalf
- **D1** [ASSUMPTION decision] (DEC-0610) — unattended planning on the templates; no `/ride`.
- **D2** [ASSUMPTION decision] (DEC-0611) — cap USD 500, batches ≤ 250, run cap 20, concurrency 3.
- **D3** [ASSUMPTION decision] (DEC-0612) — one pin for every cycle-131 arm (the Sprint 2 completion commit); cycle-130 rows re-graded, never pooled.
- **D4** [ASSUMPTION decision] (DEC-0620) — batch allowance USD 275 of the 500 cap (amends D2) to afford the within-pin open-mount arm.
- **D5** [ASSUMPTION decision] (DEC-0621) — the Flatline PRD blockers integrated as listed in Appendix F.

> Sources: decisions.yaml DEC-0610 … DEC-0612; cycle-131-brief.md
