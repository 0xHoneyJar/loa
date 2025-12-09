# Server Operations Runbook

Operational procedures for managing the DevRel integration server.

## Quick Reference

| Action | Command |
|--------|---------|
| Check status | `pm2 status` |
| View logs | `pm2 logs devrel-bot` |
| Restart app | `pm2 restart devrel-bot` |
| Stop app | `pm2 stop devrel-bot` |
| Start app | `pm2 start devrel-bot` |
| Health check | `curl http://localhost:3000/health` |

## Starting the Application

### Using PM2 (Recommended)

```bash
# Start application
pm2 start /opt/devrel-integration/ecosystem.config.js

# Or restart if already configured
pm2 restart devrel-bot

# Verify it's running
pm2 status
```

### Using Systemd (Alternative)

```bash
# Start service
sudo systemctl start devrel-integration

# Enable auto-start on boot
sudo systemctl enable devrel-integration

# Check status
sudo systemctl status devrel-integration
```

## Stopping the Application

### Graceful Stop

```bash
# PM2
pm2 stop devrel-bot

# Systemd
sudo systemctl stop devrel-integration
```

### Force Stop (if unresponsive)

```bash
# Find process ID
pgrep -f "node.*bot.js"

# Kill process
kill -9 <PID>

# Or using PM2
pm2 delete devrel-bot
```

## Restarting the Application

### Standard Restart

```bash
# PM2 (zero-downtime for multi-instance)
pm2 restart devrel-bot

# Systemd
sudo systemctl restart devrel-integration
```

### Full Restart (after code update)

```bash
cd /opt/devrel-integration

# Pull latest code
git pull

# Install dependencies
npm ci --production

# Rebuild TypeScript
npm run build

# Restart application
pm2 restart devrel-bot
```

## Viewing Logs

### Real-time Logs

```bash
# All logs (stdout + stderr)
pm2 logs devrel-bot

# Only errors
pm2 logs devrel-bot --err

# Last N lines
pm2 logs devrel-bot --lines 100
```

### Historical Logs

```bash
# Log file locations
/var/log/devrel/out.log     # Application output
/var/log/devrel/error.log   # Application errors

# View with tail
tail -f /var/log/devrel/out.log

# Search logs
grep "error" /var/log/devrel/out.log
grep "Discord" /var/log/devrel/out.log
```

### Log Rotation

Logs are automatically rotated daily. Rotated logs are compressed:

```bash
# List rotated logs
ls -la /var/log/devrel/*.gz

# View rotated log
zcat /var/log/devrel/out.log.1.gz
```

## Health Checks

### Application Health

```bash
# HTTP health check
curl http://localhost:3000/health

# Expected response:
# {"status":"healthy","uptime":12345,"discord":"connected"}
```

### System Health

```bash
# CPU and memory
htop

# Disk usage
df -h

# Network connections
netstat -tlnp | grep node

# PM2 monitoring dashboard
pm2 monit
```

### Discord Connection

```bash
# Check logs for Discord status
pm2 logs devrel-bot --lines 50 | grep -i discord

# Expected: "Discord client ready" or similar
```

## Updating the Application

### Standard Update

```bash
cd /opt/devrel-integration

# 1. Pull latest code
git pull

# 2. Install dependencies (if package.json changed)
npm ci --production

# 3. Rebuild TypeScript
npm run build

# 4. Restart
pm2 restart devrel-bot

# 5. Verify
pm2 status
curl http://localhost:3000/health
pm2 logs devrel-bot --lines 20
```

### Rollback to Previous Version

```bash
cd /opt/devrel-integration

# 1. Find previous commit
git log --oneline -10

# 2. Checkout previous version
git checkout <commit-hash>

# 3. Rebuild and restart
npm ci --production
npm run build
pm2 restart devrel-bot

# 4. Verify rollback
pm2 logs devrel-bot --lines 20
```

## Configuration Changes

### Updating Environment Variables

```bash
# 1. Edit secrets file
nano /opt/devrel-integration/secrets/.env.local

# 2. Restart to apply changes
pm2 restart devrel-bot
```

### Updating Config Files

```bash
# 1. Edit config file
nano /opt/devrel-integration/config/discord-digest.yml

# 2. Restart to apply (some configs may reload automatically)
pm2 restart devrel-bot
```

## Secrets Rotation

### Discord Bot Token

```bash
# 1. Generate new token in Discord Developer Portal
# 2. Update secrets file
nano /opt/devrel-integration/secrets/.env.local
# Change: DISCORD_BOT_TOKEN=new_token_here

# 3. Restart application
pm2 restart devrel-bot

# 4. Verify Discord connection
pm2 logs devrel-bot --lines 20 | grep Discord
```

