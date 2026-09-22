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
  # ICM Layer-2 advisory manifest; a missing path WARNs, never fails.
  - path: grimoires/loa/known-failures.md
    why: Context-Intake Discipline — read first (prior dead-ends)
  - path: CLAUDE.md
    why: process compliance + Karpathy principles
---

<input_guardrails>
<!-- @skill-include: start input_guardrails | hash:f47cf733 | DO NOT EDIT — generated from .claude/data/skill-includes/input_guardrails.md -->
## Pre-Execution Guardrails (mechanized)

Skip this section entirely when `.loa.config.yaml` has `guardrails.input.enabled: false` or env
`LOA_GUARDRAILS_ENABLED=false`.

Otherwise: write the user's invocation prompt/args to a temp file (Write tool), then run
`.claude/scripts/guardrails-orchestrator.sh --skill implementing-tasks --mode ${LOA_RUN_MODE:-interactive} --file <temp-file>`

| Outcome | Action |
|---------|--------|
| JSON `action: "BLOCK"` | HALT; report the script's `reason` to the user |
| JSON `action: "PROCEED"` or `"WARN"` | Continue (logging is handled by the script) |
| Script missing, non-zero exit, or unparseable output | Continue — fail-open, preserving the prior semantics |

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
Implement sprint tasks from `grimoires/loa/sprint.md` with production-grade code and tests, report at `grimoires/loa/a2a/sprint-N/reviewer.md`, and address feedback until the senior lead and security auditor approve.
</objective>

<zone_constraints>
## Zone Constraints

Three-Zone Model per CLAUDE.loa.md: `.claude/` system = never edit (use `.claude/overrides/` or `.loa.config.yaml`); `grimoires/loa/`, `.beads/` state = read/write; this skill's app zone (`src/`, `lib/`, `app/`) = **Read/Write**.
</zone_constraints>

<cli_tool_permissions>
## CLI Tool Usage

Run read-only local commands (`git status/log/diff/branch/show`; `gh issue/pr list/view`, `pr checks`; `npm`/`bun`/`cargo` test/lint/typecheck/build-check) without asking. Ask first for network writes (`git push`, `gh pr/issue create`), deployments, package mutations (`npm install`, `cargo add`), cloud CLIs (`aws`, `gcloud`, `az`), and destructive commands (`rm`, `git reset`, `git checkout -- .`). Use `--json` output and filter fields to avoid printing secrets; never pipe CLI output to files without confirmation; if an authenticated command fails, report the error rather than retrying or prompting for credentials. Full per-tool table: see `resources/CLI-TOOL-POLICY.md`.
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
**Success** = every acceptance criterion met, tests pass, report written.

The report MUST include, in order: Executive Summary; **AC Verification**; Tasks Completed; Technical Highlights; Testing Summary; Known Limitations; Verification Steps; Feedback Addressed (iterations only). Template: `resources/templates/implementation-report.md`.

### AC Verification Gate

Resolve `$SPRINT_FILE` to the plan that owns the current sprint's acceptance criteria: `grimoires/loa/sprint.md` normally, or the bug-cycle micro-sprint (`grimoires/loa/a2a/bug-<id>/sprint.md`) for a `/bug` run — never substitute the repo-level plan for a bug micro-sprint. Every acceptance criterion from that plan appears verbatim in the report's `## AC Verification` section with a status (`✓ Met` / `✗ Not met` / `⚠ Partial` / `⏸ [ACCEPTED-DEFERRED]`) and, for `Met`, file:line evidence. `Partial` needs a scope-split to a follow-up task; `Deferred` needs a matching `grimoires/loa/NOTES.md` Decision Log entry — neither may be silent.

**MUST**, immediately before writing a `COMPLETED` marker: run
`.claude/scripts/validate-ac-verification.sh --report grimoires/loa/a2a/sprint-N/reviewer.md --sprint "$SPRINT_FILE" --sprint-id sprint-N`
(`--sprint-id` scopes a multi-sprint plan; omit it for a single-sprint plan). Exit 0 proceeds; exit 1 means fix the reported rows and re-run; exit 2 is a validator failure — fix the report/sprint path and re-run. If the script is missing, fall back to the manual walk above.

## Evidence
Tests assert specifics ("returns 200, response includes `user.id`"), evidence is file:line (`src/auth/middleware.ts:42-67`), reproduction is the exact command (`npm test -- --coverage --watch=false`). Cite sprint task IDs and SDD sections for architectural decisions; quote feedback items verbatim when addressing them.

Before handoff, run the fast checks CI runs: linter, tests and, when the project configures them, the formatter in check mode (`prettier --check`, `ruff format --check`, `cargo fmt --check`) and the type checker (`tsc --noEmit`, `mypy`, `go vet`). A format or type failure is a failing test.
</kernel_framework>

<grounding_requirements>
Before implementing, in order:
1. `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md`, if present: `CHANGES_REQUIRED` means fix every CRITICAL/HIGH issue (MEDIUM/LOW if feasible) and record each issue, fix and verification in a "Security Audit Feedback Addressed" report section; `APPROVED - LET'S FUCKING GO`, or no file, means proceed.
2. `grimoires/loa/a2a/sprint-N/engineer-feedback.md`, if present: anything other than `All good` means address every item in a "Feedback Addressed" report section.
3. `grimoires/loa/a2a/integration-context.md`, if present (context links, documentation locations, commit formats, MCP tools).
4. `grimoires/loa/sprint.md` (acceptance criteria), `grimoires/loa/sdd.md` (architecture), `grimoires/loa/prd.md` (business requirements). Quote requirements when implementing: `> From sprint.md: Task 1.2 requires...`
5. If `.claude/scripts/qmd-context-query.sh` exists and `qmd_context.enabled` is not `false` in `.loa.config.yaml`, run it with the task description and target file names (`--scope grimoires --budget 2000 --format text`) as advisory context — the sprint plan's acceptance criteria remain the source of truth. Missing, disabled, or empty output: proceed without it.
</grounding_requirements>

