---
name: implement
description: "Execute sprint tasks with production-quality code and tests"
role: implementation
effort: xhigh
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: true
  web_access: true
  user_interaction: true
  agent_spawn: true
  task_management: true
cost-profile: heavy
parallel_threshold: 3000
timeout_minutes: 120
zones:
  system:
    path: .claude
    permission: none
  state:
    paths: [grimoires/loa, .beads]
    permission: read-write
  app:
    paths: [src, lib, app]
    permission: read
inputs:
  # ICM Layer-2 advisory manifest (glass-box: what knowledge this skill ingests
  # first). Advisory only — a missing path WARNs (drift signal), never fails.
  - path: grimoires/loa/known-failures.md
    why: Context-Intake Discipline — read first (prior dead-ends)
  - path: CLAUDE.md
    why: process compliance + Karpathy principles
---

<input_guardrails>
<!-- @skill-include: start input_guardrails | hash:f3482c6c | DO NOT EDIT — generated from .claude/data/skill-includes/input_guardrails.md -->
## Pre-Execution Guardrails (mechanized — cycle-119)

Skip this section entirely when `.loa.config.yaml` has `guardrails.input.enabled: false` or env
`LOA_GUARDRAILS_ENABLED=false`.

Otherwise: write the user's invocation prompt/args to a temp file (Write tool), then run
`.claude/scripts/guardrails-orchestrator.sh --skill implementing-tasks --mode ${LOA_RUN_MODE:-interactive} --file <temp-file>`

| Outcome | Action |
|---------|--------|
| JSON `action: "BLOCK"` | HALT; report the script's `reason` to the user |
| JSON `action: "PROCEED"` or `"WARN"` | Continue (logging is handled by the script) |
| Script missing, non-zero exit, or unparseable output | Continue — fail-open, preserving pre-cycle-119 semantics |

Never pass prompt text as a bash argv (quote-blindness FP class) — always via `--file`.
<!-- @skill-include: end input_guardrails -->
</input_guardrails>

<prompt_enhancement_prelude>
<!-- @skill-include: start prompt_enhancement_prelude | hash:73faa7b3 | DO NOT EDIT — generated from .claude/data/skill-includes/prompt_enhancement_prelude.md -->
If `.loa.config.yaml` sets `prompt_enhancement.invisible_mode.enabled: true` and this command's
frontmatter does not set `enhance: false`, silently apply the PTCF scoring + template flow from
`.claude/skills/enhancing-prompts/SKILL.md` to the user's request before main logic (log per that
skill; never show enhancement output). On any error, or when disabled: proceed with the original
prompt unchanged.
<!-- @skill-include: end prompt_enhancement_prelude -->
</prompt_enhancement_prelude>

# Sprint Task Implementer

<objective>
Implement sprint tasks from `grimoires/loa/sprint.md` with production-grade code and comprehensive tests. Generate detailed implementation report at `grimoires/loa/a2a/sprint-N/reviewer.md`. Address feedback iteratively until senior lead and security auditor approve.
</objective>

<zone_constraints>
## Zone Constraints

Zones per CLAUDE.loa.md Three-Zone Model (`.claude/` system = never edit — use `.claude/overrides/` or `.loa.config.yaml`; `grimoires/loa/`, `.beads/` state = read/write). This skill's app zone (`src/`, `lib/`, `app/`): **Read/Write**.
</zone_constraints>

<cli_tool_permissions>
## CLI Tool Usage

Run read-only local commands (`git status/log/diff/branch/show`; `gh issue/pr list/view`, `pr checks`; `npm`/`bun`/`cargo` test/lint/typecheck/build-check) without asking. Ask first for network writes (`git push`, `gh pr/issue create`), deployments, package mutations (`npm install`, `cargo add`), any cloud-CLI operation (`aws`, `gcloud`, `az`), and destructive commands (`rm`, `git reset`, `git checkout -- .`). Use `--json` output and filter fields to avoid printing secrets; never pipe CLI output to files without confirmation; if an authenticated command fails, report the error rather than retrying or prompting for credentials. Full per-tool table: see `resources/CLI-TOOL-POLICY.md`.
</cli_tool_permissions>

<integrity_precheck>
<!-- @skill-include: start integrity_precheck | hash:c6d25667 | DO NOT EDIT — generated from .claude/data/skill-includes/integrity_precheck.md -->
## Integrity Pre-Check (MANDATORY)

