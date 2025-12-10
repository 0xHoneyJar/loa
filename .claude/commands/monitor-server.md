---
description: Launch the DevOps architect to monitor the Discord bot server and generate a health report
---

I'm launching the devops-crypto-architect agent in **server monitoring mode** to check the health and performance of your Discord bot server and generate a comprehensive monitoring report.

**What this command does**:
- Connects to your server and checks system health (CPU, memory, disk, network)
- Verifies Discord bot status and PM2 process health
- Checks security configurations (firewall, SSH, fail2ban)
- Analyzes logs for errors and warnings
- Reviews resource utilization and trends
- Generates a dated monitoring report saved to `docs/deployment/monitoring-reports/YYYY-MM-DD-monitoring-report.md`

**When to use this**:
- Daily/weekly health checks
- Investigating performance issues
- Before making infrastructure changes
- After deployment to verify stability
- During incident investigation

Let me launch the agent now.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are monitoring the Discord bot production server and generating a comprehensive health report. This is **server monitoring mode**.

## Your Mission

Connect to the production server running the DevRel integration Discord bot and perform a thorough health check. Generate a dated monitoring report that provides actionable insights into system health, performance, and potential issues.

## Phase 0: Check for Existing Deployment Context

**IMPORTANT**: Before asking the user any questions, check if deployment context already exists.

Use the Read tool to check for deployment information in these locations:
1. `docs/a2a/deployment-installation-report.md` - Contains server details, deployment configuration, and stack info
2. `docs/a2a/deployment-report.md` - Contains infrastructure details
3. `docs/deployment/runbooks/operational-runbook.md` - Contains operational procedures and server details

If any of these files exist and contain server information, extract:
- Server IP address or hostname
- SSH username (typically `devrel` or `debian`)
- Application deployment path (typically `/opt/devrel-integration`)
- Process manager (PM2, systemd, Docker)
- Services to monitor (Discord bot, nginx, fail2ban, UFW, monitoring stack)
- Deployment date (to calculate how long server has been running)

**Only ask questions if the deployment context files don't exist or are missing critical information.**

## Phase 1: Gather Server Information (if needed)

If deployment context files were not found or are incomplete, ask the user for necessary connection details:

### Server Access
- What is the server IP address or hostname?
- What is the SSH username? (typically the deployment user like `devrel`)
- Should I use SSH key authentication? (path to key if needed)
- What is the application deployment path? (default: `/opt/devrel-integration`)

### Monitoring Scope
- Which services should I monitor?
  - Discord bot process (PM2/systemd)
  - System resources (CPU, memory, disk, network)
  - Security services (fail2ban, UFW)
  - Docker containers (if using Docker)
  - nginx (if using reverse proxy)
  - Monitoring stack (Prometheus/Grafana if installed)
- What time period should I analyze logs for? (default: last 24 hours)
- Are there any specific issues or symptoms to investigate?

### Summary Message

If you found deployment context, inform the user briefly:
"Found deployment context from [file name]. Monitoring server: [IP/hostname] (deployed [date]). Proceeding with health checks..."

If you didn't find context and need to ask questions, say:
"No deployment context found. I need some information about your server to proceed with monitoring..."

## Phase 2: Execute Monitoring Checks

Guide the user to run monitoring commands on their server. Provide the exact commands to run and analyze the output.

### 2.1 System Health Checks

**CPU and Load Average**:
```bash
# Check CPU usage and load average
uptime
top -bn1 | head -20
mpstat 1 3  # If sysstat is installed

# Analyze: Is load average high? Are any processes consuming excessive CPU?
```

**Memory Usage**:
```bash
# Check memory and swap usage
free -h
vmstat 1 3

# Analyze: Is memory usage high? Is swap being used heavily?
```

**Disk Usage and I/O**:
```bash
# Check disk space
df -h
du -sh /opt/devrel-integration/* 2>/dev/null | sort -h

# Check disk I/O
iostat -x 1 3  # If sysstat is installed

# Analyze: Is disk nearly full? Are there I/O bottlenecks?
```

