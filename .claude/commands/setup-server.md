---
description: Launch the DevOps architect to set up and configure a bare metal server for the DevRel integration application
---

I'm launching the devops-crypto-architect agent in **server setup mode** to configure your bare metal server for the DevRel integration application.

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

Let me launch the agent now.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are setting up a bare metal or VPS server to run the DevRel integration application. This is **server provisioning and configuration mode** with a feedback loop for security audit.

## Phase 0: Check for Previous Audit Feedback

BEFORE starting any new work, search for existing audit feedback:

### Step 0.1: Check Primary Location
First, check if `docs/a2a/deployment-feedback.md` exists.

### Step 0.2: Search Alternate Locations
If the primary file does NOT exist OR does not follow the template format (check for 'Audit Status:' header), search these alternate locations for audit feedback that may have been generated in previous cycles:

- `docs/a2a/` - Any files containing 'audit', 'feedback', 'security', or 'deployment'
- `docs/deployment/` - Look for `DEPLOYMENT-*.md`, `*-AUDIT-*.md`, `*-SECURITY-*.md`
- `docs/audits/` - Check for recent audit reports in date-based subdirectories
- `DEPLOYMENT-SECURITY-AUDIT.md` or `SECURITY-AUDIT-REPORT.md` in the project root
- Any file containing 'CHANGES_REQUIRED' or 'APPROVED - LET'S FUCKING GO'

Use Glob and Grep tools to search:
```
Glob: **/*deployment*.md, **/*audit*.md, **/*security*.md, **/*feedback*.md
Grep: 'CHANGES_REQUIRED|APPROVED.*GO|Critical Issues|HIGH.*Priority'
```

### Step 0.3: Consolidate Feedback
If you find audit feedback in alternate locations:
1. Read and understand ALL the feedback from those files
2. Note which issues have been addressed vs. still outstanding
3. You will consolidate this into the proper template format in Phase 5

### Step 0.4: Process Feedback
1. If feedback EXISTS (in any location):
   - Read it carefully and completely
   - This contains feedback from the paranoid-auditor on your previous infrastructure work
   - The file will indicate either:
     * **CHANGES_REQUIRED**: Address ALL critical and high priority issues
     * **APPROVED - LET'S FUCKING GO**: Proceed to Phase 7 (final deployment prep)
   - For CHANGES_REQUIRED:
     * Fix all CRITICAL issues (blocking - must fix)
     * Fix all HIGH priority issues (should fix)
     * Note MEDIUM/LOW issues for future maintenance
     * Update your deployment report with fixes
   - If ANYTHING is unclear or ambiguous:
     * Ask specific clarifying questions
     * Request concrete examples
     * Confirm understanding before proceeding

2. If NO feedback exists anywhere:
   - This is your first infrastructure setup cycle
   - Proceed directly to Phase 1

## Phase 1: Gather Server Information

Ask the user for essential information. Be specific and ask 2-3 questions at a time:

### Server Access
- What is the server IP address?
- What is the SSH username? (root or a sudo-capable user)
- How do you authenticate? (SSH key, password, or both)
- What Linux distribution is installed? (Debian, Ubuntu, Rocky, etc.)
- What is the server's hostname (or what should it be)?

### Services to Deploy
- Which components do you want to deploy?
  - Discord bot (required for DevRel)
  - Webhook server (for Linear/GitHub/Vercel events)
  - Cron jobs (daily digest, scheduled tasks)
  - Monitoring stack (Prometheus + Grafana)
- Do you have API tokens ready? (Discord bot token, Linear API key, etc.)
- Should this be a production or staging environment?

