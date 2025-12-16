# Deployment Runbook

> Standard procedure for deploying new versions of Onomancer Bot

---

## Pre-Deployment Checklist

Before deploying:

- [ ] All tests passing locally
- [ ] Code reviewed and approved
- [ ] Database migrations identified (if any)
- [ ] Rollback plan prepared
- [ ] Team notified of deployment window

---

## Deployment Procedure

### 1. Notify Team

```
@team Deploying Onomancer Bot update. Expected downtime: <1 minute.
```

### 2. SSH to Server

```bash
ssh devrel@your-server-ip
```

### 3. Pull Latest Code

```bash
cd /opt/devrel-integration
git fetch origin
git checkout main
git pull
```

### 4. Review Changes

```bash
git log --oneline -10
git diff HEAD~1 --stat
```

### 5. Run Deployment

```bash
cd devrel-integration
./docs/deployment/scripts/deploy.sh
```

### 6. Verify Deployment

```bash
# Check status
pm2 status

# Check logs (no errors)
pm2 logs onomancer-bot --lines 30

# Run health check
./docs/deployment/scripts/health-check.sh
```

### 7. Test Functionality

In Discord:
```
/show-sprint
```

Expected: Bot responds correctly.

### 8. Notify Team

```
@team Deployment complete. Onomancer Bot is operational.
```

---

## Rollback Procedure

If deployment fails:

### 1. Stop the Bot

```bash
pm2 stop onomancer-bot
```

### 2. Rollback Code

```bash
# Rollback to previous commit
git checkout HEAD~1

# Or rollback to specific tag
git checkout v1.0.0
```

### 3. Rebuild and Restart

```bash
npm ci
npm run build
pm2 start onomancer-bot
```

### 4. Restore Database (if needed)

```bash
./docs/deployment/scripts/rollback.sh --list
./docs/deployment/scripts/rollback.sh
```

---

## Emergency Procedures

### Bot Completely Down

```bash
# 1. Check PM2
pm2 status

# 2. If stopped, restart
pm2 restart onomancer-bot

# 3. If crashing, check logs
pm2 logs onomancer-bot --err --lines 100

# 4. If memory issue
pm2 restart onomancer-bot --update-env
```

### Database Corruption

```bash
# 1. Stop bot
pm2 stop onomancer-bot

# 2. Restore from backup
./docs/deployment/scripts/rollback.sh --list
./docs/deployment/scripts/rollback.sh

# 3. Restart
pm2 start onomancer-bot
```

---

## Post-Deployment Monitoring

Monitor for 15 minutes after deployment:

```bash
# Watch logs
pm2 logs onomancer-bot

# Watch memory/CPU
pm2 monit

# Check error rate
grep -c error /var/log/devrel/onomancer-combined.log
```
