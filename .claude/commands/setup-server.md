---
description: Launch the DevOps architect to set up and configure a bare metal server for the DevRel integration application
---

I'm launching the devops-crypto-architect agent in **server setup mode** to configure your bare metal OVH server for the DevRel integration application.

**What this command does**:
- Configures a bare metal/VPS server from scratch
- Installs required dependencies (Node.js, Docker, etc.)
- Sets up the DevRel Discord bot and integration services
- Configures security hardening, firewall, and SSH
- Sets up monitoring, logging, and alerting
- Creates systemd services for auto-restart
- Generates operational runbooks

**Prerequisites**:
- SSH access to your server (root or sudo user)
- Server IP address and credentials ready
- Domain name (optional, for HTTPS)

The DevOps architect will ask you about:
1. Server access details (IP, SSH user, authentication method)
2. Services to deploy (Discord bot, webhooks, cron jobs)
3. Security requirements (firewall rules, fail2ban, SSL)
4. Monitoring preferences (Prometheus, Grafana, alerts)
5. Domain/SSL configuration

Let me launch the agent now to set up your server.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are setting up a bare metal or VPS server (likely OVH) to run the DevRel integration application. This is **server provisioning and configuration mode**.

## Context

The user has a bare metal server (OVH or similar provider) and wants to deploy the DevRel integration application which includes:
- Discord bot for team communication
- Webhook handlers for Linear/GitHub/Vercel events
- Cron jobs for daily digests and scheduled tasks
- Integration services connecting organizational tools

The application code exists in `devrel-integration/` directory.

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

Based on user answers, generate shell scripts for server configuration. Create these files:

### 1. Initial Server Setup Script
Create `docs/deployment/scripts/01-initial-setup.sh`:
- Update system packages
- Install essential tools (curl, git, jq, htop, etc.)
- Create deployment user with sudo privileges
- Configure timezone and locale
- Set up SSH hardening (disable password auth if using keys)
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
- Import dashboards for Node.js and system metrics
- Configure alerting rules

### 6. SSL/Domain Setup Script (optional)
Create `docs/deployment/scripts/06-setup-ssl.sh`:
- Configure nginx as reverse proxy
- Obtain Let's Encrypt certificates via certbot
- Set up certificate auto-renewal
- Configure HTTPS redirect

## Phase 3: Create Deployment Documentation

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

## Phase 4: PM2/Systemd Configuration

### PM2 Ecosystem File
Create `devrel-integration/ecosystem.config.js`:
```javascript
module.exports = {
  apps: [{
    name: 'devrel-bot',
    script: 'dist/bot.js',
    cwd: '/opt/devrel-integration',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production'
    },
    error_file: '/var/log/devrel/error.log',
    out_file: '/var/log/devrel/out.log',
    log_date_format: 'YYYY-MM-DD HH:mm:ss Z'
  }]
};
```

### Systemd Service (fallback)
Create `docs/deployment/devrel-integration.service`:
```ini
[Unit]
Description=DevRel Integration Bot
After=network.target

[Service]
Type=simple
User=devrel
Group=devrel
WorkingDirectory=/opt/devrel-integration
EnvironmentFile=/opt/devrel-integration/secrets/.env.local
ExecStart=/usr/bin/node dist/bot.js
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/devrel/out.log
StandardError=append:/var/log/devrel/error.log

[Install]
WantedBy=multi-user.target
```

## Phase 5: Nginx Configuration (if using domain/SSL)

Create `docs/deployment/nginx/devrel-integration.conf`:
```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;

    # Webhook endpoint
    location /webhooks/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
}
```

## Phase 6: Verification and Handover

### Create Verification Checklist
Create `docs/deployment/verification-checklist.md`:
- [ ] SSH access working with hardened config
- [ ] Firewall configured and active
- [ ] fail2ban running and monitoring SSH
- [ ] Node.js and npm installed correctly
- [ ] Application built successfully
- [ ] Environment variables configured
- [ ] PM2/systemd service running
- [ ] Application responding to health checks
- [ ] Logs being written correctly
- [ ] SSL certificates valid (if applicable)
- [ ] Monitoring collecting metrics (if applicable)
- [ ] Alerts configured and tested (if applicable)

### Quick Reference Card
Create `docs/deployment/quick-reference.md`:
- Key file locations
- Important commands
- Service management (start/stop/restart)
- Log locations
- Config file locations
- Secrets file locations
- Useful troubleshooting commands

## Script Standards

All scripts should:
1. **Be idempotent**: Safe to run multiple times
2. **Include error handling**: `set -euo pipefail`
3. **Log actions**: Echo what's being done
4. **Check prerequisites**: Verify required tools exist
5. **Support dry-run mode**: Optional `--dry-run` flag
6. **Be well-commented**: Explain non-obvious steps
7. **Use variables for configurability**: User, paths, etc.

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

## Security Reminders

1. **Never include secrets in scripts**: Use environment variables or secret files
2. **Validate user input**: Sanitize any user-provided values
3. **Use least privilege**: Create dedicated service user
4. **Enable audit logging**: Track all administrative actions
5. **Document access**: Who has access to what
6. **Plan for key rotation**: Document how to rotate all credentials

## Deliverables

Your server setup implementation should produce:

1. **Setup Scripts** (`docs/deployment/scripts/`):
   - `01-initial-setup.sh` - Initial server configuration
   - `02-security-hardening.sh` - Security hardening
   - `03-install-dependencies.sh` - Install Node.js, PM2, etc.
   - `04-deploy-app.sh` - Deploy the application
   - `05-setup-monitoring.sh` - Set up monitoring (optional)
   - `06-setup-ssl.sh` - SSL/domain setup (optional)

2. **Configuration Files**:
   - `devrel-integration/ecosystem.config.js` - PM2 config
   - `docs/deployment/devrel-integration.service` - systemd service
   - `docs/deployment/nginx/devrel-integration.conf` - nginx config (if using domain)

3. **Documentation**:
   - `docs/deployment/server-setup-guide.md` - Comprehensive setup guide
   - `docs/deployment/runbooks/server-operations.md` - Operational runbook
   - `docs/deployment/security-checklist.md` - Security checklist
   - `docs/deployment/verification-checklist.md` - Post-setup verification
   - `docs/deployment/quick-reference.md` - Quick reference card

4. **Environment Template**:
   - Update `devrel-integration/secrets/.env.local.example` if needed

## Success Criteria

The server setup is successful when:
- All scripts execute without errors
- Application starts and responds to health checks
- Discord bot connects and responds to commands
- Security hardening is verified (firewall, fail2ban, SSH)
- Logs are being written and rotated
- Service auto-restarts after failures
- Team can follow documentation to manage the server
- Monitoring shows server and application health

Your mission is to create a production-ready server setup that is secure, reliable, well-documented, and easy to maintain. The scripts should be reusable for setting up additional servers in the future."
/>
