# Secrets Rotation Procedures

**Last Updated:** 2025-12-09
**Review Schedule:** Quarterly (every 90 days)
**Responsible:** DevOps Team, Security Team

---

## Overview

This runbook provides step-by-step procedures for rotating all secrets and credentials used by the DevRel integration application. Regular secret rotation is a critical security practice that limits the blast radius of credential leaks.

**Rotation Schedule:**
- **Quarterly (90 days)**: All API tokens, webhook secrets
- **Emergency**: Immediately upon suspected compromise
- **After incidents**: Within 24 hours of any security incident
- **Team changes**: When team members with access leave

---

## Pre-Rotation Checklist

Before rotating any secrets:

- [ ] **Schedule maintenance window** (if zero-downtime not possible)
- [ ] **Notify team** of upcoming rotation via Slack/Discord
- [ ] **Backup current secrets** to encrypted vault:
  ```bash
  gpg --encrypt --recipient admin@company.com \
      /opt/devrel-integration/secrets/.env.production > \
      /opt/devrel-integration/backups/secrets-backup-$(date +%Y%m%d).gpg
  ```
- [ ] **Verify access** to all service provider portals (Discord, Linear, GitHub, Vercel)
- [ ] **Document current configuration** in rotation log
- [ ] **Have rollback plan ready** (keep old secrets for 24h)

---

## Discord Bot Token Rotation

### When to Rotate
- Quarterly (every 90 days)
- If token appears in logs, commits, or public locations
- After team member with access leaves
- As part of security incident response

### Rotation Procedure

#### 1. Pre-Rotation Checks (5 minutes)

```bash
# Identify all places token is used
grep -r "DISCORD_BOT_TOKEN" /opt/devrel-integration/
cat /opt/devrel-integration/secrets/.env.production | grep DISCORD
cat /opt/devrel-integration/secrets/.env.staging | grep DISCORD
```

- [ ] Document all locations where token is referenced
- [ ] Verify CI/CD secrets (GitHub Actions, GitLab CI, etc.)
- [ ] Check backup systems for old tokens

#### 2. Generate New Token (5 minutes)

1. **Navigate to Discord Developer Portal**:
   - URL: https://discord.com/developers/applications
   - Select your application

2. **Regenerate Bot Token**:
   - Go to "Bot" section
   - Click "Reset Token"
   - **WARNING: Old token is immediately revoked!**
   - Copy new token (only shown once)

3. **Test New Token** (before deploying):
   ```bash
   # Quick validation
   NEW_TOKEN="your_new_token_here"
   curl -H "Authorization: Bot ${NEW_TOKEN}" \
        https://discord.com/api/users/@me

   # Expected: {"id": "...", "username": "...", "bot": true}
   # If error: Token is invalid or has wrong permissions
   ```

#### 3. Deploy New Token (10 minutes)

**Production Environment:**
```bash
# SSH into production server
ssh user@production-server

# Edit production secrets file
sudo -u devrel nano /opt/devrel-integration/secrets/.env.production

# Update DISCORD_BOT_TOKEN with new value
# Save and exit (Ctrl+X, Y, Enter)

# Verify file permissions
ls -la /opt/devrel-integration/secrets/.env.production
# Should be: -rw------- (600) devrel devrel

# Fix if needed
sudo chmod 600 /opt/devrel-integration/secrets/.env.production
```

**Staging Environment:**
```bash
# Repeat for staging
ssh user@staging-server
sudo -u devrel nano /opt/devrel-integration/secrets/.env.staging
# Update token and save
```

**CI/CD Secrets:**
- Update GitHub Actions secrets (Settings → Secrets and variables → Actions)
- Update GitLab CI/CD variables (Settings → CI/CD → Variables)
- Update any other CI/CD platforms

#### 4. Restart Services (5 minutes)

**Production:**
```bash
# If using PM2
pm2 restart devrel-bot

# If using systemd
sudo systemctl restart devrel-integration

# If using Docker
docker-compose -f docker-compose.prod.yml restart
```

Wait 30 seconds for service to start.

#### 5. Verify Rotation (10 minutes)

```bash
# Check service is running
pm2 status
# OR
sudo systemctl status devrel-integration

# Check logs for successful connection
pm2 logs devrel-bot --lines 50 | grep -i discord
# Look for: "Discord bot connected" or similar

# Verify bot is online in Discord
# Check bot status in server (should show as "Online")

# Test a command
# In Discord: Try a bot command to verify functionality
```

**Verification Checklist:**
- [ ] Bot shows as "Online" in Discord server
- [ ] Bot responds to commands
- [ ] Logs show no authentication errors
- [ ] Health endpoint shows Discord: connected
  ```bash
  curl -s http://localhost:3000/health | jq .
  ```

#### 6. Post-Rotation (5 minutes)

