---
name: implement
description: "Execute sprint tasks with production-quality code and tests"
role: implementation
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
</input_guardrails>

<prompt_enhancement_prelude>
If `.loa.config.yaml` sets `prompt_enhancement.invisible_mode.enabled: true` and this command's
frontmatter does not set `enhance: false`, silently apply the PTCF scoring + template flow from
`.claude/skills/enhancing-prompts/SKILL.md` to the user's request before main logic (log per that
skill; never show enhancement output). On any error, or when disabled: proceed with the original
prompt unchanged.
</prompt_enhancement_prelude>

# Sprint Task Implementer

<objective>
Implement sprint tasks from `grimoires/loa/sprint.md` with production-grade code and comprehensive tests. Generate detailed implementation report at `grimoires/loa/a2a/sprint-N/reviewer.md`. Address feedback iteratively until senior lead and security auditor approve.
</objective>

<zone_constraints>
## Zone Constraints

This skill operates under **Managed Scaffolding**:

| Zone | Permission | Notes |
|------|------------|-------|
| `.claude/` | NONE | System zone - never suggest edits |
| `grimoires/loa/`, `.beads/` | Read/Write | State zone - project memory |
| `src/`, `lib/`, `app/` | Read/Write | App zone - implementation target |

**NEVER** suggest modifications to `.claude/`. Direct users to `.claude/overrides/` or `.loa.config.yaml`.
</zone_constraints>

<cli_tool_permissions>
## CLI Tool Usage

Agents SHOULD proactively run CLI tools from the approved allowlist without asking:

### Approved Read-Only Allowlist

