---
description: Launch the DevOps architect to set up and configure a bare metal server for the DevRel integration application
args: [background]
---

I'm launching the devops-crypto-architect agent in **server setup mode** to configure your bare metal server for the DevRel integration application.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

**Feedback Loop Pattern**:
This command participates in an audit-fix-verify feedback loop with `/audit-deployment`:

```
/setup-server
    ↓
DevOps creates infrastructure → writes docs/a2a/deployment-report.md
    ↓
/audit-deployment
    ↓
Auditor reviews → writes docs/a2a/deployment-feedback.md
    ↓ (if changes required)
/setup-server (again)
    ↓
DevOps reads feedback, fixes issues, updates report
    ↓
(repeat until auditor approves with "LET'S FUCKING GO")
    ↓
/deploy-go
    ↓
Execute deployment on production server
```

**What this command does**:
- First checks for `docs/a2a/deployment-feedback.md` and addresses feedback if it exists
- Configures a bare metal/VPS server from scratch
- Installs required dependencies (Node.js, Docker, etc.)
- Sets up the DevRel Discord bot and integration services
- Configures security hardening, firewall, and SSH
- Sets up monitoring, logging, and alerting
- Creates systemd services for auto-restart
- Generates deployment report at `docs/a2a/deployment-report.md`

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are setting up a bare metal or VPS server to run the DevRel integration application. This is **server provisioning and configuration mode** with a feedback loop for security audit.

## Phase 0: Check for Previous Audit Feedback

BEFORE starting any new work, check if `docs/a2a/deployment-feedback.md` exists.

If feedback EXISTS:
- Read it carefully
- If CHANGES_REQUIRED: Address ALL critical and high priority issues
- If APPROVED: Proceed to Phase 7 (final deployment prep)

If NO feedback exists: This is your first cycle, proceed to Phase 1.

## Phase 1: Gather Server Information

Ask the user for:
- Server IP address and SSH username
- Linux distribution
- Which components to deploy (Discord bot, webhook server, cron jobs, monitoring)
- Domain name and SSL requirements
- Security preferences (fail2ban, auto-updates, non-root user)
- Monitoring and alerting preferences

## Phase 2: Generate Server Setup Scripts

Create shell scripts in `docs/deployment/scripts/`:
- `01-initial-setup.sh` - System update, tools, deployment user, SSH hardening
- `02-security-hardening.sh` - UFW, fail2ban, auto-updates, sysctl
- `03-install-dependencies.sh` - Node.js, PM2, Docker, nginx
- `04-deploy-app.sh` - Clone code, install deps, build, configure PM2
- `05-setup-monitoring.sh` (optional) - Prometheus, Grafana
- `06-setup-ssl.sh` (optional) - nginx reverse proxy, Let's Encrypt

## Phase 3: Create Configuration Files

- `devrel-integration/ecosystem.config.js` - PM2 config
- `docs/deployment/devrel-integration.service` - systemd fallback
- `docs/deployment/nginx/devrel-integration.conf` (if using domain)
- `devrel-integration/secrets/.env.local.example` - env template

## Phase 4: Create Deployment Documentation

- `docs/deployment/server-setup-guide.md` - Step-by-step instructions
- `docs/deployment/runbooks/server-operations.md` - Operations runbook
- `docs/deployment/security-checklist.md` - Security verification
- `docs/deployment/verification-checklist.md` - Post-deployment checks
- `docs/deployment/quick-reference.md` - Key commands

## Phase 5: Generate Deployment Report

Create `docs/a2a/deployment-report.md` with:
- Executive Summary
- Server Configuration details
- Scripts Generated (table with status)
- Configuration Files (table with status)
- Security Implementation checklist
- Documentation Created list
- Technical Decisions with rationale
- Known Limitations
- Verification Steps for auditor
- Previous Audit Feedback Addressed (if revision)

## Phase 6: Script Standards

All scripts MUST:
- Be idempotent (safe to run multiple times)
- Include `set -euo pipefail`
- Log actions with timestamps
- Check prerequisites
- Support --dry-run flag
- NEVER include secrets

## Phase 7: Feedback Loop

After generating report:
1. Inform user to run `/audit-deployment`
2. Auditor will review and write feedback
3. If changes required, re-run `/setup-server` to address
4. Cycle continues until 'LET'S FUCKING GO' approval
5. Then run `/deploy-go` for production deployment

Your goal is to create production-ready, secure infrastructure that passes rigorous security audit."
/>
{{ else }}
Let me begin server setup.

You are setting up a bare metal or VPS server to run the DevRel integration application. This is **server provisioning and configuration mode** with a feedback loop for security audit.

## Phase 0: Check for Previous Audit Feedback

BEFORE starting any new work, check if `docs/a2a/deployment-feedback.md` exists.

If feedback EXISTS:
- Read it carefully
- If CHANGES_REQUIRED: Address ALL critical and high priority issues
- If APPROVED: Proceed to Phase 7 (final deployment prep)

If NO feedback exists: This is your first cycle, proceed to Phase 1.

## Phase 1: Gather Server Information

Ask the user for:
- Server IP address and SSH username
- Linux distribution
- Which components to deploy (Discord bot, webhook server, cron jobs, monitoring)
- Domain name and SSL requirements
- Security preferences (fail2ban, auto-updates, non-root user)
- Monitoring and alerting preferences

## Phase 2: Generate Server Setup Scripts

Create shell scripts in `docs/deployment/scripts/`:
- `01-initial-setup.sh` - System update, tools, deployment user, SSH hardening
- `02-security-hardening.sh` - UFW, fail2ban, auto-updates, sysctl
- `03-install-dependencies.sh` - Node.js, PM2, Docker, nginx
- `04-deploy-app.sh` - Clone code, install deps, build, configure PM2
- `05-setup-monitoring.sh` (optional) - Prometheus, Grafana
- `06-setup-ssl.sh` (optional) - nginx reverse proxy, Let's Encrypt

## Phase 3: Create Configuration Files

- `devrel-integration/ecosystem.config.js` - PM2 config
- `docs/deployment/devrel-integration.service` - systemd fallback
- `docs/deployment/nginx/devrel-integration.conf` (if using domain)
- `devrel-integration/secrets/.env.local.example` - env template

## Phase 4: Create Deployment Documentation

- `docs/deployment/server-setup-guide.md` - Step-by-step instructions
- `docs/deployment/runbooks/server-operations.md` - Operations runbook
- `docs/deployment/security-checklist.md` - Security verification
- `docs/deployment/verification-checklist.md` - Post-deployment checks
- `docs/deployment/quick-reference.md` - Key commands

## Phase 5: Generate Deployment Report

Create `docs/a2a/deployment-report.md` with:
- Executive Summary
- Server Configuration details
- Scripts Generated (table with status)
- Configuration Files (table with status)
- Security Implementation checklist
- Documentation Created list
- Technical Decisions with rationale
- Known Limitations
- Verification Steps for auditor
- Previous Audit Feedback Addressed (if revision)

## Phase 6: Script Standards

All scripts MUST:
- Be idempotent (safe to run multiple times)
- Include `set -euo pipefail`
- Log actions with timestamps
- Check prerequisites
- Support --dry-run flag
- NEVER include secrets

## Phase 7: Feedback Loop

After generating report:
1. Inform user to run `/audit-deployment`
2. Auditor will review and write feedback
3. If changes required, re-run `/setup-server` to address
4. Cycle continues until "LET'S FUCKING GO" approval
5. Then run `/deploy-go` for production deployment

Your goal is to create production-ready, secure infrastructure that passes rigorous security audit.
{{ endif }}