**Network Statistics**:
```bash
# Check network usage and connections
ss -tunapl | grep LISTEN  # Active listening ports
netstat -i  # Network interface statistics
iftop -t -s 10  # If installed, shows bandwidth usage

# Analyze: Are there unexpected open ports? High network traffic?
```

### 2.2 Discord Bot Health Checks

**PM2 Process Status** (if using PM2):
```bash
# Check PM2 process status
pm2 status
pm2 info agentic-base-bot
pm2 logs agentic-base-bot --lines 100 --nostream

# Check PM2 resource usage
pm2 monit

# Analyze: Is bot process running? Restart count? Memory leaks?
```

**Systemd Service Status** (if using systemd):
```bash
# Check systemd service status
systemctl status agentic-base-bot.service
journalctl -u agentic-base-bot.service -n 100 --no-pager

# Analyze: Is service active? Recent failures or restarts?
```

**Docker Container Status** (if using Docker):
```bash
# Check Docker container status
docker ps -a --filter name=devrel
docker stats --no-stream
docker logs devrel-integration --tail 100

# Analyze: Is container running? Resource usage? Errors in logs?
```

**Application Health Endpoint**:
```bash
# Check application health endpoint
curl http://127.0.0.1:3000/health
curl http://127.0.0.1:3000/metrics  # If Prometheus metrics enabled

# Analyze: Is health endpoint responding? What's the bot status?
```

**Discord Bot Connectivity**:
```bash
# Check recent bot activity in logs
tail -100 /opt/devrel-integration/logs/discord-bot.log | grep -i 'connected\|ready\|error'

# Analyze: Is bot connected to Discord? Recent errors?
```

### 2.3 Security Health Checks

**Firewall Status**:
```bash
# Check UFW firewall status
sudo ufw status verbose
sudo ufw show listening

# Analyze: Is firewall enabled? Are rules correct?
```

**fail2ban Status**:
```bash
# Check fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status sshd

# Analyze: Is fail2ban active? Recent ban activity?
```

**SSH Security**:
```bash
# Check SSH configuration
sudo grep -E '^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config

# Check recent SSH login attempts
sudo last -n 20
sudo lastb -n 20  # Failed login attempts

# Analyze: Is SSH hardened? Suspicious login attempts?
```

**System Updates**:
```bash
# Check for available security updates
sudo apt update 2>/dev/null
apt list --upgradable 2>/dev/null | grep -i security

# Analyze: Are security updates available? When was last update?
```

### 2.4 Log Analysis

**Application Logs**:
```bash
# Analyze application logs for errors and warnings
tail -1000 /opt/devrel-integration/logs/discord-bot.log | grep -i 'error\|warn\|fatal' | tail -50

# Check log file sizes
ls -lh /opt/devrel-integration/logs/

# Analyze: Recent errors? Log rotation working? Disk space issues?
```

**System Logs**:
```bash
# Check system logs for errors
sudo journalctl -p err -n 50 --no-pager
sudo dmesg -T | grep -i 'error\|warn' | tail -20

# Analyze: System-level errors? Kernel warnings?
```

**nginx Logs** (if using reverse proxy):
```bash
# Check nginx access and error logs
sudo tail -100 /var/log/nginx/access.log
sudo tail -100 /var/log/nginx/error.log

# Analyze: Request patterns? 4xx/5xx errors? DDoS attempts?
```

### 2.5 Performance Metrics

**Response Time**:
```bash
# Check application response time
time curl -s http://127.0.0.1:3000/health > /dev/null

# Analyze: Is response time acceptable? (<1s is good)
```

**Database/Redis Performance** (if applicable):
```bash
# If using Redis
redis-cli info stats | grep -E 'total_connections_received|total_commands_processed|instantaneous_ops_per_sec'

# If using PostgreSQL
sudo -u postgres psql -c 'SELECT * FROM pg_stat_activity;'

# Analyze: Connection pooling working? Query performance?
```

### 2.6 Backup Verification

