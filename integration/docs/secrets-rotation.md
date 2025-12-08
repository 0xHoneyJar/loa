# Secrets Rotation Runbook

This runbook provides step-by-step procedures for rotating all secrets used by the DevRel integration. Regular rotation minimizes exposure risk if secrets are leaked.

**CRITICAL**: Follow these procedures exactly. Incorrect rotation can cause service outages.

## Table of Contents

1. [Overview](#overview)
2. [Rotation Schedule](#rotation-schedule)
3. [General Rotation Procedure](#general-rotation-procedure)
4. [Google Service Account Key](#google-service-account-key)
5. [Discord Bot Token](#discord-bot-token)
6. [Anthropic API Key](#anthropic-api-key)
7. [Mirror API Key](#mirror-api-key)
8. [Linear API Key](#linear-api-key)
9. [Emergency Rotation (Compromised Secret)](#emergency-rotation-compromised-secret)
10. [Post-Rotation Verification](#post-rotation-verification)
11. [Troubleshooting](#troubleshooting)

---

## Overview

### Why Rotate Secrets?

Secrets should be rotated regularly because:
- **Minimizes exposure window**: If a secret was leaked months ago, rotation limits damage
- **Reduces blast radius**: Shorter-lived secrets = less time for attackers to exploit
- **Compliance requirement**: Many security standards require regular rotation
- **Defense in depth**: Rotation is additional layer beyond secret scanning

### Rotation Frequency

| Secret | Interval | Next Due |
|--------|----------|----------|
| Google Service Account | 90 days | Check `secrets-rotation-policy.yaml` |
| Discord Bot Token | 90 days | Check `secrets-rotation-policy.yaml` |
| Anthropic API Key | 180 days | Check `secrets-rotation-policy.yaml` |
| Mirror API Key | 90 days | Check `secrets-rotation-policy.yaml` |
| Linear API Key | 90 days | Check `secrets-rotation-policy.yaml` |

### Automated Reminders

The system automatically:
- Checks rotation status daily
- Sends reminders 14 days before expiry
- Sends critical alerts when secrets expire
- Can pause service if rotation overdue

---

## Rotation Schedule

### Check Rotation Status

```bash
cd integration
npm run check-rotation-status
```

This will show:
```
Rotation Status Report:
=======================
✅ google_service_account: OK (45 days remaining)
⚠️  discord_bot_token: EXPIRING SOON (12 days remaining)
🚨 anthropic_api_key: EXPIRED (3 days overdue)
```

### Rotation Priority

When multiple secrets need rotation:

1. **EXPIRED** secrets (overdue) → Rotate immediately
2. **EXPIRING_SOON** secrets (<14 days) → Rotate within 1 week
3. **OK** secrets → No action needed

---

## General Rotation Procedure

Follow this process for ALL secret rotations:

### Phase 1: Pre-Rotation

1. **Schedule rotation window**
   - Choose low-traffic time (e.g., 2-4 AM)
   - Notify team of planned rotation
   - Ensure on-call engineer available

2. **Verify backup/rollback plan**
   - Have old secret available in case of issues
   - Know how to revert if rotation fails
   - Test rollback procedure in staging

3. **Check dependencies**
   - What services use this secret?
   - Will rotation cause any downtime?
   - Are there any scheduled jobs that will be affected?

### Phase 2: Rotation

1. **Generate new secret** (see specific procedures below)

2. **Update all environments**
   - Development environment
   - Staging environment
   - Production environment
   - CI/CD secrets (GitHub Actions)

3. **Restart services**
   - Restart any services using the secret
   - Verify services started successfully
   - Check logs for errors

4. **Test integration**
   - Run integration tests
   - Verify functionality end-to-end
   - Check error rates in monitoring

### Phase 3: Post-Rotation

1. **Revoke old secret**
   - Delete old secret in service provider
   - Confirm old secret no longer works
   - Never skip this step!

2. **Update rotation policy**
   - Update `last_rotated` date in `secrets-rotation-policy.yaml`
   - System will auto-calculate next rotation date
   - Commit change to git

3. **Audit logs**
   - Check for unauthorized access using old secret
   - Look for suspicious activity during rotation window
   - Document any anomalies

4. **Notify team**
   - Confirm rotation complete
   - Share any lessons learned
   - Update runbook if needed

---

## Google Service Account Key

### Purpose
Used for Google Drive API access (reading docs, fetching content)

### Rotation Procedure

#### Step 1: Generate New Service Account Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to: **IAM & Admin** → **Service Accounts**
3. Find your service account (e.g., `devrel-integration@project.iam.gserviceaccount.com`)
4. Click the **3-dot menu** → **Manage keys**
5. Click **Add Key** → **Create new key**
6. Choose **JSON** format
7. Click **Create** (key file downloads automatically)
8. **IMPORTANT**: Store this file securely (do NOT commit to git)

#### Step 2: Update Environment Variables

**Local Development:**
```bash
# Update .env file
GOOGLE_APPLICATION_CREDENTIALS=/path/to/new-service-account-key.json
```

**GitHub Actions:**
```bash
# Update GitHub Secret
# Settings → Secrets and variables → Actions → Repository secrets
# Update GOOGLE_SERVICE_ACCOUNT_KEY with contents of JSON file
```

**Production Environment:**
```bash
# Update environment variable on production server
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/new-service-account-key.json

# Or update secret management system (e.g., AWS Secrets Manager, HashiCorp Vault)
```

#### Step 3: Restart Services

```bash
# Stop integration services
npm run stop

# Start with new credentials
npm run start

# Verify startup
npm run test-google-docs
```

#### Step 4: Test Integration

```bash
# Test Google Drive API access
npm run test-google-docs

# Expected output:
# ✅ Connected to Google Drive
# ✅ Successfully fetched document: PRD-2025-01-15
# ✅ Read permissions verified
```

#### Step 5: Delete Old Service Account Key

1. Go back to [Google Cloud Console](https://console.cloud.google.com/)
2. Navigate to: **IAM & Admin** → **Service Accounts** → **Manage keys**
3. Find the OLD key (check creation date)
4. Click **Delete** button
5. Confirm deletion
6. **Verify**: Old key should no longer work

#### Step 6: Update Rotation Policy

```bash
# Edit integration/config/secrets-rotation-policy.yaml
google_service_account:
  interval_days: 90
  last_rotated: "2025-12-08"  # Today's date (YYYY-MM-DD)
  next_rotation: null  # Will auto-calculate

# Commit change
git add integration/config/secrets-rotation-policy.yaml
git commit -m "chore: Update Google Service Account rotation date"
git push
```

---

## Discord Bot Token

### Purpose
Used for bot authentication and reading/posting messages

### Rotation Procedure

#### Step 1: Reset Token in Discord Developer Portal

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Select your application
3. Navigate to **Bot** tab (left sidebar)
4. Scroll to **Token** section
5. Click **Reset Token**
6. **IMPORTANT**: Confirm you understand this will invalidate the old token
7. Copy new token (you can only see it once!)
8. Store token securely (do NOT commit to git)

#### Step 2: Update Environment Variables

**Local Development:**
```bash
# Update .env file
DISCORD_BOT_TOKEN=NEW_TOKEN_HERE
```

**GitHub Actions:**
```bash
# Update GitHub Secret
# Settings → Secrets and variables → Actions → Repository secrets
# Update DISCORD_BOT_TOKEN
```

**Production Environment:**
```bash
export DISCORD_BOT_TOKEN=NEW_TOKEN_HERE
# Or update secret management system
```

#### Step 3: Restart Discord Bot

```bash
# Stop bot
npm run discord-bot:stop

# Start with new token
npm run discord-bot

# Verify bot is online in Discord server
```

#### Step 4: Test Bot Commands

```bash
# In Discord, send test command:
/ping

# Expected response:
# Pong! Bot is online.

# Test summary command:
/generate-summary

# Expected: Command executes successfully
```

#### Step 5: Verify Old Token Invalid

```bash
# Try using old token (should fail)
curl -H "Authorization: Bot OLD_TOKEN_HERE" \
  https://discord.com/api/v10/users/@me

# Expected response: 401 Unauthorized
```

#### Step 6: Update Rotation Policy

```bash
# Edit integration/config/secrets-rotation-policy.yaml
discord_bot_token:
  interval_days: 90
  last_rotated: "2025-12-08"  # Today's date
  next_rotation: null  # Will auto-calculate

# Commit change
git add integration/config/secrets-rotation-policy.yaml
git commit -m "chore: Update Discord bot token rotation date"
git push
```

---

## Anthropic API Key

### Purpose
Used for Claude API calls (summarization, translation)

### Rotation Procedure

#### Step 1: Create New API Key

1. Go to [Anthropic Console](https://console.anthropic.com/)
2. Navigate to **API Keys** section
3. Click **Create Key**
4. Give it a name (e.g., `devrel-integration-2025-12-08`)
5. Copy the key (you can only see it once!)
6. Store securely (do NOT commit to git)

#### Step 2: Update Environment Variables

**Local Development:**
```bash
# Update .env file
ANTHROPIC_API_KEY=NEW_KEY_HERE
```

**GitHub Actions:**
```bash
# Update GitHub Secret
ANTHROPIC_API_KEY=NEW_KEY_HERE
```

**Production Environment:**
```bash
export ANTHROPIC_API_KEY=NEW_KEY_HERE
```

#### Step 3: Restart Services

```bash
npm run stop
npm run start
```

#### Step 4: Test API Access

```bash
# Test Anthropic API
npm run test-translation

# Expected output:
# ✅ Connected to Anthropic API
# ✅ Successfully generated translation
# ✅ Token usage: 1234 tokens
```

#### Step 5: Delete Old API Key

1. Go back to [Anthropic Console](https://console.anthropic.com/)
2. Navigate to **API Keys**
3. Find the old key (check creation date)
4. Click **Delete**
5. Confirm deletion
6. **Verify**: Old key should return 401 Unauthorized

#### Step 6: Update Rotation Policy

```bash
# Edit integration/config/secrets-rotation-policy.yaml
anthropic_api_key:
  interval_days: 180
  last_rotated: "2025-12-08"
  next_rotation: null

# Commit change
git add integration/config/secrets-rotation-policy.yaml
git commit -m "chore: Update Anthropic API key rotation date"
git push
```

---

## Mirror API Key

### Purpose
Used for publishing blog posts to Mirror.xyz

### Rotation Procedure

#### Step 1: Create New API Key

1. Go to [Mirror.xyz](https://mirror.xyz/)
2. Navigate to **Settings** → **API Keys**
3. Click **Create New API Key**
4. Copy the key
5. Store securely

#### Step 2: Update Environment Variables

```bash
# Update .env file
MIRROR_API_KEY=NEW_KEY_HERE
```

#### Step 3: Test Integration

```bash
npm run test-blog-publishing

# Expected: Successfully connected to Mirror API
```

#### Step 4: Revoke Old API Key

1. Go to Mirror.xyz → Settings → API Keys
2. Find old key
3. Click **Revoke**
4. Confirm

#### Step 5: Update Rotation Policy

```bash
# Edit integration/config/secrets-rotation-policy.yaml
mirror_api_key:
  interval_days: 90
  last_rotated: "2025-12-08"
  next_rotation: null

git add integration/config/secrets-rotation-policy.yaml
git commit -m "chore: Update Mirror API key rotation date"
git push
```

---

## Linear API Key

### Purpose
Used for creating/updating Linear issues

### Rotation Procedure

#### Step 1: Create New API Key

1. Go to [Linear Settings](https://linear.app/settings)
2. Navigate to **API** section
3. Click **Create New API Key**
4. Give it a label (e.g., `devrel-integration-2025-12-08`)
5. Copy the key
6. Store securely

#### Step 2: Update Environment Variables

```bash
# Update .env file
LINEAR_API_KEY=NEW_KEY_HERE
```

#### Step 3: Test Integration

```bash
npm run test-linear

# Expected: Successfully connected to Linear API
```

#### Step 4: Revoke Old API Key

1. Go back to Linear Settings → API
2. Find old key
3. Click **Revoke**
4. Confirm

#### Step 5: Update Rotation Policy

```bash
# Edit integration/config/secrets-rotation-policy.yaml
linear_api_key:
  interval_days: 90
  last_rotated: "2025-12-08"
  next_rotation: null

git add integration/config/secrets-rotation-policy.yaml
git commit -m "chore: Update Linear API key rotation date"
git push
```

---

## Emergency Rotation (Compromised Secret)

**IF A SECRET IS COMPROMISED, FOLLOW THIS PROCEDURE IMMEDIATELY**

### Priority: P0 - Critical Incident

### Step 1: Immediate Response (within 5 minutes)

1. **PAUSE ALL SERVICES**
   ```bash
   npm run emergency-pause
   ```

2. **REVOKE COMPROMISED SECRET IMMEDIATELY**
   - Go to service provider (Google/Discord/Anthropic)
   - Delete/revoke the compromised secret NOW
   - Do not wait for new secret generation
   - Every second counts!

3. **ALERT SECURITY TEAM**
   - Slack: `@security-team SECRET COMPROMISED`
   - Email: security-team@company.com
   - PagerDuty: Trigger P0 incident

### Step 2: Generate and Deploy New Secret (within 15 minutes)

1. **Generate new secret** (follow specific procedure above)

2. **Update ALL environments**
   - Dev, staging, production
   - GitHub Actions secrets
   - Any backup/DR systems

3. **Restart services**
   ```bash
   npm run start
   ```

### Step 3: Forensic Investigation (within 1 hour)

1. **Audit logs for unauthorized access**
   - Search for API calls using old secret
   - Check timestamps, IP addresses, user agents
   - Look for suspicious patterns

2. **Document the incident**
   - How was secret compromised?
   - What data was accessed?
   - What was the blast radius?

3. **Collect evidence**
   - Save relevant logs
   - Screenshot service provider activity
   - Document timeline

### Step 4: Containment (within 4 hours)

1. **Assess damage**
   - What data was exposed?
   - What unauthorized actions were taken?
   - Are there any persistent threats?

2. **Remediate**
   - Rotate any related secrets
   - Patch vulnerability that caused leak
   - Update security controls

3. **Notify stakeholders**
   - CTO
   - Legal team (if user data exposed)
   - Customers (if required by law)

### Step 5: Post-Mortem (within 1 week)

1. **Conduct post-mortem meeting**
   - What happened?
   - Why did it happen?
   - How can we prevent it?

2. **Document lessons learned**
   - Update this runbook
   - Add new security controls
   - Train team on prevention

3. **Implement improvements**
   - Prevent similar incidents
   - Improve detection
   - Improve response time

---

## Post-Rotation Verification

After rotating ANY secret, complete this checklist:

### Verification Checklist

- [ ] New secret generated successfully
- [ ] All environments updated (dev, staging, prod)
- [ ] Services restarted without errors
- [ ] Integration tests pass
- [ ] Old secret revoked/deleted
- [ ] Old secret verified as invalid
- [ ] Rotation policy updated with new date
- [ ] Changes committed to git
- [ ] No errors in service logs
- [ ] No increase in error rates (check monitoring)
- [ ] Audit logs reviewed for suspicious activity
- [ ] Team notified of completion
- [ ] Runbook updated if needed

### Rollback Procedure (if rotation fails)

If the rotation causes issues:

1. **Identify the problem**
   - Check service logs
   - Check error rates
   - Identify failing component

2. **Revert to old secret temporarily**
   - Update environment variables back to old secret
   - Restart services
   - Verify services healthy

3. **Investigate root cause**
   - Why did rotation fail?
   - Was it a configuration issue?
   - Was the new secret invalid?

4. **Fix and retry**
   - Resolve the issue
   - Attempt rotation again
   - Document what went wrong

---

## Troubleshooting

### Problem: "Rotation reminder not received"

**Symptoms**: No email/Discord alert 14 days before expiry

**Diagnosis**:
```bash
# Check rotation monitor status
npm run check-rotation-status

# Check notification configuration
cat integration/config/secrets-rotation-policy.yaml
```

**Fix**:
1. Verify `notification_channels` configured in policy
2. Verify email SMTP settings
3. Verify Discord webhook URL
4. Check cron job is running

### Problem: "Old secret still works after deletion"

**Symptoms**: Old secret not revoked after rotation

**Diagnosis**:
- Caching issue
- Service provider propagation delay
- Wrong secret deleted

**Fix**:
1. Wait 5-10 minutes for propagation
2. Verify you deleted the correct secret
3. Check service provider console for active keys
4. Contact service provider support if issue persists

### Problem: "Service down after rotation"

**Symptoms**: 500 errors, service unreachable

**Diagnosis**:
```bash
# Check service logs
npm run logs

# Check environment variables loaded
npm run env-check

# Test secret manually
npm run test-secret <secret-name>
```

**Fix**:
1. Verify new secret is valid
2. Verify environment variable updated
3. Verify service restarted
4. Rollback to old secret if needed

### Problem: "GitHub Actions failing after rotation"

**Symptoms**: CI/CD pipeline fails, can't deploy

**Diagnosis**:
- Check GitHub Actions logs
- Verify secret updated in GitHub Settings

**Fix**:
1. Go to GitHub → Settings → Secrets
2. Update the secret
3. Re-run failed workflow

---

## Additional Resources

- **Secrets Rotation Policy**: `integration/config/secrets-rotation-policy.yaml`
- **Rotation Monitor**: `integration/src/services/secrets-rotation-monitor.ts`
- **Leak Detector**: `integration/src/services/secrets-leak-detector.ts`
- **Secret Scanner**: `integration/src/services/secret-scanner.ts`
- **Security Audit**: `docs/audits/2025-12-08_1/DEVREL-INTEGRATION-SECURITY-AUDIT.md`

---

## Rotation Log

Keep a record of all rotations:

| Date | Secret | Rotated By | Reason | Notes |
|------|--------|------------|--------|-------|
| 2025-12-08 | google_service_account | alice@company.com | Scheduled | No issues |
| 2025-12-08 | discord_bot_token | bob@company.com | Scheduled | No issues |
| | | | | |

**Location**: `docs/runbooks/rotation-log.md` (create if needed)

---

**Last Updated**: 2025-12-08
**Next Review**: 2026-03-08 (quarterly review)
