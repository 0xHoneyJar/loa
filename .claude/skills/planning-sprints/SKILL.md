---
name: sprint-plan
description: Create comprehensive sprint plan based on PRD and SDD
role: planning
capabilities:
  schema_version: 1
  read_files: true
  search_code: true
  write_files: true
  execute_commands: false
  web_access: false
  user_interaction: true
  agent_spawn: false
  task_management: false
cost-profile: moderate
context: fork
parallel_threshold: null
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
---

# Sprint Planner

<objective>
Transform PRD and SDD into actionable sprint plan with right-sized sprints, including deliverables, acceptance criteria, technical tasks, dependencies, and risk mitigation. Generate `grimoires/loa/sprint.md`.
</objective>

<zone_constraints>
## Zone Constraints

Zones per CLAUDE.loa.md Three-Zone Model (`.claude/` system = never edit — use `.claude/overrides/` or `.loa.config.yaml`; `grimoires/loa/`, `.beads/` state = read/write). This skill's app zone (`src/`, `lib/`, `app/`): **Read-only**.
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
<!-- @skill-include: start context_discipline | hash:d7adbf89 | DO NOT EDIT — generated from .claude/data/skill-includes/context_discipline.md -->
## Context Discipline

Follow `.claude/protocols/tool-result-clearing.md`: single result >2K tokens / accumulated >5K /
full file >3K / session >15K → extract findings (≤10 files, ≤20 words, file:line) to NOTES.md
and reason from that synthesis. Big artefacts: `notes-guard.sh read --file F --section <H>` /
`--index` before a blind Read. Start: read NOTES.md "Session Continuity"; end / pre-compaction:
update it (decisions → Decision Log, issues → Technical Debt).
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

<workflow>
## Phase -1: Beads-First Preflight

Beads task tracking is the EXPECTED DEFAULT; check health before planning.

### Run Beads Health Check

```bash
health=$(.claude/scripts/beads/beads-health.sh --json)
status=$(echo "$health" | jq -r '.status')
```

### Status Handling

| Status | Action |
|--------|--------|
| `HEALTHY` | Proceed silently to Phase 0 |
| `DEGRADED` | Show recommendations, offer quick fix, proceed |
| `NOT_INSTALLED` | Check opt-out, prompt if needed |
| `NOT_INITIALIZED` | Check opt-out, prompt if needed |
| `MIGRATION_NEEDED` | Must address before proceeding |
| `UNHEALTHY` | Must address before proceeding |

### If NOT_INSTALLED or NOT_INITIALIZED

Check opt-out via `update-beads-state.sh --opt-out-check`; no valid opt-out → HITL gate per `.claude/protocols/beads-preflight.md` (owns the full opt-out workflow). Detail: → `resources/REFERENCE.md` §Beads NOT_INSTALLED fallback.

### If DEGRADED

Show recommendations but proceed:
```
Beads Health: DEGRADED
Recommendations:
$(echo "$health" | jq -r '.recommendations[]')

Proceeding with sprint planning...
```

### Protocol Reference

See `.claude/protocols/beads-preflight.md` for full specification.

## Phase 0: Check Feedback Files, Ledger, and Integration Context

### Step 0: Check for Sprint Ledger

If `grimoires/loa/ledger.json` is missing, offer creation (AskUserQuestion) before planning; if present, register the new sprints in it. Full choreography: → `resources/REFERENCE.md` §Sprint-Ledger Step 0.

### Step 1: Check for Security Audit Feedback

Check if `grimoires/loa/a2a/auditor-sprint-feedback.md` exists:

**If exists + "CHANGES_REQUIRED":**
- Previous sprint failed security audit
- Engineers must address feedback before new work
- STOP: "The previous sprint has unresolved security issues. Engineers should run /implement to address grimoires/loa/a2a/auditor-sprint-feedback.md before planning new sprints."

**If exists + "APPROVED - LET'S FUCKING GO":**
- Previous sprint passed security audit
- Safe to proceed with next sprint planning

**If missing:**
- No security audit performed yet
- Proceed with normal workflow

### Step 2: Check for Integration Context

Check if `grimoires/loa/a2a/integration-context.md` exists:

```bash
[ -f "grimoires/loa/a2a/integration-context.md" ] && echo "EXISTS" || echo "MISSING"
```

**If EXISTS**, read it to understand:
- Current state tracking: Where to find project status
- Priority signals: Community feedback volume, CX Triage backlog
- Team capacity: Team structure
- Dependencies: Cross-team initiatives affecting sprint scope
- Context linking: How to link sprint tasks to source discussions
- Documentation locations: Where to update status
- Available MCP tools: Discord, Linear, GitHub integrations

**If MISSING**, proceed with standard workflow using only PRD/SDD.

## Phase 1: Deep Document Analysis

Read `grimoires/loa/prd.md` and `grimoires/loa/sdd.md` completely before proceeding — if either is missing, stop and tell the user both are required.

