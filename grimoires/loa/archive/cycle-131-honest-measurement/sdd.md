# Software Design Document: Honest review-catch measurement (cycle-131)

**Version:** 1.0
**Date:** 2026-10-19
**Author:** Architecture Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (cycle-131, FR-1 … FR-7, Appendix E D1–D3 = DEC-0610 … DEC-0612)
**Status:** Draft 1.1 — autonomous run; design-level decisions taken on the operator's behalf are listed in §11.D (DEC-0613 … DEC-0619, amended by DEC-0622) and the Flatline integration in §11.E (DEC-0623)
**Pin:** every cycle-131 arm runs the Sprint 2 completion commit of `feature/cycle-131-honest-measurement`; image `loa-ablation:258` unchanged (the framework is copied from the source tree into the bind-mounted sandbox, so a harness or framework change needs no image rebuild — `pipeline-run.sh:781-782`, `sandbox-mount.sh:131`)
**Branch:** `feature/cycle-131-honest-measurement` from `main e9a66e16`

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

The cycle changes the evaluation harness under `evals/` (sandbox materialisation, took-effect rules, grader, row writer, report, runner, suite) and one framework script family (`adversarial-review.sh`, its finding schema and docs), then uses them to run four pre-registered batches. Nothing in the shipped pipeline's defaults changes; the measurement does.

> From prd.md: "Sprint 1 changes the eval harness … Sprint 2 adds three arms … and runs four pre-registered batches under the closed mount. Sprint 3 reads them under rules written before the rows exist" (Executive Summary)

### 1.2 Architectural Pattern

**Pattern:** the existing pipeline-of-scripts (`run-ablation.sh` → `pipeline-run.sh` → container → `ablation-grade.sh` → `ablation-row.sh` → `ablation-report.py`), extended at four seams: the sandbox materialiser, the per-trial took-effect rules, the grader's citation rule and oracle scan, and the arm toggle vocabulary. Every change sits behind an existing extension point (toggles, `took_effect` rule ids, grader version, suite declarations), so the shipped behaviour is reproducible by not declaring the new arms and not enabling the new knob.

### 1.3 Component Diagram

```
suite ablation-2.0.yaml ──arms/toggles/took_effect──▶ run-ablation.sh ──trial──▶ pipeline-run.sh
                                                          │ (--allow-partial → freeze --check, grader)      │
                                                          ▼                                                 ▼
                                                     MANIFEST.json                              lib/sandbox-mount.sh
                                                                                                  mount_prompt_surface  (copies the framework tree)
                                                                                                  overlay_answer_paths  (FR-1, review-catch)
                                                                                                  apply_arm_toggles     (dissent, bare_model)
                                                                                                        │
                                                                                                        ▼
                                                                    docker 26.1.5: run … -v <ws>:/workspace  claude -p <phase>
                                                                                                        │ transcripts, envelopes, feedback
                                                                                                        ▼
                               took-effect.sh (oracle_closed, bare_model_fable, review_only_phases, no_review_dissent_envelope)
                                                                                                        ▼
                               ablation-grade.sh 1.3 (recall + recall_pm3 via recall-vs-defects.sh 1.3; oracle_exposed_defects; KF-046 class 7)
                                                                                                        ▼
                               ablation-row.sh 1.4 (defect_catch_rate_pm3, defects_missed_pm3, oracle_exposed_defects, dissent_absent_gates)
                                                                                                        ▼
                               ablation-report.py 1.3 (both rules; oracle-exposed and dissent-absent sensitivities; pin partition)
```

### 1.4 System Components

#### Sandbox materialiser (`evals/harness/lib/sandbox-mount.sh`, `evals/harness/pipeline-run.sh`)
- **Purpose:** build the sandbox a phase runs in; for review-catch tasks, after `mount_prompt_surface`, overlay the PR's `pr/head/` version of every answer-bearing path under the sandbox framework directory (FR-1): PR-touched paths plus the fixture's fix-commit paths; added paths present, deleted paths removed. The copy source is the runner's pristine detached worktree at the pin (never the working tree). `CLAUDE.md` and `.loa.config.yaml` are harness-owned and outside the answer set.
- **Responsibilities:** D-1.1 overlay mode and evidence; the `bare_model` and `dissent` toggles (D-5.1, D-5.3); the review-only phase set (D-5.2).
- **Interfaces:** `overlay_answer_paths <ws> <fixture-dir> <mode>` (new; mode `head` default, `base` fallback per task), `check_mount_closed <ws> <fixture-dir>` (new; run before the container starts, refuses the launch on failure), `apply_arm_toggles` (extended: `bare_model`, `dissent`, `oracle_open`), `_sm_evidence mount_overlay …` and `overlay_sha256=<path>=<sha>` per path written before the first phase.
- **Dependencies:** the immutable fixture under `evals/fixtures/review-prs/pr-NN/` (`head.diff` headers parsed with quoted paths, renames, `/dev/null` and binary hunks; `fixture.yaml` `fix_commit`/`head_commit`; paths normalised, absolute or `..` rejected), the toggles JSON from the suite, `task.yaml` `review_catch.overlay_mode` (optional per-task fallback).

