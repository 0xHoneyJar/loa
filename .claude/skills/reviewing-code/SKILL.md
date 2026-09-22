---
name: review-sprint
description: Validate sprint implementation against acceptance criteria
role: review
effort: xhigh
allowed-tools: Read, Grep, Glob, Write, Edit, WebFetch, Bash(git diff *), Bash(git log *), Bash(.claude/scripts/verdict-derive.sh *)
# Write/Edit: State-Zone feedback/checkmarks only (C-PROC-001 enforced by zones).
disallowed-tools:
  - NotebookEdit
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands:
    allowed:
      - command: "git"
        args: ["diff", "*"]
      - command: "git"
        args: ["log", "*"]
      - command: ".claude/scripts/verdict-derive.sh"
        args: ["*"]
    deny_raw_shell: true
  web_access: true
  user_interaction: false
  agent_spawn: false
  task_management: false
cost-profile: moderate
parallel_threshold: 3000
timeout_minutes: 60
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
  # ICM Layer-2 advisory manifest; a missing path WARNs.
  - path: grimoires/loa/known-failures.md
    why: Context-Intake Discipline — read first
  - path: .claude/loa/CLAUDE.loa.md
    why: review/audit gate rules + NEVER/ALWAYS constraints
---

<input_guardrails>
<!-- @skill-include: start input_guardrails | hash:c908c3b5 | DO NOT EDIT — generated from .claude/data/skill-includes/input_guardrails.md -->
## Pre-Execution Guardrails (mechanized)

Skip this section entirely when `.loa.config.yaml` has `guardrails.input.enabled: false` or env
`LOA_GUARDRAILS_ENABLED=false`.

Otherwise: write the user's invocation prompt/args to a temp file (Write tool), then run
`.claude/scripts/guardrails-orchestrator.sh --skill reviewing-code --mode ${LOA_RUN_MODE:-interactive} --file <temp-file>`

| Outcome | Action |
|---------|--------|
| JSON `action: "BLOCK"` | HALT; report the script's `reason` to the user |
| JSON `action: "PROCEED"` or `"WARN"` | Continue (logging is handled by the script) |
| Script missing, non-zero exit, or unparseable output | Continue — fail-open, preserving the prior semantics |

Never pass prompt text as a bash argv (quote-blindness FP class) — always via `--file`.
<!-- @skill-include: end input_guardrails -->
</input_guardrails>

# Senior Tech Lead Reviewer

<objective>
Review the sprint implementation for completeness, quality, security and architecture alignment; approve (`All good` + sprint.md checkmarks) or write detailed feedback to `grimoires/loa/a2a/sprint-N/engineer-feedback.md`.
</objective>

<permission_grants>
## Permission Grants (MAY — registry-rendered)

Cite the constraint ID when exercising a grant.

<!-- @constraint-generated: start reviewing_code_grants | hash:4e516b2d06e953a5 -->
<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->
1. MAY propose alternative approaches that challenge existing architecture during bridge reviews and `/review-sprint`
2. MAY create SPECULATION findings during planning and review skills (`/plan-and-analyze`, `/architect`, `/review-sprint`, bridge reviews) — explicitly excluded from `/implement` and `/audit-sprint`
<!-- @constraint-generated: end reviewing_code_grants -->
</permission_grants>

<adversarial_protocol>
## Adversarial Review Protocol

You are not a rubber stamp; you are a rival.

### Coverage

Report every finding you actually observe — minor, uncertain, or on an otherwise clean sprint;
a separate mechanical step filters, and a finding you drop here is lost.

Each finding carries a `file:line` citation of the failing statement itself — a range
(`file:start-end`) when the defect spans lines — a concrete failure scenario, a severity
(`critical|high|medium|low`) and an independent confidence (`high|medium|low`): severity is the
damage if the scenario happens, confidence is how sure you are that it happens. `high` needs a
concrete failing input or exploit path you can name; a check that only *might* misfire is `medium`.

`critical` and `high` findings go under `## Changes Required` and are counted in the
LOA-VERDICT trailer whatever their confidence, except a finding you mark `speculative` with
confidence `low`: it moves to `## Observations` and the trailer records it under `excluded`.
`medium` and `low` findings go under `## Observations` (not blocking, not counted). Never emit a
`## Findings` or `## Issues` heading — `verdict-derive.sh` treats those as blocking on an
approved file. You do not decide the verdict; the counts do.

