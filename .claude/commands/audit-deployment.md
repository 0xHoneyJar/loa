---
name: "audit-deployment"
version: "1.0.0"
description: |
  Security audit of deployment infrastructure.
  Reviews server setup, configs, hardening, secrets management.

arguments: []

agent: "auditing-security"
agent_path: "skills/auditing-security/"

context_files:
  - path: "loa-grimoire/a2a/deployment-report.md"
    required: false
    purpose: "DevOps deployment report"
  - path: "loa-grimoire/deployment/**/*"
    required: false
    purpose: "Deployment scripts and configs"
  - path: "loa-grimoire/a2a/deployment-feedback.md"
    required: false
    purpose: "Previous audit feedback"

pre_flight: []

outputs:
  - path: "loa-grimoire/a2a/deployment-feedback.md"
    type: "file"
    description: "Audit feedback or 'APPROVED - LET'S FUCKING GO'"

mode:
  default: "foreground"
  allow_background: true
---

# Audit Deployment Infrastructure

## Purpose

Security audit of deployment infrastructure as part of the DevOps feedback loop. Reviews server setup scripts, configurations, security hardening, and operational documentation.

## Invocation

```
/audit-deployment
/audit-deployment background
```

## Agent

Launches `auditing-security` from `skills/auditing-security/`.

See: `skills/auditing-security/SKILL.md` for full workflow details.

## Feedback Loop

```
DevOps creates infrastructure
      ↓
Writes loa-grimoire/a2a/deployment-report.md
      ↓
/audit-deployment
      ↓
Auditor writes loa-grimoire/a2a/deployment-feedback.md
      ↓
CHANGES_REQUIRED          APPROVED
      ↓                       ↓
DevOps fixes issues    Proceed to deployment
      ↓
(repeat until approved)
```

## Workflow

1. **Read DevOps Report**: Review `loa-grimoire/a2a/deployment-report.md`
2. **Check Previous Feedback**: Verify previous issues were addressed
3. **Audit Infrastructure**: Review scripts, configs, docs
4. **Decision**: Approve or request changes
5. **Output**: Write feedback to `loa-grimoire/a2a/deployment-feedback.md`

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/a2a/deployment-feedback.md` | Audit results |

## Audit Checklist

### Server Setup Scripts
- Command injection vulnerabilities
- Hardcoded secrets
- Insecure file permissions
- Missing error handling
- Unsafe sudo usage
- Untrusted download sources

### Configuration Files
- Running as root
- Overly permissive permissions
- Missing resource limits
- Weak TLS configurations
- Missing security headers

### Security Hardening
- SSH hardening (key-only auth, no root login)
- Firewall configuration (UFW deny-by-default)
- fail2ban configuration
- Automatic security updates
- Audit logging

### Secrets Management
- Secrets NOT hardcoded
- Environment template exists
- Secrets file permissions restricted
- Secrets excluded from git

### Network Security
- Minimal ports exposed
- TLS 1.2+ only
- HTTPS redirect

### Operational Security
- Backup procedure documented
- Secret rotation documented
- Incident response plan exists
- Rollback procedure documented

## Decision Outcomes

### Approval ("APPROVED - LET'S FUCKING GO")

When infrastructure passes audit:
- Writes approval to `deployment-feedback.md`
- Deployment readiness: READY
- Next step: Production deployment

### Changes Required ("CHANGES_REQUIRED")

When issues found:
- Writes detailed feedback to `deployment-feedback.md`
- Includes severity and remediation steps
- Next step: DevOps fixes issues
