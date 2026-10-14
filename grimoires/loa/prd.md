# Product Requirements Document: Earned Guards and Open Voices (cycle-129)

**Version:** 1.0
**Date:** 2026-10-14
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (maintainer instruction 2026-10-14: *"proceed end to end as you suggest"*; the interview phases were answered from the brief and the review evidence, no operator questions; every decision taken on the operator's behalf is a `proposed` row in `grimoires/loa/decisions.yaml` (DEC-0125 … DEC-0148) and is listed in Appendix E with its `[ASSUMPTION decision]` tag)
**Brief:** `grimoires/loa/context/cycle-129-brief.md` (copy of `grimoires/loa/a2a/paradigm-review-2026-10/prd-brief.md`)
**Evidence:** `grimoires/loa/a2a/paradigm-review-2026-10/{comparison.md,proposals.md,sources/}` (cite tags below: `S:inv` = `sources/loa-control-surface-inventory.md`, `S:yield` = `sources/loa-gate-yield-2026-09-10.md`, `S:ow` = `sources/loa-open-weight-readiness.md`)
**Branch:** `feature/cycle-129-earned-guards` from `main` `864069f2` (v2.0.0-rc.4)

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

Loa's heavy end has fresh evidence of earning its cost on frontier models and its light end does not. Every cycle-128 sprint failed a first review or audit round with Opus 5.5 implementers and Fable 5.1 gates; the audit caught HIGHs the review approved; Bridgebuilder caught HIGHs after both, with the lowest refuted share of any gate (`S:yield` §1, §3, §7). Against that, about 20 KB of prose loads on every turn and 7.3 KB of it restates checks that already run mechanically; the destructive-command fence produced 105 real blocks in four weeks and no catch; the implement gate never blocks and emitted invalid output from cycle-050 to rc.3; the run-mode circuit breaker's counters were never updated across five changes-required rounds; the team guards are no-ops in the live team session; input guardrails caught nothing in 82 events; all six golden skills sit within one percent of their byte cap (`S:inv` §A–§G, totals). No guard carries an origin or a yield figure, so the framework cannot tell an earned guard from an invented one, and the control run its own eval harness can execute (the same work, gate off) has never been run.

Separately, the cheval substrate can reach a local OpenAI-compatible server by configuration, but every mechanism that makes a voice count is Anthropic or OpenAI shaped, there is no local posture, and the KF-004 repair chain sends findings to Anthropic first on any host with a key (`S:ow` §1–§5).

This cycle makes every guard carry its origin and measured yield (FR-1), adds pre-registered gate-off control arms to the eval harness (FR-2), thins the always-on prose only where an arm shows no recall loss (FR-3), retires or repairs the controls that do not run (FR-4), makes files rather than model-written JSON the authority for run position (FR-5), removes the fence's heredoc false positives under corpus control (FR-6), admits open-weight and local models as advisory voices (FR-7) with an honest local posture (FR-8), gives operators one profile knob that cannot reach the gate floor (FR-9), and tags sprint tasks by kind (FR-10). The floor is untouched: `/review-sprint`, `/audit-sprint`, the LOA-VERDICT one-way rule, the dissent artefact gate, the deny list, fence FR-1.2b, the System-Zone rules and the operator-only commands keep today's behaviour byte for byte.

> Sources: cycle-129-brief.md §Problem, §Goals; paradigm-review-2026-10/proposals.md ADOPT A1–A3, ADAPT B1–B7, REJECT R1–R7; S:yield §0, §1, §7; S:inv §A–§G; S:ow §Bottom line

---

## Problem Statement

### The Problem
Loa has thirty registered hook commands, thirty-two fence pattern ids, a 1,451-line artifact validator and about twenty kilobytes of always-loaded rule text, and not one of these carries a recorded origin or a measured yield (`S:inv` Quantitative totals). The framework therefore cannot distinguish a guard that paid for itself (the separate audit pass caught two cycle-128 HIGHs the review approved, `S:yield` §7) from one that never ran (the implement gate's `{"decision":"ask"}` was invalid PreToolUse output from cycle-050 to rc.3, `S:yield` §5) or one that only produces friction (96 of 105 real fence blocks in four weeks involved a heredoc body or a scratch path, `S:inv` E4). Its eval harness already carries an `ab:` block with a floor commit and a frozen corpus (`evals/suites/review-recall.yaml:23-26`), yet no arm has ever measured a gate against its own absence.

### User Pain Points
- **The maintainer** cannot answer "which of these guards do we still need?" from the record. The hooks-reference registration table lists 18 rows and omits six registered hooks (`S:inv` totals); the only yield data is a block log polluted by 395 bats replay rows out of 500 (`S:inv` E4).
- **The agent** pays about 20 KB of prose per turn (`CLAUDE.loa.md` 10,225 B at a 10,240 B cap, the project `CLAUDE.md` 2,460 B, two unscoped rule files 7,301 B) and 5,168 B more at session start; 7,301 B of it restates FR-1.2b and `validate-skill-capabilities.sh`, which already run mechanically (`S:inv` §A).
- **The run loop** is prose arithmetic the model is asked to execute: `.run/circuit-breaker.json` reads `cycle_count.current: 0`, `history: []` after five CHANGES_REQUIRED rounds; `.run/sprint-plan-state.json` read `state: RUNNING` with a `jacked_out` timestamp after the cycle-128 ship (`S:inv` E3), and at this cycle's start the preflight raised a false "RUNNING, idle 13h" alarm because the jack-out had written `.status` while every reader reads `.state`.
- **Controls that do not run are documented as if they did**: `disallowed-tools` on review skills strips NotebookEdit only while `skill-invariants.md` says Write and Edit are removed; the three team guards exit 0 whenever `LOA_TEAM_MEMBER` is unset, which it is in the live team session; the Karpathy surgical-diff hook warns on every write against a 143,324-line running total that nobody reads (`S:inv` §B, §C).
- **Fence friction**: the sweep that produced the inventory was itself blocked for quoting a force-push string inside a heredoc; five SP-1 blocks were all prose naming a spike merge inside a heredoc body; `hooks-reference.md:199` already documents the false positive (`S:inv` E4).
- **Open weights**: an operator who declares a local server gets `unknown` family, a companion that is never independent, a Bridgebuilder `Unknown provider` refusal, no schema on the chat-completions body, a 128K default context that overfills most local models, a 30 s first-token deadline tuned for hosted APIs, and a repair loop that sends findings to Anthropic Haiku first (`S:ow` §2, §4). The documented Azure example fails at load (`S:ow` §2).

### Current State
Guards: 30 hook commands, 32 fence ids, 62 deny rules, 381 allow rules, no origin field anywhere, no yield report. Prose: about 20 KB per turn; six golden skills at 15,568–16,306 B against a 16,384 B cap. Evals: `review-recall` and `audit-recall` suites with eight corpus PRs of planted defects and an `ab:` block comparing prompt trees, no gate-off arm. Run position: model-written JSON, read by the implement gate, `/loa`, run-resume and the preflight. Fence: 183 corpus rows (100 block, 78 allow, 5 residual), heredoc bodies scanned as commands. Open weights: reachable via `type: openai_compat` with a custom endpoint, counted nowhere, no local posture, no pricing requirement.

### Desired State
Every registered hook, fence pattern id, validator rule and gate has an origin and a 30-day yield figure in a generated, tracked register, and CI refuses a new guard without an origin. The eval harness has pre-registered gate-off arms whose results are the precondition for every prose deletion. Always-on prose is at most 12 KB per turn. Every control that is documented runs, or is documented as telemetry, or is gone. Run position is derived from COMPLETED markers, LOA-VERDICT trailers, the ledger and git, cached in the same JSON shape. The fence scans interpreter-consumed heredocs as today and stops blocking prose. An open-weight or local model can serve as an advisory voice whose findings reach the reviewer and whose presence never changes a verdict; a local posture pins every hop local and says plainly that one local family means DEGRADED audits. One profile knob sets the optional surfaces and cannot reach the floor. Sprint tasks say whether they are mechanical, judgment or operator work.

> Sources: S:inv §A, §B, §C, §G, E3, E4, Quantitative totals, Prose-only rules table; S:yield §5, §7; S:ow §2, §4, §5; `.run/sprint-plan-state.json` and `.run/state.json` at session start (state RUNNING, status JACKED_OUT); `evals/suites/review-recall.yaml:23-26`; `hooks-reference.md:170-189,199`

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measured by |
|----|------|-------------|
| G-1 | Every guard carries an origin and a measured 30-day yield | `grimoires/loa/guards.md` rows = registered hooks + fence ids + validator rules + gates; `tests/unit/guard-origins.bats` green; zero rows with an empty origin |
| G-2 | The control run exists and runs | FR-2 arms produce recall, refuted share and tokens per call on the seeded corpus, three trials each |
| G-3 | Always-on prose drops to at most 12 KB per turn with no recall loss | measured bytes of `CLAUDE.loa.md` + project `CLAUDE.md` + unscoped rules; FR-2 "without rule files" and "without Karpathy block" arms within the regression threshold |
| G-4 | No documented control fails to run | each FR-4 item has a bats case proving it blocks, logs, or is gone; the hooks reference describes exactly what runs |
| G-5 | Run position derives from files | the drift fixture (state RUNNING, files complete) resolves to JACKED_OUT; the breaker counts a changes-required round in a fixture run |
| G-6 | Heredoc false positives removed with the corpus intact | new B-rows allow; every pre-existing D-row still blocks; p95 under 80 ms |
| G-7 | Open-weight and local voices serve as advisory voices with an honest posture | fixture local server completes a dissent as `counted_as: advisory_voice`; verdict quality unchanged; `schema_enforced: true` on the chat body; nothing sent to `tiny` or `claude-headless` under `local_voices` |
| G-8 | One profile knob that cannot reach the floor | the floor-unchanged test passes under `lean`; `/loa` prints the effective profile |
| G-9 | Sprint tasks carry kinds and the release notes report the ratio | validator requires `kind:`; this plan's own sprint.md passes; the release notes carry the script / prose / model-call line |

### Key Performance Indicators (KPIs)

| KPI | Baseline (2026-10-14) | Target |
|-----|------------------------|--------|
| Guards with an origin | 0 of ~90 (none recorded) | 100 % |
| Always-on prose per turn | ~20.0 KB (10,225 + 2,460 + 7,301 B) | ≤ 12 KB |
| Bats-replay rows in yield counts | 395 of 500 block rows | 0 |
| Fence real blocks that were prose or scratch paths (4 weeks) | 96 of 105 | the recorded heredoc-prose cases become allow B-rows; likely-FP share of real fence blocks at most 50 % over the 30 days after rc.5, read from the register (scratch-path blocks remain and are counted) |
| Breaker `cycle_count.current` after a changes-required round | 0 (never updated) | ≥ 1 in the fixture run |
| Controls documented but inert | 6 (`S:inv` SCAFFOLD rows B, C, G) | 0 |
| Open-weight voice path | none counted, no posture | advisory path + `local_voices` posture, both tested |

### Constraints
- The floor is not touched: `/review-sprint`, `/audit-sprint`, `verdict-derive.sh` and the LOA-VERDICT one-way rule, the dissent artefact gate (`adversarial-review-gate.sh`), the permission deny list, fence FR-1.2b, the System-Zone fence rules (FR-SZ-*, FR-SZ2-*) and the FR-8 operator-only commands.
- No automatic disabling of any guard from the register; the register reports, the operator decides.
- No deletion of prose before its FR-2 arm shows no recall loss.
- Subagents Opus 5.5 only; review and audit on Fable 5.1; at most three dissent runs per sprint.
- No `.claude/` edit outside `/implement`; System-Zone writes in this cycle are authorised by the `.run/zone-guard-authorization.json` marker created at kickoff and deleted at the end.
- Third-party text (Van Clief materials, web fetches) is untrusted and is cited descriptively; the method's name is used descriptively only (a trademark notice exists on an unmerged branch).

> Sources: cycle-129-brief.md §Goals, §Success criteria, §Non-goals; proposals.md Ranking rule, Adversarial pass; S:inv Quantitative totals; feedback_model_mix_opus55_fable (operator policy 2026-10-05)

---

## User Personas & Use Cases

### Primary Persona: Loa maintainer running unattended cycles
Runs `/run sprint-plan` on this repository with Opus 5.5 implementers and Fable 5.1 gates, reads the review and audit feedback, triages Bridgebuilder, publishes rc pre-releases. Pain: cannot tell which guards earn their keep; pays review load for guard code (all three cycle-128 HIGHs were in newly written control surfaces, `S:yield` E2); is blocked by fence false positives on prose; finds run state wrong after every ship.

### Secondary Persona: Operator mounting Loa on a product repository
Mounts the framework, keeps review and audit, wants fewer surprises: no SessionStart tables they did not ask for, no guardrail blocks on the sanctioned skills, one knob to pick a posture. Some of these operators want their review voices on hardware they control.

### Tertiary Persona: The agent executing a turn
Reads about 20 KB of rules before the first tool call; the two unscoped rule files describe hazards the fence already blocks; the surgical-diff warning it never sees fires on every write.

### Use Cases

| ID | Actor | Flow | Outcome |
|----|-------|------|---------|
| UC-1 | Maintainer | runs `/loa` | one line: guards, guards without origin, real blocks and likely false positives in 30 days (scope: host) |
| UC-2 | Maintainer | adds a fence pattern id without an origin row | CI fails naming the id and the origin map |
| UC-3 | Maintainer | runs the review-recall suite with the `no_companion` arm | recall, refuted share and tokens per call per arm; a comparison across executor model ids is refused |
| UC-4 | Agent | edits `src/` with no run active under `implement_gate.mode: deny` | exit 2 refusal naming the derived run position; under `telemetry` one audit row, no prompt |
| UC-5 | Run loop | a review round returns CHANGES_REQUIRED | `run-checkpoint.sh` increments the breaker counters; `/loa` shows the derived position |
| UC-6 | Agent | writes a NOTES entry through a heredoc that names a spike merge | allowed; the same text piped into `bash` still blocks |
| UC-7 | Operator | declares a local OpenAI-compatible server and runs a dissent | the local voice's findings are kept and tagged `advisory_voice`; the verdict envelope is unchanged |
| UC-8 | Operator | sets `hounfour.locality: local_voices` with one local family | every hosted hop refused at plan time with a named reason; the audit is DEGRADED and says why |
| UC-9 | Operator | sets `loa.profile: lean` | optional surfaces off, floor unchanged, `/loa` prints the profile |
| UC-10 | Reviewer | reads a sprint plan whose `kind: mechanical` task shipped as skill prose | the spec axis flags it |

> Sources: S:yield E2, §4; S:inv §A, §B, §E; S:ow §2, §5; cycle-129-brief.md §Functional requirements

---

## Functional Requirements

### FR-1: Guard register and yield
**Description:** A generated, tracked `grimoires/loa/guards.md` listing every guard with: class (`harness` / `script` / `prose`), status (`active` / `dormant` for guards armed only by an environment variable / `telemetry`), origin (KF id, issue, review finding, cycle or ADR), knob, floor flag, and the yield snapshot from the last generation: 30-day real blocks, likely false positives, last real catch (day granularity), `scope: host`. **Identity**: one row per unique hook script with its event registrations listed, one per fence pattern id, one per validator rule id (a `# @guard validator:<id>` marker convention inside `validate-artifact.sh`), one per gate from a fixed list in the origin map. The writer is `.claude/scripts/guard-yield.sh`, which enumerates hooks from `.claude/settings.json`, pattern ids from `block-destructive-bash.sh`, validator rule markers from `validate-artifact.sh`, and gates and origins from the tracked map `.claude/data/guard-origins.yaml`, then joins them with `.run/audit.jsonl` and its rotated segments (retention at least the 30-day window), excluding every row whose `cwd` is under the temp directory or contains a bats run directory. **Definitions**: a *likely false positive* is a block whose command matched only inside a heredoc body, or whose `cwd` lies outside the repository root, or whose pattern id is one of the recorded prose classes (`SP-1`, `FR-MERGE-2`, `FR-2-AMBIGUOUS`) with no destructive verb at statement start; a *real catch* is a block that is not a likely false positive; both columns are labelled heuristics. **Privacy**: no command text, `cwd`, hostname, user or model name enters the register; ids match `^[A-Za-z0-9._/-]+$`. The tracked file is structural only (ids, class, status, origin, knob, floor, registrations) so that CI can regenerate and compare it byte for byte; the 30-day host yield is written to untracked `.run/guard-yield.md` and `.run/guard-yield.json` on demand, read by `/loa` and by the sprint reports (D32 amends D26). The hooks-reference registration table is generated from the structural register. Hook commands are parsed against a canonical schema and fence ids are enumerated from marker comments; anything unparseable fails the lint rather than being dropped. `/loa` prints one summary line.
**Acceptance criteria:**
- AC-1.1 `tests/unit/guard-origins.bats` fails when a hook script registered in `.claude/settings.json`, a pattern id present in the fence, or a validator rule marker has no row with a non-empty origin, and passes on the seeded map; `floor: true` rows equal the PRD floor set.
- AC-1.2 `guard-yield.sh` over a fixture audit log containing replay rows (cwd under the temp dir or a bats run dir) and a rotated segment excludes the replays, reads the segment, and classifies the fixture's heredoc, scratch-path and prose-class blocks as likely false positives.
- AC-1.3 The untracked yield files on this host report the 30-day block, likely-false-positive, telemetry and last-catch columns per guard, stamped `scope: host`; neither they nor the tracked register contain command text, cwd, hostname or model name; a hook command outside the canonical schema fails the lint by name.
- AC-1.4 `hooks-reference.md`'s registration table is the generated table and lists every registered hook (the six omitted today appear); `guard-yield.sh --check` exits 0 after generation and 1 after an origin edit, and passes in CI where no audit log exists.
- AC-1.5 `/loa` prints the summary line from `.run/guard-yield.json` (or the regenerate hint); the register never disables anything; `dormant` rows are excluded from the inert-controls KPI.

> Sources: proposals.md A1; S:inv E4, Quantitative totals; cycle-129-brief.md FR-1; `.run/audit.jsonl` key shapes (action/cwd/pattern_id)

### FR-2: Control arms
**Description:** `evals/suites/review-recall.yaml` and `audit-recall.yaml` gain pre-registered arms in their `ab:` block with canonical ids: review `baseline`, `no_companion` (companion voice off), `no_karpathy` (Karpathy block removed), `no_rule_files` (the two always-loaded rule files removed); audit `baseline`, `no_audit_delta` (the "look for what the review did not" instruction removed). The corpus is seeded with the round-1 states of sprints 247 to 254 as commit-pinned manifests; a finding becomes a label only when its fix commit touches the file the finding cites, and every label records `label_source` (review, audit, bridgebuilder); label files carry control-stripped finding titles, severity, category, file and anchor only, pass the no-secrets grader, and are approved by the lead before they are committed. Recall, refuted share and tokens per call are recorded per arm; a comparison across executor model ids is refused. **Pre-registered threshold** ("no recall loss"), written in the `ab:` block: all three trials of both arms completed on the full corpus; mean recall of the arm at least the baseline mean minus `ci.regression_threshold` (0.10) and the minimum trial not below the baseline minimum minus 0.15; refuted share at most 0.10 above the baseline. Anything else, including an incomplete run, is *inconclusive* and permits no deletion. The report also gives a percentile-bootstrap 90 % interval of the recall delta over fixtures and the missed labels per arm; a deletion that relies on an arm requires the lead to read that arm's missed labels and record it. The arm run executes against a detached worktree pinned at the pre-cycle commit (`main` `864069f2`), never the live tree Sprint 2 edits; results record the source commit and `compare.sh` refuses mixed sources; a transport-failed trial is retried once. The arm run is an M1 exit criterion and an M2 entry gate for FR-3 deletions only; unrelated FRs ship regardless. The executor is Fable 5.1, the production gate model, so the arms measure the gate they inform (D33). Estimated cost: 16 fixtures × (4 review + 2 audit arms) × 3 trials = 288 executor runs, run as a detached driver that writes a `STATUS.json` the Sprint 2 gate reads (SDD D-2.3).
**Acceptance criteria:**
- AC-2.1 The suites declare the arms by their canonical ids with the threshold block, and `evals/tests/recall-baseline-freshness.bats` covers them.
- AC-2.2 Eight new fixtures (247–254) each name the implementation commit, the fix commit and a label file; every label satisfies the fix-touches-file rule and carries `label_source`; `SHA256SUMS` covers them; the label files pass the no-secrets grader and contain no raw model output beyond the finding title.
- AC-2.3 `compare.sh` exits non-zero with a named reason when the two arms were captured under different executor model ids.
- AC-2.4 `report.sh --arms` names, per arm, recall, refuted share, tokens per call and the verdict `no recall loss` / `recall loss` / `inconclusive` by the pre-registered threshold; `advisory_on_model_skew` stays on; no gate flips in this cycle.

> Sources: proposals.md A2; S:yield §1, §2 (24 accepted HIGHs in sprint 248); `evals/suites/review-recall.yaml:23-26`; `evals/tasks/review-recall/review-pr-01.yaml`

### FR-3: Prose diet
**Description:** `stash-safety.md` and `skill-invariants.md` become path-scoped (`paths:` frontmatter) so they load only when a shell source or a SKILL.md / agent definition is in play. **Precondition**: the Sprint 1 report carries a crosswalk mapping every hazard named in each rule file to the fence pattern id or lint that mechanises it (with corpus rows), and names the hazards that have no mechanical check (today: the `stash -k` under pre-commit rule and the `fsck` before `gc` recovery advice), which the `no_rule_files` arm then measures. `CLAUDE.loa.md` rows that describe a mechanism shrink to a pointer that names it; prose-only rows gain a mechanism (FR-4) or move to a protocol; the kernel cap is lowered to the post-diet size; the KF session table stays behind its knob (default off downstream). Deletions are classified by evidence (D35): review-affecting prose needs its arm's `no recall loss` verdict and the lead's reading of that arm's missed labels; mechanism-describing rows become pointers; behavioural prose-only rows, which no review-recall arm measures, move to a protocol with a kernel pointer only as `proposed` DEC rows the operator confirms, with the guard register as their instrument. An `inconclusive` arm defers its deletion to a named bead; on the fallback path no row is deleted and the cap is unchanged.
**Acceptance criteria:**
- AC-3.1 Both rule files carry `paths:` frontmatter; the crosswalk is in the Sprint 1 report; `tests/unit/no-history-in-rule-text.bats` and the prompt-budget check stay green.
- AC-3.2 After Sprint 2, always-on prose per turn is at most 12 KB, or the Sprint 2 report states the fallback with the missing or inconclusive arm named; `tools/check-prompt-budget.sh` is green at the lowered `LOA_LIMIT` either way.
- AC-3.3 Every removed or moved kernel row is listed in the Sprint 2 report with the FR-2 arm verdict that cleared it.

> Sources: proposals.md B1; S:inv §A, §G, Prose-only rules table; `tools/check-prompt-budget.sh:11,53`

### FR-4: Retire or repair inert controls
**Description:** (a) `implement_gate.mode` gains `telemetry` (one compliance row to `.run/audit.jsonl`, no prompt) and `deny` (a deny decision when the write is not sanctioned) as opt-ins; **`ask` stays the default** and now logs one compliance row per ask so the register sees the base rate (D31 amends D2); `authoritative` stays a tighten-only claim modifier that combines with any mode; this repository moves to `deny` in the cycle's last commit, after the end-to-end step has validated the derived cache against the live run (D34); the hooks reference describes the hook as a fence only under `deny`. **Sanction**: the derived run position is RUNNING with a fresh `derived_at`, or `.run/implement-active.json` (written by `implementing-tasks` and `bug-triaging` at start with `skill`, `sprint`, `started_at`, valid two hours; both skills run `run-checkpoint.sh derive --write` before their first App-Zone write) is fresh; `LOA_IMPLEMENT_GATE_OVERRIDE=1` allows with one compliance row per write; every sanction path logs its own compliance row. **Unknown position** (cache missing, stale or unparseable) under `deny` falls back to `ask`, never allow. Trust-input writes ask in every mode. (b) `disallowed-tools: Write, Edit, NotebookEdit` on the four pure-review skills (`eval-running`, `flatline-knowledge`, `rtfm-testing`, `validating-construct-manifest`); the lint enforces it; Bash remains available to them and `skill-invariants.md` states that shell-redirection writes are fence territory. (c) The Karpathy surgical-diff hook resets per beads task (keyed on the checkpoint task, else the session id) and writes a per-task summary the review's SURGICAL axis reads by task id; the running total goes. (d) In the example config, input guardrails and danger-level enforcement default off; this repository keeps `guardrails.input.enabled: true` as telemetry and sets `guardrails.danger_level.enforce: false` (amends D15, see D30). (e) The five C-TEAM rows leave `constraints.json` and the kernel; the guidance moves to the agent-teams reference; the hooks stay registered and appear in the register as `dormant` with their arming variable. (f) The circuit-breaker counters (same-issue hash, no-progress, cycle count, timeout) are computed by `run-checkpoint.sh`: `record-round` at each verdict, and `derive` recomputes them from the ordered feedback history (`engineer-feedback-r*.md`, `auditor-sprint-feedback-r*.md`) at every checkpoint, so no model turn has to remember the call.
**Acceptance criteria:**
- AC-4.1 `implement-gate.bats` covers the matrix mode × {plain, `authoritative`} × {App-Zone write, trust-input write} × {no sanction, derived RUNNING, fresh marker, stale marker, override} × {cache fresh, stale, missing, unparseable}: `deny` returns a deny decision only for an unsanctioned App-Zone write with a fresh cache and falls back to `ask` on an unknown position; `telemetry` writes one row and prints nothing; `ask` keeps today's output and writes one row; a trust-input write asks in every cell; a stale marker does not sanction; the override logs; an unset key behaves as `ask`.
- AC-4.2 `skill-capabilities.bats`: a pure-review skill without the `disallowed-tools` line fails the lint; the four skills carry it; `skill-invariants.md` names the Bash gap.
- AC-4.3 The surgical-diff hook resets its counter when the checkpoint task changes, keys on the session id when no task is active, writes `.run/karpathy-surgical-summary.json`, and keeps its state directory bounded.
- AC-4.4 The example reads `false` for both guardrail keys; this repository reads `enabled: true`, `enforce: false`; the orchestrator tests pass with the knob on; the migration note exists.
- AC-4.5 `constraints.json` has no C-TEAM rows; the kernel regenerates without the Agent Teams table; the agent-teams reference states the rules and the arming variable; the three hooks are `dormant` in the register.
- AC-4.6 `run-checkpoint.sh record-round --gate review --file <CHANGES_REQUIRED feedback>` increments `cycle_count.current`, sets `same_issue.last_hash` and appends `history`; the trip at threshold writes `state: OPEN` and `HALTED`; `derive` on a fixture a2a directory with two `-r1` feedback files and a zeroed breaker recomputes the counters.

> Sources: proposals.md B2; S:inv §B (implement-gate, disallowed-tools, team guards), §C (surgical-diff), §E (guardrails), §G (breaker), E3; `implement-gate.sh:5-12`; `team-role-guard.sh:12,41`; `run-mode/SKILL.md:131-160`

### FR-5: File-authoritative run position
**Description:** `.run/sprint-plan-state.json` and `.run/circuit-breaker.json` become derived caches. `run-checkpoint.sh derive` recomputes them from `grimoires/loa/a2a/sprint-<N>/COMPLETED`, the LOA-VERDICT trailers of `engineer-feedback.md` and `auditor-sprint-feedback.md`, `ledger.json` sprint status and the latest implementation commit, writing `.state` as the canonical key and `.status` as a mirror. `/loa`, `run-resume` and the implement gate read the derivation. A stale marker is rejected unless its trailer's sprint id and the ledger row agree.
**Acceptance criteria:**
- AC-5.1 A drift fixture (state RUNNING, all sprints COMPLETED with APPROVED trailers and ledger `completed`) derives to JACKED_OUT.
- AC-5.2 A stale `COMPLETED` whose trailer names another sprint does not count.
- AC-5.3 `run-mode` recovery bats pass with the derivation in the read path; the JSON shape is unchanged for existing readers, and each known reader (`golden-path.sh`, `loa-run-state-surface.sh`, `run-preflight.sh` P6, `implement-gate.sh`, `run-resume`, `/loa`) has a fixture case over a derived file.
- AC-5.4 The SDD carries a derivation decision table mapping every input combination (markers, trailer verdicts, ledger status, latest implementation commit, breaker state) to each state value the readers consume (`RUNNING`, `INTERRUPTED`, `HALTED`, `COMPLETE`, `JACKED_OUT`; breaker `CLOSED` / `OPEN`); the bats cases are its rows; `run_mode.file_authoritative: false` restores today's write path.

> Sources: proposals.md B3; S:inv E3; S:yield §5 (stale COMPLETED from cycle-122); `.run/sprint-plan-state.json` at kickoff (`state: RUNNING`, `status: JACKED_OUT`); `golden-path.sh:874`

### FR-6: Fence false positives on heredocs
**Description:** `block-destructive-bash.sh` classifies a heredoc by its consumer and **fails closed**: a consumer on neither list scans in full, as today. **Interpreter-consumed** (scanned as today): the command word or any pipe target is a shell or interpreter (`bash`, `sh`, `zsh`, `dash`, `ksh`, `python*`, `node`, `ruby`, `perl`, `eval`, `source`, `.`, `exec`), a wrapper that runs its argument (`sudo`, `env`, `xargs`, `timeout`, `nohup`, `nice`, `setsid`, `ssh`, `docker exec`, `sh -c`, `bash -c`), command or process substitution feeding any of these, an SQL runner, or any consumer whose output path the same command line executes, sources, or marks executable (`bash x.sh`, `./x`, `source x`, `chmod +x x`). A heredoc written to a path with an executable extension or whose body starts with a shebang is interpreter-consumed regardless of consumer. **Non-executing exact forms** (an allowlist of exact command plus safe-flag patterns with a file or stdout sink): `cat`, `tee`, `printf`, `echo` with a plain file redirect; `gh pr comment -F -`, `gh issue comment -F -`, `gh pr create --body-file -`; `git commit -F -`; `br create` or `br update` reading a description from stdin; `jq` and `yq` without `-i` or `--inplace`; `grep`, `sed -n`, `sort`, `wc`. Their bodies are scanned per segment: each line is split on `;`, `&&`, `||`, `|`; any command or process substitution or variable-derived command word makes the body interpreter-consumed; wrapper prefixes (`sudo`, `command`, `exec`, `env`, `nice`, `time`, a backslash, an absolute path) are stripped before the command word is matched against the destructive verbs. Argument-level checks reject `gh api … --input -`, `jq -i`, `yq -i`, any `-x`/`--exec`/`-c`/`-e` form, `awk`, `sed` with `e`, `make -f -`, and unknown flags. The existing quoted-`cat` scrub becomes a special case. The scratch-path half of the false-positive record is out of scope for this FR and is stated as such. The classifier sits behind `destructive_command_guard.heredoc_classifier` (default on; `false` restores today's scan). Every existing corpus D-row stays; new B-rows cover the recorded prose cases; new D-rows pin every interpreter and wrapper form named above.
**Acceptance criteria:**
- AC-6.1 `tests/fixtures/fence-corpus/run-corpus.sh` green with the new rows; no D-row removed; p95 latency under the 80 ms budget; the knob off reproduces today's results on the whole corpus.
- AC-6.2 The five recorded SP-1 prose blocks and the P2 force-push quote inside a heredoc written to a file are allow rows; D-rows block each of: `bash <<EOF`, `python3 - <<PY`, `psql <<SQL`, `bash -c "$(cat <<EOF …)"`, `eval "$(…)"`, `ssh host bash <<EOF`, `docker exec -i c sh <<EOF`, `sudo bash <<EOF`, `xargs sh -c`, `gh api -X DELETE --input -`, `jq -i`, `yq -i`, a heredoc written to `x.sh` then `bash x.sh` or `chmod +x x.sh && ./x.sh` on the same line, and an unlisted consumer with a destructive body.

> Sources: proposals.md B4; S:inv E4; `hooks-reference.md:199`; `block-destructive-bash.sh:333-415,1166-1172`

### FR-7: Advisory open-weight voices
**Description:** The Azure example loads; the operator recipe documents `openai_compat`, a literal `auth`, `secret_env_allowlist`, declared `context_window`, `streaming_recovery` deadlines and a local `dispatch_group`. **Threat model and endpoint rules**: `hounfour.providers.<p>.allow_insecure_endpoint` is a host string, not a boolean, and must be an IP literal or `localhost` (never resolved, so no DNS rebinding) in a loopback or RFC1918 range; link-local, metadata and public addresses are refused; it admits `http` only to that exact host; for such a provider the adapter ignores proxy environment variables, refuses redirects and enforces the declared endpoint path prefix; every other endpoint keeps the TLS, loopback and private-range refusals of the bash validator, now applied on the cheval Python path too; a public `http` host fails at load. Request size is bounded by the declared `context_window` (a dissent prompt over it refuses the hop with a named reason and records it, never truncates silently) and response size by `max_output_tokens`; MODELINV records destination host, scheme and provider for every call. The chat-completions body carries `response_format: {type: json_schema}` for `structured_json` entries and `schema_enforced` reflects the body sent; `reasoning_content` deltas and `<think>` blocks are stripped before qualification and recorded as `thinking_stripped`. Advisory voices are declared as `flatline_protocol.<gate>.advisory_voices`; their findings live in the same `adversarial-<gate>.json` artifact the reviewer reads, but only under `advisory_voices[].findings` (tagged `voice: advisory`, `counted_as: advisory_voice`, with `duplicate_of` links to matching counted findings), never in the top-level `findings[]`, so the voice counts and the derived verdict are byte-identical with and without them; the review and audit skills read the advisory block explicitly; promotion to a counted voice is unreachable this cycle (no voice arm exists) and the check says so. The Bridgebuilder key map and the health probe derive from trusted configuration only (the base branch's config or repository settings on a pull request, never the head checkout) with a `keyless` option; a head-only keyless or insecure provider is refused by name and unknown providers are still refused; `bridgebuilder.exit_on_degraded` is the rollback key for the exit code. The catalog requires `price_source` and `price_date` on open-weight prices and the dissent budget gate reads catalog prices. The family-and-lineage slice is deferred (no operator need declared); promotion to a counted voice is gated by `hounfour.advisory_promotion.*`, unset by default, and refused by name otherwise.
**Acceptance criteria:**
- AC-7.1 The example config loads with the fixed Azure block and a documented `local` provider block; a loader test refuses an `http` endpoint on a public host and an `allow_insecure_endpoint` naming a public host; the opt-in for one provider leaves another provider's refusals intact on both paths.
- AC-7.2 pytest: the chat body carries `response_format` json_schema for a `structured_json` entry and `schema_enforced` is true only then; `<think>` and `reasoning_content` are stripped before qualification and `thinking_stripped` is recorded; a prompt over the declared `context_window` refuses the hop with a named reason and a MODELINV row.
- AC-7.3 bats (mock mode): `adversarial-review.sh` runs an advisory voice from a fixture; its findings are present under `advisory_voices[].findings` in the same artifact, tagged and linked; the top-level `findings[]`, `voices_planned`, `voices_succeeded` and the `verdict-derive.sh` output are byte-identical with and without the advisory voice; a promotion attempt is refused by name.
- AC-7.4 Bridgebuilder accepts a `keyless` provider from the trusted configuration source, refuses a head-only declaration by name, and still refuses an undeclared provider; the probe uses the configured endpoint and honours the host-string opt-in; a DEGRADED verdict exits 3 unless the rollback key says 0.
- AC-7.5 The budget gate reads the catalog price and logs the fixed-rate fallback; a zero-priced entry estimates zero and is logged; a non-zero open-weight price without `price_source` and `price_date` fails the catalog test; MODELINV rows carry destination host, scheme and provider.

> Sources: proposals.md B5; S:ow §1, §2, §4, §7; `openai_adapter.py:323-341`; `adversarial-review.sh:2305-2345,3427-3445,3927-3929`; `config.ts:135-139,384-388`

### FR-8: Local posture
**Description:** `hounfour.locality: local_voices` governs this hop inventory: the dissent primary and companion, the Flatline voices and scorers, the KF-004 repair chain (pinned to the answering voice; the `tiny` and `claude-headless` fallbacks disabled), the Bridgebuilder voices and the health probe. Every hosted hop in the inventory is refused at plan time with a named reason; `locality` is recorded in MODELINV; config and output state that with one local family every security audit is DEGRADED. The Claude Code session model is exempt and the docs say so: the session remains the platform. `hounfour.locality: hosted` (default) restores today's behaviour.
**Acceptance criteria:**
- AC-8.1 A planning test: no hosted hop is planned under the switch; the refusal names the hop and the reason.
- AC-8.2 A redaction test: the repair chain never leaves the declared providers.
- AC-8.3 MODELINV rows carry `locality: local_voices`; the audit output states the DEGRADED consequence.

> Sources: proposals.md B6; S:ow §5; `.loa.config.yaml.example:1484-1500`

### FR-9: Profile knob
**Description:** `loa.profile: lean | standard | full` sets the defaults of the optional surfaces as a set (KF and decisions surfaces, Karpathy diff warning, success-criteria gate, input guardrails, danger level, invisible retrospective, L6/L7 surfaces; interview pacing is not a profile key because `rounds` is already the default and would not discriminate). `standard` is defined as the post-cycle-129 defaults of the example config, listed explicitly in `profiles.yaml`; the two defaults this cycle changes (guardrails off downstream, `implement_gate.mode: telemetry`) are release-note migration items, not profile effects. Per-key overrides win. The schema exposes no floor key under `profile`. `/loa` prints the effective profile and the explicit overrides.
**Acceptance criteria:**
- AC-9.1 Config-loader bats for each profile; `standard` reproduces today's effective values.
- AC-9.2 The floor-unchanged test: under `lean`, review, audit, verdict-derive, the dissent artefact gate, the deny list, FR-1.2b, the System-Zone rules and the operator-only commands read the same effective configuration as under `standard`.
- AC-9.3 `/loa` prints the effective profile.

> Sources: proposals.md B7; S:inv Optional today vs always-on; `.loa.config.yaml.example` top-level keys (55)

### FR-10: Task kinds
**Description:** Sprint tasks carry `kind: mechanical | judgment | operator` at the end of the task line; `validate-artifact.sh --type sprint` requires it for plans whose `**Date:**` header (YYYY-MM-DD, compared lexically, missing or malformed is a violation for live plans as the Seams gate already rules) is on or after 2026-10-14, and WARNs before; the review's spec axis flags mechanical tasks shipped as prose and operator tasks completed unattended. Release notes report two lines with a stated mapping: the task-kind counts (mechanical / judgment / operator) and the volume ratio (script lines changed / prose bytes changed / model calls); the three kinds and both lines are defined in the framework glossary.
**Acceptance criteria:**
- AC-10.1 Validator bats: a dated plan with an untagged task fails; this cycle's `sprint.md` passes.
- AC-10.2 A review fixture with a `mechanical` task implemented as skill prose yields a MEDIUM.
- AC-10.3 The release-notes report for this cycle carries the ratio line.

> Sources: proposals.md A3, L1; `validate-artifact.sh:879-938` (Seams gate as the pattern); `sprint-template.md:49-65`

---

## Non-Functional Requirements

### Performance
Fence p95 under 80 ms per command on the corpus runner; `guard-yield.sh` completes under 10 s on a 10,000-row audit log; the derivation in `run-checkpoint.sh` completes under 2 s.

### Scalability
The register and the arms are per host; fleet aggregation is a follow-up (D6). The corpus grows by eight fixtures; the harness already runs at concurrency 2.

### Security
Every fence change except FR-6 is tighten-only: FR-4(a) adds a deny and admits the two sanction paths that already exist in substance (a run in progress, an implementation skill at work), each logged; FR-6 is the one loosening, confined to exact non-executing forms, failing closed for anything unlisted, pinned by D-rows for every interpreter and wrapper form, and switchable off; FR-7's `http` opt-in names one loopback or private host per provider and does not weaken the endpoint validator for any other provider or host; the repair chain under FR-8 never leaves the declared providers; label files in FR-2 pass the no-secrets grader; everything surfaced from `.run/audit.jsonl` or model output is control-stripped before it reaches a document, and the register carries no command text, cwd, hostname or model name. **Rollback**: each behaviour change has a key that restores the prior behaviour (`implement_gate.mode: ask`, `destructive_command_guard.heredoc_classifier: false`, `run_mode.file_authoritative: false`, `hounfour.locality: hosted`, `loa.profile: standard`), named in the release notes.

### Reliability
Every state write is atomic (jq to a temp beside the file, then rename, under the existing locks); the derivation is idempotent; a missing audit log yields an empty register with a WARN, never a crash.

### Compliance
No `.claude/` edit outside `/implement`; the zone marker is created at kickoff and deleted at the end; every operator-behalf decision is a `proposed` DEC row; the floor is unchanged and the floor-unchanged test proves it.

> Sources: proposals.md gate-risk columns; `hooks-reference.md:260` (80 ms budget); cycle-129-brief.md §Non-goals

---

## User Experience

### Key User Flows
1. **Reading the register**: `/loa` → one line; `grimoires/loa/guards.md` → one row per guard with origin and yield.
2. **Running a control arm**: `evals/harness/run-eval.sh --suite review-recall --arm no_rule_files` → results under `evals/results/`; `compare.sh` refuses cross-model comparison.
3. **Choosing a posture**: set `loa.profile` once; `/loa` shows what it enabled; override any key.
4. **Adding a local voice**: copy the documented block, declare `context_window`, opt in to loopback for that provider, run a dissent; findings arrive tagged advisory.

### Interaction Patterns
Reporting, never auto-disabling. Refusals name the reason and the fix. Degradation is stated, not hidden.

### Accessibility Requirements
Plain-text tables and one-line summaries; no colour-only signals.

> Sources: proposals.md A1 (`/loa` line), B7 (profile visibility), B6 (honest degradation)

---

## Technical Considerations

### Architecture Notes
Bash scripts with bats tests for the register, the derivation, the gate modes and the fence; Python (cheval) with pytest for the chat schema, thinking-trace stripping and pricing; TypeScript (Bridgebuilder) for the key map and the completion banner; YAML for the origin map, the eval suites and the config schema.

### Integrations
`.claude/settings.json` (hook enumeration), `block-destructive-bash.sh` (pattern ids), `validate-artifact.sh` (rules, kinds), `.run/audit.jsonl` (yield), `evals/` harness, `run-checkpoint.sh`, `adversarial-review.sh`, cheval `openai_adapter.py`, `config.ts`, `check-prompt-budget.sh`, `golden-path.sh`.

### Dependencies
jq, yq v4, bats, Python 3 with the cheval test deps, Node for the Bridgebuilder tests. A fixture OpenAI-compatible server for FR-7 tests (an injected fetch seam, not a real server).

### Technical Constraints
Kernel cap after the diet; fence 80 ms budget; portable bash (no bash-4-only expansions in hooks: the `${rel,,}` fail-open is in the record); no raw `sha256sum`; locale pinned near sort/awk.

> Sources: S:yield §2 (`${rel,,}`); feedback_cross_runtime_parity_traps; S:ow §7 slices

---

## Scope & Prioritization

### In Scope (MVP)
FR-1 … FR-10 as specified, in three sprints; the carry-over defects (Bridgebuilder banner count and DEGRADED exit code; prompt-budget workflow comment; implementing-tasks permission lines; `implement_gate.mode` documentation; hooks-reference table via FR-1) as sprint tasks with red tests where code changes.

### In Scope (Future Iterations)
Fleet block-log ingestion (D6); FR-7 family and lineage (D8); counted open-weight voices after an FR-2 result (D3); the post-merge publication of generated commits to main (bd-b4ji).

### Explicitly Out of Scope
Changes to `/review-sprint`, `/audit-sprint`, the LOA-VERDICT one-way rule, the dissent artefact gate, the deny list, fence FR-1.2b or the System-Zone fence. An open-weight model as the orchestrator. A counted open-weight voice without the FR-2 result. Removal of the fence core, beads or the ledger. A human edit gate on the build path. Any "compatible" claim about the reviewed method. Automatic disabling of any guard.

### Priority Matrix

| FR | Value | Effort | Sprint |
|----|-------|--------|--------|
| FR-1 | High (precondition for every retirement) | M | 1 |
| FR-2 | High (the control run) | M | 1 |
| FR-10 | Medium | S | 1 |
| FR-3 (path-scoping) | Medium | S | 1 |
| FR-4 | High (truthful documentation) | M | 2 |
| FR-5 | High (drift observed twice) | M | 2 |
| FR-6 | Medium (friction) | S–M | 2 |
| FR-9 | Medium | S–M | 2 |
| FR-3 (rest) | Medium | M | 2 |
| FR-7 (recipe, schema, accounting, probe, pricing) | Medium | M | 3 |
| FR-8 | Medium | S | 3 |

> Sources: proposals.md Effort column; cycle-129-brief.md §Shape

---

## Success Criteria

### Launch Criteria
- [ ] Every registered hook and fence pattern id has an origin; `guard-origins.bats` green; CI fails on a new one without it.
- [ ] `guards.md` shows this host's 30-day counts with zero bats-replay rows.
- [ ] FR-2 arms run on the seeded corpus (three trials each) and the report names which prose arms changed recall.
- [ ] Always-on prose ≤ 12 KB per turn with every removal cleared by an FR-2 `no recall loss` verdict, or the fallback stated with the inconclusive arm named; `check-prompt-budget.sh` green at the lowered cap either way.
- [ ] `.run/circuit-breaker.json` shows a non-zero cycle count after a changes-required round in a fixture run; the drift fixture derives to JACKED_OUT.
- [ ] A fixture local server completes a dissent as an advisory voice: findings tagged, verdict quality unchanged, `schema_enforced: true`, nothing sent to `tiny` or `claude-headless` under `local_voices`.
- [ ] `lean`: the floor-unchanged test passes; `/loa` prints the profile.
- [ ] Fence corpus green with the new rows; p95 under 80 ms; no D-row removed.
- [ ] No regression in `implement-gate.bats`, `verdict-derive.bats`, `skill-capabilities.bats`, `adversarial-review-schema-enforced.bats`.
- [ ] This cycle's own PRD, SDD and sprint decisions exist as `proposed` DEC rows (Appendix E).

### Post-Launch Success (30 days)
The register's counts move with real use; at least one guard retirement or repair is proposed from the register rather than from a hunch; no new fence false-positive class recorded in NOTES.

### Long-term Success (90 days)
Fleet counts arrive; a counted open-weight voice exists only if its FR-2 result cleared the maintainer's threshold; `lean` is the documented downstream default if its arms held.

> Sources: cycle-129-brief.md §Success criteria; proposals.md L2 (validator rules age)

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Deterrence is invisible to the block log; a deleted rule mattered | Med | Med | FR-2 arm per deleted text; no deletion without the result; retirements reversible |
| One host, four weeks: counts are local | High | Low | `scope: host` on every row; fleet ingestion deferred and named |
| Guard code generates review load (E2) | High | Med | tighten-only changes; bats per item; dissent capped at three runs |
| FR-6 loosens a fence | Med | Med | corpus-gated; FR-1.2b, SZ rules, deny list untouched; two-step forms fenced at the second command |
| Profiles become the downstream gate-off | Med | High | no floor key under `profile`; floor-unchanged test is a launch criterion |
| Advisory voices are dead weight | Med | Low | S slices only; findings still reach the reviewer; family slice deferred |
| Flatline planning reviews arrive degraded (KF-041) | High | Low | integrate by judgment; upstream issue filed (D10) |
| The derivation disagrees with a live run mid-flight | Low | High | derivation runs at checkpoints; the cache keeps its shape; recovery bats |

### Assumptions
- [ASSUMPTION fact] The audit log's `cwd` field distinguishes bats temp directories from real sessions (395 of 500 block rows carry such a cwd; `S:inv` E4).
- [ASSUMPTION fact] The round-1 implementation commits of sprints 247–254 are reachable in git history and their accepted findings in the record branches `record/cycle-126-a2a`, `record/cycle-127-a2a`, `record/cycle-128-a2a`.
- [ASSUMPTION fact] Claude Code rule frontmatter `paths:` scopes a rule file to the files being read or edited (the shell-conventions and zone rules use it today).

### Dependencies on External Factors
Provider availability for the dissent voices (KF-037, KF-038); CI Shell Tests about 60 minutes per push; the Bridgebuilder voice route (`BRIDGEBUILDER_MODEL=codex-headless`).

> Sources: proposals.md Adversarial pass objections 1–5; S:yield §4; S:inv E2, E4

---

## Timeline & Milestones

| Milestone | Sprint (global) | Content |
|-----------|-----------------|---------|
| M1 Measure | 255 | FR-1 register and lint; FR-2 arms and corpus; FR-10 kinds; FR-3 path-scoping; doc fixes (workflow comment, permission lines) |
| M2 Thin and repair | 256 | FR-4 (a)–(f); FR-5 derivation; FR-6 heredoc rule; FR-9 profile; FR-3 rest and cap |
| M3 Open voices | 257 | FR-7 recipe, schema, advisory accounting, probe and key map, pricing; FR-8 posture; Bridgebuilder banner fix; E2E |
| Ship | — | ICE PR, Bridgebuilder triage, admin merge on green CI, rc.5 pre-release, record branch, archive |

**Ordering gates**: FR-1 (origin map) before the generated hooks table; FR-2 corpus and arms before the arm run; the arm run is the M1 exit criterion and the M2 entry gate for FR-3 deletions only (an inconclusive run defers deletions, not the sprint); FR-5 derivation before FR-4(a) `deny` is enabled in this repository; FR-9 after FR-4(d) so `standard` lists the final defaults; FR-7 schema and advisory accounting before FR-8 locality. Each milestone's artifact list is the corresponding sprint's Deliverables section in `sprint.md`.

> Sources: cycle-129-brief.md §Shape; session-2026-10-12-pocock-skills-review (cycle-128 run recipe); Flatline gpt IMP-001, IMP-014; opus IMP-019

---

## Appendix

### A. Stakeholder Insights
The maintainer's instruction was to proceed end to end as recommended. The recommendation came from the 2026-10-14 paradigm review, which found Van Clief's newest material converging on Loa's Mechanical Floor ("Code does what is mechanical. Dialogue does what is judgment"; "Audits are earned, not invented"; the control-run comparison) while rejecting hand-rolled memory and orchestration layers. Loa takes the measurement discipline and the earned-guard rule; it rejects self-audit, mid-build human gates, folder conventions in place of beads and the ledger, and an open-weight orchestrator (proposals.md R1–R7).

### B. Competitive Analysis
See `grimoires/loa/a2a/paradigm-review-2026-10/comparison.md`: the compared method's durable parts are its verification infrastructure and its "walk test" (a fresh agent operates from files alone); its weak parts are the unexercised open-weight hedge and the underpowered memory-cost study (n = 39).

### C. Bibliography
- `grimoires/loa/a2a/paradigm-review-2026-10/comparison.md`, `proposals.md`, `prd-brief.md`, `sources/*.md` (2026-10-14)
- `grimoires/loa/a2a/skills-review-2026-10/` (cycle-128 precedent)
- `grimoires/loa/known-failures.md` KF-004, KF-033, KF-037, KF-038, KF-041, KF-042
- `docs/architecture/ADR-004-model-generation-floor.md`
- `evals/suites/review-recall.yaml`, `evals/suites/audit-recall.yaml`

### D. Glossary
- **Guard**: a hook, fence pattern id, validator rule or gate that constrains the agent or the pipeline.
- **Origin**: the KF id, issue, review finding or cycle that caused a guard to exist.
- **Yield**: real blocks, likely false positives and last real catch in a window, from the audit log.
- **Control arm**: an eval arm with a gate or prose element switched off, pre-registered in the suite.
- **Floor**: review, audit, verdict-derive, the dissent artefact gate, the deny list, FR-1.2b, the System-Zone rules and the operator-only commands.
- **Advisory voice**: a dissent voice whose findings are kept and tagged and which contributes no verdict-quality envelope.
- **Derived run position**: run state recomputed from COMPLETED markers, LOA-VERDICT trailers, the ledger and git.

### E. Decisions taken on the operator's behalf (unattended planning)
Recorded as `DEC` rows DEC-0125 … DEC-0148, each `proposed` with `proposed_by: agent` and `decided_by` null until `/decisions confirm`. The maintainer's instruction authorised the planning and the shipping, not the attribution of each row.

| # | Decision | Alternatives | Why |
|---|----------|--------------|-----|
| D1 | Codebase grounding reuses the 2026-10-14 paradigm-review evidence files instead of re-running `/ride` on the stale May reality [ASSUMPTION decision] (DEC-0125) | re-run `/ride` | the evidence is ten days fresher than any `/ride` output and cites every surface in scope |
| D2 | `implement_gate.mode` gains `telemetry` (downstream default) and `deny` (this repo); `ask` kept; `authoritative` stays tighten-only [ASSUMPTION decision] (DEC-0126) | deny by default in every mount | a downstream deny refuses ordinary interactive app writes; telemetry feeds the register so the deny can be earned |
| D3 | Advisory-voice promotion threshold is `hounfour.advisory_promotion.*`, unset by default [ASSUMPTION decision] (DEC-0127) | a fixed 0.8 ratio in code | the brief names it a maintainer decision |
| D4 | `lean` is opt-in; `standard` stays the downstream default this cycle [ASSUMPTION decision] (DEC-0128) | lean default now | no FR-2 result yet |
| D5 | Rule path-scoping keys on files: stash-safety for shell sources, skill-invariants for SKILL.md and agent definitions [ASSUMPTION decision] (DEC-0129) | key on any git command | rules frontmatter has no command-text selector; the fence covers commands |
| D6 | Fleet block logs later; the register carries `scope: host` [ASSUMPTION decision] (DEC-0130) | ingest now | no fleet transport for audit rows exists |
| D7 | No hosted open-weight price row; the catalog requires `price_source` and `price_date`; the budget gate reads catalog prices [ASSUMPTION decision] (DEC-0131) | seed OpenRouter or Together rows | prices cannot be verified unattended |
| D8 | FR-7 family-and-lineage slice not built; open-weight voices stay `advisory_voice` [ASSUMPTION decision] (DEC-0132) | build it now | no declared need; it is the independence-inflation slice |
| D9 | Carry-over defects fold into sprint tasks with red tests [ASSUMPTION decision] (DEC-0133) | five `/bug` micro-sprints | five more review and audit rounds for one-line fixes |
| D10 | KF-041 goes to an upstream issue; planning Flatline runs accepted degraded [ASSUMPTION decision] (DEC-0134) | retry until scoring succeeds | recurrence 3 is structural by the ledger's rule |
| D11 | Three sprints 255–257; Opus 5.5 implementers; Fable 5.1 gates; three dissent runs per sprint at most [ASSUMPTION decision] (DEC-0135) | two sprints | the FR-2 arms must precede the FR-3 deletions |
| D12 | `guards.md` generated by `guard-yield.sh` from registrations, fence ids, validator rules and a tracked origin map; CI fails on a guard without origin [ASSUMPTION decision] (DEC-0136) | a hand table | the hand table omits six hooks today |
| D13 | FR-2 corpus seeded from the round-1 states of sprints 247–254 as commit-pinned manifests with accepted findings as labels [ASSUMPTION decision] (DEC-0137) | synthetic planted defects | the record measures what the gates found |
| D14 | FR-5 derivation keeps the JSON shape: `.state` canonical, `.status` mirrored [ASSUMPTION decision] (DEC-0138) | a new schema | every reader would change at once |
| D15 | Input guardrails and danger-level enforcement default off in the example and this repo [ASSUMPTION decision] (DEC-0139) | keep on | 82 events, zero catches, seven blocks on the sanctioned skills |
| D16 | The five C-TEAM rows leave `constraints.json` and the kernel; hooks stay registered [ASSUMPTION decision] (DEC-0140) | export `LOA_TEAM_MEMBER` from the spawn path | no harness surface runs on teammate spawn |
| D17 | Karpathy surgical-diff hook resets per task and writes a summary the review reads [ASSUMPTION decision] (DEC-0141) | remove the hook | the review axis lacks exactly this number |
| D18 | `disallowed-tools` strips Write, Edit, NotebookEdit from the four pure-review skills [ASSUMPTION decision] (DEC-0142) | correct the doc only | the barrier is cheap to build |
| D19 | `loa.profile` offers `lean`, `standard`, `full`; no floor key under `profile`; per-key overrides win [ASSUMPTION decision] (DEC-0143) | two profiles | `full` is the framework-development posture |
| D20 | `kind:` required on sprint tasks for plans dated from 2026-10-14; this plan carries the tags [ASSUMPTION decision] (DEC-0144) | a later date | the rule binds the plan that introduces it |
| D21 | FR-6: interpreter-consumed heredocs scan as today; file- or tool-bound heredocs scan for destructive tokens at line start only; every D-row stays [ASSUMPTION decision] (DEC-0145) | skip heredoc bodies | `python3 - <<PY` executes |
| D22 | FR-8 is `hounfour.locality: local_voices`; the session remains the platform [ASSUMPTION decision] (DEC-0146) | `locality: local` | overstates the posture |
| D23 | No rule text or kernel row deleted before its FR-2 arm result; Sprint 1 only path-scopes; cap lowered in Sprint 2 [ASSUMPTION decision] (DEC-0147) | cut now | no measurement yet |
| D24 | bd-cq90 and bd-b4ji fold into the plan commit; bd-b4ji's structural fix stays an open bead [ASSUMPTION decision] (DEC-0148) | change the orchestrator this cycle | out of scope during an rc soak |
| D25 | FR-6 fails closed: an unlisted heredoc consumer scans in full; a body written to a file the same line executes is interpreter-consumed; exact-form non-executing allowlist; scratch paths out of scope [ASSUMPTION decision] (DEC-0156) | two open lists with a permissive default | Flatline SKP-001 and SKP-004 named the write-then-execute form and the unlisted-consumer gap |
| D26 | The tracked register carries origins and the last yield snapshot; `--check` compares structure and origins only; live yield under `.run`; one row per hook script; `dormant` status [ASSUMPTION decision] (DEC-0157) | track the full yield and fail CI on drift | every host would produce a different file (opus IMP-008, IMP-012, IMP-023; gpt IMP-004) |
| D27 | A rollback knob per risky change, named in the release notes [ASSUMPTION decision] (DEC-0158) | revert by commit | a downstream mount cannot revert a framework commit (gpt IMP-006) |
| D28 | The insecure-endpoint opt-in is a host string admitting only loopback or RFC1918; TLS elsewhere; destinations audited; over-window prompts refuse the hop [ASSUMPTION decision] (DEC-0159) | a boolean opt-in per provider | admits any mistyped host (SKP-005; opus IMP-016, IMP-017) |
| D29 | App-Zone writes are sanctioned by derived RUNNING or a fresh marker the implementing skills write; an audited env override exists [ASSUMPTION decision] (DEC-0160) | derived RUNNING as the only sanction | an interactive `/bug` would be refused in every mount that sets `deny` (opus IMP-010) |
| D30 | Guardrails stay enabled in this repository as telemetry with enforcement off; the example defaults both off; amends D15 [ASSUMPTION decision] (DEC-0161) | off everywhere | loses the one data source that could show a catch (opus IMP-011, IMP-025) |
| D31 | `implement_gate.mode` keeps `ask` as the default; `telemetry` and `deny` are opt-ins; asks are logged; an unknown position under `deny` falls back to `ask`; the implementing skills checkpoint before their first write; amends D2 [ASSUMPTION decision] (DEC-0163) | `telemetry` as the downstream default | moves every mount to log-and-allow without an operator decision (SDD review SKP-005, SKP-006) |
| D32 | The tracked register is structural only; the 30-day yield lives untracked under `.run`; amends D26 [ASSUMPTION decision] (DEC-0162) | a yield snapshot in the tracked file | a file generated from an untracked host log can never match in CI (SDD review SKP-007) |
| D33 | The FR-2 arm executor is Fable 5.1, the production gate model, so the arms measure the gate they inform; 288 runs [ASSUMPTION decision] (DEC-0164) | an Opus 5.5 executor with the transfer assumption recorded | deletions would rest on a different model's recall (SDD review opus IMP-015) |
| D34 | Harness-affecting changes land dark for this repository during the run; the `deny` flip waits for the cycle-end validation of the derived cache; smoke run after each apply; recovery step documented [ASSUMPTION decision] (DEC-0168) | apply and rely immediately | one bad hook apply stalls the unattended run (sprint review SKP-005) |
| D35 | Deletion evidence is classified per kernel row: review-affecting rows need an arm verdict; mechanism rows become pointers; behavioural prose-only rows move only as proposed DEC rows with the register as instrument [ASSUMPTION decision] (DEC-0169) | one arm licenses every deletion | a review-recall arm cannot license removing an implementer rule (sprint review SKP-002) |
| D36 | Bridgebuilder honours keyless and insecure-endpoint providers only from trusted configuration, never the pull-request head [ASSUMPTION decision] (DEC-0170) | read the merged config from the checkout under review | the head is attacker-controlled on a pull request (sprint review SKP-008) |
| D37 | Arm batches start as early as their inputs exist; Task 2.8 runs last; on the fallback path no row is deleted and the cap is unchanged; amends A1 [ASSUMPTION decision] (DEC-0171) | start at the end of Sprint 1 | guarantees the fallback in an unattended run (sprint review SKP-001) |

### F. Baselines measured at plan time (2026-10-14)

| Measure | Value | Source |
|---|---|---|
| Always-on prose per turn | 10,225 + 2,460 + 7,301 B ≈ 20.0 KB; 5,168 B KF table at session start | `S:inv` totals |
| Golden skills | 96,427 B over six skills, each within 1 % of 16,384 B | `S:inv` §G |
| Audit log | 10,132 rows; 500 `block`, 395 of them bats replays; 5,025 `allow-marker`; 1 `compliance.state_write` | `.run/audit.jsonl` |
| Registered hook commands | 30 (Setup 1, SessionStart 8, PreCompact 1, UserPromptSubmit 2, PreToolUse 11, PostToolUse 4, Stop 2, PermissionRequest 1) | `.claude/settings.json` |
| Fence | 32 pattern ids, 41 block sites, corpus 183 rows (100 D, 78 B, 5 R) | `block-destructive-bash.sh`, `corpus.jsonl` |
| Breaker after cycle-128 | `cycle_count.current: 0`, `history: []`, `state: CLOSED` | `.run/circuit-breaker.json` |
| Run state at kickoff | `state: RUNNING`, `status: JACKED_OUT` in both files (repaired by hand, archived as `*.cycle-128.jacked-out.json`) | `.run/` |
| Decision ledger | 124 `proposed` rows awaiting `/decisions confirm` before this cycle; 148 after seeding | `grimoires/loa/decisions.yaml` |
| Cycle-128 gate record | every sprint failed r1 review or audit; audit caught two HIGHs review approved; BB 17 fixed / 4 refuted | `S:yield` §1 |

### G. Flatline review integration (2026-10-14)
Run `flatline-24474-6736`: two voices (`gpt-5.5` via codex-headless, `claude-headless`), Phase 1 complete, Phase 2 cross-scoring degraded (KF-041 recurrence 4, exit 6); integrated by judgment per D10. **Blockers** (all tertiary skeptic): SKP-001 (write-then-execute heredoc, unlisted consumers, undefined line start) and SKP-004 (side-effecting "non-executing" tools) → FR-6 rewritten fail-closed with the exact-form allowlist, same-line execution rule, line-start definition and the D-row list (D25); SKP-005 (threat model for loopback and keyless providers) → FR-7 host-string opt-in, TLS elsewhere, size bounds, destination audit (D28); SKP-001 gpt (schedule pressure on the 12 KB target) → pre-registered threshold in FR-2, `inconclusive` permits no deletion, Launch Criteria and AC-3.2 accept the stated fallback. **Integrated improvements**: gpt IMP-001 (ordering gates in the Timeline), IMP-002 (threshold), IMP-003 (register identity and schema in FR-1 and SDD §3.1), IMP-004 (privacy rule), IMP-005 and IMP-009 (derivation decision table and reader coverage, AC-5.3, AC-5.4), IMP-006 (rollback knobs, D27), IMP-007 (label sanitisation and approval), IMP-008 (likely-FP definition), IMP-010 (`standard` definition, FR-9), IMP-011 (arm run gates FR-3 only), IMP-012 (advisory findings in the same artifact, AC-7.3), IMP-013 (date rules, FR-10), IMP-014 (artifact lists are the sprint Deliverables); opus IMP-001 (crosswalk precondition, FR-3), IMP-002 (threshold), IMP-003 (`standard`), IMP-004 (`derive` recomputes the breaker from feedback history), IMP-005 (fail-closed default and wrapper forms), IMP-006 (validator rule markers and fixed gate list), IMP-007 (definitions), IMP-008 and IMP-023 (tracked origins, host-local yield, identity per script, D26), IMP-009 (decision table), IMP-010 (sanction marker and override, D29), IMP-011 and IMP-025 (guardrails telemetry in this repo, migration note, D30), IMP-012 (`dormant`), IMP-013 and IMP-014 (scratch paths out of scope; post-ship likely-FP KPI), IMP-015 (two release-note lines with a mapping), IMP-016 and IMP-017 (host-string opt-in, over-window refusal), IMP-018 (hop inventory, FR-8), IMP-019 (M1 exit / M2 entry gate and cost estimate), IMP-020 (label rule and `label_source`), IMP-021 (Bash gap stated), IMP-022 (retention and rotated segments), IMP-024 (line start), IMP-026 (canonical arm ids), IMP-027 (session-id key), IMP-028 (mode matrix in AC-4.1). **Declined**: none. **Narrowed**: opus IMP-013's scratch-path rule is stated out of scope rather than built.

**SDD review (same day, same shape, ten skeptic blockers)** folded back into this PRD where it changed a requirement: `ask` stays the gate default and asks are logged, unknown position falls back to `ask` (D31); the tracked register is structural and the yield lives under `.run` (D32); the arm executor is Fable 5.1 (D33); FR-6 scans allowed consumers per segment with wrapper stripping and treats executable-extension and shebang bodies as interpreter-consumed; FR-7's opt-in is an IP literal or `localhost` with no DNS, redirects refused, proxy env ignored and path prefix enforced, and advisory findings live only in the advisory block; FR-9 drops interview pacing from the profile set. The full integration record is `sdd.md` §11.4.

**Sprint-plan review (same day, eleven skeptic blockers)** folded back where it changed a requirement: FR-2's arm run starts in two batches as early as its inputs exist and the Sprint 2 diet runs last (D37); FR-3 deletions are classified by evidence class, and behavioural prose-only rows move only as proposed DEC rows (D35); FR-4's `deny` flip for this repository waits for the cycle-end validation and Sprint 2 lands its hook changes with a smoke run after each apply (D34); FR-7's Bridgebuilder honours keyless and insecure providers only from trusted configuration (D36) and the exit code has a rollback key; FR-6's classifier states its grammar and treats hook, settings, rc, PATH and `.git/hooks` targets as interpreter-class; FR-8 applies the endpoint rules at request time to every local hop. Records: `sdd.md` §11.5 and `sprint.md` Appendix D.

> Sources: `~/.cache/loa/cycle-129/flatline/prd.json` (raw_reviews gpt 14 items, opus 28 items, 4 blockers); proposals.md ADOPT/ADAPT/LEARN/REJECT and Adversarial pass; prd-brief.md §Open questions; decisions.yaml DEC-0125 … DEC-0161; NOTES.md Decision Log 2026-10-13 (precedent for Appendix E)

---

*Generated by PRD Architect Agent*
