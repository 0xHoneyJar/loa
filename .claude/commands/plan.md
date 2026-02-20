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

### 3. First-Time Preamble (One-Time)

**Condition**: No PRD exists AND no completed cycles in ledger AND no `--from` override.

Display a brief, non-interactive preamble (3 lines max):

```
Loa guides you through structured planning: requirements → architecture → sprints.
Multi-model review catches issues that single-model misses.
Cross-session memory means you never start from scratch.
```

This displays ONCE. No AskUserQuestion. No gate. No "What does Loa add?" choice.
The preamble is followed immediately by the free-text prompt.

### 4. Free-Text Project Description

**Condition**: Phase is "discovery" (no existing PRD).

Present a free-text prompt via AskUserQuestion:

```yaml
question: "Tell me about your project. What are you building, who is it for, and what problem does it solve?"
header: "Your project"
options:
  - label: "Describe my project"
    description: "Type your project description in the text box below (select Other)"
  - label: "I have context files ready"
    description: "Skip to /plan-and-analyze — I've already put docs in grimoires/loa/context/"
multiSelect: false
```

**Note**: The real input comes via the "Other" free-text option (auto-appended by AskUserQuestion). The first option's description guides users to use it.

#### 4a. Process Free-Text Input

When the user provides a description (via "Other" or "Describe my project"):

**Input validation**:
- If empty or <10 characters: reprompt with "Could you tell me more? A sentence or two about what you're building helps me plan better."
- If <30 characters: accept but log a note that context is thin — Phase 0 interview will compensate
- No entropy check needed — even "todo app" is valid input

1. **Save description** to `grimoires/loa/context/user-description.md`:
   ```markdown
   # Project Description (from /plan)
   > Auto-generated from user's initial project description.

   {user's free-text input}
   ```

2. **Infer archetype** using the LLM (not keyword matching):
   - Read all archetype YAML files from `.claude/data/archetypes/*.yaml`
   - Present the list of archetype names + descriptions along with the user's description
   - Classify internally: "Which archetype best matches this project? Reply with the filename or 'none'."
   - Confidence threshold: Only seed risks if confidence is `high` or `medium`
   - If match found: silently load `context.risks` into `grimoires/loa/NOTES.md` under `## Known Risks`
   - If multiple matches: merge risk checklists from all matching archetypes
   - If no match or low confidence: skip risk seeding (no error, no prompt)
   - **Never show the archetype to the user** — it's internal scaffolding only
   - Log the inferred archetype to `grimoires/loa/context/archetype-inference.md`:
     ```markdown
     # Archetype Inference
     - **Archetype**: {filename or "none"}
     - **Confidence**: {high|medium|low}
     - **Rationale**: {1-2 sentence explanation}
     ```

3. **Route to** `/plan-and-analyze` — the description in context/ will be picked up by Phase 0 synthesis.

When the user selects "I have context files ready":
- Skip to `/plan-and-analyze` directly (current behavior for context-rich users).

**Privacy**: `user-description.md` and `archetype-inference.md` are automatically gitignored by the existing `grimoires/loa/context/*` pattern.

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

Loa guides you through structured planning: requirements → architecture → sprints.
Multi-model review catches issues that single-model misses.
Cross-session memory means you never start from scratch.

Tell me about your project. What are you building, who is it for,
and what problem does it solve?

> I'm building a data measurement platform for AI teams. It tracks
> model performance, experiment lineage, and team velocity...

✓ Saved description to grimoires/loa/context/user-description.md
→ Running /plan-and-analyze

[... plan-and-analyze Phase 0 synthesizes description ...]
```

### With Inline Context
```
/plan Build a REST API for user management with JWT auth and rate limiting

✓ Saved description to grimoires/loa/context/user-description.md
→ Running /plan-and-analyze with context
```

### Resume Mid-Planning
```
/plan

Detecting planning state...
  PRD: ✓ exists
  SDD: not found

Resuming from: Architecture Design
→ Running /architect
```
