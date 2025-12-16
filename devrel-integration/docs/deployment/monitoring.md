# Onomancer Bot - Monitoring Guide

> Comprehensive monitoring setup for production Onomancer Bot deployment

**Version:** 1.0
**Date:** 2025-12-16

---

## Table of Contents

1. [Overview](#overview)
2. [PM2 Monitoring](#pm2-monitoring)
3. [Application Logging](#application-logging)
4. [Health Checks](#health-checks)
5. [System Monitoring](#system-monitoring)
6. [Alerting](#alerting)
7. [Troubleshooting Dashboard](#troubleshooting-dashboard)

---

## Overview

### Monitoring Components

| Component | Tool | Purpose |
|-----------|------|---------|
| Process Management | PM2 | Process health, restarts, memory |
| Application Logs | Winston + PM2 | Structured logging |
| System Resources | htop, df, free | CPU, memory, disk |
| Network | nginx logs, ss | HTTP traffic, connections |
| External APIs | Application logs | API health, rate limits |

### Key Metrics to Monitor

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Memory usage | >70% | >85% | Restart app / Increase memory |
| CPU usage | >70% | >90% | Investigate hot loops |
| Disk usage | >80% | >90% | Clean logs / Increase disk |
| Restart count | >3/hour | >10/hour | Investigate crash loops |
| API error rate | >5% | >20% | Check external API status |
| Response time | >30s | >60s | Scale or optimize |

---

## PM2 Monitoring

### Real-Time Monitoring

```bash
# Interactive dashboard
pm2 monit

# Process list with status
pm2 status

# Process details
pm2 describe onomancer-bot
```

### Key PM2 Commands

```bash
# View recent logs
pm2 logs onomancer-bot --lines 100

# View error logs only
pm2 logs onomancer-bot --err --lines 50

# Stream logs in real-time
pm2 logs onomancer-bot

# Reset restart counter
pm2 reset onomancer-bot

# View memory/CPU metrics
pm2 info onomancer-bot
```

### PM2 Metrics Script

Create `/opt/devrel-integration/scripts/pm2-metrics.sh`:

```bash
#!/bin/bash
# PM2 Metrics Collection Script

PM2_HOME=/opt/devrel-integration/.pm2
export PM2_HOME

# Get process info
info=$(pm2 jlist 2>/dev/null | jq -r '.[0] // empty')

if [ -z "$info" ]; then
    echo "ERROR: Process not running"
    exit 1
fi

# Extract metrics
name=$(echo "$info" | jq -r '.name')
status=$(echo "$info" | jq -r '.pm2_env.status')
restarts=$(echo "$info" | jq -r '.pm2_env.restart_time')
uptime=$(echo "$info" | jq -r '.pm2_env.pm_uptime')
memory=$(echo "$info" | jq -r '.monit.memory')
cpu=$(echo "$info" | jq -r '.monit.cpu')

# Convert memory to MB
memory_mb=$((memory / 1024 / 1024))

# Calculate uptime in hours
now=$(date +%s)
uptime_sec=$((now * 1000 - uptime))
uptime_hours=$((uptime_sec / 1000 / 60 / 60))

echo "Process: $name"
echo "Status: $status"
echo "Uptime: ${uptime_hours}h"
echo "Restarts: $restarts"
echo "Memory: ${memory_mb}MB"
echo "CPU: ${cpu}%"

# Return non-zero if unhealthy
if [ "$status" != "online" ]; then
    exit 1
fi
```

---

## Application Logging

### Log Locations

| Log Type | Path | Description |
|----------|------|-------------|
| Combined | `/var/log/devrel/onomancer-combined.log` | All logs |
| Errors | `/var/log/devrel/onomancer-error.log` | Error logs only |
| Output | `/var/log/devrel/onomancer-out.log` | Stdout logs |
| Nginx Access | `/var/log/nginx/onomancer-access.log` | HTTP requests |
| Nginx Errors | `/var/log/nginx/onomancer-error.log` | Nginx errors |

### Log Format

Application logs use structured JSON format via Winston:

```json
{
  "level": "info",
  "message": "Translation completed",
  "timestamp": "2025-12-16T10:30:00.000Z",
  "service": "transformation-pipeline",
  "correlationId": "abc123",
  "duration": 15234,
  "persona": "leadership",
  "project": "mibera"
}
```

### Useful Log Commands

```bash
# View recent logs
tail -f /var/log/devrel/onomancer-combined.log

# Search for errors
grep -i error /var/log/devrel/onomancer-combined.log | tail -20

# Count errors by hour
grep -i error /var/log/devrel/onomancer-combined.log | cut -d'T' -f1-2 | sort | uniq -c

# View JSON logs formatted
tail -f /var/log/devrel/onomancer-combined.log | jq .

# Filter by level
tail -f /var/log/devrel/onomancer-combined.log | jq 'select(.level == "error")'

# Filter by service
tail -f /var/log/devrel/onomancer-combined.log | jq 'select(.service == "transformation-pipeline")'

# View slow operations (>30s)
cat /var/log/devrel/onomancer-combined.log | jq 'select(.duration > 30000)'
```

### Log Rotation

Log rotation is configured in `/etc/logrotate.d/devrel`:

```
/var/log/devrel/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 devrel devrel
    sharedscripts
    postrotate
        PM2_HOME=/opt/devrel-integration/.pm2 pm2 reloadLogs > /dev/null 2>&1 || true
    endscript
}
```

---

## Health Checks

### Internal Health Check

The application exposes a health endpoint at `/health` (if HTTP server is enabled):

```bash
# Check health locally
curl -s http://localhost:3000/health | jq .

# Expected response
{
  "status": "healthy",
  "uptime": 3600,
  "version": "1.0.0",
  "services": {
    "discord": "connected",
    "database": "connected",
    "redis": "connected"  # or "not configured"
  }
}
```

### External Health Check Script

Create `/opt/devrel-integration/scripts/health-check.sh`:

```bash
#!/bin/bash
# Health Check Script for Onomancer Bot

set -e

PM2_HOME=/opt/devrel-integration/.pm2
export PM2_HOME

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Onomancer Bot Health Check ==="
echo ""

# Check 1: PM2 Process
echo -n "PM2 Process: "
if pm2 list 2>/dev/null | grep -q "online.*onomancer-bot"; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    exit 1
fi

# Check 2: Memory Usage
echo -n "Memory Usage: "
mem_percent=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
if [ "$mem_percent" -lt 85 ]; then
    echo -e "${GREEN}${mem_percent}%${NC}"
else
    echo -e "${RED}${mem_percent}%${NC} (HIGH)"
fi

# Check 3: Disk Usage
echo -n "Disk Usage: "
disk_percent=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$disk_percent" -lt 90 ]; then
    echo -e "${GREEN}${disk_percent}%${NC}"
else
    echo -e "${RED}${disk_percent}%${NC} (HIGH)"
fi

# Check 4: Recent Errors
echo -n "Recent Errors (1h): "
errors=$(grep -c "error" /var/log/devrel/onomancer-combined.log 2>/dev/null | tail -1 || echo "0")
if [ "$errors" -lt 10 ]; then
    echo -e "${GREEN}${errors}${NC}"
else
    echo -e "${YELLOW}${errors}${NC}"
fi

# Check 5: Restarts
echo -n "Restarts Today: "
restarts=$(pm2 jlist 2>/dev/null | jq -r '.[0].pm2_env.restart_time // 0')
if [ "$restarts" -lt 5 ]; then
    echo -e "${GREEN}${restarts}${NC}"
else
    echo -e "${YELLOW}${restarts}${NC}"
fi

# Check 6: Nginx
echo -n "Nginx: "
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
fi

# Check 7: SSL Certificate
echo -n "SSL Certificate: "
if [ -n "$DOMAIN" ]; then
    expiry=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | grep notAfter | cut -d= -f2)
    if [ -n "$expiry" ]; then
        expiry_epoch=$(date -d "$expiry" +%s)
        now_epoch=$(date +%s)
        days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
        if [ "$days_left" -gt 30 ]; then
            echo -e "${GREEN}${days_left} days${NC}"
        elif [ "$days_left" -gt 7 ]; then
            echo -e "${YELLOW}${days_left} days${NC}"
        else
            echo -e "${RED}${days_left} days${NC} (EXPIRING SOON)"
        fi
    else
        echo -e "${YELLOW}Unable to check${NC}"
    fi
else
    echo -e "${YELLOW}No domain configured${NC}"
fi

echo ""
echo "=== Health Check Complete ==="
```

### Cron-Based Health Monitoring

Add to crontab (`crontab -e` as devrel user):

```cron
# Health check every 5 minutes
*/5 * * * * /opt/devrel-integration/scripts/health-check.sh >> /var/log/devrel/health-check.log 2>&1

# Daily log cleanup (keep 7 days of health checks)
0 0 * * * find /var/log/devrel -name "health-check.log*" -mtime +7 -delete
```

---

## System Monitoring

### Quick Commands

```bash
# System overview
htop

# Memory usage
free -h

# Disk usage
df -h

# Network connections
ss -tuln

# Process list
ps aux | grep node

# Open files by process
lsof -p $(pgrep -f "onomancer-bot")
```

### System Resource Script

Create `/opt/devrel-integration/scripts/system-stats.sh`:

```bash
#!/bin/bash
# System Statistics Script

echo "=== System Statistics ==="
echo "Time: $(date)"
echo ""

echo "--- CPU ---"
uptime

echo ""
echo "--- Memory ---"
free -h

echo ""
echo "--- Disk ---"
df -h /

echo ""
echo "--- Network ---"
ss -s

echo ""
echo "--- Top Processes ---"
ps aux --sort=-%mem | head -5
```

---

## Alerting

### Simple Email Alert Script

Create `/opt/devrel-integration/scripts/alert.sh`:

```bash
#!/bin/bash
# Alert Script for Onomancer Bot

ALERT_EMAIL="${ALERT_EMAIL:-admin@example.com}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"

send_alert() {
    local severity="$1"
    local message="$2"

    # Log alert
    echo "[$(date)] [$severity] $message" >> /var/log/devrel/alerts.log

    # Send Discord webhook (if configured)
    if [ -n "$ALERT_WEBHOOK" ]; then
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"content\": \"🚨 **[$severity]** $message\"}"
    fi

    # Send email (if mail is configured)
    if command -v mail &> /dev/null && [ -n "$ALERT_EMAIL" ]; then
        echo "$message" | mail -s "[Onomancer] $severity Alert" "$ALERT_EMAIL"
    fi
}

# Export function for use in other scripts
export -f send_alert
```

### Alert Integration

Add alerts to health check script:

```bash
# Add to health-check.sh

source /opt/devrel-integration/scripts/alert.sh

# Alert on process down
if ! pm2 list 2>/dev/null | grep -q "online.*onomancer-bot"; then
    send_alert "CRITICAL" "Onomancer Bot process is not running!"
fi

# Alert on high memory
if [ "$mem_percent" -gt 90 ]; then
    send_alert "WARNING" "Memory usage at ${mem_percent}%"
fi

# Alert on high disk
if [ "$disk_percent" -gt 90 ]; then
    send_alert "WARNING" "Disk usage at ${disk_percent}%"
fi
```

### Discord Webhook Alerting

To receive alerts in Discord:

1. Create a webhook in your Discord server
2. Set the `ALERT_WEBHOOK` environment variable
3. Alerts will be posted to the channel

```bash
# Add to /opt/devrel-integration/secrets/.env.local
ALERT_WEBHOOK=https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN
```

---

## Troubleshooting Dashboard

### Quick Diagnostic Commands

```bash
# One-liner status check
echo "PM2: $(pm2 jlist | jq -r '.[0].pm2_env.status // "not running"') | Mem: $(free -h | grep Mem | awk '{print $3"/"$2}') | Disk: $(df -h / | tail -1 | awk '{print $3"/"$2}') | Errors: $(grep -c error /var/log/devrel/onomancer-combined.log 2>/dev/null | tail -1)"
```

### Common Issues and Solutions

| Symptom | Diagnosis | Solution |
|---------|-----------|----------|
| Bot offline | `pm2 status` shows "stopped" | `pm2 restart onomancer-bot` |
| High memory | `pm2 monit` shows >1GB | Check for memory leaks, increase limit |
| Slow responses | Check logs for timeouts | Scale up or optimize queries |
| API errors | Check circuit breaker status | Wait for auto-recovery or restart |
| Disk full | `df -h` shows >90% | Clean old logs, backups |

### Diagnostic Script

Create `/opt/devrel-integration/scripts/diagnose.sh`:

```bash
#!/bin/bash
# Full Diagnostic Script

echo "=== Onomancer Bot Diagnostics ==="
echo "Generated: $(date)"
echo ""

# System info
echo "--- System ---"
uname -a
echo ""

# Memory
echo "--- Memory ---"
free -h
echo ""

# Disk
echo "--- Disk ---"
df -h
echo ""

# PM2 Status
echo "--- PM2 Status ---"
PM2_HOME=/opt/devrel-integration/.pm2 pm2 status
echo ""

# Recent logs
echo "--- Recent Logs (last 20 lines) ---"
tail -20 /var/log/devrel/onomancer-combined.log
echo ""

# Recent errors
echo "--- Recent Errors (last 10) ---"
grep -i error /var/log/devrel/onomancer-combined.log | tail -10
echo ""

# Network connections
echo "--- Active Connections ---"
ss -tuln | grep -E "(3000|443|80)"
echo ""

# Process details
echo "--- Node Processes ---"
ps aux | grep node | grep -v grep
echo ""

echo "=== End Diagnostics ==="
```

---

## Appendix: Monitoring Checklist

### Daily Checks

- [ ] PM2 process status is "online"
- [ ] No more than 5 restarts in 24h
- [ ] Memory usage < 80%
- [ ] Disk usage < 80%
- [ ] No critical errors in logs

### Weekly Checks

- [ ] Review error trends
- [ ] Check log sizes
- [ ] Verify backups are running
- [ ] Review API usage/quotas
- [ ] Check SSL certificate expiry

### Monthly Checks

- [ ] Review and rotate old logs
- [ ] Clean old database backups
- [ ] Test rollback procedure
- [ ] Review security updates
- [ ] Performance baseline comparison