Before ANY operation, verify System Zone integrity:

1. Check config: `yq eval '.integrity_enforcement' .loa.config.yaml`
2. If `strict` and drift detected -> **HALT** and report
3. If `warn` -> Log warning and proceed with caution
<!-- @skill-include: end integrity_precheck -->
</integrity_precheck>

<factual_grounding>
<!-- @skill-include: start factual_grounding | hash:edec7c58 | DO NOT EDIT — generated from .claude/data/skill-includes/factual_grounding.md -->
## Factual Grounding (MANDATORY)

Before ANY synthesis, planning, or recommendation:

1. **Extract quotes**: Pull word-for-word text from source files
2. **Cite explicitly**: `"[exact quote]" (file.md:L45)`
3. **Flag assumptions**: Prefix ungrounded claims with `[ASSUMPTION]`

**Grounded Example:**
```
The SDD specifies "PostgreSQL 15 with pgvector extension" (sdd.md:L123)
```

**Ungrounded Example:**
```
[ASSUMPTION] The database likely needs connection pooling
```
<!-- @skill-include: end factual_grounding -->
</factual_grounding>

<context_discipline>
<!-- @skill-include: start context_discipline | hash:582badb8 | DO NOT EDIT — generated from .claude/data/skill-includes/context_discipline.md -->
## Context Discipline

Follow `.claude/protocols/tool-result-clearing.md`. Thresholds: single result >2K tokens /
accumulated >5K / full file >3K / session total >15K → extract findings (≤10 files, ≤20 words
each, with file:line) to `grimoires/loa/NOTES.md`, then reason from the synthesis, not raw dumps.
Session start: read NOTES.md "Session Continuity". Session end / pre-compaction: update it
(decisions → Decision Log, discovered issues → Technical Debt).
<!-- @skill-include: end context_discipline -->
</context_discipline>

<trajectory_logging>
<!-- @skill-include: start trajectory_logging | hash:e809010f | DO NOT EDIT — generated from .claude/data/skill-includes/trajectory_logging.md -->
## Trajectory Logging

Log each significant step to `grimoires/loa/a2a/trajectory/{agent}-{date}.jsonl`:

```json
{"timestamp": "...", "agent": "...", "action": "...", "reasoning": "...", "grounding": {...}}
```
<!-- @skill-include: end trajectory_logging -->
</trajectory_logging>

<kernel_framework>
## Task
Implement sprint tasks from `grimoires/loa/sprint.md` with production-grade code and tests. Generate an implementation report at `grimoires/loa/a2a/sprint-N/reviewer.md`. Address feedback iteratively.

## Context
- **Input**: `grimoires/loa/sprint.md` (tasks), `grimoires/loa/prd.md` (requirements), `grimoires/loa/sdd.md` (architecture)
- **Feedback loops**: `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md` (security audit — highest priority), `grimoires/loa/a2a/sprint-N/engineer-feedback.md` (senior lead review)
- **Integration context**: `grimoires/loa/a2a/integration-context.md` (if present) — context preservation, documentation locations, commit formats
- **Desired state**: working, tested implementation plus the report above

## Constraints
<!-- @constraint-generated: start implementing_tasks_constraints | hash:56b77a38f8893cf7 -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
1. DO NOT start new work without checking for audit feedback FIRST (highest priority)
2. DO NOT start new work without checking for engineer feedback SECOND
3. MAY allocate time within a sprint for Vision Registry exploration when a captured vision is relevant to the current work
4. DO NOT assume feedback meaning—ask clarifying questions if unclear
5. DO NOT skip tests—comprehensive test coverage is non-negotiable
6. DO NOT ignore existing codebase patterns—follow established conventions
7. DO NOT skip reading context files—always review PRD, SDD, sprint.md
8. DO link implementations to source discussions if integration context requires
9. DO update relevant documentation if specified in integration context
10. DO format commits per org standards if defined
11. DO follow SemVer for version updates
12. DO walk the YAGNI ladder before writing code — stop at the first rung that holds (need it? → stdlib → native → installed dependency → one line → minimum code); reinventing stdlib/native features is a dominant over-engineering class
<!-- @constraint-generated: end implementing_tasks_constraints -->

## Verification
**Success** = every acceptance criterion met, tests pass, and the report below exists at its expected path.

