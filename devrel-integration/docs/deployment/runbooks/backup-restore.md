# Backup & Restore Runbook

> Procedures for backing up and restoring Onomancer Bot data

---

## What Gets Backed Up

| Data | Location | Frequency | Retention |
|------|----------|-----------|-----------|
| SQLite Database | `/opt/devrel-integration/devrel-integration/data/onomancer.db` | Daily | 7 days |
| Secrets | `/opt/devrel-integration/devrel-integration/secrets/` | Manual | Permanent |
| Application Logs | `/var/log/devrel/` | Rotated | 14 days |
| PM2 Config | `/opt/devrel-integration/devrel-integration/ecosystem.config.js` | Git | Permanent |

---

## Automatic Backups

### Database Backup Cron

Add to crontab (`crontab -e` as devrel user):

```cron
# Daily database backup at 3 AM
0 3 * * * /opt/devrel-integration/devrel-integration/docs/deployment/scripts/backup.sh >> /var/log/devrel/backup.log 2>&1
```

### Backup Script

Create `/opt/devrel-integration/devrel-integration/docs/deployment/scripts/backup.sh`:

```bash
#!/bin/bash
# Database Backup Script

set -e

DATA_DIR="/opt/devrel-integration/devrel-integration/data"
BACKUP_DIR="/opt/devrel-integration/devrel-integration/backups"
DB_FILE="$DATA_DIR/onomancer.db"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/onomancer_${TIMESTAMP}.db"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "No database to backup"
    exit 0
fi

# Create backup
sqlite3 "$DB_FILE" ".backup '$BACKUP_FILE'"

# Compress backup
gzip "$BACKUP_FILE"

# Remove backups older than 7 days
find "$BACKUP_DIR" -name "onomancer_*.db.gz" -mtime +7 -delete

echo "Backup created: ${BACKUP_FILE}.gz"
ls -lh "${BACKUP_FILE}.gz"
```

---

## Manual Backup

### Full Backup

```bash
# Stop the bot (optional, for consistency)
pm2 stop onomancer-bot

# Backup database
mkdir -p /opt/devrel-integration/devrel-integration/backups
cp /opt/devrel-integration/devrel-integration/data/onomancer.db \
   /opt/devrel-integration/devrel-integration/backups/onomancer_$(date +%Y%m%d_%H%M%S).db

# Backup secrets (do this rarely, store securely)
tar -czf /tmp/secrets_backup_$(date +%Y%m%d).tar.gz \
   /opt/devrel-integration/devrel-integration/secrets/

# Restart if stopped
pm2 start onomancer-bot
```

### Export to Remote

```bash
# Copy backup to local machine
scp devrel@server:/opt/devrel-integration/devrel-integration/backups/onomancer_*.db.gz ./backups/
```

---

## Restore Procedures

### Restore Database from Backup

```bash
# 1. List available backups
ls -lt /opt/devrel-integration/devrel-integration/backups/

# 2. Stop the bot
pm2 stop onomancer-bot

# 3. Backup current database first (just in case)
cp /opt/devrel-integration/devrel-integration/data/onomancer.db \
   /opt/devrel-integration/devrel-integration/backups/onomancer_pre_restore_$(date +%Y%m%d_%H%M%S).db

# 4. Decompress backup (if gzipped)
gunzip -k /opt/devrel-integration/devrel-integration/backups/onomancer_20251216_030000.db.gz

# 5. Restore
cp /opt/devrel-integration/devrel-integration/backups/onomancer_20251216_030000.db \
   /opt/devrel-integration/devrel-integration/data/onomancer.db

# 6. Start the bot
pm2 start onomancer-bot

# 7. Verify
pm2 logs onomancer-bot --lines 20
```

### Restore from Scratch

If you need to restore on a new server:

```bash
# 1. Set up server using server-setup.sh
# 2. Clone repository
# 3. Restore secrets
tar -xzf secrets_backup_20251216.tar.gz -C /

# 4. Restore database
gunzip -c backup.db.gz > /opt/devrel-integration/devrel-integration/data/onomancer.db

# 5. Install and build
cd /opt/devrel-integration/devrel-integration
npm ci
npm run build

# 6. Start
pm2 start ecosystem.config.js --env production
```

---

## Disaster Recovery

### Complete Server Loss

If the server is completely lost:

1. **Provision new server** with same OS (Ubuntu 22.04)
2. **Run server setup script**
3. **Clone repository from git**
4. **Restore secrets from secure backup** (1Password, team vault, etc.)
5. **Restore database from most recent backup**
6. **Re-register Discord commands**
7. **Update DNS if IP changed**

### Recovery Time Objectives

| Scenario | RTO | RPO |
|----------|-----|-----|
| Application crash | 5 minutes | 0 (no data loss) |
| Database corruption | 30 minutes | 24 hours (last backup) |
| Server failure | 2 hours | 24 hours |
| Complete disaster | 4 hours | 24 hours |

---

## Testing Backups

Monthly, verify backups are working:

```bash
# 1. Create test restore directory
mkdir -p /tmp/backup_test

# 2. Copy and decompress latest backup
cp /opt/devrel-integration/devrel-integration/backups/$(ls -t /opt/devrel-integration/devrel-integration/backups/*.db.gz | head -1) /tmp/backup_test/
cd /tmp/backup_test
gunzip *.db.gz

# 3. Verify database integrity
sqlite3 *.db "PRAGMA integrity_check;"

# 4. Check data exists
sqlite3 *.db "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "Table check complete"

# 5. Clean up
rm -rf /tmp/backup_test

echo "Backup verification complete"
```