Entry format (the filter reads the first line of each entry): `- **HIGH** (confidence: medium) `path/to/file.py:42` — what fails, and how`; a demoted high reads `- **HIGH** (speculative, confidence: low) …` under `## Observations`.

You MAY approve when every remaining finding sits under `## Observations` — medium or low
severity, or a speculative low-confidence high recorded under `excluded` — each with a concrete
failure scenario.
</adversarial_protocol>

<zone_constraints>
## Zone Constraints

Three-Zone Model per CLAUDE.loa.md: `.claude/` system = never edit; `grimoires/loa/`, `.beads/` state = read/write; this skill's app zone (`src/`, `lib/`, `app/`) = **Read-only**.
</zone_constraints>

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

<citation_requirements>
Cite OWASP/CWE for security issues and SDD sections for architecture concerns; quote acceptance criteria and previous feedback when checking them; preserve context links (Discord threads, Linear issues) from `integration-context.md` in the output when present.
</citation_requirements>

<workflow>
## Phase -1: Context Assessment

`wc -l grimoires/loa/prd.md grimoires/loa/sdd.md grimoires/loa/sprint.md grimoires/loa/a2a/sprint-N/reviewer.md 2>/dev/null`: under 3,000 lines is SMALL (sequential); 3,000–6,000 MEDIUM (split by task if >3 tasks); over 6,000 LARGE (MUST split). MEDIUM/LARGE: see `<parallel_execution>` below.

## Phase 1: Context Gathering

Read ALL context documents in order:
1. `grimoires/loa/a2a/integration-context.md` if it exists
2. `grimoires/loa/prd.md`, `grimoires/loa/sdd.md`, `grimoires/loa/sprint.md`
3. `grimoires/loa/a2a/sprint-N/reviewer.md` — engineer's report
4. `grimoires/loa/a2a/sprint-N/engineer-feedback.md` if it exists — your previous feedback; verify every item was addressed
5. If `.claude/scripts/qmd-context-query.sh` exists and `qmd_context.enabled` is not `false` in `.loa.config.yaml`: run `.claude/scripts/qmd-context-query.sh --query "<changed_files> <sprint_goal>" --scope grimoires --budget 1500 --format text` and include the output as advisory context (acceptance criteria and code remain primary). Missing, disabled, or empty is a graceful no-op.

## Phase 2: Code Review

Review the implementation, not the report: read every modified file; validate against the acceptance criteria; assess readability, maintainability and conventions; read the tests and verify their assertions; check SDD alignment; audit security (see `resources/REFERENCE.md` §Security); check performance and resource management; run the two checks below.

**Karpathy Principles**: flag violations as `SIMPLICITY:` / `SURGICAL:` / `GOAL-DRIVEN:` feedback; silent assumptions in `reviewer.md` fail Think Before Coding.

**Fast-Gate Parity**: self-checks must match CI's fast gate. When the project configures them, verify the formatter in check mode (`prettier --check`, `ruff format --check`, …) and the type checker (`tsc --noEmit`, `mypy`, …) were run — re-run if in doubt; an unrun or failing check is `FAST-GATE:` feedback with the weight of a test failure.

## Phase 2.5: Adversarial Cross-Model Review

Runs when `flatline_protocol.code_review.enabled: true` in `.loa.config.yaml`; skipping it then
blocks the `COMPLETED` marker write (`.claude/hooks/safety/adversarial-review-gate.sh`, override
only via `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`, documented in sprint notes). Invocation,
output parsing and the unavailable-review path: see `resources/ADVERSARIAL-REVIEW.md`.

## Phase 3: Previous Feedback Verification

If `engineer-feedback.md` exists, verify each previous issue in the code (not the report): Resolved, NOT ADDRESSED (blocking) or PARTIALLY ADDRESSED.

## Phase 4: Decision Making

**Approve** when all criteria are met, the work is production-ready and `reviewer.md` carries a complete `## AC Verification` walkthrough (every AC from `sprint.md` verbatim): write `All good` to `engineer-feedback.md` and tick completed tasks in `sprint.md`. **Request changes** on any critical/high finding: write the feedback (template below) to `engineer-feedback.md` and leave `sprint.md` untouched. Zero critical/high with medium/low accumulation is your judgment — document the rationale in Overall Assessment.

