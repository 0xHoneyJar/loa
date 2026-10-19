# Sprint Plan: Honest review-catch measurement (cycle-131)

**Version:** 1.0
**Date:** 2026-10-19
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** grimoires/loa/prd.md
**SDD Reference:** grimoires/loa/sdd.md (1.1)
**Ledger:** cycle `cycle-131-honest-measurement`, sprints global 263 / 264 / 265 (local sprint-1 … sprint-3)
**Execution:** `/run sprint-plan`, push AUTO; Opus 5.5 implementers in linked worktrees returning `git diff --cached --binary` patches; the lead applies, reviews and audits on Fable 5.1; at most three dissent runs per sprint; no dissent while a batch runs (KF-037)
**Task kinds:** every task carries `kind: mechanical | judgment | operator` (DEC-0144); no `operator` task exists because the operator's instruction ("proceed as you suggest") authorised the cycle end to end and every operator-level choice is an `[ASSUMPTION decision]` DEC row (prd.md Appendix E)
**Spend:** cycle cap USD 500; batches ≤ 275 (DEC-0611, DEC-0620); Sprint 1 smoke ≈ 90 (DEC-0614); review-catch run cap USD 20; halt only above the cap
**System Zone authorization:** `.claude/scripts/adversarial-review.sh`, `.claude/schemas/adversarial-finding.schema.json`, the two `ADVERSARIAL-REVIEW.md` resources, `.claude/checksums.json` regeneration — Task 1.8 only (prd.md §Technical Considerations)
**Flatline integration:** PRD run → DEC-0621 (prd.md Appendix F); SDD run → DEC-0622, DEC-0623 (sdd.md §11.E); sprint run → §Appendix D

---

## Executive Summary

Three sprints make the review-catch measurement honest, then price the two expensive gates against a control that separates the model from the pipeline. Sprint 1 (global 263) changes the eval harness and the dissent contract: the sandbox stops carrying any later-than-head copy of an answer-bearing path and a took-effect rule plus a grader detector prove it; the grader credits a citation inside the labelled definition and reports three results per grade; the runner accepts a partial suite root; the contamination scan stops firing on the PR's own repository name; the dissent voices are asked for line anchors with a budget that fits real diffs; the 36 cycle-130 runs are re-graded into a versioned file and a blind adjudication decides the rule. Sprint 2 (264) declares four arms, freezes the cycle-131 suite root, smokes, pre-registers and runs two batches under one pin. Sprint 3 (265) takes the four pre-registered reads, writes the addendum and ships the PR and the record branch. No shipped default changes.

> Sources: prd.md §Executive Summary, §Timeline & Milestones; sdd.md §8

---

## Sprint Overview

| Sprint | Global | Theme | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| 1 | 263 | Measurement fixes | closed mount + `oracle_closed` + grader detector; grader 1.3 three-result rule; manifests v1 + blind multi-site anchors; row writer 1.4 / report 1.3; `--allow-partial`; KF-046 class 7; dissent anchors + `budget_scale`; re-grade + adjudication; seven-PR smoke | none |
| 2 | 264 | Arms and batches | four arms + toggles + took-effect rules; `ablation-2.0-c131` suite root frozen and self-checked; arm smoke; pin; pre-registrations; B1 then B2; spend posts; envelope and oracle scans | Sprint 1 |
| 3 | 265 | Reads and addendum | the four reads with DEC rows; `analysis.md` §10 addendum; CHANGELOG and release notes; beads closed; PR; record branch; E2E goal validation | Sprint 2 |

> Sources: prd.md §Timeline & Milestones; sdd.md §8

---

## Sprint 1: Measurement fixes (global 263)

**Duration:** 1.5 days
**Dates:** 2026-10-19 – 2026-10-21

### Sprint Goal
Make every later number honest: no answer copy in the sandbox (proven per run), a citation rule that credits the labelled definition, a dissent that can be credited and can run, a runner that accepts the cycle's suite roots, and the 36 existing runs re-graded under both rules with a blind adjudication of what the new rule adds.

### Deliverables
- [ ] `evals/harness/lib/sandbox-mount.sh`: `overlay_answer_paths`, `check_mount_closed`, toggles `bare_model`, `dissent`, `oracle_open`; `evals/harness/pipeline-run.sh` wiring, evidence lines, pre-launch refusal; `task.yaml` `review_catch.overlay_mode`
- [ ] `evals/harness/took-effect.sh`: rules `oracle_closed`, `oracle_open_recorded`, `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope`
- [ ] `evals/harness/ablation-grade.sh`: oracle detector (diff and read forms), KF-046 class 7 line-level exemption, three recall results, `grader_version`, `corpus_sha256`; `evals/graders/recall-vs-defects.sh` 1.3.0
- [ ] `evals/fixtures/review-prs/manifests/v1/` (originals) and the curated multi-site anchors in `manifests/pr-*.json`; `SHA256SUMS` regenerated
- [ ] `evals/harness/ablation-row.sh` 1.4 and `evals/harness/ablation-report.py` 1.3 (fields, partitions, no pooling across rules, sensitivities, ≥ 4 cells)
- [ ] `evals/harness/run-ablation.sh --allow-partial` recorded in MANIFEST
- [ ] `.claude/scripts/adversarial-review.sh` numeric anchors and `budget_scale` / `budget_cents_max`; schema; docs; `.loa.config.yaml.example`; the eval config variant written by the harness
- [ ] `evals/results/ablation-2.0/regrade-c131/rows.jsonl` (36 runs, three results) and the regression proof; the replication re-take DEC
- [ ] `grimoires/loa/a2a/sprint-1/adjudication/` (protocol, packets, two label files, kappa) and the rule-adoption DEC
- [ ] the seven-PR closed-mount smoke log with `gate_scripts_at_pr_version` per PR and any per-task fallback DEC
- [ ] `evals/tests/` and `tests/unit/` green with the new cases; CHANGELOG `[Unreleased]`

