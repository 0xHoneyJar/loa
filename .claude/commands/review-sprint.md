---
name: "review-sprint"
version: "1.0.0"
description: |
  Validate sprint implementation against acceptance criteria.
  Reviews actual code, not just reports. Quality gate before security audit.

arguments:
  - name: "sprint_id"
    type: "string"
    pattern: "^sprint-[0-9]+$"
    required: true
    description: "Sprint to review (e.g., sprint-1)"
    examples: ["sprint-1", "sprint-2", "sprint-10"]

agent: "reviewing-code"
agent_path: "skills/reviewing-code/"

context_files:
  - path: "loa-grimoire/prd.md"
    required: true
    purpose: "Product requirements for validation"
  - path: "loa-grimoire/sdd.md"
    required: true
    purpose: "Architecture decisions for alignment check"
  - path: "loa-grimoire/sprint.md"
    required: true
    purpose: "Sprint tasks and acceptance criteria"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/reviewer.md"
    required: true
    purpose: "Engineer's implementation report"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    required: false
    purpose: "Previous feedback to verify addressed"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "pattern_match"
    value: "$ARGUMENTS.sprint_id"
    pattern: "^sprint-[0-9]+$"
    error: "Invalid sprint ID. Expected format: sprint-N (e.g., sprint-1)"

  - check: "directory_exists"
    path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id"
    error: "Sprint directory not found. Run /implement $ARGUMENTS.sprint_id first."

  - check: "file_exists"
    path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/reviewer.md"
    error: "No implementation report found. Run /implement $ARGUMENTS.sprint_id first."

  - check: "file_not_exists"
    path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/COMPLETED"
    error: "Sprint $ARGUMENTS.sprint_id is already COMPLETED. No review needed."

outputs:
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    type: "file"
    description: "Review feedback or approval ('All good')"
  - path: "loa-grimoire/sprint.md"
    type: "file"
    description: "Sprint plan (checkmarks added on approval)"
  - path: "loa-grimoire/a2a/index.md"
    type: "file"
    description: "Sprint index (status updated)"

mode:
  default: "foreground"
  allow_background: true
---

# Review Sprint

## Purpose

Validate sprint implementation against acceptance criteria as the Senior Technical Lead. Reviews actual code quality, not just the report. Quality gate before security audit.

## Invocation

```
/review-sprint sprint-1
/review-sprint sprint-1 background
```

## Agent

Launches `reviewing-code` from `skills/reviewing-code/`.

See: `skills/reviewing-code/SKILL.md` for full workflow details.

## Workflow

1. **Pre-flight**: Validate sprint ID, check prerequisites
2. **Context Loading**: Read PRD, SDD, sprint plan, implementation report
3. **Code Review**: Read actual code files (not just trust the report)
4. **Feedback Check**: Verify previous feedback items were addressed
5. **Decision**: Approve or request changes
6. **Output**: Write feedback or "All good" to `engineer-feedback.md`
7. **Analytics**: Update usage metrics (THJ users only)

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `sprint_id` | Which sprint to review (e.g., `sprint-1`) | Yes |
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/a2a/{sprint_id}/engineer-feedback.md` | Feedback or "All good" |
| `loa-grimoire/sprint.md` | Updated with checkmarks on approval |
| `loa-grimoire/a2a/index.md` | Updated sprint status |

## Decision Outcomes

### Approval ("All good")

When implementation meets all standards:
- Writes "All good" to `engineer-feedback.md`
- Updates `sprint.md` with checkmarks
- Sets sprint status to `REVIEW_APPROVED`
- Next step: `/audit-sprint sprint-N`

### Changes Required

When issues are found:
- Writes detailed feedback to `engineer-feedback.md`
- Includes file paths, line numbers, fixes
- Sprint status remains `IN_PROGRESS`
- Next step: `/implement sprint-N` (to address feedback)

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Loa setup has not been completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "Invalid sprint ID" | Wrong format | Use `sprint-N` format |
| "Sprint directory not found" | No A2A dir | Run `/implement` first |
| "No implementation report found" | Missing reviewer.md | Run `/implement` first |
| "Sprint is already COMPLETED" | COMPLETED marker exists | No review needed |

## Review Standards

The reviewer checks for:
- Sprint task completeness
- Acceptance criteria fulfillment
- Code quality and maintainability
- Comprehensive test coverage
- Security vulnerabilities
- Performance issues
- Architecture alignment
- Previous feedback resolution