**Check Backup Status**:
```bash
# Check for recent backups
ls -lht /opt/devrel-integration/backups/ | head -10

# Verify backup script execution (if using cron)
sudo grep backup /var/log/syslog | tail -20

# Analyze: Are backups running? Recent backup timestamp?
```

## Phase 3: Analyze and Interpret Results

For each check, provide analysis:
- **Status**: HEALTHY ✅ | WARNING ⚠️ | CRITICAL 🔴
- **Findings**: What did you observe?
- **Impact**: How does this affect service reliability?
- **Recommendation**: What action should be taken (if any)?

### Severity Levels:
- **CRITICAL 🔴**: Service down, security breach, imminent failure
- **WARNING ⚠️**: Performance degradation, approaching limits, minor issues
- **HEALTHY ✅**: Operating normally within acceptable parameters

## Phase 4: Generate Monitoring Report

Create a comprehensive monitoring report at:
`docs/deployment/monitoring-reports/YYYY-MM-DD-monitoring-report.md`

Use this structure:

```markdown
# Server Monitoring Report - [Date]

**Generated**: [Timestamp]
**Server**: [IP/Hostname]
**Environment**: Production
**Monitored by**: devops-crypto-architect agent

---

## Executive Summary

**Overall Health**: HEALTHY ✅ | WARNING ⚠️ | CRITICAL 🔴

**Key Findings**:
- [Finding 1 with severity]
- [Finding 2 with severity]
- [Finding 3 with severity]

**Critical Actions Required**: [Number] items
**Warnings to Address**: [Number] items

---

## System Health

### CPU & Load Average
**Status**: [Emoji and status]
- **Current Load**: [1min, 5min, 15min]
- **CPU Cores**: [Number]
- **Top Processes**: [List]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### Memory Usage
**Status**: [Emoji and status]
- **Total Memory**: [GB]
- **Used Memory**: [GB] ([%])
- **Available Memory**: [GB] ([%])
- **Swap Usage**: [GB] ([%])
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### Disk Usage
**Status**: [Emoji and status]
- **Root Partition**: [Used/Total] ([%])
- **Application Logs**: [Size]
- **Backup Storage**: [Size if applicable]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### Network
**Status**: [Emoji and status]
- **Open Ports**: [List]
- **Active Connections**: [Count]
- **Network I/O**: [Stats if available]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

---

## Application Health

### Discord Bot Process
**Status**: [Emoji and status]
- **Process Manager**: PM2 / systemd / Docker
- **Uptime**: [Duration]
- **Restart Count**: [Number] (last 24h)
- **Memory Usage**: [MB]
- **CPU Usage**: [%]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### Bot Connectivity
**Status**: [Emoji and status]
- **Discord Connection**: Connected / Disconnected
- **Last Activity**: [Timestamp]
- **Recent Errors**: [Count] in last 24h
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### Health Endpoint
**Status**: [Emoji and status]
- **HTTP Response**: [Status code]
- **Response Time**: [ms]
- **Service Status**: [JSON response]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

---

## Security Status

### Firewall (UFW)
**Status**: [Emoji and status]
- **Firewall State**: Active / Inactive
- **Open Ports**: [List]
- **Default Policy**: [deny/allow]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### fail2ban
**Status**: [Emoji and status]
- **Service State**: Active / Inactive
- **Banned IPs**: [Count]
- **Recent Bans**: [List top 5]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### SSH Hardening
**Status**: [Emoji and status]
- **Root Login**: Disabled / Enabled
- **Password Auth**: Disabled / Enabled
- **Key Auth**: Enabled / Disabled
- **Recent Logins**: [Last 5]
- **Failed Attempts**: [Count in last 24h]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### System Updates
**Status**: [Emoji and status]
- **Security Updates Available**: [Count]
- **Last Update**: [Date]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

---

## Log Analysis

### Application Errors (Last 24h)
**Status**: [Emoji and status]
- **Error Count**: [Number]
- **Warning Count**: [Number]
- **Top Errors**: [List top 3-5 with counts]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### System Errors (Last 24h)
**Status**: [Emoji and status]
- **Kernel Errors**: [Count]
- **Service Failures**: [Count]
- **Notable Issues**: [List]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### nginx Logs (if applicable)
**Status**: [Emoji and status]
- **Total Requests**: [Count in last 24h]
- **4xx Errors**: [Count]
- **5xx Errors**: [Count]
- **Top IPs**: [List top 5]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

---

## Performance Metrics

### Response Time
**Status**: [Emoji and status]
- **Health Endpoint**: [ms]
- **Target**: <1000ms
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

### Resource Utilization Trends
**Status**: [Emoji and status]
- **CPU Trend**: Stable / Increasing / Decreasing
- **Memory Trend**: Stable / Increasing / Decreasing
- **Disk Trend**: Stable / Increasing / Decreasing
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

---

## Backup Status

### Recent Backups
**Status**: [Emoji and status]
- **Last Backup**: [Date/time]
- **Backup Size**: [Size]
- **Backup Location**: [Path]
- **Backup Age**: [Hours/days]
- **Analysis**: [Your assessment]
- **Recommendation**: [Action if needed]

---

## Action Items

### Critical (Address Immediately) 🔴
1. [Action item with details and urgency]
2. [Action item with details and urgency]

### Warnings (Address Soon) ⚠️
1. [Action item with details and recommended timeline]
2. [Action item with details and recommended timeline]

### Maintenance (Schedule) 🔧
1. [Routine maintenance item]
2. [Routine maintenance item]

---

## Trend Analysis

### Resource Usage Over Time
- **CPU**: [Observation about trends]
- **Memory**: [Observation about trends]
- **Disk**: [Observation about trends]
- **Network**: [Observation about trends]

### Error Patterns
- [Pattern 1 if observed]
- [Pattern 2 if observed]

### Growth Projections
- **Disk Fill Rate**: [X GB/day, full in Y days]
- **Memory Growth**: [Observation]
- **Log Growth**: [X MB/day]

---

## Recommendations

### Immediate Actions (Next 24 Hours)
1. [Specific action with priority]
2. [Specific action with priority]

### Short-Term (This Week)
1. [Action item]
2. [Action item]

### Long-Term (This Month)
1. [Action item]
2. [Action item]

---

## Monitoring Report Metadata

**Report Generated**: [ISO 8601 timestamp]
**Report Generator**: devops-crypto-architect agent (via /monitor-server)
**Next Monitoring Recommended**: [Date - typically 7 days later]
**Monitoring Frequency**: Daily for first week after deployment, then weekly

---

**DevOps Sign-off**: [Overall assessment in 1-2 sentences]
```

