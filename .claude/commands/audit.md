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
  prompt="Perform a comprehensive security and quality audit of the agentic-base organizational integration that was just completed. The integration connects agentic-base with Discord, Linear, GitHub, and Vercel.

## Scope of Audit

Review the following deliverables systematically:

### Documentation
1. `docs/integration-architecture.md` - System architecture and design
2. `docs/tool-setup.md` - Setup and configuration guide
3. `docs/team-playbook.md` - Team usage guide
4. `docs/adoption-plan.md` - Rollout strategy

### Implementation Code
1. `integration/src/bot.ts` - Main Discord bot
2. `integration/src/handlers/feedbackCapture.ts` - Feedback capture handler
3. `integration/src/handlers/commands.ts` - Command handlers
4. `integration/src/services/linearService.ts` - Linear API integration
5. `integration/src/cron/dailyDigest.ts` - Daily digest cron job
6. `integration/src/utils/logger.ts` - Logging utility

### Configuration
1. Configuration templates in `integration/config/`
2. `.gitignore` patterns for secrets
3. Environment variable handling
4. Deployment procedures

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

## Special Considerations

This integration handles:
- Discord bot with message access (potential PII exposure)
- Linear API tokens (secret management critical)
- User-generated content from Discord (injection risk)
- Webhook integrations (signature verification needed)
- Multi-user notification preferences (authorization concerns)
- Cron jobs with API access (credential scope)

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

Perform a comprehensive security and quality audit of the agentic-base organizational integration that was just completed. The integration connects agentic-base with Discord, Linear, GitHub, and Vercel.

## Scope of Audit

Review the following deliverables systematically:

### Documentation
1. `docs/integration-architecture.md` - System architecture and design
2. `docs/tool-setup.md` - Setup and configuration guide
3. `docs/team-playbook.md` - Team usage guide
4. `docs/adoption-plan.md` - Rollout strategy

### Implementation Code
1. `integration/src/bot.ts` - Main Discord bot
2. `integration/src/handlers/feedbackCapture.ts` - Feedback capture handler
3. `integration/src/handlers/commands.ts` - Command handlers
4. `integration/src/services/linearService.ts` - Linear API integration
5. `integration/src/cron/dailyDigest.ts` - Daily digest cron job
6. `integration/src/utils/logger.ts` - Logging utility

### Configuration
1. Configuration templates in `integration/config/`
2. `.gitignore` patterns for secrets
3. Environment variable handling
4. Deployment procedures

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

## Special Considerations

This integration handles:
- Discord bot with message access (potential PII exposure)
- Linear API tokens (secret management critical)
- User-generated content from Discord (injection risk)
- Webhook integrations (signature verification needed)
- Multi-user notification preferences (authorization concerns)
- Cron jobs with API access (credential scope)

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