```bash
# Update rotation log
echo "$(date +%Y-%m-%d): Discord token rotated by ${USER}" | \
    sudo tee -a /var/log/secrets-rotation.log

# Old token is automatically revoked by Discord (no manual action needed)

# Schedule next rotation (90 days)
# Add to calendar: $(date -d "+90 days" +%Y-%m-%d)
```

**Total Time: ~40 minutes**

---

## Linear API Key Rotation

### When to Rotate
- Quarterly (every 90 days)
- If key appears in logs or public locations
- After team member with access leaves
- As part of security incident response

### Rotation Procedure

#### 1. Pre-Rotation Checks (5 minutes)

```bash
# Identify all places key is used
grep -r "LINEAR_API_KEY" /opt/devrel-integration/
```

- [ ] Document all locations
- [ ] Check CI/CD secrets
- [ ] Verify backup systems

#### 2. Generate New API Key (5 minutes)

1. **Navigate to Linear API Settings**:
   - URL: https://linear.app/your-workspace/settings/api
   - Go to "Personal API Keys" section

2. **Create New API Key**:
   - Click "Create new key"
   - Name: "DevRel Bot Production - $(date +%Y-%m-%d)"
   - Copy the API key (starts with `lin_api_`)
   - **Do NOT delete old key yet** (zero-downtime rotation)

3. **Test New Key**:
   ```bash
   NEW_KEY="lin_api_your_new_key_here"
   curl -H "Authorization: ${NEW_KEY}" \
        -H "Content-Type: application/json" \
        https://api.linear.app/graphql \
        -d '{"query": "{ viewer { id name email } }"}'

   # Expected: {"data": {"viewer": {"id": "...", "name": "...", "email": "..."}}}
   ```

#### 3. Deploy New Key (10 minutes)

Update production, staging, and CI/CD environments:

```bash
# Production
ssh user@production-server
sudo -u devrel nano /opt/devrel-integration/secrets/.env.production
# Update LINEAR_API_KEY
# Save and exit

# Staging
ssh user@staging-server
sudo -u devrel nano /opt/devrel-integration/secrets/.env.staging
# Update LINEAR_API_KEY
```

Update CI/CD secrets in all platforms.

#### 4. Restart Services (5 minutes)

```bash
# Production
pm2 restart devrel-bot
# OR
sudo systemctl restart devrel-integration
```

#### 5. Verify Rotation (10 minutes)

```bash
# Check logs
pm2 logs devrel-bot --lines 50 | grep -i linear

# Test Linear integration
# Create a test issue in Linear and verify bot responds

# Check health endpoint
curl -s http://localhost:3000/health | jq .
# Verify linear status is "operational"
```

**Verification Checklist:**
- [ ] Bot can read Linear issues
- [ ] Bot can create/update Linear issues
- [ ] Webhooks still work (test by updating an issue)
- [ ] No authentication errors in logs

#### 6. Delete Old Key (24 hours later)

**IMPORTANT: Wait 24 hours before deleting old key** (in case rollback needed).

After 24 hours of successful operation:
1. Go to Linear API settings
2. Find old API key
3. Click "Revoke" to delete it

```bash
# Update rotation log
echo "$(date +%Y-%m-%d): Linear API key rotated by ${USER}" | \
    sudo tee -a /var/log/secrets-rotation.log
```

**Total Time: ~35 minutes + 24h waiting period**

---

## Linear Webhook Secret Rotation

### Rotation Procedure

#### 1. Generate New Secret (2 minutes)

```bash
# Generate secure random secret (64 characters)
NEW_SECRET=$(openssl rand -hex 32)
echo "New webhook secret: ${NEW_SECRET}"
# Save this temporarily (will update in both Linear and app)
```

#### 2. Update Application First (Zero-Downtime) (5 minutes)

```bash
# Update .env.production with NEW secret
ssh user@production-server
sudo -u devrel nano /opt/devrel-integration/secrets/.env.production

# Update LINEAR_WEBHOOK_SECRET to new value
# KEEP OLD SECRET for now (Linear still uses it)
```

Restart service:
```bash
pm2 restart devrel-bot
```

Verify service started successfully.

#### 3. Update Linear Webhook Configuration (5 minutes)

1. **Navigate to Linear Webhook Settings**:
   - Linear → Settings → Webhooks
   - Find your webhook

2. **Update Webhook Secret**:
   - Edit webhook
   - Update "Secret" field with new value from step 1
   - Save changes

3. **Test Webhook**:
   - Trigger a test webhook (update an issue)
   - Check application logs for successful webhook receipt
   ```bash
   pm2 logs devrel-bot | grep -i webhook
   # Should see: "Webhook signature verified"
   ```

#### 4. Verify Rotation (5 minutes)

