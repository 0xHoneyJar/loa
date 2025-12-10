# Organizational Deployment Guide

This guide covers deploying agentic-base to integrate with your organization's tools (Discord, Linear, Google Docs) and deploying to production servers.

> **Note**: This is an optional extension. The core agentic-base framework works standalone. Use this guide when you need multi-team integration or server deployment.

## Overview

The organizational deployment workflow consists of four phases:

```
Phase 0: Design Integration    → /integrate-org-workflow
Phase 0.5: Implement Integration → /implement-org-integration
Server Setup: Configure Server  → /setup-server
Security Audit: Review & Approve → /audit-deployment
Production Deploy: Go Live      → /deploy-go
```

## Quick Start

### Prerequisites

- Completed core workflow (PRD, SDD, Sprint) or integration-only deployment
- Server access (OVH, Hetzner, DigitalOcean, etc.) for production deployment
- API tokens for services you want to integrate (Discord, Linear, GitHub)

### Workflow

```bash
# 1. Design organizational integration
/integrate-org-workflow
# Answer discovery questions about your tools, teams, workflows
# Output: docs/integration-architecture.md, docs/tool-setup.md, docs/team-playbook.md

# 2. Implement the integration layer
/implement-org-integration
# Builds Discord bot, webhooks, sync scripts
# Output: devrel-integration/ with complete implementation

# 3. Set up production server
/setup-server
# Answer questions about server, services, security
# Output: docs/deployment/scripts/, docs/a2a/deployment-report.md

# 4. Security audit (feedback loop)
/audit-deployment
# Auditor reviews infrastructure
# Output: docs/a2a/deployment-feedback.md

# 5. Fix issues and re-audit (if needed)
/setup-server  # Fix feedback
/audit-deployment  # Re-audit

# 6. Deploy to production (after approval)
/deploy-go
# Execute deployment on server
```

## Available Commands

| Command | Purpose | Output |
|---------|---------|--------|
| `/integrate-org-workflow` | Design integration with org tools | `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md` |
| `/implement-org-integration` | Implement Discord bot, webhooks, scripts | `devrel-integration/` directory |
| `/setup-server` | Configure production server | `docs/deployment/scripts/`, `docs/a2a/deployment-report.md` |
| `/audit-deployment` | Security audit of deployment | `docs/a2a/deployment-feedback.md` |
| `/deploy-go` | Execute production deployment | Deployed infrastructure |

## Phase 0: Organizational Integration Design

**Command**: `/integrate-org-workflow`
**Agent**: `context-engineering-expert`

Design how agentic-base integrates with your organization's existing tools and workflows.

### When to Use

- Multi-team initiatives spanning departments
- Discussions happen in Discord/Slack
- Requirements documented in Google Docs/Notion
- Project tracking in Linear/Jira
- Multiple developers working concurrently

### What It Does

1. Asks targeted questions across 6 discovery phases:
   - Current Workflow Mapping (tools, roles, handoffs)
   - Pain Points & Bottlenecks (where context gets lost)
   - Integration Requirements (which tools, automation level)
   - Team Structure & Permissions (authority, access controls)
   - Data & Context Requirements (what info agents need)
   - Success Criteria & Constraints (goals, limitations)

2. Generates comprehensive documentation:
   - `docs/integration-architecture.md` - Architecture and data flow diagrams
   - `docs/tool-setup.md` - Configuration guide for APIs, webhooks, bots
   - `docs/team-playbook.md` - How teams use the integrated system
   - `docs/a2a/integration-context.md` - Context for downstream agents

### Common Integration Patterns

1. **Discord → Linear → Agentic-Base**: Team discusses in Discord, creates Linear initiative, triggers agent workflow
2. **Google Docs → Linear → Implementation**: Collaborative requirements doc → Linear project → agent implementation
3. **Multi-Team Orchestration**: Leadership initiative → multiple sub-projects → coordinated implementation
4. **Discord-Native**: Agents as bot team members, all workflow in Discord

## Phase 0.5: Integration Implementation

**Command**: `/implement-org-integration`
**Agent**: `devops-crypto-architect`