When creating tasks, quote the exact requirement (`> From prd.md: FR-1.2: "..."`), cite the SDD section (`> From sdd.md: §3.2 Database Design`), link each acceptance criterion back to its requirement, and cite external dependencies with version numbers.

1. Synthesize both documents, noting:
   - Core MVP features and user stories
   - Technical architecture and design decisions
   - Dependencies between features
   - Technical constraints and risks
   - Success metrics and acceptance criteria

2. Identify gaps:
   - Ambiguous requirements or acceptance criteria
   - Missing technical specifications
   - Unclear priorities or sequencing
   - Potential scope creep — if MVP is too large, recommend specific reductions
   - Misalignment between SDD's approach and the PRD — flag and seek clarification
   - Integration points needing clarification

## Phase 2: Strategic Questioning

Ask clarifying questions about:
- Priority conflicts or feature trade-offs
- Technical uncertainties impacting effort estimation
- Resource availability or team composition
- External dependencies or third-party integrations
- Underspecified requirements
- Risk mitigation strategies

Wait for responses before proceeding. Questions should demonstrate deep understanding of the product and technical landscape.

## Phase 3: Sprint Plan Creation

Design sprint breakdown with:

**Overall Structure:**
- Executive Summary: MVP scope and total sprint count
- Sprint-by-sprint breakdown, each with specific start/end dates
- Risk register and mitigation strategies
- Success metrics and validation approach

