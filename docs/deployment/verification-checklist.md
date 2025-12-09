# Deployment Verification Checklist

Use this checklist to verify successful deployment of the DevRel integration server.

## Infrastructure Verification

### Server Access
- [ ] SSH access working
- [ ] Correct user can sudo
- [ ] Hostname set correctly
- [ ] Timezone configured (UTC recommended)

**Verify:**
```bash
ssh user@server "hostname && timedatectl"
```

### Security Hardening
- [ ] UFW firewall enabled and configured
- [ ] fail2ban running
- [ ] SSH key-only authentication
- [ ] Root login disabled
- [ ] Automatic updates enabled

**Verify:**
```bash
ssh user@server "ufw status && systemctl status fail2ban --no-pager"
```

### Dependencies
- [ ] Node.js installed (v20.x LTS)
- [ ] npm available
- [ ] PM2 installed globally
- [ ] Build tools available

**Verify:**
```bash
ssh user@server "node --version && npm --version && pm2 --version"
```

## Application Verification

### Deployment
- [ ] Application code deployed to `/opt/devrel-integration`
- [ ] Dependencies installed
- [ ] TypeScript compiled (dist/ exists)
- [ ] Correct file ownership

**Verify:**
```bash
ssh user@server "ls -la /opt/devrel-integration/dist/"
```

### Configuration
- [ ] `.env.local` file exists with secrets
- [ ] Config files in place (config/)
- [ ] PM2 ecosystem file configured
- [ ] Log directory exists with write permission

**Verify:**
```bash
ssh user@server "ls -la /opt/devrel-integration/secrets/ && ls /var/log/devrel/"
```

### Service Running
- [ ] PM2 process running
- [ ] Application status is "online"
- [ ] No recent restarts (crash loops)
- [ ] Memory usage reasonable

**Verify:**
```bash
ssh user@server "pm2 status && pm2 show devrel-bot"
```

## Integration Verification

### Health Check
- [ ] Health endpoint responds with 200
- [ ] Response indicates healthy status
- [ ] Uptime counter working

**Verify:**
```bash
ssh user@server "curl -s http://localhost:3000/health | jq ."
# Expected: {"status":"healthy","uptime":123,"discord":"connected"}
```

### Discord Connection
- [ ] Bot shows as online in Discord server
- [ ] Bot responds to commands
- [ ] Logs show "Discord client ready"

**Verify:**
```bash
ssh user@server "pm2 logs devrel-bot --lines 50 | grep -i discord"
```
Then test in Discord:
- Send `/show-sprint` command
- Check for bot response

### Linear Integration
- [ ] Can query Linear API
- [ ] Webhook endpoint accessible
- [ ] Feedback capture working

**Verify:**
```bash
# Test Linear API (replace with actual token check)
ssh user@server 'source /opt/devrel-integration/secrets/.env.local && \
  curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: Bearer $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"query\":\"{ viewer { name } }\"}" | jq .'
```

### Webhook Endpoints (if using nginx/domain)
- [ ] HTTPS working
- [ ] Certificate valid
- [ ] Webhooks reachable from external

**Verify:**
```bash
curl -I https://your-domain.com/health
curl -X POST https://your-domain.com/webhooks/linear -d '{}' -H "Content-Type: application/json"
```

## Logging Verification

### Log Files
- [ ] out.log being written
- [ ] error.log exists (may be empty)
- [ ] Log rotation configured
- [ ] Logs contain expected information

**Verify:**
```bash
ssh user@server "tail -20 /var/log/devrel/out.log"
```

### PM2 Logs
- [ ] PM2 logs accessible
- [ ] Logs show normal operation
- [ ] No repeated errors

**Verify:**
```bash
ssh user@server "pm2 logs devrel-bot --nostream --lines 30"
```

## Persistence Verification

### Auto-Restart on Crash
- [ ] PM2 configured for auto-restart
- [ ] Service restarts after kill

**Verify:**
```bash
# Kill the process and verify restart
ssh user@server "pm2 stop devrel-bot && sleep 5 && pm2 start devrel-bot && sleep 10 && pm2 status"
```

### Auto-Start on Boot
- [ ] PM2 startup configured
- [ ] Service survives reboot

**Verify:**
```bash
ssh user@server "pm2 startup" # Should show "already configured" or success
# For full test: reboot server and verify app starts
```

## Performance Verification

### Resource Usage
- [ ] CPU usage < 50% (idle)
- [ ] Memory usage < 500MB
- [ ] Disk usage < 80%
- [ ] No memory leaks over time

**Verify:**
```bash
ssh user@server "pm2 monit" # Interactive monitoring
# Or single check:
ssh user@server "pm2 show devrel-bot | grep -E 'memory|cpu'"
```

### Response Time
- [ ] Health check < 100ms
- [ ] Commands respond < 5 seconds

**Verify:**
```bash
ssh user@server "time curl -s http://localhost:3000/health"
```

## Final Sign-Off

### Verification Summary

| Check | Status | Notes |
|-------|--------|-------|
| SSH Access | [ ] | |
| Firewall | [ ] | |
| fail2ban | [ ] | |
| Node.js | [ ] | |
| App Deployed | [ ] | |
| PM2 Running | [ ] | |
| Health Check | [ ] | |
| Discord Connected | [ ] | |
| Linear API | [ ] | |
| Logs Working | [ ] | |
| Auto-Restart | [ ] | |

### Deployment Details

- **Server IP**: _______________
- **Domain**: _______________
- **Deployed By**: _______________
- **Date**: _______________
- **Version/Commit**: _______________

### Notes

_Any issues encountered or deviations from standard setup:_

---

**Verification Completed**: [ ] Yes / [ ] No
**Ready for Production**: [ ] Yes / [ ] No

**Verified By**: _______________
**Date**: _______________