- [ ] Test webhook by creating/updating Linear issue
- [ ] Verify webhook is received by application
- [ ] Check logs for signature verification success
- [ ] No signature validation errors

```bash
echo "$(date +%Y-%m-%d): Linear webhook secret rotated by ${USER}" | \
    sudo tee -a /var/log/secrets-rotation.log
```

**Total Time: ~17 minutes**

---

## GitHub Token Rotation

*(Only if GitHub integration is enabled)*

### Rotation Procedure

#### 1. Generate New Token (5 minutes)

1. **Navigate to GitHub Token Settings**:
   - URL: https://github.com/settings/tokens
   - Click "Generate new token (classic)"

2. **Configure Token**:
   - Note: "DevRel Bot Production - $(date +%Y-%m-%d)"
   - Expiration: 90 days (recommended)
   - Select scopes:
     - `repo` (full control of private repositories)
     - `admin:repo_hook` (repository webhooks)
     - `read:org` (organization membership)
   - Click "Generate token"
   - **Copy token immediately** (starts with `ghp_`)

3. **Test Token**:
   ```bash
   NEW_TOKEN="ghp_your_new_token"
   curl -H "Authorization: token ${NEW_TOKEN}" \
        https://api.github.com/user

   # Expected: {"login": "...", "id": ..., ...}
   ```

#### 2. Deploy New Token (10 minutes)

Update all environments:
```bash
# Production
ssh user@production-server
sudo -u devrel nano /opt/devrel-integration/secrets/.env.production
# Update GITHUB_TOKEN

# Staging
ssh user@staging-server
sudo -u devrel nano /opt/devrel-integration/secrets/.env.staging
# Update GITHUB_TOKEN
```

#### 3. Restart Services (5 minutes)

```bash
pm2 restart devrel-bot
```

#### 4. Verify Rotation (10 minutes)

```bash
# Test GitHub integration
# Trigger a GitHub webhook (create PR, push commit)
# Verify bot receives webhook

pm2 logs devrel-bot | grep -i github
# Should see successful GitHub API calls
```

#### 5. Delete Old Token (Immediately)

Unlike Linear, GitHub tokens can be revoked immediately:
1. Go to https://github.com/settings/tokens
2. Find old token
3. Click "Delete"

```bash
echo "$(date +%Y-%m-%d): GitHub token rotated by ${USER}" | \
    sudo tee -a /var/log/secrets-rotation.log
```

**Total Time: ~30 minutes**

---

## GitHub Webhook Secret Rotation

### Rotation Procedure

Similar to Linear webhook secret rotation:

1. **Generate New Secret**:
   ```bash
   NEW_SECRET=$(openssl rand -hex 32)
   ```

2. **Update Application Configuration** (app config first, then GitHub)

3. **Update GitHub Webhook Settings**:
   - Repository → Settings → Webhooks
   - Edit webhook
   - Update "Secret" field
   - Save

4. **Test Webhook** by triggering GitHub event

**Total Time: ~15 minutes**

---

## Vercel Token Rotation

*(Only if Vercel integration is enabled)*

### Rotation Procedure

#### 1. Generate New Token (5 minutes)

1. **Navigate to Vercel Tokens**:
   - URL: https://vercel.com/account/tokens
   - Click "Create"

2. **Configure Token**:
   - Name: "DevRel Bot Production - $(date +%Y-%m-%d)"
   - Scope: Full access (or project-specific if available)
   - Expiration: 90 days (if available)
   - Click "Create"
   - **Copy token immediately**

3. **Test Token**:
   ```bash
   NEW_TOKEN="your_new_vercel_token"
   curl -H "Authorization: Bearer ${NEW_TOKEN}" \
        https://api.vercel.com/v2/user

   # Expected: {"user": {"id": "...", "email": "...", ...}}
   ```

#### 2. Deploy New Token (10 minutes)

Update all environments.

#### 3. Restart Services (5 minutes)

```bash
pm2 restart devrel-bot
```

#### 4. Verify Rotation (10 minutes)

Test Vercel integration by triggering deployment webhook.

#### 5. Delete Old Token (Immediately)

1. Go to https://vercel.com/account/tokens
2. Find old token
3. Click "Delete"

```bash
echo "$(date +%Y-%m-%d): Vercel token rotated by ${USER}" | \
    sudo tee -a /var/log/secrets-rotation.log
```

**Total Time: ~30 minutes**

---

## Emergency Rotation (Credential Leak)

**If a secret is compromised, rotate IMMEDIATELY:**

### Incident Response Steps

1. **Isolate (0-5 minutes)**:
   - Stop using the leaked secret immediately
   - Do NOT wait for maintenance window
   - Alert security team

2. **Rotate (5-15 minutes)**:
   - Generate new secret
   - Deploy to PRODUCTION FIRST (highest priority)
   - Deploy to staging after production is secure