### Acceptance Criteria
- [ ] PRD FR-1 AC 1–6 (overlay, evidence before the first phase, `oracle_closed` clauses a–d, detector forms a–b, detector validation flags exactly the three known runs, bats, seven-PR smoke)
- [ ] PRD FR-2 AC 1–4 (grader 1.3 outputs and tests; versioned re-grade with every `recall_pm3_v1` equal to the stored value; adjudication protocol run with kappa and share reported)
- [ ] PRD FR-3 AC 1–3 (`--allow-partial` dry run passes on the replication root; the two replication rows re-graded clean into the versioned file; the re-take DEC beside DEC-0604)
- [ ] PRD FR-4 AC 1–3 (anchors and budget change with tests; example config; shipped default `fixed`)
- [ ] `evals/tests/` (447 + new) and `tests/unit/` green; `bash -n` on every changed script; `validate-suite.sh` on both suite roots

### Technical Tasks

- [ ] Task 1.1: Implement `overlay_answer_paths <ws> <fixture-dir> <mode>` and `check_mount_closed` in `sandbox-mount.sh` (answer set from head.diff headers with quoted/renamed//dev/null/binary handling plus `pr/head`, `pr/base` and `git show --name-only <fix_commit>`; `.claude/**` scope; head mode default, base per `task.yaml` `review_catch.overlay_mode`; deletions and fix-commit paths via `git show <head_commit>:<path>`; evidence lines `mount_overlay`, `overlay_sha256=`, `gate_scripts_at_pr_version`, `copy_source`), wire the overlay into `pipeline-run.sh` for review-catch mounted arms after `mount_prompt_surface` and before toggles, config writes and `regen_sandbox_manifest`, run `check_mount_closed` AFTER those three steps (the checked surface is the launched one) and refuse the launch (`infra`) when it fails, and add the toggles `bare_model`, `dissent`, `oracle_open` to `apply_arm_toggles`; bats cases for every path shape and toggle → **[G-1, G-4, G-5]** ⇐ none · kind: mechanical
- [ ] Task 1.2: Add took-effect rules `oracle_closed` (clauses a–d against the immutable fixture and `meta/` evidence; clause d = the sandbox `.git` holds exactly the base commit, no remote, `git fsck --unreachable --no-reflogs` empty, no packed later objects), `oracle_open_recorded`, `bare_model_fable` (model and `effort_requested: high`), `review_only_phases`, `no_review_dissent_envelope` (audit envelope present with voices) to `took-effect.sh` with pass and fail fixtures → **[G-1, G-4, G-5]** ⇐ Task 1.1 · kind: mechanical
- [ ] Task 1.3: Implement the grader oracle detector in `ablation-grade.sh` (diff form and read form, Bash and `Read`/`Grep` tool events, tool_use↔tool_result correlation, `exposed_unknown`, `oracle_exposed_defects` / `oracle_exposed_events`), the KF-046 class 7 line-level exemption with `contamination_exempt[]`, `grader_version` and `corpus_sha256` in `grade.json`; validate the detector over the 36 cycle-130 run directories (the three known runs `priority-v2-p1-a1_full-review-04-t2`, `replication-01-a1_full-review-r17-t1`, `replication-01-a1_full-review-r18-t1` must be flagged and no bare run may be; any additional full-arm hit is read by hand and recorded as a finding, not as a detector defect) and pin the known cases with trimmed transcript fixtures in `evals/tests/ablation-grade.bats`; `exposed_unknown` rows are excluded pairwise from primary reads and listed in a sensitivity → **[G-1]** ⇐ none · kind: mechanical
- [ ] Task 1.4: Ship `recall-vs-defects.sh` 1.3.0 (citation validity, 25-line range rule, same-scope clause with header-line identity, end-of-definition detection, nested → innermost, 400-line cap → ±20, no-regex file types → ±20, three results `recall_pm3_v1` / `recall_pm3` / `recall` with `detected`/`missed` each and `credits_function_only`) and bump `ablation-grade.sh` to write them; red-first cases in `evals/tests/eval-recall-grader.bats` for every clause → **[G-2]** ⇐ none · kind: mechanical
- [ ] Task 1.5: Snapshot the eighteen corpus manifests to `manifests/v1/`, then curate multi-site `anchors[]` for pr-05 … pr-18 blind from each defect's `label_source` line and the record review text on the record branches (never from cycle-130 outputs), re-stamp `approved_by`, regenerate `SHA256SUMS` through `seed-corpus-from-record.sh`, and write the curation note (`grimoires/loa/a2a/sprint-1/anchors-curation.md`: per defect the lines added and the review sentence they come from) → **[G-2]** ⇐ none · kind: judgment
- [ ] Task 1.6: Row writer 1.4 (`defect_catch_rate` = new rule, `_pm3`, `_pm3_v1`, the three missed lists, `credits_function_only`, `oracle_exposed_defects`, `dissent_absent_gates`, `dissent_absent_reason`, `grader_rule`, `grader_version`, `corpus_sha256`, `config_variant`, `overlay_mode`, `gate_scripts_at_pr_version`) and report 1.3 (three rules with the decision statistic named, `--pin`, partition and refusal to pool across `grader_rule`/`source_commit`, "oracle-exposed cells excluded" and "dissent-absent gates excluded" sensitivities with planned absence never excluded, ≥ 4 valid cells, precision and finding volume per arm) with bats and the report fixtures; `exposed_unknown` counts as exposed for exclusion; exclusion counts per arm printed beside every read → **[G-2, G-5]** ⇐ Task 1.3, Task 1.4 · kind: mechanical
- [ ] Task 1.7: Add `--allow-partial` to `run-ablation.sh` (freeze check and every grader argv; relaxes only the four-per-type count; `MANIFEST.json.allow_partial`; kept on `--resume`) with bats cases; confirm the dry run on `grimoires/loa/evals/ablation-2.0-replication` passes with the flag and is refused without it → **[G-1, G-2]** ⇐ none · kind: mechanical
- [ ] Task 1.8: In `adversarial-review.sh` ask every voice for `anchor_line` / `anchor_line_end` beside `anchor`/`anchor_type`, keep integers only in `_normalize_finding_for_validation`, extend `adversarial-finding.schema.json`, add `flatline_protocol.<gate>.budget_scale: fixed|diff` and `budget_cents_max` (default 600; `budget_cents = min(max(configured, ceil(estimate × 1.2)), max)`; `budget_exceeded` reason `budget` above the max) with the shipped default `fixed`, document both in the two `ADVERSARIAL-REVIEW.md` resources and `.loa.config.yaml.example`, write the eval config variant (`budget_scale: diff` for both gates) from the harness for every mounted arm and record `config_variant: eval`, extend the grader's envelope reduction to read `anchor_line` with the anchor's path, regenerate `.claude/checksums.json`; `tests/unit/adversarial-review-*.bats` cases for a numeric anchor parsed, a symbol-only anchor kept, the scaled budget and the maximum → **[G-3]** ⇐ none · kind: mechanical
- [ ] Task 1.9: Two-step re-grade: (0) verify `manifests/v1/` byte-equals the manifests the cycle-130 batches graded against (`git show ba11b860:evals/fixtures/review-prs/manifests/pr-NN.json`); (1) regression — grader 1.3 with `manifests/v1/` over the 36 cycle-130 review-catch run directories must reproduce every stored `recall` as `recall_pm3_v1` (a mismatch stops the sprint: one fix attempt within the sprint, then halt); (2) versioned re-grade into `evals/results/ablation-2.0/regrade-c131/rows.jsonl` with the current manifests (shipped rows and grade.json files untouched), then the replication re-take under the old rule and original anchors on six valid cells with the oracle-exposed cells excluded as a second line, recorded as a DEC beside DEC-0604 → **[G-2]** ⇐ Task 1.3, Task 1.4, Task 1.5, Task 1.6, Task 1.7 · kind: mechanical
- [ ] Task 1.10: Pre-register the adjudication protocol in NOTES (deduplication key (run, defect); 20 packets stratified by arm and PR from `credits_function_only` plus up to 10 from the credits anchor expansion alone adds (`detected_pm3` minus `detected_pm3_v1`), seed 20261015, an empty stratum redistributed, fewer eligible than planned → all of them; blind packets; codebook; two independent Opus 5.5 labelers with recorded prompts; kappa < 0.6 → a third labeler, still < 0.6 → the rule is not adopted; adopt iff ≥ 80 % of the function-only packets are "the labelled defect", with a Wilson 95 % interval reported), run it, and record the rule-adoption DEC (adopt → `recall` stays the decision statistic; else `recall_pm3` becomes it for every Sprint 2 pre-registration and Sprint 3 read) → **[G-2]** ⇐ Task 1.9 · kind: judgment
- [ ] Task 1.11: Run the closed-mount smoke — one `a1_full` trial on each of exactly these seven PRs: pr-05, pr-08, pr-12, pr-13, pr-16, pr-17, pr-18 (pr-14 and pr-15 stay unused) — through `run-ablation.sh --smoke` on a smoke root (a smoke batch counts as an evaluation context), with a per-PR expected-dissent table written first (both voices expected under `budget_scale: diff` on every PR; pr-12 runs the PR's own dissent script), read each run's gate completion, `oracle_closed`, `gate_scripts_at_pr_version`, the numeric-anchor share (numerator: findings with an integer `anchor_line`; denominator: all findings of dissent-enabled gates) and voices, decide any per-task `base` fallback with a DEC, and post the spend (≈ USD 90) in NOTES → **[G-1, G-3]** ⇐ Task 1.1, Task 1.2, Task 1.3, Task 1.4, Task 1.6, Task 1.8 · kind: judgment
- [ ] Task 1.12: Run `evals/tests/` and `tests/unit/` to green, `validate-suite.sh` on both roots, `bash -n` on every changed script, add the CHANGELOG `[Unreleased]` entries for FR-1 … FR-4 and the `budget_scale` knob, and update `grimoires/loa/evals/ablation-2.0/README.md` for the new grader fields → **[G-6]** ⇐ Task 1.1, Task 1.2, Task 1.3, Task 1.4, Task 1.6, Task 1.7, Task 1.8 · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `overlay_answer_paths` on a fixture-shaped sandbox: the overlaid tree and `arm_evidence` lines | wrong answer set (missed rename, quoted path, fix-commit path), stray later copy, missing evidence, wrong mode | whether a model reads the mount at all | `evals/tests/sandbox-mount.bats` (existing toggle cases) |
| `took-effect.sh oracle_closed` exit code and message on pass/fail fixtures | an unmodified mount, a stray copy, a mutated path, a second commit in the sandbox `.git` | an exposure through a channel the inventory does not cover | `evals/tests/took-effect.bats` |
| `ablation-grade.sh` oracle detector output on synthetic and real transcripts | a covering diff, a later-line read, `diff -q` and `cat pr/head.diff` as non-hits, the three known runs flagged and no bare run | a paraphrased recollection of the fixed code with no tool output | `evals/tests/ablation-grade.bats`; the 36 run directories |
| `recall-vs-defects.sh` JSON on crafted findings files | same-scope credit, next-function non-credit, nested scope, 400-line cap, 40-line range, markdown section, `manifests/v1/` for `_pm3_v1` | semantic correctness of a credited finding (the adjudication's job) | `evals/tests/eval-recall-grader.bats` |
| `ablation-row.sh --validate` and `ablation-report.py --partial` on fixture rows | missing fields, pooling across rules or pins, planned dissent absence excluded by mistake, < 4 cells not reported | the arms' behaviour | `evals/tests/ablation-row.bats`, `ablation-report.bats` |
| `run-ablation.sh --dry-run` on the replication root | `--allow-partial` not passed to the freeze check or the grader; MANIFEST field absent | a batch-time failure | `evals/tests/run-ablation.bats` |
| `adversarial-review.sh` normaliser and budget gate on stub envelopes | non-integer anchors kept, numeric anchors dropped, budget not scaled, maximum not enforced, shipped default changed | a voice that ignores the prompt (the smoke measures the share) | `tests/unit/adversarial-review-normalise.bats`, `adversarial-review-companion.bats` |

### Dependencies
- None (first sprint). External: docker and `loa-ablation:258`; the codex credential for the smoke's dissent; the 36 cycle-130 run directories and `record/cycle-130-analysis` (the detector's validation set and `oracle_scan.py` as the reference implementation).

### Security Considerations
- **Trust boundaries**: `head.diff` headers, PR files and transcripts are untrusted data — parsed with validated paths (no absolute, no `..`, no symlink following), never evaluated; the overlay writes only inside the sandbox copy; the detector's regexes run over text.
- **External dependencies**: none added; `git show` reads the local repository only.
- **Sensitive data**: none; the per-run HOME still carries the codex access token only (KF-048 fix, unchanged).
- **System Zone**: Task 1.8 is the only `.claude/` edit, inside the PRD's authorization; the zone marker is set by the run and deleted at the close.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| A head-version gate script breaks a gate on pr-12 or pr-13 in the smoke | Med | Med | per-task `base` fallback recorded by DEC; those PRs are re-grade only |
| `recall_pm3_v1` does not reproduce a stored value | Low | High | the regression step stops the sprint; the grader is fixed before any re-grade |
| The detector flags a fourth cycle-130 run or misses one of the three | Med | Med | the validation is a bats case; the detector is tuned on synthetic cases, never on the three runs' text |
| Numeric anchors change the voices' output quality | Med | Low | the symbol anchor stays required; the smoke compares finding counts with cycle-130 envelopes |
| Smoke spend above ≈ USD 90 | Low | Low | run caps; the smoke is seven single trials |

### Success Metrics
- `oracle_closed` true and detector empty on all seven smoke runs; both gates complete on each
- 36/36 `recall_pm3_v1` equalities; the versioned re-grade file exists; adjudication kappa and share recorded
- Dissent envelopes on the smoke: ≥ 80 % numeric anchors; both voices on the review gate of pr-13/pr-17/pr-18
- `evals/tests/` ≥ 447 + new cases green; `tests/unit/` green

---

## Sprint 2: Arms and batches (global 264)

**Duration:** 1 day
**Dates:** 2026-10-21 – 2026-10-22

### Sprint Goal
Declare and prove the four arms, freeze the cycle-131 suite root, record one pin, pre-register the two batches and run them under the closed mount within the batch allowance.

### Deliverables
- [ ] `evals/suites/ablation-2.0.yaml`: `a0_bare_fable`, `a1_review_only`, `a1_no_dissent`, `a1_full_openmount` (eval-only) with phases, toggles and took-effect rules; `a1_full` with `oracle_closed`
- [ ] `grimoires/loa/evals/ablation-2.0-c131/` (review-r17, review-r18; REVIEW.md copy notes; `MANIFEST.sha256`; self-check log 6/6)
- [ ] Arm smoke rows (one trial per new arm on pr-17) with every took-effect rule true
- [ ] NOTES pre-registrations for B1 and B2 with section sha256, the pin, and DEC rows; `MANIFEST.json` of both batches
- [ ] Batch rows under `evals/results/ablation-2.0/c131-b1-oracle-ab/` and `c131-b2-control-prices/`; spend posts; the envelope and oracle scans

### Acceptance Criteria
- [ ] PRD FR-5 AC 1–2 (suite validates; toggles implemented and tested; `a1_full_openmount` refused outside an evaluation batch; smoke trial per arm with rules true)
- [ ] PRD FR-6 AC 1–3 (pre-registration refs dated before the first rows with sha256 in MANIFEST; budget B1 ≈ 48, B2 ≈ 220, total ≤ 275; every row's `oracle_exposed_defects` empty except the open-mount arm, took-effect true, dissent fields and models recorded)
- [ ] One `source_commit` in both MANIFESTs; `copy_source` equals it on every row

### Technical Tasks

- [ ] Task 2.1: Declare the four arms in `evals/suites/ablation-2.0.yaml` (phases, toggles, `took_effect`, `eval_only: true` on the open-mount arm), map `bare_model: fable` to the BARE phase model in `pipeline-run.sh`, refuse `eval_only` arms outside a `run-ablation.sh` batch or smoke (`pipeline-run.sh` run by hand refuses them), extend `validate-suite.sh` for the new keys, and state the full took-effect rule set per arm in the suite; bats cases → **[G-4, G-5]** ⇐ none · kind: mechanical
- [ ] Task 2.2: Build `grimoires/loa/evals/ablation-2.0-c131/` from the replication root's `review-r17` and `review-r18` (task.yaml, TASK.md, REVIEW.md plus a one-line copy note), `README.md`, freeze with `--allow-partial`, run the image self-check (6/6) into `grimoires/loa/a2a/sprint-2/self-check-c131.log`; the pin is the commit that contains this root, the manifests, the grader, the report code and the eval-config variant → **[G-4, G-5]** ⇐ none · kind: mechanical
- [ ] Task 2.3: Run one smoke trial per new arm on review-r17 (pr-17; `--smoke` root copy), read the took-effect rules, the envelopes (`a1_full_openmount` shows `oracle_exposed_defects` when it peeks; `a1_no_dissent` shows the audit envelope with voices) and the models per phase, apply the batch-entry gates (every rule true; numeric-anchor share ≥ 80 % on the dissent-enabled arm; both voices at the review gate) and record the arm readiness in NOTES → **[G-4, G-5]** ⇐ Task 2.1, Task 2.2 · kind: judgment
- [ ] Task 2.4: Run the Sprint 2 review and audit dissent BEFORE any batch (KF-037), record the pin (the commit after Tasks 2.1 and 2.2 on the cycle branch; any later harness, grader or framework fix re-pins and re-runs the affected batch — no exception) in NOTES, write the cycle spend ledger (smoke ≈ 90, arm smoke ≈ 30, adjudication ≈ 10, B1 ≈ 48, B2 ≈ 220, gates' own cost, against 500) and the B1 and B2 pre-registrations (rules verbatim from prd.md FR-6; the decision statistic named from Task 1.10's DEC; the unit = the planted defect with trials averaged; exclusions = only the pre-registered validity failures, with exclusion counts per arm and an all-rows sensitivity reported to show any selection effect; caps; the cell matrix below; expected dissent status per PR; retries retained with their cost) with their section sha256 in DEC rows, dry-run and launch B1 then B2 detached with `--allow-partial`, watch, post spend after each, and apply the first-cut rule if B1 overruns → **[G-1, G-4, G-5]** ⇐ Task 2.3 · kind: judgment
- [ ] Task 2.5: Scan every batch row's envelopes (numeric-anchor share, `voices_succeeded`, `dissent_absent_reason`) and run the grader's oracle report over the batch run directories, writing `grimoires/loa/a2a/sprint-2/batch-scans.md` → **[G-3]** ⇐ Task 2.4 · kind: mechanical

### Cell matrix and reads (pre-registered in Task 2.4)
| batch | arm | review-r17 (pr-17, 20 defects) | review-r18 (pr-18, 8 defects) | reads served |
|---|---|---|---|---|
| B1 | `a1_full_openmount` | 3 | — | R1 (vs B2's `a1_full` × r17) |
| B2 | `a0_bare` | 3 | 3 | R5 |
| B2 | `a0_bare_fable` | 3 | 3 | R5 |
| B2 | `a1_full` | 3 | 3 | R1, R3, R4, R5 |
| B2 | `a1_review_only` | 3 | 3 | R3 |
| B2 | `a1_no_dissent` | 3 | 3 | R4 |

| read | question | contrast | defects | statistic | outcomes (prd.md FR-6) |
|---|---|---|---|---|---|
| R1 | did the oracle inflate the catch? | closed − open on pr-17 | 20 | the Task 1.10 statistic, 90 % defect bootstrap | inflated / no measurable inflation / investigate |
| R5 | does the model explain the lift? | bare-Fable vs `a1_full` and vs `a0_bare` | 28 | same | model explains / gates earn their cost / between |
| R3 | what does the audit gate buy? | `a1_review_only` − `a1_full`, cost ratio | 28 | same | propose opt-in / keep / inconclusive |
| R4 | what does the dissent buy? | `a1_no_dissent` − `a1_full` | 28 | same | investigate / propose opt-in / keep / inconclusive |

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `validate-suite.sh` on the suite file with the four arms | an unknown toggle, a missing took-effect rule id, an eval-only arm without the flag | an arm that validates but does not take effect (the smoke's job) | `evals/tests/validate-suite.bats` |
| `pipeline-run.sh --dry-run` plan for each new arm | wrong BARE model, wrong phase set, overlay applied to the open-mount arm | runtime behaviour | `evals/tests/pipeline-run.bats` |
| `run-ablation.sh --dry-run` on the c131 root | hard gate (self-check lines, REVIEW.md), `--allow-partial` missing, cap arithmetic | provider behaviour | `evals/tests/run-ablation.bats` |

### Dependencies
- Sprint 1: every harness change merged on the cycle branch; the smoke's per-task fallback decisions.
- External: codex credential valid for the batch horizon (runner pre-flight); Fable 5.1 access at concurrency 3.

### Security Considerations
- **Trust boundaries**: batch rows and envelopes are data; the pre-registration text is hashed so a later edit is visible.
- **External dependencies**: none added.
- **Sensitive data**: the per-run HOME credential copy (unchanged).

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| B1 overruns and B2 is cut | Low | Med | first cut `a1_review_only` on pr-18; priority order recorded |
| A harness fix is needed between B1 and B2 | Low | High | one-pin policy: re-run B1 at the new pin or run B2 without the fix (DEC) |
| Fable 5.1 rate limits on the bare-Fable arm | Low | Med | concurrency 3; the runner's transport retry |

### Success Metrics
- 6 B1 + 30 B2 rows landed or cut with a reason; batch spend ≤ USD 275
- `oracle_exposed_defects` empty on every closed-mount row; `oracle_closed` true on all
- Both voices on every review gate of the dissent-enabled arms on pr-17 and pr-18

---

## Sprint 3 (Final): Reads and addendum (global 265)

**Duration:** 0.5 day
**Dates:** 2026-10-22

### Sprint Goal
Take the four pre-registered reads, write the addendum beside the shipped report, record every decision, close the beads, ship the PR and the record branch, and validate all PRD goals end-to-end.

### Deliverables
- [ ] `grimoires/loa/reports/ablation-2.0/analysis.md` §10 "cycle-131 addendum" (re-grade table with three rules, oracle A/B, control reading, two prices with rules quoted, adjudication, spend); `report.md` untouched
- [ ] DEC rows per read; the seven `cycle-131-candidate` beads closed or re-labelled with outcomes; KF-049 / KF-046 / KF-041 attempts rows
- [ ] CHANGELOG `[Unreleased]` and release notes for the harness changes and the `budget_scale` knob (shipped default unchanged)
- [ ] PR merged on green CI; `record/cycle-131-honest-measurement` built with the temporary-index recipe and pushed; `evals/tests/` and `tests/unit/` green at the close

### Acceptance Criteria
- [ ] Each read's outcome text matches its pre-registration verbatim; the decision statistic is the one Task 1.10's DEC named
- [ ] PRD FR-7 AC 1–2 (validators pass; CHANGELOG lists FR-1 … FR-5 — the lead writes each sprint's entries at integration; no shipped default changed — the diff against `main` shows only the optional knob with its `fixed` default and the additive anchor fields)
- [ ] Task 3.E2E documents evidence for G-1 … G-6

### Technical Tasks

- [ ] Task 3.1: Run `ablation-report.py --partial --pin <sha>` on each batch's rows, apply the pre-registered rules in their written order, write one DEC row per read quoting the outcome branch verbatim, and append the spend post → **[G-4, G-5]** ⇐ none · kind: mechanical
- [ ] Task 3.2: Write the addendum (`analysis.md` §10) with an ELI5 paragraph first, the re-grade table, the oracle A/B, the control reading, the two prices, the adjudication result and spend; update the release notes and CHANGELOG; close or re-label the `cycle-131-candidate` beads; add the KF attempts rows → **[G-6]** ⇐ Task 3.1 · kind: judgment
- [ ] Task 3.3: Open the PR (docs, suite roots, decisions, known-failures, harness and the authorized framework files), wait for CI, admin-merge, run the repository's secret scanner (`gitleaks` via the existing tooling, or `tools/`'s redaction check) over the record tree before publishing it, build and push the record branch (a2a/sprint-1…3, the batch records minus sandboxes and minus any HOME copy, NOTES, archive/notes), delete the zone marker, archive the cycle → **[G-6]** ⇐ Task 3.E2E · kind: mechanical

### Task 3.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1 … G-6)

**Description:**
Validate that every PRD goal is achieved through the complete implementation.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Close the peek, proven per run | `oracle_closed` on every batch trial; detector output over every batch run dir; the three-run validation case | all true; empty except the open-mount arm; bats green |
| G-2 | Fix the ruler, both rules reported | the regression equalities; the versioned re-grade file; the adjudication DEC | 36/36; file present; kappa and share recorded |
| G-3 | Dissent measurable | envelope scan over B1/B2 rows | ≥ 80 % numeric anchors; both voices on dissent-enabled review gates |
| G-4 | Model separated from pipeline | `a0_bare_fable` rows and the R5 read | 6 rows; one named outcome |
| G-5 | Gates priced under pre-registered rules | R3 and R4 reads; MANIFEST refs | outcomes quoted verbatim; refs dated before the rows |
| G-6 | No shipped default changes | diff vs `main` of `.loa.config.yaml`, every `SKILL.md` frontmatter, the suite's shipped arms, `adversarial-review.sh`'s defaults | only the optional `budget_scale`/`budget_cents_max` keys with defaults `fixed`/600; the additive `anchor_line` fields are a listed schema extension, not a default change |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence
- [ ] Integration points verified (rows → report → addendum → DEC)
- [ ] No goal marked as "not achieved" without explicit justification

- [ ] Task 3.E2E: End-to-end goal validation of G-1 … G-6 with the evidence table above, written to `grimoires/loa/a2a/sprint-3/e2e.md` BEFORE the PR is opened (a post-publication check of the record branch and the archive is appended after Task 3.3) → **[G-1, G-2, G-3, G-4, G-5, G-6]** ⇐ Task 3.2 · kind: judgment

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `ablation-report.py` decision lines on the batch rows | a rule applied out of order, pooling across pins or rules, a missing sensitivity | the correctness of the arms themselves | `evals/tests/ablation-report.bats` |
| `validate-artifact.sh` on the three planning artefacts and the addendum's cited DEC ids | a decision tag without a ledger row | prose quality | `tests/unit/validate-artifact*.bats` |

### Dependencies
- Sprint 2: both batches landed or cut with a reason.

### Security Considerations
- **Trust boundaries**: none new; the addendum quotes transcripts as data.
- **External dependencies**: none.
- **Sensitive data**: none.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| A read lands on "inconclusive" or "insufficient" | Med | Low | reported as such; the rule's named branch, not a softened reading |
| CI red on the PR | Low | Low | fix in the PR phase (the narrow exception); re-run |

### Success Metrics
- Four outcome DEC rows; addendum merged; record branch pushed; validators and tests green

---

## Risk Register
| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | Head-version gate script breaks a gate on pr-12/pr-13 | 1 | Med | Med | per-task `base` fallback; re-grade only for those PRs | lead |
| R2 | Grader regression (`recall_pm3_v1` ≠ stored) | 1 | Low | High | stop-the-sprint rule | lead |
| R3 | Same-scope rule credits unrelated findings | 1 | Med | Med | 400-line cap, 25-line ranges, adjudication gate | lead |
| R4 | Dissent cost rises under `budget_scale: diff` | 1-2 | Med | Low | `budget_cents_max` 600; USD 20 run cap; eval-only variant | lead |
| R5 | Batch overrun | 2 | Low | Med | priority order and first cut recorded | lead |
| R6 | Two pins in one read | 2-3 | Low | High | one-pin policy; report refuses to pool | lead |
| R7 | KF-048/037/046 recurrences | 1-2 | Med | Low | runner pre-flight; no dissent during batches; class-7 exemption; hand reads | lead |

---

## Success Metrics Summary
| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Smoke runs with `oracle_closed` true and detector empty | 7/7 | took-effect + grade.json | 1 |
| Regression equalities | 36/36 | re-grade step 1 | 1 |
| Adjudication | kappa and share recorded; rule DEC | labels CSV | 1 |
| Numeric-anchor share in envelopes | ≥ 80 % | envelope scan | 1-2 |
| Batch rows | 36 landed or cut with a reason; ≤ USD 275 | STATUS.json, spend posts | 2 |
| Reads | 4 outcomes quoted verbatim | DEC rows, addendum | 3 |
| Tests | `evals/tests/` and `tests/unit/` green | bats | 1-3 |

---

## Dependencies Map
```
Sprint 1 (263) ──────────▶ Sprint 2 (264) ──────────▶ Sprint 3 (265)
   │ harness + grader +        │ arms + suite root +       │ reads + addendum +
   │ dissent contract +        │ pin + pre-registrations   │ PR + record branch
   └ re-grade + adjudication   └ B1 then B2                └ E2E
```

---

## Appendix

### A. PRD Feature Mapping
| PRD Feature (FR-X) | Sprint | Status |
|--------------------|--------|--------|
| FR-1 closed mount | Sprint 1 (Tasks 1.1–1.3, 1.11) | Planned |
| FR-2 grader rule and labels | Sprint 1 (Tasks 1.4–1.6, 1.9, 1.10) | Planned |
| FR-3 harness follow-ups | Sprint 1 (Tasks 1.3, 1.6, 1.7, 1.9) | Planned |
| FR-4 dissent anchors and budget | Sprint 1 (Task 1.8) | Planned |
| FR-5 arms | Sprint 2 (Tasks 2.1–2.3) | Planned |
| FR-6 batches | Sprint 2 (Tasks 2.4–2.5) | Planned |
| FR-7 addendum and records | Sprint 3 (Tasks 3.1–3.3) | Planned |

### B. SDD Component Mapping
| SDD Component | Sprint | Status |
|---------------|--------|--------|
| Sandbox materialiser (§1.4) | Sprint 1 | Planned |
| Took-effect rules | Sprint 1 | Planned |
| Grader and recall rule | Sprint 1 | Planned |
| Row writer and report | Sprint 1 | Planned |
| Runner `--allow-partial` | Sprint 1 | Planned |
| Adversarial review | Sprint 1 | Planned |
| Corpus manifests | Sprint 1 | Planned |
| Suite arms and c131 root | Sprint 2 | Planned |
| Batches and reads (§5.3) | Sprints 2–3 | Planned |

### C. PRD Goal Mapping
| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Close the peek | Sprint 1: 1.1, 1.2, 1.3, 1.11; Sprint 2: 2.4 | Sprint 3: Task 3.E2E |
| G-2 | Fix the ruler | Sprint 1: 1.4, 1.5, 1.6, 1.7, 1.9, 1.10 | Sprint 3: Task 3.E2E |
| G-3 | Dissent measurable | Sprint 1: 1.8, 1.11; Sprint 2: 2.5 | Sprint 3: Task 3.E2E |
| G-4 | Model separated | Sprint 2: 2.1, 2.3, 2.4; Sprint 3: 3.1 | Sprint 3: Task 3.E2E |
| G-5 | Gates priced | Sprint 1: 1.6; Sprint 2: 2.1–2.5; Sprint 3: 3.1 | Sprint 3: Task 3.E2E |
| G-6 | Nothing shipped changes | Sprint 1: 1.12; Sprint 3: 3.2, 3.3 | Sprint 3: Task 3.E2E |

**Goal Coverage Check:**
- [x] All PRD goals have at least one contributing task
- [x] All goals have a validation task in final sprint

### D. Flatline integration (sprint run, 2026-10-19)
Two voices, 16 blockers, 45 items, cross-scoring degraded (KF-041 recurrence 8); read by judgment (DEC-0624). Integrated: E2E before the PR with a post-publication check (SKP-019, IMP-002 ×2); a secret scan of the record tree before publication (SKP-020, gpt IMP-022); `check_mount_closed` after toggles, config writes and manifest regeneration (SKP-002); clause d with `git fsck --unreachable` (SKP-003, SKP-001 720); `exposed_unknown` excluded pairwise and reported (SKP-004, gpt IMP-010); the detector validation worded as a floor, extra hits read by hand (SKP-005); the pin defined as the commit after Tasks 2.1 and 2.2 and any later fix re-pins and re-runs (SKP-008, SKP-009, gpt IMP-004/005); adjudication fallbacks, the anchor-expansion sample and a Wilson interval (SKP-010, SKP-012, gpt IMP-006/007, opus IMP-009/021); exclusion counts and an all-rows sensitivity against selection effects (SKP-015, gpt IMP-011); the cycle spend ledger (SKP-016, gpt IMP-014, opus IMP-007); the answer-set scope stated as `.claude/**` with the config excluded by design (SKP-001 780, gpt IMP-016 — see sdd.md §5.2); G-6 reworded to allowlisted default checks with the additive schema fields listed (SKP-018, gpt IMP-018, opus IMP-012); the smoke PR list fixed to the explicit seven (gpt/opus IMP-001); dependencies 1.3 → 1.6/1.9 and 1.4/1.6 → 1.11 (gpt IMP-008, opus IMP-005/022); `manifests/v1/` verified against `ba11b860` (opus IMP-010); the smoke's expected-dissent table and the anchor-share definition (opus IMP-018, gpt IMP-015); the eval-only refusal's smoke exception (opus IMP-020); dissent runs scheduled before the batches (opus IMP-016); the cell matrix and reads table (gpt IMP-003, opus IMP-003/006); the stop-the-sprint rule time-boxed (opus IMP-019); the decision statistic named from Task 1.10's DEC in the pre-registrations (opus IMP-014). Declined: a formal retry-accounting schema beyond the runner's existing attempts/retry_reason fields (gpt IMP-020); blocking the curator's worktree mechanically (opus IMP-013) — the run directories are gitignored and absent from a fresh worktree, and the brief forbids the main checkout.

> Sources: prd.md §Functional Requirements, §Goals & Success Metrics; sdd.md §5, §7, §8, §11.D–E