The report MUST include, in order: Executive Summary; **AC Verification**; Tasks Completed; Technical Highlights; Testing Summary; Known Limitations; Verification Steps; Feedback Addressed (iterations only). Use `resources/templates/implementation-report.md`, which carries the full structure, including the AC Verification block format.

### AC Verification Gate

Resolve `$SPRINT_FILE` to the plan that owns the current sprint's acceptance criteria before running this gate: `grimoires/loa/sprint.md` normally, or the bug-cycle micro-sprint (`grimoires/loa/a2a/bug-<id>/sprint.md`) for a `/bug` run — never substitute the repo-level plan for a bug micro-sprint. Every acceptance criterion from that plan must appear verbatim in the report's `## AC Verification` section, each with a status (`✓ Met` / `✗ Not met` / `⚠ Partial` / `⏸ [ACCEPTED-DEFERRED]`) and, for `Met`, file:line evidence. `Partial` needs a scope-split to a follow-up task; `Deferred` needs a matching `grimoires/loa/NOTES.md` Decision Log entry — neither may be silent.

**MUST**, immediately before writing a `COMPLETED` marker: run
`.claude/scripts/validate-ac-verification.sh --report grimoires/loa/a2a/sprint-N/reviewer.md --sprint "$SPRINT_FILE" --sprint-id sprint-N`
(`--sprint-id` scopes a multi-sprint plan; omit it for a single-sprint plan). Exit 0 proceeds; exit 1 means fix the reported rows and re-run; exit 2 is a validator failure — fix the report/sprint path and re-run. If the script is missing, fall back to the manual walk above.

## Evidence and Reproducibility
Tests assert specifics, not "it works" — e.g. "returns 200, response includes `user.id`". Evidence is file:line, not a directory — e.g. `src/auth/middleware.ts:42-67`, not "updated auth". Reproduce with exact commands, e.g. `npm test -- --coverage --watch=false`. Cite sprint task IDs, SDD sections for architectural decisions, and quote feedback items verbatim when addressing them.

### Pre-Handoff Verification Gate

Before marking a task done, run the same fast checks CI runs, not just a linter and tests. When the project configures them, also run the formatter in check mode (`ruff format --check`, `prettier --check`, `gofmt -l`, `cargo fmt --check`, …) and the type checker (`mypy`, `tsc --noEmit`, `pyright`, `go vet`, …) — these are examples; run whatever the project configures. A formatter that would rewrite files is a red CI run waiting to happen. Treat a format or type failure like a lint/test failure: fix it before handoff.
</kernel_framework>

<uncertainty_protocol>
- If requirements are ambiguous, reference PRD and SDD for clarification
- If feedback is unclear, ASK specific clarifying questions before proceeding
- Say "I need clarification on [X]" when feedback meaning is uncertain
- Document interpretations and reasoning in report for reviewer attention
- Flag technical tradeoffs explicitly for reviewer decision
</uncertainty_protocol>

<karpathy_principles>
Karpathy Principles are injected every session via `CLAUDE.loa.md`. Full protocol:
`.claude/protocols/karpathy-principles.md`.
</karpathy_principles>

<grounding_requirements>
Before implementing, in order:
1. Read `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md` if present. `CHANGES_REQUIRED` means fix every CRITICAL/HIGH issue (MEDIUM/LOW if feasible) and document it in a "Security Audit Feedback Addressed" report section, quoting each issue with its fix and verification steps. `APPROVED - LET'S FUCKING GO`, or no file, means proceed.
2. Read `grimoires/loa/a2a/sprint-N/engineer-feedback.md` if present. Anything other than `All good` means address every item in a "Feedback Addressed" report section. `All good`, or no file, means proceed.
3. Read `grimoires/loa/a2a/integration-context.md` if present, for context-preservation links, documentation locations, commit-message formats, and available MCP tools.
4. Read `grimoires/loa/sprint.md` (acceptance criteria), `grimoires/loa/sdd.md` (architecture), `grimoires/loa/prd.md` (business requirements). Quote requirements when implementing: `> From sprint.md: Task 1.2 requires...`
5. If `.claude/scripts/qmd-context-query.sh` exists and `qmd_context.enabled` is not `false` in `.loa.config.yaml`, run it with a query built from the task description and target file names (`--scope grimoires --budget 2000 --format text`) and use its output as advisory context — the sprint plan's acceptance criteria remain the source of truth. Missing, disabled, or empty output: proceed without it.
</grounding_requirements>