**Per Sprint** (template: `resources/templates/sprint-template.md`; full checklist: `resources/REFERENCE.md` §Sprint Structure Checklist):
- Sprint Goal (1 sentence)
- Scope: SMALL (1-3 tasks) / MEDIUM (4-6) / LARGE (7-10) — no sprint exceeds 10 tasks
- Deliverables, Acceptance Criteria, and Technical Tasks (checkboxes; annotate each task's goal contribution, `→ **[G-1]**`; specific/testable examples: `resources/REFERENCE.md` §Common Anti-Patterns)
- Dependencies, Risks & Mitigation, Success Metrics (quantifiable)

A complete plan lets engineers start immediately without clarification.

### Goal Traceability (Appendix C)

**Extract Goals from PRD:**
1. Check PRD for goal table with ID column: `| ID | Goal | Measurement | Validation Method |`
2. If IDs present (G-1, G-2, etc.), use them directly
3. If IDs missing, auto-assign G-1, G-2, G-3 to numbered goals in "Primary Goals" section
4. Log auto-assigned IDs to trajectory

**Create Goal Mapping:**
1. For each task, identify which goal(s) it contributes to
2. Annotate tasks with `→ **[G-N]**` format
3. Populate Appendix C with goal-to-task mappings
4. Generate warnings for:
   - Goals without any contributing tasks: `⚠️ WARNING: Goal G-N has no contributing tasks`
   - Final sprint missing E2E validation task: `⚠️ WARNING: No E2E validation task found`

**E2E Validation Task:**
1. In the final sprint, include Task N.E2E: End-to-End Goal Validation
2. List all PRD goals with validation steps
3. This task is P0 priority (Must Complete)

## Phase 4: Quality Assurance

Verify: all PRD goals are mapped to tasks (Appendix C), every task is annotated with its goal contribution, and the final sprint includes the E2E validation task. See `resources/REFERENCE.md` §Quality Assurance Checklist for the full pre-finalization pass.

Save to `grimoires/loa/sprint.md`.
</workflow>

<output_format>
See `resources/templates/sprint-template.md` for the full per-sprint field list and structure.
</output_format>

<planning_principles>
See `resources/REFERENCE.md` §Sprint Sequencing Principles when ordering sprints across the plan (foundation first, high-risk early, respect dependencies, incremental value).
</planning_principles>

<beads_workflow>
## Beads Workflow (beads_rust)

When beads_rust (`br`) is installed, use it to track sprint structure:

### Session Start
```bash
br sync --import-only  # Import latest state from JSONL
```

### Creating Sprint Structure
Use helper scripts for epic and task creation:

```bash
# Create sprint epic
EPIC_ID=$(.claude/scripts/beads/create-sprint-epic.sh "Sprint N: Theme" 1)

# Create tasks under epic — EVERY task declares its dependencies at creation
TASK_A=$(.claude/scripts/beads/create-sprint-task.sh "$EPIC_ID" "Build auth middleware" 1 task --deps none)
TASK_B=$(.claude/scripts/beads/create-sprint-task.sh "$EPIC_ID" "Wire login route" 2 task --deps "$TASK_A")
```

**Edge-or-none rule (REQUIRED):** every non-epic bead declares either `--deps <id1,id2>`
(what blocks it) or `--deps none` (an explicit no-blockers assertion, recorded as the
`deps:none` label). A sprint plan is an ordered list — the ordering knowledge exists NOW
and is captured in one flag; retrofitting edges later costs O(n²) review. A task graph
with edges is schedulable (topological order, parallel tracks, honest unblock counts);
a flat list silently degrades every downstream consumer (`get-ready-work.sh --graph`,
`bv --robot-plan` wave dispatch) into priority-only guessing.

### Structural Validation

Cycles are always checked; the richer checks run when `bv` (beads_viewer) is installed
and are skipped gracefully when it is not. bv is an OPTIONAL sidecar — Loa does not
ship or require it; install via `.claude/scripts/beads/install-bv.sh` (or check with
`--check-only`). Agents: never run bare `bv` (interactive TUI) — `--robot-*` flags only.

```bash
# HARD check: the dependency graph must be a DAG
br dep cycles   # must report none

# ADVISORY checks (bv): missing-dep suggestions, duplicates, plan structure
if command -v bv &>/dev/null; then
  CI=1 bv --robot-suggest   # review suggested edges/duplicates; apply what is real
  CI=1 bv --robot-plan      # sanity-check the parallel tracks match plan intent
fi
```

### Semantic Labels for Relationships
Use labels instead of dependency types:

| Relationship | Label | Example |
|--------------|-------|---------|
| Sprint membership | `sprint:<n>` | `br label add beads-xxx sprint:1` |
| Epic association | `epic:<epic-id>` | Auto-added by create-sprint-task.sh |
| Review status | `needs-review` | `br label add beads-xxx needs-review` |

### Session End
```bash
br sync --flush-only  # Export SQLite → JSONL before commit
```

**Protocol Reference**: See `.claude/protocols/beads-integration.md`

### Beads Flatline Loop

After creating beads from the sprint plan, see `resources/beads-flatline-loop.md` if the task graph needs multi-model refinement before `/run sprint-plan` begins.
</beads_workflow>

<visual_communication>
See `resources/visual-communication.md` when a sprint plan would benefit from a Mermaid diagram (task dependencies, sprint workflow); otherwise optional — use agent discretion.
</visual_communication>

<post_completion>
## Post-Completion Debrief

Author each acceptance-criteria checkbox on a single physical line. The AC
verification gate matches that line verbatim in the implementation report;
do not manually wrap the bullet or its quoted report text. Use the exact
heading `### Acceptance Criteria` (and the template's other required headings)
without parenthetical annotations; put explanatory text below the heading.

The artifact validator checks every `## Sprint N` block in the supplied file.
Keep the active cycle's plan separate from archived plans; do not rewrite
shipped sprint blocks just to satisfy a newer template. Goal traceability
may span multiple `## Appendix` sections; all are checked.

After saving the Sprint Plan to `grimoires/loa/sprint.md`, MUST run `.claude/scripts/validate-artifact.sh --type sprint --file grimoires/loa/sprint.md` before the debrief; repair per its output on exit 1; exit 2 (usage/file-not-found) is a validator FAILURE — fix the path and re-run, do not proceed. Present a structured debrief before the user decides to continue.

### Debrief Structure

Present the following in this exact order:

1. **Confirmation**: "✓ Sprint Plan saved to grimoires/loa/sprint.md"

2. **Key Decisions** (3-5 items): The most impactful planning choices. Each decision should be one line: "• {choice made} (not {alternative rejected})"

3. **Assumptions** (1-3 items): Things assumed true but not explicitly confirmed by the user. Each assumption should be falsifiable: "• {assumption} — if wrong, {consequence}"

4. **Biggest Tradeoff** (1 item): The most consequential either/or decision. Format: "• Chose {A} over {B} — {reason}. Risk: {what could go wrong}"

5. **Steer Prompt**: Use AskUserQuestion:

```yaml
question: "Sprint plan ready. Anything to steer before implementation?"
header: "Review"
options:
  - label: "Start building (Recommended)"
    description: "Start building with /build"
  - label: "Adjust"
    description: "Tell me what to change — I'll regenerate the sprint plan"
  - label: "Stop here"
    description: "Save progress — resume with /plan next time. Not what you expected? /feedback helps us fix it."
multiSelect: false
```

### "Adjust" Flow

When the user selects "Adjust":

1. **Prompt**: "What would you like to change?" (free-text via AskUserQuestion "Other")
2. **Scope**: Regenerate the Sprint Plan ONLY (not rerun the entire planning phase)
3. **Context preserved**: PRD, SDD, and all planning decisions are retained
4. **Output**: After regeneration, re-present the debrief with updated decisions/assumptions/tradeoffs
5. **Diff awareness**: If changes are small, note what changed: "Updated: {decision that changed}"
6. **Loop limit**: Max 3 adjustment rounds before suggesting "Start building" more firmly

### Constraints

- "Start building" is always the first option (recommended) — this is the final planning phase
- "Stop here" always includes /feedback mention
</post_completion>
