# Sprint Plan: The conclusive review-catch answer (cycle-132)

**Version:** 1.0
**Date:** 2026-10-21
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** grimoires/loa/prd.md (cycle-132, FR-1 … FR-11; Appendix E D1–D18)
**SDD Reference:** grimoires/loa/sdd.md (1.1; §1.4 components, §3.2 schema, §5.2 contracts, §5.3 pre-registered design, §11.D D-1.1 … D-7.10)
**Ledger:** cycle `cycle-132-conclusive-review-catch`, sprints global 269 / 270 / 271 (local sprint-1 … sprint-3; `next_sprint_number` set past the sprint-bug-266 … 268 micro-sprints, SDD D-6.1)
**Execution:** `/run sprint-plan`, push AUTO; Opus 5.5 implementers in linked worktrees returning `git diff --cached --binary` patches; the lead applies, reviews and audits on Fable 5.1; at most three dissent runs per sprint; no dissent while a batch runs (KF-037); blind labelling roles run as containerized sessions (SDD D-7.1), never as Agent-tool subagents
**Task kinds:** every task carries `kind: mechanical | judgment | operator` (DEC-0144); no `operator` task exists — the operator's instruction authorised the cycle end to end and every operator-level choice is an `[ASSUMPTION decision]` DEC row (prd.md Appendix E)
**Spend:** planning envelope USD 2,500 (DEC-0669); the binding cap is set by Task 1.9 and written into the hashed registration before any Phase 1 row; Phase 0 arm spend is zero (blind sessions and planning dissents are the only model calls); halt only on spend above the cap by the runner's reservation rule
**System Zone authorization:** none (the cycle edits `evals/`, `grimoires/`, `CHANGELOG.md` only; prd.md § Technical Considerations)
**Flatline integration:** PRD run → DEC-0685 (prd.md Appendix F); SDD run → DEC-0692 (sdd.md §11.E); sprint run → § Appendix D

---

## Executive Summary

Three sprints answer one question with evidence a stranger can re-derive. Sprint 1 (global 269) spends no arm money: it seeds the unseen corpus with provenance, compiles incidents, re-derives the ground truth with two blind containerized annotators (kappa, adjudication, label source, review-driven tag), builds the compute-matched arms and the harness follow-ups, writes the stdlib analysis module and proves it on placebo data from the 63 existing runs, sizes the study by a simulation of the complete decision procedure, and hashes a registration that binds every input — after a dissent review of the plan. Sprint 2 (global 270) runs the pre-registered batches at one pin in PR groups with interim looks under the YES / NO / SMALL / FUTILE / CONTINUE rule, the open-mount positive control on the first group, and the blind judge on a stratified sample. Sprint 3 (global 271) takes the pre-registered reads and the sensitivities, writes the standalone report, has a reproducer rebuild every grade, row and read from a fresh clone, runs the placebo and positive-control checks on the new rows, and ships through review, audit, Bridgebuilder, merge, record branch and archive, cutting the held rc.7 only after the proof.

> Sources: prd.md § Executive Summary, § Timeline & Milestones; sdd.md §8

---

## Sprint Overview

| Sprint | Global | Theme | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| 1 | 269 | Phase 0 — ground truth, harness, analysis, power, registration | corpus + provenance; incidents; packets + blind sessions + annotation merge → v2 manifests (frozen sets migrated); matched cells + registration + follow-up beads; analysis module + unit tests; placebo on the 63 existing rows committed; power → N, cap, k, groups, calibrated constant; PREREGISTRATION.md + REGISTRATION.json hashed after the Flatline spec review; rc.7 hold line | sprint-bug-266 … 268 merged (labels grammar, archive script) |
| 2 | 270 | Phase 1 — batches | pin; suite root frozen + self-check; smoke (oracle_closed, realized k ratios); G1 (+ open mount) → look 1; G2 → look 2; G3 → look 3 or stop; judge sample + blind judge + agreement; spend posts; contamination hand-reads | Sprint 1 |
| 3 | 271 | Phases 2–3 — reads, report, proof, ship | `--final` reads + DEC rows; report; REPRODUCE.md + reproducer run from a fresh clone; placebo + positive control on the new rows; CHANGELOG rc.7; PR; review; audit; Bridgebuilder; merge; record branch; archive | Sprint 2 |

> Sources: prd.md § Timeline & Milestones; sdd.md §8

---

## Sprint 1: Phase 0 — ground truth, harness, analysis, power, registration (global 269)

**Duration:** 2 days
**Dates:** 2026-10-21 – 2026-10-23

### Sprint Goal
Every input of the measurement exists, is hashed and is proven before a single arm dollar is spent: re-derived labels with a reported kappa, a matched-bare arm the harness can run and check, an analysis module that reads zero on shuffled data, a simulation-derived N and cap, and a registration whose dissent review precedes the first row.

