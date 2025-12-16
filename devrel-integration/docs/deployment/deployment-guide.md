# Onomancer Bot - Production Deployment Guide

> Step-by-step guide to deploy Onomancer Bot to production

**Version:** 1.0
**Date:** 2025-12-16
**Target Environment:** OVH Bare Metal VPS (Single Server MVP)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Detailed Deployment Steps](#detailed-deployment-steps)
4. [Post-Deployment Verification](#post-deployment-verification)
5. [Common Operations](#common-operations)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Server Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| CPU | 1 core | 2 cores |
| RAM | 1 GB | 2 GB |
| Disk | 10 GB | 20 GB |
| Network | 100 Mbps | 1 Gbps |

### Required Credentials

Before deployment, ensure you have:

- [ ] **Discord Bot Token** - From Discord Developer Portal
- [ ] **Google Service Account** - JSON key file with Drive/Docs API access
- [ ] **Anthropic API Key** - For Claude transformations
- [ ] **Linear API Token** - For context aggregation (optional)
- [ ] **Domain Name** - For HTTPS (optional but recommended)

> See [CREDENTIALS_SETUP_GUIDE.md](../CREDENTIALS_SETUP_GUIDE.md) for detailed credential creation instructions.

### Local Machine Requirements

- SSH access to server
- Git (for deployment)
- Basic familiarity with Linux command line

---

## Quick Start

For experienced users, here's the condensed deployment process:

```bash
# 1. SSH to server
ssh root@your-server-ip

# 2. Download and run server setup
curl -O https://raw.githubusercontent.com/your-org/agentic-base/main/devrel-integration/docs/deployment/scripts/server-setup.sh
chmod +x server-setup.sh
./server-setup.sh --domain your-domain.com --email admin@your-domain.com

# 3. Switch to devrel user
su - devrel
cd /opt/devrel-integration

# 4. Clone repository
git clone https://github.com/your-org/agentic-base.git .

# 5. Configure secrets
cp devrel-integration/secrets/.env.local.example devrel-integration/secrets/.env.local
nano devrel-integration/secrets/.env.local  # Add your credentials

# 6. Copy Google service account
# Upload service-account.json to /opt/devrel-integration/devrel-integration/secrets/

# 7. Deploy
cd devrel-integration
./docs/deployment/scripts/deploy.sh

# 8. Verify
pm2 status
pm2 logs onomancer-bot --lines 20
```

---

## Detailed Deployment Steps

### Step 1: Server Setup

Connect to your fresh server:

```bash
ssh root@your-server-ip
```

Run the server setup script:

```bash
# Download setup script
curl -O https://raw.githubusercontent.com/your-org/agentic-base/main/docs/deployment/scripts/server-setup.sh
chmod +x server-setup.sh

# Run with your domain (for SSL) and email (for Let's Encrypt)
./server-setup.sh --domain onomancer.yourdomain.com --email admin@yourdomain.com

# Or without SSL (for testing)
./server-setup.sh --skip-nginx
```

The script will:
- Update system packages
- Install Node.js 20 LTS
- Install PM2 process manager
- Create `devrel` service user
- Configure firewall (UFW)
- Set up fail2ban for SSH protection
- Install and configure nginx with SSL (if domain provided)
- Configure Redis (optional)

### Step 2: Deploy Application Code

Switch to the devrel user:

```bash
su - devrel
cd /opt/devrel-integration
```

Clone the repository:

```bash
git clone https://github.com/your-org/agentic-base.git .
```

Or copy files manually:

```bash
# From your local machine
scp -r ./agentic-base/* devrel@your-server:/opt/devrel-integration/
```

### Step 3: Configure Secrets

Navigate to the devrel-integration directory:

```bash
cd devrel-integration
```

Create the secrets file:

```bash
mkdir -p secrets
cp secrets/.env.local.example secrets/.env.local
chmod 600 secrets/.env.local
```

Edit the secrets file:

```bash
nano secrets/.env.local
```

Required environment variables:

```bash
# === DISCORD (Required) ===
DISCORD_TOKEN=your-discord-bot-token
DISCORD_CLIENT_ID=your-discord-client-id
DISCORD_GUILD_ID=your-discord-server-id

# === GOOGLE (Required) ===
GOOGLE_SERVICE_ACCOUNT_KEY_PATH=/opt/devrel-integration/devrel-integration/secrets/service-account.json

# === ANTHROPIC (Required) ===
ANTHROPIC_API_KEY=your-anthropic-api-key

# === LINEAR (Optional) ===
LINEAR_API_KEY=your-linear-api-key

# === DATABASE ===
DATABASE_PATH=/opt/devrel-integration/devrel-integration/data/onomancer.db

# === LOGGING ===
LOG_LEVEL=info
LOG_DIR=/var/log/devrel

# === DOMAIN (if using nginx) ===
DOMAIN=onomancer.yourdomain.com
```

Upload your Google service account key:

```bash
# From your local machine
scp service-account.json devrel@your-server:/opt/devrel-integration/devrel-integration/secrets/

# On the server, secure the file
chmod 600 /opt/devrel-integration/devrel-integration/secrets/service-account.json
```

### Step 4: Run Deployment

Run the deployment script:

```bash
cd /opt/devrel-integration/devrel-integration
./docs/deployment/scripts/deploy.sh
```

The script will:
1. Validate environment and credentials
2. Backup existing database
3. Install dependencies
4. Build TypeScript
5. Create PM2 configuration
6. Start/reload the application
7. Verify deployment

### Step 5: Register Discord Commands

If this is a fresh deployment, register slash commands with Discord:

```bash
npm run register-commands
```

### Step 6: Verify Deployment

Check PM2 status:

```bash
pm2 status
```

Expected output:
```
┌─────┬────────────────┬─────────────┬─────────┬─────────┬──────────┬────────┬──────┬───────────┬──────────┬──────────┬──────────┬──────────┐
│ id  │ name           │ namespace   │ version │ mode    │ pid      │ uptime │ ↺    │ status    │ cpu      │ mem      │ user     │ watching │
├─────┼────────────────┼─────────────┼─────────┼─────────┼──────────┼────────┼──────┼───────────┼──────────┼──────────┼──────────┼──────────┤
│ 0   │ onomancer-bot  │ default     │ 1.0.0   │ fork    │ 12345    │ 1m     │ 0    │ online    │ 0%       │ 150mb    │ devrel   │ disabled │
└─────┴────────────────┴─────────────┴─────────┴─────────┴──────────┴────────┴──────┴───────────┴──────────┴──────────┴──────────┴──────────┘
```

Check application logs:

```bash
pm2 logs onomancer-bot --lines 50
```

Look for:
- "Discord client logged in as..."
- "Bot is ready!"
- No error messages

---

## Post-Deployment Verification

### 1. Discord Bot Status

- Bot should appear online in Discord
- Check bot status icon is green

### 2. Slash Commands

In your Discord server, type `/` and verify commands appear:
- `/translate`
- `/exec-summary`
- `/audit-summary`
- `/show-sprint`

### 3. Test Command

Run a simple test:

```
/show-sprint
```

Expected: Bot responds with current sprint status.

### 4. Health Check

If you configured nginx with a health endpoint:

```bash
curl -s https://your-domain.com/health | jq .
```

### 5. Logs Check

```bash
# Check for errors
pm2 logs onomancer-bot --err --lines 20

# Verify successful Discord connection
grep "logged in" /var/log/devrel/onomancer-combined.log
```

---

## Common Operations

### Starting and Stopping

```bash
# Stop the bot
pm2 stop onomancer-bot

# Start the bot
pm2 start onomancer-bot

# Restart the bot
pm2 restart onomancer-bot

# Zero-downtime reload
pm2 reload onomancer-bot
```

### Viewing Logs

```bash
# Stream all logs
pm2 logs onomancer-bot

# View last 100 lines
pm2 logs onomancer-bot --lines 100

# View error logs only
pm2 logs onomancer-bot --err

# View combined log file
tail -f /var/log/devrel/onomancer-combined.log
```

### Updating the Application

```bash
# Pull latest code
cd /opt/devrel-integration
git pull

# Run deployment (handles build and restart)
cd devrel-integration
./docs/deployment/scripts/deploy.sh
```

### Rolling Back

```bash
# List available rollback points
./docs/deployment/scripts/rollback.sh --list

# Rollback to previous database
./docs/deployment/scripts/rollback.sh

# Rollback to specific git version
./docs/deployment/scripts/rollback.sh --code v1.0.0
```

### Checking Status

```bash
# PM2 status
pm2 status

# Detailed process info
pm2 describe onomancer-bot

# Real-time monitoring
pm2 monit
```

---

## Troubleshooting

### Bot Not Starting

**Symptoms:** PM2 shows "stopped" or "errored" status

**Check logs:**
```bash
pm2 logs onomancer-bot --err --lines 50
```

**Common causes:**
1. Invalid Discord token → Check `DISCORD_TOKEN` in `.env.local`
2. Missing dependencies → Run `npm ci`
3. Build failed → Run `npm run build`
4. Wrong node version → Check `node --version` (needs 18+)

### Bot Goes Offline Frequently

**Symptoms:** Multiple restarts shown in PM2

**Check restart count:**
```bash
pm2 describe onomancer-bot | grep restarts
```

**Common causes:**
1. Memory limit exceeded → Increase `max_memory_restart` in ecosystem.config.js
2. Discord rate limits → Check logs for "429" errors
3. API errors → Check circuit breaker status in logs

### Commands Not Working

**Symptoms:** Slash commands don't appear or don't respond

**Solutions:**
1. Re-register commands: `npm run register-commands`
2. Check bot permissions in Discord server
3. Verify `DISCORD_GUILD_ID` is correct
4. Wait 1 hour (Discord caches commands)

### Google Docs Integration Failing

**Symptoms:** "Google API error" in logs

**Check:**
1. Service account key file exists and is readable
2. Service account has Drive API enabled
3. Folder permissions in Google Drive

```bash
# Test Google auth
cat secrets/service-account.json | jq .client_email
```

### SSL Certificate Issues

**Symptoms:** HTTPS not working or certificate expired

**Check certificate:**
```bash
sudo certbot certificates
```

**Renew certificate:**
```bash
sudo certbot renew
```

### High Memory Usage

**Symptoms:** Memory > 1GB, slow responses

**Check memory:**
```bash
pm2 monit
```

**Solutions:**
1. Restart the bot: `pm2 restart onomancer-bot`
2. Check for memory leaks in logs
3. Increase server RAM

---

## Additional Resources

- [Infrastructure Architecture](./infrastructure.md) - Detailed architecture documentation
- [Monitoring Guide](./monitoring.md) - Setting up monitoring and alerting
- [Credentials Setup Guide](../CREDENTIALS_SETUP_GUIDE.md) - Creating required credentials
- [Existing Deployment Runbook](../DEPLOYMENT_RUNBOOK.md) - Detailed operational procedures

---

## Support

If you encounter issues not covered in this guide:

1. Check application logs: `pm2 logs onomancer-bot`
2. Review the [troubleshooting section](#troubleshooting)
3. Open an issue on GitHub
4. Contact the team via Discord
