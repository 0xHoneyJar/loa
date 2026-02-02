# Feedback Loops Protocol

This protocol defines the three feedback loops used for quality assurance in the Loa framework.

## Overview

The framework uses three feedback loops:

1. **Implementation Feedback Loop** (Phases 4-5) - Code quality
2. **Sprint Security Audit Loop** (Phase 5.5) - Security review
3. **Deployment Feedback Loop** - Infrastructure security

## 1. Implementation Feedback Loop (Phases 4-5)

### Flow

```
Engineer → Senior Lead → Engineer → ... → Approval
```

### Files

| File | Created By | Purpose |
|------|------------|---------|
| `grimoires/loa/a2a/sprint-N/reviewer.md` | `implementing-tasks` | Implementation report |
| `grimoires/loa/a2a/sprint-N/engineer-feedback.md` | `reviewing-code` | Code review feedback |

### Process

1. **Engineer implements** → generates `reviewer.md`
2. **Senior lead reviews** → writes feedback or "All good" to `engineer-feedback.md`
3. **If feedback**: Engineer reads, fixes issues, regenerates report
4. **Repeat** until "All good"

### Approval Marker

When approved, `engineer-feedback.md` contains: **"All good"**

## 2. Sprint Security Audit Loop (Phase 5.5)

### Prerequisites

- Sprint must have "All good" in `engineer-feedback.md`

### Flow

```
Engineer → Security Auditor → Engineer → ... → Security Approval
```

### Files

| File | Created By | Purpose |
|------|------------|---------|
| `grimoires/loa/a2a/sprint-N/reviewer.md` | `implementing-tasks` | Implementation context |
| `grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md` | `auditing-security` | Security feedback |
| `grimoires/loa/a2a/sprint-N/COMPLETED` | `auditing-security` | Completion marker |

### Process

1. **Auditor reviews** implemented code for security vulnerabilities
2. **Auditor writes** verdict to `auditor-sprint-feedback.md`:
   - **CHANGES_REQUIRED** - Security issues found with detailed feedback
   - **APPROVED - LETS FUCKING GO** - No critical/high issues
3. **If changes required**: Engineer reads audit feedback FIRST on next `/implement`
4. **Repeat** until approved
5. **On approval**: Creates `COMPLETED` marker file

### Priority

- Audit feedback has **HIGHEST priority** (checked before engineer feedback)
- Security issues take precedence over code review feedback

### Security Checklist

- No hardcoded secrets or credentials
- Proper authentication and authorization
- Comprehensive input validation
- No injection vulnerabilities (SQL, command, XSS)
- Secure API implementation
- Data privacy protected
- Dependencies secure (no known CVEs)

## 3. Deployment Feedback Loop

### Flow

```
DevOps → Security Auditor → DevOps → ... → Deployment Approval
```

### Files

| File | Created By | Purpose |
|------|------------|---------|
| `grimoires/loa/a2a/deployment-report.md` | `deploying-infrastructure` | Infrastructure report |
| `grimoires/loa/a2a/deployment-feedback.md` | `auditing-security` | Deployment audit feedback |

### Process

1. **DevOps creates** infrastructure → generates `deployment-report.md`
2. **Auditor reviews** via `/audit-deployment` → writes feedback
3. **Verdict**:
   - **CHANGES_REQUIRED** - Infrastructure security issues
   - **APPROVED - LET'S FUCKING GO** - Ready for production
4. **If changes required**: DevOps addresses feedback, regenerates report
5. **Repeat** until approved

## A2A Directory Structure

```
grimoires/loa/a2a/
├── index.md                         # Sprint audit trail index (auto-maintained)
├── integration-context.md           # Feedback configuration
├── trajectory/                      # v1.20.0: Guardrail and handoff logs
│   ├── guardrails-2026-02-03.jsonl  # Input guardrail events
│   └── ...
├── sprint-1/
│   ├── reviewer.md                  # Engineer implementation report
│   ├── engineer-feedback.md         # Senior lead feedback
│   ├── auditor-sprint-feedback.md   # Security audit feedback
│   └── COMPLETED                    # Completion marker (audit approval)
├── sprint-2/
│   └── ...
├── deployment-report.md             # DevOps infrastructure report
└── deployment-feedback.md           # Deployment security audit feedback
```

## Handoff Logging (v1.20.0)

When agents hand off work to each other, explicit handoff events are logged to trajectory.

### Logging Handoffs

Use `.claude/scripts/log-handoff.sh`:

```bash
# Log handoff from implementing-tasks to reviewing-code
log-handoff.sh --from implementing-tasks --to reviewing-code \
  --artifact grimoires/loa/a2a/sprint-1/reviewer.md \
  --context sprint_id --context task_list
```

### Handoff Event Format

```json
{
  "type": "handoff",
  "timestamp": "2026-02-03T10:35:00Z",
  "session_id": "abc123",
  "skill": "implementing-tasks",
  "action": "PROCEED",
  "from_agent": "implementing-tasks",
  "to_agent": "reviewing-code",
  "handoff_type": "file_based",
  "artifacts": [
    {"path": "grimoires/loa/a2a/sprint-1/reviewer.md", "size_bytes": 2048}
  ],
  "context_preserved": ["sprint_id", "task_list", "commit_hash"]
}
```

### When to Log Handoffs

| Transition | Artifacts | Context |
|------------|-----------|---------|
| Implement → Review | `reviewer.md` | sprint_id, task_list |
| Review → Audit | `engineer-feedback.md` | sprint_id, approval_status |
| Audit → Next Sprint | `COMPLETED` marker | sprint_id, audit_verdict |
| DevOps → Audit | `deployment-report.md` | environment, infra_type |

### Configuration

```yaml
# .loa.config.yaml
guardrails:
  logging:
    handoffs: true  # Enable handoff logging
```

## Complete Sprint Workflow

```
/implement sprint-1
    ↓
/review-sprint sprint-1
    ↓ (if feedback)
/implement sprint-1 ←──┐
    ↓ (if "All good") │
/audit-sprint sprint-1 │
    ↓ (if CHANGES_REQUIRED)
    └──────────────────┘
    ↓ (if APPROVED)
Creates COMPLETED marker
    ↓
Move to sprint-2 or deployment
```

## Feedback Document Structure

### Engineer Feedback (when issues found)

```markdown
## Overall Assessment
[Summary of review]

## Critical Issues (MUST FIX)
- **Issue**: [Description]
- **File**: `path/to/file.ts:42`
- **Required Fix**: [Specific fix]

## Non-Critical Improvements
- [Recommendations]

## Previous Feedback Status
- [x] Issue 1 - Fixed
- [ ] Issue 2 - Not addressed

## Next Steps
[Instructions for engineer]
```

### Security Audit Feedback (when issues found)

```markdown
## Overall Security Assessment
[Summary]

## CRITICAL Security Issues
- **Vulnerability**: [Name]
- **Severity**: CRITICAL
- **File**: `path/to/file.ts:42`
- **Impact**: [Security impact]
- **Remediation**: [Specific fix]

## HIGH Priority Issues
[...]

## Security Checklist Status
- [x] No hardcoded secrets
- [ ] Input validation comprehensive
[...]

## Next Steps
Address ALL CRITICAL and HIGH issues, then re-run /audit-sprint
```