| Tool | Allowed Commands | Notes |
|------|-----------------|-------|
| `git` | `status`, `log`, `diff`, `branch`, `show` | Local only, no network |
| `gh` | `issue list`, `issue view`, `pr list`, `pr view`, `pr checks` | Use `--json` + field filtering to avoid leaking secrets from PR bodies |
| `npm`/`bun` | `test`, `run lint`, `run typecheck`, `run format` | Build/check + format-check commands (#1086) |
| `cargo` | `check`, `test`, `clippy` | Build/check commands |

### Require Confirmation

| Operation Type | Examples |
|---------------|----------|
| Network writes | `git push`, `gh pr create`, `gh issue create` |
| Deployments | `railway deploy`, `vercel deploy` |
| Package mutations | `npm install`, `cargo add` |
| Cloud CLIs | `aws`, `gcloud`, `az` (any operation) |
| Destructive | `rm`, `git reset`, `git checkout -- .` |

### Safety Rules

- Use `--json` output and filter fields when available to avoid printing secrets
- Never pipe CLI output to files without user confirmation
- If a CLI command requires authentication and fails, report the error — do not retry or prompt for credentials
</cli_tool_permissions>

<integrity_precheck>
## Integrity Pre-Check (MANDATORY)

Before ANY operation, verify System Zone integrity:

1. Check config: `yq eval '.integrity_enforcement' .loa.config.yaml`
2. If `strict` and drift detected -> **HALT** and report
3. If `warn` -> Log warning and proceed with caution
</integrity_precheck>

<factual_grounding>
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
</factual_grounding>

<context_discipline>
## Context Discipline

Follow `.claude/protocols/tool-result-clearing.md`. Thresholds: single result >2K tokens /
accumulated >5K / full file >3K / session total >15K → extract findings (≤10 files, ≤20 words
each, with file:line) to `grimoires/loa/NOTES.md`, then reason from the synthesis, not raw dumps.
Session start: read NOTES.md "Session Continuity". Session end / pre-compaction: update it
(decisions → Decision Log, discovered issues → Technical Debt).
</context_discipline>

<trajectory_logging>
## Trajectory Logging

Log each significant step to `grimoires/loa/a2a/trajectory/{agent}-{date}.jsonl`:

```json
{"timestamp": "...", "agent": "...", "action": "...", "reasoning": "...", "grounding": {...}}
```
</trajectory_logging>

<kernel_framework>
## Task (N - Narrow Scope)
Implement sprint tasks from `grimoires/loa/sprint.md` with production-grade code and tests. Generate implementation report at `grimoires/loa/a2a/sprint-N/reviewer.md`. Address feedback iteratively.

## Context (L - Logical Structure)
- **Input**: `grimoires/loa/sprint.md` (tasks), `grimoires/loa/prd.md` (requirements), `grimoires/loa/sdd.md` (architecture)
- **Feedback loops**:
  - `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md` (security audit - HIGHEST PRIORITY)
  - `grimoires/loa/a2a/sprint-N/engineer-feedback.md` (senior lead review)
- **Integration context**: `grimoires/loa/a2a/integration-context.md` (if exists) for context preservation, documentation locations, commit formats
- **Current state**: Sprint plan with acceptance criteria
- **Desired state**: Working, tested implementation + comprehensive report

## Constraints (E - Explicit)
<!-- @constraint-generated: start implementing_tasks_constraints | hash:5b15ea042277c84d -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
1. DO NOT start new work without checking for audit feedback FIRST (highest priority)
2. DO NOT start new work without checking for engineer feedback SECOND
3. DO NOT assume feedback meaning—ask clarifying questions if unclear
4. DO NOT skip tests—comprehensive test coverage is non-negotiable
5. DO NOT ignore existing codebase patterns—follow established conventions
6. DO NOT skip reading context files—always review PRD, SDD, sprint.md
7. DO link implementations to source discussions if integration context requires
8. DO update relevant documentation if specified in integration context
9. DO format commits per org standards if defined
10. DO follow SemVer for version updates
11. DO walk the YAGNI ladder before writing code — stop at the first rung that holds (need it? → stdlib → native → installed dependency → one line → minimum code); reinventing stdlib/native features is a dominant over-engineering class
<!-- @constraint-generated: end implementing_tasks_constraints -->

## Verification (E - Easy to Verify)
**Success** = All acceptance criteria met + comprehensive tests pass + detailed report at expected path

Report MUST include (in this order, enforced):
- Executive Summary
- **AC Verification** (REQUIRED — Issue #475, see structural rule below)
- Tasks Completed (files/lines modified, approach, test coverage)
- Technical Highlights (architecture, performance, security, integrations)
- Testing Summary (test files, scenarios, how to run)
- Known Limitations
- Verification Steps for reviewer
- Feedback Addressed section (if iteration after feedback)

### AC Verification Gate (cycle-057, closes #475)

Before writing the `COMPLETED` marker for a sprint, the implementation report
MUST contain an `## AC Verification` section that walks every acceptance
criterion from `grimoires/loa/sprint.md`. Each AC requires:

1. **Verbatim quote** — copy the AC text from sprint.md, not a paraphrase
2. **Status marker** — one of `✓ Met` / `✗ Not met` / `⚠ Partial` / `⏸ [ACCEPTED-DEFERRED]`
3. **File:line evidence** — for every `Met` claim, a specific path and line
   pointing to the symbol, assertion, or test that proves the AC is honored
4. **Deferral rationale** — `[ACCEPTED-DEFERRED]` requires a matching entry
   in `grimoires/loa/NOTES.md` under the Decision Log

**Skill behavior enforcement**:

- **DO NOT** write a `COMPLETED` marker if any AC has status `✗ Not met` or
  `⚠ Partial` without an accompanying scope-split to a follow-up sprint task
- **DO NOT** silently mark ACs as deferred — always pair with a NOTES.md entry
- **DO NOT** write generic evidence like "implemented in src/batch/" — provide
  specific file:line references with enough context that the reviewer can
  verify the AC is honored without re-reading the whole implementation

This gate catches SDD-implementation drift at implement time rather than
letting it slip through to `/review-sprint`, saving the fix-loop round trip.
Karpathy-aligned: goal-driven verification, not just code written.

See `resources/templates/implementation-report.md` for the structured
`## AC Verification` template.

**MUST**: immediately before writing the `COMPLETED` marker, run
`.claude/scripts/validate-ac-verification.sh --report grimoires/loa/a2a/sprint-N/reviewer.md --sprint grimoires/loa/sprint.md`.
Exit 0 → proceed. Exit 1 → fix the reported AC rows (exact repair text) and
re-run before writing the marker. Exit 2 (usage error / file not found) →
treat as a validator FAILURE, do NOT proceed: fix the report/sprint path and
re-run. Script missing entirely → fall back to the manual walk above
(fail-open, pre-cycle-119 semantics).

## Reproducibility (R - Reproducible Results)
- Write tests with specific assertions: NOT "it works" → "returns 200 status, response includes user.id field"
- Document specific file paths and line numbers: NOT "updated auth" → "src/auth/middleware.ts:42-67"
- Include exact commands to reproduce: NOT "run tests" → "npm test -- --coverage --watch=false"
- Reference specific commits or branches when relevant

## Pre-Handoff Verification Gate — match CI's fast gate (#1086)

Before marking a task done, run the SAME fast checks CI will run — not just a
linter + tests. When the project configures them (detect from `pyproject.toml`,
`package.json` scripts, `.golangci.yml`, `Cargo.toml`, or the `.github/workflows`
files), ALSO run, in addition to the linter and tests:

- the **formatter in check mode** — `ruff format --check`, `prettier --check`,
  `gofmt -l`, `cargo fmt --check`, … (a formatter that would *rewrite* files is
  a red CI waiting to happen), and
- the **type checker** — `mypy`, `tsc --noEmit`, `pyright`, `go vet`, ….

Treat a format-check or type-check failure exactly like a lint/test failure: fix
it before handoff. Goal: **the agent's self-check == CI's fast gate**, so work
marked done doesn't bounce on formatting/types after it's otherwise approved.
Tool-agnostic — the above are examples; run whatever the project configures.
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
Before implementing:
1. Check `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md` FIRST (security audit)
2. Check `grimoires/loa/a2a/sprint-N/engineer-feedback.md` SECOND (senior lead)
3. Check `grimoires/loa/a2a/integration-context.md` for organizational context
4. Read `grimoires/loa/sprint.md` for acceptance criteria
5. Read `grimoires/loa/sdd.md` for technical architecture
6. Read `grimoires/loa/prd.md` for business requirements
7. Quote requirements when implementing: `> From sprint.md: Task 1.2 requires...`
8. If `.claude/scripts/qmd-context-query.sh` exists and `qmd_context.enabled` is not `false` in `.loa.config.yaml`:
   - Build query from current task descriptions and target file names
   - Run: `.claude/scripts/qmd-context-query.sh --query "<task_desc> <file_names>" --scope grimoires --budget 2000 --format text`
   - Include output as advisory context for implementation decisions (sprint plan acceptance criteria remain source of truth)
   - If script missing, disabled, or returns empty: proceed normally (graceful no-op)
</grounding_requirements>

<citation_requirements>
- Reference sprint task IDs when implementing
- Cite SDD sections for architectural decisions
- Include file paths and line numbers in report
- Quote feedback items when addressing them
- Reference test file paths and coverage metrics
</citation_requirements>

<karpathy_goal_driven_gate>
## Goal-Driven Gate (Karpathy principle 4 — applies before any tool call)

Karpathy principle 4 (Goal-Driven Execution) requires testable verification
before implementation. Tasks without written success criteria invite scope
drift and unverifiable completion claims. This gate enforces the principle at
the /implement entry point.

### When the gate fires

Before Phase -2 (Beads-First Integration) runs:

1. Read `grimoires/loa/sprint.md`
2. Check for a section heading matching one of:
   - "Success criteria" (case-insensitive)
   - "Acceptance criteria" (case-insensitive)
   - "Verification" (case-insensitive)
3. Section body MUST be non-empty (a heading with no follow-up content fails the check)
4. Read config: `yq eval '.karpathy_principles.require_success_criteria // true' .loa.config.yaml`

### Gate decision

| Section present | Config `require_success_criteria` | Action |
|---|---|---|
| Yes | any | Proceed to Phase -2 normally |
| No  | `false` | Proceed (operator opted out) — log to trajectory: `{"phase":"karpathy_check","principle":"goal_driven","verdict":"skipped_by_config",...}` |
| No  | `true` (default) | **AskUserQuestion** before any tool call |

### AskUserQuestion shape

When the gate fires, present these 3 options:

| Option | Effect |
|---|---|
| **Provide criteria now** | Operator dictates the criteria; agent appends a "Success Criteria" section to sprint.md, then proceeds |
| **Skip with rationale** | Operator provides a 1-line rationale; agent logs to trajectory and proceeds |
| **Abort** | Exit cleanly (no tool calls); operator can re-invoke /implement after updating sprint.md |

### Trajectory log

Every gate decision emits a single event to `grimoires/loa/a2a/trajectory/karpathy-{date}.jsonl`:

```jsonl
{"phase":"karpathy_check","principle":"goal_driven","verdict":"passed|skipped_by_config|skipped_by_operator|aborted","timestamp":"...","sprint_path":"..."}
```

The schema at `.claude/data/trajectory-schemas/karpathy-check.payload.schema.json`
permits `principle: goal_driven` alongside the `surgical_changes` events from
the K-1 hook.

### Why this is a hard precondition

This gate is intentionally NOT a "remind once and proceed" check — it's a
precondition. Even autonomous /run cycles MUST satisfy it, either via
config-driven opt-out (`require_success_criteria: false` for trusted batch
runs) or via per-invocation skip with rationale. The rationale itself is the
audit trail.

See: #961 K-3 / FR-4, PR #960 (companion: inline Karpathy in CLAUDE.loa.md),
`.claude/protocols/karpathy-principles.md` (full protocol doc).
</karpathy_goal_driven_gate>

<workflow>
For wait-loops, cd hygiene, edit-anchor freshness, and fan-out budgets during this workflow, see `.claude/protocols/agent-ergonomics.md`.

## Phase -2: Beads-First Integration (v1.29.0)

Beads task tracking is the EXPECTED DEFAULT. Check health and sync before implementation.

### Task Tracking: Beads vs TaskCreate

**For sprint task lifecycle**: Use beads (`br`) commands exclusively.
- `br update <task-id> --status in-progress` when starting a task
- `br close <task-id>` when completing a task
- `br list` to see all tasks and their status

**Claude's `TaskCreate`/`TaskUpdate`**: Use ONLY for session-level progress display to the user (e.g., showing a progress checklist). These are NOT a substitute for beads task tracking. Sprint tasks tracked only via TaskCreate are invisible to cross-session recovery, `/run-resume`, and beads health checks.

**If beads is not available**: Fall back to markdown tracking in NOTES.md (existing behavior).

### Run Beads Health Check

```bash
health=$(.claude/scripts/beads/beads-health.sh --quick --json)
status=$(echo "$health" | jq -r '.status')
```

### Status Handling

| Status | Action |
|--------|--------|
| `HEALTHY` | Import state and proceed |
| `DEGRADED` | Warn, import state, proceed |
| `NOT_INSTALLED`/`NOT_INITIALIZED` | Check opt-out, fallback to markdown |
| `MIGRATION_NEEDED`/`UNHEALTHY` | Warn, fallback to markdown |

### If HEALTHY or DEGRADED

1. **Import latest state**:
   ```bash
   br sync --import-only
   .claude/scripts/beads/update-beads-state.sh --sync-import
   ```

2. **Use beads_rust for task lifecycle**:
   - `br ready` - Get next actionable task (JIT retrieval)
   - `br update <task-id> --status in_progress` - Mark task started
   - `br close <task-id>` - Mark task completed
   - Task state persists across context windows

### If NOT_INSTALLED or NOT_INITIALIZED

1. **Check for valid opt-out**:
   ```bash
   opt_out=$(.claude/scripts/beads/update-beads-state.sh --opt-out-check 2>/dev/null || echo "NO_OPT_OUT")
   ```

2. **If no valid opt-out**, log warning:
   ```
   Beads not available. Task tracking via markdown only.
   Consider installing: cargo install beads_rust && br init
   ```

3. **Fallback**: Use markdown-based tracking from sprint.md.

### Update State After Check

```bash
.claude/scripts/beads/update-beads-state.sh --health "$status"
```

### Beads Task Lifecycle

**IMPORTANT**: Users should NOT run br commands manually. This agent handles the entire beads_rust lifecycle internally:

1. On start: Run health check, then `br sync --import-only`, then `br ready` to find first unblocked task
2. Before implementing: Auto-run `br update <task-id> --status in_progress`
3. After completing: Auto-run `br close <task-id>`
4. At session end: Run `br sync --flush-only` then record: `.claude/scripts/beads/update-beads-state.sh --sync-flush`
5. Repeat until sprint complete

### Protocol Reference

See `.claude/protocols/beads-preflight.md` for full specification.

## Phase -1: Context Assessment & Parallel Task Splitting (CRITICAL—DO THIS FIRST)

Assess context size to determine if parallel splitting is needed:

```bash
wc -l grimoires/loa/prd.md grimoires/loa/sdd.md grimoires/loa/sprint.md grimoires/loa/a2a/*.md 2>/dev/null
```

**Thresholds:**
| Size | Lines | Strategy |
|------|-------|----------|
| SMALL | <3,000 | Sequential implementation |
| MEDIUM | 3,000-8,000 | Consider parallel if >3 independent tasks |
| LARGE | >8,000 | MUST split into parallel |

**If MEDIUM/LARGE:** See `<parallel_execution>` section below.

**If SMALL:** Proceed to Phase 0.

## Phase 0: Check Feedback Files and Integration Context (BEFORE NEW WORK)

### Step 1: Security Audit Feedback (HIGHEST PRIORITY)

Check `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md`:

**If exists + "CHANGES_REQUIRED":**
- Sprint FAILED security audit
- MUST address ALL CRITICAL and HIGH priority security issues
- Address MEDIUM and LOW if feasible
- Update report with "Security Audit Feedback Addressed" section
- Quote each audit issue with your fix and verification steps

**If exists + "APPROVED - LET'S FUCKING GO":**
- Sprint passed security audit
- Proceed to check engineer feedback

**If missing:**
- No security audit yet
- Proceed to check engineer feedback

### Step 2: Senior Lead Feedback

Check `grimoires/loa/a2a/sprint-N/engineer-feedback.md`:

**If exists + NOT "All good":**
- Senior lead requested changes
- Address all feedback items systematically
- Update report with "Feedback Addressed" section

**If exists + "All good":**
- Sprint approved by senior lead
- Proceed with new work or wait for security audit

**If missing:**
- First implementation
- Proceed with implementing sprint tasks

### Step 3: Integration Context

Check `grimoires/loa/a2a/integration-context.md`:

**If exists**, read for:
- Context preservation requirements (link to source discussions)
- Documentation locations (where to update status)
- Commit message formats (e.g., "[LIN-123] Description")
- Available MCP tools

## Phase 1: Context Gathering and Planning

1. Review core documentation:
   - `grimoires/loa/sprint.md` - Primary task list and acceptance criteria
   - `grimoires/loa/prd.md` - Product requirements and business context
   - `grimoires/loa/sdd.md` - System design and technical architecture

2. Analyze existing codebase:
   - Understand current architecture and patterns
   - Identify existing components to integrate with
   - Note coding standards and conventions
   - Review existing test patterns

3. Create implementation strategy:
   - Break down tasks into logical order
   - Identify task dependencies
   - Plan test coverage for each component

## Phase 2: Implementation

### Beads Task Loop (if beads_rust installed)

```bash
# 0. Import latest state (session start)
br sync --import-only

# 1. Get next actionable task
TASK=$(br ready --json | jq '.[0]')
TASK_ID=$(echo $TASK | jq -r '.id')

# 2. Mark in progress (automatic - user never sees this)
br update $TASK_ID --status in_progress

# 3. Implement the task...

# 4. Mark complete (automatic - user never sees this)
br close $TASK_ID

# 5. Repeat for next task...

# 6. Flush state before commit (session end)
br sync --flush-only
```

The user only runs `/implement sprint-1`. All br commands are invisible.

### Log Discovered Issues

When bugs or tech debt are discovered during implementation:

```bash
.claude/scripts/beads/log-discovered-issue.sh "$CURRENT_TASK_ID" "Description of discovered issue" bug 2
```

This creates a new issue with semantic label `discovered-during:<parent-id>` for traceability.

### For each task:
1. Implement according to specifications
2. Follow established project patterns
3. Write clean, maintainable, documented code
4. Consider performance, security, scalability
5. Handle edge cases and errors gracefully

**Testing Requirements:**
- Comprehensive unit tests for all new code
- Test both happy paths and error conditions
- Include edge cases and boundary conditions
- Follow existing test patterns
- Ensure tests are readable and maintainable

**Code Quality Standards:**
- Self-documenting with clear names
- Comments for complex logic
- DRY principles
- Consistent formatting
- Future maintainability

## Phase 3: Documentation and Reporting

Create report at `grimoires/loa/a2a/sprint-N/reviewer.md`:

Use template from `resources/templates/implementation-report.md`.

Key sections:
- Executive Summary
- Tasks Completed (with files, approach, tests)
- Technical Highlights
- Testing Summary
- Known Limitations
- Verification Steps

**MUST**, immediately before writing any `COMPLETED` marker: run
`.claude/scripts/validate-ac-verification.sh --report <reviewer.md> --sprint grimoires/loa/sprint.md`
(see AC Verification Gate above for the full contract and fail-open fallback).

## Phase 4: Feedback Integration Loop

1. Monitor for feedback files
2. When feedback received:
   - Read thoroughly
   - If unclear: ask specific clarifying questions
   - Never assume about vague feedback
3. Address feedback systematically
4. Generate updated report
</workflow>

<file_creation_safety>
## File Creation Safety (CRITICAL)

Use the **Write tool** for ALL source files — never an unquoted Bash heredoc,
which silently corrupts template-literal syntax (`${variable}`) in `.tsx`/`.ts`/
`.jsx`/`.vue`/`.md` and similar. This duplicates the canonical rule in
`.claude/rules/shell-conventions.md`; the full decision tree lives in
`.claude/protocols/safe-file-creation.md`, and the expanded rules, examples, and
pre-write checklist are in `resources/REFERENCE.md`.
</file_creation_safety>

<parallel_execution>
## When to Split

- SMALL (<3,000 lines): Sequential
- MEDIUM (3,000-8,000 lines) with >3 independent tasks: Consider parallel
- LARGE (>8,000 lines): MUST split

## Option A: Parallel Feedback Checking (Phase 0)

When multiple feedback sources exist:

```
Spawn 2 parallel Explore agents:

Agent 1: "Read grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md:
1. Does file exist?
2. If yes, verdict (CHANGES_REQUIRED or APPROVED)?
3. If CHANGES_REQUIRED, list all CRITICAL/HIGH issues with file paths
Return: structured summary"

Agent 2: "Read grimoires/loa/a2a/sprint-N/engineer-feedback.md:
1. Does file exist?
2. If yes, verdict (All good or changes requested)?
3. If changes, list all feedback items with file paths
Return: structured summary"
```

## Option B: Parallel Task Implementation (Phase 2)

When sprint has multiple independent tasks:

```
1. Read sprint.md and identify all tasks
2. Analyze task dependencies
3. Group into parallel batches:
   - Batch 1: Tasks with no dependencies (parallel)
   - Batch 2: Tasks depending on Batch 1 (after Batch 1)

For independent tasks, spawn parallel agents:
Agent 1: "Implement Task 1.2 - read acceptance criteria, review patterns, implement, write tests, return summary"
Agent 2: "Implement Task 1.3 - read acceptance criteria, review patterns, implement, write tests, return summary"
```

## Consolidation

1. Collect results from all parallel agents
2. Verify no conflicts between implementations
3. Run integration tests across all changes
4. Generate unified report

## Evidence-Gathering Dispatch (cycle-119)

Evidence-gathering fan-outs (e.g. Option A feedback checks, codebase surveys) MAY dispatch the
`loa-scout` agent (haiku, read-only — `.claude/agents/loa-scout.md`) instead of a full Explore
agent, to cut cost on pure read-and-report work. Implementation substeps (any Write/Edit) and
anything verdict-bearing (feedback verdict classification, AC status determination, audit/review
judgments) MUST stay in-session or on a full agent — never delegated to loa-scout.
</parallel_execution>

<output_format>
See `resources/templates/implementation-report.md` for full structure.

Key sections:
- Executive Summary
- Tasks Completed (files, approach, tests)
- Technical Highlights
- Testing Summary
- Known Limitations
- Verification Steps
- Feedback Addressed (if iteration)
</output_format>

<success_criteria>
- **Specific**: Every task implemented per acceptance criteria
- **Measurable**: Test coverage metrics included
- **Achievable**: All sprint tasks completed
- **Relevant**: Implementation matches PRD/SDD
- **Time-bound**: Report generated for review
</success_criteria>

<semver_requirements>
See `resources/REFERENCE.md` for the SemVer version format (MAJOR.MINOR.PATCH),
the when-to-bump table, and the version update process.
</semver_requirements>

<task_planning>
## Task Planning (Required for Complex Tasks) (v0.19.0)

### What is a Complex Task?

A task is complex if ANY of these apply:
- Touches 3+ files/modules
- Involves architectural decisions
- Implementation path is unclear
- Estimated at >2 hours
- Has multiple acceptance criteria
- Involves security-sensitive code

### Planning Requirement

For complex tasks, create a plan BEFORE writing code: see the **Task Plan
Template** in `resources/REFERENCE.md` for the full plan structure (Objective,
Approach, Files to Modify, Dependencies, Risks, Verification, Acceptance Criteria).

### Plan Review

Before implementing:
1. Review plan for completeness
2. Identify any blockers
3. Confirm approach aligns with SDD
4. Get human approval if high-risk

### Simple Tasks

For simple tasks (documentation updates, config changes, small fixes), planning is optional. Use judgment.

### Plan as Artifact

Task plans are stored in `grimoires/loa/a2a/sprint-N/task-{N}-plan.md` and become part of the review artifact.
</task_planning>

<checklists>
See `resources/REFERENCE.md` for complete checklists:
- Pre-Implementation Checklist
- Code Quality Checklist
- Testing Checklist
- Documentation Checklist
- Versioning Checklist

**Red Flags (immediate action required):**
- No tests for new code
- Hardcoded secrets
- Skipped error handling
- Ignored existing patterns
</checklists>

<beads_workflow>
## Beads Workflow (beads_rust)

The canonical `br` task lifecycle is Phase -2 (Beads-First Integration) above
and `.claude/protocols/beads-integration.md`. The full session-start /
task-lifecycle / semantic-labels / session-end command reference (including
`get-ready-work.sh` and the label table) is in `resources/REFERENCE.md`.
</beads_workflow>

<retrospective_postlude>
After main skill logic completes, if `.loa.config.yaml` `invisible_retrospective.enabled: true`
(and not disabled for this skill under `invisible_retrospective.skills`), silently run the
learning-signal scan per `.claude/skills/continuous-learning/SKILL.md` and its
`resources/RETROSPECTIVE.md` (quality gates, sanitization, trajectory logging). Recursion guard:
never when the active skill is continuous-learning itself.
</retrospective_postlude>
