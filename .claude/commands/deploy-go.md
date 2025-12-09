---
description: Execute production deployment after security audit approval (requires "LET'S FUCKING GO" approval)
---

I'm launching the devops-crypto-architect agent in **production deployment mode** to execute the approved deployment.

**Prerequisites**:
This command requires security audit approval. It will check `docs/a2a/deployment-feedback.md` for "APPROVED - LET'S FUCKING GO" status.

**Workflow Position**:
```
/setup-server → /audit-deployment → (repeat until approved) → /deploy-go
```

**What this command does**:
1. **Verify approval**: Check that `docs/a2a/deployment-feedback.md` contains "APPROVED - LET'S FUCKING GO"
2. **Final safety check**: Confirm with user before proceeding
3. **Guide deployment execution**: Walk through executing scripts on target server
4. **Verify deployment**: Run verification checklist
5. **Document completion**: Update deployment status

**If not approved**: The command will refuse to proceed and direct you to fix issues first.

Let me launch the agent now.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are executing a **Production Deployment** that has been approved by security audit. This is the final step in the deployment feedback loop.

## Phase 0: Verify Security Approval (BLOCKING)

BEFORE doing anything else, check `docs/a2a/deployment-feedback.md`:

1. If the file DOES NOT EXIST:
   - STOP immediately
   - Inform user: 'Deployment cannot proceed. No security audit has been performed.'
   - Instruct: 'Please run /setup-server first, then /audit-deployment'
   - DO NOT PROCEED

2. If the file EXISTS but status is CHANGES_REQUIRED:
   - STOP immediately
   - Inform user: 'Deployment cannot proceed. Security audit found issues that must be fixed.'
   - Show the critical/high priority issues from the feedback file
   - Instruct: 'Please run /setup-server to address the feedback, then /audit-deployment again'
   - DO NOT PROCEED

3. If the file EXISTS and status is 'APPROVED - LET'S FUCKING GO':
   - Confirm with user: 'Security audit passed. Ready to deploy to production. Proceed? (yes/no)'
   - Wait for explicit confirmation before proceeding
   - If user confirms, proceed to Phase 1

## Phase 1: Pre-Deployment Checklist

Before executing deployment, verify with the user:

### Server Access
- [ ] SSH access to target server confirmed?
- [ ] Deployment user credentials ready?
- [ ] Network connectivity verified?

### Secrets Ready
- [ ] All required API tokens/keys available?
- [ ] .env.local file prepared with real values?
- [ ] Secrets will be transferred securely (NOT via git)?

### Rollback Plan
- [ ] Rollback procedure understood?
- [ ] Previous version backed up (if upgrading)?
- [ ] Team notified of deployment window?

Ask user to confirm these items before proceeding.

## Phase 2: Deployment Execution Guide

Walk the user through executing the deployment scripts on the target server.

### Step 1: Transfer Scripts to Server
```bash
# From local machine - transfer scripts
scp -r docs/deployment/scripts/ user@server:/tmp/deployment-scripts/

# Or use rsync for larger transfers
rsync -avz docs/deployment/scripts/ user@server:/tmp/deployment-scripts/
```

### Step 2: Connect to Server
```bash
ssh user@server
cd /tmp/deployment-scripts
chmod +x *.sh
```

### Step 3: Execute Scripts in Order

Guide user through each script, one at a time:

1. **Initial Setup** (if new server)
```bash
sudo ./01-initial-setup.sh
# Verify: hostname set, user created, SSH hardened
```

2. **Security Hardening**
```bash
sudo ./02-security-hardening.sh
# Verify: UFW active, fail2ban running, updates configured
```

3. **Install Dependencies**
```bash
sudo ./03-install-dependencies.sh
# Verify: node --version, pm2 --version, nginx -v
```

4. **Deploy Application**
```bash
# First, transfer secrets securely (NOT in scripts)
# Create .env.local with real values

sudo ./04-deploy-app.sh
# Verify: Application built, PM2 started
```

5. **Setup Monitoring** (if applicable)
```bash
sudo ./05-setup-monitoring.sh
# Verify: Prometheus running, Grafana accessible
```

6. **Setup SSL** (if applicable)
```bash
sudo ./06-setup-ssl.sh
# Verify: HTTPS working, certificate valid
```

After each script, pause and ask user to confirm success before proceeding.

## Phase 3: Post-Deployment Verification

Run through the verification checklist from `docs/deployment/verification-checklist.md`:

### Server Verification
```bash
# SSH access
ssh user@server 'echo "SSH OK"'

# Firewall status
sudo ufw status

# fail2ban status
sudo systemctl status fail2ban

# Security updates
cat /etc/apt/apt.conf.d/50unattended-upgrades | head -20
```

### Application Verification
```bash
# PM2 status
pm2 status

# Application logs
pm2 logs devrel-bot --lines 50

# Health check
curl -s http://localhost:3000/health || curl -s http://127.0.0.1:3000/health
```

### Service Verification
```bash
# Discord bot responding (check Discord)
# Webhook endpoint accessible
curl -s https://your-domain.com/webhooks/health
```

### SSL Verification (if applicable)
```bash
# Certificate check
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null 2>/dev/null | openssl x509 -noout -dates

# HTTPS redirect
curl -I http://your-domain.com 2>/dev/null | grep -i location
```

## Phase 4: Document Deployment Completion

After successful verification, create deployment completion record.

Update `docs/a2a/deployment-feedback.md` to append:

```markdown

---

## Deployment Execution Record

**Deployment Date**: [YYYY-MM-DD HH:MM UTC]
**Deployed By**: [username]
**Server**: [IP/hostname]
**Environment**: [Production/Staging]

### Deployment Status: DEPLOYED

### Scripts Executed
- [x] 01-initial-setup.sh
- [x] 02-security-hardening.sh
- [x] 03-install-dependencies.sh
- [x] 04-deploy-app.sh
- [x] 05-setup-monitoring.sh (if applicable)
- [x] 06-setup-ssl.sh (if applicable)

### Verification Results
- [x] SSH access working
- [x] Firewall active
- [x] fail2ban running
- [x] Application running (PM2)
- [x] Health check passing
- [x] SSL valid (if applicable)
- [x] Discord bot online (if applicable)

### Post-Deployment Notes
[Any observations, warnings, or follow-up items]

---

**DEPLOYMENT COMPLETE**

Next steps:
1. Monitor application for 24-48 hours
2. Address any MEDIUM/LOW priority items from audit
3. Set up ongoing monitoring alerts
4. Document any operational learnings
```

## Phase 5: Handover

Provide the user with:

1. **Quick Reference**: Key commands for managing the deployment
2. **Monitoring Dashboard**: Link to Grafana/monitoring (if set up)
3. **Log Locations**: Where to find application and system logs
4. **Rollback Procedure**: How to rollback if issues arise
5. **Contact Points**: Who to contact for different types of issues

## Error Handling

If deployment fails at any step:

1. **STOP immediately**
2. **Document the failure**: What step, what error, what state
3. **Assess rollback need**: Is partial deployment dangerous?
4. **Guide rollback if needed**: Use documented rollback procedure
5. **Update feedback file**: Document failure for next attempt

## Critical Requirements

- NEVER proceed without 'APPROVED - LET'S FUCKING GO' status
- ALWAYS get explicit user confirmation before executing
- ALWAYS pause between scripts to verify success
- NEVER rush through verification steps
- ALWAYS document the deployment execution
- If anything fails, STOP and assess before continuing

Your goal is to guide a safe, verified production deployment of the approved infrastructure."
/>
