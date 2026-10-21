# Software Design Document: The conclusive review-catch answer (cycle-132)

**Version:** 1.0
**Date:** 2026-10-21
**Author:** Architecture Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (cycle-132, FR-1 … FR-11, Appendix E D1–D12 = DEC-0661 … DEC-0672)
**Status:** Draft 1.0 — autonomous run; design-level decisions taken on the operator's behalf are listed in §11.D (DEC-0673 … DEC-0684); the Flatline integration goes in §11.E
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
- **Behaviour:** given a fixture, read `fixture.yaml` (`fix_commit`, its date, `sprint`), compute the head-changed file set from `head.diff`; (a) `git log origin/main --since=<fix date> --until=<fix date + 30 d> --format=… -- <files>` keeping commits whose subject starts with `fix` (the diff of each, restricted to the files); (b) `gh issue list --state all --limit 200 --search "<basename>"` for each changed file's basename, keeping issues whose body cites a changed path; (c) the record branch's `bridgebuilder*.md` / `bridgebuilder-triage*.md` for the sprint; (d) `grep -n` of each changed path in `grimoires/loa/known-failures.md`. Output `incidents/pr-NN.tsv` (`id`, `kind` ∈ {fix-commit, issue, bridgebuilder, kf}, `ref`, `date`, `files`, `excerpt ≤ 400 chars`) plus `incidents/pr-NN.meta.json` recording the `origin/main` SHA and the `gh` query time, so the scan is reproducible from that SHA (the `gh` results are a snapshot: recorded, not re-queried by the reproduction). D-2.1.

