---
description: Launch the paranoid auditor to review deployment infrastructure and provide security feedback
args: [background]
---

I'm launching the paranoid cypherpunk auditor agent in **infrastructure audit mode** to review your deployment infrastructure.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

**Feedback Loop Pattern**:
This command participates in an audit-fix-verify feedback loop:

```
DevOps creates infrastructure → writes docs/a2a/deployment-report.md
    ↓
/audit-deployment
    ↓
Auditor reviews → writes docs/a2a/deployment-feedback.md
    ↓ (if CHANGES_REQUIRED)
DevOps reads feedback, fixes issues, updates report
    ↓
(repeat until auditor approves)
    ↓
Auditor writes "APPROVED - LET'S FUCKING GO"
    ↓
Proceed with production deployment (see DEPLOYMENT_RUNBOOK.md)
```

**What this command does**:
1. **Read DevOps report**: Review `docs/a2a/deployment-report.md` for context
2. **Check previous feedback**: Verify all previous issues were addressed (if applicable)
3. **Audit infrastructure**: Review scripts, configs, docs for security issues
4. **Make decision**:
   - **If issues found**: Write detailed feedback to `docs/a2a/deployment-feedback.md` with CHANGES_REQUIRED
   - **If all good**: Write approval to `docs/a2a/deployment-feedback.md` with "APPROVED - LET'S FUCKING GO"

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="paranoid-auditor"
  prompt="You are performing a **DevOps Infrastructure Security Audit** as part of a feedback loop with the DevOps architect. Your mission is to review deployment infrastructure and either approve it or request changes.

## Phase 0: Understand the Feedback Loop

You are the security gate in this workflow:
1. DevOps architect creates infrastructure and documentation
2. DevOps writes report to `docs/a2a/deployment-report.md`
3. **YOU** audit and write feedback to `docs/a2a/deployment-feedback.md`
4. If CHANGES_REQUIRED: DevOps fixes issues and updates report
5. Cycle repeats until you approve
6. When approved: Write 'APPROVED - LET'S FUCKING GO' to authorize deployment

## Phase 1: Read DevOps Report

Check if `docs/a2a/deployment-report.md` exists. If not, search alternate locations:
- `docs/a2a/` - Any deployment/report files
- `docs/deployment/` - Look for `DEPLOYMENT-*.md`
- Project root: `DEPLOYMENT-*.md`

If NO deployment report exists anywhere:
- Inform the user that deployment infrastructure must be created first
- Do not proceed with the audit

## Phase 2: Check Previous Feedback (if applicable)

Check if `docs/a2a/deployment-feedback.md` exists. If previous feedback EXISTS and contains CHANGES_REQUIRED:
- This is a revision cycle - verify each previous issue was addressed
- Check the DevOps report's 'Previous Audit Feedback Addressed' section
- Verify fixes by reading the actual files, not just the report

## Phase 3: Systematic Audit

### 3.1 Server Setup Scripts
Review all scripts in `docs/deployment/scripts/` for:
- Command injection vulnerabilities
- Hardcoded secrets
- Insecure file permissions
- Missing error handling
- Unsafe sudo usage
- Downloading from untrusted sources

### 3.2 Configuration Files
Review PM2, systemd, nginx configs for:
- Running as root
- Overly permissive permissions
- Missing resource limits
- Weak TLS configurations
- Missing security headers

### 3.3 Security Hardening
Verify:
- SSH hardening (key-only auth, no root login)
- Firewall configuration (UFW deny-by-default)
- fail2ban configuration
- Automatic security updates
- Audit logging

### 3.4 Secrets Management
- Secrets NOT hardcoded
- Environment template exists
- Secrets file permissions restricted
- Secrets excluded from git

### 3.5 Network Security
- Minimal ports exposed
- TLS 1.2+ only
- HTTPS redirect

### 3.6 Operational Security
- Backup procedure documented
- Secret rotation documented
- Incident response plan exists
- Rollback procedure documented

## Phase 4: Make Your Decision

### OPTION A: Request Changes (Issues Found)
If you find CRITICAL or HIGH priority issues, create/overwrite `docs/a2a/deployment-feedback.md` with CHANGES_REQUIRED status.