<karpathy_goal_driven_gate>
## Goal-Driven Gate

Before Phase -2 runs, check `grimoires/loa/sprint.md` for a non-empty "Success criteria" / "Acceptance criteria" / "Verification" section (case-insensitive heading match — a heading with no body fails the check). Config: `yq eval '.karpathy_principles.require_success_criteria // true' .loa.config.yaml`.

Section present → proceed to Phase -2. Absent with config `false` → proceed and log `verdict: skipped_by_config` to `grimoires/loa/a2a/trajectory/karpathy-{date}.jsonl`. Absent with config `true` (default) → **AskUserQuestion** before any tool call, offering: provide criteria now (append a "Success Criteria" section to sprint.md, then proceed), skip with a one-line rationale (log and proceed), or abort (no tool calls; re-invoke after updating sprint.md).

Every gate decision logs one event to the trajectory file above (`verdict`: `passed` / `skipped_by_config` / `skipped_by_operator` / `aborted`), per the schema at `.claude/data/trajectory-schemas/karpathy-check.payload.schema.json`.
</karpathy_goal_driven_gate>

<workflow>
## Phase -2: Beads-First Integration

### Task Tracking: Beads vs TaskCreate

Use `br` (beads_rust) exclusively for sprint task lifecycle — `br update <id> --status in_progress`, `br close <id>`, `br list`. Claude's `TaskCreate`/`TaskUpdate` are for session-level progress display only; tasks tracked only there are invisible to cross-session recovery, `/run-resume`, and beads health checks. If beads is unavailable, fall back to markdown tracking in NOTES.md.

```bash
health=$(.claude/scripts/beads/beads-health.sh --quick --json)
status=$(echo "$health" | jq -r '.status')
```

`HEALTHY` → import state (`br sync --import-only`; `update-beads-state.sh --sync-import`) and proceed. `DEGRADED` → warn, import, proceed. `NOT_INSTALLED`/`NOT_INITIALIZED` → check opt-out (`update-beads-state.sh --opt-out-check`); without one, warn (`cargo install beads_rust && br init` to add it) and fall back to markdown. `MIGRATION_NEEDED`/`UNHEALTHY` → warn, fall back to markdown. Record the outcome: `.claude/scripts/beads/update-beads-state.sh --health "$status"`.

Run the full lifecycle per task yourself (the user only runs `/implement sprint-N`): health check → `br sync --import-only` → `br ready` → `br update <id> --status in_progress` → implement → `br close <id>` → `br sync --flush-only` at session end. Log discovered issues as they surface — this adds a `discovered-during:<parent-id>` label for traceability:

```bash
.claude/scripts/beads/log-discovered-issue.sh "$CURRENT_TASK_ID" "Description of discovered issue" bug 2
```

Spec: `.claude/protocols/beads-preflight.md`; command reference: `resources/REFERENCE.md` §Beads Workflow.

## Phase -1: Context Assessment and Parallel Task Splitting

`wc -l grimoires/loa/prd.md grimoires/loa/sdd.md grimoires/loa/sprint.md grimoires/loa/a2a/*.md 2>/dev/null`: under 3,000 lines is SMALL (sequential); 3,000–8,000 MEDIUM (parallel when 3+ independent tasks); over 8,000 LARGE (split). MEDIUM/LARGE: see `resources/REFERENCE.md` §Parallel Implementation Guidelines.

## Phase 0: Feedback and Context Check

Work through `<grounding_requirements>` above before any new work.

## Phase 1: Implementation

Study the existing architecture, patterns, conventions and test patterns first. Then, per task in the beads loop: implement to spec following those patterns (Karpathy principles govern style), with tests for the happy path, error conditions and edge cases — the runnable-check floor from CLAUDE.loa.md applies. Write the report per Verification above.

## Phase 2: Feedback Integration Loop

When a feedback file arrives, read it fully, address every item (ask when an item's meaning is unclear; in an unattended run record the interpretation in NOTES.md and proceed), and regenerate the report with a "Feedback Addressed" section that also states interpretations and tradeoffs for the reviewer.
</workflow>

<checklists>
Checklists (Pre-Implementation, Code Quality, Testing, Documentation, Versioning), the SemVer bump table, and the Task Plan Template live in `resources/REFERENCE.md`. A complex task (3+ files, an architectural decision, an unclear path, several acceptance criteria, or security-sensitive work) gets a plan first at `grimoires/loa/a2a/sprint-N/task-{N}-plan.md`, checked against the SDD (human approval if high-risk); simple tasks skip it.

**Red flags**: no tests for new code, hardcoded secrets, skipped error handling, ignored existing patterns.
</checklists>

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

Removed from rule text: AC Verification Gate (cycle-057, #475); fast-gate parity (#1086); goal-driven gate (#961); scout tiering (cycle-119).
