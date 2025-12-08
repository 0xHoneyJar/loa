# Disaster Recovery Plan

**Status**: ✅ APPROVED
**Version**: 1.0
**Last Updated**: December 8, 2025
**Owner**: Infrastructure & Security Team
**Review Schedule**: Quarterly

---

## Table of Contents

1. [Overview](#overview)
2. [Recovery Objectives](#recovery-objectives)
3. [Backup Strategy](#backup-strategy)
4. [Recovery Procedures](#recovery-procedures)
5. [Service Redundancy & Failover](#service-redundancy--failover)
6. [Disaster Scenarios](#disaster-scenarios)
7. [Testing & Verification](#testing--verification)
8. [Monitoring & Alerting](#monitoring--alerting)
9. [Roles & Responsibilities](#roles--responsibilities)
10. [Contact Information](#contact-information)

---

## Overview

This Disaster Recovery Plan (DRP) defines the procedures for recovering the Agentic-Base integration system from catastrophic failures, data loss, or service disruptions. The system integrates Discord, Linear, GitHub, and Vercel with automated workflows for team communication, project tracking, and stakeholder updates.

### Scope

**In Scope**:
- Discord bot application and services
- Database (SQLite: auth.db)
- Configuration files (YAML, JSON)
- Application logs
- Docker containers and PM2 processes
- External service integrations (Discord, Linear, GitHub, Vercel)
- Secrets and environment variables

**Out of Scope**:
- External services themselves (Discord, Linear, GitHub, Vercel)
- User devices or workstations
- Network infrastructure (beyond application level)
- Third-party dependencies (npm packages)

### Disaster Types

This DRP covers the following disaster scenarios:

1. **Data Loss**: Database corruption, accidental deletion, ransomware
2. **Service Outage**: Bot crash, server failure, infrastructure outage
3. **Configuration Corruption**: Invalid configs, accidental changes
4. **Security Breach**: Compromised credentials, unauthorized access
5. **Infrastructure Failure**: Hardware failure, data center outage
6. **Human Error**: Accidental deletion, misconfiguration, bad deployment

---

## Recovery Objectives

### RTO (Recovery Time Objective)

**Target**: 2 hours

The maximum acceptable time to restore services after a disaster declaration.

**Breakdown by Component**:
| Component | RTO | Priority |
|-----------|-----|----------|
| Discord Bot (core features) | 30 minutes | CRITICAL |
| Database (auth.db) | 1 hour | CRITICAL |
| Configuration files | 15 minutes | HIGH |
| Logs (historical) | 4 hours | MEDIUM |
| Webhooks (Linear, GitHub) | 2 hours | HIGH |
| Automated workflows (digest, sync) | 3 hours | MEDIUM |

### RPO (Recovery Point Objective)

**Target**: 24 hours

The maximum acceptable amount of data loss measured in time.

**Breakdown by Data Type**:
| Data Type | RPO | Backup Frequency |
|-----------|-----|------------------|
| Database (auth.db) | 24 hours | Daily (automated) |
| Configuration files | 1 hour | Git commit (on change) |
| Application logs | 7 days | Weekly (archived) |
| Environment variables | 1 week | Manual (encrypted backup) |
| User preferences | 24 hours | Daily (with database) |

### Service Level Objectives

**Availability Target**: 99.5% uptime (43.8 hours downtime/year)

**Performance Targets**:
- Bot command response: < 2 seconds
- Database queries: < 100ms
- Webhook processing: < 5 seconds
- Log ingestion: < 1 second

---

## Backup Strategy

### 1. Database Backups

#### SQLite Database: `data/auth.db`

**Backup Schedule**:
- **Daily**: Full database backup at 3:00 AM UTC
- **Weekly**: Full backup with 4-week retention
- **Monthly**: Archive backup with 1-year retention

**Backup Script**: `scripts/backup-database.sh`

```bash
#!/bin/bash
# Database backup script
# Location: scripts/backup-database.sh

set -e

BACKUP_DIR="/var/backups/agentic-base/database"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
DB_FILE="/opt/agentic-base/integration/data/auth.db"
BACKUP_FILE="$BACKUP_DIR/auth-db-$DATE.sqlite"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup database (online backup with integrity check)
sqlite3 "$DB_FILE" ".backup '$BACKUP_FILE'"

# Verify backup integrity
sqlite3 "$BACKUP_FILE" "PRAGMA integrity_check;" > /dev/null

# Compress backup
gzip "$BACKUP_FILE"

# Calculate checksum
sha256sum "$BACKUP_FILE.gz" > "$BACKUP_FILE.gz.sha256"

echo "✅ Database backup complete: $BACKUP_FILE.gz"

# Retention: Delete backups older than 30 days
find "$BACKUP_DIR" -name "auth-db-*.sqlite.gz" -mtime +30 -delete

# Weekly backup (copy to long-term storage)
if [ "$(date +%u)" -eq 7 ]; then
  WEEKLY_DIR="$BACKUP_DIR/weekly"
  mkdir -p "$WEEKLY_DIR"
  cp "$BACKUP_FILE.gz" "$WEEKLY_DIR/auth-db-$(date +%Y-W%V).sqlite.gz"

  # Delete weekly backups older than 28 days (4 weeks)
  find "$WEEKLY_DIR" -name "auth-db-*.sqlite.gz" -mtime +28 -delete
fi

# Monthly backup (copy to archive storage)
if [ "$(date +%d)" -eq 01 ]; then
  MONTHLY_DIR="$BACKUP_DIR/monthly"
  mkdir -p "$MONTHLY_DIR"
  cp "$BACKUP_FILE.gz" "$MONTHLY_DIR/auth-db-$(date +%Y-%m).sqlite.gz"

  # Delete monthly backups older than 365 days (1 year)
  find "$MONTHLY_DIR" -name "auth-db-*.sqlite.gz" -mtime +365 -delete
fi
```

**Cron Schedule**:
```cron
# Daily database backup at 3:00 AM UTC
0 3 * * * /opt/agentic-base/integration/scripts/backup-database.sh >> /var/log/agentic-base-backup.log 2>&1
```

**Storage Locations**:
- **Primary**: `/var/backups/agentic-base/database/` (local server)
- **Secondary**: AWS S3 bucket `s3://agentic-base-backups/database/` (encrypted)
- **Tertiary**: Google Cloud Storage `gs://agentic-base-backups/database/` (geo-redundant)

**Encryption**:
- Backups encrypted at rest using AES-256
- Encryption key stored in AWS Secrets Manager / Google Secret Manager
- Backup files encrypted before upload to cloud storage

### 2. Configuration File Backups

#### Configuration Directory: `config/`

**Files**:
- `bot-commands.yml`
- `discord-digest.yml`
- `linear-sync.yml`
- `rbac-config.yaml`
- `secrets-rotation-policy.yaml`
- `user-preferences.json`

**Backup Strategy**:
- **Primary**: Git repository (version controlled)
- **Commit on change**: Automatic commit when config files modified
- **Daily snapshot**: Full config directory backup with database

**Backup Script**: `scripts/backup-configs.sh`

```bash
#!/bin/bash
# Configuration backup script
# Location: scripts/backup-configs.sh

set -e

BACKUP_DIR="/var/backups/agentic-base/configs"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
CONFIG_DIR="/opt/agentic-base/integration/config"
BACKUP_FILE="$BACKUP_DIR/configs-$DATE.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup configuration files
tar -czf "$BACKUP_FILE" -C "$CONFIG_DIR" .

# Calculate checksum
sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256"

echo "✅ Configuration backup complete: $BACKUP_FILE"

# Retention: Delete backups older than 30 days
find "$BACKUP_DIR" -name "configs-*.tar.gz" -mtime +30 -delete
```

**Git Commit Strategy**:
```bash
# Auto-commit config changes (triggered by file watcher)
cd /opt/agentic-base/integration
git add config/
git commit -m "Auto-backup: Configuration change at $(date +%Y-%m-%d\ %H:%M:%S)" || true
git push origin main
```

### 3. Log Backups

#### Log Directory: `logs/`

**Files**:
- Application logs (Winston daily rotate)
- PM2 logs (error, output, combined)
- Security audit logs
- Critical security logs

**Backup Schedule**:
- **Weekly**: Full log archive (compressed)
- **Monthly**: Long-term log archive (1-year retention)
- **Real-time**: Critical logs streamed to centralized logging (optional)

**Backup Script**: `scripts/backup-logs.sh`

```bash
#!/bin/bash
# Log backup script
# Location: scripts/backup-logs.sh

set -e

BACKUP_DIR="/var/backups/agentic-base/logs"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
LOG_DIR="/opt/agentic-base/integration/logs"
BACKUP_FILE="$BACKUP_DIR/logs-$DATE.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup logs (exclude current day's logs)
find "$LOG_DIR" -name "*.log" -mtime +1 -type f | tar -czf "$BACKUP_FILE" -T -

# Calculate checksum
sha256sum "$BACKUP_FILE" > "$BACKUP_FILE.sha256"

echo "✅ Log backup complete: $BACKUP_FILE"

# Retention: Delete log backups older than 90 days
find "$BACKUP_DIR" -name "logs-*.tar.gz" -mtime +90 -delete
```

**Cron Schedule**:
```cron
# Weekly log backup every Sunday at 4:00 AM UTC
0 4 * * 0 /opt/agentic-base/integration/scripts/backup-logs.sh >> /var/log/agentic-base-backup.log 2>&1
```

### 4. Secrets & Environment Variables

#### Secrets Directory: `secrets/.env.local`

**Backup Strategy**:
- **Encrypted backup**: Weekly encrypted backup of `.env.local`
- **Secrets manager**: Store critical secrets in AWS Secrets Manager / Google Secret Manager
- **Manual backup**: Encrypted USB drive stored in secure location (offline backup)

**CRITICAL**: Never store secrets in unencrypted backups or commit to Git!

**Backup Script**: `scripts/backup-secrets.sh`

```bash
#!/bin/bash
# Secrets backup script (encrypted)
# Location: scripts/backup-secrets.sh

set -e

BACKUP_DIR="/var/backups/agentic-base/secrets"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
SECRETS_FILE="/opt/agentic-base/integration/secrets/.env.local"
BACKUP_FILE="$BACKUP_DIR/secrets-$DATE.tar.gz.gpg"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup secrets (encrypted with GPG)
tar -czf - "$SECRETS_FILE" | gpg --symmetric --cipher-algo AES256 --output "$BACKUP_FILE"

echo "✅ Secrets backup complete (encrypted): $BACKUP_FILE"

# Retention: Delete encrypted backups older than 90 days
find "$BACKUP_DIR" -name "secrets-*.tar.gz.gpg" -mtime +90 -delete
```

**GPG Passphrase**: Stored in separate secure location (not on server)

**Cron Schedule**:
```cron
# Weekly secrets backup every Sunday at 5:00 AM UTC
0 5 * * 0 /opt/agentic-base/integration/scripts/backup-secrets.sh >> /var/log/agentic-base-backup.log 2>&1
```

### 5. Docker Images & Configurations

#### Docker Configuration

**Backup Items**:
- `Dockerfile`
- `docker-compose.yml`
- `.dockerignore`
- Docker volumes (data/, logs/)

**Backup Strategy**:
- **Git repository**: Version-controlled Dockerfile and docker-compose.yml
- **Docker image export**: Weekly export of built images
- **Volume backups**: Included in database and log backups

**Backup Script**: `scripts/backup-docker.sh`

```bash
#!/bin/bash
# Docker image backup script
# Location: scripts/backup-docker.sh

set -e

BACKUP_DIR="/var/backups/agentic-base/docker"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
IMAGE_NAME="agentic-base-bot:latest"
BACKUP_FILE="$BACKUP_DIR/docker-image-$DATE.tar"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Export Docker image
docker save "$IMAGE_NAME" -o "$BACKUP_FILE"

# Compress backup
gzip "$BACKUP_FILE"

# Calculate checksum
sha256sum "$BACKUP_FILE.gz" > "$BACKUP_FILE.gz.sha256"

echo "✅ Docker image backup complete: $BACKUP_FILE.gz"

# Retention: Delete image backups older than 30 days
find "$BACKUP_DIR" -name "docker-image-*.tar.gz" -mtime +30 -delete
```

### 6. PM2 Process State

#### PM2 Configuration

**Backup Items**:
- `ecosystem.config.js`
- PM2 dump file (`~/.pm2/dump.pm2`)
- PM2 logs

**Backup Strategy**:
- **Git repository**: Version-controlled ecosystem.config.js
- **PM2 save**: Periodic PM2 state save

**Backup Script**: `scripts/backup-pm2.sh`

```bash
#!/bin/bash
# PM2 state backup script
# Location: scripts/backup-pm2.sh

set -e

BACKUP_DIR="/var/backups/agentic-base/pm2"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
PM2_DIR="$HOME/.pm2"
BACKUP_FILE="$BACKUP_DIR/pm2-state-$DATE.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Save PM2 state
pm2 save

# Backup PM2 directory
tar -czf "$BACKUP_FILE" -C "$PM2_DIR" .

echo "✅ PM2 state backup complete: $BACKUP_FILE"

# Retention: Delete PM2 backups older than 30 days
find "$BACKUP_DIR" -name "pm2-state-*.tar.gz" -mtime +30 -delete
```

---

## Recovery Procedures

### General Recovery Steps

**Prerequisites**:
1. Access to backup storage (S3, GCS, local backups)
2. Server access (SSH, console)
3. Decryption keys (for encrypted backups)
4. Service credentials (Discord bot token, API keys)

**Recovery Workflow**:
```
1. Declare disaster
2. Assess damage and identify affected components
3. Notify stakeholders
4. Execute component-specific recovery procedures
5. Verify recovered services
6. Resume operations
7. Conduct post-incident review
```

### 1. Database Recovery

#### Scenario: Database Corrupted or Deleted

**Recovery Steps**:

1. **Stop the application**:
   ```bash
   # If using Docker
   docker-compose down

   # If using PM2
   pm2 stop agentic-base-bot
   ```

2. **Locate most recent backup**:
   ```bash
   # List available backups
   ls -lht /var/backups/agentic-base/database/auth-db-*.sqlite.gz | head -n 5

   # Or from S3
   aws s3 ls s3://agentic-base-backups/database/ --recursive | sort -r | head -n 5
   ```

3. **Download backup (if remote)**:
   ```bash
   # From AWS S3
   aws s3 cp s3://agentic-base-backups/database/auth-db-2025-12-08_03-00-00.sqlite.gz /tmp/

   # From Google Cloud Storage
   gsutil cp gs://agentic-base-backups/database/auth-db-2025-12-08_03-00-00.sqlite.gz /tmp/
   ```

4. **Verify backup integrity**:
   ```bash
   # Verify checksum
   sha256sum -c /tmp/auth-db-2025-12-08_03-00-00.sqlite.gz.sha256

   # Decompress backup
   gunzip /tmp/auth-db-2025-12-08_03-00-00.sqlite.gz

   # Verify SQLite integrity
   sqlite3 /tmp/auth-db-2025-12-08_03-00-00.sqlite "PRAGMA integrity_check;"
   ```

5. **Restore database**:
   ```bash
   # Backup current (corrupted) database
   mv /opt/agentic-base/integration/data/auth.db /opt/agentic-base/integration/data/auth.db.corrupted-$(date +%Y%m%d)

   # Restore from backup
   cp /tmp/auth-db-2025-12-08_03-00-00.sqlite /opt/agentic-base/integration/data/auth.db

   # Set correct permissions
   chmod 600 /opt/agentic-base/integration/data/auth.db
   chown app:app /opt/agentic-base/integration/data/auth.db
   ```

6. **Verify restoration**:
   ```bash
   # Test database connection
   sqlite3 /opt/agentic-base/integration/data/auth.db "SELECT COUNT(*) FROM users;"

   # Verify critical tables
   sqlite3 /opt/agentic-base/integration/data/auth.db ".tables"
   ```

7. **Restart application**:
   ```bash
   # If using Docker
   docker-compose up -d

   # If using PM2
   pm2 start agentic-base-bot

   # Verify bot is online
   pm2 logs agentic-base-bot --lines 50
   ```

8. **Verify functionality**:
   ```bash
   # Test bot command
   # In Discord: /help

   # Check database operations
   # In Discord: /mfa-status
   ```

**Estimated Recovery Time**: 30-60 minutes

**Data Loss**: Up to 24 hours (since last backup)

### 2. Configuration Recovery

#### Scenario: Configuration Files Corrupted or Deleted

**Recovery Steps**:

1. **Identify corrupted configs**:
   ```bash
   # Check which configs are missing or invalid
   ls -la /opt/agentic-base/integration/config/

   # Validate YAML syntax
   yamllint /opt/agentic-base/integration/config/*.yml
   ```

2. **Restore from Git**:
   ```bash
   cd /opt/agentic-base/integration

   # Reset to last known good commit
   git checkout main -- config/

   # Or restore specific file
   git checkout main -- config/bot-commands.yml
   ```

3. **Or restore from backup**:
   ```bash
   # Find latest backup
   ls -lht /var/backups/agentic-base/configs/configs-*.tar.gz | head -n 1

   # Extract backup
   tar -xzf /var/backups/agentic-base/configs/configs-2025-12-08_03-00-00.tar.gz -C /opt/agentic-base/integration/config/
   ```

4. **Verify configurations**:
   ```bash
   # Validate YAML syntax
   yamllint /opt/agentic-base/integration/config/*.yml

   # Test config loading (dry run)
   npm run bot:start -- --dry-run
   ```

5. **Restart application**:
   ```bash
   # Restart to pick up new configs
   docker-compose restart
   # OR
   pm2 restart agentic-base-bot
   ```

**Estimated Recovery Time**: 10-15 minutes

**Data Loss**: None (configs are version-controlled)

### 3. Complete System Recovery

#### Scenario: Server Failure or Data Center Outage

**Recovery Steps**:

1. **Provision new server**:
   ```bash
   # Cloud VM (AWS EC2, GCP Compute Engine, etc.)
   # Minimum specs: 2 vCPU, 4GB RAM, 50GB SSD

   # Install prerequisites
   sudo apt-get update
   sudo apt-get install -y docker.io docker-compose nodejs npm git sqlite3

   # Install PM2 (if using PM2 instead of Docker)
   sudo npm install -g pm2
   ```

2. **Clone repository**:
   ```bash
   # Clone codebase
   git clone https://github.com/your-org/agentic-base.git /opt/agentic-base
   cd /opt/agentic-base/integration

   # Install dependencies
   npm install

   # Build application
   npm run build
   ```

3. **Restore database**:
   ```bash
   # Download latest backup from S3
   aws s3 cp s3://agentic-base-backups/database/auth-db-2025-12-08_03-00-00.sqlite.gz /tmp/

   # Decompress and verify
   gunzip /tmp/auth-db-2025-12-08_03-00-00.sqlite.gz
   sqlite3 /tmp/auth-db-2025-12-08_03-00-00.sqlite "PRAGMA integrity_check;"

   # Copy to data directory
   mkdir -p /opt/agentic-base/integration/data
   cp /tmp/auth-db-2025-12-08_03-00-00.sqlite /opt/agentic-base/integration/data/auth.db
   chmod 600 /opt/agentic-base/integration/data/auth.db
   ```

4. **Restore configuration files**:
   ```bash
   # Configs are in Git, but restore user-specific files
   aws s3 cp s3://agentic-base-backups/configs/configs-2025-12-08_03-00-00.tar.gz /tmp/
   tar -xzf /tmp/configs-2025-12-08_03-00-00.tar.gz -C /opt/agentic-base/integration/config/
   ```

5. **Restore secrets**:
   ```bash
   # Download encrypted secrets backup
   aws s3 cp s3://agentic-base-backups/secrets/secrets-2025-12-08_05-00-00.tar.gz.gpg /tmp/

   # Decrypt (requires GPG passphrase)
   gpg --decrypt /tmp/secrets-2025-12-08_05-00-00.tar.gz.gpg | tar -xzf - -C /opt/agentic-base/integration/secrets/

   # Or manually recreate .env.local from password manager
   ```

6. **Start services**:
   ```bash
   # Using Docker
   cd /opt/agentic-base/integration
   docker-compose up -d

   # Using PM2
   pm2 start ecosystem.config.js --env production
   pm2 save
   pm2 startup
   ```

7. **Verify all services**:
   ```bash
   # Check Docker containers
   docker-compose ps

   # Check PM2 processes
   pm2 list

   # Test bot in Discord
   # /help
   # /show-sprint
   # /mfa-status

   # Check webhooks
   curl -I http://localhost:3000/health
   ```

8. **Reconfigure DNS and webhooks**:
   ```bash
   # Update DNS A record to point to new server IP
   # Update webhook URLs in Linear, GitHub
   # Update Discord bot webhook URL (if using webhooks)
   ```

**Estimated Recovery Time**: 1.5-2 hours

**Data Loss**: Up to 24 hours (database), minimal for configs and code

### 4. Secrets Compromise Recovery

#### Scenario: API Keys or Bot Token Compromised

**Recovery Steps**:

1. **Immediately revoke compromised credentials**:
   ```bash
   # Discord Bot Token: https://discord.com/developers/applications
   # Linear API Key: https://linear.app/settings/api
   # GitHub Personal Access Token: https://github.com/settings/tokens
   # Vercel API Token: https://vercel.com/account/tokens
   # Anthropic API Key: https://console.anthropic.com/
   ```

2. **Generate new credentials**:
   - Discord: Generate new bot token
   - Linear: Create new API key with restricted scopes
   - GitHub: Create new PAT with minimum permissions
   - Vercel: Create new API token
   - Anthropic: Create new API key

3. **Update `.env.local` file**:
   ```bash
   # Edit secrets file
   nano /opt/agentic-base/integration/secrets/.env.local

   # Update compromised credentials
   DISCORD_BOT_TOKEN=NEW_TOKEN_HERE
   LINEAR_API_KEY=NEW_KEY_HERE
   GITHUB_PERSONAL_ACCESS_TOKEN=NEW_TOKEN_HERE
   VERCEL_API_TOKEN=NEW_TOKEN_HERE
   ANTHROPIC_API_KEY=NEW_KEY_HERE
   ```

4. **Restart services**:
   ```bash
   docker-compose restart
   # OR
   pm2 restart agentic-base-bot
   ```

5. **Verify new credentials**:
   ```bash
   # Test Discord bot
   # In Discord: /help

   # Test Linear integration
   # In Discord: /my-tasks

   # Check logs for authentication errors
   tail -f /opt/agentic-base/integration/logs/critical-security-*.log
   ```

6. **Audit security logs**:
   ```sql
   -- Check for unauthorized access
   SELECT * FROM auth_audit_log
   WHERE timestamp > datetime('now', '-24 hours')
   ORDER BY timestamp DESC;

   -- Check for failed MFA attempts
   SELECT * FROM mfa_challenges
   WHERE success = 0
     AND challenged_at > datetime('now', '-24 hours')
   ORDER BY challenged_at DESC;
   ```

7. **Notify stakeholders**:
   ```
   Subject: Security Incident - API Key Rotation Complete

   A security incident was detected involving potential compromise of API credentials.
   All affected credentials have been rotated and services are operational.

   Timeline:
   - Incident detected: YYYY-MM-DD HH:MM UTC
   - Credentials revoked: YYYY-MM-DD HH:MM UTC
   - New credentials deployed: YYYY-MM-DD HH:MM UTC
   - Services restored: YYYY-MM-DD HH:MM UTC

   Impact: Brief service interruption (~15 minutes)
   Data exposure: Under investigation

   Next steps: Post-incident review scheduled for YYYY-MM-DD
   ```

**Estimated Recovery Time**: 15-30 minutes

**Data Loss**: None

---

## Service Redundancy & Failover

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       Load Balancer                         │
│                  (HAProxy or NGINX)                        │
└──────────────┬────────────────────────┬─────────────────────┘
               │                        │
               ▼                        ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│   Primary Instance       │  │   Standby Instance       │
│   agentic-base-bot-01    │  │   agentic-base-bot-02    │
│                          │  │                          │
│   - Discord Bot          │  │   - Discord Bot (idle)   │
│   - Database (primary)   │  │   - Database (replica)   │
│   - Active workflows     │  │   - Health check only    │
└──────────────────────────┘  └──────────────────────────┘
               │                        │
               └────────┬───────────────┘
                        │
                        ▼
            ┌───────────────────────┐
            │   Shared Backup       │
            │   Storage (S3/GCS)    │
            └───────────────────────┘
```

### Failover Strategy

#### Automatic Failover

**Health Check Monitoring**:
- Primary instance health checked every 30 seconds
- If 3 consecutive health checks fail (90 seconds), trigger failover
- Standby instance promoted to primary automatically

**Health Check Endpoint**: `http://localhost:3000/health`

```javascript
// Health check implementation
app.get('/health', (req, res) => {
  const checks = {
    database: false,
    discord: false,
    uptime: process.uptime()
  };

  // Check database connection
  try {
    db.get('SELECT 1');
    checks.database = true;
  } catch (error) {
    // Database unreachable
  }

  // Check Discord connection
  checks.discord = client.isReady();

  // Return health status
  if (checks.database && checks.discord) {
    res.status(200).json({ status: 'healthy', checks });
  } else {
    res.status(503).json({ status: 'unhealthy', checks });
  }
});
```

**Failover Script**: `scripts/failover.sh`

```bash
#!/bin/bash
# Automatic failover script
# Location: scripts/failover.sh

set -e

PRIMARY_HOST="agentic-base-bot-01"
STANDBY_HOST="agentic-base-bot-02"
HEALTH_ENDPOINT="http://localhost:3000/health"

echo "🔄 Initiating failover from $PRIMARY_HOST to $STANDBY_HOST"

# 1. Verify primary is unhealthy
echo "1. Verifying primary instance health..."
if curl -f -s "$PRIMARY_HOST:3000/health" > /dev/null 2>&1; then
  echo "❌ Primary instance is healthy. Failover aborted."
  exit 1
fi

# 2. Stop primary instance
echo "2. Stopping primary instance..."
ssh "$PRIMARY_HOST" "cd /opt/agentic-base/integration && docker-compose down" || true

# 3. Sync database from backup
echo "3. Syncing latest database backup to standby..."
LATEST_BACKUP=$(aws s3 ls s3://agentic-base-backups/database/ | sort -r | head -n 1 | awk '{print $4}')
ssh "$STANDBY_HOST" "aws s3 cp s3://agentic-base-backups/database/$LATEST_BACKUP /tmp/ && gunzip -f /tmp/$LATEST_BACKUP && cp /tmp/${LATEST_BACKUP%.gz} /opt/agentic-base/integration/data/auth.db"

# 4. Promote standby to primary
echo "4. Promoting standby instance to primary..."
ssh "$STANDBY_HOST" "cd /opt/agentic-base/integration && docker-compose up -d"

# 5. Wait for standby to be ready
echo "5. Waiting for new primary to be ready..."
for i in {1..30}; do
  if curl -f -s "$STANDBY_HOST:3000/health" > /dev/null 2>&1; then
    echo "✅ Standby promoted to primary successfully"
    break
  fi
  sleep 2
done

# 6. Update load balancer
echo "6. Updating load balancer to route to new primary..."
# Update HAProxy/NGINX config to route traffic to standby

echo "✅ Failover complete. $STANDBY_HOST is now primary."
```

#### Manual Failover

**When to Use**:
- Planned maintenance on primary instance
- Performance degradation on primary
- Manual testing of failover procedures

**Steps**:
1. Announce maintenance window to team
2. Execute failover script: `bash scripts/failover.sh`
3. Verify standby is operational
4. Perform maintenance on original primary
5. Fail back to original primary (if desired)

### Database Replication

**Strategy**: Periodic sync from primary to standby (SQLite limitation: no real-time replication)

**Sync Script**: `scripts/sync-database-replica.sh`

```bash
#!/bin/bash
# Database replication sync script
# Location: scripts/sync-database-replica.sh

set -e

PRIMARY_HOST="agentic-base-bot-01"
STANDBY_HOST="agentic-base-bot-02"
DB_FILE="/opt/agentic-base/integration/data/auth.db"

# Sync database from primary to standby
echo "🔄 Syncing database from $PRIMARY_HOST to $STANDBY_HOST"

# Use rsync over SSH for efficient sync
rsync -avz --progress "$PRIMARY_HOST:$DB_FILE" "$STANDBY_HOST:$DB_FILE.new"

# Atomic replacement on standby
ssh "$STANDBY_HOST" "mv $DB_FILE.new $DB_FILE"

echo "✅ Database sync complete"
```

**Cron Schedule** (run every 15 minutes):
```cron
# Sync database replica every 15 minutes
*/15 * * * * /opt/agentic-base/integration/scripts/sync-database-replica.sh >> /var/log/agentic-base-replica-sync.log 2>&1
```

### Webhook Redundancy

**Challenge**: Discord bots use WebSocket connections (cannot have multiple active connections)

**Solution**: Active-standby pattern
- Primary instance maintains active Discord connection
- Standby instance remains idle (no Discord connection)
- On failover, standby connects to Discord

**Webhook Endpoints** (Linear, GitHub):
- Configure multiple webhook URLs (primary + standby)
- Both instances receive webhooks
- Primary processes webhooks, standby discards (unless primary fails)

---

## Disaster Scenarios

### Scenario 1: Database Corruption

**Symptoms**:
- Bot crashes on startup
- SQLite error: "database disk image is malformed"
- Cannot query database

**Root Causes**:
- Disk I/O error
- Filesystem corruption
- Improper shutdown
- Ransomware

**Recovery Procedure**: See [Database Recovery](#1-database-recovery)

**Prevention**:
- Enable SQLite WAL mode (write-ahead logging)
- Regular integrity checks: `PRAGMA integrity_check`
- Daily backups with verification
- Filesystem monitoring (SMART, disk health)

---

### Scenario 2: Configuration Corruption

**Symptoms**:
- Bot fails to start
- YAML parse error in logs
- Invalid configuration values

**Root Causes**:
- Manual edit error
- Automated config update bug
- Git merge conflict

**Recovery Procedure**: See [Configuration Recovery](#2-configuration-recovery)

**Prevention**:
- YAML schema validation on config load
- Git pre-commit hooks for YAML validation
- Configuration change approval workflow

---

### Scenario 3: Secrets Compromise

**Symptoms**:
- Unauthorized API usage
- Security alert from Discord/Linear/GitHub
- Unusual bot behavior

**Root Causes**:
- Leaked to public repository
- Compromised server access
- Social engineering

**Recovery Procedure**: See [Secrets Compromise Recovery](#4-secrets-compromise-recovery)

**Prevention**:
- Never commit secrets to Git
- Use secrets manager (AWS Secrets Manager, Google Secret Manager)
- Rotate secrets every 90 days (automated)
- Monitor for leaked secrets (GitHub secret scanning, GitGuardian)

---

### Scenario 4: Complete Infrastructure Loss

**Symptoms**:
- Server unreachable
- Data center outage
- Cloud provider outage

**Root Causes**:
- Hardware failure
- Natural disaster
- Cyber attack (DDoS, ransomware)
- Cloud provider outage

**Recovery Procedure**: See [Complete System Recovery](#3-complete-system-recovery)

**Prevention**:
- Multi-region deployment
- Geo-redundant backups (AWS S3 + GCS)
- Infrastructure as Code (Terraform, CloudFormation)
- Regular disaster recovery drills

---

### Scenario 5: Cascading Service Failure

**Symptoms**:
- Discord API rate limit exceeded
- Linear API timeout
- Multiple services failing simultaneously

**Root Causes**:
- External API outage
- Network connectivity issues
- Bot bug causing infinite loop

**Recovery Procedure**:

1. **Identify failing services**:
   ```bash
   # Check service status
   curl -s http://localhost:3000/health | jq

   # Check external service status
   curl -s https://discordstatus.com/api/v2/status.json | jq
   curl -s https://linear.app/api/status | jq
   ```

2. **Enable circuit breaker** (if not already enabled):
   ```javascript
   // Circuit breaker automatically stops retries to failing services
   // Check circuit breaker status in logs
   grep "Circuit breaker" /opt/agentic-base/integration/logs/*.log
   ```

3. **Temporarily disable failing integrations**:
   ```yaml
   # Edit config/linear-sync.yml
   enabled: false
   ```

4. **Wait for external services to recover**:
   - Monitor status pages
   - Check Twitter for service announcements
   - Subscribe to status notifications

5. **Re-enable integrations after recovery**:
   ```yaml
   # Edit config/linear-sync.yml
   enabled: true
   ```

6. **Restart bot**:
   ```bash
   docker-compose restart
   ```

**Prevention**:
- Circuit breaker pattern (implemented in HIGH-004)
- Rate limiting and backoff (implemented in HIGH-003)
- Health checks for external services
- Graceful degradation (bot works without Linear/GitHub)

---

## Testing & Verification

### Backup Verification

**Automated Verification** (runs after each backup):

```bash
#!/bin/bash
# Backup verification script
# Location: scripts/verify-backup.sh

set -e

BACKUP_FILE="$1"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Backup file not found: $BACKUP_FILE"
  exit 1
fi

# 1. Verify file is not empty
if [ ! -s "$BACKUP_FILE" ]; then
  echo "❌ Backup file is empty"
  exit 1
fi

# 2. Verify checksum
if [ -f "$BACKUP_FILE.sha256" ]; then
  sha256sum -c "$BACKUP_FILE.sha256" || {
    echo "❌ Checksum verification failed"
    exit 1
  }
fi

# 3. Test decompression (if gzipped)
if [[ "$BACKUP_FILE" == *.gz ]]; then
  gzip -t "$BACKUP_FILE" || {
    echo "❌ Gzip integrity check failed"
    exit 1
  }
fi

# 4. For database backups, verify SQLite integrity
if [[ "$BACKUP_FILE" == *auth-db*.sqlite* ]]; then
  # Decompress to temp file
  TEMP_DB=$(mktemp)
  gunzip -c "$BACKUP_FILE" > "$TEMP_DB"

  # Run SQLite integrity check
  sqlite3 "$TEMP_DB" "PRAGMA integrity_check;" || {
    echo "❌ SQLite integrity check failed"
    rm -f "$TEMP_DB"
    exit 1
  }

  # Verify critical tables exist
  TABLE_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
  if [ "$TABLE_COUNT" -lt 6 ]; then
    echo "❌ Missing tables in database backup (expected 6, found $TABLE_COUNT)"
    rm -f "$TEMP_DB"
    exit 1
  fi

  rm -f "$TEMP_DB"
fi

echo "✅ Backup verified successfully: $BACKUP_FILE"
```

**Manual Verification Checklist** (quarterly):

- [ ] Restore latest database backup to test environment
- [ ] Verify all tables and indexes present
- [ ] Query sample data to ensure correctness
- [ ] Restore configuration files from Git
- [ ] Decrypt secrets backup and verify contents
- [ ] Restore complete system to test server
- [ ] Execute full recovery procedure end-to-end

### Disaster Recovery Drills

**Schedule**: Quarterly (every 3 months)

**Drill Types**:

1. **Tabletop Exercise** (2 hours):
   - Walkthrough of recovery procedures
   - Role assignments and responsibilities
   - Q&A and procedure clarifications

2. **Partial Recovery Drill** (4 hours):
   - Restore database to test environment
   - Restore configurations
   - Verify bot functionality

3. **Full Recovery Drill** (8 hours):
   - Simulate complete infrastructure loss
   - Provision new server from scratch
   - Restore all components from backups
   - Verify full functionality

**Drill Checklist**:

```markdown
# Disaster Recovery Drill - YYYY-MM-DD

## Participants
- [ ] Infrastructure Lead: ___________
- [ ] Security Lead: ___________
- [ ] On-call Engineer: ___________

## Scenario
Simulate: [Database corruption | Server failure | Secrets compromise | Complete outage]

## Pre-Drill
- [ ] Review DRP document
- [ ] Verify backup access (S3, GCS credentials)
- [ ] Prepare test environment
- [ ] Notify team of drill (no user impact)

## Drill Execution
Start Time: _________
End Time: _________

- [ ] Step 1: ___________
- [ ] Step 2: ___________
- [ ] Step 3: ___________
...

## Post-Drill
- [ ] Document lessons learned
- [ ] Update DRP with improvements
- [ ] Track action items
- [ ] Schedule next drill

## Metrics
- Time to recovery: _______ (Target: < 2 hours)
- Data loss: _______ (Target: < 24 hours)
- Issues encountered: _______

## Action Items
1. _______________________________
2. _______________________________
3. _______________________________
```

---

## Monitoring & Alerting

### Backup Monitoring

**Metrics to Monitor**:
- Backup success/failure rate
- Backup size and duration
- Time since last successful backup
- Backup storage usage

**Alerting Rules**:

```yaml
# Example monitoring rules (Prometheus/Grafana)
- alert: BackupFailed
  expr: agentic_base_backup_success == 0
  for: 5m
  annotations:
    summary: "Backup failed for {{ $labels.component }}"
    description: "Backup for {{ $labels.component }} has failed."

- alert: BackupOverdue
  expr: time() - agentic_base_backup_last_success_timestamp > 86400
  for: 5m
  annotations:
    summary: "Backup overdue for {{ $labels.component }}"
    description: "No successful backup for {{ $labels.component }} in the last 24 hours."

- alert: BackupStorageFull
  expr: agentic_base_backup_storage_usage_percent > 90
  for: 5m
  annotations:
    summary: "Backup storage nearly full"
    description: "Backup storage is {{ $value }}% full."
```

**Notification Channels**:
- Email: infrastructure-team@example.com
- Slack: #infrastructure-alerts
- PagerDuty: On-call rotation

### Service Health Monitoring

**Health Check Monitoring**:
- HTTP health endpoint: `http://localhost:3000/health`
- Discord bot status (heartbeat)
- Database query response time
- External API connectivity

**Alerting Rules**:

```yaml
- alert: BotUnhealthy
  expr: agentic_base_health_status == 0
  for: 2m
  annotations:
    summary: "Bot health check failing"
    description: "Bot has been unhealthy for 2 minutes."

- alert: DatabaseSlow
  expr: agentic_base_database_query_duration_seconds > 0.5
  for: 5m
  annotations:
    summary: "Database queries slow"
    description: "Database query duration is {{ $value }}s (threshold: 0.5s)."
```

---

## Roles & Responsibilities

### Disaster Recovery Team

| Role | Responsibilities | Contact |
|------|------------------|---------|
| **Incident Commander** | Declare disaster, coordinate recovery, communicate with stakeholders | |
| **Infrastructure Lead** | Execute recovery procedures, provision resources, restore services | |
| **Security Lead** | Assess security impact, rotate compromised credentials, audit logs | |
| **Database Administrator** | Restore database, verify integrity, handle data recovery | |
| **Communications Lead** | Notify stakeholders, provide status updates, manage external comms | |

### Escalation Path

```
1. On-call Engineer (detects issue)
   ↓
2. Infrastructure Lead (assesses severity)
   ↓
3. Incident Commander (declares disaster if RTO/RPO at risk)
   ↓
4. Full DR Team (executes recovery)
   ↓
5. Leadership (notified, decision-making for major outages)
```

---

## Contact Information

### Emergency Contacts

| Role | Name | Phone | Email |
|------|------|-------|-------|
| Incident Commander | | | |
| Infrastructure Lead | | | |
| Security Lead | | | |
| Database Administrator | | | |
| On-call Rotation | | | PagerDuty |

### Vendor Support

| Service | Support Contact | SLA |
|---------|----------------|-----|
| AWS | support.aws.amazon.com | Business: 1 hour response |
| Google Cloud | support.google.com/cloud | Standard: 4 hour response |
| Discord | support.discord.com | Developer: 48 hour response |
| Linear | help.linear.app | Email: 24 hour response |
| GitHub | support.github.com | Premium: 1 hour response |

---

## Document Maintenance

### Review Schedule

- **Monthly**: Review backup logs and verify storage
- **Quarterly**: Conduct disaster recovery drill and update document
- **Annually**: Comprehensive review and leadership approval

### Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-08 | Security Team | Initial version (HIGH-009 implementation) |

### Approval

**Approved By**: [Infrastructure Lead Name]
**Date**: 2025-12-08
**Next Review**: 2026-03-08 (Q1 2026)

---

## Related Documents

- **HIGH-001 Implementation**: Discord security and access controls (`docs/DISCORD-SECURITY.md`)
- **HIGH-005 Implementation**: Database-backed authorization (`docs/HIGH-005-IMPLEMENTATION.md`)
- **CRITICAL-003**: Secrets management (`docs/audits/2025-12-08/CRITICAL-003-REMEDIATION.md`)
- **HIGH-004 Implementation**: Error handling and resilience (`docs/HIGH-004-IMPLEMENTATION.md`)
- **Infrastructure Architecture**: System design and deployment (`docs/devrel-integration-architecture.md`)

---

**Document Version**: 1.0
**Last Updated**: December 8, 2025
**Maintained By**: Infrastructure & Security Team
**Contact**: infrastructure@agentic-base.com