#### Took-effect rules (`evals/harness/took-effect.sh`)
- **Purpose:** prove per trial that the arm's configuration and the closed mount took effect.
- **New rules:** `oracle_closed` (against the immutable fixture, incl. stray copies, pre-run evidence equality and a one-commit sandbox `.git`), `oracle_open_recorded`, `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope` (D-1.2, D-5.4).

#### Grader (`evals/harness/ablation-grade.sh`, `evals/graders/recall-vs-defects.sh`)
- **Purpose:** credit catches under both rules; flag oracle use; stop the repo-name false positive.
- **New behaviour:** D-2.1 same-function rule with three outputs (`recall_pm3_v1`, `recall_pm3`, `recall`) and `credits_function_only`; D-1.3 oracle detector (diff and read forms, Bash and non-Bash tool events, unparseable results recorded as `exposed_unknown`); D-3.2 KF-046 class 7 at line level; `grader_version` and the corpus `SHA256SUMS` digest in every grade.

#### Row writer and report (`evals/harness/ablation-row.sh`, `evals/harness/ablation-report.py`)
- **New fields:** `defect_catch_rate_pm3`, `defect_catch_rate_pm3_v1`, `defects_missed_pm3*`, `credits_function_only`, `oracle_exposed_defects`, `dissent_absent_gates`, `dissent_absent_reason` ({gate: disabled|budget|preflight|error|none}), `grader_rule`, `grader_version`, `corpus_sha256`, `config_variant` (`shipped`|`eval`); the report prints the three rules with the decision statistic named, the labelled sensitivities, partitions by `source_commit` and **refuses to pool rows whose `grader_rule` or `source_commit` differ** (D-2.3, D-3.3).

#### Runner (`evals/harness/run-ablation.sh`)
- **New flag:** `--allow-partial` passed to the freeze check and to every grader call, recorded in `MANIFEST.json` (D-3.1).

#### Adversarial review (`.claude/scripts/adversarial-review.sh`, `.claude/schemas/adversarial-finding.schema.json`, the two `ADVERSARIAL-REVIEW.md` resources, `.loa.config.yaml.example`)
- **New behaviour:** numeric anchors requested and recorded (D-4.1); `budget_scale: fixed|diff` with `budget_cents = min(max(budget_cents, ceil(estimate × 1.2)), budget_cents_max)` and `budget_cents_max` 600 (D-4.2); shipped default unchanged; every cycle-131 mounted arm runs the `eval` config variant and its rows say so. These are the only System Zone paths the PRD authorizes (prd.md §Technical Considerations).

#### Corpus manifests (`evals/fixtures/review-prs/manifests/pr-*.json`)
- **Change:** multi-site `anchors[]` curated against the record review files (D-2.2); `SHA256SUMS` regenerated through `seed-corpus-from-record.sh`.

#### Suite (`evals/suites/ablation-2.0.yaml`)
- **Change:** four arms declared (`a0_bare_fable`, `a1_review_only`, `a1_no_dissent`, `a1_full_openmount`) with phases, toggles and took-effect rules; `a1_full` gains `oracle_closed`; `a1_full_openmount` carries `oracle_open_recorded` instead and is refused outside an evaluation batch.

### 1.5 Data Flow

A trial: `run-ablation.sh` plans arm × task × trial → `pipeline-run.sh` materialises `pr/`, copies the framework tree from the pristine pinned worktree, **overlays the PR's head versions of the answer-bearing framework paths (review-catch only, unless `oracle_open`)**, applies toggles and the eval config, regenerates the sandbox manifest, writes the overlay evidence, **runs `check_mount_closed` and refuses to launch on failure** → the container runs the phases → `took-effect.sh` checks the rules (`oracle_closed` compares the sandbox against the immutable fixture and the pre-run evidence) → `ablation-grade.sh` reduces the agent's files to citations, grades under the three rules, runs the oracle detector → `ablation-row.sh` writes the row with its provenance fields → `ablation-report.py` reads rows per pin and grader rule and prints the pre-registered statistic plus the sensitivities.

### 1.6 External Integrations

| Service | Purpose | API Type | Documentation |
|---------|---------|----------|---------------|
| Claude Code CLI 2.1.299 in `loa-ablation:258` | the phases (Opus 5.5 / Fable 5.1 via Bedrock) | CLI | cycle-130 SDD D-4.3 |
| codex CLI (OpenAI) | dissent primary voice | CLI | KF-048 pre-flight in the runner |
| claude-headless | dissent companion voice | CLI | ADVERSARIAL-REVIEW.md |
| docker 26.1.5 | container runtime | CLI | `pipeline-run.sh:79` |

### 1.7 Deployment Architecture

Host-run harness scripts; one docker 26.1.5 container per phase with the sandbox bind-mounted at `/workspace` and a per-run HOME at `/home/evaluser` (`pipeline-run.sh:781-782`). The framework under test is the pinned worktree's framework directory copied into the sandbox (`sandbox-mount.sh:131`; the runner's pre-flight 5 refuses a dirty worktree), so the pin is the source commit, and the image holds only the CLI and tools — no rebuild for this cycle.

