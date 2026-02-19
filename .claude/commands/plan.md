---
name: plan
description: Plan your project — requirements, architecture, and sprints
output: Planning artifacts (PRD, SDD, Sprint Plan)
command_type: workflow
---

# /plan - Guided Planning Flow

## Purpose

Single command that walks through the entire planning pipeline: requirements discovery → architecture design → sprint planning. Auto-detects where you left off and resumes from there.

**This is a Golden Path command.** It routes to the existing truename commands (`/plan-and-analyze`, `/architect`, `/sprint-plan`) based on your current state.

## Invocation

```
/plan                              # Resume from wherever you left off
/plan --from discovery             # Force restart from requirements
/plan --from architect             # Skip to architecture (requires PRD)
/plan --from sprint                # Skip to sprint planning (requires PRD + SDD)
/plan Build an auth system         # Pass context to discovery phase
```

## Workflow

### 1. Detect Planning Phase

Run the golden-path state detection:

```bash
source .claude/scripts/golden-path.sh
phase=$(golden_detect_plan_phase)
# Returns: "discovery" | "architecture" | "sprint_planning" | "complete"
```

### 2. Handle `--from` Override

If the user passed `--from`, validate prerequisites:

| `--from` | Requires | Routes To |
|----------|----------|-----------|
| `discovery` | Nothing | `/plan-and-analyze` |
| `architect` | PRD must exist | `/architect` |
| `sprint` | PRD + SDD must exist | `/sprint-plan` |

If prerequisites missing, show error:
```
LOA-E001: Missing prerequisite
  Architecture design requires a PRD.
  Run /plan first (or /plan --from discovery).
```

### 3. Use-Case Qualification (First-Time Projects Only)

Before archetype selection, help new users understand if Loa is right for them. Only show this when:
1. `grimoires/loa/prd.md` does NOT exist
2. `grimoires/loa/ledger.json` has NO completed cycles

Present via AskUserQuestion:
```yaml
question: "Ready to plan your project with Loa?"
header: "Welcome"
options:
  - label: "Let's go!"
    description: "Start planning — I know what I want to build"
  - label: "What does Loa add?"
    description: "Show me what Loa provides over vanilla Claude Code"
multiSelect: false
```

If user selects "What does Loa add?", display:

```
What Loa adds to Claude Code:

  Structured Planning     PRD → SDD → Sprint Plan → Implementation
  Quality Gates           Code review + security audit on every sprint
  Cross-Session Memory    NOTES.md persists learnings across sessions
  Multi-Model Review      Flatline Protocol (Opus + GPT-5.2) on docs
  Task Tracking           Beads CLI for sprint task lifecycle
  Deployment Support      IaC, CI/CD, and production hardening

Loa works best for:
  ✓ Projects with 2+ weeks of development
  ✓ Teams that want structured quality gates
  ✓ Codebases that need architecture documentation

Less useful for:
  → Quick scripts or one-off tasks
  → Projects with < 1 day of work
```

After displaying the information, present a follow-up confirmation via AskUserQuestion:

```yaml
question: "Ready to start planning?"
header: "Continue"
options:
  - label: "Let's go!"
    description: "Start the planning process now"
  - label: "Not yet"
    description: "Exit — come back when ready"
multiSelect: false
```

If user selects "Not yet", end the command with: "No problem. Run /plan when you're ready."
If user selects "Let's go!", continue to archetype selection.

### 4. Archetype Selection (First-Time Projects Only)

Before routing to discovery, check if this is a first-time project:

1. Does `grimoires/loa/prd.md` exist? → If yes, **SKIP** archetypes.
2. Does `grimoires/loa/ledger.json` have any completed cycles? → If yes, **SKIP**.
3. If both conditions indicate a fresh project, **dynamically discover** archetypes:

```bash
for f in .claude/data/archetypes/*.yaml; do
  name=$(yq '.name' "$f")
  desc=$(yq '.description' "$f")
  echo "$name: $desc"
done
```

Build AskUserQuestion options from discovered archetype files. Since AskUserQuestion has a maximum of 4 options (plus auto-appended "Other"), select the **first 3** archetypes to leave room for "Other" as the 4th visible option:

1. Read all `.claude/data/archetypes/*.yaml` files
2. Sort by a `priority` field if present, otherwise alphabetically
3. Take the first 3 files as options
4. The 4th slot is reserved — leave it empty so "Other" (auto-appended) is the 4th visible option

If more than 3 archetypes exist, add a note in the 3rd option's description: "More archetypes available — select Other to describe your project."

```yaml
question: "What type of project are you building?"
header: "Archetype"
options:
  # Dynamically built from .claude/data/archetypes/*.yaml
  # Each file becomes one option: name → label, description → description
  # Max 3 archetype options so "Other" is visible as the 4th option
multiSelect: false
```

The user can select "Other" to skip and start from a blank slate. If no archetype files exist, skip this step entirely.

On selection: read the archetype YAML, format its `context` fields into Markdown, and write to `grimoires/loa/context/archetype.md`. The context ingestion pipeline in `/plan-and-analyze` picks it up automatically.

**Risk Seeding**: After writing `archetype.md`, also seed `grimoires/loa/NOTES.md` with domain-specific risks from the archetype:

1. Extract `context.risks` from the selected archetype YAML
2. If `grimoires/loa/NOTES.md` does not exist, create it with a `## Known Risks` section
3. If `grimoires/loa/NOTES.md` exists but has no `## Known Risks` section, append it
4. If `## Known Risks` already has content, **skip** (don't duplicate on re-selection)
5. Each risk becomes a bullet point: `- **[Archetype: {name}]**: {risk}`

This ensures domain knowledge persists across sessions. A developer starting sprint-3 of a REST API project sees OWASP risks in NOTES.md even if archetype selection happened weeks ago.

### 5. Route to Truename

Based on detected (or overridden) phase:

| Phase | Action |
|-------|--------|
| `discovery` | Execute `/plan-and-analyze` with any user-provided context |
| `architecture` | Execute `/architect` |
| `sprint_planning` | Execute `/sprint-plan` |
| `complete` | Show: "Planning complete. All artifacts exist. Next: /build" |

### 6. Chain Phases

After each phase completes successfully, check if the next phase should run:

- After discovery → "PRD created. Continue to architecture? [Y/n]"
- After architecture → "SDD created. Continue to sprint planning? [Y/n]"
- After sprint planning → "Sprint plan ready. Next: /build"

Use the AskUserQuestion tool for continuations:
```yaml
question: "Continue to architecture design?"
options:
  - label: "Yes, continue"
    description: "Design the system architecture now"
  - label: "Stop here"
    description: "I'll run /plan again later to continue"
```

## Arguments

| Argument | Description |
|----------|-------------|
| `--from discovery` | Force start from requirements gathering |
| `--from architect` | Start from architecture (requires PRD) |
| `--from sprint` | Start from sprint planning (requires PRD + SDD) |
| Free text | Passed as context to `/plan-and-analyze` |

## Error Handling

| Error | Response |
|-------|----------|
| `--from architect` without PRD | Show error, suggest `/plan` or `/plan --from discovery` |
| `--from sprint` without SDD | Show error, suggest `/plan --from architect` |
| All phases complete | Show success message, suggest `/build` |

## Examples

### Fresh Project
```
/plan

Detecting planning state...
  PRD: not found
  SDD: not found
  Sprint: not found

Starting from: Requirements Discovery
→ Running /plan-and-analyze

[... plan-and-analyze executes ...]

PRD created. Continue to architecture design? [Y/n]
> Y

→ Running /architect

[... architect executes ...]

SDD created. Continue to sprint planning? [Y/n]
> Y

→ Running /sprint-plan

[... sprint-plan executes ...]

Planning complete!
  ✓ PRD: grimoires/loa/prd.md
  ✓ SDD: grimoires/loa/sdd.md
  ✓ Sprint: grimoires/loa/sprint.md

Next: /build
```

### Resume Mid-Planning
```
/plan

Detecting planning state...
  PRD: ✓ exists
  SDD: not found
  Sprint: not found

Resuming from: Architecture Design
→ Running /architect
```

### With Context
```
/plan Build a REST API for user management with JWT auth and rate limiting

Starting from: Requirements Discovery
→ Running /plan-and-analyze with context:
  "Build a REST API for user management with JWT auth and rate limiting"
```
