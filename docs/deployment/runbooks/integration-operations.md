# Integration Layer Operations Runbook

This runbook provides operational guidance for running, monitoring, and troubleshooting the agentic-base integration layer.

## Table of Contents

- [Overview](#overview)
- [Starting and Stopping](#starting-and-stopping)
- [Monitoring](#monitoring)
- [Common Operations](#common-operations)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)
- [Emergency Procedures](#emergency-procedures)

## Overview

The agentic-base integration layer connects Discord, Linear, GitHub, and Vercel to enable seamless workflow automation. It consists of:

- **Discord Bot**: Handles commands, feedback capture, and notifications
- **Webhook Server**: Processes webhooks from Linear, GitHub, Vercel
- **Cron Jobs**: Scheduled tasks (daily digest, sync jobs)
- **Service Integrations**: API wrappers for external services

**Key Components:**
- Main process: `dist/bot.js`
- Health check endpoint: `http://localhost:3000/health`
- Webhook endpoint: `http://localhost:3000/webhooks/*`
- Logs: `integration/logs/`

## Starting and Stopping

### Docker (Recommended)

**Start the integration layer:**
```bash
cd integration
docker-compose up -d
```

**Stop the integration layer:**
```bash
docker-compose down
```

**Restart the integration layer:**
```bash
docker-compose restart
```

**View logs:**
```bash
docker-compose logs -f bot
```

**View last 100 log lines:**
```bash
docker-compose logs --tail=100 bot
```

### PM2

**Start with PM2:**
```bash
cd integration
pm2 start ecosystem.config.js --env production
```

**Stop with PM2:**
```bash
pm2 stop agentic-base-bot
```

**Restart with PM2:**
```bash
pm2 restart agentic-base-bot
```

**View logs:**
```bash
pm2 logs agentic-base-bot
```

**View monitoring dashboard:**
```bash
pm2 monit
```

### Systemd

**Start with systemd:**
```bash
sudo systemctl start agentic-base-bot
```

**Stop with systemd:**
```bash
sudo systemctl stop agentic-base-bot
```

**Restart with systemd:**
```bash
sudo systemctl restart agentic-base-bot
```

**View logs:**
```bash
journalctl -u agentic-base-bot -f
```

**View last 100 log lines:**
```bash
journalctl -u agentic-base-bot -n 100
```

**Enable auto-start on boot:**
```bash
sudo systemctl enable agentic-base-bot
```

## Monitoring

### Health Checks

**Check service health:**
```bash
curl http://localhost:3000/health
```

**Expected response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-12-08T12:00:00.000Z",
  "services": {
    "discord": "connected",
    "linear": "operational"
  }
}
```

**Unhealthy response:**
```json
{
  "status": "unhealthy",
  "timestamp": "2025-12-08T12:00:00.000Z",
  "services": {
    "discord": "disconnected",
    "linear": "operational"
  }
}
```

### Log Monitoring

**Monitor logs in real-time (Docker):**
```bash
docker-compose logs -f bot | grep ERROR
```

**Monitor logs in real-time (systemd):**
```bash
journalctl -u agentic-base-bot -f | grep ERROR
```

**Key log patterns to watch:**
- `ERROR` - Application errors requiring attention
- `WARN` - Warnings that may indicate issues
- `rate limit` - API rate limiting events
- `circuit breaker` - Service degradation
- `Discord connected` - Bot successfully connected
- `Discord disconnected` - Bot lost connection

### Service Status

**Check Discord connection status:**
```bash
# Check logs for recent "Discord connected" message
docker-compose logs --tail=50 bot | grep "Discord connected"
```

**Check Linear API status:**
```bash
# Check for recent Linear API errors
docker-compose logs --tail=100 bot | grep "Linear API"
```

**Check webhook processing:**
```bash
# Check for recent webhook events
docker-compose logs --tail=100 bot | grep "webhook"
```

### Performance Metrics

**Docker resource usage:**
```bash
docker stats agentic-base-bot
```

**PM2 resource monitoring:**
```bash
pm2 monit
```

**System resource usage:**
```bash
# CPU and memory usage of the process
ps aux | grep "node.*bot.js"
```

## Common Operations

### Configuration Changes

**Update configuration files:**
1. Edit the configuration file in `integration/config/`
2. Restart the integration layer
3. Verify changes in logs

```bash
# Edit config
vi integration/config/discord-digest.yml

# Restart (Docker)
docker-compose restart bot

# Restart (PM2)
pm2 restart agentic-base-bot

# Restart (systemd)
sudo systemctl restart agentic-base-bot
```

### Rotating API Tokens

**Rotate Discord bot token:**
1. Generate new token in Discord Developer Portal
2. Update `secrets/.env.local`: `DISCORD_BOT_TOKEN=new_token`
3. Restart the integration layer
4. Verify connection in logs

**Rotate Linear API token:**
1. Generate new token in Linear Settings > API
2. Update `secrets/.env.local`: `LINEAR_API_KEY=new_token`
3. Restart the integration layer
4. Verify API calls work

**Rotate webhook secrets:**
1. Update webhook secret in external service (Linear, GitHub, Vercel)
2. Update corresponding secret in `secrets/.env.local`
3. Restart the integration layer
4. Test webhook delivery

### Manual Digest Trigger

**Trigger daily digest manually (for testing):**

```bash
# Docker
docker-compose exec bot node -e "require('./dist/cron/dailyDigest').triggerManualDigest()"

# Direct node (if running locally)
cd integration
node -e "require('./dist/cron/dailyDigest').triggerManualDigest()"
```

### Viewing Active Configuration

**Check loaded configuration:**
```bash
# View Discord digest config
cat integration/config/discord-digest.yml

# View Linear sync config
cat integration/config/linear-sync.yml

# View bot commands config
cat integration/config/bot-commands.yml
```

**Verify environment variables (without exposing secrets):**
```bash
# Docker
docker-compose exec bot env | grep -E "(DISCORD|LINEAR|GITHUB|VERCEL|NODE_ENV)" | sed 's/\(TOKEN\|KEY\|SECRET\)=.*/\1=***REDACTED***/'

# systemd
sudo systemctl show agentic-base-bot | grep Environment
```

## Troubleshooting

### Bot Not Connecting to Discord

**Symptoms:**
- Bot shows as offline in Discord
- Logs show connection errors
- Health check shows `discord: "disconnected"`

**Diagnosis:**
```bash
# Check for Discord connection errors
docker-compose logs bot | grep -i "discord\|error" | tail -20
```

**Common causes and fixes:**

1. **Invalid bot token:**
   ```bash
   # Verify token format (should start with specific prefix)
   grep DISCORD_BOT_TOKEN secrets/.env.local
   # Regenerate token in Discord Developer Portal if needed
   ```

2. **Network issues:**
   ```bash
   # Test Discord API connectivity
   curl https://discord.com/api/v10/gateway
   ```

3. **Bot not invited to server:**
   - Check bot is invited with correct permissions
   - Verify DISCORD_GUILD_ID matches your server

4. **Rate limiting:**
   ```bash
   # Check for rate limit messages
   docker-compose logs bot | grep "rate limit"
   ```

### Linear API Errors

**Symptoms:**
- Commands fail with "Linear integration unavailable"
- Logs show Linear API errors
- Circuit breaker opens

**Diagnosis:**
```bash
# Check Linear API errors
docker-compose logs bot | grep -i "linear.*error" | tail -20

# Check circuit breaker status
docker-compose logs bot | grep "circuit breaker"
```

**Common causes and fixes:**

1. **Invalid API token:**
   ```bash
   # Test Linear API directly
   curl -H "Authorization: YOUR_LINEAR_API_KEY" https://api.linear.app/graphql \
     -X POST -d '{"query":"{ viewer { id name } }"}'
   ```

2. **Rate limiting:**
   - Linear allows 2000 requests/hour
   - Check logs for rate limit warnings
   - Wait for rate limit to reset (resets hourly)

3. **Network connectivity:**
   ```bash
   # Test Linear API connectivity
   curl -I https://api.linear.app
   ```

4. **Circuit breaker opened:**
   - Circuit breaker opens after 50% error rate
   - Automatically recovers after 30 seconds
   - Check underlying cause (token, network, rate limit)

### Webhook Not Processing

**Symptoms:**
- Linear/GitHub/Vercel events not triggering notifications
- Webhook endpoint returning errors
- No webhook events in logs

**Diagnosis:**
```bash
# Check webhook processing logs
docker-compose logs bot | grep "webhook" | tail -20

# Check if webhook server is running
curl http://localhost:3000/health
```

**Common causes and fixes:**

1. **Webhook signature verification failing:**
   ```bash
   # Check for signature verification errors
   docker-compose logs bot | grep "signature"

   # Verify webhook secrets match
   # - Linear: LINEAR_WEBHOOK_SECRET
   # - GitHub: GITHUB_WEBHOOK_SECRET
   # - Vercel: VERCEL_WEBHOOK_SECRET
   ```

2. **Webhook URL not configured:**
   - Verify webhook URL in external service points to your server
   - Format: `https://your-domain.com/webhooks/linear`
   - Must be publicly accessible (use ngrok for local testing)

3. **Firewall blocking webhooks:**
   ```bash
   # Verify port 3000 is accessible
   curl http://YOUR_PUBLIC_IP:3000/health

   # Check firewall rules
   sudo iptables -L | grep 3000
   ```

4. **Webhook payload format changed:**
   - External service may have updated webhook format
   - Check logs for parsing errors
   - May require code update

### Commands Not Working

**Symptoms:**
- Bot doesn't respond to commands
- Commands return permission errors
- Commands timeout

**Diagnosis:**
```bash
# Check command processing logs
docker-compose logs bot | grep "command" | tail -20

# Check for permission errors
docker-compose logs bot | grep "permission" | tail -10
```

**Common causes and fixes:**

1. **Command disabled in config:**
   ```bash
   # Check if command is enabled
   cat integration/config/bot-commands.yml | grep -A5 "your-command"
   ```

2. **Permission issues:**
   - Verify user has required role
   - Check `bot-commands.yml` for allowed_roles
   - Admin roles bypass all permission checks

3. **Rate limiting:**
   ```bash
   # Check for rate limit messages
   docker-compose logs bot | grep "rate limit"
   ```
   - User may be sending commands too quickly
   - Rate limit: 20 commands per 5 minutes per user

4. **Service dependency unavailable:**
   - Commands may depend on Linear/GitHub/Vercel
   - Check if dependent service is accessible

### High Memory Usage

**Symptoms:**
- Memory usage growing over time
- Process restarting due to OOM
- Slow response times

**Diagnosis:**
```bash
# Check memory usage (Docker)
docker stats agentic-base-bot

# Check memory usage (PM2)
pm2 info agentic-base-bot

# Check for memory-related errors
docker-compose logs bot | grep -i "memory\|heap"
```

**Common causes and fixes:**

1. **Memory leak:**
   - Check for unclosed connections
   - Review recent code changes
   - Restart to temporarily mitigate

2. **Too many concurrent operations:**
   - Reduce rate limit reservoir
   - Reduce max concurrent requests
   - Check for request queuing issues

3. **Large log files:**
   ```bash
   # Check log file sizes
   du -sh integration/logs/*

   # Rotate logs if needed
   docker-compose restart bot
   ```

### Cron Jobs Not Running

**Symptoms:**
- Daily digest not posting
- Scheduled tasks not executing
- No cron-related logs

**Diagnosis:**
```bash
# Check for cron job execution
docker-compose logs bot | grep -i "digest\|cron" | tail -20

# Verify cron schedule
cat integration/config/discord-digest.yml | grep schedule
```

**Common causes and fixes:**

1. **Digest disabled in config:**
   ```bash
   # Check if enabled
   cat integration/config/discord-digest.yml | grep enabled
   # Should be: enabled: true
   ```

2. **Invalid cron schedule:**
   - Verify cron syntax: "minute hour day month weekday"
   - Test with online cron validator

3. **Timezone issues:**
   - Check timezone in config: `discord-digest.yml`
   - Verify server timezone: `date`

4. **Channel not accessible:**
   - Verify DISCORD_CHANNEL_ID is correct
   - Ensure bot has permission to post in channel

## Maintenance

### Log Rotation

**Docker logs:**
```bash
# Docker automatically rotates logs with config in docker-compose.yml
# View log rotation settings:
docker inspect agentic-base-bot | grep -A5 "LogConfig"
```

**Manual log cleanup:**
```bash
# Remove old log files
find integration/logs -name "*.log" -mtime +30 -delete

# Compress old logs
find integration/logs -name "*.log" -mtime +7 -exec gzip {} \;
```

**PM2 log rotation:**
```bash
# Install PM2 log rotation module
pm2 install pm2-logrotate

# Configure rotation
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7
```

### Updates and Deployments

**Update to new version:**

1. **Backup current state:**
   ```bash
   # Backup configuration
   cp -r integration/config integration/config.backup
   cp integration/secrets/.env.local integration/secrets/.env.local.backup
   ```

2. **Pull new code:**
   ```bash
   git pull origin main
   ```

3. **Update dependencies:**
   ```bash
   cd integration
   npm install
   ```

4. **Rebuild:**
   ```bash
   npm run build
   ```

5. **Restart service:**
   ```bash
   # Docker
   docker-compose down
   docker-compose build
   docker-compose up -d

   # PM2
   pm2 restart agentic-base-bot

   # systemd
   sudo systemctl restart agentic-base-bot
   ```

6. **Verify deployment:**
   ```bash
   # Check health
   curl http://localhost:3000/health

   # Monitor logs
   docker-compose logs -f bot
   ```

### Database/Cache Cleanup

**Clear request cache (if issues with stale data):**
- Restart the service (cache is in-memory)

**Clear user preferences (reset to defaults):**
```bash
# Backup first
cp integration/config/user-preferences.json integration/config/user-preferences.json.backup

# Reset to defaults (manually edit or restore from template)
```

### Performance Optimization

**If experiencing performance issues:**

1. **Reduce rate limit reservoir:**
   - Edit `src/services/linearService.ts`
   - Reduce `reservoir` and `maxConcurrent` values

2. **Disable unnecessary features:**
   - Disable cron jobs if not needed
   - Disable webhook processing for unused services
   - Disable verbose logging

3. **Scale horizontally:**
   - Run multiple instances behind a load balancer
   - Use separate instances for bot vs webhooks

## Emergency Procedures

### Total Service Outage

**Immediate actions:**

1. **Check service status:**
   ```bash
   docker-compose ps
   # or
   pm2 status
   # or
   sudo systemctl status agentic-base-bot
   ```

2. **Check recent logs for cause:**
   ```bash
   docker-compose logs --tail=100 bot
   ```

3. **Attempt restart:**
   ```bash
   docker-compose restart bot
   ```

4. **If restart fails, check:**
   - Disk space: `df -h`
   - Memory: `free -h`
   - Network: `ping discord.com`
   - Secrets file exists: `ls -la integration/secrets/.env.local`

5. **Escalate if unresolved:**
   - Check GitHub issues for known problems
   - Contact development team
   - Revert to last known good version

### Linear API Completely Down

**Symptoms:**
- All Linear-dependent commands failing
- Circuit breaker open
- Linear API returns 5xx errors

**Actions:**

1. **Verify Linear status:**
   ```bash
   curl https://status.linear.app
   ```

2. **If Linear is down:**
   - Wait for service restoration
   - Circuit breaker will auto-recover
   - Inform team via Discord (manual message)

3. **If Linear is up but integration failing:**
   - Check API token validity
   - Verify network connectivity
   - Check for API version changes

### Discord Bot Compromised

**Symptoms:**
- Unauthorized commands being executed
- Spam from bot account
- Unexpected bot behavior

**Immediate actions:**

1. **Stop the bot immediately:**
   ```bash
   docker-compose down
   # or
   pm2 stop agentic-base-bot
   # or
   sudo systemctl stop agentic-base-bot
   ```

2. **Revoke bot token in Discord Developer Portal:**
   - Go to Discord Developer Portal
   - Regenerate bot token
   - Do NOT restart bot with old token

3. **Audit logs:**
   ```bash
   # Check recent command execution
   docker-compose logs bot | grep "command" | tail -100

   # Check for suspicious activity
   docker-compose logs bot | grep -i "unauthorized\|forbidden" | tail -50
   ```

4. **Rotate all secrets:**
   - Discord bot token
   - Linear API token
   - Webhook secrets
   - Update `secrets/.env.local`

5. **Review access:**
   - Check Discord server audit log
   - Review bot permissions
   - Review allowed roles in `bot-commands.yml`

6. **Restart with new credentials:**
   ```bash
   docker-compose up -d
   ```

### Data Loss or Corruption

**If configuration lost or corrupted:**

1. **Stop the service:**
   ```bash
   docker-compose down
   ```

2. **Restore from backup:**
   ```bash
   cp -r integration/config.backup/* integration/config/
   cp integration/secrets/.env.local.backup integration/secrets/.env.local
   ```

3. **If no backup, restore from Git:**
   ```bash
   git checkout integration/config/
   # Then manually re-enter secrets
   ```

4. **Restart and verify:**
   ```bash
   docker-compose up -d
   docker-compose logs -f bot
   ```

## Support and Escalation

**For issues not covered in this runbook:**

1. Check `integration/README.md` for additional documentation
2. Check `integration/DEPLOYMENT.md` for deployment-specific issues
3. Review GitHub issues: `https://github.com/your-org/agentic-base/issues`
4. Contact development team with:
   - Symptom description
   - Recent logs (last 100 lines, redacted of secrets)
   - Steps taken to diagnose
   - Health check output
   - System resource usage

**Emergency contacts:**
- DevOps Team: [contact-info]
- Development Team: [contact-info]
- On-call Engineer: [contact-info]