<karpathy_goal_driven_gate>
## Goal-Driven Gate

Before Phase -2 runs, check `grimoires/loa/sprint.md` for a non-empty "Success criteria" / "Acceptance criteria" / "Verification" section (case-insensitive heading match — a heading with no body fails the check). Read `yq eval '.karpathy_principles.require_success_criteria // true' .loa.config.yaml` for the config.

| Section present | Config | Action |
|---|---|---|
| Yes | any | Proceed to Phase -2 |
| No | `false` | Proceed; log `{"phase":"karpathy_check","principle":"goal_driven","verdict":"skipped_by_config",...}` to `grimoires/loa/a2a/trajectory/karpathy-{date}.jsonl` |
| No | `true` (default) | **AskUserQuestion** before any tool call, offering: provide criteria now (append a "Success Criteria" section to sprint.md, then proceed), skip with a one-line rationale (log and proceed), or abort (no tool calls; re-invoke after updating sprint.md) |

Every gate decision logs one event to the trajectory file above (`verdict`: `passed` / `skipped_by_config` / `skipped_by_operator` / `aborted`), per the schema at `.claude/data/trajectory-schemas/karpathy-check.payload.schema.json`.
</karpathy_goal_driven_gate>

<workflow>
For wait-loops, cd hygiene, edit-anchor freshness, and fan-out budgets during this workflow, see `.claude/protocols/agent-ergonomics.md`.

## Phase -2: Beads-First Integration

Beads task tracking is the expected default. Check health and sync before implementation.

**Task tracking**: use `br` (beads_rust) exclusively for sprint task lifecycle — `br update <id> --status in_progress`, `br close <id>`, `br list`. Claude's `TaskCreate`/`TaskUpdate` are for session-level progress display only; tasks tracked only there are invisible to cross-session recovery, `/run-resume`, and beads health checks. If beads is unavailable, fall back to markdown tracking in NOTES.md.

```bash
health=$(.claude/scripts/beads/beads-health.sh --quick --json)
status=$(echo "$health" | jq -r '.status')
```

| Status | Action |
|--------|--------|
| `HEALTHY` | Import state (`br sync --import-only`; `update-beads-state.sh --sync-import`) and proceed |
| `DEGRADED` | Warn, import state, proceed |
| `NOT_INSTALLED`/`NOT_INITIALIZED` | Check opt-out (`update-beads-state.sh --opt-out-check`); without one, warn (`cargo install beads_rust && br init` to add it) and fall back to markdown |
| `MIGRATION_NEEDED`/`UNHEALTHY` | Warn, fall back to markdown |

Record the outcome: `.claude/scripts/beads/update-beads-state.sh --health "$status"`.

Users never run `br` commands manually — the user only runs `/implement sprint-N`; this skill runs the full lifecycle per task, invisibly: health check → `br sync --import-only` → `br ready` → `br update <id> --status in_progress` → implement → `br close <id>` → `br sync --flush-only` at session end. Log discovered issues as they surface:

```bash
.claude/scripts/beads/log-discovered-issue.sh "$CURRENT_TASK_ID" "Description of discovered issue" bug 2
```

This adds a `discovered-during:<parent-id>` label for traceability. See `.claude/protocols/beads-preflight.md` for the full specification.

## Phase -1: Context Assessment and Parallel Task Splitting

Assess context size before starting:

```bash
wc -l grimoires/loa/prd.md grimoires/loa/sdd.md grimoires/loa/sprint.md grimoires/loa/a2a/*.md 2>/dev/null
```

| Size | Lines | Strategy |
|------|-------|----------|
| SMALL | <3,000 | Sequential |
| MEDIUM | 3,000-8,000 | Parallel if 3+ independent tasks |
| LARGE | >8,000 | Split into parallel |

SMALL: proceed to Phase 0. MEDIUM/LARGE: see `<parallel_execution>` below first.

## Phase 0: Feedback and Context Check

Before any new work, work through the checks in `<grounding_requirements>` above.

## Phase 1: Codebase Analysis

Read the codebase context grounding_requirements already named, then look at the existing implementation: architecture and patterns in play, components to integrate with, coding conventions, and existing test patterns to follow.

## Phase 2: Implementation