### Deliverables
- [ ] `evals/fixtures/review-prs/record-pairs.tsv` rows for sprints 255 … 265; the new fixtures seeded (`pr-19 …`); `fixture.yaml` `exposure` + `contamination_note` on every fixture; `SHA256SUMS` refrozen → **[G-1, G-2]**
- [ ] `evals/harness/incident-scan.sh` + `incidents/pr-NN.tsv`, `evidence/`, `.meta.json` for every candidate fixture → **[G-1]**
- [ ] `evals/harness/annotation-packets.sh` (+ codebook, `hunks.meta.json` with `review_driven`, leak check), `evals/harness/schemas/annotation.schema.json` → **[G-1]**
- [ ] `evals/harness/blind-session.sh` (container executor; packet-only sandbox; taint check) → **[G-1, G-4]**
- [ ] `evals/analysis/c132/annotation_merge.py`; labels TSV v2 header; `evals/harness/schemas/review-manifest.schema.json`; `--build-manifest` v2 fields; frozen sets moved to `manifests/c131/` and `labels/review/` with the c131 suite-root task paths updated; grader `label_set`/`labels_meta`; a c131 re-grade equality test → **[G-1]**
- [ ] The annotation run: two blind sessions per selected fixture, `kappa.json`, `adjudication.{md,json}`, `result.md`, v2 manifests built and byte-identical from labels → **[G-1]**
- [ ] Matched cells: runner session units with the 2-re-run limit, `ablation-grade.sh --union`, took-effect `bare_sessions_matched` + `mount_cheval_ok`, row writer 1.5, report 1.4, arms `a0_bare_matched` + `a0_bare_fable_matched`, `--registration` + MANIFEST fields + resume refusal, `--batch-context`, toggle vocabulary parity, `dissent_absent_reason` from evidence, `false_positive_rule`, egress class 9, distinct-defect tests → **[G-3, G-4]**
- [ ] `evals/analysis/c132/{stats,reads,power,judge_agree}.py` + `tests/` (textbook-value unit tests) + `evals/tests/analysis-c132.bats` wrapper; `reads-c132.py`, `power.py` CLIs → **[G-2, G-3, G-5]**
- [ ] `a2a/sprint-1/placebo-existing.{md,json}` — the 200-shuffle placebo on the 63 existing rows, committed → **[G-3]**
- [ ] `a2a/sprint-1/power/power.{md,json}` — N, cap, k table, groups and looks, calibrated boundary constant, candidate table with seeded order, sensitivities → **[G-2]**
- [ ] `grimoires/loa/evals/ablation-2.0-c132/{PREREGISTRATION.md, REGISTRATION.json, tasks/, MANIFEST.sha256, README.md}` frozen; Flatline `--phase spec` record `a2a/sprint-1/flatline-prereg.json` + integration note; the registration hash in NOTES → **[G-3]**
- [ ] Beads bd-9zmfn, bd-eriso, bd-56nn6, bd-jszcp, bd-st02i, bd-gdl5s closed with evidence; CHANGELOG `[Unreleased]` entries; `evals/tests/` + `tests/unit/` green → **[G-7]**

### Acceptance Criteria
- [ ] PRD FR-1 AC 1–4 (record-pairs rows validated; new fixtures complete; `exposure` fields parse on every fixture; `--check` passes; `evals/tests/` green)
- [ ] PRD FR-2 AC 1–4 (packets deterministic and leak-free; annotation records with kappa, localization and grouping agreement, adjudication; v2 manifests validate and rebuild byte-identically; grader reads v2 with `label_set`; frozen sets byte-identical to `main`)
- [ ] PRD FR-3 AC 1–4 (dry run shows k sessions; stub run k = 3 with per-session transcripts and summed cost; union credits once; `recall_session1`; took-effect pass/fail; row validate; report partitions; suite validate) plus SDD D-7.3 (session-level validity, attempt limit, intention-to-run fields)
- [ ] PRD FR-5 AC 1–3 (unit tests incl. REML, permutation, calibrated boundaries, RCI, placebo distribution, validity filter, degenerate statuses; placebo on existing rows committed and inside the band; `--look`/`--final` byte-identical across two runs)
- [ ] PRD FR-6 AC 1–3 (power deterministic by seed; candidate table; the chosen N reproduces from frozen inputs; the complete-procedure simulation with calibration and the correlated-sessions sensitivity)
- [ ] PRD FR-7 AC 1–3 (`--registration` recorded and resume-bound; the NOTES heading with the hash precedes any Phase 1 row; the Flatline spec review precedes the hash; addenda rule stated)
- [ ] PRD FR-11 AC 1–2 (the follow-up beads closed with bats evidence; the rc.7 hold line present)
- [ ] `evals/tests/` (535 + new) and `tests/unit/` green; `bash -n` on every changed script; `validate-suite.sh` on the c132 and c131 roots

### Technical Tasks

