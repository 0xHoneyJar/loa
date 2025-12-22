---
name: "sprint-plan"
version: "1.0.0"
description: |
  Create comprehensive sprint plan based on PRD and SDD.
  Task breakdown, prioritization, acceptance criteria, assignments.

arguments: []

agent: "planning-sprints"
agent_path: "skills/planning-sprints/"

context_files:
  - path: "loa-grimoire/prd.md"
    required: true
    purpose: "Product requirements for scope"
  - path: "loa-grimoire/sdd.md"
    required: true
    purpose: "Architecture for technical breakdown"
  - path: "loa-grimoire/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and knowledge sources"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "file_exists"
    path: "loa-grimoire/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."

  - check: "file_exists"
    path: "loa-grimoire/sdd.md"
    error: "SDD not found. Run /architect first."

outputs:
  - path: "loa-grimoire/sprint.md"
    type: "file"
    description: "Sprint plan with tasks and acceptance criteria"

mode:
  default: "foreground"
  allow_background: true
---

# Sprint Plan

## Purpose

Create a comprehensive sprint plan based on PRD and SDD. Breaks down work into actionable tasks with acceptance criteria, priorities, and assignments.

## Invocation

```
/sprint-plan
/sprint-plan background
```

## Agent

Launches `planning-sprints` from `skills/planning-sprints/`.

See: `skills/planning-sprints/SKILL.md` for full workflow details.

## Prerequisites

- Setup completed (`.loa-setup-complete` exists)
- PRD created (`loa-grimoire/prd.md` exists)
- SDD created (`loa-grimoire/sdd.md` exists)

## Workflow

1. **Pre-flight**: Verify setup, PRD, and SDD exist
2. **Analysis**: Read PRD for requirements, SDD for architecture
3. **Breakdown**: Create sprint structure with actionable tasks
4. **Clarification**: Ask about team size, sprint duration, priorities
5. **Validation**: Confirm assumptions about capacity and scope
6. **Generation**: Create sprint plan at `loa-grimoire/sprint.md`
7. **Analytics**: Update usage metrics (THJ users only)

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/sprint.md` | Sprint plan with tasks |

## Sprint Plan Sections

The generated plan includes:
- Sprint Overview (goals, duration, team structure)
- Sprint Breakdown with:
  - Sprint number and goals
  - Tasks with clear descriptions
  - Acceptance criteria (specific, measurable)
  - Estimated effort/complexity
  - Developer assignments
  - Dependencies and prerequisites
  - Testing requirements
- MVP Definition and scope
- Feature prioritization rationale
- Risk assessment and mitigation
- Success metrics per sprint
- Dependencies and blockers
- Buffer time for unknowns

## Task Format

Each task includes:
- Task ID and title
- Detailed description
- Acceptance criteria
- Estimated effort
- Assigned to
- Dependencies
- Testing requirements

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Loa setup has not been completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "PRD not found" | Missing prd.md | Run `/plan-and-analyze` first |
| "SDD not found" | Missing sdd.md | Run `/architect` first |

## Planner Style

The planner will:
- Ask about team capacity and sprint duration
- Clarify MVP scope and feature priorities
- Present options for sequencing and dependencies
- Only generate plan when confident in breakdown

## Next Step

After sprint plan is complete: `/implement sprint-1` to start implementation
