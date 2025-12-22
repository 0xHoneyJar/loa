---
name: "audit-sprint"
version: "1.0.0"
description: |
  Security and quality audit of sprint implementation.
  Final gate before sprint completion. Creates COMPLETED marker on approval.

arguments:
  - name: "sprint_id"
    type: "string"
    pattern: "^sprint-[0-9]+$"
    required: true
    description: "Sprint to audit (e.g., sprint-1)"
    examples: ["sprint-1", "sprint-2", "sprint-10"]

agent: "auditing-security"
agent_path: "skills/auditing-security/"

context_files:
  - path: "loa-grimoire/prd.md"
    required: true
    purpose: "Product requirements for context"
  - path: "loa-grimoire/sdd.md"
    required: true
    purpose: "Architecture decisions for alignment"
  - path: "loa-grimoire/sprint.md"
    required: true
    purpose: "Sprint tasks and acceptance criteria"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/reviewer.md"
    required: true
    purpose: "Engineer's implementation report"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    required: true
    purpose: "Senior lead approval verification"

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

  - check: "file_exists"
    path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    error: "Sprint has not been reviewed. Run /review-sprint $ARGUMENTS.sprint_id first."

  - check: "content_contains"
    path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/engineer-feedback.md"
    pattern: "All good"
    error: "Sprint has not been approved by senior lead. Run /review-sprint $ARGUMENTS.sprint_id first."

  - check: "file_not_exists"
    path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/COMPLETED"
    error: "Sprint $ARGUMENTS.sprint_id is already COMPLETED. No audit needed."

outputs:
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/auditor-sprint-feedback.md"
    type: "file"
    description: "Audit feedback or 'APPROVED - LETS FUCKING GO'"
  - path: "loa-grimoire/a2a/$ARGUMENTS.sprint_id/COMPLETED"
    type: "file"
    description: "Completion marker (created on approval)"
  - path: "loa-grimoire/a2a/index.md"
    type: "file"
    description: "Sprint index (status updated)"

mode:
  default: "foreground"
  allow_background: true
---

# Audit Sprint

## Purpose

Security and quality audit of sprint implementation as the Paranoid Cypherpunk Auditor. Final gate before sprint completion. Runs AFTER senior lead approval.

## Invocation

```
/audit-sprint sprint-1
/audit-sprint sprint-1 background
```

## Agent

Launches `auditing-security` from `skills/auditing-security/`.

See: `skills/auditing-security/SKILL.md` for full workflow details.

## Prerequisites

- Sprint tasks implemented (`/implement`)
- Senior lead approved with "All good" (`/review-sprint`)
- Not already completed (no COMPLETED marker)

## Workflow

1. **Pre-flight**: Validate sprint ID, verify senior approval
2. **Context Loading**: Read PRD, SDD, sprint plan, implementation report
3. **Code Audit**: Read actual code files for security review
4. **Security Checklist**: OWASP Top 10, secrets, auth, input validation
5. **Decision**: Approve or require changes
6. **Output**: Write audit feedback or approval
7. **Completion**: Create COMPLETED marker on approval
8. **Analytics**: Update usage metrics (THJ users only)

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `sprint_id` | Which sprint to audit (e.g., `sprint-1`) | Yes |
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/a2a/{sprint_id}/auditor-sprint-feedback.md` | Audit results |
| `loa-grimoire/a2a/{sprint_id}/COMPLETED` | Completion marker |
| `loa-grimoire/a2a/index.md` | Updated sprint status |

## Decision Outcomes

### Approval ("APPROVED - LETS FUCKING GO")

When security audit passes:
- Writes approval to `auditor-sprint-feedback.md`
- Creates `COMPLETED` marker file
- Sets sprint status to `COMPLETED`
- Next step: Move to next sprint or deployment

### Changes Required ("CHANGES_REQUIRED")

When security issues found:
- Writes detailed findings to `auditor-sprint-feedback.md`
- Includes severity (CRITICAL/HIGH/MEDIUM/LOW)
- Sets sprint status to `AUDIT_CHANGES_REQUIRED`
- Next step: `/implement sprint-N` (to fix issues)

## Security Checklist

The auditor reviews:
- **Secrets**: No hardcoded credentials, proper env vars
- **Auth/Authz**: Proper access control, no privilege escalation
- **Input Validation**: No injection vulnerabilities
- **Data Privacy**: No PII leaks, proper encryption
- **API Security**: Rate limiting, CORS, validation
- **Error Handling**: No info disclosure, proper logging
- **Code Quality**: No obvious bugs, tested error paths

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Loa setup has not been completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "Invalid sprint ID" | Wrong format | Use `sprint-N` format |
| "Sprint directory not found" | No A2A dir | Run `/implement` first |
| "No implementation report found" | Missing reviewer.md | Run `/implement` first |
| "Sprint has not been reviewed" | Missing engineer-feedback.md | Run `/review-sprint` first |
| "Sprint has not been approved" | No "All good" | Get senior approval first |
| "Sprint is already COMPLETED" | COMPLETED marker exists | No audit needed |

## Feedback Loop

```
/audit-sprint sprint-N
      ↓
[Security audit]
      ↓
CHANGES_REQUIRED          APPROVED
      ↓                       ↓
/implement sprint-N    [COMPLETED marker]
      ↓                       ↓
/audit-sprint sprint-N   Next sprint
```
