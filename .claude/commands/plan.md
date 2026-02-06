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

### 3. Route to Truename

Based on detected (or overridden) phase:

| Phase | Action |
|-------|--------|
| `discovery` | Execute `/plan-and-analyze` with any user-provided context |
| `architecture` | Execute `/architect` |
| `sprint_planning` | Execute `/sprint-plan` |
| `complete` | Show: "Planning complete. All artifacts exist. Next: /build" |

### 4. Chain Phases

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