#### Annotation packets and merge (`evals/harness/annotation-packets.sh`, `evals/analysis/c132/annotation_merge.py`, new)
- **Purpose:** give two blind annotators the same data and nothing else; turn their labels into kappa, an adjudication list and v2 label rows (FR-2).
- **Packets:** `packets/pr-NN/codebook.md` (fixed text: what counts as a defect at head; the not-defect classes test/docs/refactor/style/follow-on; severity scale; anchors are head-side line numbers of the wrong behaviour, several allowed; one group id per distinct defect), `hunks.md` (every hunk of `git diff <head>..<fix> -- <fixture files>` with id `H01 …`, path, head-side range, 12 lines of head context, the hunk text), `incidents.md` (every incident row with id `I01 …`). No line from any `labels/`, `manifests/`, feedback file or run directory may appear: the generator greps its own output against those sources and fails closed. Deterministic (sorted paths, fixed context, no timestamps).
- **Annotator output** (one JSON per annotator, schema `evals/harness/schemas/annotation.schema.json`): `hunks.<id>: {verdict: defect|not-defect, not_defect_class?, group: D<k>|null, file, anchor_lines: [int…], description, severity, category}`, `incidents.<id>: {verdict: defect-at-head|not-at-head, group, file, anchor_lines, description, severity}`.
- **Merge:** Cohen's kappa on hunk verdicts (2 × 2 table), on incident verdicts, and on severity among agreed defects; disagreements written to `adjudication.md` with both labels; the lead's `adjudication.json` (`{id: {verdict, group, reason}}`) resolves them; groups are merged across annotators by shared hunks; output rows (one per anchor line; `must_match` = the head line's text when unique else `@L<n>`; `label_source` fix-commit | incident; `annotators "A,B"`; `agreement agreed|adjudicated`; `adjudication` reason) appended to `labels/pr-NN.tsv` under the v2 header after the review-derived rows are moved to `labels/review/pr-NN.tsv` (the frozen review set stays rebuildable). D-2.2.

#### Matched-bare cells (`evals/harness/run-ablation.sh`, `evals/harness/ablation-grade.sh --union`, `evals/harness/took-effect.sh`, `evals/harness/ablation-row.sh`)
- **Purpose:** the compute-matched arm (FR-3, DEC-0663).
- **Design:** arm `a0_bare_matched` (`toggles: {loa_mount: false, bare_sessions: matched}`, `task_types: [review-catch]`). A cell (arm × task × trial) is **k independent sub-runs**, each a normal `pipeline-run.sh` invocation with the `a0_bare` phase plan (one BARE session, Opus 5.5, `--effort high`, its own sandbox, transcript, cost ledger) in `<cell-dir>/sessions/s<i>/`; k = the task's `review_catch.bare_sessions_matched` (fixed by the pre-registration from the smoke; floor 2, cap 30). The runner treats each session as a work unit for `--concurrency` and for `--resume` (a missing or failed session re-runs alone); when all k sessions have landed it writes `<cell-dir>/meta/cell.json` (k, session ids, per-session cost and status), calls `ablation-grade.sh --union <cell-dir>` and then `ablation-row.sh` once for the cell. **Union grading:** each session is graded on its own (its `grade.json`, DEC-0413 invariants intact); the union step reads only the k sessions' `grading/gates-combined.md` and `grade.json`, writes `<cell-dir>/grading/gates-combined.md` as the concatenation with `## session s<i>` separators, and grades it with the same citation reduction → `grade.json` with `recall` (union), `recall_session1` and `precision_session1` (session 1 alone), `bare_sessions: k`, `per_session: [{session, recall, detected, false_positives, cost_usd}]`, `label_set`. **Took-effect** `bare_sessions_matched`: exactly k session dirs; each session passes `no_dot_claude`, `no_system_prompt`, `no_audit_rows`, `integrity_clean`; each has one completed BARE phase; k equals the task's value. **Row:** `bare_sessions`, `session_costs[]`, `recall_session1`, `precision_session1`, `cost_usd = Σ sessions`, `phases[]` = the k BARE records, status `completed` only when every session completed (a `cap_failure` or `interrupted` session makes the cell that status). D-3.1, D-3.2.
- **Rejected inside this design:** k sessions inside one sandbox (a later session could read an earlier session's output; independence lost).

#### Grader (`evals/harness/ablation-grade.sh`, `evals/graders/recall-vs-defects.sh` 1.3.2)
- **Changes:** `--union <cell-dir>` mode (above); `label_set: v2|c131|v1` from the task's `review_catch.manifest` path (`manifests/`, `manifests/c131/`, `manifests/v1/`); v2 manifest fields read and passed through to `grade.json.labels_meta` (per defect `label_source`, `agreement`); bd-9zmfn: `false_positives` / `findings_refuted` computed under the same rule as the decision statistic (`pm3` on the task's manifest) and the rule named in `grade.json.false_positive_rule`; `grader_version 1.3.2`. The citation rule itself is unchanged (DEC-0638: `recall_pm3` is the decision statistic). D-4.1.

#### Took-effect (`evals/harness/took-effect.sh`)
- **New rule:** `bare_sessions_matched` (above). bd-56nn6: pipeline-run writes `mount_cheval=ok|broken:<reason>` before the first phase (a `python3 -I -c "import loa_cheval"` probe against the mounted adapters) and the rule `mount_cheval_ok` is on every dissent-enabled mounted arm (a `broken` mount is a refused launch, not a degraded row — KF-050 made it an expected absence; now it is caught before spend).

#### Row writer and report (`evals/harness/ablation-row.sh` 1.5, `evals/harness/ablation-report.py` 1.4)
- **Changes:** fields in §3.2; bd-jszcp: `dissent_absent_reason: disabled` only when `meta/arm-evidence.txt` carries `dissent=false` written by the harness (never from the sandbox `.loa.config.yaml`); report partitions by `label_set` and by `bare_sessions`; a matched cell prints k and the session-1 figures beside the union.

#### Runner (`evals/harness/run-ablation.sh`)
- **Changes:** `--pre-registration-file F` → `MANIFEST.json.preregistration_sha256` + `preregistration_path`; `--resume` recomputes the hash and exits 2 on a mismatch (the batch is bound to the text it was registered under); bd-st02i: `--batch-context <id>` passed to `pipeline-run.sh` as an argv flag and recorded in `arm-evidence` (the `LOA_ABLATION_BATCH_CONTEXT` env var is read no more); session work units for matched cells (above). D-5.2.

#### Toggle vocabulary (`evals/harness/lib/sandbox-mount.sh`, `validate-suite.sh`)
- **Changes:** `bare_sessions: matched` accepted (`loa_mount: false` required with it); bd-gdl5s: `print_toggle_vocabulary` emits the key list and value forms, and `validate-suite.sh` / `pipeline-run.sh --dry-run` read it instead of their hand-kept copies (a parity bats case pins equality).

#### Judge sampler and agreement (`evals/harness/judge-sample.sh`, `evals/analysis/c132/judge_agree.py`, new)
- **Purpose:** validate grader 1.3.2 against a blind Opus judge on a stratified sample (FR-4, DEC-0667).
- **Sampling:** items = every (finding, labelled defect) decision the grader made in the batch rows' run directories: `credited` (a citation inside ±3 of a site), `near-miss` (the nearest citation within 4–20 lines of a site, not credited), `far-miss` (a labelled defect with no citation within 20 lines; the item quotes the finding closest in the same file if any), and `stray` (a cited region outside every window). Strata = arm × PR × class; per stratum min(all, 10), total ≥ 150 (if below, raise the per-stratum cap uniformly); seeded (20261021). Packets (`judge/packets/J0001.md …`): the finding's text (the paragraph or line holding the citation), the cited lines of `head/<file>` (±5), the labelled defect's description and anchor lines (for `stray`: only the finding and its cited lines), no arm, trial or grader decision; `judge/key.json` (outside the packets) maps items to their provenance.
- **Judge output:** `judge/labels.json` `{J0001: {verdict: describes|partially|does-not-describe | real|style|wrong|not-a-finding, note}}`.
- **Agreement:** `judge_agree.py` → `result.json`/`result.md`: per stratum and pooled agreement between grader credit and judge `describes` (with `partially` reported both ways), Cohen's kappa with a bootstrap 95 % interval, the confusion table, and the judge-corrected recall and precision per arm (credits the judge rejects removed; near-misses the judge accepts added; strays the judge calls `real` counted as real for corrected precision).

#### Analysis module (`evals/analysis/c132/`, new; stdlib only)
- `stats.py`: `cluster_bootstrap(cells, n=10000, seed, level)` resampling PRs with replacement, returning the point estimate, percentile interval and SE; `reml_lmm(cells)` — model `y_{p,t,a} = μ + β·[a = full] + u_p + ε`, `u_p ~ N(0, σ_u²)`, `ε ~ N(0, σ_e²)`, REML profile likelihood on `λ = σ_u²/σ_e²` maximised by golden-section search, GLS for `β`, Wald 95 % interval; `permutation_test(cells, n=10000, seed)` swapping the two arms within each PR × trial pair, two-sided p; `obf_boundaries(fractions, alpha=0.05)` — Lan–DeMets O'Brien–Fleming spending `α*(t) = 2 − 2Φ(z_{α/2}/√t)` with boundaries solved by the Armitage–McPherson–Rowe recursion on a 2,000-point grid; `conditional_power(z_k, t_k, boundary_final, drift)`; `placebo(cells, seed)` permuting arm labels within PR and re-running the primary read.
- `reads.py` (CLI `reads-c132.py`): loads `rows.jsonl` + each row's `grade.json` (defect-level detected sets), applies the validity filter (§5.2), builds paired cells per PR × trial, and writes `reads.md`/`reads.json` for `--look n` (the boundary table and the decision), `--final` (pre-registered reads first, sensitivities after, in the pre-registered order), `--placebo` (the zero-band check). Byte-identical across runs (sorted keys, fixed formats, no timestamps; the input hashes are printed).
- `power.py`: the simulation of §5.3 → `power.md`/`power.json` (per-N table, chosen N, the cap, sensitivity tables, the candidate-fixture table with the seeded order).
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
`label_set`, `labels_meta[]`, `false_positive_rule`, `bare_sessions`, `per_session[]`, `recall_session1`, `precision_session1`, `grader_version: "1.3.2"`.

#### Entity: rows.jsonl (row writer 1.5, additive)
`bare_sessions`, `session_costs[]`, `recall_session1`, `precision_session1`, `label_set`, `batch_context`, `mount_cheval`, `preregistration_sha256` (copied from the MANIFEST).

#### Entity: MANIFEST.json (additive)
`preregistration_sha256`, `preregistration_path`, `batch_context`, `bare_sessions_by_task: {task: k}`.

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

#### `run-ablation.sh … --pre-registration-file F [--batch-context ID]`
Records `preregistration_sha256`/`preregistration_path`; on `--resume` recomputes the hash and exits 2 (`pre-registration text changed: <old> ≠ <new>`) on a mismatch; matched cells planned as k session units; `--batch-context` forwarded as argv.

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

#### `reads-c132.py --rows F --results-root DIR --prereg PREREGISTRATION.md (--look N | --final | --placebo) --out DIR [--seed N]`
Validity filter: a cell is valid when `status = completed`, every took-effect rule true, `contaminated` null, `oracle_exposed_defects` empty (not applied to `a1_full_openmount`), no `refusal_fallbacks` in any phase; pairwise exclusion: a PR × trial pair enters the primary only when both arms' cells are valid; the 25 % guard: an arm whose excluded share exceeds 0.25 marks the read `inconclusive by degradation` (reported, the figures still printed). Primary: defect-weighted Δ (Σ caught / Σ defects per arm over the valid pairs), cluster bootstrap over PRs (10,000; seed 20261021; 95 % and 90 % percentile intervals; SE); PR-weighted Δ (mean of per-PR Δ) beside; REML LMM on cell recall; permutation p. `--look N`: z_yes = Δ̂/SE vs the OBF boundary at information fraction t_N (defects accrued / planned total); z_no = (MDE − Δ̂)/SE vs the one-sided boundary (α 0.025 spending); conditional power for each under the current drift; decision ∈ {YES, NO, FUTILE, CONTINUE}. `--final`: every pre-registered read, then sensitivities (frozen c131 labels, v1 labels, judge-corrected, exact-dollar trim, 90 %, leave-one-PR-out, pr-11 in/out, degraded/contaminated excluded, PR-weighted). `--placebo`: arm labels permuted within PR (seed), the primary read; pass when |Δ| < 0.03 and the 95 % interval covers 0. Exit 0 written; 1 inputs unreadable or hashes mismatch `--expect`; 2 usage.

#### `power.py --rows <existing rows…> --results-root … --out DIR --seed N`
As in §5.3.

#### `reproduce.sh [--clone-dir D] [--rerun-sample]`
As in §1.4.

### 5.3 Pre-registered design (FR-5 … FR-8; the numbers are filled by Sprint 1 and hashed)

**Power model.** Inputs: the 63 existing runs' per-defect detected sets for `a0_bare` and `a1_full` (pr-05, 08, 12, 13 × 3 trials at the c131 labels; pr-17, 18 × 3 bare + 3 full from replication-01 and B2a); per-PR cost ratio `r_p = cost(a1_full)/cost(a0_bare)`. Per PR, per defect: `p_bare(d)`, `p_full(d)` as Beta(1,1)-smoothed trial means. Matched: `p_matched(d) = 1 − (1 − p_bare(d))^k_p`, `k_p = round(r_p)`. A simulated study of N PRs draws N PR profiles with replacement from the six, draws 2 trials per arm from Bernoulli(p), shifts `p_full` multiplicatively so the expected Δ equals the design effect (0 or 0.10), and applies the primary test (cluster bootstrap, 1,000 resamples for speed, 95 %). 2,000 studies per N ∈ {6, 8, 10, 12, 14, 16}; power = share with the interval above 0 at Δ = 0.10; type I = share excluding 0 at Δ = 0. Chosen N: the smallest with power ≥ 0.80; sensitivities: between-PR profile spread × 0.5 / × 1.5 (by shrinking/stretching profiles toward/away from the grand mean), k ± 3. Cap = N × (2 × 22 + 2 × 22 + 2 × 12 + 24) + |G1| × 2 × 20 + 80 + 60, × 1.25, rounded up to the next 50 USD.

**Groups and looks.** The chosen fixtures in a seeded order (post-cutoff first; pr-11 last and flagged) split into three groups of ⌈N/3⌉; information fraction at look k = labelled defects accrued ÷ planned total.

**Boundaries.** Lan–DeMets O'Brien–Fleming spending, two-sided α 0.05 for YES (the published values at 1/3, 2/3, 1 are 3.710, 2.511, 1.993); NO uses one-sided α 0.025 spending on z_no; futility non-binding at conditional power < 0.20 for both.

**Positive control.** `a1_full_openmount − a1_full` on G1's cells: pass when the point estimate > 0 and the 90 % interval's lower bound ≥ 0; otherwise every read is reported void.

**Placebo band.** |Δ| < 0.03 and the 95 % interval covers 0, on the 63 existing rows before Phase 1 and on the new rows before `--final`.

**Spend halt.** The batches halt when `spend.sh` (cycle total since the kickoff timestamp) exceeds the cap; nothing else halts them except a fired boundary. D-5.1, D-5.3.

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

### E. Flatline integration (SDD review)
Pending: the SDD Flatline run follows validation; its blockers and the integration record will be appended here with their DEC row.
