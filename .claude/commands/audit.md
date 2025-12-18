---
description: Launch the paranoid cypherpunk auditor agent to perform a rigorous security and quality audit of the integration work
args: [background]
---

I'm launching the paranoid cypherpunk auditor agent with 30+ years of professional experience across systems administration, DevOps, architecture, blockchain, cryptography, and AI.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="paranoid-auditor"
  prompt="Perform a comprehensive security and quality audit of the application codebase.

## Scope of Audit

Review the following systematically:

### Documentation
1. `docs/prd.md` - Product requirements
2. `docs/sdd.md` - System architecture and design
3. `docs/sprint.md` - Sprint plan and implementation status

### Implementation Code
1. `app/src/` - Application source code
2. `app/tests/` - Test files
3. Configuration files and environment handling

### Configuration
1. Configuration files in `app/config/` (if exists)
2. `.gitignore` patterns for secrets
3. Environment variable handling
4. Deployment procedures in `docs/deployment/`

## Focus Areas

Apply your systematic methodology covering:

1. **Security Audit** (Highest Priority)
   - Secrets management
   - Authentication & authorization
   - Input validation & injection vulnerabilities
   - Data privacy concerns
   - Supply chain security
   - API security
   - Infrastructure security

2. **Architecture Audit**
   - Threat modeling
   - Single points of failure
   - Complexity analysis
   - Scalability concerns
   - Vendor lock-in risks

3. **Code Quality Audit**
   - Error handling
   - Type safety
   - Code smells
   - Testing coverage
   - Documentation quality

4. **DevOps & Infrastructure Audit**
   - Deployment security
   - Monitoring & observability
   - Backup & recovery
   - Access control

## Deliverable

Provide a comprehensive audit report following your standard format:
- Executive summary with overall risk level
- Critical issues (fix immediately)
- High priority issues (fix before production)
- Medium and low priority issues
- Informational notes and best practices
- Positive findings
- Actionable recommendations
- Complete security checklist status
- Threat model summary

Be brutally honest. The team needs to know what's wrong before deploying to production.

**Begin your systematic audit now.**"
/>
{{ else }}
## Your Mission

Perform a comprehensive security and quality audit of the application codebase.

## Scope of Audit

Review the following systematically:

### Documentation
1. `docs/prd.md` - Product requirements
2. `docs/sdd.md` - System architecture and design
3. `docs/sprint.md` - Sprint plan and implementation status

### Implementation Code
1. `app/src/` - Application source code
2. `app/tests/` - Test files
3. Configuration files and environment handling

### Configuration
1. Configuration files in `app/config/` (if exists)
2. `.gitignore` patterns for secrets
3. Environment variable handling
4. Deployment procedures in `docs/deployment/`

## Focus Areas

Apply your systematic methodology covering:

1. **Security Audit** (Highest Priority)
   - Secrets management
   - Authentication & authorization
   - Input validation & injection vulnerabilities
   - Data privacy concerns
   - Supply chain security
   - API security
   - Infrastructure security

2. **Architecture Audit**
   - Threat modeling
   - Single points of failure
   - Complexity analysis
   - Scalability concerns
   - Vendor lock-in risks

3. **Code Quality Audit**
   - Error handling
   - Type safety
   - Code smells
   - Testing coverage
   - Documentation quality

4. **DevOps & Infrastructure Audit**
   - Deployment security
   - Monitoring & observability
   - Backup & recovery
   - Access control

## Deliverable

Provide a comprehensive audit report following your standard format:
- Executive summary with overall risk level
- Critical issues (fix immediately)
- High priority issues (fix before production)
- Medium and low priority issues
- Informational notes and best practices
- Positive findings
- Actionable recommendations
- Complete security checklist status
- Threat model summary

Be brutally honest. The team needs to know what's wrong before deploying to production.

**Begin your systematic audit now.**
{{ endif }}
