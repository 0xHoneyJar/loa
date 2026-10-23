# Software Design Document: The conclusive review-catch answer (cycle-132)

**Version:** 1.1
**Date:** 2026-10-21
**Author:** Architecture Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (cycle-132, FR-1 … FR-11, Appendix E D1–D18 = DEC-0661 … DEC-0672, DEC-0686 … DEC-0691)
**Status:** Draft 1.1 — autonomous run; design-level decisions taken on the operator's behalf are listed in §11.D (DEC-0673 … DEC-0684 for 1.0; D-7.1 … D-7.10 = DEC-0693 … DEC-0702 for 1.1); the Flatline SDD review is integrated in §11.E (DEC-0692)
**Pin:** every Phase 1 cell runs the first commit of Sprint 2 on `feature/cycle-132-conclusive-review-catch` (DEC-0672); image `loa-ablation:258` unchanged (Claude Code 2.1.299 inside; the framework and the harness are copied from the pinned source tree into the bind-mounted sandbox, so no image rebuild is needed for harness changes — `pipeline-run.sh` § Session)
**Branch:** `feature/cycle-132-conclusive-review-catch` from `main 16e0b48b` (+ `fix/cycle-132-bugs`: sprint-bug-266/267/268)

---

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

---

## 1. Project Architecture

### 1.1 System Overview

