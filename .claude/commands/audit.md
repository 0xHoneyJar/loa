---
name: "audit"
version: "1.0.0"
description: |
  Comprehensive security and quality audit of the application codebase.
  OWASP Top 10, secrets, architecture, code quality review.

arguments: []

agent: "auditing-security"
agent_path: "skills/auditing-security/"

context_files:
  - path: "loa-grimoire/prd.md"
    required: false
    purpose: "Product requirements for context"
  - path: "loa-grimoire/sdd.md"
    required: false
    purpose: "Architecture decisions for context"
  - path: "loa-grimoire/sprint.md"
    required: false
    purpose: "Sprint plan and implementation status"
  - path: "app/src/**/*"
    required: false
    purpose: "Application source code"
  - path: "app/tests/**/*"
    required: false
    purpose: "Test files"

pre_flight: []

outputs:
  - path: "SECURITY-AUDIT-REPORT.md"
    type: "file"
    description: "Comprehensive security audit report"

mode:
  default: "foreground"
  allow_background: true
---

# Audit Codebase

## Purpose

Comprehensive security and quality audit of the application codebase by the Paranoid Cypherpunk Auditor. Use before production deployment or after major code changes.

## Invocation

```
/audit
/audit background
```

## Agent

Launches `auditing-security` from `skills/auditing-security/`.

See: `skills/auditing-security/SKILL.md` for full workflow details.

## When to Use

- Before production deployment
- After major code changes or new integrations
- When implementing security-sensitive features (auth, payments, data handling)
- Periodically for ongoing projects
- When onboarding to assess existing codebase

## Workflow

1. **Documentation Review**: Read PRD, SDD, sprint plan for context
2. **Code Audit**: Review `app/src/` for security vulnerabilities
3. **Test Review**: Check `app/tests/` for coverage and quality
4. **Config Audit**: Review configuration and environment handling
5. **Report**: Generate `SECURITY-AUDIT-REPORT.md`

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `SECURITY-AUDIT-REPORT.md` | Comprehensive audit report |

## Focus Areas

### Security Audit (Highest Priority)
- Secrets management
- Authentication & authorization
- Input validation & injection vulnerabilities
- Data privacy concerns
- Supply chain security
- API security
- Infrastructure security

### Architecture Audit
- Threat modeling
- Single points of failure
- Complexity analysis
- Scalability concerns
- Vendor lock-in risks

### Code Quality Audit
- Error handling
- Type safety
- Code smells
- Testing coverage
- Documentation quality

### DevOps & Infrastructure Audit
- Deployment security
- Monitoring & observability
- Backup & recovery
- Access control

## Report Format

The audit report includes:
- Executive summary with overall risk level
- Critical issues (fix immediately)
- High priority issues (fix before production)
- Medium and low priority issues
- Informational notes and best practices
- Positive findings
- Actionable recommendations
- Complete security checklist status
- Threat model summary