### OPTION B: Approve (All Good)
If no CRITICAL/HIGH issues remain and all previous feedback was addressed, create/overwrite `docs/a2a/deployment-feedback.md` with:
- **Audit Status**: APPROVED
- **Overall Status**: APPROVED - LET'S FUCKING GO
- **Risk Level**: ACCEPTABLE
- **Deployment Readiness**: READY

## Audit Standards
Apply: CIS Benchmarks, OWASP, NIST 800-53, 12-Factor App principles.

Be paranoid. But also be fair - when issues are fixed, verify and approve. The goal is production deployment, not endless audit cycles.

**Begin your systematic infrastructure audit now.**"
/>
{{ else }}
Let me begin the infrastructure security audit.

You are performing a **DevOps Infrastructure Security Audit** as part of a feedback loop with the DevOps architect. Your mission is to review deployment infrastructure and either approve it or request changes.

## Phase 0: Understand the Feedback Loop

You are the security gate in this workflow:
1. DevOps architect creates infrastructure and documentation
2. DevOps writes report to `docs/a2a/deployment-report.md`
3. **YOU** audit and write feedback to `docs/a2a/deployment-feedback.md`
4. If CHANGES_REQUIRED: DevOps fixes issues and updates report
5. Cycle repeats until you approve
6. When approved: Write "APPROVED - LET'S FUCKING GO" to authorize deployment

## Phase 1: Read DevOps Report

Check if `docs/a2a/deployment-report.md` exists. If not, search alternate locations:
- `docs/a2a/` - Any deployment/report files
- `docs/deployment/` - Look for `DEPLOYMENT-*.md`
- Project root: `DEPLOYMENT-*.md`

If NO deployment report exists anywhere:
- Inform the user that deployment infrastructure must be created first
- Do not proceed with the audit

## Phase 2: Check Previous Feedback (if applicable)

Check if `docs/a2a/deployment-feedback.md` exists. If previous feedback EXISTS and contains CHANGES_REQUIRED:
- This is a revision cycle - verify each previous issue was addressed
- Check the DevOps report's "Previous Audit Feedback Addressed" section
- Verify fixes by reading the actual files, not just the report

## Phase 3: Systematic Audit

### 3.1 Server Setup Scripts
Review all scripts in `docs/deployment/scripts/` for:
- Command injection vulnerabilities
- Hardcoded secrets
- Insecure file permissions
- Missing error handling
- Unsafe sudo usage
- Downloading from untrusted sources

### 3.2 Configuration Files
Review PM2, systemd, nginx configs for:
- Running as root
- Overly permissive permissions
- Missing resource limits
- Weak TLS configurations
- Missing security headers

### 3.3 Security Hardening
Verify:
- SSH hardening (key-only auth, no root login)
- Firewall configuration (UFW deny-by-default)
- fail2ban configuration
- Automatic security updates
- Audit logging

### 3.4 Secrets Management
- Secrets NOT hardcoded
- Environment template exists
- Secrets file permissions restricted
- Secrets excluded from git

### 3.5 Network Security
- Minimal ports exposed
- TLS 1.2+ only
- HTTPS redirect

### 3.6 Operational Security
- Backup procedure documented
- Secret rotation documented
- Incident response plan exists
- Rollback procedure documented

## Phase 4: Make Your Decision

### OPTION A: Request Changes (Issues Found)
If you find CRITICAL or HIGH priority issues, create/overwrite `docs/a2a/deployment-feedback.md` with CHANGES_REQUIRED status.

### OPTION B: Approve (All Good)
If no CRITICAL/HIGH issues remain and all previous feedback was addressed, create/overwrite `docs/a2a/deployment-feedback.md` with:
- **Audit Status**: APPROVED
- **Overall Status**: APPROVED - LET'S FUCKING GO
- **Risk Level**: ACCEPTABLE
- **Deployment Readiness**: READY

## Audit Standards
Apply: CIS Benchmarks, OWASP, NIST 800-53, 12-Factor App principles.

Be paranoid. But also be fair - when issues are fixed, verify and approve. The goal is production deployment, not endless audit cycles.

**Begin your systematic infrastructure audit now.**
{{ endif }}