- [ ] Task 1.1: Seed the corpus — `record-pairs.tsv` rows for sprints 255 … 265 (base = parent of the first implementation commit, head = the round-1 tree, fix = the closing commit; the cycle-131 sprints' feedback under `a2a/sprint-1 … 3/` via the new `--feedback` paths); `seed-corpus-from-record.sh --feedback <paths>` and the `exposure`/`contamination_note` fields with the model-availability constant table; seed every new fixture; stamp `exposure` on pr-11 … pr-18; `--freeze`; bats for the fields and the paths; **the corpus ceiling**: the report's candidate table counts the eligible fixtures (seeded, ≥ 2 defects expected, `exposure` recorded) — at most 15 — so Task 1.9 can bound N by it (Flatline SKP-001) → **[G-1, G-2]** · kind: mechanical
- [ ] Task 1.2: `incident-scan.sh` — merge-date window to the scan date across the four sources (SDD D-7.8), `gh api --paginate` with completeness recorded, evidence files, `.meta.json`; run over every candidate fixture (read-only `gh`); bats on a synthetic repo with `--no-gh` → **[G-1]** · kind: mechanical
- [ ] Task 1.3: `annotation-packets.sh` + `codebook.md` + `annotation.schema.json` — hunks with 12 lines of head context, incidents, `hunks.meta.json` with `review_driven` from the feedback citations (outside the packet), the leak check (fails closed on any label/feedback line); bats on a synthetic fixture → **[G-1]** · kind: mechanical
- [ ] Task 1.4: `blind-session.sh` — container executor reuse, packet-only sandbox, tools Read/Grep/Glob/Write, prompt → fixed label path, transcript + cost + `taint.json`; bats with the stub CLI, including an adversarial-packet case (a packet line shaped as an instruction to read `/workspace/../labels` or to call Bash: the stub records the attempt and the taint check marks the role `tainted`) (Flatline SKP-010) → **[G-1, G-4]** · kind: mechanical
- [ ] Task 1.5: `annotation_merge.py` (kappa ×3, localization and grouping agreement, complete adjudication records, cross-source dedupe, v2 rows) + labels v2 header in `seed-corpus-from-record.sh` + `review-manifest.schema.json` + `--build-manifest` v2 fields + the frozen-set migration (`git mv` to `manifests/c131/`, `labels/review/`; c131 root `task.yaml` paths; byte-identity and one c131 re-grade equality test) + grader `label_set`/`labels_meta` → **[G-1]** · kind: mechanical
- [ ] Task 1.6: The annotation run (lead) — packets for the candidate set (N + 2 spares from Task 1.9's order), two blind sessions each through `blind-session.sh` (Opus 5.5), `annotation_merge.py --kappa`, the lead's `adjudication.json` with reasons, v2 rows → `--build-manifest` → byte-identical rebuild → `--freeze`; `a2a/sprint-1/annotation/result.md` (kappa per fixture and pooled, adjudication share, review-driven share) → **[G-1]** · kind: judgment
- [ ] Task 1.7a: Matched cells in the runner — session work units for `bare_sessions: matched` arms, `meta/cell.json`, the 2-re-run attempt limit for every unit, `--resume` re-running only missing/failed sessions, the cell rowed once all k land (SDD D-3.1, D-3.2, D-7.3); arms `a0_bare_matched`, `a0_bare_fable_matched` + toggle vocabulary (`print_toggle_vocabulary`, parity bats — bd-gdl5s); `--batch-context` argv (bd-st02i); `mount_cheval` evidence + `mount_cheval_ok` (bd-56nn6); RAB cases → **[G-4]** · kind: mechanical
- [ ] Task 1.7b: `ablation-grade.sh --union` + 1.3.2 (`label_set`, `labels_meta`, `false_positive_rule` — bd-9zmfn, `multi_credit_citations` + distinct-defect tests, egress class 9 incl. WebFetch/WebSearch inputs — bd-eriso), took-effect `bare_sessions_matched`, row writer 1.5 (`sessions_valid`, `session_costs`, `all_spend_usd`, `dollar_match`, `recall_session1`, `dissent_absent_reason` from harness evidence — bd-jszcp, `registration_sha256`), report 1.4 partitions; bats → **[G-3, G-4]** · kind: mechanical
- [ ] Task 1.7c: `run-ablation.sh --registration` — `REGISTRATION.json` (JCS via `lib/jcs.sh`), MANIFEST fields, resume refusal on a changed hash, `overshoot_bound_usd`; `evals/analysis/c132/registration.py` to build and hash the manifest; **the spend gate stated and tested**: each batch's `--max-usd` is derived at launch from the registered cap minus `spend.sh --since <kickoff>` (the cycle meter), and the runner's existing reservation rule (spent + in-flight reservations + the next unit's estimate under the batch cap; durable in STATUS.json across `--resume`, settled on actual costs) is pinned by RAB cases for concurrent launches, retries and resume (Flatline SKP-003b); bats → **[G-3]** · kind: mechanical
- [ ] Task 1.8: `evals/analysis/c132/` — `stats.py` (cluster bootstrap, REML LMM with boundary flag, PR-level and pair-level permutation, Lan–DeMets OBF recursion with a calibration constant, RCI, conditional power, 200-shuffle placebo, defects per USD), `reads.py` (`reads-c132.py`: input manifest validation, validity filter incl. matched-cell rule, the partition, `--look/--final/--placebo`, degenerate statuses, byte-identical output), `power.py` (SDD §5.3 model: Beta-Binomial shrinkage + blind-spot mixture, logit design effect with clipping diagnostics, correlated-sessions sensitivity, the complete procedure under data-dependent completion — session/cell exclusion rate `r`, a cap-driven partial last group drawn at random, the ≥ 6-PR rule — calibration, cap and affordable-N, and the corpus ceiling as an input (Flatline SKP-005, SKP-001)), `judge_agree.py` (Horvitz–Thompson corrected figures; the universe includes missed ground-truth defects as far-miss units with their own inclusion probability — Flatline SKP-007), missingness reporting in `reads.py` (excluded cells and sessions by arm and k; the two bounding sensitivities "every excluded matched session missed everything" / "caught everything" beside the primary — Flatline SKP-012), `tests/` (textbook two-group REML within 1e-6; OBF 3.710/2.511/1.993 within 0.02; permutation on a constructed case; kappa 2×2; placebo calibration on synthetic data; validity filter; degenerate cases) + `evals/tests/analysis-c132.bats` wrapper → **[G-2, G-3, G-5]** · kind: mechanical
- [ ] Task 1.9: The power run (lead) — `power.py` over the 63 existing runs (the 36 tracked c130 run dirs + the 27 c131 run dirs fetched from the record branch into a scratch results root), k table from the cost fits (PRD D18), N, cap, groups/looks, the calibrated constant, the candidate table in seeded order with `exposure`; the affordable-N rule applied and stated; **the cap's accounting scope stated** (Flatline SKP-004): the binding cap is the total cycle spend — every metered row on `.run/cost-ledger.jsonl` since the kickoff timestamp 2026-10-21T00:23Z (planning dissents, Flatline runs, blind sessions, the judge, the reproduction rerun, retries) plus every arm row — with the arm allowance a sub-cap and explicit reserve lines for annotation, judging, controls, retries and reproduction set aside before the affordable-N comparison; `spend.sh --since 2026-10-21T00:23:00Z` is the meter; **the corpus ceiling**: if the simulated N exceeds the eligible count from Task 1.1, N is the ceiling and the registration states the achieved power (below 0.50 → exploratory, SDD §5.3) (Flatline SKP-001); DEC row → **[G-2]** · kind: judgment
- [ ] Task 1.10: The placebo on existing rows (lead) — `reads-c132.py --placebo` over the same 63 rows (c131 label set) → `a2a/sprint-1/placebo-existing.{md,json}`, committed before any Phase 1 spend; DEC row with the band outcome → **[G-3]** · kind: mechanical
- [ ] Task 1.11: Pre-registration (lead) — `PREREGISTRATION.md` (question, corpus and order, groups and looks, arms and k, primary and secondary estimands, intervals and tests, the partition and calibrated boundaries, validity and exclusion incl. D-7.3, dollar-matching tolerance, placebo band, positive-control rule, judge protocol, sensitivity list, cap and reservation rule, seeds, exchangeability statement, the smoke's role); suite root `ablation-2.0-c132/` (tasks per selected PR with bounds 50/40, `review_catch.manifest` v2, `bare_sessions_matched`; `freeze.sh --allow-partial`; image self-check); Flatline `--phase spec --autonomous` on PREREGISTRATION.md → integrate by judgment (DEC) → `registration.py` → `REGISTRATION.json` (binding also the container image digest and the pin, so runner and grader code are frozen with the analysis tree — Flatline SKP-011) + sha256 → NOTES heading; **the amendment policy, written in PREREGISTRATION.md**: a bug fix to the analysis or runner code after registration lands as `REGISTRATION-N.json` naming its predecessor, the original outputs are kept and both the original and the amended reads are reported with the diff explained → **[G-3]** · kind: judgment
- [ ] Task 1.12: Sprint close — beads bd-9zmfn, bd-eriso, bd-56nn6, bd-jszcp, bd-st02i, bd-gdl5s closed with evidence; CHANGELOG `[Unreleased]` `### Added` entries under the rc.7 hold line; `evals/tests/` + `tests/unit/` green; DEC rows for every implementer DECISION; `reviewer.md` with `## AC Verification` → **[G-7]** · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `seed-corpus-from-record.sh --feedback <paths>` and the `exposure` fields on a synthetic record | a feedback path outside `a2a/sprint-<N>/` refused or misread; a fixture without `exposure`; `--check` drift | the quality of the seeded labels (the annotation replaces them) | `evals/tests/seed-corpus.bats` SC-1 … SC-12 |
| `incident-scan.sh --no-gh` on a synthetic repo | a fix commit outside the merge→scan window counted; evidence file missing; meta without counts | an issue `gh` never returned | new `evals/tests/incident-scan.bats` |
| `annotation-packets.sh` leak check | a label or feedback line in a packet (exit 1); nondeterministic output; a hunk without `review_driven` | a paraphrase of a finding that no line matches | new `evals/tests/annotation-packets.bats` |
| `blind-session.sh` with the stub CLI | a disallowed tool or an outside read in the transcript (tainted); a missing label file; wrong sandbox contents | a model that infers labels from the hunks themselves (that is the task) | `evals/tests/pipeline-run.bats` executor fixtures |
| `annotation_merge.py` on crafted A/B files | wrong kappa on a textbook 2×2; unresolved disagreement accepted; dedupe across sources; a row that does not resolve on head | annotator quality | unit tests under `evals/analysis/c132/tests/` |
| `--build-manifest` with the v2 header and the frozen-set migration | a v2 column dropped; `manifests/c131/` not byte-identical; a c131 run re-graded differently | — | `seed-corpus.bats`, `ablation-grade.bats` |
| Runner session units (stub CLI, k = 3): plan, resume with one failed session, attempt limit, `cell.json`, one row | a session re-run beyond 2 attempts; a cell rowed before all sessions land; a refusal-fallback session re-run | real model variance | `evals/tests/run-ablation.bats` RAB cases |
| `ablation-grade.sh --union` on synthetic sessions | a defect credited twice; FP dedupe across sessions; `recall_session1`; an invalid session included | semantic correctness of a credit (the judge's job) | `evals/tests/ablation-grade.bats` |
| Egress class 9 and distinct-defect semantics on crafted transcripts and manifests | `git fetch github.com` missed; a WebFetch of the repo missed; a citation hitting two defects miscounted | an egress the transcript cannot show (named in the report) | `ablation-grade.bats` AG cases |
| `run-ablation.sh --registration` dry run + resume with a changed file | hash not recorded; resume accepted after an edit; overshoot bound absent | — | `run-ablation.bats` |
| `stats.py` / `reads.py` / `power.py` unit tests | REML off the textbook value; OBF boundaries off the published table; permutation unit wrong; placebo not calibrated on synthetic nulls; a degenerate input printing a number | the external validity of the normal approximation (the simulation's job) | new `evals/analysis/c132/tests/`, `evals/tests/analysis-c132.bats` |
| `reads-c132.py --placebo` on the 63 existing rows | a biased primary read (band failed) | a bias the shuffle cannot see | `a2a/sprint-1/placebo-existing.md` |

### Dependencies
- sprint-bug-266 … 268 merged into the cycle branch at `5b840b01` (PR #1288 to `main` pending CI): the `@L<n>` grammar and `--sync-labels` (Task 1.5 builds on them), the fixed archive script (used at the cycle's end)
- Record branches fetched locally (`origin/record/cycle-129-a2a`, `cycle-130-a2a`, `cycle-130-analysis`, `cycle-131-honest-measurement`)
- Docker image `loa-ablation:258` (blind sessions); Bedrock key; `gh` read-only

### Security Considerations
- Blind sessions run in the container executor with the existing credential copies only; no repository mount; packets pass `no-secrets.sh`
- Third-party text (issue bodies, feedback files, transcripts) is quoted inside fences in packets and never interpreted; the leak check fails closed
- No `.claude/` edit; `evals/`, `grimoires/`, `CHANGELOG.md` only

### Risks & Mitigation
| Risk | Mitigation |
|------|------------|
| Annotator kappa below 0.6 | the codebook is tried on one fixture first and revised before the blind run; the adjudication share is a headline caveat; the review-derived set stays a sensitivity |
| The power simulation names an N the envelope cannot afford | the affordable-N rule (deterministic) with the achieved power stated; below 0.5 the registration declares the study exploratory |
| The 27 c131 run directories must come from the record branch | `git archive origin/record/cycle-131-honest-measurement evals/results/ablation-2.0/c131-*` into a scratch results root; hashes recorded |
| Session-unit runner changes break the existing batch path | the stub-CLI RAB cases run both `a1_full` and matched plans; the c131 root dry run stays byte-identical |
| The Flatline spec review degrades (KF-041) | integrate by judgment, record the degradation, hash the final text |

### Success Metrics
- Kappa and adjudication share reported for every selected fixture; v2 manifests rebuild byte-identically
- Placebo on existing rows inside the band and committed; power.md names N, cap, k, groups, constant
- Registration hash in NOTES and MANIFEST-ready before any Phase 1 row; Flatline spec record dated before it
- `evals/tests/` and `tests/unit/` green; six follow-up beads closed

> Sources: prd.md FR-1 … FR-7, FR-11; sdd.md §1.4, §3.2, §5.2, §5.3, §7.1, §11.D

---

## Sprint 2: Phase 1 — batches (global 270)

**Duration:** 2 days
**Dates:** 2026-10-23 – 2026-10-25

### Sprint Goal
Run the registered design at one pin: smoke, the groups in order with a look after each, the positive control on the first group, the blind judge on the stratified sample — stopping where the rule says, posting spend after every batch, hand-reading every contaminated row.

### Deliverables
- [ ] Pin recorded (the Sprint 2 start commit); suite root frozen and self-checked; codex pre-flight green; `REGISTRATION.json` hash equal to the Sprint 1 record → **[G-3, G-4]**
- [ ] Smoke rows (one `a1_full` + one BARE per selected PR; `oracle_closed` true on every PR; realized cost ratios beside the registered k) in NOTES → **[G-4]**
- [ ] Batch rows for G1 (+ `a1_full_openmount`), G2, G3 as the rule allows, in `evals/results/ablation-2.0/c132-g*/` and the tracked `reports/review-catch-c132/rows.jsonl`; look reads and decisions in NOTES with timestamps → **[G-4, G-5]**
- [ ] Judge sample packets, blind judge labels, `a2a/sprint-2/judge/result.{md,json}` → **[G-4]**
- [ ] Spend posts per batch; contamination hand-reads; DEC rows per look → **[G-5]**

### Acceptance Criteria
- [ ] PRD FR-8 AC 1–4 (suite root per PR with bounds, k and v2 manifest paths; smoke decides nothing and its k ratios are recorded; rows at the pin with refusal fallbacks and contaminations reported; looks in NOTES; batches stop at a boundary or the cap)
- [ ] PRD FR-4 AC 1–3 (judge sampler deterministic with strata and inclusion probabilities; agreement, kappa, confusion table, corrected figures; grader stays primary)
- [ ] Every batch MANIFEST carries `registration_sha256` equal to the registered hash; no row from a batch with a different hash
- [ ] The positive-control read (open − closed on G1, saturation-exempt) and its mechanism evidence recorded before any other read

### Technical Tasks

- [ ] Task 2.1: Pin and freeze (lead) — record the pin; `freeze.sh --root grimoires/loa/evals/ablation-2.0-c132 --allow-partial`; image self-check (`ablation-grade.sh --self-check base|reference|noisy` per task); codex pre-flight (KF-048); `REGISTRATION.json` hash check → **[G-3]** · kind: mechanical
- [ ] Task 2.2: Smoke (lead) — `run-ablation.sh --smoke` one `a1_full` + one BARE per selected PR under the closed mount; `oracle_closed` per PR; realized `cost(full)/cost(bare)` beside the registered k; NOTES entry; a PR whose smoke fails the mount is handled as the registration says (excluded or recorded) → **[G-4]** · kind: judgment
- [ ] Task 2.3: G1 batch (lead) — `run-ablation.sh --registration … --batch c132-g1` with the registered arms (`a1_full`, `a0_bare_matched`, `a0_bare_fable_matched`, `a1_review_only`, `a1_full_openmount`) × G1 × 2 trials, concurrency 3, `--run-cap 30`, `--allow-partial`; spend post; contamination hand-reads; `reads-c132.py --look 1`; the positive-control read; DEC row → **[G-4, G-5]** · kind: judgment
- [ ] Task 2.4: G2 batch and look 2 (lead) — as 2.3 without the open mount; stop if the rule fired at look 1 → **[G-4, G-5]** · kind: judgment
- [ ] Task 2.5: G3 batch and look 3 (lead) — as 2.4; or the recorded stop → **[G-4, G-5]** · kind: judgment
- [ ] Task 2.6: Judge (lead) — `judge-sample.sh` over the batch rows and run dirs (seeded; strata, inclusion probabilities, universe recorded), blind judge sessions through `blind-session.sh` (Opus 5.5), `judge_agree.py` → agreement, kappa, confusion table, Horvitz–Thompson corrected recall and precision per arm → **[G-4]** · kind: judgment
- [ ] Task 2.7: Sprint close — rows copied to `reports/review-catch-c132/rows.jsonl`; `a2a/sprint-2/batch-scans.md`; NOTES spend table; DEC rows; `reviewer.md` with `## AC Verification` → **[G-5]** · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| Smoke rows + `oracle_closed` + realized k ratios | a PR the closed mount cannot run; a k far from its realized ratio (reported, never changed) | arm quality (smoke decides nothing) | cycle-131 smoke records |
| Batch MANIFEST `registration_sha256` vs the Sprint 1 record | a batch started under an edited registration | — | `run-ablation.bats` |
| `reads-c132.py --look n` on the batch rows | a decision at fewer than 6 valid PRs; the wrong boundary; a stale information fraction | the truth of the estimate | unit tests (Sprint 1) |
| The positive-control read | no exposure in any open run (control not exercised); a negative estimate with exposure (void) | — | `c131-reads.md` R1 |
| `judge-sample.sh` strata and packets | a packet carrying arm or decision; inclusion probabilities missing | the judge's own error | new `evals/tests/judge-sample.bats` (Sprint 1) |

### Dependencies
- Sprint 1 complete (registration hashed, placebo committed, harness green)
- Codex credential valid through the batch horizon (expires 2026-10-28T04:44Z); Bedrock key; Docker

### Security Considerations
- The per-run credential copies as in cycle-130/131 (placeholder refresh token); the judge runs blind in a container
- Contaminated rows are claims to verify by hand under the declared shapes; never silently re-included

### Risks & Mitigation
| Risk | Mitigation |
|------|------------|
| Matched cells degrade through refusal fallbacks or contaminations | session-level validity (D-7.3); the intention-to-run table |
| The cap binds mid-group | the reservation rule stops launches; the partial group's valid pairs enter the look |
| A boundary fires at look 1 with 6 PRs | pre-registered; the report says why; the remaining groups are not run |
| Codex token expiry | pre-flight per batch; schedule to finish by 10-27 |

### Success Metrics
- Every planned cell has an outcome in the intention-to-run table; every look is in NOTES with its boundary table
- Judge agreement and kappa reported with the confusion table
- Spend within the cap; the overshoot bound respected

> Sources: prd.md FR-4, FR-8; sdd.md §5.3; known-failures.md KF-046, KF-048, KF-051

---

## Sprint 3 (Final): Phases 2–3 — reads, report, proof, ship (global 271)

**Duration:** 1.5 days
**Dates:** 2026-10-25 – 2026-10-27

### Sprint Goal
Take only the registered reads, then the sensitivities; write the report a consortium member can check; have a stranger reproduce every grade, row and read from a fresh clone; ship through every gate; cut rc.7 only after the proof.

### Deliverables
- [x] `reads-c132.py --final` → `reports/review-catch-c132/{reads.md, reads.json}`; DEC rows per read and for the stopping-rule outcome → **[G-5]**
- [x] `reports/review-catch-c132/report.md` (ELI5; the answer; reads; stopping rule; sensitivities; placebo; positive control; ground truth; judge; spend; caveats; proof) + `analysis.md` §11 pointer → **[G-5, G-6]**
- [x] `REPRODUCE.md` + `evals/analysis/c132/reproduce.sh`; the reproducer's `a2a/sprint-3/reproduction/report.md` with the hash table and the sampled rerun → **[G-6]**
- [x] Placebo on the new rows and the positive-control result embedded → **[G-6]**
- [ ] CHANGELOG: `[Unreleased]` → `## [2.0.0-rc.7]` after the proof; release notes; PR; review; audit; Bridgebuilder; merge; record branch; archive → **[G-7]**

### Acceptance Criteria
- [x] PRD FR-9 AC 1–3 (report files tracked; `reads.md` byte-identical across runs; every figure in the report reproduced by the script; DEC rows per read)
- [x] PRD FR-10 AC 1–2 (REPRODUCE.md exact; the reproducer's hashes equal; sampled rerun inside the recorded arm range or the discrepancy named; report § Proof links everything)
- [x] PRD G-7 (allowlisted diff vs `main` of `.loa.config.yaml`, skill frontmatter and shipped suite arms empty; rc.7 cut only after FR-9 and FR-10)
- [ ] Review APPROVED, audit APPROVED, Bridgebuilder round triaged, CI green, merged, record branch pushed, cycle archived through the fixed `archive-cycle.sh`

### Technical Tasks

- [x] Task 3.1: Final reads (lead) — `reads-c132.py --final` with the registration and input manifests; the naive and repeated intervals; DEC rows: primary, each secondary (defects per USD, cost per extra defect valid-pair and all-spend, review-only, pipeline-independent, matched-Fable), the stopping-rule outcome, placebo and positive-control verdicts → **[G-5]** · kind: judgment
- [x] Task 3.2: Report (lead) — `report.md` per sdd.md §4.3 with the ELI5 ≤ 300 words; `analysis.md` §11 pointer; `rows.jsonl`, `power.md`, `REGISTRATION.json` beside it; a bats case diffs the report's tables against `reads.md` → **[G-5]** · kind: judgment
- [x] Task 3.3a: The evidence commit — build and push **stage 1 of the record branch** (`record/cycle-132-conclusive-review-catch`: the tree at the cycle branch head plus the batch records minus sandboxes, packets, blind-session transcripts, labels, judge files, rows, `REGISTRATION.json`; secret scan before push), pin its SHA in NOTES; this is the exact commit the reproducer clones (Flatline SKP-002, SKP-003) → **[G-6]** · kind: mechanical
- [x] Task 3.3b: Reproduction — `REPRODUCE.md` (commands, expected hashes, the sampled cells, the stage-1 SHA) and `reproduce.sh`; an Opus 5.5 reproducer from a fresh clone of the stage-1 commit into an empty directory re-grades every run dir (`--allow-partial`, container executor, `--union` for matched cells), re-rows, re-reads (`--final`, `--placebo`), hashes, then reruns the three registered sample cells live (≈ USD 60) and reports; **re-trigger rule**: any later change to `evals/analysis/c132/`, the grader, the row writer, the rows or the manifests (a Bridgebuilder fix in Task 3.6 included) re-runs the reproduction against a new stage-1 commit before merge → **[G-6]** · kind: judgment
- [x] Task 3.4: Controls (lead) — `reads-c132.py --placebo` on the new rows; the positive-control read restated; both embedded in the report → **[G-6]** · kind: mechanical
- [x] Task 3.5: Release — CHANGELOG `[Unreleased]` becomes `## [2.0.0-rc.7] — <date>` (after 3.1–3.4), release notes with the answer and the caveats (`grimoires/loa/reports/release-notes-2.0.0-rc.7.md`), `.loa-version.json` and the README version pin — the release-metadata files the PRD authorizes for the ship step (prd.md § Technical Considerations, amended for Flatline SKP-001) → **[G-7]** · kind: mechanical
- [ ] Task 3.6: Ship — PR from the cycle branch; `/review-sprint`, `/audit-sprint`; Bridgebuilder round triaged (a fix that touches the analysis, grader, rows or manifests re-runs Task 3.3b first); CI green; admin merge; **stage 2 of the record branch** (parents stage 1 and the merge commit; appends the reproduction report, the a2a review/audit records and NOTES); `archive-cycle.sh` (fixed) → **[G-7]** · kind: mechanical
- [x] Task 3.E2E: End-to-End Goal Validation — for G-1 … G-7 the evidence path named in prd.md § Goals (manifests + kappa; power.md; registration hash + placebo + Flatline record; rows + judge result; report + DEC rows; reproduction report + controls; the allowlisted diff + the rc.7 heading); `a2a/sprint-3/e2e.md` → **[G-1, G-2, G-3, G-4, G-5, G-6, G-7]** · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `reads-c132.py --final` twice on the tracked rows | a non-deterministic read; a hand-typed number in the report (the table diff) | — | `c131-reads.md` recipe |
| `reproduce.sh` in a fresh clone | a grade, row or read that does not reproduce; a run dir missing from the record branch | a bias shared by the code and the reproduction (the placebo's job) | cycle-131 record-branch recipe |
| The allowlisted diff vs `main` | a shipped default changed | — | cycle-131 G-6 check |

### Dependencies
- Sprint 2 complete; record branch built before the reproducer runs; the archive script from sprint-bug-266 on `main`

### Security Considerations
- The record branch secret scan before push; no sandbox directories on the record branch; the reproducer clones with read-only credentials

### Risks & Mitigation
| Risk | Mitigation |
|------|------------|
| The reproduction finds a mismatch | the discrepancy is named in the report; the read is marked unreproduced until fixed |
| The positive control reads void | every other read is reported void; the cycle ships the apparatus finding, not a measurement |
| Bridgebuilder round late in the cycle | one round budgeted; findings fixed before merge |

### Success Metrics
- The answer in one sentence with its interval; the stopping rule stated; every proof artefact linked
- Byte-identical reproduction; sampled rerun inside range
- rc.7 cut after the proof; cycle archived

> Sources: prd.md FR-9, FR-10, § Success Criteria; sdd.md §1.4 Reproduction, §4.3

---

## Risk Register

| Risk | Sprint | Likelihood | Impact | Mitigation |
|------|--------|-----------|--------|------------|
| Kappa low | 1 | medium | high | codebook trial; adjudication share as caveat; review-derived set as sensitivity |
| Unaffordable N | 1 | medium | high | affordable-N rule; exploratory declaration below 0.5 power |
| Matched-cell degradation | 2 | medium | medium | D-7.3 session-level validity; intention-to-run table |
| Codex token expiry | 2 | low | medium | pre-flight; schedule |
| Positive control void | 2–3 | low | high | reported as void; apparatus finding shipped |
| Reproduction mismatch | 3 | low | high | named; read unreproduced until fixed |

## Success Metrics Summary

| Metric | Target |
|--------|--------|
| Fixtures with v2 labels and kappa | N (+2 spares) |
| Registration hash before any Phase 1 row | yes, in NOTES and every MANIFEST |
| Placebo (existing and new rows) | inside the band |
| Positive control | positive with verified exposure (or "not exercised" / void, stated) |
| Primary read | reported with 95 %/90 %/RCI, REML, permutation; stopping rule stated |
| Reproduction | byte-identical grades, rows, reads; sampled rerun in range |
| Spend | ≤ the registered cap |

## Dependencies Map

sprint-bug-266 … 268 (merged) → Sprint 1 (Tasks 1.1 … 1.5, 1.7, 1.8 in parallel; 1.6 after 1.3–1.5 and the candidate order; 1.9 after 1.8 and the 63-run inputs; 1.10 after 1.8; 1.11 after 1.6, 1.9, 1.10; 1.12 last) → Sprint 2 (2.1 → 2.2 → 2.3 → 2.4 → 2.5 → 2.6 → 2.7) → Sprint 3 (3.1 → 3.2 → 3.3/3.4 → 3.5 → 3.6 → 3.E2E).

---

## Appendix

### A. PRD Feature Mapping
| PRD Feature (FR-X) | Sprint | Status |
|--------------------|--------|--------|
| FR-1 corpus with provenance | Sprint 1 (Task 1.1) | Planned |
| FR-2 ground truth re-derived | Sprint 1 (Tasks 1.2 … 1.6) | Planned |
| FR-3 compute-matched arm | Sprint 1 (Tasks 1.7a–c) | Planned |
| FR-4 grader validation by a blind judge | Sprint 1 (1.4, 1.8); Sprint 2 (2.6) | Planned |
| FR-5 analysis code, placebo, stopping rule | Sprint 1 (1.8, 1.10) | Planned |
| FR-6 power simulation | Sprint 1 (1.8, 1.9) | Planned |
| FR-7 hashed registration + dissent | Sprint 1 (1.7c, 1.11) | Planned |
| FR-8 batches with looks | Sprint 2 (2.1 … 2.5, 2.7) | Planned |
| FR-9 reads and report | Sprint 3 (3.1, 3.2) | Planned |
| FR-10 proof | Sprint 3 (3.3, 3.4) | Planned |
| FR-11 follow-ups and the release hold | Sprint 1 (1.7a–b, 1.12); Sprint 3 (3.5) | Planned |

### B. SDD Component Mapping
| SDD Component | Sprint | Status |
|---------------|--------|--------|
| Corpus seeder (§1.4) | Sprint 1 | Planned |
| Incident scanner | Sprint 1 | Planned |
| Annotation packets, blind sessions, merge | Sprint 1 | Planned |
| Matched-bare cells (runner, union grader, took-effect, row, report) | Sprint 1 | Planned |
| Registration manifest and runner flags | Sprint 1 | Planned |
| Analysis module | Sprint 1 | Planned |
| Judge sampler and agreement | Sprints 1–2 | Planned |
| Pre-registration and suite root | Sprint 1 | Planned |
| Batches and looks (§5.3) | Sprint 2 | Planned |
| Report and reproduction | Sprint 3 | Planned |

### C. PRD Goal Mapping
| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Ground truth re-derived | Sprint 1: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6 | Sprint 3: Task 3.E2E |
| G-2 | A powered design | Sprint 1: 1.1, 1.8, 1.9 | Sprint 3: Task 3.E2E |
| G-3 | Hashed registration, placebo first, dissent before any run | Sprint 1: 1.7b, 1.7c, 1.8, 1.10, 1.11; Sprint 2: 2.1 | Sprint 3: Task 3.E2E |
| G-4 | The arms run on the unseen corpus | Sprint 1: 1.4, 1.7a, 1.7b; Sprint 2: 2.2 … 2.6 | Sprint 3: Task 3.E2E |
| G-5 | Only the pre-registered reads; stopping rule stated | Sprint 1: 1.8; Sprint 2: 2.3 … 2.7; Sprint 3: 3.1, 3.2 | Sprint 3: Task 3.E2E |
| G-6 | Proof | Sprint 3: 3.2, 3.3, 3.4 | Sprint 3: Task 3.E2E |
| G-7 | Nothing shipped changes; rc.7 held | Sprint 1: 1.12; Sprint 3: 3.5, 3.6 | Sprint 3: Task 3.E2E |

**Goal Coverage Check:**
- [x] All PRD goals have at least one contributing task
- [x] All goals have a validation task in final sprint

### D. Flatline integration (sprint run, 2026-10-21T02:28–02:36Z)
Two voices (claude-headless = Fable 5.1, gpt-5.5 via codex), 12 blockers (all HIGH), cross-scoring degraded (KF-041 shape, 0 % agreement, `verdict_quality` DEGRADED); read in full and integrated by judgment (DEC-0708). Record: `grimoires/loa/a2a/flatline/sprint-review-c132.json`.

**Adopted (task text amended):** two-stage record branch — the evidence commit is built and pushed before the reproduction and the proof is appended after merge, with a re-trigger rule for post-reproduction fixes (SKP-002, SKP-003 → Tasks 3.3a, 3.3b, 3.6; DEC-0709); release-metadata files authorized for the ship step (SKP-001 → Task 3.5, prd.md § Technical Considerations; DEC-0707); the cap's accounting scope and reserve lines stated before the affordable-N comparison (SKP-004 → Task 1.9; DEC-0710); the corpus ceiling counted in Task 1.1 and bounding N in Task 1.9 (SKP-001 gpt → Tasks 1.1, 1.9); the registration binds the image digest and the pin, with an amendment policy (SKP-011 → Task 1.11); the spend reservation gate derived from the cycle meter and pinned by tests (SKP-003 gpt → Task 1.7c); the power simulation runs under data-dependent completion and partial groups (SKP-005 → Task 1.8); missingness by arm and k with bounding sensitivities (SKP-012 → Task 1.8, SDD D-7.3); the judge universe names missed defects explicitly (SKP-007 → Task 1.8); an adversarial-packet taint case (SKP-010 → Task 1.4).

**Not adopted, with reasons:** an "independent discovery pass" as a ground-truth source (SKP-009) — a model reading the PR to label it is another arm in disguise (PRD D14; the judge-confirmed-stray sensitivity is the independent channel); runtime network restriction for blind sessions (SKP-010, in part) — the model API is the only egress the container needs and no proxy exists this cycle (SDD §11.E); re-litigating cell-level validity (SKP-012, in part) — SDD D-7.3 already decides session-level validity and the intention-to-run table.
