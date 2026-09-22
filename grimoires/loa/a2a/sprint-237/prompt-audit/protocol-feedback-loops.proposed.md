# Feedback Loops Protocol

This protocol defines the three feedback loops used for quality assurance in the Loa framework.

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

## Verdict Trailers and the Gate

Both feedback files end with a machine trailer, `<!-- LOA-VERDICT {json} -->`, as their last line
(gate, verdict, counts, optional `excluded` / `excluded_confirmed`). `golden-path.sh` and run mode
read the trailer, not the prose: a file with any `LOA…VERDICT` marker is sent to
`verdict-derive.sh`, which accepts only the exact canonical form and is fail-closed — an
inconsistent, malformed or unparseable trailer, a non-zero exit or a missing `jq` all read as
"not reviewed" / "not audited". The prose heuristic applies only to legacy files with no marker at
all. An audit implies review: with a trailer, `engineer-feedback.md` is re-derived too, and a review
`excluded > 0` passes only when the audit trailer's `excluded_confirmed` equals it.

## Handoff Logging

When `guardrails.logging.handoffs: true` in `.loa.config.yaml`, log each agent handoff to the trajectory with `.claude/scripts/log-handoff.sh --from <skill> --to <skill> --artifact <path> --context <key>…` — implement → review (`reviewer.md`; sprint_id, task_list), review → audit (`engineer-feedback.md`; sprint_id, approval_status), audit → next sprint (`COMPLETED`; sprint_id, audit_verdict), DevOps → audit (`deployment-report.md`; environment, infra_type). The script writes the handoff event record.

## Feedback Document Structure

The review and audit skills write their feedback from their own templates (`reviewing-code/resources/templates/review-feedback.md`, `auditing-security/resources/templates/audit-report.md`); both end with the trailer described above.
## Overall Assessment
[Summary of review]

## Changes Required
- **Issue**: [Description]
- **File**: `path/to/file.ts:42`
- **Required Fix**: [Specific fix]

## Observations
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
