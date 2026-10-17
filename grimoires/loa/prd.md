# Product Requirements Document: Loa 2.0 Component Ablation (cycle-130)

**Version:** 1.0
**Date:** 2026-10-15
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (operator instruction 2026-10-15: deliver cycle-130 end to end with admin pre-approval; the interview phases were answered from the operator's brief and the tree, no operator questions; every decision taken on the operator's behalf is a `proposed` row in `grimoires/loa/decisions.yaml` (DEC-0355 … DEC-0378) and is listed in Appendix E with its `[ASSUMPTION decision]` tag; the PRD Flatline run's integration decisions are DEC-0391 … DEC-0410, Appendix G)
**Brief:** `grimoires/loa/context/cycle-130-brief.md` (the operator's "Loa 2.0 component ablation plan", 2026-10-14, sha256 `85fd49ca…`; gitignored)
**Continuation prompt:** `grimoires/loa/a2a/prompts/ablation-2.0-continue-2026-10-14.md`
**Component under test:** Loa `v2.0.0-rc.5` (tag commit `4d69c3c4`, main `9e53d5d2`) plus the #1267 mount fix: the arms pin the Sprint 258 completion commit and the manifest records the `.claude/` delta against `4d69c3c4` [ASSUMPTION decision] (DEC-0392)
**Branch:** `feature/cycle-130-ablation-2.0` from `main 9e53d5d2`

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

Every Loa component encodes an assumption about what the model cannot do alone. This cycle measures which components of `v2.0.0-rc.5` still add lift on the current model generation (Opus 5.5 at `high`, Fable 5.1 as reviewer) and removes from the default path the ones that do not, before 2.0.0 is promoted. The measurement is a frozen sixteen-task suite (four feature builds, four bug fixes, four refactors, four review-catch tasks) graded only by hidden tests and seeded-defect keys that the agent never sees; nine pre-registered arms (A0 bare Claude Code, A1 full Loa, A2–A8 one component removed each) run the suite under a whole-cycle cap of USD 1,500 and a per-run cap of USD 12, priority arms A0–A4 first; paired-bootstrap decision rules fixed before the first run turn each arm into a keep, remove, simplify, inconclusive or investigate decision for its component.

The cycle reuses cycle-129's instruments (the arm runner, the toggle mechanism, the review-recall corpus and its hidden manifests, the bootstrap report) and adds what the brief needs and cycle-129 did not have: a pipeline executor that runs the Loa phases as separate fresh-context sessions inside a sandbox repository, so that sprint decomposition, the review and audit gates, Flatline and context resets can actually be removed; a frozen task suite with hidden tests outside the agent tree; a `runs.jsonl` row per run with every brief metric; a mechanical grader that scores a known-good and a known-bad patch correctly on every task before any arm runs; the spend-cap mechanism (`--max-usd`, per-run abort) that makes the operator's two numbers mechanical; and the #1267 mount-integrity fix the brief lists as the first prerequisite. Five sprints (global 258–262) follow the brief's breakdown: mount integrity and plumbing, suite and grader, runs, analysis, prune and document. The floor — review, audit, verdict-derive and the one-way rule, the dissent artefact gate, the deny list, fence FR-1.2b, the System-Zone rules, the operator-only commands — is never pruned; A4 informs the suite's sensitivity check and the report only.

> Sources: cycle-130-brief.md §Objective and hypothesis, §Arms, §Decision rules, §Sprint breakdown; ablation-2.0-continue-2026-10-14.md §What already exists, §Known constraints; `evals/harness/run-arms.sh:1-50`; `evals/harness/execute-agent.sh:1-80`

---

## Problem Statement

### The Problem

Loa's harness grew component by component against earlier model generations. Cycle-129 began measuring it: the guard register recorded every guard's origin and yield, and four pre-registered gate-off arms (`no_karpathy`, `no_rule_files`, `no_companion`, `no_audit_delta`) found no recall loss on eight review fixtures. But those arms ran one skill per trial with Read, Grep, Glob and Write only, so the components that live *between* skills — sprint decomposition, the separate evaluator (review and audit), Flatline, the reset-and-handoff pattern, the effort default, planning ceremonies — have never been measured against bare Claude Code on the current model generation. Anthropic dropped sprint decomposition once Opus 4.6 could sustain long tasks natively; Loa has not tested the same question for its own scaffolding. Promoting 2.0.0 without that measurement would ship components whose cost is known (tokens per turn, wall-clock, dollars) and whose benefit is assumed.

### User Pain Points

- The maintainer cannot say which of the harness's components earn their cost on Opus 5.5 and Fable 5.1; the 2.0.0 promotion decision rests on assumptions written for Opus 4.x.
- A downstream mount of `v2.0.0-rc.1` to `rc.5` fails `check-loa.sh` because `.claude/checksums.json` was generated from a dirty tree (1,308 manifest paths absent from the tag; 242 build and cache artefacts in the manifest); four downstream repositories have reported it (#1267). A broken mount contaminates every measurement downstream.
- `run-arms.sh` has no spend ceiling: the cycle-129 DEC-0173 cost gate was read by hand (bd-j4lwr).
- The record-fixture manifests count generated artefacts (`dist/*.js`, `.checksum`, `REPO-MAP.md`) as fix regions, lowering the refuted share a stray finding there would earn (bd-8o5rx).
- Two kernel text deletions (bd-2txz1) wait for an ablation verdict that only a suite with build tasks can give.

### Current State

- `evals/harness/run-arms.sh` runs the declared arms of `review-recall` or `audit-recall` on a detached worktree pinned at `--source-commit`, interleaved trials, one transport retry, `MANIFEST.json` and `STATUS.json`, Opus 5.5 executor by default (DEC-0172); `report.sh --arms` writes paired bootstrap 90 % intervals and pre-registered verdicts; eighteen review fixtures (`pr-01` … `pr-18`) carry hidden manifests and approved labels outside the agent tree.
- `execute-agent.sh` applies four toggles to the sandbox copy only (`companion_voice`, `karpathy_block`, `rule_files`, `audit_delta_instruction`), verified absent afterwards; the executor is `claude -p --restricted --tools Read,Grep,Glob,Write`, so no sandbox trial runs a script, a gate or a second session.
- Five implementation fixtures (`evals/fixtures/implement-tasks/01` … `05`, Python, pytest) carry hidden expectations and are graded by `implement-discipline.sh` (test-first, surgical, zone, tests pass).
- MODELINV rows carry `effort`, `effort_effective`, `tokens_input/output`, `cost_micro_usd`, `locality_mode`, `destination`; `.run/cost-ledger.jsonl` carries model, provider, transport, tokens and cost; `executor.json` records `model_id`, `effort`, `total_cost_usd`, `usage`, `models_used`, `refusal_fallbacks`.
- `check-loa.sh` exits 1 on this checkout (83 `Tampered` rows, all `__pycache__`); the manifest has 3,387 entries against 1,976 tracked `.claude/` files; `.loa-version.json` says `2.0.0-rc.3`.
- `/meeting` geometries and a Sosyete panel, named by the brief's arm A8, do not exist at the pinned SHA (no command, skill or configuration key).

### Desired State

Every harness component has a measured keep, remove or simplify decision traceable to numbers in `grimoires/loa/reports/ablation-2.0/report.md`; the components with no measured lift are opt-in; the pruned default is re-verified within three points of the old full harness on both primary metrics; the suite stays runnable so the next model bump can repeat the ablation; a fresh submodule mount of the rc passes `check-loa.sh`; and the operator's spend caps are mechanical.

> Sources: cycle-130-brief.md §Objective and hypothesis, §Prerequisites; `grimoires/loa/a2a/sprint-257/arms-report-review-recall-2026-10-14.md`; `grimoires/loa/guards.md:1-12`; `evals/harness/execute-agent.sh:20-30,56-77`; `evals/graders/implement-discipline.sh:1-24`; `.claude/scripts/check-loa.sh:47-68`; issue #1267 and its downstream comment; `br show bd-j4lwr`, `bd-8o5rx`, `bd-2txz1`

---

## Goals & Success Metrics

### Primary Goals

1. **G-1 Measured decisions.** Every component listed in §Arms has a keep / remove / simplify / inconclusive / investigate decision produced by the pre-registered rules from `runs.jsonl`, with the two primary metrics, their 90 % intervals and the cost delta next to it.
2. **G-2 Honest measurement.** The grader is mechanical and blind to arm labels; hidden tests and defect keys never enter the agent tree; every run records the executor's model id, effort requested and effective, the voices actually run and a `degraded` flag; a silently degraded run is visible and excluded with its reason.
3. **G-3 Clean mount.** #1267 is closed: the manifest is generated from the tracked tree, CI fails on a manifest path absent from the tree, and `check-loa.sh` is green on a fresh submodule mount with Aleph absent.
4. **G-4 Caps are mechanical.** No run launches past the cycle cap; a run that reaches the per-run cap is recorded as a failure; the running spend is posted in NOTES after every batch.
5. **G-5 Pruned default verified.** Components with a remove or simplify decision move to opt-in; the pruned default scores within three points of old A1 on both primary metrics on the re-verification set.
6. **G-6 Repeatable.** `evals/harness/run-ablation.sh` reruns the frozen suite against any source commit; the manifest hash, the tasks and the grader are tracked.

### Key Performance Indicators (KPIs)

| KPI | Target | Measured by |
|---|---|---|
| Components with a traceable decision | 6 of 6 measurable components (A2–A7) carry one of the five rule outcomes, or `Not run (cut)` / `Inconclusive-by-power` with the figure that stopped them; A8 recorded as component-absent; A4's own row reads Keep or Investigate (it is the sensitivity control) [ASSUMPTION decision] (DEC-0400) [ASSUMPTION decision] (DEC-0434) | report.md decision table |
| Runs recorded or explicitly cut | 100 % of planned priority runs recorded; every cut carries a reason | `runs.jsonl`, NOTES |
| Grader self-check | known-good passes and known-bad fails on 16 of 16 tasks | `ablation-grade.sh --self-check` |
| Fresh-mount integrity | `check-loa.sh` exit 0, 0 Tampered, 0 Missing-should-link | `tools/fresh-mount-proof.sh` |
| Spend | cycle total ≤ USD 1,500; no run above USD 12 counted as completed | `evals/harness/spend.sh` |
| A4 sensitivity | A4 worse than A1 on at least one primary metric with the interval excluding zero | report.md |
| Pruned default | within −0.03 of old A1 on each applicable primary, by the re-verification rule in FR-9 | report.md §Re-verification |

### Constraints

- Whole-cycle cap USD 1,500 and per-run cap USD 12, operator-set; priority arms A0–A4 first; a run at the per-run cap is a failure, not a discard [ASSUMPTION decision] (DEC-0363). The cap covers executor-reported run cost plus cost-ledger rows; the lead's interactive session and its Agent-tool subagents are unmetered and outside it [ASSUMPTION decision] (DEC-0430).
- One host, one route (the Claude CLI via Bedrock for every Claude session; the codex CLI for the cross-model voice); `hounfour.headless.agy_opt_in` unset on every arm [ASSUMPTION decision] (DEC-0372).
- No dissent run while an arm batch is running (KF-037); batches detached under `~/.cache/loa/cycle-130/`.
- The floor is never pruned [ASSUMPTION decision] (DEC-0367).
- The cycle finishes before the 2.0.0 promotion PR; the promotion stays the operator's call.

> Sources: cycle-130-brief.md §Deliverables and exit criteria, §Metrics and instrumentation; ablation-2.0-continue-2026-10-14.md §Authority, §Known constraints; `grimoires/loa/known-failures.md` KF-037

---

## User Personas & Use Cases

### Primary Persona: Loa maintainer deciding the 2.0.0 promotion
Needs one table: component, measured lift on each primary metric with its interval, cost delta, decision. Reads `report.md`, confirms the `proposed` DEC rows with `/decisions confirm --cycle cycle-130 --all`, and links the report from the 2.0.0 release notes.

### Secondary Persona: Operator mounting Loa on a product repository
Needs `check-loa.sh` green on a fresh mount, a migration-guide addendum that names every component moved to opt-in and the key that turns it back on, and defaults that do not pay for components with no measured lift.

### Tertiary Persona: The next model bump
Needs `run-ablation.sh --source-commit <sha>` to rerun the frozen suite and the same report to come out, so the ablation repeats cheaply.

### Use Cases

| UC | Actor | Flow |
|---|---|---|
| UC-1 Run the priority arms | lead | `run-ablation.sh --arms a0_bare,a1_full,a2_no_sprint_plan,a3_one_voice,a4_no_gates --source-commit <sprint-258 commit> --max-usd <from batch-plan.md> --detach` → `runs.jsonl` rows, `STATUS.json`, spend posted |
| UC-2 Smoke an arm | lead | `run-ablation.sh --smoke --arms A7` → one review-catch and one build run; the took-effect check prints `effort: medium` on every phase or fails |
| UC-3 Decide a component | report | `ablation-report.py` reads `runs.jsonl`, applies the pre-registered rules, writes the decision row with its numbers |
| UC-4 Prove the mount | CI, lead | `tools/check-manifest-paths.sh` in Shell Tests; `tools/fresh-mount-proof.sh` in a temp dir |
| UC-5 Repeat after a model bump | maintainer | same command with a new `--source-commit`; the frozen manifest hash is checked first |

> Sources: cycle-130-brief.md §Run protocol, §Deliverables; ablation-2.0-continue-2026-10-14.md §Deliverables

---

## Functional Requirements

### FR-1: Mount integrity (#1267) and version markers
**Description:** `tools/gen-checksums.sh` writes `.claude/checksums.json` from the tracked `.claude/` tree (`git ls-files .claude`, excluding `overrides/` and the manifest itself) and `--check` compares the committed manifest to that generation; a Shell Tests step (`tools/check-manifest-paths.sh`) fails when a manifest path is untracked, absent from the tree, or under a build, cache or runtime class (`__pycache__`, `.pytest_cache`, `node_modules`, `.run/`, `*.pyc`, `*.lock`); `check-loa.sh` reports a manifest path that is absent from a submodule mount but present under `.loa/.claude/` as `not-mounted` (informational, counted) and fails only on `Tampered` or on a missing path the mount is supposed to link; `tools/fresh-mount-proof.sh` mounts this branch into a temporary directory as a submodule with Aleph absent and runs `check-loa.sh`; `.loa-version.json` and the `CLAUDE.loa.md` marker read `2.0.0-rc.5` [ASSUMPTION decision] (DEC-0368).
**Acceptance criteria:**
- AC-1.1 `gen-checksums.sh --check` exits 0 on the committed manifest; the manifest has no entry outside `git ls-files .claude`; entry count equals the tracked count minus `overrides/` and the manifest.
- AC-1.2 `check-manifest-paths.sh` fails on a fixture manifest with one untracked path and on one with a `__pycache__` entry; passes on the committed one; the step runs in `bats-tests.yml` Shell Tests.
- AC-1.3 `fresh-mount-proof.sh` exits 0 with Aleph absent: `check-loa.sh` prints `Integrity verified` or `not-mounted: N` with 0 Tampered and 0 Missing-should-link; the proof log is in the sprint report.
- AC-1.4 `.loa-version.json:framework_version` and the `CLAUDE.loa.md` managed marker both read `2.0.0-rc.5`; `tools/check-prompt-budget.sh` is ok on the tag under test (recorded).

> Sources: issue #1267 body and downstream comment (242 build artefacts; 0 mismatches on anything mounted); `.claude/scripts/mount-loa.sh:1103-1127`; `.claude/scripts/check-loa.sh:47-68`; `.github/workflows/bats-tests.yml:86`; `git diff main v2.0.0-rc.5 -- .loa-version.json .claude/loa/CLAUDE.loa.md`

### FR-2: Spend caps as mechanism
**Description:** `run-arms.sh` and the new `run-ablation.sh` take `--max-usd <ceiling>`: the driver sums the executor-reported `total_cost_usd` of completed and failed trials and stops launching new trials when the next trial would pass the ceiling, writes `cut_reason: max_usd` and the figure to `STATUS.json`, and exits 1 (partial); `--screen` runs a screening tier (one trial of the first N tasks per arm) and prints a per-arm cost table before a full batch (bd-j4lwr). `--max-usd` reserves the per-run cap for every in-flight trial, so completed plus reserved never passes the ceiling under concurrency. The pipeline executor aborts a run whose cumulative phase cost passes the per-run cap (`--max-run-usd`, default 12) and records `status: cap_failure` with the phase reached; a cap failure counts as a failed run (0 on each applicable primary) and is listed; it is never excluded [ASSUMPTION decision] (DEC-0393). `evals/harness/spend.sh` prints the cycle spend: `runs.jsonl` cost plus `.run/cost-ledger.jsonl` rows since the kickoff timestamp, and the remaining headroom [ASSUMPTION decision] (DEC-0363).
**Acceptance criteria:**
- AC-2.1 `run-arms.bats` pins: a stub executor whose rows cost USD 5 each under `--max-usd 12` launches two trials, cuts before the third, writes `cut_reason`, exits 1.
- AC-2.2 `pipeline-run.bats` pins: a stub phase sequence whose third phase passes USD 12 aborts after that phase, writes `status: cap_failure` and `cap_phase`, and the grader scores the run 0 on hidden tests.
- AC-2.3 `spend.sh --since <ts>` sums a fixture `runs.jsonl` and a fixture cost ledger and prints total, cap and headroom; `--json` carries the same fields.
- AC-2.4 `--screen` prints the per-arm table from one trial of two tasks and writes nothing to the suite's `STATUS.json`.

> Sources: `evals/harness/run-arms.sh:120-135,330-420`; `br show bd-j4lwr`; ablation-2.0-continue-2026-10-14.md §Spend; `evals/harness/execute-agent.sh:430-470` (`total_cost_usd`)

### FR-3: Arm profiles and toggles
**Description:** `evals/suites/ablation-2.0.yaml` declares the nine arms with canonical ids `a0_bare`, `a1_full`, `a2_no_sprint_plan`, `a3_one_voice`, `a4_no_gates`, `a5_no_flatline`, `a6_one_window`, `a7_effort_medium`, `a8_no_ceremonies` (declared `absent: true` with the grep evidence; never run), each with its toggles, its applicability (`task_types`: A2, A4, A5, A6 build tasks only — on a review-catch task the gates are the task, so A4 there is degenerate; A0, A1, A3, A7 all types) and the took-effect check the smoke pass runs [ASSUMPTION decision] (DEC-0400). `execute-agent.sh` gains toggles `loa_mount: false` (no `.claude/`, no `CLAUDE.md`, no appended skill prompt; the task prompt only), `effort: medium` (`--effort medium` on the CLI call, recorded), `gates: false` (`flatline_protocol.code_review.enabled` and `security_audit.enabled` false in the sandbox config and `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` in the sandbox environment), `flatline: false` (`flatline_protocol.enabled: false`); the pipeline executor reads `sprint_plan: false`, `context_resets: false` (A6: PLAN, IMPLEMENT and the FIX rounds continue one Opus 5.5 session with `--resume`; the gates stay separate Fable 5.1 sessions with dissent, exactly as A1, so only reset-and-handoff is removed [ASSUMPTION decision] (DEC-0391)) and `companion_voice: false`; every toggle is applied to the sandbox copy only, verified afterwards, and a toggle that cannot take effect fails the trial (exit 2). The cycle-129 toggles stay as they are [ASSUMPTION decision] (DEC-0358).
**Acceptance criteria:**
- AC-3.1 `arm-toggles.bats`: a sandbox prepared for `a0_bare` has no `.claude/` and no `CLAUDE.md` and the CLI stub receives no `--append-system-prompt-file`; `a7_effort_medium` passes `--effort medium`; `a4_no_gates` leaves both `enabled` keys `false` and the env var set; `a5_no_flatline` leaves `flatline_protocol.enabled: false`; the baseline (`a1_full`) takes no toggles.
- AC-3.2 The suite file declares `task_types` per arm (A2, A4, A5, A6 build only; A8 absent); `run-ablation.sh` refuses to schedule an arm on a task type outside its declaration and `ablation-report.py` refuses such a row [ASSUMPTION decision] (DEC-0406).
- AC-3.3 The smoke took-effect check reads the artefacts named in the suite and fails the batch on any arm whose evidence is missing.

> Sources: `evals/harness/execute-agent.sh:56-77,161-200,240-295`; `evals/suites/review-recall.yaml:16-50`; `.claude/hooks/safety/adversarial-review-gate.sh:24,84`; `.loa.config.yaml` `flatline_protocol.{enabled,code_review.enabled,security_audit.enabled}`; `grep -rli sosyete .claude/ docs/` (no match)

### FR-4: Pipeline executor for build tasks
**Description:** `evals/harness/pipeline-run.sh` runs one build task under one arm: it materialises a sandbox repository from the task's pinned fixture tree plus the Loa mount from the pinned source worktree (`.claude/` copied, `CLAUDE.md`, `.loa.config.yaml` from the arm profile, `grimoires/loa/` with `ledger.json`, `NOTES.md` and the task brief, `.run/` with a zone-free state), then drives the phases as separate `claude -p` sessions with Bash, Read, Grep, Glob, Write and Edit inside the sandbox: PLAN (`sprint.md` from the brief; Flatline on it when on), IMPLEMENT (implementing-tasks, Opus 5.5), REVIEW (reviewing-code on Fable 5.1 with `adversarial-review.sh`), FIX (one round when CHANGES_REQUIRED), AUDIT (auditing-security on Fable 5.1 with its dissent), FIX (one round); each phase reads the a2a handoff files the previous one wrote; A2 skips PLAN, A4 stops after IMPLEMENT, A5 runs PLAN without Flatline, A6 keeps the implementer's session continuous across PLAN, IMPLEMENT and the FIX rounds while the gates run as in A1, A3 sets `companion_voice: false`, A7 passes `--effort medium`, A0 runs one bare session with the task text, the same tools and the same environment, `--effort high`, and a turn and time budget equal to the sum of A1's implementer-side caps [ASSUMPTION decision] (DEC-0403). Every phase runs inside the ablation container (per-run read-only copies of the CLI credential directories, the sandbox read-write, no other host path; the host sandbox is the recorded fallback when the Sprint 258 smoke cannot complete a run in the container) [ASSUMPTION decision] (DEC-0411), under `env -i` with an enumerated allowlist (`PATH`, `HOME`, `LANG`, `LC_ALL`, `TERM`, a sandbox `TMPDIR`, `CLAUDE_CODE_USE_BEDROCK`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`, `CLAUDE_CODE_SUBAGENT_MODEL`, the two Loa ledger paths, the arm's own variables); no access key or API key is present; network and `HOME` cannot be isolated without breaking the CLI's own route, which the report states [ASSUMPTION decision] (DEC-0394). The sandbox tree is committed after IMPLEMENT and after each FIX so the grader can score each gate's verdict against the tree it reviewed [ASSUMPTION decision] (DEC-0402). A run killed mid-phase is `status: interrupted`: not graded, not counted, listed, rerun by `--resume` when budget allows [ASSUMPTION decision] (DEC-0406). Each phase records session id, model id, effort requested and effective, tokens, cost, duration and exit in `.eval/pipeline.json`; the sandbox MODELINV and cost ledger are redirected into `.eval/`; the run aborts at the per-run cap [ASSUMPTION decision] (DEC-0357) [ASSUMPTION decision] (DEC-0374).
**Acceptance criteria:**
- AC-4.1 `pipeline-run.bats` with a stub CLI: A1 runs six phases in order and writes `pipeline.json` with one record per phase; A2 has no PLAN record; A4 ends after IMPLEMENT; A6 has one session id; A0 has one phase and the sandbox has no `.claude/`.
- AC-4.2 The sandbox never contains the hidden tests or defect keys (`grimoires/loa/evals/ablation-2.0/tasks/<id>/hidden/` is read by the grader only); `pipeline-run.bats` asserts their absence.
- AC-4.3 Every phase's environment is exactly the allowlist (asserted on the stub's captured environment: no variable outside the list, no `AWS_ACCESS_KEY_ID`, `GH_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY` or Google key); the codex voice uses the codex CLI's own auth under `HOME`.
- AC-4.4 A live smoke run of A1 on one build task completes with `pipeline.json` carrying a MODELINV-derived `effort_effective` per phase, the dissent envelope's `voices` under REVIEW and AUDIT, the post-IMPLEMENT and post-FIX snapshot ids, and `check-loa.sh` integrity green inside the sandbox mount.
- AC-4.5 `pipeline-run.bats`: A6 shows one session id across PLAN, IMPLEMENT and FIX records and distinct ids on REVIEW and AUDIT; A0's `--max-turns` and timeout equal the sums declared in the suite; a stub phase killed by SIGTERM yields `status: interrupted` and no `grade.json`.

> Sources: `evals/harness/execute-agent.sh:340-380` (session decoupling, credential unset); `.claude/skills/run-mode/SKILL.md` (phase order); `.claude/scripts/adversarial-review.sh:1-60`; `.claude/scripts/verdict-derive.sh:1-30`; cycle-130-brief.md §Arms notes

### FR-5: Frozen task suite with hidden tests
**Description:** `grimoires/loa/evals/ablation-2.0/` holds `tasks/<id>/task.yaml` (type, source, pinned commit, fixture path, success criterion in one line, test command, time and turn bounds), `TASK.md` (the brief the agent sees), `hidden/` (tests and keys the grader applies after the run; never copied into a sandbox), `REVIEW.md` (the fairness review) and `MANIFEST.sha256` over everything; `freeze.sh` writes the manifest and `--check` refuses any drift. Sixteen tasks: four review-catch from the frozen corpus (two planted fixtures with three seeded defects, two record fixtures with approved labels), four bug-fix tasks seeded from Loa fix commits dated 2026-08 or later whose fix touched tests (base = parent; hidden tests = the fix's tests; verified red at base and green at the fix mechanically), four refactor tasks from Loa refactor commits with unchanged green tests (diff size and churn recorded), four feature-build tasks from open beads at rc.5 with hidden bats written for the suite. A build task's fixture tree, its tests and its reference patch never touch `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/` or `.run/` (the mount owns those paths in the sandbox); Loa-history candidates come from `tools/`, `evals/` and `tests/`, the seeders refuse any other, and bd-yzzb9 (code under `.claude/adapters/`) is replaced as a feature-build source by an `evals/`- or `tools/`-scoped bead or a synthetic feature on the Python fixtures [ASSUMPTION decision] (DEC-0396). Each refactor task's hidden tests add a structural assertion the reference refactor satisfies (red at base, green at the reference) so the self-check has a failing state [ASSUMPTION decision] (DEC-0401). Each review-catch `TASK.md` carries an arm-neutral output contract (findings file path, one `path:line — description` per line, a verdict line) that A0 writes and whose shape the gates' files are reduced to for grading [ASSUMPTION decision] (DEC-0403). The suite freezes at the end of Sprint 259; any change after the Sprint 260 smoke (a cap-fit shrink, an insensitivity hardening) bumps `suite_version`, writes a new manifest, archives the smoke rows under the old version and runs the main batch on one version only [ASSUMPTION decision] (DEC-0405). At least half the tasks are from code written after 2026-07 (all sixteen are; feature-build tasks date from their bead's creation). Each task's hidden tests are reviewed by an Opus 5.5 subagent that did not write the task [ASSUMPTION decision] (DEC-0359) [ASSUMPTION decision] (DEC-0361).
**Acceptance criteria:**
- AC-5.1 `freeze.sh --check` exits 0 on the committed suite and 1 after any byte changes under `tasks/`; the manifest hash is in the sprint report and `report.md`.
- AC-5.2 Every `task.yaml` names a one-line `success_criterion` the grader evaluates mechanically, a `test_command` from the allowlist, and `post_cutoff: true` with the commit date.
- AC-5.3 For every bug-fix and feature-build task the hidden tests fail at base and pass at the reference patch (`ablation-grade.sh --self-check` runs both); for every refactor task the reference diff leaves the suite green and the churn figure is recorded.
- AC-5.4 Every task has a `REVIEW.md` written by a different session than its author, with the three checks (no solution leak, red-then-green run, criterion mechanical) answered.
- AC-5.5 No hidden file path appears under any sandbox created for the task (asserted by `pipeline-run.bats` and the single-skill `execute-agent.bats` case).
- AC-5.6 `seed-bugfix.bats` and `seed-refactor` cases: a candidate whose paths touch `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/` or `.run/` is refused by name; every committed `task.yaml` lists `grader_protected` files and the review-catch tasks carry the output contract.

> Sources: cycle-130-brief.md §Task suite; `evals/fixtures/review-prs/corpus.tsv`, `labels/`, `manifests/`; `evals/fixtures/implement-tasks/expectations/01.json`; `git log --since=2026-08-01 --diff-filter=A -- 'tests/unit/*.bats' '.claude/adapters/tests/*.py'`; `br ready`

### FR-6: Mechanical grader and `runs.jsonl`
**Description:** `evals/harness/ablation-grade.sh <run-dir> <task-id>` grades in a fresh grading tree: the agent's final tree is copied, the task's `grader_protected` files (test infrastructure: `conftest.py`, `pytest.ini` and pyproject test config, bats helpers, Makefile test targets, runner configs) are restored from the frozen reference, the hidden tests are overlaid, and the task's test command runs under `env -i` with `PATH` limited to `/usr/bin:/bin` plus the declared toolchain directory, `python3 -I -s -m pytest -p no:cacheprovider --rootdir` for Python, a 120 s timeout; regressions run on the restored tests; `recall-vs-defects.sh` and the false-positive count run on the arm-neutral findings file for review-catch tasks; verdict accuracy is scored per gate against the snapshot that gate reviewed (the run-level figure is the audit gate's when it ran, else the review gate's); every phase transcript is scanned for tool inputs naming an absolute path outside the sandbox (the CLI's own `HOME` configuration excepted), the string `hidden`, the repository's suite path, or `git log --all`/reflog, and a hit marks the run `contaminated`; the report and the logs print defect and test ids only. `grade.json` is written; the grader never reads the arm label [ASSUMPTION decision] (DEC-0395) [ASSUMPTION decision] (DEC-0402). `evals/harness/ablation-row.sh` writes one `runs.jsonl` row per run (schema in SDD §3.1): arm, task, type, trial, source commit, host fingerprint, image digest, per-phase model id, effort requested and effective, tokens, cost, duration, voices run, both primary metrics, every secondary and cost metric, `degraded` with reason, `status`. `--self-check` grades the reference patch (expects pass) and the base tree (expects fail) for every task [ASSUMPTION decision] (DEC-0360) [ASSUMPTION decision] (DEC-0375) [ASSUMPTION decision] (DEC-0376).
**Acceptance criteria:**
- AC-6.1 `ablation-grade.bats`: hidden tests applied after the run in a grading tree outside the sandbox; a run that deleted the test directory still gets graded; an agent-edited `conftest.py`, `pytest.ini`, bats helper or Makefile target is replaced by the frozen reference before the tests run; a same-named file is overwritten by the hidden copy; a transcript naming a path outside the sandbox yields `contaminated`; test and defect names never appear in `grade.json`'s summary fields.
- AC-6.2 Verdict accuracy per gate is `true` when APPROVED and the snapshot that gate reviewed passes the hidden tests, or CHANGES_REQUIRED and it fails; `false` otherwise; `null` when no gate ran (A0, A4); the run-level figure is the audit gate's, else the review gate's.
- AC-6.3 `ablation-row.sh --validate` rejects a row missing any schema field; `runs.jsonl` rows carry `effort_effective` per phase from the sandbox MODELINV and `voices_run` from the dissent envelopes; a phase whose effective effort or model differs from the requested one sets `degraded: true` with the reason.
- AC-6.4 `--self-check` passes 16 of 16 and is recorded in the Sprint 259 report: for bug-fix and feature-build tasks the reference patch passes and the base tree fails; for refactor tasks the structural assertion fails at base and passes at the reference while the unchanged suite is green at both; for review-catch tasks an empty findings file scores recall 0 and a file citing every key anchor scores 1 [ASSUMPTION decision] (DEC-0401).

> Sources: cycle-130-brief.md §Metrics and instrumentation; `evals/graders/recall-vs-defects.sh:1-60`; `evals/graders/tests-pass.sh:1-40`; `evals/graders/implement-discipline.sh:40-60` (clean-env test run); `.claude/scripts/verdict-derive.sh`; `.claude/adapters/loa_cheval/audit/modelinv.py` (`effort_effective`)

### FR-7: Run protocol, pre-registration and smoke
**Description:** `run-ablation.sh` plans arm × task × trial in a randomised order (seeded shuffle recorded in the manifest), runs single-skill trials through `run-arms.sh`'s machinery and build trials through `pipeline-run.sh`, interleaves arms, retries once on a transport failure only (logged with reason), grades after the batch, and appends rows. Before the priority batch, the lead records the decision rules, the applicability matrix, the cut order and the budget plan in NOTES § Decision Log, runs `--smoke` (one review-catch and one build task, one trial, every runnable arm) and the took-effect check, and reads A1's cost per build task: a median above USD 9 sends the build tasks back for shrinking before any batch (never the cap). Three trials per build task and three per review-catch task (under the gate pipeline a review-catch trial costs as much as a build run; SDD A4); the plan is trial-major with a seeded shuffle inside each trial block; a batch refuses a CLI-version or model-id change mid-batch [ASSUMPTION decision] (DEC-0407). Priority arms A0–A4 first; the pre-registered cut ladder beyond the arms is (1) A5, A6, A7 not run, (2) A2 and A3 build trials 3 → 2, (3) A3 review-catch trials 3 → 2, while A0, A1 and A4 keep three build trials because H1 and the sensitivity check rest on them; the smoke calibration picks the rung in `batch-plan.md`; every cut is recorded with its reason and figure [ASSUMPTION decision] (DEC-0397). Each arm is decided on the primaries its task types reach: build-only arms on hidden-test pass rate alone, all-type arms on both [ASSUMPTION decision] (DEC-0400). Degraded and contaminated runs are excluded pairwise (the task-trial cell leaves both arms of the comparison; a task with no valid cell in an arm leaves that pair and is listed); an arm whose excluded share exceeds 25 % reads Inconclusive-by-degradation [ASSUMPTION decision] (DEC-0393). The defect catch rate interval resamples defect ids (about 150 units) with the task-level interval also shown; the hidden-test pass rate interval resamples the twelve build tasks; the minimum detectable effect is computed from smoke variance; six components are decided without a multiple-comparison correction and the expected false-positive count at 90 % is printed [ASSUMPTION decision] (DEC-0399). Two decisions are escalations: H1 not established (A1 not better than A0 on at least one primary with the interval excluding zero) halts before promotion; A4 not clearly worse than A1 means the suite is insensitive. In either case Sprint 262 performs no opt-in move, the report and the addendum say so, rc.6 ships with the report linked, and the operator decides between hardening (with its cost estimate) and halting [ASSUMPTION decision] (DEC-0409) [ASSUMPTION decision] (DEC-0364) [ASSUMPTION decision] (DEC-0365) [ASSUMPTION decision] (DEC-0377) [ASSUMPTION decision] (DEC-0378).
**Acceptance criteria:**
- AC-7.1 The NOTES Decision Log carries the pre-registration entry with a timestamp earlier than the first row in `runs.jsonl`.
- AC-7.2 `run-ablation.sh --dry-run` prints the randomised plan with its shuffle seed and writes `MANIFEST.json` with the source commit, model ids, toolchain fingerprint, `agy_opt_in: false`, arms, tasks, trials, cap figures.
- AC-7.3 The smoke report lists every arm with its took-effect evidence and A1's cost per build task; the batch command in the sprint report shows `--max-usd`.
- AC-7.4 Every retry is a row field (`attempts`, `retry_reason`); model-caused failures carry `status: agent_error` and are never retried; a killed run carries `status: interrupted`.
- AC-7.5 `batch-plan.md` shows the arm × type × trials × unit-cost table from smoke actuals, the chosen rung of the cut ladder, the minimum detectable effect, the wall-clock estimate at the chosen concurrency, and the gate-model contingency read.

> Sources: cycle-130-brief.md §Run protocol, §Decision rules; `evals/harness/run-arms.sh:150-170,300-330` (plan, transport classifier); ablation-2.0-continue-2026-10-14.md §Spend

### FR-8: Analysis and report
**Description:** `evals/harness/ablation-report.py` (stdlib) reads `runs.jsonl` and the batch manifests, scores cap failures as failed runs and excludes degraded, contaminated and interrupted runs pairwise (listing them, with the per-arm excluded share and the 25 % guard), computes per arm the applicable primaries and every secondary and cost metric, the paired bootstrap (10,000 resamples, 90 % percentile interval; defects as the unit for the catch rate, tasks for the pass rate) of each arm's difference from A1, a labelled sensitivity figure with cap failures excluded that no decision uses, applies the pre-registered rules to produce one decision per component, checks H1 and the A4 sensitivity rule, and writes `grimoires/loa/reports/ablation-2.0/report.md` with a decision table whose every cell names the rows it came from; the lead adds the reading of missed labels and failed runs. Inconclusive arms get two more trials once, then the rule applies again (recorded).
**Acceptance criteria:**
- AC-8.1 `ablation-report.bats` on a fixture `runs.jsonl`: a planted −0.05 drop with a tight interval reads Keep; a 0.00 drop with 20 % lower cost reads Remove; a 0.00 drop with similar cost reads Simplify; a wide interval reads Inconclusive; a +0.04 reads Investigate; H1 and A4 rules fire on planted inputs; a cap failure scores 0; a degraded cell is dropped from both arms; an arm with 30 % excluded reads Inconclusive-by-degradation; a build-only arm is decided on the pass rate alone.
- AC-8.2 `report.md` lists per arm: n runs, excluded runs with reasons, both primaries with intervals, secondaries, cost per task, wall-clock, tokens, the decision and the rule line it matched.
- AC-8.3 The report's decision table has one row per component A2–A7, a row for A8 reading component-absent, and the H1 and A4 verdict lines.

> Sources: cycle-130-brief.md §Decision rules, §Deliverables; `evals/harness/arms-report.py:1-60` (bootstrap, verdict shape)

### FR-9: Prune, document and re-verify
**Description:** Components with a Remove decision leave the default path and become opt-in through existing keys or profile knobs; Simplify decisions remove unless a written non-quality purpose (auditability, governance) is recorded; Keep decisions write the measured lift into the component's docs; the floor is untouched. `docs/migration/v2.0-ablation-addendum.md` lists every component moved to opt-in with the key that restores it. The re-verification follows one rule: if no component reads Remove or Simplify there is no re-run; if exactly one does, that arm's rows already measure the pruned default and the bound is read from them; if several do, `a1_pruned` (the shipped Sprint 262 tree pinned as its own source commit) and a fresh `a1_full` control run interleaved on the same day, one trial per task, paired by task, when the reserve allows, else only the removal with the largest cost saving is applied and the others are recorded as decided, not applied this cycle; the bound is the paired point estimate ≥ −0.03 on each applicable primary with the 90 % interval and the minimum detectable effect printed, and the report states that this sample detects a gross regression only; the reserve is USD 250, released to A7 when the first two cases apply [ASSUMPTION decision] (DEC-0398) [ASSUMPTION decision] (DEC-0425). If H1 is not established or A4 is insensitive, no component is pruned (DEC-0409). bd-2txz1's kernel deletions are decided by the arm outcomes and applied or closed with the reading [ASSUMPTION decision] (DEC-0371).
**Acceptance criteria:**
- AC-9.1 Every Remove or Simplify decision maps to a config key or profile knob change in `.loa.config.yaml.example` and `profiles.yaml`, with the restore key in the addendum; `floor-snapshot.bats` and `profile-floor.bats` stay green.
- AC-9.2 `report.md §Re-verification` names the rule case that applied and shows the pruned default within −0.03 of `a1_full` on each applicable primary (from the arm's rows or from `a1_pruned`), or the prune is reverted or held back and the reason recorded.
- AC-9.3 Every Keep component's reference doc carries one sentence with its measured lift and interval.
- AC-9.4 `grimoires/loa/reports/release-notes-2.0.0-rc.6.md` links `report.md`; the 2.0.0 notes stub carries the same link.

> Sources: cycle-130-brief.md §Decision rules, §Sprint breakdown 5; `.claude/data/profiles.yaml`; `.claude/data/floor.yaml`; `docs/migration/v2.0-model-generation-floor.md:1-12`

### FR-10: Carry-overs
**Description:** bd-s93s8 (cycle-129 archive on main) lands in the plan commit; bd-j4lwr's `--max-usd` and `--screen` in FR-2, its dispatch-practice note in the run-mode reference; bd-8o5rx (generated paths excluded from `fix_regions` in `seed-corpus-from-record.sh`, the eight manifests and `SHA256SUMS` regenerated, cycle-129 batch 1 refuted share regraded; recall unchanged by construction) in Sprint 259; bd-yzzb9 is a feature-build task source and its production fix a Sprint 262 task gated on remaining budget; bd-b4ji is noted at archive time (this plan commit folds the rc.5 CHANGELOG heading and ledger archive onto main for the third cycle running) [ASSUMPTION decision] (DEC-0371).
**Acceptance criteria:**
- AC-10.1 `seed-corpus.bats` pins the exclusion (`dist/`, `*.map`, `*.d.ts`, `.checksum`, `checksums.json`, `REPO-MAP.md`, `.build-manifest.json`); the regenerated manifests carry no generated path in `fix_regions`; the regraded batch-1 refuted shares are in the sprint report with recall unchanged.
- AC-10.2 The ledger shows cycle-129 archived and cycle-130 active with sprints 258–262 in the plan commit; `CHANGELOG.md` carries `## [2.0.0-rc.5] — 2026-10-14` over the cycle-129 entries on this branch.
- AC-10.3 bd-s93s8 closed at the plan commit; bd-j4lwr, bd-8o5rx, bd-2txz1 closed or re-scoped with a comment by cycle end; bd-yzzb9 closed if its Sprint 262 fix lands, else commented.

> Sources: `br show bd-s93s8 bd-j4lwr bd-8o5rx bd-2txz1 bd-yzzb9 bd-b4ji`; ablation-2.0-continue-2026-10-14.md §Prerequisites the plan commit must carry

> Sources: this section's requirements derive from cycle-130-brief.md (§Prerequisites, §Task suite, §Arms, §Metrics, §Run protocol, §Decision rules, §Sprint breakdown) and the continuation prompt; file cites per FR above

---

## Non-Functional Requirements

### Performance
- A single-skill review-catch trial completes in ≤ 25 min (the cycle-129 `per_trial` 1,500 s); a pipeline run completes in ≤ 90 min with per-phase timeouts (PLAN 15, IMPLEMENT 25, REVIEW 20, FIX 15, AUDIT 20, FIX 15); concurrency 2–3 so the whole priority batch fits in about one day of wall-clock.
- The grader runs in ≤ 3 min per run; `ablation-report.py` with 10,000 resamples finishes in ≤ 2 min on 300 rows.

### Scalability
- The suite and the runner are parameterised by `--source-commit`, so the next model bump reruns the same sixteen tasks without code changes; adding a task is one directory plus `freeze.sh`.

### Security
- Hidden tests and keys live under `grimoires/loa/evals/ablation-2.0/tasks/<id>/hidden/` and are never copied into a sandbox; the grader reads them from the repository root.
- The sandbox executor unsets every operator credential except the CLI's own route (as `execute-agent.sh` does); the codex voice runs under the codex CLI's own auth; no credential enters an image or a fixture.
- Fixture trees drawn from Loa history pass `no-secrets.sh` at seeding; task text is control-stripped; third-party text (fixture PR bodies) is untrusted and never interpreted as instructions by the harness.
- Nothing from a run's output reaches `report.md` unescaped; the report prints ids, numbers and the lead's prose.

### Reliability
- Batches run detached (`setsid nohup`) with logs under `~/.cache/loa/cycle-130/`; a host reboot leaves `STATUS.json` `running`, which `run-ablation.sh --resume` reconciles from the rows on disk.
- Transport failures are retried once; model failures never; every retry is logged.

### Compliance
- Decision rules, applicability and cut order are written in NOTES before the first run and quoted in the report; results do not change them.
- Every operator-behalf decision is a `proposed` DEC row; the operator confirms with `/decisions confirm --cycle cycle-130 --all`.

> Sources: cycle-130-brief.md §Run protocol, §Risks and threats to validity; `evals/harness/execute-agent.sh:350-375`; `evals/graders/no-secrets.sh`; `grimoires/loa/known-failures.md` KF-037

---

## User Experience

### Key User Flows
1. **Lead runs the cycle**: plan commit → Sprint 258 (plumbing, smoke on existing fixtures) → Sprint 259 (frozen suite, grader self-check) → Sprint 260 (pre-registration, smoke, priority batch, spend posts) → Sprint 261 (report) → Sprint 262 (prune, addendum, re-verification) → PR → Bridgebuilder → merge → rc.6.
2. **Maintainer reads the result**: `report.md` decision table; `/decisions confirm`; the 2.0.0 promotion PR links the report.
3. **Operator upgrades**: the addendum names each opt-in component and its restore key.

### Interaction Patterns
- Every script prints one line per decision it takes (`cut: max_usd 1270.4 reached after 212 trials`), exits by the documented code table, and writes JSON next to its markdown.
- The smoke took-effect check prints `arm <id>: <evidence>` per arm and refuses the batch on a miss.

### Accessibility Requirements
- Reports are plain markdown tables; no colour carries meaning; every number has its unit.

> Sources: cycle-130-brief.md §Run protocol step 7; `evals/harness/report.sh:1-40`

---

## Technical Considerations

### Architecture Notes
- Two executors, one row schema: single-skill trials (review-catch) reuse `run-arms.sh` → `execute-agent.sh` → `grade.sh`; build trials run `pipeline-run.sh`; both end in `ablation-grade.sh` and `ablation-row.sh` [ASSUMPTION decision] (DEC-0357).
- The sandbox is the host temp-dir sandbox; the image digest field is a toolchain fingerprint; all arms share one host and one route [ASSUMPTION decision] (DEC-0362).
- A seed is the trial index; the CLI route has no sampling seed [ASSUMPTION decision] (DEC-0373).

### Integrations
- Claude CLI (2.1.299, Bedrock route, `global.anthropic.claude-opus-5-5` executor, `global.anthropic.claude-fable-5-1` gates), codex CLI 0.137.0 for the cross-model voice, pytest 9 and bats 1.13 for hidden tests, yq v4, jq, Python 3.13 stdlib for the report.

### Dependencies
- The `v2.0.0-rc.5` tag fetched (done); the record fixtures approved (done in cycle-129); the cycle-129 helper scripts (`refresh-checksums.py`, `publish-rc5.sh`, `record-branch.sh`) adapted under `~/.cache/loa/cycle-130/`.

### Technical Constraints
- A3 is a new measurement: cycle-129's `no_companion` ran a single skill where no dissent executed; here the companion voice runs inside the REVIEW and AUDIT phases [ASSUMPTION decision] (DEC-0408).
- The Fable 5.1 executor refuses security-shaped tasks mid-trial and the CLI falls back silently; the executor is Opus 5.5 and every row records `models_used` and `refusal_fallbacks` (cycle-129 DEC-0172).
- No dissent while a batch runs (KF-037); the lead's sprint gates for Sprint 260 run between batches.
- The planning skills are not loaded through the Skill tool in this session (KF-043 class) [ASSUMPTION decision] (DEC-0369); the planning Flatline runs are integrated by judgment under KF-041 [ASSUMPTION decision] (DEC-0370).

> Sources: `evals/harness/run-arms.sh:46-56`; `grimoires/loa/known-failures.md` KF-037, KF-041, KF-043; `~/.cache/loa/cycle-129/` helper scripts

---

## Scope & Prioritization

### In Scope (MVP)
FR-1 … FR-10 as written; arms A0–A4 on the sixteen tasks at the brief's trial counts; smoke; report; prune; re-verification on the reserve set.

### In Scope (Future Iterations)
A5, A6, A7 beyond what the cap allows this cycle (recorded as cut with figures; the suite reruns them later); feature-build tasks from Freeside or Hounfour once their toolchains have a sandbox recipe; a cross-family appeal pass on missed labels as a report column.

### Explicitly Out of Scope
New features, new constructs, model retargeting (the brief); pruning any floor guard; the 2.0.0 promotion itself; changes to `adversarial-review.sh`, `verdict-derive.sh` or the gate hooks beyond what the arms need to read.

### Priority Matrix

| Priority | Items |
|---|---|
| P0 | FR-1 (prerequisite: no arm runs on a broken mount), FR-2, FR-3, FR-4, FR-5, FR-6, FR-7 |
| P1 | FR-8, FR-9 |
| P2 | FR-10 beyond bd-s93s8 and bd-j4lwr flags; A5–A7 runs |

> Sources: cycle-130-brief.md §Out of scope, §Arms notes ("If the arms don't fit the budget, run A0, A1, A2, A3, A4 first"); ablation-2.0-continue-2026-10-14.md §Floor

---

## Success Criteria

### Launch Criteria
- All five sprints reviewed and audited APPROVED with COMPLETED markers; PR green; Bridgebuilder findings triaged; `v2.0.0-rc.6` published as a pre-release with the report linked.
- G-1 … G-6 validated in the Sprint 262 E2E record.

### Post-Launch Success (30 days)
- The 2.0.0 promotion PR cites `report.md`; downstream mounts report `check-loa.sh` green on rc.6.

### Long-term Success (90 days)
- The next model bump reruns `run-ablation.sh` on the frozen suite and the decision table is reproduced or revised with new numbers.

> Sources: cycle-130-brief.md §Deliverables and exit criteria

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| A1 pipeline runs cost more than the per-run cap and read as failures | Med | High | smoke cap-fit rule (DEC-0378): median > USD 9 shrinks the build tasks; one fix round per gate (DEC-0374) |
| The suite is too easy (A4 ≈ A1) | Med | High | the brief's sensitivity rule halts action on other arms until the tasks are hardened; the self-check requires a known-bad patch to fail |
| Budget runs out before A5–A7 | High | Med | priority order pre-registered; reserve for re-verification; every cut recorded with figures |
| Provider drift or rate limits during a day-long batch | Med | Med | interleaved randomised order, transport retry once, `--resume`, breakers observed |
| Memorised tasks | Low | Med | all sixteen tasks post-2026-07; Loa's own history after the cutoff |
| Hidden tests leak into the sandbox | Low | High | tests live outside fixture trees; bats asserts absence; the grader restores them |
| Fable refuses a security-shaped build task and the CLI falls back | Med | Med | executor Opus 5.5; `refusal_fallbacks` recorded; a changed model sets `degraded` |
| The planning Flatline degrades (KF-041) | High | Low | integrate by judgment, no retry |
| `.claude/` edits by subagents outside the sprint | Low | Med | worktrees with the marker; patches applied by the lead; `check-no-raw-sha256sum`, shell-compat and fixture sync before commits |

### Assumptions
- Opus 5.5's effective training cutoff precedes 2026-07 [ASSUMPTION fact] (the Agent-tool subagent reported June 2026 for this family; the arms do not depend on it beyond the memorisation mitigation).
- The Bedrock route stays available for the batch day; the breaker state is read before each batch [ASSUMPTION fact].

### Dependencies on External Factors
- Bedrock and OpenAI availability; GitHub Actions for the PR gates; the operator's confirmation of DEC rows is not a blocker for shipping the rc.

> Sources: cycle-130-brief.md §Risks and threats to validity; `evals/harness/run-arms.sh:300-330`; `grimoires/loa/known-failures.md` KF-041

---

## Timeline & Milestones

| Sprint | Global | Theme | Exit |
|---|---|---|---|
| 1 | 258 | Mount integrity and harness plumbing (FR-1, FR-2, FR-3, FR-4, FR-6 writer, smoke on existing fixtures) | fresh mount green; smoke shows each arm's config in its artefacts |
| 2 | 259 | Task suite and grader (FR-5, FR-6 grader, bd-8o5rx) | manifest hash committed; grader self-check 16/16 |
| 3 | 260 | Runs (FR-7): pre-registration, smoke, priority batch, cuts | all planned runs recorded or cut with reason; spend posted |
| 4 | 261 | Analysis (FR-8): blind grade, bootstrap, rules, report | one decision per component |
| 5 | 262 | Prune and document (FR-9, FR-10): opt-in moves, addendum, re-verification, E2E | pruned default within −0.03 of old A1 |

[ASSUMPTION decision] (DEC-0366): five sprints in the brief's order, Opus 5.5 implementers in worktrees, Fable 5.1 gates, at most three dissent runs per sprint.

> Sources: cycle-130-brief.md §Sprint breakdown; ablation-2.0-continue-2026-10-14.md §Process

---

## Appendix

### A. Stakeholder Insights
- The operator's brief is the requirement set; the continuation prompt adds two corrections (rc.5, reuse of cycle-129 instruments) and the authority chain. The brief's A8 names components that are not in Loa core at the pinned SHA; the suite records that rather than inventing a stand-in.

### B. Competitive Analysis
- The brief cites Anthropic's own removal of sprint decomposition once Opus 4.6 sustained long tasks natively; this cycle applies the same test to Loa's scaffolding with a pre-registered, externally graded design.

### C. Bibliography
- `grimoires/loa/context/cycle-130-brief.md`; `grimoires/loa/a2a/prompts/ablation-2.0-continue-2026-10-14.md`; `grimoires/loa/a2a/sprint-257/arms-report-{review,audit}-recall-2026-10-14.md`; issue #1267; `grimoires/loa/guards.md`; `.claude/data/floor.yaml`.

### D. Glossary
- **Arm**: one configuration of the harness run on every task; **A1** the full harness at the pinned SHA; **A0** bare Claude Code.
- **Primary metric**: hidden-test pass rate (build tasks) and defect catch rate (review-catch tasks).
- **Point**: one hundredth of a rate in the unit interval; "three points" = 0.03 absolute.
- **Pipeline executor**: the harness component that runs Loa's phases as separate sessions inside a sandbox repository.
- **Took-effect check**: the mechanical reading of a run's artefacts that proves the arm's toggle changed what it claims to change.
- **Cap failure**: a run aborted at the per-run cap; counted as a failed run.

### E. Decisions taken on the operator's behalf (unattended planning)
Recorded as `DEC` rows DEC-0355 … DEC-0378, each `proposed` with `proposed_by: agent` and `decided_by` null until `/decisions confirm`. The operator's instruction authorised the planning and the shipping, not the attribution of each row.

| # | Decision | Alternatives | Why |
|---|----------|--------------|-----|
| D1 | Component under test is `v2.0.0-rc.5` at tag commit `4d69c3c4`, not rc.3 [ASSUMPTION decision] (DEC-0355); amended by F2: the arms pin the Sprint 258 commit (rc.5 plus the mount fix) | pin main `9e53d5d2` | the published rc is the tag commit; same `.claude/` tree |
| D2 | Reuse cycle-129 instruments; cite its four arm verdicts, never re-run [ASSUMPTION decision] (DEC-0356) | re-run under the new suite | about USD 300 of the cap to repeat a day-old measurement |
| D3 | Two executors: single-skill for review-catch, pipeline for build tasks [ASSUMPTION decision] (DEC-0357) | single-skill for every arm | A2, A4, A5, A6 would remove nothing the executor runs |
| D4 | Applicability matrix pre-registered; A8 dropped as component-absent [ASSUMPTION decision] (DEC-0358) | run A8 against a construct | out of scope; no construct in the suite |
| D5 | Task sources: corpus, post-cutoff Loa history, open beads at rc.5 [ASSUMPTION decision] (DEC-0359); amended by F6: fixtures never under the mount paths; bd-yzzb9 replaced | Freeside or Hounfour items | toolchains and secrets in the sandbox |
| D6 | Mechanical grader; the cross-family matcher is an appeal column only [ASSUMPTION decision] (DEC-0360) | a model as primary defect grader | the grading-itself risk |
| D7 | Fairness review by a non-author Opus subagent, `REVIEW.md` per task [ASSUMPTION decision] (DEC-0361) | self-review | the rule exists for the author's blind spots |
| D8 | Host temp-dir sandbox with a toolchain fingerprint; no credentials in an image [ASSUMPTION decision] (DEC-0362); amended by the SDD Flatline run (DEC-0411): phases run in a container with per-run read-only credential copies and no other host mount, the host sandbox being the recorded fallback | image with mounted credentials | credentials are never baked into the image; read-only per-run copies are mounted at run time |
| D9 | Spend caps enforced by scripts; cycle spend = run cost + ledger rows since kickoff [ASSUMPTION decision] (DEC-0363) | count arm runs only | Flatline, dissent and BB are cycle spend |
| D10 | Decision rules = the brief's table pre-registered; three points = 0.03 absolute [ASSUMPTION decision] (DEC-0364) | 3 % relative | the brief writes points |
| D11 | Smoke two tasks × one trial per arm with a mechanical took-effect check [ASSUMPTION decision] (DEC-0365) | trust the declaration | cycle-129 DISS-C-001 leak class |
| D12 | Five sprints 258–262; Opus implementers; Fable gates; ≤ 3 dissent runs per sprint [ASSUMPTION decision] (DEC-0366) | three sprints | runs take a day; analysis waits on them |
| D13 | Floor never pruned; A4 informs the report only [ASSUMPTION decision] (DEC-0367) | let A4 decide the gates | the evaluator keeps the suite honest |
| D14 | #1267 fix: tracked-tree manifest, CI path check, mount-scoped `not-mounted` [ASSUMPTION decision] (DEC-0368) | regenerate only | the mount-layout class remains |
| D15 | Planning skills not loaded via the Skill tool; lead authors on the templates [ASSUMPTION decision] (DEC-0369) | invoke the three skills | KF-043 tool-policy risk on an unattended session |
| D16 | Planning Flatline integrated by judgment under KF-041, never retried [ASSUMPTION decision] (DEC-0370) | retry for the scorer | recurrence 4 is structural |
| D17 | Carry-overs folded into the sprints that need them [ASSUMPTION decision] (DEC-0371) | separate `/bug` sprints | five more rounds for owned changes |
| D18 | Google voice off on every arm; recorded in manifests [ASSUMPTION decision] (DEC-0372) | opt in for the arms | mixed-voice settings invalidate the comparison |
| D19 | Seed = trial index; `seed: null` recorded [ASSUMPTION decision] (DEC-0373) | a seed parameter | none exists on the route |
| D20 | A1 pipeline shape with one fix round per gate [ASSUMPTION decision] (DEC-0374) | unbounded rounds | cap failures would bias A1 against itself |
| D21 | `runs.jsonl` schema with per-phase `effort_effective`, `voices_run`, `degraded` [ASSUMPTION decision] (DEC-0375) | reuse the arms row | no phases, verdict accuracy or hidden-test field |
| D22 | Blind grading by layout: grader never sees the arm label [ASSUMPTION decision] (DEC-0376) | grade in the runner | one variable from the grader |
| D23 | Budget plan with a USD 150 reserve for the re-verification; A7, A5, A6 if room [ASSUMPTION decision] (DEC-0377); amended by F7 (table and cut ladder) and F8 (reserve USD 250, released when no re-run is needed) | every arm at three seeds, no re-run | the exit criterion needs the re-run |
| D24 | Per-run cap fit: A1 smoke median > USD 9 shrinks tasks, never the cap [ASSUMPTION decision] (DEC-0378) | raise the cap | the cap is the operator's number |

### F. Baselines measured at plan time (2026-10-15)

| Measure | Value | Source |
|---|---|---|
| `check-loa.sh` on this checkout | exit 1; 83 Tampered (all `__pycache__`), 0 Missing | run at kickoff |
| Manifest vs tracked tree | 3,387 entries; 1,976 tracked `.claude/` files; 1,411 untracked entries on this checkout (1,058 `skills/bridgebuilder-review` node_modules, 153 `adapters/tests` caches, 79 `adapters/loa_cheval`, 54 `constructs/packs`, 13 `adapters/.run`, 5 `.pytest_cache`); #1267's 1,308 counts paths absent from the tag's tree and 242 build artefacts — different denominators, both stated; AC-1.1 uses the tracked-tree measure [ASSUMPTION decision] (DEC-0406) | `comm` of `jq keys` and `git ls-files`; issue #1267 |
| Version markers | `.loa-version.json` 2.0.0-rc.3; `CLAUDE.loa.md` marker 2.0.0-rc.3; tag has rc.5 | `git diff main v2.0.0-rc.5` |
| `check-prompt-budget.sh` | rc 0 (`CLAUDE.loa.md` 9,189 B of 9,445; protocols 131,444 B WARN over 114,688) | run at kickoff |
| cycle-129 single-skill trial cost | USD 0.89 (pr-01 baseline, 437K tokens, 5 min) to 3.5 (record fixtures) on Opus 5.5 | `evals/results/arms/review-recall/batch-1/baseline/results.jsonl`; NOTES |
| cycle-129 arm verdicts | `no_karpathy` 0.000 [0,0], `no_rule_files` 0.000 [0,0], `no_companion` 0.028 [0,0.083] informational, `no_audit_delta` 0.000 — all no recall loss, 8 fixtures × 3 trials | `a2a/sprint-257/arms-report-*.md` |
| Fixtures available | 18 review (`pr-01`–`pr-18`; 8 planted with 3 defects each, 8 record with 37–143 labels), 5 implement (Python, pytest, hidden expectations) | `evals/fixtures/` |
| Post-cutoff fix commits touching scripts, hooks, adapters or tests | 198 since 2026-07-01 | `git log --since=2026-07-01` |
| Spend since 2026-10-13 in the cost ledger | USD 76.44 over 68 rows (cycle-129); 0 today | `.run/cost-ledger.jsonl` |
| Decision ledger | 354 rows before this cycle; 378 after seeding D1–D24 | `grimoires/loa/decisions.yaml` |
| Toolchain | Docker 26.1.5; codex 0.137.0; claude 2.1.299 (Bedrock route); Python 3.13.5; Node 22.22.2; bats 1.13.0; 8 CPUs, 30 GB RAM, 981 GB free | kickoff probe |

### F2. Budget plan (planning estimates; recalibrated from smoke actuals in `batch-plan.md`)

| Slice | Runs | Unit USD (est.) | USD |
|---|---|---|---|
| Build, A0 (12 tasks × 3) | 36 | 1.5 | 54 |
| Build, A1 | 36 | 7.0 | 252 |
| Build, A2 | 36 | 6.0 | 216 |
| Build, A3 | 36 | 6.5 | 234 |
| Build, A4 | 36 | 3.5 | 126 |
| Review-catch, A0 (4 × 3) | 12 | 2.0 | 24 |
| Review-catch, A1 | 12 | 8.0 | 96 |
| Review-catch, A3 | 12 | 7.0 | 84 |
| Smoke (8 arms × 2 tasks) | 16 | 4.5 | 72 |
| Priority batch + smoke | 232 | | **1,158** |
| Planning Flatline ×3, sprint dissent (≤ 3 × 5 sprints × 2 gates), Bridgebuilder | | | ≈ 60 |
| Reserve (re-verification case 3; released to A7 otherwise) | | | 250 |
| Total committed | | | ≈ 1,468 of 1,500 |
| Cut ladder rung 2 saves (A2, A3 build 3 → 2) | −24 runs | | ≈ −150 |
| Wall-clock at concurrency 3 | 180 build × ~35 min + 36 review × ~20 min | | ≈ 39 h |

### G. Flatline review integration (2026-10-15)
Run: `flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --autonomous`, two voices (codex-headless gpt-5.5, claude-headless), Phase 1 complete 2/2, cross-scoring degraded (`scoring_degraded: true`, `gpt_score null` on every item — the KF-041 shape, recurrence recorded), 18 skeptic blockers, 61 improvements, 0 high-consensus by score. Integrated by judgment (DEC-0370); envelope at `~/.cache/loa/cycle-130/flatline/prd.json` and `grimoires/loa/a2a/flatline/`.

| # | Blocker / item | Integration | DEC |
|---|---|---|---|
| F1 | SKP-010, opus IMP-012: A6 as one session removes the separate evaluator too | A6 keeps one continuous implementer session; gates separate as A1 | DEC-0391 |
| F2 | SKP-007, opus IMP-008: arms pinned to the broken-manifest commit | pin the Sprint 258 commit; `.claude/` delta recorded; integrity green in the sandbox | DEC-0392 |
| F3 | SKP-004/005, gpt IMP-003, opus IMP-001/016: cap rule stated two ways; exclusion bias | one rule: cap failure = failed run; degraded/contaminated excluded pairwise; 25 % guard; labelled sensitivity figure | DEC-0393 |
| F4 | SKP-012/013, opus IMP-004: credential exceptions not enumerated; containment | `env -i` allowlist enumerated; containment limit stated | DEC-0394 |
| F5 | SKP-002 ×2, SKP-009, gpt IMP-010, opus IMP-003/004/015: hidden tests reachable or alterable | grading tree with restored infrastructure; `-I -s`; contamination scan; id-only logs | DEC-0395 |
| F6 | SKP-001, opus IMP-003: Loa-history tasks under `.claude/` collide with the mount | fixture path rule; tasks from `tools/`, `evals/`, `tests/`; bd-yzzb9 replaced | DEC-0396 |
| F7 | SKP-003/006, gpt IMP-016, opus IMP-005/020/021: budget arithmetic absent; counts do not fit | budget table F2; cut ladder; in-flight reservation; 39 h estimate | DEC-0397 |
| F8 | SKP-006, opus IMP-007: re-verification unresolvable at one trial | three-case rule; reserve USD 250 | DEC-0398 |
| F9 | SKP-004, opus IMP-009/027, gpt IMP-001: power; four-task bootstrap; corrections | defects as the catch-rate unit; MDE from smoke; no correction, stated; H1 halt-and-report | DEC-0399 |
| F10 | SKP-007, gpt IMP-005, opus IMP-010/026: mixed primaries; A4 on review-catch; KPI count | per-arm applicability of primaries; A4 build-only; 6 of 6 | DEC-0400 |
| F11 | opus IMP-002, gpt IMP-009: refactor has no red state; known-bad undefined | structural assertion; empty / full findings files | DEC-0401 |
| F12 | opus IMP-014: verdict accuracy against the final tree scores the fix | snapshots after IMPLEMENT and FIX; per-gate accuracy | DEC-0402 |
| F13 | opus IMP-012/017/018, gpt IMP-012: A0 contract and budget | same text, tools, env; `--effort high`; summed budget; output contract | DEC-0403 |
| F14 | opus IMP-019/023, gpt IMP-023/024: freeze sequencing; hardening protocol | `suite_version`; one version per batch; H1/A4 fail path | DEC-0404 |
| F15 | opus IMP-029/030, gpt IMP-028: interrupted runs; planner guard; locations | `status: interrupted`; planner refuses; paths pinned; run_ids cited | DEC-0405 |
| F16 | opus IMP-031: 1,308 vs 1,411 | denominators named; AC-1.1 measure | DEC-0406 |
| F17 | gpt IMP-014/015: drift; stratified order | batch drift guard; trial-major seeded shuffle | DEC-0407 |
| F18 | opus IMP-013: A3 vs D2 | A3 is a new measurement | DEC-0408 |
| F19 | gpt IMP-006, opus IMP-023: H1-fail / A4-insensitive path | no pruning; report ships; operator decides | DEC-0409 |
| F20 | gpt IMP-022/026: exit codes; degraded cost | SDD §6 map; degraded cost counts in spend | DEC-0410 |

Accepted without a change: SKP-003 (artefacts can reveal the arm to a reader) — the grader is mechanical and reads no label, so there is no judgment to bias; the claim is reworded as structural blindness. Not adopted: a correction across components (the brief fixes one rule per component); re-running the four cycle-129 single-skill arms (D2).

> Sources: NOTES.md § Session Continuity 2026-10-15; `grimoires/loa/decisions.yaml` DEC-0355 … DEC-0378; kickoff probes recorded in NOTES