### Network & Domain
- Do you have a domain name to point to this server?
- Do you want HTTPS/SSL certificates? (Let's Encrypt recommended)
- What ports should be open? (22 SSH, 443 HTTPS, 3000 app, etc.)
- Are there any IP restrictions needed? (whitelist specific IPs for SSH)

### Security Preferences
- Should I set up fail2ban for SSH brute-force protection?
- Do you want automatic security updates enabled?
- Should I create a non-root deployment user?
- Do you want UFW/firewall configured?

### Monitoring & Alerts
- Do you want monitoring set up? (Prometheus + Grafana)
- Where should alerts go? (Discord channel, email, PagerDuty)
- What metrics are most important? (uptime, API latency, error rates)

## Phase 2: Generate Server Setup Scripts

Based on user answers, generate shell scripts for server configuration:

### 1. Initial Server Setup Script
Create `docs/deployment/scripts/01-initial-setup.sh`:
- Update system packages
- Install essential tools (curl, git, jq, htop, etc.)
- Create deployment user with sudo privileges
- Configure timezone and locale
- Set up SSH hardening
- Configure hostname

### 2. Security Hardening Script
Create `docs/deployment/scripts/02-security-hardening.sh`:
- Configure UFW firewall with appropriate rules
- Install and configure fail2ban
- Set up automatic security updates (unattended-upgrades)
- Configure SSH (disable root login, key-only auth)
- Set up auditd for security logging
- Configure sysctl security parameters

### 3. Application Dependencies Script
Create `docs/deployment/scripts/03-install-dependencies.sh`:
- Install Node.js LTS (via NodeSource or nvm)
- Install npm/yarn
- Install PM2 globally for process management
- Install Docker and Docker Compose (optional)
- Install nginx (for reverse proxy if needed)
- Install certbot for SSL certificates

### 4. Application Deployment Script
Create `docs/deployment/scripts/04-deploy-app.sh`:
- Clone or copy application code
- Install npm dependencies
- Build TypeScript application
- Create environment file from template
- Configure PM2 ecosystem file
- Set up systemd service as fallback
- Configure log rotation

### 5. Monitoring Setup Script (optional)
Create `docs/deployment/scripts/05-setup-monitoring.sh`:
- Install Prometheus node exporter
- Set up application metrics endpoint
- Configure Grafana (Docker or direct install)
- Import dashboards
- Configure alerting rules

### 6. SSL/Domain Setup Script (optional)
Create `docs/deployment/scripts/06-setup-ssl.sh`:
- Configure nginx as reverse proxy
- Obtain Let's Encrypt certificates
- Set up certificate auto-renewal
- Configure HTTPS redirect

## Phase 3: Create Configuration Files

### PM2 Ecosystem File
Create `devrel-integration/ecosystem.config.js` with:
- App name and script path
- Working directory (use relative paths for portability)
- Memory limits
- Environment variables (NODE_ENV only, no secrets)
- Log file locations
- Restart policy

### Systemd Service (fallback)
Create `docs/deployment/devrel-integration.service` with:
- Non-root user execution
- Environment file reference
- Restart policy
- Log configuration

### Nginx Configuration (if using domain/SSL)
Create `docs/deployment/nginx/devrel-integration.conf` with:
- HTTP to HTTPS redirect
- Reverse proxy to app
- Security headers
- SSL configuration

### Environment Template
Create/update `devrel-integration/secrets/.env.local.example` with:
- All required environment variables
- Comments explaining each variable
- Example values (non-sensitive)
- Clear instructions for secrets

## Phase 4: Create Deployment Documentation

### Server Setup Guide
Create `docs/deployment/server-setup-guide.md`:
- Prerequisites and requirements
- Step-by-step setup instructions
- Script execution order
- Verification steps for each phase
- Troubleshooting common issues

### Operational Runbook
Create `docs/deployment/runbooks/server-operations.md`:
- Starting/stopping the application
- Viewing logs
- Restarting after server reboot
- Updating the application
- Rolling back to previous version
- Rotating secrets
- Checking system health

### Security Checklist
Create `docs/deployment/security-checklist.md`:
- Pre-deployment security checks
- Post-deployment verification
- Regular security maintenance tasks
- Incident response procedures

### Verification Checklist
Create `docs/deployment/verification-checklist.md`:
- SSH access verification
- Firewall verification
- Application health checks
- SSL verification (if applicable)
- Monitoring verification (if applicable)

### Quick Reference Card
Create `docs/deployment/quick-reference.md`:
- Key file locations
- Important commands
- Service management
- Log locations

## Phase 5: Generate Deployment Report for Audit

### Step 5.1: Check for Existing Reports
Before creating the report, search for any existing deployment reports that may have been generated in alternate locations:

- `docs/deployment/DEPLOYMENT-*.md`
- `docs/deployment/*-report*.md`
- `docs/a2a/deployment-report.md` (may exist but not follow template)
- Project root: `DEPLOYMENT-*.md`

If you find existing reports:
1. Read them to understand what was previously documented
2. Extract relevant information (scripts created, configs, decisions)
3. Consolidate into the new template format
4. Reference the old report location in the 'Previous Audit Feedback Addressed' section

### Step 5.2: Create/Update the Report
Create or **overwrite** `docs/a2a/deployment-report.md` following the template at `docs/a2a/deployment-report.md.template`.

**IMPORTANT**:
- Read the template file first and follow its structure exactly
- If an existing report exists but doesn't follow the template, **rewrite it** using the template format
- Preserve any relevant content from the old format while restructuring

The template includes:

1. **Header**: Created by, Read by, Date, Status fields
2. **Executive Summary**: What was set up and overall status
3. **Server Configuration**: Target environment details
4. **Scripts Generated**: Table of all scripts with status
5. **Configuration Files**: Table of all configs with status
6. **Security Implementation**: Checklist of security measures
7. **Documentation Created**: List of all docs created
8. **Technical Decisions**: Key decisions with rationale
9. **Known Limitations**: Any limitations with justification
10. **Verification Steps**: How auditor can verify the work
11. **Previous Audit Feedback Addressed**: (if revision) Quote each feedback item and explain fix

End the report with:
- Self-review checklist completion status
- Sign-off indicating ready for audit

## Phase 6: Script Standards

All scripts MUST:
1. **Be idempotent**: Safe to run multiple times
2. **Include error handling**: `set -euo pipefail`
3. **Log actions**: Echo what's being done
4. **Check prerequisites**: Verify required tools exist
5. **Support dry-run mode**: Optional `--dry-run` flag
6. **Be well-commented**: Explain non-obvious steps
7. **Use variables for configurability**: User, paths, etc.
8. **NEVER include secrets**: Use environment variables or secret files

Example script header:
```bash
#!/bin/bash
set -euo pipefail

# ==============================================================================
# Script: 01-initial-setup.sh
# Purpose: Initial server setup and configuration
# Prerequisites: Fresh Debian/Ubuntu server with root/sudo access
# Usage: sudo ./01-initial-setup.sh [--dry-run]
# ==============================================================================

DRY_RUN=false
if [[ \"${1:-}\" == \"--dry-run\" ]]; then
    DRY_RUN=true
    echo \"[DRY RUN] No changes will be made\"
fi

log() {
    echo \"[$(date '+%Y-%m-%d %H:%M:%S')] $*\"
}

run() {
    if [[ \"$DRY_RUN\" == \"true\" ]]; then
        echo \"[DRY RUN] Would run: $*\"
    else
        \"$@\"
    fi
}

# ... rest of script
```

## Phase 7: Feedback Loop

After you generate the deployment report:
1. Inform the user to run `/audit-deployment` for security review
2. The paranoid-auditor will review your work
3. If issues found: Auditor writes feedback to `docs/a2a/deployment-feedback.md`
4. When you are invoked again (`/setup-server`), you will:
   - Read `docs/a2a/deployment-feedback.md` (Phase 0)
   - Address all CRITICAL and HIGH priority issues
   - Update scripts, configs, and documentation
   - Update `docs/a2a/deployment-report.md` with fixes
5. This cycle continues until the auditor approves with 'LET'S FUCKING GO'
6. After approval, user runs `/deploy-go` to execute production deployment

## Deliverables Summary

Your server setup implementation should produce:

1. **Setup Scripts** (`docs/deployment/scripts/`):
   - `01-initial-setup.sh`
   - `02-security-hardening.sh`
   - `03-install-dependencies.sh`
   - `04-deploy-app.sh`
   - `05-setup-monitoring.sh` (optional)
   - `06-setup-ssl.sh` (optional)

2. **Configuration Files**:
   - `devrel-integration/ecosystem.config.js`
   - `docs/deployment/devrel-integration.service`
   - `docs/deployment/nginx/devrel-integration.conf` (if using domain)
   - `devrel-integration/secrets/.env.local.example`

3. **Documentation**:
   - `docs/deployment/server-setup-guide.md`
   - `docs/deployment/runbooks/server-operations.md`
   - `docs/deployment/security-checklist.md`
   - `docs/deployment/verification-checklist.md`
   - `docs/deployment/quick-reference.md`

4. **A2A Communication**:
   - `docs/a2a/deployment-report.md` (YOUR OUTPUT - for auditor review)

## Critical Requirements

- ALWAYS check for `docs/a2a/deployment-feedback.md` FIRST before starting new work
- NEVER assume what feedback means - ask for clarification if unclear
- Address ALL CRITICAL and HIGH priority feedback items
- Be thorough in your deployment report - the auditor needs detailed information
- Include specific file paths and line numbers
- Document your reasoning for security decisions
- NEVER include secrets in scripts or committed files
- Be honest about limitations or concerns

Your goal is to create production-ready, secure infrastructure that passes rigorous security audit."
/>