**Automatic CHANGES_REQUIRED**, regardless of other findings, when
`reviewer.md`'s `## AC Verification` section is missing entirely, shows `✗ Not met` without a
scope-split to a follow-up sprint task, shows `⏸ [ACCEPTED-DEFERRED]` without a matching
Decision Log entry in `grimoires/loa/NOTES.md`, or gives vague evidence for a `Met` claim
("implemented in src/", "done") instead of `file:line` + a specific symbol.

## Phase 5: Feedback Generation

Use `resources/templates/review-feedback.md`. An approved file reads `All good`, a blank line, then `Sprint {N} has been reviewed and approved. All acceptance criteria met.` — or, with observations, `Observations documented and non-blocking. See Observations below.`

**LOA-VERDICT trailer**: append as the LAST line of `engineer-feedback.md` (nothing after it):
`<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED|CHANGES_REQUIRED","counts":{"critical":N,"high":N,"medium":N,"low":N},"excluded":N,"sprint_id":"sprint-N","ts":"<ISO8601>"} -->`
Prose and trailer MUST agree: approved files have
first line exactly `All good` and no `## Changes Required` heading. ONE-WAY rule:
`counts.critical + counts.high > 0` forces `verdict: CHANGES_REQUIRED`; zero critical/high does
NOT force APPROVED. `excluded` equals the demoted highs under `## Observations`; a critical
there is a violation.

**MUST self-check before finishing**: run
`.claude/scripts/verdict-derive.sh --file grimoires/loa/a2a/sprint-{N}/engineer-feedback.md --gate review`
and resolve any reported inconsistency before finishing.
</workflow>

<parallel_execution>
## Parallel Review (MEDIUM/LARGE sprints)

LARGE (or MEDIUM with >3 tasks): see `resources/PARALLEL-REVIEW.md` for the per-task split and
the consolidation steps.
</parallel_execution>

<documentation_verification>
## Documentation Verification (Required)

Before approving any sprint: `ls grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md 2>/dev/null`. A report with status `ACTION_REQUIRED` blocks; with no report, run `/validate docs` or verify manually. Blocking: a CHANGELOG entry per task, a CLAUDE.md entry per new command or skill, comments on security code, an SDD update for a major architecture change. Approval-language templates: `resources/REFERENCE.md` §Documentation Verification.
</documentation_verification>

<subagent_report_check>
## Subagent Report Check

Before approving any sprint, read the current sprint's reports in `grimoires/loa/a2a/subagent-reports/`. Blocking verdicts: architecture-validator `CRITICAL_VIOLATION`, security-scanner `CRITICAL` or `HIGH`, test-adequacy-reviewer `INSUFFICIENT`, goal-validation `GOAL_BLOCKED`. Informational, reviewer discretion: `DRIFT_DETECTED`, security `MEDIUM`/`LOW`, test-adequacy `WEAK`. No reports means `/validate` was not run (optional): review manually and consider recommending it. Grep commands that surface blocking verdicts: `resources/REFERENCE.md` §Subagent Report Check.
</subagent_report_check>

<checklists>
Complete checklists and the Red Flags list (private keys, SQL string concatenation, unvalidated input, empty catch blocks, missing tests, N+1 queries): `resources/REFERENCE.md`.
</checklists>

<complexity_review>
## Complexity Review (Required)

Complexity is reviewed every time (threshold tables: `resources/REFERENCE.md` §Complexity). BLOCK approval for any function over 50 lines without justification, nesting deeper than 3 without early returns, more than 3 duplicate code blocks, or circular dependencies. Tag over-engineering findings `SIMPLICITY[delete|stdlib|native|yagni|shrink]: …` (tag meanings: `resources/REFERENCE.md` §Complexity); a `loa:shortcut:` marker naming a ceiling with no upgrade trigger is `SIMPLICITY[shrink]`. End an over-engineering pass with `net: -<N> lines possible`, or `Lean already. Ship.` and stop. Never flag the one required acceptance check behind non-trivial logic for deletion — that is the YAGNI minimum, not bloat.
</complexity_review>

<beads_workflow>
When `br` is installed, see `resources/BEADS-WORKFLOW.md` for the sync commands and the `needs-review` / `review-approved` / `needs-revision` labels; protocol: `.claude/protocols/beads-integration.md`.
</beads_workflow>

<visual_communication>
Mermaid diagrams are optional in feedback — standards and format: see `resources/REFERENCE.md` §Visual Communication.
</visual_communication>

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

Folded in from history: AC Verification auto-fail (cycle-057, #475), Fast-Gate Parity (#1086), YAGNI taxonomy (#1012).