## Phase 5: Save Report and Notify

1. Save the report to `docs/deployment/monitoring-reports/YYYY-MM-DD-monitoring-report.md`
2. If critical issues found, create a summary of immediate actions required
3. Inform the user:
   - Overall health status
   - Number of critical/warning/maintenance items
   - Immediate actions required (if any)
   - Where to find the full report

## Best Practices

### Analysis Quality:
- Be specific with numbers and thresholds
- Compare against baselines and best practices
- Provide context (e.g., \"70% memory usage is normal for this workload\")
- Flag trends (increasing over time vs. stable)

### Recommendations:
- Prioritize by severity and impact
- Provide specific commands or steps
- Include links to relevant runbooks or documentation
- Estimate effort required (5 min, 1 hour, etc.)

### Report Format:
- Use emojis for quick visual status (✅ ⚠️ 🔴)
- Include timestamps for all observations
- Provide copy-paste commands for fixes
- Link to relevant documentation or runbooks

## Critical Success Factors

- **Thoroughness**: Check all critical components
- **Clarity**: Make findings actionable and understandable
- **Priority**: Clearly distinguish critical vs. maintenance items
- **Trends**: Identify patterns and project future issues
- **Actionability**: Every finding should have a recommended action

Your goal is to provide a comprehensive, actionable monitoring report that helps the user maintain a healthy, secure, and performant Discord bot server."
/>
