# Onomancer Bot Deployment Runbook

> Production deployment procedures for Onomancer Bot

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Deployment Checklist](#pre-deployment-checklist)
3. [Deployment Procedure](#deployment-procedure)
4. [Post-Deployment Verification](#post-deployment-verification)
5. [Rollback Procedure](#rollback-procedure)
6. [Monitoring & Alerting](#monitoring--alerting)
7. [Common Operations](#common-operations)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Server Requirements

- **OS**: Ubuntu 22.04 LTS or Debian 12
- **Node.js**: v18.x or higher (LTS)
- **RAM**: Minimum 1GB (2GB recommended)
- **Disk**: 10GB available
- **Network**: Outbound access to Discord, Google APIs, Anthropic API

### Required Accounts & Access

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

**First Deployment:**
```bash
pm2 start ecosystem.config.js --env production
pm2 save
```

**Subsequent Deployments:**
```bash
pm2 reload agentic-base-bot --update-env
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

3. **Permission Check**
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

# Restart
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

*Last Updated: December 2025*
*Version: 1.0.0*
