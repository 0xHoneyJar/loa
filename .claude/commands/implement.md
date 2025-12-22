---
name: "implement"
version: "1.0.0"
description: |
  Execute sprint tasks with production-quality code and tests.
  Automatically checks for and addresses audit/review feedback before new work.

arguments:
  - name: "sprint_id"
    type: "string"
    pattern: "^sprint-[0-9]+$"
    required: true
    description: "Sprint to implement (e.g., sprint-1)"
    examples: ["sprint-1", "sprint-2", "sprint-10"]

agent: "implementing-tasks"
agent_path: "skills/implementing-tasks/"

context_files:
  - path: "loa-grimoire/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and MCP tools"
  - path: "loa-grimoire/prd.md"
    required: true
    purpose: "Product requirements for grounding"
  - path: "loa-grimoire/sdd.md"
    required: true
    purpose: "Architecture decisions"
  - path: "loa-grimoire/sprint.md"
    required: true
    purpose: "Sprint tasks and acceptance criteria"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/auditor-sprint-feedback.md"
    required: false
    priority: 1
    purpose: "Security audit feedback (checked FIRST)"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    required: false
    priority: 2
    purpose: "Senior lead feedback"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "pattern_match"
    value: "$ARGUMENTS.sprint_id"
    pattern: "^sprint-[0-9]+$"
    error: "Invalid sprint ID. Expected format: sprint-N (e.g., sprint-1)"

  - check: "file_exists"
    path: "loa-grimoire/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."

  - check: "file_exists"
    path: "loa-grimoire/sdd.md"
    error: "SDD not found. Run /architect first."

  - check: "file_exists"
    path: "loa-grimoire/sprint.md"
    error: "Sprint plan not found. Run /sprint-plan first."

  - check: "content_contains"
    path: "loa-grimoire/sprint.md"
    pattern: "$ARGUMENTS.sprint_id"
    error: "Sprint $ARGUMENTS.sprint_id not found in sprint.md"

  - check: "file_not_exists"
    path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/COMPLETED"
    error: "Sprint $ARGUMENTS.sprint_id is already COMPLETED."

outputs:
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/"
    type: "directory"
    description: "Sprint A2A directory (created if needed)"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/reviewer.md"
    type: "file"
    description: "Implementation report for senior review"
  - path: "loa-grimoire/a2a/index.md"
    type: "file"
    description: "Sprint index (updated)"
  - path: "app/src/**/*"
    type: "glob"
    description: "Implementation code and tests"

mode:
  default: "foreground"
  allow_background: true
---

# Implement Sprint

## Purpose

Execute assigned sprint tasks with production-quality code, comprehensive tests, and detailed implementation report for senior review.

## Invocation

```
/implement sprint-1
/implement sprint-1 background
```

## Agent

Launches `implementing-tasks` from `skills/implementing-tasks/`.

See: `skills/implementing-tasks/SKILL.md` for full workflow details.

## Workflow

1. **Pre-flight**: Validate sprint ID, check setup, verify prerequisites
2. **Directory Setup**: Create `loa-grimoire/a2a/{sprint_id}/` if needed
3. **Feedback Check**: Audit feedback (priority 1) → Engineer feedback (priority 2)
4. **Context Loading**: Read PRD, SDD, sprint plan for requirements
5. **Implementation**: Execute tasks with production-quality code and tests
6. **Report Generation**: Create `reviewer.md` with full implementation details
7. **Index Update**: Update `loa-grimoire/a2a/index.md` with sprint status
8. **Analytics**: Update usage metrics (THJ users only)

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `sprint_id` | Which sprint to implement (e.g., `sprint-1`) | Yes |
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/a2a/{sprint_id}/reviewer.md` | Implementation report |
| `loa-grimoire/a2a/index.md` | Updated sprint index |
| `app/src/**/*` | Implementation code and tests |

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Loa setup has not been completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "Invalid sprint ID" | Wrong format | Use `sprint-N` format |
| "PRD not found" | Missing prd.md | Run `/plan-and-analyze` first |
| "SDD not found" | Missing sdd.md | Run `/architect` first |
| "Sprint plan not found" | Missing sprint.md | Run `/sprint-plan` first |
| "Sprint not found in sprint.md" | Sprint doesn't exist | Verify sprint number |
| "Sprint is already COMPLETED" | COMPLETED marker exists | Move to next sprint |

## Feedback Loop

```
/implement sprint-N
      ↓
[reviewer.md created]
      ↓
/review-sprint sprint-N
      ↓
[feedback or approval]
      ↓
If feedback: /implement sprint-N (addresses feedback)
If approved: /audit-sprint sprint-N
```