### Linear API Key

```bash
# 1. Generate new key in Linear Settings > API
# 2. Update secrets file
nano /opt/devrel-integration/secrets/.env.local
# Change: LINEAR_API_KEY=new_key_here

# 3. Restart application
pm2 restart devrel-bot

# 4. Test Linear integration
# Trigger a command that queries Linear
```

## Troubleshooting

### Application Won't Start

```bash
# 1. Check for syntax errors
cd /opt/devrel-integration
node dist/bot.js  # Run directly to see errors

# 2. Check environment variables
cat secrets/.env.local | grep -v "^#"

# 3. Check permissions
ls -la dist/bot.js
chown -R devrel:devrel /opt/devrel-integration

# 4. Check port availability
lsof -i :3000
```

### High Memory Usage

```bash
# 1. Check current usage
pm2 monit

# 2. Restart to clear memory
pm2 restart devrel-bot

# 3. If persistent, check for memory leaks
pm2 logs devrel-bot | grep -i memory
```

### Discord Connection Failed

```bash
# 1. Check token validity
curl -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
  https://discord.com/api/users/@me

# 2. Check network connectivity
ping discord.com
curl -I https://discord.com

# 3. Check logs for specific error
pm2 logs devrel-bot | grep -i "discord\|error"
```

### Linear API Errors

```bash
# 1. Test API token
curl -X POST https://api.linear.app/graphql \
  -H "Authorization: Bearer $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"{ viewer { name } }"}'

# 2. Check rate limits
pm2 logs devrel-bot | grep -i "rate limit"

# 3. Check Linear status
curl https://status.linear.app
```

## Emergency Procedures

### Application Crash Loop

```bash
# 1. Stop the application
pm2 stop devrel-bot

# 2. Check logs for cause
tail -100 /var/log/devrel/error.log

# 3. Fix the issue (rollback, config fix, etc.)

# 4. Clear PM2 logs and restart
pm2 flush devrel-bot
pm2 start devrel-bot
```

### Server Unresponsive

```bash
# 1. SSH to server (if possible)
# 2. Check system resources
top -bn1 | head -20

# 3. If disk full
df -h
# Clear logs if needed
truncate -s 0 /var/log/devrel/out.log

# 4. If memory exhausted
# Kill non-essential processes or reboot
sudo reboot
```

### Security Incident

```bash
# 1. Isolate the server (if network attack)
# Block incoming traffic except your IP
ufw default deny incoming
ufw allow from YOUR_IP to any port 22

# 2. Preserve evidence
cp -r /var/log /root/incident-logs-$(date +%Y%m%d)

# 3. Rotate all secrets
# Generate new tokens for Discord, Linear, etc.

# 4. Review audit logs
cat /var/log/auth.log | tail -100

# 5. Document and report incident
```

## Monitoring Alerts

### Setting Up Discord Alerts

Configure the application to send alerts to a Discord channel:

```bash
# In secrets/.env.local
ALERT_DISCORD_WEBHOOK=https://discord.com/api/webhooks/xxx/yyy
```

### Common Alert Conditions

| Alert | Condition | Action |
|-------|-----------|--------|
| App Down | Health check fails 3x | Check logs, restart |
| High Memory | >80% for 5 min | Restart, investigate leak |
| Disk Full | >90% usage | Clear logs, expand disk |
| API Errors | >10 errors/min | Check external services |

## Backup Procedures

### Configuration Backup

```bash
# Backup configs and secrets
tar -czf backup-$(date +%Y%m%d).tar.gz \
  /opt/devrel-integration/config \
  /opt/devrel-integration/secrets \
  /opt/devrel-integration/ecosystem.config.js

# Encrypt backup
gpg -c backup-$(date +%Y%m%d).tar.gz

# Store securely offsite
```

### Restore from Backup

```bash
# Decrypt backup
gpg -d backup-20250101.tar.gz.gpg > backup.tar.gz

# Extract
tar -xzf backup.tar.gz -C /

# Restart application
pm2 restart devrel-bot
```

## Contact Information

For escalation:
- **Primary**: [Your contact]
- **Secondary**: [Backup contact]
- **Emergency**: [Emergency contact]

## Related Documentation

- [Server Setup Guide](../server-setup-guide.md)
- [Security Checklist](../security-checklist.md)
- [Quick Reference](../quick-reference.md)

---

**Last Updated**: 2025-12-09