The beads task loop and health check are in Phase -2 above. For each task: implement to spec, following established project patterns (Karpathy principles govern style and are in context every session). Write tests for the happy path, error conditions, and edge cases, following existing test patterns — the runnable-check floor from CLAUDE.loa.md applies.

## Phase 3: Documentation and Reporting

Create the report at `grimoires/loa/a2a/sprint-N/reviewer.md` from `resources/templates/implementation-report.md` — the section list and the AC Verification gate (including the validator invocation) are under Verification above.

## Phase 4: Feedback Integration Loop

Monitor for feedback files. When one arrives, read it fully, address every item (the uncertainty protocol above governs anything unclear), and regenerate the report with a "Feedback Addressed" section.
</workflow>

<file_creation_safety>
## File Creation Safety

Use the Write tool for source files (`.tsx`/`.ts`/`.jsx`/`.vue`/`.md` and similar) — an unquoted Bash heredoc silently corrupts `${variable}` template-literal syntax. Full decision tree and pre-write checklist: `resources/REFERENCE.md`; canonical rule: `.claude/rules/shell-conventions.md`.
</file_creation_safety>

<parallel_execution>
## Parallel Execution

Split per the thresholds in Phase -1. For Phase 0, dispatch each feedback file (audit, engineer) to its own agent when both exist, and have each return the verdict plus any CRITICAL/HIGH or unaddressed items. For Phase 2, group sprint tasks into dependency batches and dispatch the independent tasks in a batch to parallel agents, each implementing one task with its own tests; after they return, check for conflicts across the changes and run integration tests before writing the unified report.

Evidence-gathering fan-outs (feedback checks, codebase surveys) MAY dispatch `loa-scout` (haiku, read-only — `.claude/agents/loa-scout.md`) instead of a full Explore agent to cut cost on read-and-report work. Anything that writes (Write/Edit) or renders a verdict (feedback classification, AC status, audit/review judgment) MUST stay in-session or on a full agent — never on loa-scout.
</parallel_execution>

<semver_requirements>
See `resources/REFERENCE.md` for the SemVer version format (MAJOR.MINOR.PATCH),
the when-to-bump table, and the version update process.
</semver_requirements>

<task_planning>
## Task Planning

A task is complex when it touches 3+ files/modules, involves an architectural decision, has an unclear implementation path, is estimated at 2+ hours, carries multiple acceptance criteria, or is security-sensitive. For a complex task, write a plan before code — see the Task Plan Template in `resources/REFERENCE.md` (Objective, Approach, Files to Modify, Dependencies, Risks, Verification, Acceptance Criteria) — confirm the approach against the SDD, and get human approval if high-risk. Plans live at `grimoires/loa/a2a/sprint-N/task-{N}-plan.md` and become part of the review artifact. Simple tasks (docs, config, small fixes) can skip planning — use judgment.
</task_planning>

<checklists>
See `resources/REFERENCE.md` for complete checklists: Pre-Implementation, Code Quality, Testing, Documentation, Versioning.

**Red flags**: no tests for new code, hardcoded secrets, skipped error handling, ignored existing patterns.
</checklists>

<beads_workflow>
## Beads Workflow (beads_rust)

The canonical `br` task lifecycle is Phase -2 above and `.claude/protocols/beads-integration.md`. The full session-start / task-lifecycle / semantic-labels / session-end command reference (including `get-ready-work.sh` and the label table) is in `resources/REFERENCE.md`.
</beads_workflow>

<retrospective_postlude>
<!-- @skill-include: start retrospective_postlude | hash:44ec4643 | DO NOT EDIT — generated from .claude/data/skill-includes/retrospective_postlude.md -->
After main skill logic completes, if `.loa.config.yaml` `invisible_retrospective.enabled: true`
(and not disabled for this skill under `invisible_retrospective.skills`), silently run the
learning-signal scan per `.claude/skills/continuous-learning/SKILL.md` and its
`resources/RETROSPECTIVE.md` (quality gates, sanitization, trajectory logging). Recursion guard:
never when the active skill is continuous-learning itself.
<!-- @skill-include: end retrospective_postlude -->
</retrospective_postlude>

## Provenance

Removed from rule text: AC Verification Gate (cycle-057, #475); CI fast-gate parity (#1086); Karpathy goal-driven gate (#961, PR #960); evidence-gathering tiering (cycle-119).
