# Incident Response Runbook

> Procedures for handling production incidents with Onomancer Bot

---

## Severity Levels

| Level | Description | Response Time | Example |
|-------|-------------|---------------|---------|
| **SEV1** | Complete outage | Immediate | Bot offline, no responses |
| **SEV2** | Major degradation | < 1 hour | Commands failing, high error rate |
| **SEV3** | Minor issues | < 24 hours | Slow responses, minor errors |
| **SEV4** | Cosmetic/minor | Best effort | Typos, UI issues |

---

## SEV1: Complete Outage

### Symptoms
- Bot appears offline in Discord
- No responses to commands
- PM2 shows "stopped" or "errored"

### Immediate Actions

```bash
# 1. SSH to server
ssh devrel@your-server-ip

# 2. Check PM2 status
PM2_HOME=/opt/devrel-integration/.pm2 pm2 status

# 3. Check error logs
PM2_HOME=/opt/devrel-integration/.pm2 pm2 logs onomancer-bot --err --lines 50

# 4. Attempt restart
PM2_HOME=/opt/devrel-integration/.pm2 pm2 restart onomancer-bot

# 5. Verify recovery
PM2_HOME=/opt/devrel-integration/.pm2 pm2 status
```

### If Restart Fails

```bash
# Check system resources
free -h
df -h

# Check for crash loops
PM2_HOME=/opt/devrel-integration/.pm2 pm2 describe onomancer-bot | grep restarts

# Kill and restart fresh
PM2_HOME=/opt/devrel-integration/.pm2 pm2 delete onomancer-bot
cd /opt/devrel-integration/devrel-integration
PM2_HOME=/opt/devrel-integration/.pm2 pm2 start ecosystem.config.js --env production
```

### If Still Failing

```bash
# Check Node.js
node --version

# Check dependencies
npm ci

# Rebuild
npm run build

# Start manually to see errors
NODE_ENV=production node dist/bot.js
```

### Escalation

If unable to resolve within 15 minutes:
1. Check external dependencies (Discord, Anthropic, Google APIs)
2. Contact team lead
3. Consider rolling back to known-good version

---

## SEV2: Major Degradation

### Symptoms
- Commands working intermittently
- High error rate (>10%)
- Slow responses (>60 seconds)
- Circuit breakers tripped

### Diagnosis

```bash
# Check error count
grep -c error /var/log/devrel/onomancer-combined.log | tail -1

# Check API errors
grep -i "anthropic\|google\|discord" /var/log/devrel/onomancer-error.log | tail -20

# Check circuit breaker status
grep "circuit" /var/log/devrel/onomancer-combined.log | tail -10
```

### Actions

For high error rate:
```bash
# Clear Redis cache (if using Redis)
redis-cli FLUSHDB

# Restart to reset circuit breakers
pm2 restart onomancer-bot
```

For slow responses:
```bash
# Check memory
pm2 monit

# Check external API latency in logs
grep "duration" /var/log/devrel/onomancer-combined.log | tail -20
```

For external API issues:
- Check Discord status: https://discordstatus.com
- Check Anthropic status: https://status.anthropic.com
- Check Google status: https://status.cloud.google.com

---

## SEV3: Minor Issues

### Symptoms
- Occasional errors
- Specific commands failing
- Minor functionality issues

### Diagnosis

```bash
# Check specific error patterns
grep "error" /var/log/devrel/onomancer-combined.log | grep "translate"

# Check user-reported command
grep "command-name" /var/log/devrel/onomancer-combined.log
```

### Actions

1. Document the issue
2. Check for recent deployments
3. Create bug ticket
4. Schedule fix for next release

---

## Common Issues & Quick Fixes

### Issue: "Discord Token Invalid"

```bash
# Verify token in secrets file
grep DISCORD_TOKEN /opt/devrel-integration/devrel-integration/secrets/.env.local

# Regenerate token in Discord Developer Portal if needed
# Update .env.local and restart
pm2 restart onomancer-bot
```

### Issue: "Google API Quota Exceeded"

```bash
# Check quota usage in GCP Console
# Implement backoff or wait until quota resets
# Consider requesting quota increase
```

### Issue: "Out of Memory"

```bash
# Check current memory
pm2 describe onomancer-bot | grep memory

# Force restart with garbage collection
pm2 restart onomancer-bot --node-args="--expose-gc"

# Increase memory limit in ecosystem.config.js if needed
```

### Issue: "Disk Full"

```bash
# Check disk usage
df -h

# Clear old logs
find /var/log/devrel -name "*.log" -mtime +7 -delete

# Clear old backups
find /opt/devrel-integration/devrel-integration/backups -mtime +30 -delete
```

---

## Post-Incident

After resolving any incident:

1. **Document** what happened
2. **Root cause analysis** for SEV1/SEV2
3. **Update runbook** if new procedures discovered
4. **Notify team** of resolution
5. **Create follow-up tickets** for improvements
