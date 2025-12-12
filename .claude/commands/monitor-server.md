---
description: Launch the DevOps architect to monitor the Discord bot server and generate a health report
args: [background]
---

I'm launching the devops-crypto-architect agent in **server monitoring mode** to check the health and performance of your Discord bot server and generate a comprehensive monitoring report.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

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

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="devops-crypto-architect"
  prompt="You are monitoring the Discord bot production server and generating a comprehensive health report. This is **server monitoring mode**.

## Phase 0: Check for Existing Deployment Context

Before asking questions, check for deployment info in:
1. `docs/a2a/deployment-installation-report.md`
2. `docs/a2a/deployment-report.md`
3. `docs/deployment/runbooks/operational-runbook.md`

Extract: Server IP, SSH username, app path, process manager, services to monitor.

Only ask questions if deployment context files don't exist or are missing info.

## Phase 1: Gather Server Information (if needed)

If no context found, ask for:
- Server IP/hostname and SSH username
- Application deployment path
- Which services to monitor
- Time period for log analysis
- Any specific issues to investigate

## Phase 2: Execute Monitoring Checks

Guide user to run these checks:

### 2.1 System Health
- CPU/Load: `uptime`, `top -bn1 | head -20`
- Memory: `free -h`, `vmstat 1 3`
- Disk: `df -h`, `du -sh /opt/devrel-integration/*`
- Network: `ss -tunapl | grep LISTEN`

### 2.2 Discord Bot Health
- PM2: `pm2 status`, `pm2 info agentic-base-bot`, `pm2 logs --lines 100`
- Or systemd: `systemctl status agentic-base-bot.service`
- Or Docker: `docker ps -a`, `docker stats --no-stream`
- Health endpoint: `curl http://127.0.0.1:3000/health`

### 2.3 Security Health
- Firewall: `sudo ufw status verbose`
- fail2ban: `sudo fail2ban-client status sshd`
- SSH: Check config and recent logins
- Updates: `apt list --upgradable | grep security`

### 2.4 Log Analysis
- App errors: `grep -i 'error\|warn' logs/discord-bot.log | tail -50`
- System: `sudo journalctl -p err -n 50`
- nginx (if used): Check access and error logs

### 2.5 Performance Metrics
- Response time: `time curl -s http://127.0.0.1:3000/health`
- Database/Redis (if applicable)

### 2.6 Backup Verification
- Recent backups: `ls -lht /opt/devrel-integration/backups/`

## Phase 3: Analyze Results

For each check, provide:
- **Status**: HEALTHY ✅ | WARNING ⚠️ | CRITICAL 🔴
- **Findings**: What was observed
- **Impact**: How it affects service
- **Recommendation**: Action to take

## Phase 4: Generate Monitoring Report

Create report at `docs/deployment/monitoring-reports/YYYY-MM-DD-monitoring-report.md` with:
- Executive Summary (overall health, key findings, action counts)
- System Health (CPU, Memory, Disk, Network)
- Application Health (process status, connectivity, health endpoint)
- Security Status (firewall, fail2ban, SSH, updates)
- Log Analysis (app errors, system errors, nginx)
- Performance Metrics (response time, trends)
- Backup Status
- Action Items (Critical, Warnings, Maintenance)
- Trend Analysis
- Recommendations (immediate, short-term, long-term)

## Phase 5: Save and Notify

1. Save report to `docs/deployment/monitoring-reports/`
2. Summarize critical issues for user
3. Recommend next monitoring date

Your goal is to provide a comprehensive, actionable monitoring report."
/>
{{ else }}
Let me begin server monitoring.

You are monitoring the Discord bot production server and generating a comprehensive health report. This is **server monitoring mode**.

## Phase 0: Check for Existing Deployment Context

Before asking questions, check for deployment info in:
1. `docs/a2a/deployment-installation-report.md`
2. `docs/a2a/deployment-report.md`
3. `docs/deployment/runbooks/operational-runbook.md`

Extract: Server IP, SSH username, app path, process manager, services to monitor.

Only ask questions if deployment context files don't exist or are missing info.

## Phase 1: Gather Server Information (if needed)

If no context found, ask for:
- Server IP/hostname and SSH username
- Application deployment path
- Which services to monitor
- Time period for log analysis
- Any specific issues to investigate

## Phase 2: Execute Monitoring Checks

Guide user to run these checks:

### 2.1 System Health
- CPU/Load: `uptime`, `top -bn1 | head -20`
- Memory: `free -h`, `vmstat 1 3`
- Disk: `df -h`, `du -sh /opt/devrel-integration/*`
- Network: `ss -tunapl | grep LISTEN`

### 2.2 Discord Bot Health
- PM2: `pm2 status`, `pm2 info agentic-base-bot`, `pm2 logs --lines 100`
- Or systemd: `systemctl status agentic-base-bot.service`
- Or Docker: `docker ps -a`, `docker stats --no-stream`
- Health endpoint: `curl http://127.0.0.1:3000/health`

### 2.3 Security Health
- Firewall: `sudo ufw status verbose`
- fail2ban: `sudo fail2ban-client status sshd`
- SSH: Check config and recent logins
- Updates: `apt list --upgradable | grep security`

### 2.4 Log Analysis
- App errors: `grep -i 'error\|warn' logs/discord-bot.log | tail -50`
- System: `sudo journalctl -p err -n 50`
- nginx (if used): Check access and error logs

### 2.5 Performance Metrics
- Response time: `time curl -s http://127.0.0.1:3000/health`
- Database/Redis (if applicable)

### 2.6 Backup Verification
- Recent backups: `ls -lht /opt/devrel-integration/backups/`

## Phase 3: Analyze Results

For each check, provide:
- **Status**: HEALTHY ✅ | WARNING ⚠️ | CRITICAL 🔴
- **Findings**: What was observed
- **Impact**: How it affects service
- **Recommendation**: Action to take

## Phase 4: Generate Monitoring Report

Create report at `docs/deployment/monitoring-reports/YYYY-MM-DD-monitoring-report.md` with:
- Executive Summary (overall health, key findings, action counts)
- System Health (CPU, Memory, Disk, Network)
- Application Health (process status, connectivity, health endpoint)
- Security Status (firewall, fail2ban, SSH, updates)
- Log Analysis (app errors, system errors, nginx)
- Performance Metrics (response time, trends)
- Backup Status
- Action Items (Critical, Warnings, Maintenance)
- Trend Analysis
- Recommendations (immediate, short-term, long-term)

## Phase 5: Save and Notify

1. Save report to `docs/deployment/monitoring-reports/`
2. Summarize critical issues for user
3. Recommend next monitoring date

Your goal is to provide a comprehensive, actionable monitoring report.
{{ endif }}
