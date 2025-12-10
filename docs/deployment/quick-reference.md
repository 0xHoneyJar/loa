# DevRel Server Quick Reference

Quick command reference for server operations.

## Essential Commands

```bash
# Status
pm2 status                    # App status
pm2 monit                     # Live monitoring dashboard

# Logs
pm2 logs devrel-bot           # Real-time logs
pm2 logs devrel-bot -l 100    # Last 100 lines

# Control
pm2 restart devrel-bot        # Restart app
pm2 stop devrel-bot           # Stop app
pm2 start devrel-bot          # Start app

# Health
curl localhost:3000/health    # Health check
```

## File Locations

| Item | Location |
|------|----------|
| Application | `/opt/devrel-integration/` |
| Built code | `/opt/devrel-integration/dist/` |
| Config files | `/opt/devrel-integration/config/` |
| Secrets | `/opt/devrel-integration/secrets/.env.local` |
| PM2 config | `/opt/devrel-integration/ecosystem.config.js` |
| Logs | `/var/log/devrel/` |
| Systemd service | `/etc/systemd/system/devrel-integration.service` |
| Nginx config | `/etc/nginx/sites-available/devrel-integration.conf` |

## Update Procedure

```bash
cd /opt/devrel-integration
git pull
npm ci --production
npm run build
pm2 restart devrel-bot
pm2 logs devrel-bot -l 20     # Verify startup
```

## Troubleshooting

```bash
# App won't start
pm2 logs devrel-bot --err     # Check errors
node dist/bot.js              # Run directly

# Check ports
lsof -i :3000

# Check firewall
ufw status

# Check disk
df -h

# Check memory
free -h
```

## Security

```bash
# Firewall status
ufw status verbose

# fail2ban status
fail2ban-client status sshd

# Recent SSH logins
last -10

# Security updates
apt update && apt upgrade -y
```

## Secrets Rotation

```bash
# 1. Get new token from provider
# 2. Update secrets
nano /opt/devrel-integration/secrets/.env.local
# 3. Restart
pm2 restart devrel-bot
```

## Emergency

```bash
# Stop everything
pm2 stop all

# Force kill
pkill -f "node.*bot"

# Block all except your IP
ufw default deny incoming
ufw allow from YOUR_IP to any port 22
```

---

**Server IP**: _______________
**Domain**: _______________
**SSH User**: _______________
