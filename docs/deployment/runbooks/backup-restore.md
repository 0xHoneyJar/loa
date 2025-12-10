# Backup and Restore Procedures

**Document Version:** 1.0
**Last Updated:** 2025-12-09
**Owner:** DevOps Team
**Review Frequency:** Quarterly

## Table of Contents

1. [Overview](#overview)
2. [Automated Daily Backups](#automated-daily-backups)
3. [Manual Backup Procedures](#manual-backup-procedures)
4. [Restore from Backup](#restore-from-backup)
5. [Testing Restore (Quarterly Requirement)](#testing-restore-quarterly-requirement)
6. [Backup Verification](#backup-verification)
7. [Off-Site Backup Storage](#off-site-backup-storage)
8. [Retention Policy](#retention-policy)
9. [Emergency Recovery](#emergency-recovery)

---

## Overview

This document describes backup and restore procedures for the DevRel Integration application running in production.

### What is Backed Up

The backup strategy covers the following components:

1. **Application Configuration** (`/opt/devrel-integration/config`)
   - Bot configuration files
   - Integration settings
   - Feature flags

2. **Application Data** (`/opt/devrel-integration/data`)
   - User preferences database (`auth.db`)
   - Local cache and state
   - Application-generated data

3. **Secrets** (`/opt/devrel-integration/secrets`)
   - Environment files (`.env.production`, `.env.staging`)
   - API tokens and credentials
   - **CRITICAL: Always encrypt before backup**

4. **PM2 Configuration** (`ecosystem.config.js`)
   - Process management configuration
   - Environment settings

5. **systemd Service Files** (`/etc/systemd/system/devrel-integration.service`)
   - Service configuration
   - System integration

6. **nginx Configuration** (if applicable)
   - Reverse proxy configuration
   - SSL/TLS certificates

### What is NOT Backed Up

- Application source code (versioned in Git)
- Node.js dependencies (`node_modules` - reinstall via `npm install`)
- Docker images (rebuild from Dockerfile)
- Operating system configuration (documented in setup scripts)
- Log files (retain separately with log rotation)

### Backup Frequency

- **Production:** Daily automated backups at 2:00 AM UTC
- **Staging:** Weekly automated backups
- **Development:** Manual backups as needed

### Recovery Time Objective (RTO)

- **Target RTO:** 4 hours (from incident to full service restoration)
- **Target RPO:** 24 hours (maximum data loss: 1 day)

---

## Automated Daily Backups

### Setup Automated Backup Cron Job

1. **Create backup script:**

```bash
sudo mkdir -p /opt/devrel-integration/scripts
sudo nano /opt/devrel-integration/scripts/automated-backup.sh
```

2. **Add the following content:**

```bash
#!/bin/bash
# ============================================================================
# Automated Backup Script - DevRel Integration
# ============================================================================
# Purpose: Daily automated backup of application data, config, and secrets
# Schedule: Run daily at 2:00 AM UTC via cron
# ============================================================================

set -euo pipefail

# Configuration
BACKUP_DATE=$(date +%Y%m%d)
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_ROOT="/opt/backups/devrel-integration"
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_DATE}"
APP_DIR="/opt/devrel-integration"
LOG_FILE="/var/log/devrel/backup.log"

# GPG recipient for encryption (configure your GPG key email)
GPG_RECIPIENT="admin@your-company.com"

# S3 bucket for off-site storage (configure if using AWS)
S3_BUCKET="s3://your-company-backups/devrel-integration"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    exit 1
}

log "=========================================="
log "Starting automated backup"
log "=========================================="

# Create backup directory
mkdir -p "${BACKUP_DIR}" || error_exit "Failed to create backup directory"
log "Backup directory: ${BACKUP_DIR}"

# 1. Backup configuration (non-sensitive)
log "Backing up configuration..."
if [ -d "${APP_DIR}/config" ]; then
    tar -czf "${BACKUP_DIR}/config.tar.gz" -C "${APP_DIR}" config || error_exit "Failed to backup config"
    log "Config backup: $(du -h ${BACKUP_DIR}/config.tar.gz | cut -f1)"
else
    log "WARNING: Config directory not found, skipping"
fi

# 2. Backup data (database, user preferences)
log "Backing up data directory..."
if [ -d "${APP_DIR}/data" ]; then
    # If SQLite database exists, use proper backup method
    if [ -f "${APP_DIR}/data/auth.db" ]; then
        log "Backing up SQLite database with proper locking..."
        sqlite3 "${APP_DIR}/data/auth.db" ".backup '${BACKUP_DIR}/auth.db.backup'" 2>/dev/null || \
            log "WARNING: SQLite backup command failed, using file copy as fallback"
    fi

    tar -czf "${BACKUP_DIR}/data.tar.gz" -C "${APP_DIR}" data || error_exit "Failed to backup data"
    log "Data backup: $(du -h ${BACKUP_DIR}/data.tar.gz | cut -f1)"
else
    log "WARNING: Data directory not found, skipping"
fi

# 3. Backup secrets (ENCRYPTED - CRITICAL FOR SECURITY)
log "Backing up secrets (encrypted)..."
if [ -d "${APP_DIR}/secrets" ]; then
    # Check if GPG key exists
    if gpg --list-keys "${GPG_RECIPIENT}" &>/dev/null; then
        tar -czf - -C "${APP_DIR}" secrets | \
            gpg --encrypt --armor --recipient "${GPG_RECIPIENT}" \
                --output "${BACKUP_DIR}/secrets.tar.gz.gpg" || error_exit "Failed to backup secrets"
        log "Secrets backup (encrypted): $(du -h ${BACKUP_DIR}/secrets.tar.gz.gpg | cut -f1)"
    else
        log "ERROR: GPG key not found for ${GPG_RECIPIENT}"
        log "Secrets will NOT be backed up (security risk if unencrypted)"
        error_exit "Configure GPG key before running automated backups"
    fi
else
    log "WARNING: Secrets directory not found, skipping"
fi

# 4. Backup PM2 ecosystem config
log "Backing up PM2 configuration..."
if [ -f "${APP_DIR}/ecosystem.config.js" ]; then
    cp "${APP_DIR}/ecosystem.config.js" "${BACKUP_DIR}/ecosystem.config.js" || log "WARNING: Failed to backup PM2 config"
else
    log "WARNING: PM2 config not found, skipping"
fi

# 5. Backup systemd service file
log "Backing up systemd service..."
if [ -f "/etc/systemd/system/devrel-integration.service" ]; then
    cp "/etc/systemd/system/devrel-integration.service" "${BACKUP_DIR}/devrel-integration.service" || log "WARNING: Failed to backup systemd service"
else
    log "WARNING: systemd service not found, skipping"
fi

# 6. Backup nginx configuration (if exists)
log "Backing up nginx configuration..."
if [ -d "/etc/nginx/sites-available" ]; then
    if [ -f "/etc/nginx/sites-available/devrel-integration" ]; then
        cp "/etc/nginx/sites-available/devrel-integration" "${BACKUP_DIR}/nginx-devrel-integration.conf" || log "WARNING: Failed to backup nginx config"
    fi
fi

# 7. Create backup manifest
log "Creating backup manifest..."
cat > "${BACKUP_DIR}/MANIFEST.txt" <<EOF
Backup Manifest
===============

Date: ${BACKUP_TIMESTAMP}
Server: $(hostname)
Application: DevRel Integration

Backup Contents:
- config.tar.gz: Application configuration
- data.tar.gz: Database and user data
- secrets.tar.gz.gpg: Encrypted secrets (API tokens, credentials)
- ecosystem.config.js: PM2 process manager config
- devrel-integration.service: systemd service file
- nginx-devrel-integration.conf: nginx reverse proxy config (if applicable)

Backup Size: $(du -sh ${BACKUP_DIR} | cut -f1)

To restore from this backup:
1. See docs/deployment/runbooks/backup-restore.md
2. Decrypt secrets: gpg --decrypt secrets.tar.gz.gpg | tar -xzf -
3. Extract archives: tar -xzf config.tar.gz && tar -xzf data.tar.gz
4. Restore to /opt/devrel-integration/
5. Set proper ownership: chown -R devrel:devrel /opt/devrel-integration
6. Restart services
EOF

log "Backup manifest created"

# 8. Verify backup integrity
log "Verifying backup integrity..."
tar -tzf "${BACKUP_DIR}/config.tar.gz" > /dev/null || error_exit "Config backup is corrupted"
tar -tzf "${BACKUP_DIR}/data.tar.gz" > /dev/null || error_exit "Data backup is corrupted"
gpg --list-packets "${BACKUP_DIR}/secrets.tar.gz.gpg" > /dev/null 2>&1 || error_exit "Secrets backup is corrupted"
log "Backup integrity verified"

# 9. Copy to off-site storage (optional - configure AWS CLI first)
if command -v aws &> /dev/null; then
    log "Copying backup to off-site storage..."
    aws s3 sync "${BACKUP_ROOT}" "${S3_BUCKET}" \
        --storage-class STANDARD_IA \
        --sse AES256 \
        --exclude "*" \
        --include "${BACKUP_DATE}/*" || log "WARNING: Failed to sync to S3"
    log "Off-site backup completed"
else
    log "WARNING: AWS CLI not found, skipping off-site backup"
    log "Configure AWS CLI for disaster recovery protection"
fi

# 10. Retention - Keep last 30 days, delete older
log "Applying retention policy (30 days)..."
find "${BACKUP_ROOT}" -type d -name "20*" -mtime +30 -exec rm -rf {} \; 2>/dev/null || true
log "Old backups cleaned up"

# 11. Calculate total backup size
TOTAL_SIZE=$(du -sh "${BACKUP_ROOT}" | cut -f1)
log "Total backup storage used: ${TOTAL_SIZE}"

log "=========================================="
log "Automated backup completed successfully"
log "=========================================="
```

3. **Make script executable:**

```bash
sudo chmod +x /opt/devrel-integration/scripts/automated-backup.sh
```

4. **Configure GPG encryption:**

```bash
# Generate GPG key for backups (if not exists)
gpg --gen-key
# Follow prompts:
#   - Real name: DevRel Backup
#   - Email: admin@your-company.com
#   - Passphrase: Use strong passphrase (store in password manager!)

# Verify key created
gpg --list-keys admin@your-company.com

# Update script with your GPG recipient email
sudo nano /opt/devrel-integration/scripts/automated-backup.sh
# Change: GPG_RECIPIENT="admin@your-company.com"
```

5. **Test backup script manually:**

```bash
sudo /opt/devrel-integration/scripts/automated-backup.sh
# Check output for errors
# Verify backup created: ls -lh /opt/backups/devrel-integration/$(date +%Y%m%d)/
```

6. **Schedule with cron:**

```bash
# Edit crontab for root
sudo crontab -e

# Add daily backup at 2:00 AM UTC
0 2 * * * /opt/devrel-integration/scripts/automated-backup.sh >> /var/log/devrel/backup.log 2>&1
```

7. **Verify cron job:**

```bash
sudo crontab -l | grep automated-backup
```

---

## Manual Backup Procedures

### Before Deployment or Major Changes

1. **Stop application (optional, but recommended for consistency):**

```bash
pm2 stop devrel-bot
# OR
sudo systemctl stop devrel-integration
```

2. **Create timestamped backup:**

```bash
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
sudo mkdir -p /opt/backups/devrel-integration/manual_${BACKUP_DATE}
BACKUP_DIR="/opt/backups/devrel-integration/manual_${BACKUP_DATE}"
```

3. **Backup all components:**

```bash
# Configuration
sudo tar -czf "${BACKUP_DIR}/config.tar.gz" -C /opt/devrel-integration config

# Data
sudo tar -czf "${BACKUP_DIR}/data.tar.gz" -C /opt/devrel-integration data

# Secrets (encrypted!)
sudo tar -czf - -C /opt/devrel-integration secrets | \
    gpg --encrypt --armor --recipient admin@your-company.com \
    --output "${BACKUP_DIR}/secrets.tar.gz.gpg"

# PM2 config
sudo cp /opt/devrel-integration/ecosystem.config.js "${BACKUP_DIR}/"

# systemd service
sudo cp /etc/systemd/system/devrel-integration.service "${BACKUP_DIR}/"
```

4. **Create backup label:**

```bash
echo "Manual backup before [REASON]" | sudo tee "${BACKUP_DIR}/REASON.txt"
echo "Created: $(date)" | sudo tee -a "${BACKUP_DIR}/REASON.txt"
echo "By: ${USER}" | sudo tee -a "${BACKUP_DIR}/REASON.txt"
```

5. **Restart application:**

```bash
pm2 start devrel-bot
# OR
sudo systemctl start devrel-integration
```

---

## Restore from Backup

### Full Server Recovery

Use this procedure when recovering from complete server failure, data corruption, or disaster.

#### Prerequisites

- New server provisioned (bare metal or VPS)
- Server setup completed (see `docs/deployment/server-setup-guide.md`)
- Dependencies installed (Node.js, PM2, nginx)
- Access to backup files (local or S3)

#### Step 1: Prepare Server

```bash
# Run initial setup (if new server)
sudo ./docs/deployment/scripts/01-initial-setup.sh
sudo ./docs/deployment/scripts/02-security-hardening.sh
sudo ./docs/deployment/scripts/03-install-dependencies.sh

# Verify application directory exists
ls -ld /opt/devrel-integration
```

#### Step 2: Download Backup

**From local backup storage:**

```bash
# If backups are on same server (different disk/partition)
sudo cp -r /opt/backups/devrel-integration/YYYYMMDD /tmp/restore/
```

**From S3 (if using off-site backup):**

```bash
# Install AWS CLI if not present
sudo apt-get install awscli -y

# Configure AWS credentials
aws configure

# Download latest backup
LATEST_BACKUP=$(aws s3 ls s3://your-company-backups/devrel-integration/ | sort | tail -n 1 | awk '{print $2}')
aws s3 sync "s3://your-company-backups/devrel-integration/${LATEST_BACKUP}" /tmp/restore/
```

#### Step 3: Decrypt and Extract Secrets

**CRITICAL: Secrets must be decrypted first**

```bash
# Decrypt secrets backup
gpg --decrypt /tmp/restore/secrets.tar.gz.gpg | sudo tar -xzf - -C /opt/devrel-integration/

# Verify secrets extracted
ls -l /opt/devrel-integration/secrets/

# Set proper permissions (owner-only read/write)
sudo chmod 600 /opt/devrel-integration/secrets/.env.*
```

#### Step 4: Restore Configuration and Data

```bash
# Extract configuration
sudo tar -xzf /tmp/restore/config.tar.gz -C /opt/devrel-integration/

# Extract data (database, user preferences)
sudo tar -xzf /tmp/restore/data.tar.gz -C /opt/devrel-integration/

# If SQLite database backup exists separately
if [ -f /tmp/restore/auth.db.backup ]; then
    sudo cp /tmp/restore/auth.db.backup /opt/devrel-integration/data/auth.db
fi
```

#### Step 5: Restore System Configuration

```bash
# Restore PM2 ecosystem config
sudo cp /tmp/restore/ecosystem.config.js /opt/devrel-integration/

# Restore systemd service
sudo cp /tmp/restore/devrel-integration.service /etc/systemd/system/
sudo systemctl daemon-reload

# Restore nginx config (if applicable)
if [ -f /tmp/restore/nginx-devrel-integration.conf ]; then
    sudo cp /tmp/restore/nginx-devrel-integration.conf /etc/nginx/sites-available/devrel-integration
    sudo ln -sf /etc/nginx/sites-available/devrel-integration /etc/nginx/sites-enabled/
    sudo nginx -t  # Test configuration
    sudo systemctl reload nginx
fi
```

#### Step 6: Fix Ownership and Permissions

```bash
# Set ownership to application user
sudo chown -R devrel:devrel /opt/devrel-integration

# Set directory permissions
sudo chmod 750 /opt/devrel-integration
sudo chmod 700 /opt/devrel-integration/secrets
sudo chmod 750 /opt/devrel-integration/logs
sudo chmod 750 /opt/devrel-integration/data
```

#### Step 7: Install Application Dependencies

```bash
# Navigate to application directory
cd /opt/devrel-integration

# Install npm dependencies (as devrel user)
sudo -u devrel npm install --production

# Build TypeScript (if needed)
sudo -u devrel npm run build
```

#### Step 8: Start Application

```bash
# Start with PM2
sudo -u devrel pm2 start /opt/devrel-integration/ecosystem.config.js --env production

# OR start with systemd
sudo systemctl enable devrel-integration
sudo systemctl start devrel-integration
```

#### Step 9: Verify Restoration

```bash
# Check service status
pm2 status
# OR
sudo systemctl status devrel-integration

# Check health endpoint
curl http://localhost:3000/health
# Expected: {"status":"healthy","uptime":...}

# Check logs for errors
pm2 logs devrel-bot --lines 50
# OR
sudo journalctl -u devrel-integration -n 50

# Verify Discord connection
pm2 logs devrel-bot | grep -i "discord connected"

# Verify Linear integration
pm2 logs devrel-bot | grep -i "linear"
```

#### Step 10: Post-Recovery Validation

```bash
# Test Discord bot
# - Send a test command in Discord
# - Verify bot responds

# Test Linear webhook
# - Create a test issue in Linear
# - Verify Discord notification

# Check metrics endpoint
curl http://localhost:3000/metrics
```

---

## Testing Restore (Quarterly Requirement)

**MANDATORY: Test restore procedures every quarter (90 days)**

### Purpose

- Verify backups are valid and not corrupted
- Practice restore procedures before emergency
- Identify gaps in documentation
- Update procedures based on changes

### Test Procedure

1. **Provision test server** (separate from production)

```bash
# Use staging server or temporary VM
# DO NOT test on production!
```

2. **Select random backup** (not most recent - test older backups)

```bash
# List backups
ls -lt /opt/backups/devrel-integration/

# Select backup from 2-3 weeks ago
BACKUP_DATE="20251120"  # Example
```

3. **Follow full restore procedure** (documented above)

4. **Document results:**

```bash
# Create test report
cat > /tmp/restore-test-$(date +%Y%m%d).txt <<EOF
Restore Test Report
===================

Date: $(date)
Tester: ${USER}
Backup Tested: ${BACKUP_DATE}

Results:
- [ ] Backup integrity verified
- [ ] Secrets decrypted successfully
- [ ] Configuration restored
- [ ] Data restored (database accessible)
- [ ] Application started successfully
- [ ] Health checks passing
- [ ] Discord connection working
- [ ] Linear integration working

Issues Found:
[List any problems encountered]

Time to Restore:
Start: [TIME]
End: [TIME]
Total: [X hours]

Recommendations:
[Any improvements to procedures or documentation]

Next Test Due: $(date -d "+90 days" +%Y-%m-%d)
EOF
```

5. **Update procedures** based on findings

6. **Schedule next test** (90 days from now)

```bash
# Add to calendar/task tracker
# Set reminder for next quarterly test
```

---

## Backup Verification

### Daily Automated Verification

The automated backup script includes basic verification:
- Tar archive integrity check (`tar -tzf`)
- GPG encryption validation
- File size reasonableness check

### Weekly Manual Spot Checks

1. **Check backup logs:**

```bash
tail -50 /var/log/devrel/backup.log
# Look for errors or warnings
```

2. **Verify recent backups exist:**

```bash
ls -lh /opt/backups/devrel-integration/ | tail -10
# Should see daily backups
```

3. **Check backup sizes:**

```bash
du -sh /opt/backups/devrel-integration/20*/ | tail -7
# Sizes should be consistent (within 10-20%)
```

4. **Test secret decryption:**

```bash
# Pick random backup
RANDOM_BACKUP=$(ls /opt/backups/devrel-integration/ | shuf -n 1)

# Test decryption (don't extract)
gpg --list-packets "/opt/backups/devrel-integration/${RANDOM_BACKUP}/secrets.tar.gz.gpg"
# Should show encryption metadata without errors
```

---

## Off-Site Backup Storage

### AWS S3 Configuration

1. **Install AWS CLI:**

```bash
sudo apt-get install awscli -y
```

2. **Configure credentials:**

```bash
aws configure
# Enter:
#   AWS Access Key ID: [Your key]
#   AWS Secret Access Key: [Your secret]
#   Default region: us-east-1 (or your region)
#   Default output format: json
```

3. **Create S3 bucket:**

```bash
aws s3 mb s3://your-company-backups-devrel \
    --region us-east-1

# Enable versioning (protect against accidental deletion)
aws s3api put-bucket-versioning \
    --bucket your-company-backups-devrel \
    --versioning-configuration Status=Enabled

# Enable encryption at rest
aws s3api put-bucket-encryption \
    --bucket your-company-backups-devrel \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
```

4. **Update backup script with S3 bucket name**

5. **Test S3 sync:**

```bash
# Manual sync to verify credentials
aws s3 sync /opt/backups/devrel-integration/ \
    s3://your-company-backups-devrel/ \
    --storage-class STANDARD_IA \
    --sse AES256
```

### Alternative: rsync to Remote Server

```bash
# Configure SSH key-based authentication to backup server
ssh-keygen -t ed25519 -f /root/.ssh/backup_key

# Copy public key to backup server
ssh-copy-id -i /root/.ssh/backup_key.pub backup@backup-server.com

# Add to backup script:
rsync -avz -e "ssh -i /root/.ssh/backup_key" \
    /opt/backups/devrel-integration/ \
    backup@backup-server.com:/backups/devrel-integration/
```

---

## Retention Policy

### Backup Retention Schedule

- **Daily backups:** Keep for 30 days
- **Weekly backups:** Keep first backup of week for 90 days
- **Monthly backups:** Keep first backup of month for 1 year
- **Yearly backups:** Keep first backup of year for 7 years (compliance)

### Implementation

The automated backup script includes 30-day retention. For longer retention:

```bash
# Create monthly backup preservation script
sudo nano /opt/devrel-integration/scripts/preserve-monthly-backup.sh
```

```bash
#!/bin/bash
# Preserve first backup of month
set -euo pipefail

FIRST_OF_MONTH=$(date +%Y%m01)
BACKUP_DIR="/opt/backups/devrel-integration/${FIRST_OF_MONTH}"
PRESERVE_DIR="/opt/backups/devrel-integration/monthly"

if [ -d "${BACKUP_DIR}" ]; then
    mkdir -p "${PRESERVE_DIR}"
    cp -r "${BACKUP_DIR}" "${PRESERVE_DIR}/"
    echo "Preserved monthly backup: ${FIRST_OF_MONTH}"
fi
```

Schedule with cron (1st of each month):

```bash
sudo crontab -e
# Add:
0 3 1 * * /opt/devrel-integration/scripts/preserve-monthly-backup.sh
```

---

## Emergency Recovery

### Rapid Recovery (Service Down)

If service is down but server is intact:

```bash
# 1. Check service status
pm2 status
sudo systemctl status devrel-integration

# 2. Try restart
pm2 restart devrel-bot
sudo systemctl restart devrel-integration

# 3. If restart fails, restore from last backup
LATEST=$(ls -t /opt/backups/devrel-integration/ | head -1)
cd /tmp && tar -xzf "/opt/backups/devrel-integration/${LATEST}/data.tar.gz"
sudo cp -r data/* /opt/devrel-integration/data/
sudo chown -R devrel:devrel /opt/devrel-integration/data/
pm2 restart devrel-bot

# 4. Verify recovery
curl http://localhost:3000/health
```

### Data Corruption Recovery

If database is corrupted:

```bash
# 1. Stop application
pm2 stop devrel-bot

# 2. Backup corrupted database
sudo cp /opt/devrel-integration/data/auth.db /tmp/corrupted_db_$(date +%Y%m%d).db

# 3. Restore from last known good backup
LATEST=$(ls -t /opt/backups/devrel-integration/ | head -1)
sudo tar -xzf "/opt/backups/devrel-integration/${LATEST}/data.tar.gz" -C /tmp/
sudo cp /tmp/data/auth.db /opt/devrel-integration/data/auth.db
sudo chown devrel:devrel /opt/devrel-integration/data/auth.db

# 4. Restart and verify
pm2 restart devrel-bot
pm2 logs devrel-bot --lines 50
```

### Complete Disaster (Server Loss)

Follow [Full Server Recovery](#full-server-recovery) procedure above.

---

## Backup Security

### Encryption Requirements

- **Secrets:** ALWAYS encrypt (GPG with strong passphrase)
- **Data:** Encrypt if contains PII or sensitive information
- **Configuration:** Encryption recommended (may contain sensitive paths)
- **Off-site backups:** Always encrypted in transit (S3 SSE, HTTPS)

### Access Control

- Backup directory: `chmod 700` (root only)
- Backup files: `chmod 600` (root only)
- GPG private key: `chmod 600` and passphrase-protected
- S3 bucket: IAM policy restricting access to backup user only

### Backup Integrity

- GPG signatures verify authenticity
- SHA-256 checksums for each backup
- Test restore quarterly to verify integrity

---

## Troubleshooting

### GPG Decryption Fails

**Error:** `gpg: decryption failed: No secret key`

**Solution:**
```bash
# Import private key (from secure storage)
gpg --import /path/to/private-key.asc

# Or restore from backup server
```

### Backup Script Fails with Permission Denied

**Error:** `tar: Cannot open: Permission denied`

**Solution:**
```bash
# Run backup script as root
sudo /opt/devrel-integration/scripts/automated-backup.sh

# Or fix cron to run as root
sudo crontab -e  # Edit root's crontab, not user's
```

### S3 Sync Fails

**Error:** `Unable to locate credentials`

**Solution:**
```bash
# Configure AWS credentials
sudo aws configure

# Or create IAM role for EC2 instance
```

### Database Restore Fails

**Error:** `Error: database disk image is malformed`

**Solution:**
```bash
# Try SQLite recovery
sqlite3 corrupted.db ".recover" | sqlite3 recovered.db

# Or restore from older backup
# Backups are kept for 30 days - try yesterday's backup
```

---

## Backup Checklist

### Daily (Automated)

- [ ] Automated backup runs successfully
- [ ] Backup integrity verified
- [ ] Off-site sync completed (if configured)
- [ ] Backup logs checked for errors

### Weekly (Manual)

- [ ] Spot check recent backups exist
- [ ] Verify backup sizes are consistent
- [ ] Test GPG decryption on random backup
- [ ] Review backup logs for warnings

### Monthly (Scheduled)

- [ ] Preserve first-of-month backup
- [ ] Review disk space usage
- [ ] Verify off-site backups accessible
- [ ] Update backup documentation if needed

### Quarterly (Mandatory)

- [ ] **Perform full restore test** on staging server
- [ ] Document restore test results
- [ ] Update procedures based on findings
- [ ] Schedule next quarterly test

---

## Contact Information

**Backup Issues:**
- On-Call Engineer: [Phone/Pagerduty]
- DevOps Team: [Email/Slack]

**Disaster Recovery:**
- Incident Commander: [Phone]
- CTO: [Phone]

---

**End of Backup and Restore Procedures**

*Next Review Due: [DATE + 90 days]*