Implement the Discord bot, webhooks, sync scripts, and integration infrastructure.

### Prerequisites

Must have completed Phase 0 first:
- `docs/integration-architecture.md` exists
- `docs/tool-setup.md` exists
- `docs/team-playbook.md` exists

### What It Builds

- **Discord Bot**: Command handlers, event listeners, message formatting
- **Webhook Handlers**: Linear, GitHub, Vercel event processing
- **Cron Jobs**: Daily digests, scheduled tasks
- **Deployment Configs**: Docker, PM2, systemd
- **Monitoring**: Health checks, structured logging

### Output Structure

```
devrel-integration/
├── src/                  # Bot source code (TypeScript)
│   ├── bot.ts           # Discord bot entry point
│   ├── commands/        # Slash command handlers
│   ├── events/          # Event listeners
│   └── webhooks/        # Webhook handlers
├── config/              # Configuration files
├── secrets/             # .env templates (not secrets!)
├── Dockerfile           # Container build
├── docker-compose.yml   # Local development
├── ecosystem.config.js  # PM2 configuration
└── README.md            # Integration guide
```

## Deployment Feedback Loop

The deployment workflow uses a feedback loop between DevOps and Security Auditor:

```
/setup-server
    ↓
DevOps creates infrastructure → writes docs/a2a/deployment-report.md
    ↓
/audit-deployment
    ↓
Auditor reviews → writes docs/a2a/deployment-feedback.md
    ↓
├── If CHANGES_REQUIRED:
│   ↓
│   /setup-server (again)
│   ↓
│   DevOps reads feedback, fixes issues
│   ↓
│   (repeat until approved)
│
└── If "APPROVED - LET'S FUCKING GO":
    ↓
    /deploy-go
    ↓
    Execute production deployment
```

### Server Setup (`/setup-server`)

**Agent**: `devops-crypto-architect`

Configures a bare metal or VPS server for the DevRel integration application.

**Asks about**:
- Server access (IP, SSH user, authentication)
- Services to deploy (Discord bot, webhooks, cron jobs)
- Security preferences (firewall, fail2ban, SSL)
- Monitoring requirements

**Generates**:
- `docs/deployment/scripts/01-initial-setup.sh`
- `docs/deployment/scripts/02-security-hardening.sh`
- `docs/deployment/scripts/03-install-dependencies.sh`
- `docs/deployment/scripts/04-deploy-app.sh`
- `docs/deployment/scripts/05-setup-monitoring.sh` (optional)
- `docs/deployment/scripts/06-setup-ssl.sh` (optional)
- `docs/deployment/server-setup-guide.md`
- `docs/deployment/runbooks/server-operations.md`
- `docs/deployment/security-checklist.md`
- `docs/deployment/verification-checklist.md`
- `docs/a2a/deployment-report.md`

### Security Audit (`/audit-deployment`)

**Agent**: `paranoid-auditor`

Reviews deployment infrastructure before production deployment.

**Audits**:
- Server setup scripts for security vulnerabilities
- Deployment configurations and procedures
- Infrastructure security hardening (SSH, firewall, fail2ban)
- Secrets management and credential handling
- PM2/systemd/nginx configurations
- Backup and disaster recovery procedures

**Verdicts**:
- **CHANGES_REQUIRED**: Issues found, feedback written to `docs/a2a/deployment-feedback.md`
- **APPROVED - LET'S FUCKING GO**: Ready for production

### Deploy (`/deploy-go`)

**Agent**: `devops-crypto-architect`

Executes production deployment after security audit approval.

**Prerequisites**:
- `docs/a2a/deployment-feedback.md` must contain "APPROVED - LET'S FUCKING GO"
- Will refuse to proceed without approval

**What It Does**:
1. Verifies security approval
2. Guides deployment execution step by step
3. Runs verification checklist
4. Documents deployment completion

## A2A Communication Files

The deployment workflow uses these agent-to-agent communication files:

| File | Created By | Read By | Purpose |
|------|------------|---------|---------|
| `docs/a2a/deployment-report.md` | DevOps | Auditor | Infrastructure report |
| `docs/a2a/deployment-feedback.md` | Auditor | DevOps, deploy-go | Security feedback/approval |

## Example: Full Deployment Workflow

```bash
# 1. Design organizational integration
/integrate-org-workflow

# Agent asks:
# - What tools does your team use? (Discord, Linear, Google Docs)
# - How do decisions get made and communicated?
# - What are your biggest workflow pain points?
# - Who needs access to what information?

# Output: Integration architecture documentation

# 2. Implement integration layer
/implement-org-integration

# Agent builds Discord bot, webhooks, deployment configs
# Output: devrel-integration/ with complete implementation

# 3. Configure production server
/setup-server

# Agent asks:
# - Server IP and SSH credentials?
# - Which services to deploy?
# - Domain name for SSL?
# - Monitoring preferences?

# Agent generates:
# - Setup scripts in docs/deployment/scripts/
# - Deployment report in docs/a2a/deployment-report.md

# 4. Security audit
/audit-deployment

# Agent reviews all scripts and configs
# Agent writes feedback to docs/a2a/deployment-feedback.md

# If CHANGES_REQUIRED:
# 5. Fix issues
/setup-server
# Agent reads feedback, fixes issues, updates report

# 6. Re-audit
/audit-deployment
# Agent verifies fixes

# When APPROVED:
# 7. Deploy to production
/deploy-go

# Agent guides you through:
# - Transferring scripts to server
# - Executing setup scripts in order
# - Verifying each step
# - Final deployment verification
```

## Security Best Practices

### Server Hardening

The setup scripts implement:
- SSH key-only authentication (no password auth)
- Root login disabled
- fail2ban for brute-force protection
- UFW firewall with deny-by-default
- Automatic security updates
- Audit logging

### Secrets Management

- Never commit secrets to git
- Use `.env.local` files excluded from version control
- Environment templates (`.env.local.example`) document required vars
- Secrets transferred securely (not via git)
- Rotation procedures documented

### Network Security

- Minimal port exposure
- Internal services not exposed externally
- TLS 1.2+ only
- HTTPS redirect for all traffic
- Security headers configured

## Troubleshooting

### Audit Loop Not Completing

If the audit keeps requesting changes:
1. Read `docs/a2a/deployment-feedback.md` carefully
2. Address ALL critical and high priority issues
3. Update `docs/a2a/deployment-report.md` with fixes
4. Re-run `/audit-deployment`

### `/deploy-go` Refusing to Proceed

The command requires explicit audit approval:
1. Check `docs/a2a/deployment-feedback.md` exists
2. Verify it contains "APPROVED - LET'S FUCKING GO"
3. If not, run `/audit-deployment` first

### Integration Not Working

1. Verify all API tokens are correctly set in `.env.local`
2. Check Discord bot has required permissions
3. Review webhook signatures are configured
4. Check logs: `pm2 logs devrel-bot`

## Documentation

- **[DEPLOY-ORG-PROCESS.md](DEPLOY-ORG-PROCESS.md)** - Detailed workflow documentation
- **[CLAUDE.md](CLAUDE.md)** - Guidance for Claude Code instances
- **[README.md](README.md)** - Core framework documentation

## Related Files

```
docs/
├── integration-architecture.md  # Integration design (Phase 0)
├── tool-setup.md               # Tool configuration guide (Phase 0)
├── team-playbook.md            # Team usage guide (Phase 0)
├── a2a/
│   ├── integration-context.md  # Context for downstream agents
│   ├── deployment-report.md    # DevOps infrastructure report
│   └── deployment-feedback.md  # Security audit feedback
└── deployment/
    ├── scripts/                # Server setup scripts
    ├── runbooks/               # Operational procedures
    ├── server-setup-guide.md   # Setup instructions
    ├── security-checklist.md   # Security verification
    └── verification-checklist.md # Deployment verification

devrel-integration/             # Discord bot & integration code
├── src/                        # TypeScript source
├── config/                     # Configuration files
├── secrets/                    # .env templates
└── ecosystem.config.js         # PM2 config
```