3. **Verify (15-20 minutes)**:
   - Confirm new secret works in production
   - Test all integration points
   - Check for any errors

4. **Revoke (20-25 minutes)**:
   - Immediately revoke/delete leaked secret
   - Do NOT wait 24 hours in emergency scenarios
   - Verify old secret no longer works

5. **Audit (25-60 minutes)**:
   - Review logs for unauthorized use of leaked secret
   - Check for any suspicious activity during exposure window
   - Document findings in incident report

6. **Document (60+ minutes)**:
   - Create incident report
   - Timeline of exposure
   - Actions taken
   - Lessons learned
   - Preventive measures

### Emergency Contacts

- **Security Team**: security@company.com
- **On-Call Engineer**: [Phone/PagerDuty]
- **CTO/Technical Lead**: [Phone for P0 escalation]

---

## Rotation Log Format

Maintain a rotation log at `/var/log/secrets-rotation.log`:

```
2025-12-09: Discord token rotated by alice (scheduled quarterly)
2025-12-09: Linear API key rotated by alice (scheduled quarterly)
2025-12-09: Linear webhook secret rotated by alice (scheduled quarterly)
2025-12-15: GitHub token rotated by bob (team member departure)
2025-12-20: Discord token rotated by alice (EMERGENCY - leaked in logs)
```

Format:
```
YYYY-MM-DD: [Service] [Secret Type] rotated by [User] ([Reason])
```

---

## Automation Recommendations

### Future Improvements

1. **Automated Rotation Reminders**:
   - Set up cron job to alert team 7 days before 90-day mark
   - Send notification to Slack/Discord

2. **Rotation Scripts**:
   - Create scripts to automate common rotation tasks
   - Reduce manual steps and human error

3. **Secret Management Tools**:
   - Consider HashiCorp Vault for centralized secret management
   - Evaluate AWS Secrets Manager, GCP Secret Manager
   - Implement automatic secret rotation where supported

4. **Monitoring**:
   - Alert if secrets older than 90 days
   - Track last rotation date in monitoring system

---

## Troubleshooting

### Issue: Service Won't Start After Rotation

**Symptoms**: Application crashes immediately after restart

**Diagnosis**:
```bash
# Check logs for authentication errors
pm2 logs devrel-bot --lines 100 | grep -i error

# Common errors:
# - "Invalid token"
# - "401 Unauthorized"
# - "403 Forbidden"
```

**Resolution**:
1. Verify new secret is correct (no typos, extra spaces)
2. Verify secret format matches service requirements
3. Verify file permissions: `600` on `.env` files
4. Test secret manually with curl command
5. Rollback to old secret if new secret invalid

### Issue: Webhooks Stop Working After Rotation

**Symptoms**: Webhook events not received

**Diagnosis**:
```bash
# Check webhook signature validation
pm2 logs devrel-bot | grep -i "signature"
# Look for: "Invalid signature" or "Signature verification failed"
```

**Resolution**:
1. Verify webhook secret matches in both application and service
2. Check webhook secret encoding (no special characters issues)
3. Verify webhook is still configured in service portal
4. Test webhook manually with service's test feature

### Issue: Old Token Still Being Used

**Symptoms**: Old token appears in logs after rotation

**Diagnosis**:
```bash
# Check all environment files
grep -r "old_token_here" /opt/devrel-integration/
# Check CI/CD secrets
```

**Resolution**:
1. Verify all `.env` files updated
2. Check if application was actually restarted
3. Verify no cached tokens in memory
4. Check CI/CD secrets in all platforms

---

## Compliance Notes

**SOC 2 Compliance**: Regular secret rotation is required for SOC 2 Type 2 certification.

**GDPR Compliance**: Credential management is part of data security requirements.

**Industry Best Practice**: NIST recommends rotating credentials every 60-90 days.

---

## Appendix: Secret Inventory

| Secret | Service | Location | Rotation Frequency | Last Rotated |
|--------|---------|----------|-------------------|--------------|
| Discord Bot Token | Discord | `.env.production` | 90 days | YYYY-MM-DD |
| Linear API Key | Linear | `.env.production` | 90 days | YYYY-MM-DD |
| Linear Webhook Secret | Linear | `.env.production` | 90 days | YYYY-MM-DD |
| GitHub Token | GitHub | `.env.production` | 90 days | YYYY-MM-DD |
| GitHub Webhook Secret | GitHub | `.env.production` | 90 days | YYYY-MM-DD |
| Vercel Token | Vercel | `.env.production` | 90 days | YYYY-MM-DD |
| Vercel Webhook Secret | Vercel | `.env.production` | 90 days | YYYY-MM-DD |

**Update this table after each rotation.**

---

**End of Secrets Rotation Runbook**
