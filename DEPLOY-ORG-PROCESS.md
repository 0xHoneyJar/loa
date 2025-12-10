# Organizational Deployment Process

This document provides detailed workflow documentation for deploying agentic-base with organizational tool integration and production server deployment.

## Table of Contents

- [Overview](#overview)
- [Agents](#agents)
- [Workflow](#workflow)
  - [Phase 0: Organizational Integration Design](#phase-0-organizational-integration-design)
  - [Phase 0.5: Integration Implementation](#phase-05-integration-implementation)
  - [Deployment Feedback Loop](#deployment-feedback-loop)
- [Custom Commands](#custom-commands)
- [Document Artifacts](#document-artifacts)
- [Agent-to-Agent Communication](#agent-to-agent-communication)
- [Best Practices](#best-practices)

---

## Overview

The organizational deployment process extends the core agentic-base workflow with:

1. **Phase 0: Organizational Integration Design** → Integration Architecture
2. **Phase 0.5: Integration Implementation** → Discord Bot, Webhooks, Scripts
3. **Server Setup → Audit → Deploy Feedback Loop** → Production Infrastructure

This process is optional. Use it when you need:
- Multi-team coordination with Discord/Slack
- Integration with Linear/Jira for project tracking
- Google Docs/Notion for collaborative requirements
- Production server deployment

---

## Agents

### 1. **context-engineering-expert** (AI & Context Engineering Expert)

- **Role**: Pioneering AI expert with 15 years of experience in context engineering
- **Expertise**: Multi-tool orchestration, prompt engineering, workflow integration, agent coordination
- **Responsibilities**:
  - Map and analyze existing organizational workflows
  - Design integration architecture between agentic-base and org tools
  - Create context flow patterns across Discord, Google Docs, Linear, etc.
  - Adapt framework for multi-developer concurrent collaboration
  - Document integration specifications and requirements
  - Design adoption and change management strategy
- **Output**: `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`, `docs/a2a/integration-context.md`
- **Note**: This agent designs but does NOT implement. Use `/implement-org-integration` after this phase.

### 2. **devops-crypto-architect** (DevOps Architect)

- **Role**: Battle-tested DevOps Architect with 15 years of crypto/blockchain infrastructure experience
- **Expertise**: Infrastructure as code, CI/CD, security, monitoring, blockchain operations
- **Modes**:
  - **Integration Implementation Mode** (Phase 0.5): Implements Discord bots, webhooks, sync scripts
  - **Server Setup Mode**: Configures bare metal/VPS servers, security hardening
  - **Production Deployment Mode** (Phase 6): Full production infrastructure
- **Output**:
  - Phase 0.5: `devrel-integration/` directory with complete integration infrastructure
  - Server Setup: `docs/deployment/scripts/`, `docs/a2a/deployment-report.md`
  - Deployment: Production infrastructure and operational docs

### 3. **paranoid-auditor** (Security Auditor)

- **Role**: Paranoid Cypherpunk Security Auditor with 30+ years of experience
- **Expertise**: Infrastructure security, CIS Benchmarks, OWASP, secrets management
- **Deployment Audit Responsibilities**:
  - Review server setup scripts for vulnerabilities
  - Audit deployment configurations and procedures
  - Validate security hardening (SSH, firewall, fail2ban)
  - Check secrets management and credential handling
  - Assess backup and disaster recovery procedures
- **Output**: `docs/a2a/deployment-feedback.md` with verdict and findings

---

## Workflow

### Phase 0: Organizational Integration Design

**Command**: `/integrate-org-workflow`
**Agent**: `context-engineering-expert`

**Goal**: Design how agentic-base integrates with your organization's existing tools and workflows.

#### When to Use

- Multi-team initiatives spanning departments
- Discussions happen in Discord/Slack
- Requirements documented in Google Docs/Notion
- Project tracking in Linear/Jira
- Multiple developers working concurrently
- Need to adapt agentic-base to your organizational processes

#### Process

1. Agent asks targeted questions across 6 discovery phases:
   - **Current Workflow Mapping**: Tools, roles, handoffs
   - **Pain Points & Bottlenecks**: Where context gets lost
   - **Integration Requirements**: Which tools, automation level
   - **Team Structure & Permissions**: Authority, access controls
   - **Data & Context Requirements**: What info agents need
   - **Success Criteria & Constraints**: Goals, limitations

2. Agent designs integration architecture

3. Agent proposes adaptation strategies for multi-developer teams

4. Generates comprehensive integration documentation

#### Outputs

- `docs/integration-architecture.md` - Architecture and data flow diagrams
- `docs/tool-setup.md` - Configuration guide for APIs, webhooks, bots
- `docs/team-playbook.md` - How teams use the integrated system
- `docs/a2a/integration-context.md` - Context for downstream agents

#### Integration Architecture Includes

- Current vs. proposed workflow diagrams
- Tool interaction map (which tools communicate)
- Data flow diagrams (how information moves)
- Agent trigger points (when agents activate)
- Context preservation strategy
- Security and permissions model
- Rollout phases (incremental adoption)

#### Multi-Developer Adaptation Strategies

- Initiative-based isolation (per Linear initiative)
- Linear-centric workflow (issues as source of truth)
- Branch-based workflows (feature branch scoped docs)
- Hybrid orchestration (mix of shared docs and per-task issues)

#### Common Integration Patterns

1. **Discord → Linear → Agentic-Base**: Team discusses in Discord, creates Linear initiative, triggers agent workflow
2. **Google Docs → Linear → Implementation**: Collaborative requirements doc → Linear project → agent implementation
3. **Multi-Team Orchestration**: Leadership initiative → multiple sub-projects → coordinated implementation
4. **Discord-Native**: Agents as bot team members, all workflow in Discord

---

### Phase 0.5: Integration Implementation

**Command**: `/implement-org-integration`
**Agent**: `devops-crypto-architect` (Integration Implementation Mode)

**Goal**: Implement the Discord bot, webhooks, sync scripts, and integration infrastructure designed in Phase 0.

#### Prerequisites

Must have completed Phase 0 (`/integrate-org-workflow`):
- `docs/integration-architecture.md` exists
- `docs/tool-setup.md` exists
- `docs/team-playbook.md` exists
- `docs/a2a/integration-context.md` exists

#### Process

1. Agent reviews all integration architecture documents
2. Plans implementation based on specifications
3. Implements Discord bot with command handlers
4. Implements webhook handlers (Linear, GitHub, Vercel)
5. Implements cron jobs and scheduled tasks
6. Creates deployment configs (Docker, docker-compose, systemd, PM2)
7. Sets up monitoring, logging, and health checks
8. Creates tests for integration components
9. Generates operational runbooks and documentation

#### Outputs

```
devrel-integration/
├── src/                           # Complete bot and webhook implementation
│   ├── bot.ts                     # Discord bot entry point
│   ├── commands/                  # Slash command handlers
│   ├── events/                    # Event listeners
│   └── webhooks/                  # Webhook handlers
├── config/                        # Configuration files (committed)
├── secrets/.env.local.example     # Secrets template
├── Dockerfile                     # Container build
├── docker-compose.yml             # Local development
├── ecosystem.config.js            # PM2 configuration
├── README.md                      # Integration guide
└── DEPLOYMENT.md                  # Deployment instructions

docs/deployment/
├── runbooks/integration-operations.md
└── integration-layer-handover.md
```

#### Implementation Includes

- Discord bot with event listeners and command handlers
- Linear webhook handler with signature verification
- GitHub/Vercel webhook handlers (if needed)
- Daily digest cron job
- Feedback capture (emoji reactions → Linear issues)
- Structured logging with health check endpoints
- Rate limiting and error handling
- Unit and integration tests
- Deployment-ready infrastructure

#### Testing Checklist

- [ ] Bot connects to Discord successfully
- [ ] Commands work in Discord (e.g., `/show-sprint`)
- [ ] Emoji reactions create Linear draft issues
- [ ] Webhooks trigger correctly with signature verification
- [ ] Cron jobs execute on schedule
- [ ] Logs are written properly
- [ ] Health check endpoint responds
- [ ] Error handling prevents crashes

---

### Deployment Feedback Loop

The deployment workflow uses a feedback loop between DevOps and Security Auditor to ensure secure production deployment.

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
│   DevOps reads feedback, fixes issues, updates report
│   ↓
│   (repeat until approved)
│
└── If "APPROVED - LET'S FUCKING GO":
    ↓
    /deploy-go
    ↓
    Execute production deployment
```

---

### Server Setup (`/setup-server`)

**Agent**: `devops-crypto-architect` (Server Setup Mode)

**Goal**: Configure a bare metal or VPS server for production deployment.

#### Phase 0: Check for Previous Feedback

Before starting, agent checks `docs/a2a/deployment-feedback.md`:
- If exists with CHANGES_REQUIRED: Address all feedback first
- If exists with APPROVED: Proceed to deployment prep
- If doesn't exist: First setup cycle, proceed normally

#### Phase 1: Gather Server Information

Agent asks 2-3 questions at a time:

**Server Access**:
- Server IP address
- SSH username (root or sudo-capable user)
- Authentication method (SSH key, password)
- Linux distribution (Debian, Ubuntu, Rocky)
- Hostname

**Services to Deploy**:
- Discord bot (required for DevRel)
- Webhook server (Linear/GitHub/Vercel events)
- Cron jobs (daily digest, scheduled tasks)
- Monitoring stack (Prometheus + Grafana)
- Production or staging environment

**Network & Domain**:
- Domain name
- SSL certificates (Let's Encrypt)
- Ports to open
- IP restrictions

**Security Preferences**:
- fail2ban setup
- Automatic security updates
- Non-root deployment user
- UFW firewall

**Monitoring & Alerts**:
- Monitoring stack (Prometheus + Grafana)
- Alert destinations (Discord, email, PagerDuty)
- Key metrics (uptime, latency, error rates)

#### Phase 2: Generate Setup Scripts

Agent generates scripts in `docs/deployment/scripts/`:

| Script | Purpose |
|--------|---------|
| `01-initial-setup.sh` | System packages, user creation, SSH hardening, hostname |
| `02-security-hardening.sh` | UFW firewall, fail2ban, automatic updates, auditd, sysctl |
| `03-install-dependencies.sh` | Node.js, npm, PM2, Docker, nginx, certbot |
| `04-deploy-app.sh` | Clone code, install deps, build, configure PM2/systemd |
| `05-setup-monitoring.sh` | Prometheus, Grafana, dashboards, alerting (optional) |
| `06-setup-ssl.sh` | nginx reverse proxy, Let's Encrypt, HTTPS redirect (optional) |

#### Phase 3: Create Configuration Files

- `devrel-integration/ecosystem.config.js` - PM2 configuration
- `docs/deployment/devrel-integration.service` - systemd fallback
- `docs/deployment/nginx/devrel-integration.conf` - nginx reverse proxy
- `devrel-integration/secrets/.env.local.example` - environment template

#### Phase 4: Create Documentation

- `docs/deployment/server-setup-guide.md` - Step-by-step instructions
- `docs/deployment/runbooks/server-operations.md` - Operational procedures
- `docs/deployment/security-checklist.md` - Security verification
- `docs/deployment/verification-checklist.md` - Post-setup verification
- `docs/deployment/quick-reference.md` - Key commands and locations

#### Phase 5: Generate Deployment Report

Agent writes `docs/a2a/deployment-report.md` with:
- Executive summary of what was set up
- Server configuration details
- Scripts generated (with status)
- Configuration files created
- Security implementation checklist
- Documentation created
- Technical decisions with rationale
- Known limitations
- Verification steps for auditor
- Previous feedback addressed (if revision)

#### Script Standards

All scripts must:
1. Be idempotent (safe to run multiple times)
2. Include error handling (`set -euo pipefail`)
3. Log actions (echo what's being done)
4. Check prerequisites (verify tools exist)
5. Support dry-run mode (`--dry-run` flag)
6. Be well-commented
7. Use variables for configurability
8. NEVER include secrets

---

### Security Audit (`/audit-deployment`)

**Agent**: `paranoid-auditor` (Deployment Audit Mode)

**Goal**: Review deployment infrastructure and either approve or request changes.

#### Phase 1: Read DevOps Report

Agent reads `docs/a2a/deployment-report.md`:
- Understand scope of infrastructure setup
- Note what was implemented vs. skipped
- Check if this is a revision

If file doesn't exist: Inform user to run `/setup-server` first.

#### Phase 2: Check Previous Feedback

If `docs/a2a/deployment-feedback.md` exists with CHANGES_REQUIRED:
- Read previous feedback carefully
- Verify each issue was addressed
- Check DevOps report's "Previous Audit Feedback Addressed" section
- Verify fixes by reading actual files

#### Phase 3: Systematic Audit

**Server Setup Scripts** - For each script, check:
- [ ] Command injection vulnerabilities
- [ ] Hardcoded secrets or credentials
- [ ] Insecure file permissions
- [ ] Missing error handling
- [ ] Unsafe sudo usage
- [ ] Unvalidated user input
- [ ] Insecure package sources
- [ ] Missing idempotency
- [ ] Downloading from untrusted sources
- [ ] curl | bash patterns without verification

**Configuration Files** - Check for:
- [ ] Running as root
- [ ] Overly permissive file permissions
- [ ] Missing resource limits
- [ ] Insecure environment variable handling
- [ ] Weak TLS configurations
- [ ] Missing security headers
- [ ] Open proxy vulnerabilities
- [ ] Exposed debug endpoints

**Security Hardening** - Verify:
- [ ] SSH hardening (key-only auth, no root login, strong ciphers)
- [ ] Firewall configuration (UFW deny-by-default)
- [ ] fail2ban configuration
- [ ] Automatic security updates
- [ ] Audit logging
- [ ] sysctl security parameters

**Secrets Management** - Audit:
- [ ] Secrets NOT hardcoded in scripts
- [ ] Environment template exists
- [ ] Secrets file permissions restricted (600)
- [ ] Secrets excluded from git
- [ ] Rotation procedure documented

**Network Security** - Review:
- [ ] Minimal ports exposed
- [ ] Internal ports NOT exposed externally
- [ ] TLS 1.2+ only
- [ ] Strong cipher suites
- [ ] HTTPS redirect
- [ ] Security headers

**Operational Security** - Assess:
- [ ] Backup procedure documented
- [ ] Restore procedure documented
- [ ] Secret rotation documented
- [ ] Incident response plan
- [ ] Access revocation procedure
- [ ] Rollback procedure

#### Phase 4: Make Decision

**Option A: Request Changes**

If ANY critical/high issues found or previous feedback unaddressed:

Write to `docs/a2a/deployment-feedback.md`:
```markdown
# Deployment Security Audit Feedback

**Date**: YYYY-MM-DD
**Audit Status**: CHANGES_REQUIRED
**Risk Level**: CRITICAL | HIGH | MEDIUM | LOW
**Deployment Readiness**: NOT_READY

## Critical Issues (MUST FIX)
[Detailed findings with locations, risks, required fixes, verification steps]

## High Priority Issues
[Similar format]

## Previous Feedback Status
[Table showing FIXED/NOT_FIXED for each previous item]

## Infrastructure Security Checklist
[Checkboxes with ✅/❌/⚠️]

## Next Steps
1. DevOps addresses CRITICAL issues
2. DevOps addresses HIGH priority issues
3. DevOps updates deployment-report.md
4. Re-run /audit-deployment

## Auditor Sign-off
**Verdict**: CHANGES_REQUIRED
```

**Option B: Approve**

If no critical/high issues and all previous feedback addressed:

Write to `docs/a2a/deployment-feedback.md`:
```markdown
# Deployment Security Audit Feedback

**Date**: YYYY-MM-DD
**Audit Status**: APPROVED - LET'S FUCKING GO
**Risk Level**: ACCEPTABLE
**Deployment Readiness**: READY

## Security Assessment
[Brief summary of security posture]

## Infrastructure Security Checklist
[All checkboxes ✅]

## Remaining Items (Post-Deployment)
[MEDIUM/LOW items to address later]

## Positive Findings
[What was done well]

## Deployment Authorization
The infrastructure is APPROVED for production deployment.
**Next Step**: Run `/deploy-go` to execute the deployment

## Auditor Sign-off
**Verdict**: APPROVED - LET'S FUCKING GO
```

---

### Production Deployment (`/deploy-go`)

**Agent**: `devops-crypto-architect` (Deployment Execution Mode)

**Goal**: Execute production deployment after security audit approval.

#### Phase 0: Verify Security Approval (BLOCKING)

Check `docs/a2a/deployment-feedback.md`:
- If doesn't exist: STOP, instruct to run `/setup-server` then `/audit-deployment`
- If CHANGES_REQUIRED: STOP, show issues, instruct to fix
- If APPROVED - LET'S FUCKING GO: Confirm with user, proceed

#### Phase 1: Pre-Deployment Checklist

Verify with user:
- [ ] SSH access to target server confirmed
- [ ] Deployment user credentials ready
- [ ] Network connectivity verified
- [ ] All required API tokens available
- [ ] .env.local file prepared with real values
- [ ] Secrets will be transferred securely (NOT via git)
- [ ] Rollback procedure understood
- [ ] Team notified of deployment window

#### Phase 2: Deployment Execution Guide

Walk user through each script:

1. **Transfer Scripts to Server**
```bash
scp -r docs/deployment/scripts/ user@server:/tmp/deployment-scripts/
```

2. **Connect and Prepare**
```bash
ssh user@server
cd /tmp/deployment-scripts
chmod +x *.sh
```

3. **Execute Scripts in Order**
```bash
sudo ./01-initial-setup.sh
# Verify: hostname set, user created, SSH hardened

sudo ./02-security-hardening.sh
# Verify: UFW active, fail2ban running, updates configured

sudo ./03-install-dependencies.sh
# Verify: node --version, pm2 --version, nginx -v

# Transfer secrets securely, create .env.local
sudo ./04-deploy-app.sh
# Verify: Application built, PM2 started

sudo ./05-setup-monitoring.sh  # if applicable
# Verify: Prometheus running, Grafana accessible

sudo ./06-setup-ssl.sh  # if applicable
# Verify: HTTPS working, certificate valid
```

Pause after each script to verify success.

#### Phase 3: Post-Deployment Verification

Run through verification checklist:

**Server Verification**:
```bash
ssh user@server 'echo "SSH OK"'
sudo ufw status
sudo systemctl status fail2ban
```

**Application Verification**:
```bash
pm2 status
pm2 logs devrel-bot --lines 50
curl -s http://localhost:3000/health
```

**SSL Verification** (if applicable):
```bash
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null
curl -I http://your-domain.com | grep -i location
```

#### Phase 4: Document Completion

Update `docs/a2a/deployment-feedback.md` with deployment execution record:
- Deployment date and time
- Scripts executed
- Verification results
- Post-deployment notes
- **DEPLOYMENT COMPLETE**

---

## Custom Commands

### `/integrate-org-workflow`
Design organizational integration architecture.
- **Agent**: `context-engineering-expert`
- **Output**: `docs/integration-architecture.md`, `docs/tool-setup.md`, `docs/team-playbook.md`

### `/implement-org-integration`
Implement Discord bot, webhooks, scripts.
- **Agent**: `devops-crypto-architect`
- **Prerequisites**: Phase 0 must be complete
- **Output**: `devrel-integration/` directory

### `/setup-server`
Configure production server with feedback loop.
- **Agent**: `devops-crypto-architect`
- **Reads**: `docs/a2a/deployment-feedback.md` (if exists)
- **Output**: `docs/deployment/scripts/`, `docs/a2a/deployment-report.md`

### `/audit-deployment`
Security audit of deployment infrastructure.
- **Agent**: `paranoid-auditor`
- **Reads**: `docs/a2a/deployment-report.md`
- **Output**: `docs/a2a/deployment-feedback.md`

### `/deploy-go`
Execute production deployment (requires approval).
- **Agent**: `devops-crypto-architect`
- **Reads**: `docs/a2a/deployment-feedback.md` (must be APPROVED)
- **Output**: Deployed infrastructure

---

## Document Artifacts

### Integration Documents

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Integration Architecture** | `docs/integration-architecture.md` | `context-engineering-expert` | Architecture and data flow |
| **Tool Setup** | `docs/tool-setup.md` | `context-engineering-expert` | API and webhook configuration |
| **Team Playbook** | `docs/team-playbook.md` | `context-engineering-expert` | How teams use the system |
| **Integration Context** | `docs/a2a/integration-context.md` | `context-engineering-expert` | Context for downstream agents |

### Deployment Documents

| Document | Path | Created By | Purpose |
|----------|------|------------|---------|
| **Server Setup Guide** | `docs/deployment/server-setup-guide.md` | `devops-crypto-architect` | Step-by-step setup |
| **Security Checklist** | `docs/deployment/security-checklist.md` | `devops-crypto-architect` | Security verification |
| **Verification Checklist** | `docs/deployment/verification-checklist.md` | `devops-crypto-architect` | Post-deployment checks |
| **Quick Reference** | `docs/deployment/quick-reference.md` | `devops-crypto-architect` | Key commands |
| **Server Operations** | `docs/deployment/runbooks/server-operations.md` | `devops-crypto-architect` | Operational procedures |

### A2A Communication

| Document | Path | Created By | Read By |
|----------|------|------------|---------|
| **Deployment Report** | `docs/a2a/deployment-report.md` | `devops-crypto-architect` | `paranoid-auditor` |
| **Deployment Feedback** | `docs/a2a/deployment-feedback.md` | `paranoid-auditor` | `devops-crypto-architect` |

---

## Agent-to-Agent Communication

### Deployment Feedback Loop

The deployment feedback loop enables iterative security review:

1. **DevOps → Auditor** (`docs/a2a/deployment-report.md`)
   - What infrastructure was created
   - Scripts and configs generated
   - Security measures implemented
   - Decisions and rationale
   - How previous feedback was addressed

2. **Auditor → DevOps** (`docs/a2a/deployment-feedback.md`)
   - Audit verdict (CHANGES_REQUIRED or APPROVED)
   - Critical/High/Medium/Low issues
   - Specific remediation steps
   - Verification instructions
   - Security checklist status

### Approval Signals

- **CHANGES_REQUIRED**: Issues found, DevOps must fix and re-submit
- **APPROVED - LET'S FUCKING GO**: Ready for production, `/deploy-go` enabled

---

## Best Practices

### For Integration Design (Phase 0)

- Map current workflows thoroughly before designing new ones
- Identify where context gets lost in handoffs
- Start with minimal integration, expand incrementally
- Consider team adoption and change management
- Document everything for future reference

### For Integration Implementation (Phase 0.5)

- Implement one integration at a time
- Test each component before moving to next
- Use structured logging from the start
- Handle errors gracefully
- Write tests for critical paths

### For Server Setup

- Use SSH keys, never password authentication
- Create dedicated non-root deployment user
- Enable automatic security updates
- Configure fail2ban immediately
- Document every manual configuration

### For Security Audit

- Be paranoid: assume everything will be attacked
- Verify fixes by reading actual code, not just reports
- Don't approve until all critical issues are fixed
- Acknowledge good security practices
- Provide specific, actionable remediation steps

### For Production Deployment

- Never skip the security audit
- Execute one script at a time, verify each step
- Transfer secrets securely (never via git)
- Have rollback plan ready before deploying
- Monitor closely for 24-48 hours after deployment

---

## Example Workflow

```bash
# Phase 0: Design organizational integration
/integrate-org-workflow
# → Answer discovery questions about tools, teams, workflows
# → Review docs/integration-architecture.md
# → Review docs/tool-setup.md
# → Review docs/team-playbook.md

# Phase 0.5: Implement integration
/implement-org-integration
# → Agent builds Discord bot and webhooks
# → Review devrel-integration/ implementation
# → Test locally with docker-compose

# Server Setup: Configure production server
/setup-server
# → Answer questions about server, services, security
# → Review generated scripts in docs/deployment/scripts/
# → Review docs/a2a/deployment-report.md

# Security Audit: Review infrastructure
/audit-deployment
# → Auditor reviews all scripts and configs
# → Check docs/a2a/deployment-feedback.md for verdict

# If CHANGES_REQUIRED:
/setup-server
# → Agent reads feedback, fixes issues
# → Updates report
/audit-deployment
# → Re-audit

# When APPROVED - LET'S FUCKING GO:
/deploy-go
# → Transfer scripts to server
# → Execute scripts in order
# → Verify each step
# → Document completion
```

---

## Questions?

If you have questions about the organizational deployment process:
- Review agent definitions in `.claude/agents/`
- Check command definitions in `.claude/commands/`
- Review existing artifacts in `docs/`
- Consult [DEPLOY-ORG-README.md](DEPLOY-ORG-README.md) for quick reference
- Ask Claude Code for help with `/help`

---

**Remember**: The deployment feedback loop exists to ensure secure production deployment. Don't rush the audit, address all issues, and only deploy when you have explicit approval. "APPROVED - LET'S FUCKING GO" means the infrastructure is ready for production.