### 1.8 Scalability Strategy

Not applicable beyond concurrency 3 and the caps (PRD NFR-5).

### 1.9 Security Architecture

The sandbox never holds `.run/zone-guard-authorization.json`; the overlay writes only inside the sandbox copy; the oracle scan reads transcripts as data (regexes over tool inputs and results, never evaluated); the dissent prompt change adds a field, not an instruction surface; `budget_scale: diff` is bounded by the per-run USD 20 cap (`pipeline-run.sh --max-run-usd`). Third-party text in envelopes and transcripts stays untrusted (CLAUDE.loa.md agent-network invariants).

---

## 2. Software Stack

### 2.1 Frontend Technologies
None (CLI and markdown reports).

### 2.2 Backend Technologies
Bash ≥ 5 (`set -euo pipefail`, the repo's shell conventions), `jq`, `yq` v4, Python 3 (`python3 -I`, stdlib only: `json`, `re`, `difflib`, `random`) for the grader internals and the report; bats for tests (`evals/tests/`, `tests/unit/`).

### 2.3 Infrastructure & DevOps
docker 26.1.5 + `loa-ablation:258`; GitHub Actions (CI, Shell Tests, Security Audit) on the PR; the record-branch recipe (temporary index) for gitignored records.

---

## 3. Database Design

### 3.1 Database Technology
Flat files: `runs.jsonl` rows (one per run), `grade.json` per run, `MANIFEST.json`/`STATUS.json` per batch, the manifests under `evals/fixtures/review-prs/manifests/`, `grimoires/loa/decisions.yaml`, `NOTES.md`.

### 3.2 Schema Design

#### Entity: grade.json (grader 1.3)
- `recall.recall` (new rule, new anchors), `recall.detected`, `recall.missed`; **new** `recall.recall_pm3` / `missed_pm3` (old rule, new anchors), `recall.recall_pm3_v1` / `missed_pm3_v1` (old rule, `manifests/v1/`), `recall.credits_function_only`, `recall.rule = "pm3_or_same_function"`; **new** `oracle_exposed_defects: ["dN", …]`, `oracle_exposed_events: [{phase, event, how: diff|read|exposed_unknown, path}]`; **new** `grader_version`, `corpus_sha256`; `contaminated` unchanged in shape, `repo_name` exempt when the matched line exists in the fixture's head tree or `head.diff` (line level; the matching fixture line is recorded).

#### Entity: runs.jsonl row (row writer 1.4)
- `defect_catch_rate` (= `recall`, the new rule — the pre-committed decision statistic), **new** `defect_catch_rate_pm3`, `defect_catch_rate_pm3_v1`, `defects_missed_pm3`, `defects_missed_pm3_v1`, `credits_function_only`, `oracle_exposed_defects`, `dissent_absent_gates: ["review"|"audit"]`, `dissent_absent_reason: {review, audit}`, `grader_rule`, `grader_version`, `corpus_sha256`, `config_variant`, `overlay_mode`, `gate_scripts_at_pr_version: [paths]`; `source_commit` already present and used for the pin partition.

#### Entity: manifest pr-NN.json
- `defects[].anchors[]` extended with every head line the human finding named, derived blind from `label_source` and the record review text only (never from cycle-130 outputs); `approved_by` re-stamped; the originals retained unchanged under `manifests/v1/` for `recall_pm3_v1`; `SHA256SUMS` regenerated and its digest recorded per grade.

#### Entity: suite arm
```yaml
- {id: a0_bare_fable, label: A0F, task_types: [review-catch], toggles: {loa_mount: false, bare_model: fable}, phases: [BARE], effort: high,
   took_effect: [no_dot_claude, no_system_prompt, no_audit_rows, bare_model_fable, integrity_clean]}
- {id: a1_review_only, label: A1R, task_types: [review-catch], toggles: {}, phases: [REVIEW],
   took_effect: [review_only_phases, oracle_closed, integrity_clean]}
- {id: a1_no_dissent, label: A1N, task_types: [review-catch], toggles: {dissent: false},
   took_effect: [all_phases_present, no_review_dissent_envelope, oracle_closed, integrity_clean]}
- {id: a1_full_openmount, label: A1O, task_types: [review-catch], toggles: {oracle_open: true}, eval_only: true,
   took_effect: [all_phases_present, oracle_open_recorded, integrity_clean]}
```
`a1_full` gains `oracle_closed`. Every mounted cycle-131 arm runs the `eval` config variant (`budget_scale: diff`, numeric anchors requested) and its rows carry `config_variant: eval`.

### 3.3 Data Modeling Approach
Additive fields only; every existing field keeps its meaning; `defect_catch_rate` under grader 1.3 is the new rule and `grader_rule` says so on every row, so a reader can never mistake a 1.3 row for a 1.2 row (D-2.3).

### 3.4 Migration Strategy
Two steps with different oracles: (1) regression — grader 1.3 over the 36 cycle-130 run directories with `manifests/v1/`: `recall_pm3_v1` must equal the stored `recall` on every run (a mismatch is a grader defect, fixed before anything else); (2) re-grade — the same runs graded into the versioned file `evals/results/ablation-2.0/regrade-c131/rows.jsonl` with the new anchors (`recall_pm3`, `recall`); the shipped `runs.jsonl`, every stored `grade.json` and `report.md` are untouched; the addendum reads the re-grade file.

### 3.5 Data Access Patterns
`ablation-report.py` partitions by `suite_version` (existing), `source_commit` and `grader_rule` (new) and refuses to pool across any of them: cycle-130 rows (`ba11b860`, 1.2.x) and cycle-131 rows (the Sprint 2 pin, 1.3) are never pooled; a pairwise read names its pin and rule.

### 3.6 Caching Strategy
None.

### 3.7 Backup and Recovery
Rows under flock with temp-and-rename (existing); the ledger's own backup; record branch at the close.

---

## 4. UI Design

### 4.1 Design System
CLI output in the harness's existing style; markdown reports in `analysis.md`'s shape.

### 4.2 Key User Flows

#### Flow 1: run a batch under the closed mount
`run-ablation.sh … --suite-root <root> --allow-partial --dry-run` → inspect the plan → `--detach` → `watch-batch2.sh` → the rows → `ablation-report.py --partial --pin <sha>`.

#### Flow 2: re-grade and compare
`ablation-grade.sh <run-dir> <task> --suite-root … --allow-partial` → `--rerow` → the addendum table.

### 4.3 Page/View Structure
The addendum: ELI5 paragraph; re-grade table (36 runs × both rules); oracle A/B per PR; control arm reading; two prices with the rules quoted; adjudication; spend.

### 4.4 Component Architecture
Not applicable.

### 4.5 Responsive Design Strategy
Not applicable.

### 4.6 Accessibility Standards
Plain markdown tables; no colour-only signals in CLI output (the existing `[arm-check]`/`refused:` prefixes).

### 4.7 State Management
`STATUS.json` per batch (existing); `.run/sprint-plan-state.json` for the cycle's run mode.

---

## 5. API Specifications

### 5.1 API Design Principles
Shell CLIs with explicit flags; JSON on stdout where the existing tool does; additive flags and fields only.

### 5.2 Endpoints

#### `sandbox-mount.sh overlay_answer_paths <ws> <fixture-dir> <mode>` and `check_mount_closed <ws> <fixture-dir>`
- **Answer-bearing set** (computed once from the immutable fixture): paths from `head.diff`'s `diff --git` headers (quoted paths unquoted, `rename from/to` counted under both names, `/dev/null` and binary hunks handled), plus every path under `pr/head/` and `pr/base/`, plus the fixture's fix-commit paths (`git show --name-only <fix_commit>`); every path normalised (no absolute, no `..`, no symlink component) and intersected with the sandbox framework directory (`.claude/**`). `CLAUDE.md` and `.loa.config.yaml` are harness-owned and excluded.
- **mode `head` (default, DEC-0622):** each answer path's sandbox copy is replaced by `pr/head/X`; a path the PR deleted is removed; a fix-commit path outside the PR takes its content at the fixture's `head_commit` (`git show`) or is removed when absent there. **mode `base`** (per-task fallback, `task.yaml` `review_catch.overlay_mode`, recorded by DEC when the smoke needs it): `pr/base/X` instead, added paths removed.
- Evidence written **before the first phase** to `arm_evidence`: `mount_overlay=<mode>:<n paths>`, `overlay_sha256=<path>=<sha>` per path, `gate_scripts_at_pr_version=<paths>` (answer paths under `.claude/scripts/`, `.claude/hooks/` or `.claude/skills/*/SKILL.md`), `copy_source=<worktree sha>`.
- Called from `pipeline-run.sh` only when `KIND == review-catch && LOA_MOUNT == true && !oracle_open`, after `mount_prompt_surface`, before `apply_arm_toggles`, the eval-config writes and `regen_sandbox_manifest`; then `check_mount_closed` runs the same comparison as the took-effect rule (below) and the launch is refused (`infra`) on any failure. Exit 2 on a missing fixture.

#### `took-effect.sh` rule `oracle_closed` / `oracle_open_recorded`
- `oracle_closed` reads the mode and the pre-run evidence from `<run-dir>/meta/` and the fixture from `evals/fixtures/review-prs/pr-NN/` (never the sandbox's `pr/`): (a) every answer path present under the mount byte-equals its fixture version for the mode, or is absent where the mode says absent; (b) no regular file in the sandbox outside `pr/` is byte-equal to the pinned (later) version of an answer path (stray copies); (c) each overlaid path's post-run sha equals its pre-run `overlay_sha256` (else `mount_mutated=<path>`); (d) the sandbox `.git` holds exactly the `base` commit, no remote, `git fsck --unreachable --no-reflogs` reports nothing and no packfile predates the base commit. Fails naming the first violated clause and path.
- `oracle_open_recorded` (the open-mount arm only): `arm_evidence` says `mount_overlay=none` and the row will carry `oracle_exposed_defects` as reported, not as an exclusion.

#### `took-effect.sh` rules `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope`
- `bare_model_fable`: `pipeline.json.phases[BARE].models_used` has exactly one key and it starts with `global.anthropic.claude-fable`, and `effort_requested` is `high`.
- `review_only_phases`: the phase records are exactly `[REVIEW]` and no `auditor-sprint-feedback.md` exists.
- `no_review_dissent_envelope`: no `eval/adversarial-review.json`, the sandbox `.loa.config.yaml` has `flatline_protocol.code_review.enabled: false`, and the audit envelope exists with its voices (the audit dissent stays enabled: the contrast is the review gate's dissent alone).

#### `recall-vs-defects.sh` 1.3.0
- Citation validity first: positive in-file line numbers, ordered bounded ranges; a range wider than 25 lines credits only through its first line. Detection: a citation `(path, a, b)` detects defect `d` when `path_matches` and (±3 of any site) OR (`same_scope(path, a..b, site)`): the enclosing definition of the site in `head/<file>` — identified by its header line number, not its name — bash `^\s*(function\s+)?NAME\s*\(\)\s*\{?` / `^\s*function\s+NAME\s*\{`, python `^\s*def NAME\(`, bats `^@test "…"`, markdown the nearest preceding `#` heading; the definition runs from its header to the line before the next header at the same or lower indentation (nested → innermost); a definition longer than 400 lines, or a file type with no definition regex (yaml, json, txt), falls back to ±20 lines around the site. Three results: `recall_pm3_v1` (±3, `manifests/v1/`), `recall_pm3` (±3, current manifest), `recall` (±3 or same scope, current manifest), each with `detected`/`missed`; `credits_function_only` lists defects credited only by the scope clause.
- `ablation-grade.sh` passes through and writes the three results, `credits_function_only`, `recall.rule`, `grader_version` and `corpus_sha256`.

#### `ablation-grade.sh` oracle scan (D-1.3)
- Over `transcripts/events-{REVIEW,AUDIT}.jsonl`, correlating each `tool_use` with its `tool_result` by id: (a) **diff form** — a Bash command segment whose executable is `diff`, `sdiff`, `comm` or `git diff --no-index`, without `-q`/`--brief`, not the word `head.diff`, not inside a heredoc body, with one operand under `pr/head|pr/base` (or a variable bound to them in the same command) and one operand outside `pr/` naming an answer path; the result's unified or normal ranges are read, and a planted site inside a range (±3) or the site's `must_match` text in the result marks the defect exposed; an unparseable result marks `exposed_unknown` for every defect of that file; (b) **read form** — a Bash read (`cat`, `sed`, `awk`, `grep`, `head`, `tail`, `less`, `python3`) or a `Read`/`Grep` tool_use on a workspace copy of an answer path whose result contains a line present in the pinned copy but absent from `pr/head` within ±3 lines of a planted site. Written to `grade.json.oracle_exposed_defects` / `oracle_exposed_events` ({phase, event, how, path}). Validated on the 36 cycle-130 run directories (exactly `review-04 t2`, `review-r17 t1`, `review-r18 t1`) and on synthetic transcripts (covering diff, later-line read, `diff -q`, `cat pr/head.diff`).

#### `ablation-grade.sh` KF-046 class 7 (D-3.2)
- `repo_name` is not contamination when the whole matched line (not just the token) exists in the task fixture's head tree or `head.diff`; the matching fixture line is recorded in `grade.json.contamination_exempt[]`.

#### `run-ablation.sh --allow-partial` (D-3.1)
- Appended to `FREEZE_ARGS` and to every grader argv; relaxes exactly the four-per-type count in `validate-suite.sh` (nothing else: schema, leakage and hash checks stand); `MANIFEST.json.allow_partial: true`; `--resume` keeps the manifest's value.

#### `adversarial-review.sh` (D-4.1, D-4.2)
- Prompt: `"anchor": "file:symbol", "anchor_type": "function|hunk|line", "anchor_line": <int, the head line of the finding>, "anchor_line_end": <int, optional>` with one sentence requiring the numeric anchor whenever the finding sits on a specific line; `_normalize_finding_for_validation` keeps integer `anchor_line`/`anchor_line_end` and drops non-integers; the schema adds both as optional integers; the grader's `envelope_texts` is extended to read `anchor_line` with the finding's file (the `anchor`'s path part) as `path:line[-end]`.
- Budget: `flatline_protocol.<gate>.budget_scale: fixed|diff` (default `fixed`): with `diff`, `budget_cents = min(max(budget_cents, ceil(estimate × 1.2)), budget_cents_max)` where `estimate` is `_adv_budget_estimate`'s total over the planned voices (adversarial-review.sh §budget gate) and `budget_cents_max` defaults to 600; an estimate above the maximum still refuses (`budget_exceeded`, reason `budget`). The eval config written for every mounted arm sets `budget_scale: diff` for both gates; the shipped `.loa.config.yaml` is untouched; rows carry `config_variant: eval`.

#### `ablation-row.sh` 1.4 / `ablation-report.py` 1.3
- New fields as in §3.2; `--pin <sha>` filter and a per-pin, per-rule section; the decision line uses `defect_catch_rate` (the new rule) and prints `_pm3` and `_pm3_v1` beside it; labelled sensitivities "oracle-exposed cells excluded" and "dissent-absent gates excluded" (planned absence — `dissent_absent_reason: disabled` — is never excluded); a contrast with fewer than 4 valid cells reads "insufficient"; rows differing in `grader_rule` or `source_commit` are never pooled.

### 5.3 Pre-registered batches (FR-6, executed in Sprint 2)

| batch | arms × tasks × trials | est. USD (unit cost basis: cycle-130/replication actuals) | rule |
|---|---|---|---|
| `c131-b1-oracle-ab` | `a1_full_openmount` × review-r17 (pr-17) × 3 (the closed cells are B2's `a1_full` × review-r17) | 3 × ≈ 16 = 48 | Δ = closed − open on `recall`, 90 % interval over 20 defects: entirely below 0 → "the oracle inflated the catch on pr-17"; includes 0 → "no measurable inflation"; entirely above 0 → "investigate" |
| `c131-b2-control-prices` | `a0_bare`, `a0_bare_fable`, `a1_full`, `a1_review_only`, `a1_no_dissent` × review-r17 (pr-17), review-r18 (pr-18) × 3 | a0 6 × 1.4 + a0F 6 × ≈ 3 + a1_full 6 × ≈ 13 + review_only 6 × ≈ 7 + no_dissent 6 × ≈ 12 ≈ 220 | R5, R3, R4 exactly as written in prd.md FR-6 (interval rules, ordered branches) |

Both batches run at one pin (the merge commit of FR-1 … FR-5 on the cycle branch, recorded in NOTES before B1's first row); a harness or framework fix found after B1 means B1 is re-run at the new pin or B2 runs at the old pin without the fix — never two pins in one read. pr-12 and pr-13 are not in any batch: their PRs touch the gate machinery itself (dissent script; review skill and session hook), so a closed-mount gate would run the PR's version of the gate; they stay in the re-grade. Suite root for B1/B2: `grimoires/loa/evals/ablation-2.0-c131/` holding `review-r17` and `review-r18` copied unchanged from the replication root (REVIEW.md carried over with a one-line copy note), frozen with `--allow-partial`, self-checked. Rows to `evals/results/ablation-2.0/<batch>/`. Open-mount rows report `oracle_exposed_defects` and are not excluded for it.

## 6. Error Handling Strategy

### 6.1 Error Categories

| Category | Handling |
|---|---|
| An answer path has no fixture version for the mode (deleted by the PR in head mode; added by the PR in base mode) | removed from the mount; logged in `mount.log`; `oracle_closed` expects absence for that path |
| `check_mount_closed` fails before launch | the trial is `infrastructure_error`, nothing runs, the path and clause are logged; the arm pauses after the runner's rule |
| A head-version gate script breaks a gate (pr-12's planted dissent bugs, pr-13's hook) | the Sprint 1 smoke on all seven PRs decides the per-task fallback to `base` (DEC + `task.yaml` `overlay_mode`); the batches use pr-17/pr-18 whose gate surface is a fence hook and one skill line; a failing gate is `agent_error`/`infrastructure_error`, never silently a miss |
| Oracle scan hit on a batch row | row flagged `oracle_exposed_defects ≠ []`; excluded pairwise under the pre-registered validity rule; cause recorded in NOTES |
| Dissent budget still refuses under `diff` scaling (cap hit) | `dissent_absent_gates` records it; the labelled sensitivity excludes those rows; the read states it |
| Grader rule regression (`recall_pm3` ≠ stored) | the re-grade step fails loudly; no row is rewritten until it matches |
| Contamination class 8+ | read by hand (KF-046 guide); recorded; no grader change mid-batch |

### 6.2 Error Response Format
Existing: `refuse`/`infra`/`die_usage` prefixes and exit codes (2 usage, 1 fail); grader `GradeError`; took-effect names the failing rule.

### 6.3 Logging Strategy
`mount.log`, `run.log`, `driver.log`, `arm_evidence` lines (existing); `grading/oracle-scan.json` (new, per run); NOTES entries per batch.

---

## 7. Testing Strategy

### 7.1 Testing Pyramid
- bats unit cases per change (`evals/tests/sandbox-mount.bats`, `took-effect.bats`, `ablation-grade.bats`, `eval-recall-grader.bats`, `ablation-row.bats`, `ablation-report.bats`, `run-ablation.bats`; `tests/unit/adversarial-review-*.bats`).
- Grader self-checks (`--self-check base|reference|noisy`) on the cycle-131 suite root inside the image.
- Smoke: one `a1_full` trial per corpus PR under the closed mount (7 runs ≈ USD 90; counted against the cycle cap, outside the ≤ 250 batch allowance — D-7.1) plus one trial per new arm on pr-12.
- Regression: the 36 re-grades (`recall_pm3` equality) and `evals/tests/` (447 → more).

### 7.2 Testing Guidelines
Test-first for every grader rule change (a red case before the rule); synthetic transcripts for the oracle scan (a covering `diff`, a `diff -q`, a `cat head.diff` that must not trip); every took-effect rule has a pass and a fail fixture.

### 7.3 CI/CD Integration
Existing workflows (Shell Tests runs `evals/tests/` since cycle-130's CR-7 fix); the PR must be green before merge; the local full run at the close.

---

## 8. Development Phases

### Phase 1: Measurement fixes (Sprint 1)
FR-1 (D-1.1 … D-1.3), FR-2 (D-2.1 … D-2.3), FR-3 (D-3.1 … D-3.3), FR-4 (D-4.1, D-4.2); re-grade the 36 runs; adjudication (two Opus labelers, 20 packets); smoke of the seven PRs; the replication read re-taken (SC-3). Exit: tests green, smoke green, re-grade equality, DEC rows.

### Phase 2: Arms and batches (Sprint 2)
FR-5 (D-5.1 … D-5.4), the cycle-131 suite root, pin recorded, pre-registrations (NOTES + DEC) before each batch, B1 then B2, spend posted. Exit: rows landed or cut with a reason.

### Phase 3: Reads and addendum (Sprint 3)
FR-6 reads, FR-7 addendum, DEC rows, beads, CHANGELOG, release notes, PR, record branch. Exit: PR merged, record branch pushed.

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| Head-mode overlay runs the PR's (planted-defect) version of a gate script on pr-12/pr-13 | those PRs are re-grade only; the smoke records gate behaviour per PR; the per-task `base` fallback exists; both modes satisfy FR-1 ("no later copy") and the row discloses `gate_scripts_at_pr_version` |
| The copy source drifts from the pin during an unattended sprint | the runner's pristine detached worktree is the only copy source; `copy_source` sha in `arm_evidence` must equal `source_commit` or the trial is refused |
| The same-function rule credits a different finding in a long function | the 400-line cap with a ±20 fallback; the ≥ 80 % adjudication gate; both rules always reported |
| Numeric anchors reduce the dissent's willingness to report | the symbol anchor stays required; the smoke compares finding counts with cycle-130 envelopes; the read reports the numeric share beside the price |
| `budget_scale: diff` raises dissent cost | bounded by `budget_cents_max` 600 and the USD 20 run cap; only the eval config enables it |
| An A3-style one-voice arm is not run | out of scope (R4 is priced by `a1_no_dissent`; `a3_one_voice` exists for a later cycle) |
| Pin drift between Sprint 2 batches | one pin recorded in both MANIFESTs; the runner's drift guard |

---

## 10. Open Questions

- Should `budget_scale: diff` become the shipped default after the price is read? (Operator; not this cycle.)
- Is the markdown "section" rule the right unit for prose defects (pr-13 d4/d5)? The adjudication will say.
- Does the bare-Fable arm want `effort: high` (Opus's bare setting) or Fable's gate effort (`xhigh`)? D-5.1 picks `high` for the model-only comparison; a second arm at `xhigh` is a later cycle's question.
- Should symbol-only dissent anchors be resolved to their function's line range by the grader (so the shipped dissent could be credited retroactively)? Declined this cycle: FR-4's numeric anchors are the fix, and a function-range credit for the dissent would reopen the same-function question for one component only.

---

## 11. Appendix

### A. Glossary
Overlay — replacing the mounted copy of a PR-touched path with the PR's own version. Pin — the source commit all arms of a batch run. Price — a pre-registered arm-vs-`a1_full` read with named outcomes.

### B. References
`grimoires/loa/prd.md` (cycle-131); `grimoires/loa/reports/ablation-2.0/analysis.md`; `evals/harness/pipeline-run.sh:17, :232, :459, :503-545, :746, :781-782`; `evals/harness/lib/sandbox-mount.sh:125-200`; `evals/harness/took-effect.sh:13-35`; `evals/harness/run-ablation.sh:696-699, :1242`; `evals/graders/recall-vs-defects.sh`; `.claude/scripts/adversarial-review.sh:200, :1148-1165, :549, :1002`; `.claude/schemas/adversarial-finding.schema.json:97-110`; KF-046, KF-048, KF-049.

### C. Change Log
1.0 — initial, unattended.

### D. Decisions taken on the operator's behalf
- **D-1.1** (amended by DEC-0622) Overlay mode `head` by default for review-catch sandboxes: the PR's own `pr/head/` copy of every answer-bearing path (PR-touched plus fix-commit paths, under `.claude/**`) replaces the mounted later copy; deleted paths are removed; `base` is the recorded per-task fallback where a head-version gate script breaks a gate. [ASSUMPTION decision] (DEC-0613)
- **D-1.2** `oracle_closed` is a took-effect rule (pauses the arm on a miss) rather than a grader-only check, because a leaked sandbox must stop the batch, not just mark a row. [ASSUMPTION decision] (DEC-0615)
- **D-1.3** The grader-side oracle scan is the analysis detector (`oracle_scan.py`) rewritten inside `ablation-grade.sh` with the same three exclusions (`-q`, the word `head.diff`, heredoc bodies) and tested on synthetic transcripts. [ASSUMPTION decision] (DEC-0615)
- **D-2.1** Same-function rule: enclosing symbol via regexes for bash/python/bats, markdown by heading section; a function longer than 400 lines falls back to ±20 lines. [ASSUMPTION decision] (DEC-0616)
- **D-2.2** Multi-site anchors are curated by the lead from the record review files and re-approved; no new manifest key. [ASSUMPTION decision] (DEC-0616)
- **D-2.3** The primary `defect_catch_rate` carries the rule each batch's pre-registration names; `_pm3` always reported beside it; the report partitions by `source_commit`. [ASSUMPTION decision] (DEC-0616)
- **D-3.1** `--allow-partial` is a runner flag recorded in MANIFEST, not a default. [ASSUMPTION decision] (DEC-0617)
- **D-3.2** KF-046 class 7: a repo-name token present in the PR fixture is PR content. [ASSUMPTION decision] (DEC-0617)
- **D-3.3** `dissent_absent_gates` is a new row field; `degraded` keeps its definition (bd-ocovl). [ASSUMPTION decision] (DEC-0617)
- **D-4.1** Numeric anchors are additional optional fields (`anchor_line`, `anchor_line_end`); the symbol anchor stays required; the grader reads them. [ASSUMPTION decision] (DEC-0618)
- **D-4.2** `budget_scale: fixed|diff` with `budget_cents_max` 600; `diff` only in the eval config; shipped default `fixed`. [ASSUMPTION decision] (DEC-0618)
- **D-5.1** `a0_bare_fable` runs BARE on Fable 5.1 at `effort: high` (model-only comparison with `a0_bare`). [ASSUMPTION decision] (DEC-0619)
- **D-5.2** `a1_review_only` is `a1_full` with `phases: [REVIEW]`; **D-5.3** `a1_no_dissent` sets `flatline_protocol.code_review.enabled: false` in the sandbox config (audit gate unchanged); **D-5.4** one took-effect rule per toggle. [ASSUMPTION decision] (DEC-0619)
- **D-7.1** The Sprint 1 smoke (seven PRs under the closed mount, ≈ USD 90) counts against the USD 500 cycle cap but not against the ≤ 250 batch allowance. [ASSUMPTION decision] (DEC-0614)

### E. Flatline integration (SDD review, 2026-10-19)
Two voices, 15 blockers, 51 items, cross-scoring degraded (KF-041 recurrence 7); read by judgment; integrated in 1.1 (DEC-0622, DEC-0623): head-mode default so the mounted copy keeps head coordinates and added-line defects exist (SKP-003); the answer set scoped to `.claude/**` so the toggles' config writes never break `oracle_closed` (SKP-004 ×2, opus IMP-001); the verifier reads the immutable fixture and `meta/` evidence, never the agent-writable `pr/` (SKP-003 740); the copy source is the pristine pinned worktree and `copy_source` must equal `source_commit` (SKP-002 800, gpt IMP-018); robust diff-header parsing and path normalisation (SKP-001 830, gpt IMP-003, opus IMP-026); the complete expected inventory, including deletions and stray copies, and a one-commit sandbox `.git` (SKP-002 730, gpt IMP-001, opus IMP-015); pre-launch `check_mount_closed` (opus IMP-014); the detector's read form, non-Bash tool events, result correlation and `exposed_unknown` (SKP-009, gpt IMP-010/011, opus IMP-012/023); the within-pin B1 with the open-mount arm reported not excluded (SKP-005 ×2, gpt IMP-005, opus IMP-002/006); fixed-meaning recall fields with `grader_rule` per row and no pooling across rules (SKP-012, gpt IMP-012, opus IMP-020); the two-step re-grade with `manifests/v1/` (gpt IMP-013/014, opus IMP-004); scope identity by header line and end-of-definition detection, range validity, the long-definition fallback for sites and citations alike, file types without a regex (gpt IMP-006/007/008, opus IMP-005/009/010/011); `dissent_absent_reason` and the planned/unplanned distinction (opus IMP-007, gpt IMP-023); `config_variant: eval` on every cycle-131 mounted row (opus IMP-021); `grader_version` and the corpus digest per row (opus IMP-025, IMP-022); the one-pin policy between B1 and B2 (opus IMP-027); the budget formula's inputs and precedence (gpt IMP-020, opus IMP-017); `--allow-partial` semantics (opus IMP-018); the adjudication consequence (opus IMP-019: < 80 % → the rule is not adopted and `recall_pm3` becomes the decision statistic for Sprint 3's reads, recorded as a DEC). Declined: grader-side resolution of symbol-only dissent anchors (opus IMP-016; §10); a formal non-inferiority design (gpt IMP-016; the interval rules say "inconclusive" honestly).

