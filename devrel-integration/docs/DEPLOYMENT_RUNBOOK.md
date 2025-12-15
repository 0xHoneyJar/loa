# Onomancer Bot Deployment Runbook

> Production deployment procedures for Onomancer Bot

## Table of Contents

0. [Credentials Setup Guide](./CREDENTIALS_SETUP_GUIDE.md) *(Prerequisite - create tokens first)*
1. [Prerequisites](#prerequisites)
2. [Fresh Server Setup](#fresh-server-setup) *(NEW)*
3. [Pre-Deployment Checklist](#pre-deployment-checklist)
4. [Deployment Procedure](#deployment-procedure)
5. [Post-Deployment Verification](#post-deployment-verification)
6. [Rollback Procedure](#rollback-procedure)
7. [Monitoring & Alerting](#monitoring--alerting)
8. [Common Operations](#common-operations)
9. [Troubleshooting](#troubleshooting)
10. [Lessons Learned](#lessons-learned)
11. [Appendix C: Script Development Standards](#appendix-c-script-development-standards)
12. [Appendix D: Security Audit Reference Checklist](#appendix-d-security-audit-reference-checklist)

---

## Prerequisites

> **First-time setup?** See the [Credentials Setup Guide](./CREDENTIALS_SETUP_GUIDE.md) for step-by-step instructions to create all required tokens and credentials from scratch (Discord, Google Cloud, Linear, Anthropic).

### Server Requirements

- **OS**: Ubuntu 22.04 LTS or Debian 12
- **Node.js**: v18.x or higher (LTS)
- **RAM**: Minimum 1GB (2GB recommended)
- **Disk**: 10GB available
- **Network**: Outbound access to Discord, Google APIs, Anthropic API

### Required Accounts & Access

> **Need to create these from scratch?** Follow the [Credentials Setup Guide](./CREDENTIALS_SETUP_GUIDE.md)

- [ ] Discord Bot Token (from Discord Developer Portal)
- [ ] Google Cloud Service Account with Drive API access
- [ ] Anthropic API Key
- [ ] Linear API Token (optional)
- [ ] Server SSH access

### Tools Required

- PM2 (`npm install -g pm2`)
- Git
- Node.js & npm

---

## Fresh Server Setup

> Complete guide to setting up a brand new server from scratch.
> Based on lessons learned from prototype deployment (December 2024).

### Step 1: Initial Server Configuration

```bash
# Connect to server as root or sudo user
ssh root@your-server-ip

# Update system packages
apt update && apt upgrade -y

# Install essential tools
apt install -y curl git jq htop unzip vim ufw fail2ban

# Set timezone
timedatectl set-timezone UTC
```

### Step 2: Create Dedicated Service User

**CRITICAL**: Run the bot under a dedicated non-root user for security isolation.

```bash
# Create devrel user with home directory
useradd -m -s /bin/bash devrel

# Create application directory
mkdir -p /opt/devrel-integration
chown devrel:devrel /opt/devrel-integration

# Create logs directory
mkdir -p /var/log/devrel
chown devrel:devrel /var/log/devrel
```

### Step 3: Security Hardening

```bash
# Configure UFW firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 443/tcp   # HTTPS (if using nginx)
# WARNING: Only allow 3000 for initial testing. Remove after nginx is configured!
# In production, app should only be accessible via nginx reverse proxy (localhost:3000)
ufw allow 3000/tcp  # App port - REMOVE THIS after nginx setup
ufw --force enable

# Enable fail2ban for SSH protection
systemctl enable fail2ban
systemctl start fail2ban

# RECOMMENDED: Disable root login and password auth (do this AFTER confirming SSH key access works)
# Edit /etc/ssh/sshd_config:
#   PermitRootLogin no
#   PasswordAuthentication no
# Then: systemctl restart sshd
# WARNING: Ensure you have SSH key access configured before disabling password auth!
```

### Step 4: Install Node.js and PM2

```bash
# Install Node.js 20 LTS (as root)
# Note: NodeSource is an official trusted source. For higher security environments,
# consider downloading and verifying checksums manually from https://nodejs.org
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Verify installation
node --version   # Should show v20.x.x
npm --version

# Install PM2 globally
npm install -g pm2
```

### Step 5: Configure PM2 with Custom Home Directory

**IMPORTANT**: This is a key lesson from prototype deployment. Running PM2 with a custom
`PM2_HOME` inside the application directory keeps everything self-contained and makes
it easier to manage when the bot runs as a different user.

```bash
# Switch to devrel user
su - devrel

# Set up PM2 home inside application directory
export PM2_HOME=/opt/devrel-integration/.pm2
mkdir -p $PM2_HOME

# Add to devrel's .bashrc for persistence
echo 'export PM2_HOME=/opt/devrel-integration/.pm2' >> ~/.bashrc

# Configure PM2 startup (run as root, specify devrel user)
exit  # Back to root
PM2_HOME=/opt/devrel-integration/.pm2 pm2 startup systemd -u devrel --hp /home/devrel
```

### Step 6: Deploy Application Code

```bash
# Switch to devrel user
su - devrel
cd /opt/devrel-integration

# Clone repository (or copy files)
git clone https://github.com/your-org/agentic-base.git .
# Or if copying: scp -r ./devrel-integration/* devrel@server:/opt/devrel-integration/

# Navigate to integration directory if needed
cd devrel-integration  # (if repo has this structure)

# Install dependencies
npm ci

# Build TypeScript
npm run build

# Copy non-TypeScript assets to dist (not handled by tsc)
cp src/database/schema.sql dist/database/

# Verify build succeeded
ls -la dist/bot.js
ls -la dist/database/schema.sql
```

### Step 7: Configure Secrets

```bash
# Create secrets directory
mkdir -p secrets

# Copy example and edit
cp secrets/.env.local.example secrets/.env.local
vim secrets/.env.local

# Set secure permissions (CRITICAL)
chmod 600 secrets/.env.local
```

**Required Environment Variables** (Sprint 4 full feature set):

```bash
# === DISCORD (Required) ===
DISCORD_BOT_TOKEN=your_discord_bot_token
DISCORD_CLIENT_ID=your_discord_client_id
DISCORD_GUILD_ID=your_discord_guild_id
DISCORD_DIGEST_CHANNEL_ID=your_digest_channel_id

# === DISCORD ROLES (Required for RBAC) ===
ADMIN_ROLE_ID=your_admin_role_id
DEVELOPER_ROLE_ID=your_developer_role_id
RESEARCHER_ROLE_ID=your_researcher_role_id  # Optional

# === LINEAR (Required for sprint features) ===
LINEAR_API_TOKEN=lin_api_xxxxxxxxxxxx
LINEAR_TEAM_ID=your-team-uuid
LINEAR_WEBHOOK_SECRET=your_webhook_secret  # For webhook verification

# === ANTHROPIC (Required for /translate commands) ===
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxx

# === GOOGLE CLOUD (Required for Google Docs output) ===
GOOGLE_SERVICE_ACCOUNT_EMAIL=bot@project.iam.gserviceaccount.com
GOOGLE_SERVICE_ACCOUNT_KEY_PATH=/opt/devrel-integration/secrets/gcp-service-account.json
# Or use GOOGLE_APPLICATION_CREDENTIALS instead of KEY_PATH

# === GOOGLE DRIVE FOLDERS (Required for document storage) ===
GOOGLE_FOLDER_LEADERSHIP=folder_id_for_leadership_docs
GOOGLE_FOLDER_PRODUCT=folder_id_for_product_docs
GOOGLE_FOLDER_MARKETING=folder_id_for_marketing_docs
GOOGLE_FOLDER_DEVREL=folder_id_for_devrel_docs
GOOGLE_FOLDER_ORIGINALS=folder_id_for_original_docs

# === OPTIONAL ===
DISCORD_ALERTS_CHANNEL_ID=your_alerts_channel_id
GITHUB_TOKEN=ghp_xxxxxxxxxxxx
VERCEL_TOKEN=your_vercel_token
VERCEL_WEBHOOK_SECRET=your_vercel_webhook_secret
DEFAULT_PERSONA=devrel
LOG_LEVEL=info
NODE_ENV=production
PORT=3000
TZ=UTC
VALIDATE_WEBHOOK_SIGNATURES=true
```

### Step 7b: Configure Google Drive Folder IDs

The bot also requires a `config/folder-ids.json` file for Google Drive integration:

```bash
# Copy example and edit
cp config/folder-ids.json.example config/folder-ids.json
nano config/folder-ids.json
```

Update with your Google Drive folder IDs (same values as env vars):

```json
{
  "leadership": "your_leadership_folder_id",
  "product": "your_product_folder_id",
  "marketing": "your_marketing_folder_id",
  "devrel": "your_devrel_folder_id",
  "originals": "your_originals_folder_id"
}
```

**Note**: Get folder IDs from Google Drive URLs: `https://drive.google.com/drive/folders/{FOLDER_ID}`

### Step 8: Set Up Google Cloud Service Account

```bash
# Copy service account JSON key to server
scp gcp-service-account.json devrel@server:/opt/devrel-integration/secrets/

# Set secure permissions
ssh devrel@server 'chmod 600 /opt/devrel-integration/secrets/gcp-service-account.json'
```

**GCP Console Setup**:
1. Create project in Google Cloud Console
2. Enable Google Drive API and Google Docs API
3. Create Service Account with "Editor" role
4. Download JSON key
5. Share target Drive folders with service account email

### Step 9: Register Discord Commands

```bash
# As devrel user
cd /opt/devrel-integration
npm run register-commands
```

Expected output:
```
Successfully registered X application commands.
```

### Step 10: Start Application with PM2

**CRITICAL**: PM2's `env_file` directive does NOT reliably load environment variables. You MUST source the env file before starting PM2.

```bash
# As devrel user with PM2_HOME set
export PM2_HOME=/opt/devrel-integration/.pm2

# CRITICAL: Source environment variables BEFORE starting PM2
# set -a exports all variables, set +a stops exporting
set -a && source secrets/.env.local && set +a

# Start the bot (env vars are now in the shell environment)
pm2 start ecosystem.config.js --env production

# Save PM2 process list for auto-restart on reboot
pm2 save

# Verify
pm2 status
pm2 logs agentic-base-bot --lines 20
```

**If you see "No accessToken provided to LinearClient" error:**
```bash
# Stop the bot
pm2 stop agentic-base-bot

# Re-source environment and restart
set -a && source secrets/.env.local && set +a
pm2 start ecosystem.config.js --env production
```

### Step 11: Verify Installation

```bash
# Check PM2 status
pm2 status
# Should show: agentic-base-bot | online | 0 restarts

# Check health endpoint
curl -s http://localhost:3000/health
# Should return: {"status": "healthy"}

# Check Discord connection in logs
pm2 logs agentic-base-bot --lines 50 | grep -i "discord\|ready\|logged"

# Test a command in Discord
# Type: /show-sprint
# Should return sprint status

# Test /doc command (critical - verifies path resolution)
# Type: /doc prd
# Should return PRD document content
```

### Expected Server Directory Structure

After successful deployment, the server should have:

```
/opt/devrel-integration/
├── config/
│   ├── folder-ids.json          # Created from example (Step 7b)
│   ├── folder-ids.json.example
│   └── role-mapping.yml
├── data/
│   └── auth.db                  # Created at runtime
├── dist/                        # TypeScript compiled output
│   ├── bot.js                   # Entry point
│   ├── database/
│   │   └── schema.sql           # Copied by postbuild script
│   └── handlers/
│       ├── commands.js          # Text commands (uses ../../docs)
│       └── interactions.js      # Slash commands (uses ../../docs)
├── docs/                        # Documentation (served by /doc command)
│   ├── prd.md
│   ├── sdd.md
│   ├── sprint.md
│   └── a2a/                     # Agent-to-agent communication
├── logs/
│   └── *.log
├── secrets/
│   ├── .env.local               # chmod 600
│   └── gcp-service-account.json # chmod 600
├── src/                         # TypeScript source
├── .pm2/                        # PM2 home directory
├── ecosystem.config.js
├── package.json
└── tsconfig.json
```

**Critical Path Resolution**:
- `/doc` command code runs from `dist/handlers/`
- DOC_ROOT resolves: `dist/handlers/` + `../../docs` = `/opt/devrel-integration/docs/`
- If docs are in wrong location, `/doc` commands will fail

### Quick Reference: PM2 Commands for Custom Home

When running as a different user or with custom PM2_HOME, always specify:

```bash
# As root, running devrel's PM2:
sudo -u devrel PM2_HOME=/opt/devrel-integration/.pm2 pm2 status
sudo -u devrel PM2_HOME=/opt/devrel-integration/.pm2 pm2 logs agentic-base-bot
sudo -u devrel PM2_HOME=/opt/devrel-integration/.pm2 pm2 restart agentic-base-bot

# As devrel user (if PM2_HOME in .bashrc):
pm2 status
pm2 logs agentic-base-bot
```

---

## Pre-Deployment Checklist

### Code Preparation

- [ ] All tests passing (`npm test`)
- [ ] TypeScript compiles without errors (`npm run build`)
- [ ] Security audit passed (`npm audit`)
- [ ] Code reviewed and approved
- [ ] Sprint audit approved ("LETS FUCKING GO")

### Configuration

- [ ] `secrets/.env.local` configured with production values
- [ ] File permissions set: `chmod 600 secrets/.env.local`
- [ ] Google service account key in place
- [ ] `config/folder-ids.json` configured
- [ ] `config/role-mapping.yml` configured

### Infrastructure

- [ ] Server provisioned and accessible
- [ ] Firewall rules configured (outbound: 443, 80)
- [ ] Domain DNS configured (if applicable)
- [ ] SSL certificates installed (if applicable)

---

## Deployment Procedure

### 1. Connect to Server

```bash
ssh deploy@your-server.com
cd /opt/devrel-integration
```

### 2. Pull Latest Code

```bash
git fetch origin
git checkout main
git pull origin main
```

### 3. Install Dependencies

```bash
npm ci --production=false
```

### 4. Build Application

```bash
npm run build

# Copy non-TypeScript assets to dist (not handled by tsc)
cp src/database/schema.sql dist/database/
```

### 5. Verify Secrets

```bash
npm run verify-secrets
```

Expected output:
```
✓ Discord token valid
✓ Google credentials valid
✓ Anthropic API key valid
```

### 6. Run Pre-Flight Checks

```bash
# Verify build
ls -la dist/bot.js

# Check secrets file permissions
ls -la secrets/.env.local
# Should show: -rw------- (600)

# Verify logs directory
mkdir -p logs
chmod 755 logs
```

### 7. Start/Restart Application

**CRITICAL**: Always source environment variables before PM2 commands.

**First Deployment:**
```bash
# Source env vars first
set -a && source secrets/.env.local && set +a

pm2 start ecosystem.config.js --env production
pm2 save
```

**Subsequent Deployments:**
```bash
# Source env vars first
set -a && source secrets/.env.local && set +a

pm2 restart agentic-base-bot
```

### 8. Verify Deployment

```bash
# Check process status
pm2 status

# View logs
pm2 logs agentic-base-bot --lines 50

# Check health endpoint
curl -s http://localhost:3000/health
```

---

## Post-Deployment Verification

### Immediate Checks (Within 5 minutes)

1. **Process Running**
   ```bash
   pm2 status agentic-base-bot
   # Status should be "online"
   ```

2. **No Error Logs**
   ```bash
   pm2 logs agentic-base-bot --err --lines 20
   # Should be empty or no critical errors
   ```

3. **Health Check**
   ```bash
   curl -s http://localhost:3000/health | jq .
   # Should return {"status": "healthy"}
   ```

4. **Discord Connection**
   - Check Discord server for bot online status
   - Green circle = connected

### Functional Verification (Within 15 minutes)

1. **Slash Commands Visible**
   - Type `/` in Discord
   - Verify commands appear: `/translate`, `/exec-summary`, etc.

2. **Test Command Execution**
   ```
   /show-sprint
   ```
   - Should return current sprint status

3. **Test Document Commands** (CRITICAL)
   ```
   /doc prd
   /doc sdd
   /doc sprint
   ```
   - Should return document content or "Document not found" (NOT "Invalid document path")
   - If you get path errors, verify docs exist at `/opt/devrel-integration/docs/`

4. **Verify DOC_ROOT Path Resolution**
   ```bash
   # On server, verify path resolves correctly
   node -e "const path = require('path'); console.log(path.resolve('/opt/devrel-integration/dist/handlers', '../../docs'))"
   # Should output: /opt/devrel-integration/docs
   ```

5. **Permission Check**
   ```
   /translate mibera @prd for leadership
   ```
   - Should process or return appropriate error

### Extended Monitoring (First hour)

- Monitor PM2 dashboard: `pm2 monit`
- Watch for memory growth
- Check for rate limiting errors
- Verify no restart loops

---

## Rollback Procedure

### Immediate Rollback

If deployment fails, rollback immediately:

```bash
# Stop current version
pm2 stop agentic-base-bot

# Checkout previous release
git checkout <previous-commit-hash>

# Rebuild
npm ci --production=false
npm run build

# Source env vars and restart
set -a && source secrets/.env.local && set +a
pm2 start ecosystem.config.js --env production
```

### Identify Previous Version

```bash
git log --oneline -10
# Find the last known good commit
```

### Rollback Script

```bash
#!/bin/bash
# rollback.sh

PREVIOUS_COMMIT=${1:-HEAD~1}

echo "Rolling back to $PREVIOUS_COMMIT..."
pm2 stop agentic-base-bot

git checkout $PREVIOUS_COMMIT
npm ci --production=false
npm run build

pm2 start ecosystem.config.js --env production
pm2 save

echo "Rollback complete. Verifying..."
pm2 status
```

---

## Monitoring & Alerting

### PM2 Monitoring

```bash
# Real-time monitoring
pm2 monit

# Process details
pm2 show agentic-base-bot

# Memory/CPU usage
pm2 status
```

### Health Endpoints

| Endpoint | Description | Expected Response |
|----------|-------------|-------------------|
| `GET /health` | Basic health check | `{"status": "healthy"}` |
| `GET /metrics` | Prometheus metrics | Metrics data |

### Log Monitoring

```bash
# All logs
pm2 logs agentic-base-bot

# Error logs only
pm2 logs agentic-base-bot --err

# Follow logs
pm2 logs agentic-base-bot --lines 100 -f
```

### Key Metrics to Watch

- **Memory Usage**: Should stay under 500MB
- **Restart Count**: Should be 0 after stable deployment
- **CPU Usage**: Should be minimal when idle
- **Error Rate**: Should be <1% of requests

### Alert Conditions

| Condition | Severity | Action |
|-----------|----------|--------|
| Process stopped | Critical | Auto-restart, notify |
| Memory >400MB | Warning | Monitor |
| Memory >500MB | Critical | Auto-restart |
| 5+ restarts in 10min | Critical | Investigate, disable auto-restart |
| Health check fails | Critical | Notify, investigate |

---

## Common Operations

### Restart Bot

```bash
pm2 restart agentic-base-bot
```

### Stop Bot

```bash
pm2 stop agentic-base-bot
```

### Start Bot

```bash
pm2 start agentic-base-bot
```

### View Logs

```bash
# Last 100 lines
pm2 logs agentic-base-bot --lines 100

# Follow logs
pm2 logs agentic-base-bot -f

# Error logs only
pm2 logs agentic-base-bot --err
```

### Clear Logs

```bash
pm2 flush agentic-base-bot
```

### Rotate Secrets

1. Update `secrets/.env.local` with new values
2. Verify file permissions: `chmod 600 secrets/.env.local`
3. Restart bot: `pm2 restart agentic-base-bot`
4. Verify connection: `pm2 logs agentic-base-bot --lines 20`

### Register/Update Discord Commands

```bash
cd /opt/devrel-integration
npm run register-commands
```

### Run Database Migrations

```bash
# If database migrations are needed
npm run migrate
```

---

## Troubleshooting

### Bot Not Starting

**Symptoms**: PM2 shows "stopped" or "errored" status

**Check**:
```bash
pm2 logs agentic-base-bot --err --lines 50
```

**Common Causes**:
1. Missing secrets file
2. Invalid token format
3. Build errors (missing dist/bot.js)
4. Port already in use

**Resolution**:
```bash
# Verify build
ls -la dist/bot.js

# Verify secrets
npm run verify-secrets

# Check port usage
lsof -i :3000
```

### Bot Disconnecting from Discord

**Symptoms**: Bot goes offline intermittently

**Check**:
```bash
pm2 logs agentic-base-bot | grep -i "disconnect\|reconnect"
```

**Common Causes**:
1. Network issues
2. Invalid token
3. Rate limiting

**Resolution**:
1. Check network connectivity
2. Verify token is valid
3. Check Discord Developer Portal for issues

### High Memory Usage

**Symptoms**: Memory usage growing over time

**Check**:
```bash
pm2 monit
```

**Resolution**:
1. Check for memory leaks in logs
2. Restart bot: `pm2 restart agentic-base-bot`
3. If persistent, investigate code changes

### Commands Not Appearing

**Symptoms**: Slash commands not visible in Discord

**Check**:
```bash
# Re-register commands
npm run register-commands
```

**Common Causes**:
1. Commands not registered
2. Wrong guild ID
3. Bot missing permissions

**Resolution**:
1. Run `npm run register-commands`
2. Verify `DISCORD_GUILD_ID` in secrets
3. Verify bot has `applications.commands` scope

### API Errors

**Symptoms**: Transformation failures, API timeouts

**Check**:
```bash
pm2 logs agentic-base-bot | grep -i "error\|timeout\|rate"
```

**Common Causes**:
1. API rate limiting
2. Invalid API keys
3. Service outage

**Resolution**:
1. Check API status pages
2. Verify API keys
3. Wait for rate limit reset

---

## Emergency Contacts

- **Dev Team Lead**: @jani
- **On-Call**: Check #dev-support
- **Escalation**: Post in #incidents

---

## Appendix: Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `DISCORD_BOT_TOKEN` | Discord bot token | Yes |
| `DISCORD_GUILD_ID` | Target server ID | Yes |
| `ANTHROPIC_API_KEY` | Claude API key | Yes |
| `GOOGLE_SERVICE_ACCOUNT_EMAIL` | GCP service account | Yes |
| `GOOGLE_SERVICE_ACCOUNT_KEY` | GCP private key | Yes |
| `LINEAR_API_TOKEN` | Linear API token | No |
| `NODE_ENV` | Environment (production) | Yes |
| `LOG_LEVEL` | Logging level (info) | No |

---

## Lessons Learned

> Documented issues from prototype deployment (December 2024) to prevent recurrence.

### 1. Token Validation Regex Too Strict

**Problem**: The `secrets.ts` file had overly strict regex patterns that rejected valid production tokens.

**Symptoms**:
- Bot fails to start with "Invalid format for DISCORD_BOT_TOKEN"
- Token works in Discord Developer Portal but fails validation

**Root Cause**: Original regex expected exact character counts that don't match all valid token formats.

**Solution**: If you encounter token validation failures:
```typescript
// In src/utils/secrets.ts, use more permissive patterns:
DISCORD_BOT_TOKEN: {
  pattern: /^[MN][A-Za-z\d]{20,30}\.[\w-]{5,10}\.[\w-]{25,45}$/,  // Relaxed
},
LINEAR_API_TOKEN: {
  pattern: /^lin_api_[A-Za-z0-9]{30,50}$/,  // Relaxed
},
```

### 2. PM2 User Isolation Issues

**Problem**: Running `pm2 status` as root showed no processes, but bot was running.

**Symptoms**:
- `pm2 status` shows empty table
- `ps aux | grep node` shows bot is running
- Confusion about whether bot is actually running

**Root Cause**: PM2 was started by `devrel` user with custom `PM2_HOME`, but commands were run as root.

**Solution**: Always specify user and PM2_HOME:
```bash
sudo -u devrel PM2_HOME=/opt/devrel-integration/.pm2 pm2 status
```

### 3. Missing Sprint 3/4 Environment Variables

**Problem**: Bot deployed but `/translate` commands fail silently or with errors.

**Symptoms**:
- `/translate` returns "An error occurred"
- No Google Docs output generated
- Logs show "ANTHROPIC_API_KEY not configured"

**Root Cause**: Prototype was deployed with Sprint 2 env vars, missing Sprint 3 requirements.

**Solution**: Ensure ALL required env vars are present before deployment:
- `ANTHROPIC_API_KEY` - Required for AI transformation
- `GOOGLE_SERVICE_ACCOUNT_*` - Required for Google Docs
- `GOOGLE_FOLDER_*` - Required for document storage

### 4. Live Monkeypatching Creates Drift

**Problem**: Fixing issues directly on server creates undocumented drift from repository.

**Symptoms**:
- Server code differs from repo
- Subsequent deployments may overwrite fixes
- No record of what was changed or why

**Root Cause**: Rushing to fix production issues without proper change management.

**Solution**:
1. **Never edit source files on server** - Only edit config/secrets
2. **Document emergency changes** - Create immediate notes
3. **Backport to repo** - Push fixes to repo within 24 hours
4. **Redeploy from repo** - Verify fix works from clean deployment

### 5. High Restart Count Indicates Problems

**Problem**: PM2 shows 74+ restarts, indicating instability.

**Symptoms**:
- High restart count in `pm2 status`
- Intermittent bot unavailability
- "Crash loop" behavior

**Root Cause**: Usually one of:
- Memory leaks hitting 500MB limit
- Unhandled exceptions
- Invalid configuration
- API rate limiting

**Solution**:
```bash
# Check error logs
pm2 logs agentic-base-bot --err --lines 100

# Monitor memory in real-time
pm2 monit

# After fixing issue, reset restart count
pm2 reset agentic-base-bot
```

### 6. Commands Not Appearing After Deployment

**Problem**: New slash commands from Sprint 3 not visible in Discord.

**Symptoms**:
- `/translate` not in command list
- Old commands work, new ones missing
- No errors in logs

**Root Cause**: Discord commands must be explicitly registered after code deployment.

**Solution**: Always run after adding new commands:
```bash
npm run register-commands
```

### 7. Code Naming Inconsistencies

**Problem**: Code uses both `LINEAR_API_KEY` and `LINEAR_API_TOKEN` in different files.

**Symptoms**:
- Linear features work in some places, fail in others
- Confusing error messages about missing env vars

**Root Cause**: Inconsistent naming across codebase.

**Solution**: Standardize on `LINEAR_API_TOKEN` everywhere. Check for inconsistencies:
```bash
grep -r "LINEAR_API" src/
```

### 8. Missing Non-TypeScript Assets in dist

**Problem**: Bot fails to start with "Schema file not found" error.

**Symptoms**:
- Bot connects to Discord but crashes during database initialization
- Error: `Schema file not found: /opt/devrel-integration/dist/database/schema.sql`

**Root Cause**: TypeScript compiler (`tsc`) only compiles `.ts` files. Non-TypeScript assets like `.sql` files are not copied to `dist/`.

**Solution**: After `npm run build`, manually copy required assets:
```bash
cp src/database/schema.sql dist/database/
```

Consider adding a post-build script to `package.json` for automation:
```json
"postbuild": "cp src/database/schema.sql dist/database/"
```

### 9. PM2 env_file Directive Does NOT Load Environment Variables

**Problem**: Bot crashes with "No accessToken provided to LinearClient" even though `.env.local` exists.

**Symptoms**:
- Bot starts but immediately crashes
- Error logs show missing API keys/tokens
- `secrets/.env.local` file exists with correct values
- PM2 ecosystem.config.js has `env_file` pointing to correct path

**Root Cause**: PM2's `env_file` directive is unreliable and does NOT actually load environment variables into the process environment.

**Solution**: ALWAYS source the env file manually before starting PM2:
```bash
# Stop the bot first if running
pm2 stop agentic-base-bot

# Source environment variables into current shell
# set -a exports all vars, set +a stops exporting
set -a && source secrets/.env.local && set +a

# Now start PM2 - it inherits env vars from shell
pm2 start ecosystem.config.js --env production
```

**Important**: This must be done every time you start or restart the bot from a fresh shell session.

---

## Appendix B: Server Audit Checklist

Use this checklist when auditing an existing server:

- [ ] Check PM2 status and restart count
- [ ] Compare server code to repository (`git diff` or manual diff)
- [ ] List env var keys (not values) and compare to expected
- [ ] Check for `.bash_history` and `.viminfo` (evidence of live edits)
- [ ] Review PM2 error logs for crash patterns
- [ ] Verify all Sprint features are present in deployed code
- [ ] Check file permissions on secrets (should be 600)
- [ ] Verify Discord commands are registered

---

## Appendix C: Script Development Standards

When creating or modifying deployment scripts, follow these standards:

### Requirements

All deployment scripts must:

1. **Be idempotent** - Safe to run multiple times without side effects
2. **Include error handling** - Use `set -euo pipefail` at the top
3. **Log actions** - Echo what's being done at each step
4. **Check prerequisites** - Verify required tools exist before using them
5. **Support dry-run mode** - Accept `--dry-run` flag for testing
6. **Be well-commented** - Explain non-obvious commands
7. **Use variables** - Make scripts configurable via variables at top
8. **NEVER include secrets** - Use environment variables or `.env` files

### Script Template

```bash
#!/bin/bash
set -euo pipefail

# Script: XX-description.sh
# Purpose: Brief description
# Prerequisites: List required tools/state
# Usage: ./XX-description.sh [--dry-run]

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
run() {
  log "Running: $*"
  $DRY_RUN || "$@"
}

# Check prerequisites
command -v required_tool >/dev/null || { log "ERROR: required_tool not found"; exit 1; }

# Main script logic
log "Starting script..."
run some_command --with-args

log "Script completed successfully"
```

---

## Appendix D: Security Audit Reference Checklist

Reference checklist for `/audit-deployment` security reviews. Use when auditing deployment infrastructure.

### Server Setup Scripts

For each script, verify:

- [ ] No command injection vulnerabilities
- [ ] No hardcoded secrets or credentials
- [ ] Secure file permissions (secrets: 600, scripts: 755)
- [ ] Proper error handling (`set -euo pipefail`)
- [ ] Safe sudo usage (specific commands, not broad)
- [ ] No unvalidated user input
- [ ] Trusted package sources only (official repos)
- [ ] Idempotent operations
- [ ] No `curl | bash` without checksum verification

### Configuration Files

For PM2, systemd, nginx configs:

- [ ] Not running as root (use dedicated user)
- [ ] Restrictive file permissions
- [ ] Resource limits configured (memory, CPU)
- [ ] Environment variables not logged
- [ ] TLS 1.2+ only (no SSLv3, TLS 1.0/1.1)
- [ ] Security headers present (nginx)
- [ ] No open proxy vulnerabilities
- [ ] Debug endpoints disabled in production

### Security Hardening

Verify implementation of:

- [ ] SSH key-only auth (PasswordAuthentication no)
- [ ] Root login disabled (PermitRootLogin no)
- [ ] Strong SSH ciphers configured
- [ ] UFW firewall enabled (default deny incoming)
- [ ] fail2ban active and configured
- [ ] Automatic security updates enabled
- [ ] Audit logging configured (auditd)
- [ ] sysctl security parameters set

### Secrets Management

Confirm:

- [ ] No secrets in scripts or committed code
- [ ] `.env.local.example` template exists
- [ ] Actual secrets file permissions: 600
- [ ] Secrets directory in `.gitignore`
- [ ] Rotation procedure documented
- [ ] Secrets transferred securely (not via git)

### Network Security

Review:

- [ ] Minimal ports exposed (only required)
- [ ] Internal ports not externally accessible
- [ ] HTTPS redirect configured
- [ ] Valid SSL certificate
- [ ] Security headers (HSTS, X-Frame-Options, etc.)

### Operational Security

Assess documentation of:

- [ ] Backup procedure
- [ ] Restore/recovery procedure
- [ ] Secret rotation procedure
- [ ] Incident response plan
- [ ] Access revocation procedure
- [ ] Rollback procedure

---

*Last Updated: December 2024*
*Version: 1.2.1*