The system under design is the measurement apparatus that answers one question — does `a1_full` catch more real defects per dollar than a bare model at the same dollars on unseen PRs — with evidence a stranger can re-derive. It has five parts: (1) the **corpus and its ground truth** (record fixtures seeded from the record branches, re-labelled blind from fix hunks and incidents, with frozen older label sets); (2) the **harness** (the existing ablation runner, executor, grader, took-effect rules, row writer and report, extended with a compute-matched bare arm, a pre-registration hash in the manifest, and the five follow-up beads); (3) the **analysis module** (stdlib Python: cluster-by-PR bootstrap, REML linear mixed model, permutation test, Lan–DeMets O'Brien–Fleming group-sequential boundaries with conditional-power futility, the placebo, the power simulation); (4) the **blind labelling protocols** (annotators for ground truth, a judge for grader validation) with deterministic packet generators so the models see only data; (5) the **proof** (a hashed pre-registration whose dissent precedes the first row; a reproduction protocol a fresh clone can run; the record branch that carries every artefact).

### 1.2 Architectural Pattern

A pre-registered, mechanical pipeline: every artefact a model touches (packets, prompts, run directories) is generated deterministically from tracked inputs; every number in the report is produced by a script from tracked rows and grades; every rule is written and hashed before its data exist; every judgment is a decision row. Models appear in exactly three roles — the arms under test, the blind labelers, and the dissent reviewers of the plan — and none of them writes a number into the report.

### 1.3 Component Diagram

```
 record branches ──seed──▶ evals/fixtures/review-prs/pr-NN ──┐
   (feedback, fix commits)        │ fixture.yaml (+post_cutoff, contamination_note)
                                  ▼
            incident-scan.sh ──▶ incidents/pr-NN.tsv ─┐
                                                       ├──▶ annotation-packets.sh ──▶ packets/pr-NN/{codebook,hunks,incidents}.md
            fix hunks (head..fix) ─────────────────────┘             │ (two blind Opus annotators)
                                                                      ▼
                                  annotation-merge.py ◀── labels A.json, B.json ──▶ kappa.json, adjudication.md
                                        │ (lead adjudicates)
                                        ▼
                     labels/pr-NN.tsv (v2 header) ──build-manifest──▶ manifests/pr-NN.json (v2)   [manifests/c131/, manifests/v1/ frozen]
                                                                                 │
 evals/analysis/c132/power.py ◀── 63 existing grade.json/rows ──▶ power.md, N, cap, PR order
                                        │
                                        ▼
       PREREGISTRATION.md ──sha256──▶ NOTES + MANIFEST.json.preregistration_sha256   (Flatline --phase spec before the first row)
                                        │
   run-ablation.sh (pin, groups G1..G3) ─┼─▶ pipeline-run.sh ──▶ run dirs (a1_full, a1_review_only, a1_full_openmount)
                                        └─▶ matched cells: sessions/s1..sk (k × pipeline-run a0_bare) ──union──▶ grade.json
                                        │
       ablation-grade.sh 1.3.2 ──▶ grade.json ──▶ ablation-row.sh 1.5 ──▶ rows.jsonl ──▶ ablation-report.py 1.4
                                        │
       judge-sample.sh ──▶ judge/packets (blind Opus judge) ──▶ judge-agree.py ──▶ agreement, kappa
                                        │
       reads-c132.py --look n | --final | --placebo ──▶ reads.md/json ──▶ reports/review-catch-c132/report.md
                                        │
       REPRODUCE.md + reproduce.sh (fresh clone of the record branch) ──▶ hash table
```

### 1.4 System Components

#### Corpus seeder (`evals/harness/seed-corpus-from-record.sh`)
- **Purpose:** build record fixtures for sprints 255 … 265 and carry provenance (FR-1); generate v2 manifests from v2 labels (FR-2).
- **Changes:** `record-pairs.tsv` rows for the new sprints; `--feedback <path>[,<path>…]` accepts record-branch paths outside `grimoires/loa/a2a/sprint-<N>/` (the cycle-131 sprints keep their feedback under `a2a/sprint-1 … 3/`); `fixture.yaml` gains `post_cutoff: true|false|borderline`, `model_availability: {fable-5-1: "2026-06 (knowledge cutoff)", opus-5-5: "2026-10-05 (catalog date)"}`, `contamination_note`; labels header v2 (`HEADER_V2 = HEADER + [annotators, agreement, adjudication]`, optional trailing columns, both headers accepted); `label_source` enum gains `fix-commit`, `incident`; `--build-manifest` copies the three new columns into `defects[]`; the `@L<n>` form and `--sync-labels` from sprint-bug-268 are the base. D-1.1, D-2.3.
- **Interfaces:** unchanged modes plus the flag and the header; `--check`/`--freeze` unchanged.
- **Dependencies:** the record branches fetched locally; `git show` on the fix commits.

#### Incident scanner (`evals/harness/incident-scan.sh`, new)
- **Purpose:** compile, mechanically, the post-merge incidents attributable to a fixture (FR-2).
- **Behaviour:** given a fixture, read `fixture.yaml` (`fix_commit`, `sprint`), compute the head-changed file set from `head.diff` and the **merge date** (the first `origin/main` commit containing `fix_commit`); **one temporal rule for every source (D-7.8): from the merge date to the scan date**; (a) `git log origin/main --since=<merge date> --format=… -- <files>` keeping commits whose subject starts with `fix` (the diff of each, restricted to the files); (b) `gh api --paginate` over `search/issues` for each changed file's basename and path, keeping issues (and PR comments) created in the window whose body cites a changed path, with the page count and any truncation recorded; (c) the record branches' `bridgebuilder*.md` / `bridgebuilder-triage*.md` rounds dated in the window for the sprint's PR; (d) `grep -n` of each changed path in `grimoires/loa/known-failures.md`, entries dated in the window. Output `incidents/pr-NN.tsv` (`id`, `kind` ∈ {fix-commit, issue, bridgebuilder, kf}, `ref`, `date`, `files`, `excerpt ≤ 400 chars`), `incidents/pr-NN/evidence/<id>.{md,diff}` (the full issue body or commit diff) and `incidents/pr-NN.meta.json` (`origin/main` SHA, scan time, window, per-source counts, `truncated: false|true`, maturity = days between merge and scan), so the scan is reproducible from that SHA (the `gh` results are a snapshot: recorded, not re-queried by the reproduction). D-2.1.

#### Annotation packets and merge (`evals/harness/annotation-packets.sh`, `evals/analysis/c132/annotation_merge.py`, new)
- **Purpose:** give two blind annotators the same data and nothing else; turn their labels into kappa, an adjudication list and v2 label rows (FR-2).
- **Packets:** `packets/pr-NN/codebook.md` (fixed text: what counts as a defect at head; the not-defect classes test/docs/refactor/style/follow-on; severity scale; anchors are head-side line numbers of the wrong behaviour, several allowed; one group id per distinct defect), `hunks.md` (every hunk of `git diff <head>..<fix> -- <fixture files>` with id `H01 …`, path, head-side range, 12 lines of head context, the hunk text), `incidents.md` (every incident row with id `I01 …`). No line from any `labels/`, `manifests/`, feedback file or run directory may appear: the generator greps its own output against those sources and fails closed. Deterministic (sorted paths, fixed context, no timestamps).
- **Annotator output** (one JSON per annotator, schema `evals/harness/schemas/annotation.schema.json`): `hunks.<id>: {verdict: defect|not-defect, not_defect_class?, group: D<k>|null, file, anchor_lines: [int…], description, severity, category}`, `incidents.<id>: {verdict: defect-at-head|not-at-head, group, file, anchor_lines, description, severity}`.
- **Blinding (D-7.1):** each annotator is a containerized `claude -p` session run by `blind-session.sh` (below) over a sandbox that holds the three packet files and nothing else — no repository, no labels, no run directories; the transcript is the access log and is kept under `a2a/sprint-1/annotation/pr-NN/transcripts/`. The judge (FR-4) runs the same way.
- **Review-driven tag (D-7.6):** outside the blind packet, the generator matches every fix hunk against the sprint's record-branch feedback files (the `file:line` citations and the quoted snippets of `engineer-feedback*`, `auditor-sprint-feedback*`, `bridgebuilder*`) and records `review_driven: true|false` per hunk in `packets/pr-NN/hunks.meta.json`; the merge carries it to the defect (`review_driven: true` when any of its hunks is). The pre-registered secondary read "pipeline-independent" uses only defects with `review_driven: false` or `label_source: incident`.
- **Merge:** Cohen's kappa on hunk verdicts (2 × 2 table), on incident verdicts, and on severity among agreed defects; **localization agreement** (share of agreed defects whose anchor sets overlap, and the median anchor distance) and **grouping agreement** (pairwise same-group Jaccard over hunks) are reported beside (SKP-021); disagreements on verdict, group, file, anchors, description, severity or category are written to `adjudication.md` with both labels; the lead's `adjudication.json` holds a **complete adjudicated defect record** per disagreement (`{id: {verdict, group, file, anchor_lines, description, severity, category, reason}}`), every anchor validated against the head file; groups are merged across annotators by shared hunks and deduplicated across sources (a hunk defect and an incident naming the same head lines ±3 are one defect, `label_source` listing both); output rows (one per anchor line; `must_match` = the head line's text when unique else `@L<n>`; `label_source` fix-commit | incident | fix-commit+incident; `annotators "A,B"`; `agreement agreed|adjudicated`; `adjudication` reason; `review_driven`) appended to `labels/pr-NN.tsv` under the v2 header after the review-derived rows are moved to `labels/review/pr-NN.tsv` (the frozen review set stays rebuildable). D-2.2.

#### Matched-bare cells (`evals/harness/run-ablation.sh`, `evals/harness/ablation-grade.sh --union`, `evals/harness/took-effect.sh`, `evals/harness/ablation-row.sh`)
- **Purpose:** the compute-matched arm (FR-3, DEC-0663).
- **Design:** arm `a0_bare_matched` (`toggles: {loa_mount: false, bare_sessions: matched}`, `task_types: [review-catch]`). A cell (arm × task × trial) is **k independent sub-runs**, each a normal `pipeline-run.sh` invocation with the `a0_bare` phase plan (one BARE session, Opus 5.5, `--effort high`, its own sandbox, transcript, cost ledger) in `<cell-dir>/sessions/s<i>/`; k = the task's `review_catch.bare_sessions_matched` (fixed by the pre-registration from the smoke; floor 2, cap 30). The runner treats each session as a work unit for `--concurrency` and for `--resume` (a missing or failed session re-runs alone); when all k sessions have landed it writes `<cell-dir>/meta/cell.json` (k, session ids, per-session cost and status), calls `ablation-grade.sh --union <cell-dir>` and then `ablation-row.sh` once for the cell. **Union grading:** each session is graded on its own (its `grade.json`, DEC-0413 invariants intact); the union step reads only the k sessions' `grading/gates-combined.md` and `grade.json`, writes `<cell-dir>/grading/gates-combined.md` as the concatenation with `## session s<i>` separators, and grades it with the same citation reduction → `grade.json` with `recall` (union), `recall_session1` and `precision_session1` (session 1 alone), `bare_sessions: k`, `per_session: [{session, recall, detected, false_positives, cost_usd}]`, `label_set`. **Took-effect** `bare_sessions_matched`: exactly k session dirs attempted; each session passes `no_dot_claude`, `no_system_prompt`, `no_audit_rows`, `integrity_clean`; k equals the task's value. **Session-level validity (D-7.3):** a session whose outcome is infrastructure (`transport_error`, `cap_failure`, `interrupted`) is re-run at most twice (attempt 1 + 2 re-runs; every attempt's cost counted in `session_costs[]` and in the all-spend figures); a session with a refusal fallback (KF-051) or a contamination is **kept and marked invalid** (never re-run); the cell is `completed` when at least ⌈k/2⌉ sessions are valid, graded on the valid sessions only, with `sessions_valid`, `sessions_attempted`, `realized_cost_usd` (valid sessions) and `all_spend_usd` recorded; fewer valid sessions make the cell `degraded` (excluded pairwise). The same attempt limit (2 re-runs) applies to every other arm's run. **Row:** `bare_sessions`, `sessions_valid`, `session_costs[]`, `recall_session1`, `precision_session1`, `cost_usd = Σ valid sessions`, `all_spend_usd`, `phases[]` = the k BARE records. **Dollar matching (D-7.9):** a pair is dollar-matched when `|cost_usd(matched) − cost_usd(full)| ≤ 0.25 × cost_usd(full)`; other pairs are flagged (`dollar_match: false`) and the exact-dollar trim sensitivity covers them. **Same-model arm (PRD D13):** `a0_bare_fable_matched` (`toggles: {loa_mount: false, bare_model: fable, bare_sessions: matched}`) has the same mechanics with its own k from the Fable cost fit. **Intention-to-run:** the report prints every planned cell with its outcome (completed / degraded / cut / not run) beside the complete-pair read. D-3.1, D-3.2.
- **Rejected inside this design:** k sessions inside one sandbox (a later session could read an earlier session's output; independence lost).

#### Grader (`evals/harness/ablation-grade.sh`, `evals/graders/recall-vs-defects.sh` 1.3.2)
- **Changes:** `--union <cell-dir>` mode (above; valid sessions only, per `meta/cell.json`); `label_set: v2|c131|v1` from the task's `review_catch.manifest` path (`manifests/`, `manifests/c131/`, `manifests/v1/`); v2 manifest fields read and passed through to `grade.json.labels_meta` (per defect `label_source`, `agreement`, `review_driven`); bd-9zmfn: `false_positives` / `findings_refuted` computed under the same rule as the decision statistic (`pm3` on the task's manifest) and the rule named in `grade.json.false_positive_rule`; **distinct-defect semantics stated and tested (SKP-022):** defects are distinct by id with their anchor sets; each defect is credited at most once per run; one citation may credit every defect whose anchor set it hits, and `grade.json.multi_credit_citations` counts citations that credited two or more defects (bats: overlapping sites, multiple anchors, a citation near several defects); **network-egress contamination class 9 (PRD D15):** Bash `tool_use` commands with `git fetch|clone|pull|ls-remote`, `gh api|pr|issue|repo`, `curl|wget`, `python … urllib|requests` whose arguments name `github.com`, `raw.githubusercontent.com` or `api.github.com`, and WebFetch/WebSearch inputs naming the repository (bd-eriso) → `contaminated` with `pattern: network_egress`; `grader_version 1.3.2`. The citation rule itself is unchanged (DEC-0638: `recall_pm3` is the decision statistic). D-4.1.

#### Took-effect (`evals/harness/took-effect.sh`)
- **New rule:** `bare_sessions_matched` (above). bd-56nn6: pipeline-run writes `mount_cheval=ok|broken:<reason>` before the first phase (a `python3 -I -c "import loa_cheval"` probe against the mounted adapters) and the rule `mount_cheval_ok` is on every dissent-enabled mounted arm (a `broken` mount is a refused launch, not a degraded row — KF-050 made it an expected absence; now it is caught before spend).

#### Row writer and report (`evals/harness/ablation-row.sh` 1.5, `evals/harness/ablation-report.py` 1.4)
- **Changes:** fields in §3.2; bd-jszcp: `dissent_absent_reason: disabled` only when `meta/arm-evidence.txt` carries `dissent=false` written by the harness (never from the sandbox `.loa.config.yaml`); report partitions by `label_set` and by `bare_sessions`; a matched cell prints k and the session-1 figures beside the union.

#### Runner (`evals/harness/run-ablation.sh`)
- **Changes:** `--registration F` (a `REGISTRATION.json`, D-7.2) → `MANIFEST.json.registration_sha256` + `registration_path` + the manifest's listed input hashes copied; `--resume` recomputes the hash and exits 2 on a mismatch (the batch is bound to the registration it started under); `REGISTRATION.json` is JCS-canonical (`lib/jcs.sh`) and lists `preregistration_sha256` (the text), `corpus_sha256sums_sha256` (`evals/fixtures/review-prs/SHA256SUMS`), `suite_manifest_sha256` (`ablation-2.0-c132/MANIFEST.sha256`), `analysis_tree_sha256` (`git rev-parse HEAD:evals/analysis/c132`), `pin`, `arms` (ids, toggles, phase models, k per task), `label_set: v2`, `seed`, `addenda: []`; an addendum is a later `REGISTRATION-N.json` naming its predecessor's hash; `reads-c132.py` refuses rows from batches whose registration differs from the one it is given; bd-st02i: `--batch-context <id>` passed to `pipeline-run.sh` as an argv flag and recorded in `arm-evidence` (the `LOA_ABLATION_BATCH_CONTEXT` env var is read no more); session work units for matched cells (above) with the 2-re-run attempt limit; the `--max-usd` reservation rule (spent + in-flight reservations + the next unit's estimate under the cap) is the only spend gate, with the overshoot bound (concurrency × per-unit cap) printed in the MANIFEST. D-5.2.

#### Toggle vocabulary (`evals/harness/lib/sandbox-mount.sh`, `validate-suite.sh`)
- **Changes:** `bare_sessions: matched` accepted (`loa_mount: false` required with it); bd-gdl5s: `print_toggle_vocabulary` emits the key list and value forms, and `validate-suite.sh` / `pipeline-run.sh --dry-run` read it instead of their hand-kept copies (a parity bats case pins equality).

#### Judge sampler and agreement (`evals/harness/judge-sample.sh`, `evals/analysis/c132/judge_agree.py`, new)
- **Purpose:** validate grader 1.3.2 against a blind Opus judge on a stratified sample (FR-4, DEC-0667).
- **Sampling:** items = every (finding, labelled defect) decision the grader made in the batch rows' run directories: `credited` (a citation inside ±3 of a site), `near-miss` (the nearest citation within 4–20 lines of a site, not credited), `far-miss` (a labelled defect with no citation within 20 lines; the item quotes the finding closest in the same file if any), and `stray` (a cited region outside every window). Strata = arm × PR × class; per stratum min(all, 10), total ≥ 150 (if below, raise the per-stratum cap uniformly); seeded (20261021). Packets (`judge/packets/J0001.md …`): the finding's text (the paragraph or line holding the citation), the cited lines of `head/<file>` (±5), the labelled defect's description and anchor lines (for `stray`: only the finding and its cited lines), no arm, trial or grader decision; `judge/key.json` (outside the packets) maps items to their provenance.
- **Judge output:** `judge/labels.json` `{J0001: {verdict: describes|partially|does-not-describe | real|style|wrong|not-a-finding, note}}`.
- **Sampling units and weights (SKP-023):** the universe is enumerated and recorded first with one unit type per class — `credited` and `near-miss` units are (citation region, defect) pairs, `far-miss` units are defects, `stray` units are citation regions — and every stratum's inclusion probability `π_s = n_s / N_s` is recorded in `key.json`.
- **Agreement:** `judge_agree.py` → `result.json`/`result.md`: per stratum and pooled agreement between grader credit and judge `describes` (`partially` reported as disagreement in the strict figure and agreement in the lenient one), Cohen's kappa with a bootstrap 95 % interval, the confusion table, and the **judge-corrected recall and precision per arm as Horvitz–Thompson estimates**: each judged unit updates its defect's credit (a rejected credit removes it, an accepted near-miss adds it, a stray rated `real` counts as a real finding) with weight `1/π_s`, unsampled units keep the grader's decision, and the uncertainty is a cluster bootstrap over PRs of the weighted estimator; the judge runs blind through `blind-session.sh` (D-7.1).

#### Blind session runner (`evals/harness/blind-session.sh`, new; D-7.1)
- **Purpose:** run one blind labelling role (annotator A, annotator B, the judge) as a `claude -p` session inside the container executor over a sandbox that holds only the role's packets.
- **Behaviour:** `blind-session.sh --packets DIR --prompt FILE --model <id> --out DIR [--image loa-ablation:258] [--max-usd 6]` copies the packets into a fresh sandbox, runs the session with the same `env -i` allowlist, Bedrock pass-through and `--tools Read,Grep,Glob,Write` as the BARE phase (no Bash, no WebFetch, no network tools; the model API is the only egress), with the prompt asking for the label file at a fixed path; copies out the label file and the stream-json transcript; records cost. A transcript that shows a Read outside the sandbox or any tool other than the allowed four marks the role `tainted` (the lead reruns it). Deterministic layout; no timestamps in the packet sandbox.

#### Analysis module (`evals/analysis/c132/`, new; stdlib only)
- `stats.py`: `cluster_bootstrap(cells, n=10000, seed, level)` resampling PRs with replacement (all of a PR's pairs travel together), returning the point estimate, percentile interval and SE; `reml_lmm(cells)` — model `y_{p,t,a} = μ + β·[a = full] + u_p + ε`, `u_p ~ N(0, σ_u²)`, `ε ~ N(0, σ_e²)`, REML profile likelihood on `λ = σ_u²/σ_e²` maximised by golden-section search, GLS for `β`, Wald 95 % interval, a `boundary: true` flag when `λ` hits 0 or the grid's edge; `permutation_test(cells, n=10000, seed, unit="pr")` — **PR-level**: the arm labels of all of a PR's cells are swapped together (D-7.4; the exchangeability assumption stated in the pre-registration), two-sided p; `unit="pair"` is the sensitivity; `gs_boundaries(fractions, alpha=0.05, constant=None)` — Lan–DeMets O'Brien–Fleming spending `α*(t) = 2 − 2Φ(z_{α/2}/√t)` with boundaries solved by the Armitage–McPherson–Rowe recursion on a 2,000-point grid, and a `constant` multiplier the power simulation calibrates (PRD D16); `rci(delta, se, boundary)` — the repeated confidence interval `Δ̂ ± b_k·SE`; `conditional_power(z_k, t_k, boundary_final, drift)`; `placebo(cells, seed, n=200)` — 200 within-PR arm-label shuffles, each through the primary read, returning the share of 95 % intervals excluding 0 and the mean |Δ| (PRD D17); `defects_per_usd(cells)` with cluster-bootstrap intervals (D-7.9).
- `reads.py` (CLI `reads-c132.py`): requires `--registration REGISTRATION.json` and `--inputs INPUTS.json` (rows file hash, every grade.json hash, pin, label set, the expected cells and session membership) and refuses any mismatch (D-7.5; this is the `--expect` of 1.0, now mandatory); loads `rows.jsonl` + each row's `grade.json` (defect-level detected sets; unique cell keys `batch/arm/task/trial`, duplicates refused), applies the validity filter (§5.2), builds paired cells per PR × trial, computes the information fraction `t_k = SE²_planned-final / SE²_k`, and writes `reads.md`/`reads.json` for `--look n` (the boundary table, conditional power and the decision under the YES / NO / SMALL / FUTILE / CONTINUE partition; **no decision before 6 valid PRs and 30 labelled defects** — the look prints CONTINUE with the reason), `--final` (pre-registered reads first — primary Δ with the 95 % and 90 % cluster intervals and the repeated confidence interval at the stopping look, PR-weighted Δ, REML, PR-level permutation, defects per USD, cost per extra defect on valid pairs and on all spend, the pipeline-independent read (D-7.6), the dollar-matching table — then sensitivities in the pre-registered order), `--placebo` (the 200-shuffle calibration check). Degenerate inputs (zero SE, no valid pairs, fewer than 6 PRs, a REML boundary) print a named status instead of a number. Byte-identical across runs (sorted keys, fixed formats, no timestamps; the input hashes are printed).
- `power.py`: the simulation of §5.3 → `power.md`/`power.json` (per-N table with the probabilities of YES / NO / SMALL / FUTILE / void / inconclusive at Δ = 0 and Δ = MDE, the calibrated boundary constant, chosen N, the cap, sensitivity tables, the candidate-fixture table with the seeded order).
- `tests/`: `python3 -m unittest discover evals/analysis/c132/tests` (and a bats wrapper `evals/tests/analysis-c132.bats` so CI's bats step runs them).

#### Pre-registration and suite root (`grimoires/loa/evals/ablation-2.0-c132/`)
- `PREREGISTRATION.md` (§5.3 contents), `tasks/review-rNN/` per selected PR (`task.yaml` with `bounds {REVIEW: 50, AUDIT: 40}`, `review_catch.manifest: evals/fixtures/review-prs/manifests/pr-NN.json`, `review_catch.bare_sessions_matched: k`, `post_cutoff`, `TASK.md`, `REVIEW.md` copied byte-identical from the c131 root's pattern), `MANIFEST.sha256` (`freeze.sh --allow-partial`), `README.md`, the image self-check log under `a2a/sprint-2/`.

#### Reproduction (`grimoires/loa/reports/review-catch-c132/REPRODUCE.md`, `evals/analysis/c132/reproduce.sh`)
- A stranger's script: clone the record branch into an empty directory, re-grade every recorded run directory (`ablation-grade.sh … --allow-partial`, container executor; matched cells via `--union`), re-row, re-read (`--final`, `--placebo`), hash everything (`sha256_portable`), print a table against the recorded hashes; then `--rerun-sample` runs the three pre-registered cells live through `run-ablation.sh` into a scratch results root and prints their grades beside the recorded arm range.

### 1.5 Data Flow

Phase 0: seed → scan incidents → packets → (annotators) → merge → labels v2 → manifests v2 (frozen sets moved/kept) → power → PREREGISTRATION.md → Flatline spec review → integrate → hash → NOTES; the analysis code's placebo on the 63 existing rows committed. Phase 1: pin → smoke (one `a1_full` + one BARE per PR; `oracle_closed`; k table) → G1 batch (full, matched, review-only, open-mount) → look 1 → G2 → look 2 → G3 → look 3 (or stop) → judge sample → judge → agreement. Phase 2: `--final` → report. Phase 3: reproducer on a fresh clone → hash table → report § Proof → review → audit → PR → Bridgebuilder → merge → record branch → archive.

### 1.6 External Integrations

Docker 26.1.5 (container executor; image `loa-ablation:258`); Claude Code CLI 2.1.299 inside the image (Bedrock route, `AWS_BEARER_TOKEN_BEDROCK` passed through); codex CLI 0.162.1 via the per-run credential copy (KF-048; token valid to 2026-10-28T04:44Z — pre-flight per batch); `gh` 2.x read-only for the incident scan; git 2.x for the record branches.

### 1.7 Deployment Architecture

Everything runs on the operator's host: the lead session, the Opus subagents (implementers in linked worktrees; annotators, judge and reproducer in scratch directories), the runner (detached under `setsid nohup`), the containers. Tracked outputs land on the cycle branch; gitignored records (a2a, batch run directories minus sandboxes, packets, labels of the annotators and the judge) travel to the record branch via the temporary-index recipe.

### 1.8 Scalability Strategy

Concurrency 3 (runner); a matched cell of k ≈ 13 sessions at ≈ 5 min each runs as 13 work units, so a group of 4 PRs (4 × (2 full ≈ 40 min + 2 × 13 sessions × 5 min + 2 review-only ≈ 25 min)) ≈ 4 × 290 min ÷ 3 ≈ 6.5 h; three groups ≈ 20 h plus smoke ≈ 2 h. Looks are seconds. Annotation and judging are subagent time, not batch time.

### 1.9 Security Architecture

Credentials: only the per-run read-only copies the harness already makes reach a container (Bedrock key via env pass-through; codex `auth.json` with a placeholder refresh token). Untrusted text (transcripts, envelopes, issue bodies, PR bodies) is quoted inside fences in packets and reports and never interpreted; the packet generator fails closed if a packet would contain a label or feedback line. Secrets: every written file passes `evals/graders/no-secrets.sh`. Sandbox network: unchanged (the contamination scan is the control; declared scratch shapes). Zone: no `.claude/` write in this cycle; `evals/`, `grimoires/`, `CHANGELOG.md` only.

---

## 2. Software Stack

### 2.1 Frontend Technologies
None: Markdown reports and CLI output.

### 2.2 Backend Technologies
Bash 5.2 (bash 3.2-safe idioms), Python 3.13.5 standard library only (`json`, `math`, `random`, `statistics`, `hashlib`, `unittest`), jq 1.6, yq 4.x (mikefarah), git 2.47, bats 1.13.

### 2.3 Infrastructure & DevOps
Docker 26.1.5 with image `loa-ablation:258`; GitHub Actions (`bats-tests.yml`, `ci.yml` incl. the eval-harness step, `check-no-raw-sha256sum.yml`, `check-no-swallowed-jq.yml`); the Loa run-mode state files under `.run/`.

---

## 3. Database Design

### 3.1 Database Technology
Files: JSON, JSONL, TSV and Markdown under tracked paths (`evals/fixtures/review-prs/`, `grimoires/loa/evals/ablation-2.0-c132/`, `grimoires/loa/reports/review-catch-c132/`) and gitignored records that travel on the record branch (`evals/results/ablation-2.0/c132-*/`, `grimoires/loa/a2a/sprint-*/`).

### 3.2 Schema Design

#### Entity: `fixture.yaml` (additive)
`post_cutoff: true|false|borderline`, `model_availability: {fable-5-1: "2026-06 knowledge cutoff", opus-5-5: "2026-10-05 catalog date"}`, `contamination_note: <text>`.

#### Entity: labels TSV v2 (`labels/pr-NN.tsv`)
First line `# approved-by: <who> <date>`; header `defect_id severity category file must_match label_source source annotators agreement adjudication` (the last three optional; the 7-column header stays accepted); `label_source ∈ {review, audit, bridgebuilder, fix, fix-commit, incident}`; `must_match` text or `@L<n>`; `annotators` `"A,B"`; `agreement ∈ {agreed, adjudicated}`; `adjudication` the lead's reason or `-`. The review-derived rows of the eight existing fixtures move to `labels/review/pr-NN.tsv` (the frozen c131 set is rebuilt from there into `manifests/c131/`).

#### Entity: manifest v2 (`manifests/pr-NN.json`; schema `evals/harness/schemas/review-manifest.schema.json`)
Existing fields plus `label_set: "v2"`, per defect `label_source`, `annotators`, `agreement`, `adjudication`; `record.incidents_meta` (the scan's `origin/main` SHA). `manifests/c131/pr-NN.json` (`label_set: "c131"`, byte-identical to today's `manifests/pr-NN.json`) and `manifests/v1/` unchanged.

#### Entity: `incidents/pr-NN.tsv` + `.meta.json`
Columns `id kind ref date files excerpt`; meta `{main_sha, scanned_at, gh_queries: [...]}`.

#### Entity: annotation files (`a2a/sprint-1/annotation/pr-NN/`)
`A.json`, `B.json` (schema `annotation.schema.json`), `kappa.json` `{hunks: {table: [[a,b],[c,d]], kappa, n}, incidents: {...}, severity: {...}}`, `adjudication.md`, `adjudication.json`, `result.md`.

#### Entity: matched cell (`<batch>/a0_bare_matched/<task>-t<n>/`)
`sessions/s<i>/` (full pipeline-run dirs), `meta/cell.json` `{k, sessions: [{id, status, cost_usd, run_dir}], started, finished}`, `grading/gates-combined.md` (concatenation), `grade.json` (union + `recall_session1`, `precision_session1`, `per_session[]`, `bare_sessions`).

#### Entity: grade.json (1.3.2, additive)
`label_set`, `labels_meta[]` (per defect `label_source`, `agreement`, `review_driven`), `false_positive_rule`, `multi_credit_citations`, `bare_sessions`, `sessions_valid`, `per_session[]`, `recall_session1`, `precision_session1`, `contaminated.pattern` gains `network_egress`, `grader_version: "1.3.2"`.

#### Entity: rows.jsonl (row writer 1.5, additive)
`bare_sessions`, `sessions_valid`, `sessions_attempted`, `session_costs[]`, `all_spend_usd`, `dollar_match`, `recall_session1`, `precision_session1`, `label_set`, `batch_context`, `mount_cheval`, `registration_sha256` (copied from the MANIFEST), `attempts` (already present) now bounded at 3.

#### Entity: REGISTRATION.json (new; JCS-canonical; D-7.2)
`{schema_version: 1, cycle, preregistration_path, preregistration_sha256, corpus_sha256sums_sha256, suite_root, suite_manifest_sha256, analysis_tree_sha256, pin, label_set: "v2", seed, arms: [{id, toggles, phase_models, k_by_task}], groups: [[task…]…], looks: [n…], boundary_constant, cap_usd, addenda: []}`; its sha256 is `registration_sha256`. An addendum `REGISTRATION-N.json` repeats the fields and names `supersedes: <previous sha256>`.

#### Entity: MANIFEST.json (additive)
`registration_sha256`, `registration_path`, `preregistration_sha256`, `batch_context`, `bare_sessions_by_task: {task: k}`, `overshoot_bound_usd`.

#### Entity: fixture.yaml `exposure` block (PRD FR-1, replaces `post_cutoff`)
`exposure: {fable_5_1: post-cutoff|pre-cutoff, opus_5_5: unverified, retrieval: public-repository}`, `contamination_note`.

#### Entity: analysis outputs
`power.json` `{seed, inputs_sha256, per_n: [{n, power_at_mde, type1}], chosen_n, cap_usd, sensitivities, candidates: [{fixture, head_date, defects, post_cutoff, order}]}`; `reads.json` `{inputs: {rows_sha256, grades_sha256}, primary: {delta, ci95, ci90, se, n_prs, n_defects}, lmm: {beta, ci95, sigma_u, sigma_e}, permutation: {p, n}, looks: [{k, t, z_yes, b_yes, z_no, b_no, cp_yes, cp_no, decision}], secondary: {...}, sensitivities: {...}, placebo: {...}}`.

#### Entity: judge files (`a2a/sprint-2/judge/`)
`packets/J####.md`, `key.json`, `labels.json`, `result.json`, `result.md`.

### 3.3 Data Modeling Approach
Additive fields only; `label_set` on every grade and row so no reader can pool v2 with c131 or v1; the frozen sets keep their bytes; every generated file is deterministic and hashed.

### 3.4 Migration Strategy
Move `manifests/pr-11 … 18.json` → `manifests/c131/` (git mv; byte-identical), move review-derived labels → `labels/review/`, rebuild `manifests/c131/` from them (byte-identical check), write the new v2 manifests at `manifests/pr-NN.json`; the c131 suite root's `task.yaml` manifest paths are updated to `manifests/c131/` so cycle-131 re-grades stay reproducible (a bats case re-grades one c131 run dir and compares to its recorded grade.json).

### 3.5 Data Access Patterns
Scripts read tracked inputs and run directories; the grader reads only the run dir, task and key (DEC-0413); the union grader reads only the k session dirs; the analysis reads rows + grades; the reproducer reads the clone only.

### 3.6 Caching Strategy
None.

### 3.7 Backup and Recovery
The record branch (built with the temporary-index recipe) carries every artefact; `--resume` re-runs missing sessions or cells; the pre-registration hash binds a resumed batch to its text.

---

## 4. UI Design

### 4.1 Design System
CLI and Markdown; the report's first table is the primary read.

### 4.2 Key User Flows
Lead: `seed … ; incident-scan.sh pr-NN; annotation-packets.sh pr-NN` → dispatch annotators → `annotation_merge.py … --kappa` → adjudicate → `--build-manifest` → `power.py` → write `PREREGISTRATION.md` → `flatline-orchestrator.sh --phase spec` → integrate → hash → NOTES → `reads-c132.py --placebo --rows <existing>` → commit → smoke → batches with `--pre-registration-file` → `--look n` → judge → `--final` → report → `reproduce.sh` (subagent) → ship.

### 4.3 Page/View Structure
`report.md`: ELI5 → the answer (one sentence + interval) → Pre-registered reads (primary; secondary) → Stopping rule → Sensitivities → Placebo → Positive control → Ground truth (kappa, adjudication share) → Judge agreement → Spend → Honest caveats → Proof (reproduction, dissent records) → Files.

### 4.4 Component Architecture
Not applicable.

### 4.5 Responsive Design Strategy
Not applicable.

### 4.6 Accessibility Standards
Plain Markdown tables; every figure also in `reads.json`.

### 4.7 State Management
Run-mode state under `.run/`; batch state in `STATUS.json`/`MANIFEST.json`; spend and looks posted to NOTES with timestamps.

---

## 5. API Specifications

### 5.1 API Design Principles
Every script: usage header, explicit exit codes, deterministic output, inputs by path never by environment (bd-st02i), refusals before writes.

### 5.2 Endpoints

#### `seed-corpus-from-record.sh <sprint> <record-ref> [--feedback p1,p2] …`
New `--feedback` accepts any record-branch paths; `fixture.yaml` gains the provenance fields (values from `--post-cutoff`, `--contamination-note`, the model dates from a constant table in the script); v2 header handling in `read_labels`/`build_manifest`; exit codes unchanged.

#### `incident-scan.sh <fixture> [--out DIR] [--main-ref origin/main] [--window-days 30] [--no-gh]`
Writes `incidents/pr-NN.tsv` and `.meta.json`; exit 0 written, 1 refused (fixture or ref missing), 2 usage; `--no-gh` records `gh_queries: []`.

#### `annotation-packets.sh <fixture> [--incidents F] [--out DIR] [--context 12]`
Writes the three packet files; exit 1 when a packet line matches any line of the fixture's labels, manifests or feedback files (the match is printed, nothing written); exit 2 usage.

#### `annotation_merge.py --fixture pr-NN --a A.json --b B.json [--adjudication adj.json] --out DIR`
Without `--adjudication`: writes `kappa.json` and `adjudication.md` (exit 3 when disagreements exist, 0 when none). With it: writes the v2 label rows (`labels.rows.tsv`) and `result.md`; refuses (exit 1) an adjudication that leaves a disagreement unresolved.

#### `run-ablation.sh … --registration F [--batch-context ID]`
Records `registration_sha256`/`registration_path` and the manifest's input hashes; on `--resume` recomputes the hash and exits 2 (`registration changed: <old> ≠ <new>`) on a mismatch; matched cells planned as k session units with the 2-re-run attempt limit; `--batch-context` forwarded as argv; the reservation rule and `overshoot_bound_usd` in the MANIFEST.

#### `blind-session.sh --packets DIR --prompt FILE --model ID --out DIR [--image IMG] [--max-usd USD]`
Runs one blind role in the container executor over a packet-only sandbox (tools Read, Grep, Glob, Write; no Bash, no web tools); writes `labels.json`, `transcript.jsonl`, `cost.json`, `taint.json` (`tainted: true` with the offending event when the transcript shows a read outside the sandbox or a disallowed tool); exit 0 written, 1 session failed, 2 usage, 3 tainted.

#### `pipeline-run.sh … [--batch-context ID]`
Writes `batch_context=<id>` and `mount_cheval=ok|broken:<reason>` to `arm-evidence` before the first phase; a `broken` mount on a dissent-enabled arm refuses the launch (exit 3, `refused.json`).

#### `ablation-grade.sh --union <cell-dir> --task-id T [--suite-root DIR] [--allow-partial]`
Reads `sessions/s*/grading/gates-combined.md` and `grade.json`; writes the cell's `grading/gates-combined.md` and `grade.json`; exit 2 when a session has no grade or k mismatches `meta/cell.json`.

#### `took-effect.sh` rules `bare_sessions_matched`, `mount_cheval_ok`
As in §1.4.

#### `ablation-row.sh` 1.5 / `ablation-report.py` 1.4
Fields of §3.2; the report's matched-arm section prints the union and session-1 figures and k.

#### `judge-sample.sh --rows F --results-root DIR --out DIR --seed N [--per-stratum 10] [--min-total 150]`
Writes packets and `key.json`; prints the strata table; exit 1 when a packet would carry a provenance field.

#### `judge_agree.py --key key.json --labels labels.json --rows F --out DIR`
Writes `result.json`/`result.md`.

#### `reads-c132.py --rows F --results-root DIR --registration REGISTRATION.json --inputs INPUTS.json (--look N | --final | --placebo) --out DIR`
Inputs validated first (D-7.5): the rows file hash, every grade.json hash, the pin, the label set, the expected cells and each matched cell's session membership must match `INPUTS.json`, and every row's `registration_sha256` must equal the registration's; any mismatch exits 1 and writes nothing. Validity filter: a cell is valid when `status = completed`, every took-effect rule true, `contaminated` null (classes 1–9), `oracle_exposed_defects` empty (not applied to `a1_full_openmount`), no `refusal_fallbacks` in any phase of a non-matched cell (matched cells follow D-7.3: valid at ≥ ⌈k/2⌉ valid sessions); pairwise exclusion: a PR × trial pair enters the primary only when both arms' cells are valid; the 25 % guard: an arm whose excluded share exceeds 0.25 marks the read `inconclusive by degradation` (reported, the figures still printed). Primary: defect-weighted Δ (Σ caught / Σ defects per arm over the valid pairs), cluster bootstrap over PRs (10,000; the registration's seed; 95 % and 90 % percentile intervals; SE); PR-weighted Δ beside; REML LMM on cell recall (boundary flag); PR-level permutation p (pair-level as a sensitivity); defects per USD per arm; cost per extra defect on valid pairs and on all spend; the pipeline-independent read; the dollar-matching table. `--look N`: requires ≥ 6 valid PRs and ≥ 30 labelled defects for a decision, else CONTINUE with the reason; t_N = `SE²_planned-final / SE²_N`; z_yes = Δ̂/SE vs the calibrated boundary; z_no = (MDE − Δ̂)/SE vs the one-sided calibrated boundary; conditional power for each; decision ∈ {YES, NO, SMALL, FUTILE, CONTINUE} per the PRD D16 partition; the repeated confidence interval at the look. `--final`: every pre-registered read, then sensitivities in the registered order (frozen c131 labels, v1 labels, judge-corrected, judge-confirmed strays as defects, exact-dollar trim, pair-level permutation, 90 %, leave-one-PR-out, pr-11 in/out, degraded/contaminated excluded, PR-weighted, matched-Fable contrast). `--placebo`: 200 within-PR arm-label shuffles; pass when ≤ 8 % of the 95 % intervals exclude 0 and the mean |Δ| < 0.03. Degenerate inputs print a named status (`no_valid_pairs`, `zero_se`, `too_few_prs`, `reml_boundary`). Exit 0 written; 1 inputs invalid; 2 usage.

#### `power.py --rows <existing rows…> --results-root … --out DIR --seed N`
As in §5.3.

#### `reproduce.sh [--clone-dir D] [--rerun-sample]`
As in §1.4.

### 5.3 Pre-registered design (FR-5 … FR-8; the numbers are filled by Sprint 1 and hashed)

**Power model (D-7.7, replaces 1.0's Beta(1,1) smoothing).** Inputs: the 63 existing runs' per-defect detection vectors for `a0_bare` and `a1_full` (pr-05, 08, 12, 13 × 3 trials at the c131 labels; pr-17, 18 × 3 bare + 3 full from replication-01 and B2a) and per-run costs with diff lines. **k per PR (PRD D18):** least-squares fits `ĉ_full(L)` and `ĉ_bare(L)` of per-run cost on diff lines over the 63 runs give `k_p = round(ĉ_full(L_p)/ĉ_bare(L_p))`, floor 2, cap 30 (the Fable matched arm uses `ĉ_bare_fable` from the six bare-Fable rows). **Per-defect model:** each arm's catch probabilities follow a Beta-Binomial with a hierarchical prior fitted across defects by the method of moments (shrinkage toward the arm's grand mean, not toward 0.5), plus a **blind-spot mixture** weight `π0` per arm = the share of defects never caught in three trials minus the share expected by chance under the fitted Beta; a blind-spot defect has p = 0. Matched recall for a defect = `(1 − π0) × (1 − (1 − p)^k)`; a correlated-sessions sensitivity draws a per-defect latent `p` once and all k sessions from it (SKP-006), with `ρ ∈ {0.3, 0.6}` added as a shared per-run shock. **Design effect** applied on the logit scale to `p_full` so the expected Δ equals 0 or the MDE; the share of defects clipped at the ends is reported and a clipped share above 10 % flags the N as unreliable. **A simulated study** of N PRs draws N PR profiles with replacement from the six (bootstrap uncertainty in the profile sample reported), 2 trials per arm, applies the validity filter and pairwise exclusion with an exclusion rate `r ∈ {0, 0.05, 0.10}` per cell/session, and runs **the complete decision procedure**: looks at the pre-registered sizes, the YES / NO / SMALL / FUTILE / CONTINUE partition with the minimum-information rule, the positive-control and placebo gates as pass-through diagnostics. 2,000 studies per N ∈ {6, 8, 10, 12} (bounded by the 15 candidates). Reported per N: P(YES), P(NO), P(SMALL), P(FUTILE), P(inconclusive) at Δ = 0 and at Δ = MDE; **calibration:** the boundary constant is inflated until P(YES | Δ = 0) ≤ 0.05 and that constant is what the registration hashes; chosen N: the smallest with P(YES | Δ = MDE) ≥ 0.80 under the calibrated constant; sensitivities: profile spread × 0.5 / × 1.5, k ± 3, `ρ`, `r`. Cap = N × (full 2 × 22 + matched-Opus 2 × 22 + matched-Fable 2 × 22 + review-only 2 × 12 + smoke 24) + |G1| × 2 × 20 (open mount) + blind sessions ≈ 2 × N × 3 + judge 30 + reproduction rerun 80 + dissents 60, × 1.25, rounded up to the next 50 USD. **Affordable-N fallback (PRD FR-6, SKP-009):** if the chosen N's cap exceeds the planning envelope, N is the largest grid value whose cap fits and the registration states the power achieved; if that power is below 0.50 the registration declares the study exploratory and the primary read is reported inconclusive-by-design.

**Groups and looks (D-7.5).** The chosen fixtures in a seeded order (post-cutoff first; pr-11 last and flagged) form groups so that the first look has at least 6 PRs: N = 6 → one look; 8 → 6, 8; 10 → 6, 10; 12 → 6, 9, 12; information fraction at look k = `SE²_planned-final / SE²_k` (the planned final SE from the simulation at the chosen N); no decision at a look with fewer than 6 valid PRs or 30 labelled defects.

**Boundaries.** Lan–DeMets O'Brien–Fleming spending, two-sided α 0.05 for YES (the uncalibrated published values at 1/3, 2/3, 1 are 3.710, 2.511, 1.993), one-sided α 0.025 spending on z_no for NO, both multiplied by the simulation-calibrated constant; outcomes under the PRD D16 partition; futility non-binding at conditional power < 0.20 for both; the final report prints the naive interval and the repeated confidence interval at the stopping look.

**Positive control (D-7.10).** `a1_full_openmount − a1_full` on G1's pairs, excluding PRs whose closed-mount recall exceeds 0.9 (no headroom): pass when the point estimate > 0 and the oracle detector shows exposure in at least one open run; the 90 % interval and the expected effect (cycle-131 R1: +0.067 on pr-17) are reported; no exposure in any open run reads "control not exercised"; a negative point estimate with verified exposure reads "void" and every other read is reported void.

**Placebo (PRD D17).** 200 seeded within-PR arm-label shuffles through the primary read: pass when ≤ 8 % of the 95 % intervals exclude 0 and the mean |Δ| < 0.03 — on the 63 existing rows before Phase 1 and on the new rows before `--final`; deterministic synthetic cases test the implementation separately.

**Spend.** The runner's reservation rule is the gate (no unit launches when spent + reservations + its estimate would pass the cap); the overshoot bound (concurrency × per-unit cap) is stated; a stop inside a group leaves a partial group whose valid pairs enter the next look with the information fraction computed from them. D-5.1, D-5.3.

---

## 6. Error Handling Strategy

### 6.1 Error Categories
- **Refusals before spend** (exit 2/3, nothing written): changed pre-registration on resume; broken mount for a dissent-enabled arm; a packet that would leak a label; an unresolved adjudication; a k mismatch in a union.
- **Degraded cells** (rows carry the reason): refusal fallbacks (KF-051), transport errors, cap failures, interrupted sessions — excluded pairwise by the validity filter and counted in the 25 % guard.
- **Contamination** (KF-046): rows marked `contaminated`, hand-read before the final read under the declared scratch shapes; never silently re-included.
- **Credential horizon** (KF-048): the codex pre-flight refuses a batch whose horizon passes the token's expiry.
- **Analysis inputs**: hash mismatches or unreadable rows exit 1; no partial `reads.md` is written.

### 6.2 Error Response Format
Harness: `refused.json` / row fields; analysis: a one-line stderr reason and a non-zero exit; every refusal and every degraded cell is listed in NOTES with the batch post.

### 6.3 Logging Strategy
`run.log`/`driver.log` per batch; NOTES dated entries for pre-registration, spend posts, looks and decisions; DEC rows for judgments; the audit chain (`audit_emit`) untouched.

---

## 7. Testing Strategy

### 7.1 Testing Pyramid
Unit: `evals/analysis/c132/tests/` (unittest: bootstrap seed reproducibility; REML on a textbook two-group dataset within 1e-6; permutation p on a constructed case; OBF boundaries at (1/3, 2/3, 1) within 0.02 of 3.710/2.511/1.993; conditional power at known values; placebo on shuffled synthetic data covers 0; validity filter and 25 % guard; kappa on a textbook 2 × 2). Harness bats (`evals/tests/`): matched-cell planning/resume/union with stub CLIs (k = 3); `bare_sessions_matched`; `--pre-registration-file` + resume refusal; `--batch-context`; `mount_cheval`; `dissent_absent_reason` from evidence; toggle-vocabulary parity; packet generator leak check; judge sampler strata; incident scanner on a synthetic repo (`--no-gh`); seeder provenance fields and v2 header; manifest migration byte-identity (c131 re-grade equality). Integration: the smoke (one `a1_full` + one BARE per PR). System: the placebo on existing rows; the reproduction.

### 7.2 Testing Guidelines
Test-first per task; scratch roots under `$BATS_TEST_TMPDIR`; no live model calls in tests; stub CLIs from `evals/tests/fixtures/*-stub.sh`; `bash -n` on scripts; every new field has a `--validate` case.

### 7.3 CI/CD Integration
`bats-tests.yml` (tests/unit + evals/tests), `ci.yml` eval-harness step, `check-no-raw-sha256sum`, `check-no-swallowed-jq`, repo-map validate; the analysis unittest runs through the bats wrapper.

---

## 8. Development Phases

### Phase 0 — Sprint 1: ground truth, power, pre-registration, harness
FR-1 (seed sprints 255–265; provenance), FR-2 (incident scan, packets, two annotators, kappa, adjudication, v2 manifests, frozen sets migration), FR-3 (matched cells: runner, union grader, took-effect, row, report), FR-5 (analysis module + unit tests; placebo on the 63 existing rows committed), FR-6 (power → N, cap, order), FR-7 (PREREGISTRATION.md; Flatline spec review; hash in NOTES), FR-11 (five beads; the rc.7 hold line). Exit: `evals/tests/` + unittest green; placebo committed; hash in NOTES; Flatline record; no arm spend.

### Phase 1 — Sprint 2: batches
Pin recorded; suite root frozen + self-check; smoke (k table, `oracle_closed`); G1 (+ open-mount), look 1; G2, look 2; G3, look 3 (or stop at a boundary / cap); judge sample + judge + agreement. Exit: rows at the pin in `reports/review-catch-c132/rows.jsonl`; looks in NOTES; spend posts.

### Phase 2 + 3 — Sprint 3: reads, report, proof, ship
`--final`; report; DEC rows per read; REPRODUCE.md + reproducer run; placebo on new rows; positive control; CHANGELOG (rc.7 heading after the proof); PR; review; audit; Bridgebuilder; merge; record branch; archive (through the fixed `archive-cycle.sh`).

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| Sessions of a matched cell are not independent (shared sandbox) | each session is its own pipeline-run dir; the union reads only outputs |
| k sessions blow the per-run cap or the wall clock | the cap applies per session (USD 30 is far above one bare session); sessions are runner work units |
| The REML/OBF implementations are wrong in stdlib | textbook-value unit tests; the published OBF table; the implementer documents the recursion |
| Annotators peek (filesystem access) | packets contain nothing else; the brief forbids opening the corpus; the final message must list the files read; recorded as a limitation |
| The incident scan is irreproducible (`gh` changes) | the scan records a snapshot and the `origin/main` SHA; the reproduction uses the recorded TSV |
| Migration of manifests breaks cycle-131 re-grades | `manifests/c131/` byte-identical; the c131 root's task paths updated; a re-grade equality test |
| The pre-registration needs a correction after hashing | addendum files with their own hashes; the batch MANIFEST records the hash it ran under |
| Two sprint counters (`global_sprint_counter` vs `next_sprint_number`) collide numerically with the bug sprints | the sprint plan sets `next_sprint_number` past 268 and records the reason (follow-up bead for the ledger) |
| Matched cells excluded far more often than full cells (k sessions, each a chance of refusal or contamination) | session-level validity (D-7.3): valid at ≥ ⌈k/2⌉ sessions; infrastructure re-runs capped at 2; the intention-to-run table |
| The power model saturates at k ≈ 13 | latent-difficulty + blind-spot mixture (D-7.7); clipping diagnostics; the correlated-sessions sensitivity |
| Labels remain downstream of the production pipeline | `review_driven` tag and the pipeline-independent secondary read (D-7.6); the judge-confirmed-stray sensitivity (PRD D14) |
| Blind roles can read the corpus | containerized packet-only sessions with transcripts as access logs (D-7.1) |
| Credentials in network-enabled sandboxes (SKP-031) | pre-existing harness exposure (cycle-130 audit DISS-C-001, bead bd-lfrkn): the per-run copies carry a placeholder refresh token and the Bedrock key by env; short-lived credentials or a proxy are not available this cycle — documented, not solved |

---

## 10. Open Questions

- Should the primary be PR-weighted rather than defect-weighted? D-5.1 picks defect-weighted (more defects, more information) with PR-weighted beside; the pre-registration fixes it.
- If power at the affordable N is below 0.80, run at that N and say so (PRD Appendix D default) — the pre-registration states the achieved power.
- Should `a1_review_only` also get an exact-dollar comparison (review-only ≈ 0.5 × full)? Reported as a secondary read; not a primary.
- Is a 30-day incident window right? It bounds the scan; later incidents are listed in the report but not labelled (the pre-registration fixes 30).

---

## 11. Appendix

### A. Glossary
Cell — one arm × task × trial; for the matched arm, k sessions. Session — one `pipeline-run.sh` BARE run. Look — an interim read. Boundary — the z threshold at a look. Label set — v2 (re-derived), c131 (curated review-derived), v1 (original).

### B. References
`grimoires/loa/prd.md` (cycle-132); `grimoires/loa/context/cycle-132-brief.md`; `evals/harness/{run-ablation,pipeline-run,ablation-grade,ablation-row,took-effect,freeze,seed-corpus-from-record}.sh`; `evals/harness/lib/sandbox-mount.sh`; `evals/graders/recall-vs-defects.sh`; `evals/suites/ablation-2.0.yaml`; `grimoires/loa/evals/ablation-2.0-c131/`; `~/.cache/loa/cycle-131/scripts/reads-c131.py` (pattern); Lan & DeMets (1983) spending functions; O'Brien & Fleming (1979); Armitage, McPherson & Rowe (1969) recursion; DEC-0413, DEC-0626, DEC-0638, DEC-0640, DEC-0645, DEC-0661 … DEC-0672; KF-046, KF-048, KF-050, KF-051.

### C. Change Log
- 1.0 (2026-10-21): initial design.
- 1.1 (2026-10-21): Flatline SDD review integrated (§11.E, DEC-0692) — blind containerized sessions, the registration manifest, session-level validity for matched cells, PR-level permutation, minimum-information rules, the review-driven tag and the pipeline-independent read, the latent-difficulty power model, the incident temporal rule, defects per USD and dollar matching, the control's saturation exemption; the PRD's D13–D18 folded in (matched-Fable arm, egress class, outcome partition, placebo distribution, k from existing runs, exposure fields).

### D. Design decisions taken on the operator's behalf
- **D-1.1** (DEC-0673) — the seeder gains `--feedback` paths and the provenance fields rather than a new seeder.
- **D-2.1** (DEC-0680) — incidents are compiled by a scanner with a recorded snapshot (fix commits in a 30-day window, issues citing the files, Bridgebuilder rounds, KF entries).
- **D-2.2** (DEC-0674) — the annotation unit is the fix hunk; kappa is on hunk verdicts; the lead adjudicates; rows are one per anchor line with text or `@L<n>`.
- **D-2.3** (DEC-0681) — labels TSV v2 header with three optional columns; `label_source` enum extended; frozen sets moved to `manifests/c131/` and `labels/review/`.
- **D-3.1** (DEC-0675) — a matched cell is k independent `pipeline-run` sessions in `sessions/s<i>/`, union-graded from their outputs only.
- **D-3.2** (DEC-0676) — sessions are runner work units (concurrency, resume); the cell row is written once all k land.
- **D-4.1** (DEC-0682) — grader 1.3.2 adds `label_set`, union mode and `false_positive_rule`; the citation rule is unchanged.
- **D-5.1** (DEC-0683) — primary Δ is defect-weighted; PR-weighted beside; REML LMM on cell recall; permutation within PR × trial pairs.
- **D-5.2** (DEC-0677) — the pre-registration hash binds the batch: `--resume` refuses a changed text.
- **D-5.3** (DEC-0684) — power model as in §5.3 (Beta-smoothed per-defect probabilities, matched = 1 − (1 − p)^k, 2,000 studies per N).
- **D-5.4** (DEC-0678) — the report is `grimoires/loa/reports/review-catch-c132/` (DEC-0671) with `rows.jsonl` tracked beside it.
- **D-6.1** (DEC-0679) — the cycle's sprints take global ids past the bug sprints (`next_sprint_number` set to 269).

- **D-7.1** (DEC-0694) — blind roles (annotators, judge) run as containerized packet-only `claude -p` sessions through `blind-session.sh`; transcripts are the access log.
- **D-7.2** (DEC-0695) — `REGISTRATION.json` (JCS-canonical) binds the pre-registration text, corpus sums, suite manifest, analysis-code tree hash, pin, arm routing and addenda; its sha256 is the batch's hash.
- **D-7.3** (DEC-0696) — matched cells: infrastructure failures re-run at most twice; refusal-fallback and contaminated sessions are kept as invalid; a cell is valid at ≥ ⌈k/2⌉ valid sessions; an intention-to-run table beside complete pairs.
- **D-7.4** (DEC-0693) — PR-level permutation (all of a PR's cells swap together); the within-pair swap is a sensitivity.
- **D-7.5** (DEC-0697) — minimum information: no decision before 6 valid PRs and 30 labelled defects; named statuses for degenerate inputs; a mandatory input manifest.
- **D-7.6** (DEC-0698) — every fix hunk carries `review_driven`; the pipeline-independent read (non-review-driven + incidents) is pre-registered beside the primary.
- **D-7.7** (DEC-0699) — the power model uses latent difficulty with a blind-spot mixture and a logit-scale design effect with clipping diagnostics.
- **D-7.8** (DEC-0700) — one incident window (merge date → scan date) across sources; paginated `gh` with completeness recorded; full evidence saved.
- **D-7.9** (DEC-0701) — defects per USD per arm as a pre-registered secondary read; dollar matching within 25 % else flagged.
- **D-7.10** (DEC-0702) — the positive control pre-registers its expected effect, exempts saturated PRs and requires detector-verified exposure.

### E. Flatline integration (SDD review, 2026-10-21T01:07–01:18Z)
Two voices (claude-headless = Fable 5.1, gpt-5.5 via codex), 27 blockers (4 CRITICAL, 23 HIGH), cross-scoring degraded (KF-041 shape, 0 % agreement, `verdict_quality` DEGRADED); the raw reviews were read in full and integrated by judgment (DEC-0692). Record: `grimoires/loa/a2a/flatline/sdd-review-c132.json`.

**Adopted (SDD 1.1):** session-level validity, attempt limits and the intention-to-run table (SKP-004, SKP-012 → D-7.3); complete adjudicated records, localization and grouping agreement, cross-source deduplication (SKP-021, SKP-022 → §1.4 Merge, D-4.1 distinct-defect semantics); containerized blind sessions (SKP-019 → D-7.1); the registration manifest and the mandatory input manifest (SKP-026, SKP-027 → D-7.2, D-7.5); the weighted judge estimator and unit definitions (SKP-023 → §1.4 Judge); exposure fields instead of availability claims (SKP-025 → PRD FR-1, already); the affordable-N fallback and the exploratory declaration (SKP-009 → §5.3); the reservation rule and mid-group inference (SKP-013 → §5.3 Spend); PR-level permutation (SKP-014 → D-7.4); the complete-procedure simulation with calibration, the minimum of 6 valid PRs before any decision, the repeated confidence intervals (SKP-002 ×2, SKP-003 ×2, SKP-007 → §5.3, D-7.5, PRD D16); degenerate-input statuses (SKP-015 → D-7.5); the incident temporal rule, pagination and evidence (SKP-017 → D-7.8); the control's expected effect, saturation exemption and exposure verification (SKP-011 → D-7.10); the placebo distribution (SKP-010 → PRD D17); the latent-difficulty power model and the correlated-sessions sensitivity (SKP-002 gpt, SKP-006 → D-7.7); k from the existing runs before the hash (SKP-005 → PRD D18); defects per USD and the dollar-matching tolerance (SKP-004 opus → D-7.9); the `review_driven` tag and the pipeline-independent read (SKP-001 gpt → D-7.6); the outcome partition (SKP-001 opus → PRD D16).

**Not adopted, with reasons:** short-lived credentials or an authenticated egress proxy for the sandboxes (SKP-031) — pre-existing harness exposure recorded in cycle-130 (DISS-C-001, bead bd-lfrkn), not buildable and validatable before Phase 1; documented in §1.9 and §9. A defect-level logistic GLMM — stdlib limitation, named. Replacing recall with defects-per-dollar as the primary (SKP-004 opus, in part) — recall at matched spend remains the primary because it is the pre-registered, pairwise-testable estimand; defects per USD is a co-reported secondary with intervals.
