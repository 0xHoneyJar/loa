# Deployment Infrastructure Security Audit Report

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2025-12-09
**Scope:** Server setup documentation, deployment scripts, infrastructure security
**Methodology:** Systematic review of deployment automation, infrastructure configuration, secrets management, and operational security

---

## Executive Summary

I conducted a comprehensive security audit of the agentic-base DevRel integration deployment infrastructure. This audit covered server setup procedures, deployment automation scripts, Docker configurations, service files, and operational runbooks.

**Overall Risk Level:** **MEDIUM**

The deployment infrastructure demonstrates good security practices in many areas (SHA-256 pinned Docker images, non-root execution, secrets validation). However, there are **CRITICAL gaps** that must be addressed before production deployment.

**Key Statistics:**
- **Critical Issues:** 7 (deployment-blocking)
- **High Priority Issues:** 8 (fix before production)
- **Medium Priority Issues:** 6 (address soon)
- **Low Priority Issues:** 4 (technical debt)
- **Informational Notes:** 5

**Deployment Readiness Verdict:** ❌ **NOT READY FOR PRODUCTION**

Critical issues must be resolved before deploying to any production server. The infrastructure has solid foundations but contains security gaps that attackers WILL exploit.

---

## Critical Issues (Fix Immediately - Deployment Blocking)

### [CRITICAL-001] No Environment Template File Exists

**Severity:** CRITICAL
**Component:** `devrel-integration/secrets/`
**Risk:** Secrets exposure, deployment failures

**Description:**
The deployment documentation references `secrets/.env.local.example` template file, but this file DOES NOT EXIST in the repository. Multiple components depend on this file:
- Server setup guide instructs: "cp secrets/.env.local.example secrets/.env.local"
- Deployment scripts check for this template
- Secrets validation script assumes this exists

**Impact:**
- Deployers have NO reference for which secrets are required
- Risk of missing critical environment variables
- Risk of incorrect environment variable formats
- Risk of copy-pasting secrets from documentation (which may contain example values)
- No secure onboarding path for new team members

**Proof of Concept:**
```bash
$ find /home/debian/agentic-base/devrel-integration -name "*.example" -o -name ".env.template"
# NO OUTPUT - File does not exist!
```

**Remediation:**
1. **IMMEDIATELY create** `devrel-integration/secrets/.env.local.example` with:
   ```bash
   # Discord Configuration
   DISCORD_BOT_TOKEN=your_discord_bot_token_here
   DISCORD_GUILD_ID=your_discord_server_id_here
   DISCORD_CLIENT_ID=your_discord_client_id_here

   # Linear Configuration
   LINEAR_API_KEY=lin_api_your_key_here
   LINEAR_TEAM_ID=your-linear-team-uuid-here
   LINEAR_WEBHOOK_SECRET=generate_random_64_char_secret_here

   # GitHub Configuration (optional)
   GITHUB_TOKEN=ghp_your_token_here
   GITHUB_WEBHOOK_SECRET=generate_random_32_char_secret_here

   # Vercel Configuration (optional)
   VERCEL_TOKEN=your_vercel_token_here
   VERCEL_WEBHOOK_SECRET=generate_random_32_char_secret_here

   # Application Configuration
   NODE_ENV=development
   LOG_LEVEL=info
   PORT=3000
   TZ=UTC
   ```

2. **Add comments** explaining:
   - Where to obtain each token (Discord Developer Portal, Linear Settings, etc.)
   - Required permissions/scopes for each token
   - How to generate secure webhook secrets (`openssl rand -hex 32`)
   - Which variables are required vs optional

3. **Update `.gitignore`** to ensure `.env.local.example` is NOT ignored:
   ```gitignore
   # Secrets (CRITICAL - NEVER COMMIT)
   secrets/
   .env
   .env.local
   .env.*.local
   *.key
   *.pem

   # BUT allow the example template
   !secrets/.env.local.example
   ```

4. **Document secret generation** in `docs/deployment/secrets-setup.md`

**References:** OWASP A07:2021 - Identification and Authentication Failures

---

### [CRITICAL-002] Deployment Scripts Don't Actually Exist on Server

**Severity:** CRITICAL
**Component:** `docs/deployment/server-setup-guide.md` (Lines 46-53, 61-111)
**Risk:** Deployment failure, manual error-prone setup

**Description:**
The server setup guide instructs users to run deployment scripts:
```bash
sudo ./01-initial-setup.sh
sudo ./02-security-hardening.sh
sudo ./03-install-dependencies.sh
sudo ./04-deploy-app.sh
```

**These scripts DO NOT EXIST.** The `docs/deployment/scripts/` directory is empty:
```bash
$ ls -la /home/debian/agentic-base/docs/deployment/scripts/
# NO FILES FOUND
```

The documentation describes what these scripts SHOULD do (lines 63-111), but the actual shell scripts were never created. This forces users to:
1. Manually run commands from "Manual Setup Steps" section
2. Manually type commands (risk of typos)
3. No validation that steps completed successfully
4. No idempotency (running twice may fail)

**Impact:**
- **Deployment failures** due to missing scripts
- **Manual errors** when typing commands
- **Inconsistent deployments** across team members
- **Security misconfigurations** from skipped steps
- **No audit trail** of deployment actions

**Remediation:**
**IMMEDIATELY create these scripts:**

1. **`docs/deployment/scripts/01-initial-setup.sh`**
2. **`docs/deployment/scripts/02-security-hardening.sh`**
3. **`docs/deployment/scripts/03-install-dependencies.sh`**
4. **`docs/deployment/scripts/04-deploy-app.sh`**
5. **`docs/deployment/scripts/05-setup-monitoring.sh`** (optional)
6. **`docs/deployment/scripts/06-setup-ssl.sh`** (optional)

Each script MUST:
- Start with `#!/bin/bash` and `set -euo pipefail`
- Check prerequisites before proceeding
- Be idempotent (safe to run multiple times)
- Log all actions
- Validate success of each step
- Provide clear error messages
- Exit with non-zero status on failure

**Priority:** BLOCKING - Cannot deploy without these scripts

**References:** NIST SP 800-53 CM-7 (Least Functionality)

---

### [CRITICAL-003] PM2 Ecosystem Config Uses Absolute Path That Won't Exist

**Severity:** CRITICAL
**Component:** `devrel-integration/ecosystem.config.js` (Line 24)
**Risk:** Application won't start, PM2 failures

**Description:**
The PM2 ecosystem configuration hardcodes:
```javascript
cwd: '/opt/agentic-base/integration',
```

**This path will NOT exist** on most servers. The documentation shows inconsistent paths:
- PM2 config: `/opt/agentic-base/integration`
- Server setup guide: `/opt/devrel-integration`
- Systemd service: `/opt/agentic-base/integration`
- Docker configs: `/app`

When a user follows the server setup guide, they create `/opt/devrel-integration`, but PM2 tries to start from `/opt/agentic-base/integration`, causing:
```
Error: ENOENT: no such file or directory, chdir '/opt/agentic-base/integration'
```

**Impact:**
- **PM2 won't start** the application
- **Confusing errors** for deployers
- **Inconsistent documentation** causes deployment failures
- **Manual workarounds** required (defeating automation)

**Remediation:**
1. **Standardize on ONE path** across all documentation:
   - Recommendation: `/opt/devrel-integration` (matches current server setup guide)

2. **Update ALL references:**
   - `devrel-integration/ecosystem.config.js` line 24
   - `devrel-integration/agentic-base-bot.service` line 11, 14
   - `docs/deployment/server-setup-guide.md` (verify consistency)
   - Any Docker volume mount paths in production configs

3. **Make path configurable:**
   ```javascript
   // ecosystem.config.js
   const APP_DIR = process.env.APP_DIR || '/opt/devrel-integration';

   module.exports = {
     apps: [{
       cwd: APP_DIR,
       // ... rest of config
     }]
   };
   ```

4. **Add validation** to deployment scripts:
   ```bash
   if [ ! -d "/opt/devrel-integration" ]; then
       error_exit "Application directory does not exist"
   fi
   ```

**References:** CWE-73 (External Control of File Name or Path)

---

### [CRITICAL-004] Secrets Validation Script Never Actually Runs

**Severity:** CRITICAL
**Component:** `devrel-integration/scripts/deploy-production.sh` (Lines 146-153), `deploy-staging.sh` (Lines 94-101)
**Risk:** Deploying with invalid/missing secrets

**Description:**
Both deployment scripts have secrets validation logic:
```bash
if [ -f "scripts/verify-secrets.ts" ]; then
    npm run verify-secrets -- --env=production || error_exit "Secrets validation failed"
else
    log_warning "Secrets validation script not found, skipping validation"
fi
```

**The script checks for `verify-secrets.ts` (TypeScript), but the actual script is `verify-deployment-secrets.sh` (Bash).**

The validation NEVER runs. The script just logs a warning and continues deployment with potentially invalid secrets. This defeats the entire purpose of having validation.

**Impact:**
- **Deploy with missing secrets** → Application crashes immediately
- **Deploy with malformed secrets** → Subtle runtime failures
- **Deploy with example values** → Security breach (bots use placeholder tokens)
- **No pre-deployment verification** → Fail late instead of failing fast
- **False sense of security** → Team thinks validation happened

**Actual deployed secrets could be:**
- `DISCORD_BOT_TOKEN=your_discord_bot_token_here` (example value)
- `LINEAR_API_KEY=changeme` (placeholder)
- Missing entirely

**Remediation:**
1. **Fix deployment scripts** to call correct script:
   ```bash
   # deploy-production.sh line 146
   if [ -f "scripts/verify-deployment-secrets.sh" ]; then
       ./scripts/verify-deployment-secrets.sh production || error_exit "Secrets validation failed"
   else
       error_exit "Secrets validation script not found: scripts/verify-deployment-secrets.sh"
   fi
   ```

2. **Make validation MANDATORY** (not optional):
   - Remove the `if [ -f ... ]` check
   - Always require the validation script to exist
   - Exit with error if validation fails (already does this)

3. **Run validation in CI/CD** before deployment approval

4. **Add to pre-deployment checklist** in runbooks

**References:** OWASP A07:2021 - Identification and Authentication Failures

---

### [CRITICAL-005] No Secrets Rotation Procedure or Documentation

**Severity:** CRITICAL
**Component:** Operational procedures
**Risk:** Long-lived credentials, no incident response capability

**Description:**
The documentation references secrets rotation multiple times:
- `server-setup-guide.md` line 397: "Quarterly: Rotate API tokens"
- `security-checklist.md` line 148: "Quarterly: Rotate API tokens"
- `server-operations.md` lines 247-275: Basic token replacement procedures
- `quick-reference.md` lines 87-93: Simple environment file editing

**But there is NO comprehensive secrets rotation documentation:**
- No step-by-step procedures for each service (Discord, Linear, GitHub, Vercel)
- No coordination plan (how to rotate without downtime)
- No testing procedures (verify new tokens work before removing old)
- No rollback procedures (if new tokens don't work)
- No documentation of where tokens are used (may be in multiple places)
- No notification requirements (alert team, update CI/CD, etc.)

**What happens in a security incident?**
1. Discord bot token leaks in logs
2. Need to rotate immediately
3. No documented procedure
4. Engineer guesses: Update `.env.local`, restart bot
5. Forgot to update Discord Developer Portal first
6. Bot fails to connect (old token revoked, new token not generated)
7. Downtime, panic, manual fixes

**Impact:**
- **Cannot respond to credential leaks** quickly
- **Downtime during rotation** due to incorrect procedure
- **Incomplete rotation** (miss some instances)
- **No validation** that rotation succeeded
- **Compliance violations** (no quarterly rotation)

**Remediation:**
**IMMEDIATELY create** `docs/deployment/runbooks/secrets-rotation.md` with:

```markdown
# Secrets Rotation Procedures

## Discord Bot Token Rotation

1. **Pre-rotation checks:**
   - [ ] Identify all places token is used (.env files, CI/CD, backups)
   - [ ] Schedule maintenance window (if zero-downtime not possible)
   - [ ] Notify team of rotation

2. **Generate new token:**
   - [ ] Go to Discord Developer Portal
   - [ ] Navigate to Bot section
   - [ ] Click "Regenerate Token"
   - [ ] Copy new token (only shown once!)
   - [ ] Test token: `curl -H "Authorization: Bot NEW_TOKEN" https://discord.com/api/users/@me`

3. **Deploy new token:**
   - [ ] Update production `.env.production`
   - [ ] Update staging `.env.staging`
   - [ ] Update local `.env.local`
   - [ ] Update CI/CD secrets (GitHub Actions, etc.)
   - [ ] Update backup systems

4. **Restart services:**
   - [ ] Restart production: `pm2 restart devrel-bot`
   - [ ] Verify connection: Check logs for "Discord connected"
   - [ ] Test commands in Discord

5. **Verify rotation:**
   - [ ] Bot shows as online
   - [ ] Commands respond correctly
   - [ ] Webhooks still work
   - [ ] No errors in logs

6. **Post-rotation:**
   - [ ] Old token is automatically revoked by Discord
   - [ ] Update rotation log: `echo "$(date): Discord token rotated by ${USER}" >> /var/log/secrets-rotation.log`
   - [ ] Schedule next rotation (90 days)

## Emergency Rotation (Credential Leak)

If a secret is compromised, rotate IMMEDIATELY:

1. **Isolate:** Stop using the leaked secret immediately
2. **Rotate:** Generate new secret and deploy to production first
3. **Verify:** Confirm new secret works
4. **Revoke:** Revoke/delete old secret
5. **Audit:** Review logs for unauthorized use
6. **Document:** Record incident details
```

Do this for EVERY service integration (Linear, GitHub, Vercel).

**References:** NIST SP 800-57 (Key Management), SOC 2 CC6.1

---

### [CRITICAL-006] Docker Production Config Exposes Port 3000 Publicly

**Severity:** CRITICAL
**Component:** `devrel-integration/docker-compose.prod.yml` (Lines 42-45)
**Risk:** Webhooks and health checks exposed to internet without auth

**Description:**
The production Docker Compose config binds port 3000 to all interfaces:
```yaml
ports:
  - "3000:3000"  # HTTP server (webhooks, health checks)
  # In production, consider using reverse proxy in front:
  # - "127.0.0.1:3000:3000"
```

**This exposes the application directly to the internet** without:
- HTTPS/TLS encryption (traffic is plaintext)
- Rate limiting at network level
- DDoS protection
- IP restrictions
- Reverse proxy security headers

**An attacker can:**
1. Send unlimited webhook requests (DoS attack)
2. Probe health endpoint for version disclosure
3. Attempt webhook signature bypass
4. Intercept plaintext traffic (if no HTTPS)

**The comment acknowledges this:** "consider using reverse proxy" but leaves it configured insecurely.

**Impact:**
- **Webhook endpoints publicly accessible** without TLS
- **Secrets in webhook payloads** transmitted in plaintext (if no HTTPS)
- **No rate limiting** at network edge
- **Health check exposes internal state** to attackers
- **DDoS vulnerability** (no firewall protection)

**Remediation:**
1. **Bind to localhost ONLY in production:**
   ```yaml
   # docker-compose.prod.yml
   ports:
     - "127.0.0.1:3000:3000"  # Only accessible from localhost
   ```

2. **REQUIRE nginx reverse proxy** in deployment:
   ```bash
   # Add to pre-deployment checks
   if ! systemctl is-active --quiet nginx; then
       error_exit "nginx reverse proxy must be running in production"
   fi
   ```

3. **Document nginx setup** in `docs/deployment/scripts/06-setup-ssl.sh`

4. **Add to security checklist:**
   - [ ] Application not directly exposed to internet
   - [ ] Reverse proxy configured with HTTPS
   - [ ] Rate limiting enabled at nginx level

5. **Update production compose** to make this the default (not a comment)

**References:** OWASP A05:2021 - Security Misconfiguration, CIS Docker Benchmark 5.7

---

### [CRITICAL-007] No Backup Strategy or Restore Procedures Exist

**Severity:** CRITICAL
**Component:** Backup and disaster recovery
**Risk:** Permanent data loss, extended downtime

**Description:**
The deployment documentation mentions backups in several places:
- `server-setup-guide.md` lines 415-423: Basic manual backup command
- `server-operations.md` lines 417-444: Backup and restore commands
- `deploy-production.sh` lines 110-143: Backup before deployment

**But critical gaps exist:**
- **No automated backup schedule** (daily/weekly/monthly)
- **No backup verification** (backups may be corrupt)
- **No off-site backup storage** (server failure = data loss)
- **No tested restore procedure** (backups that can't be restored are useless)
- **No backup retention policy** (how long to keep, when to delete)
- **No backup encryption** (secrets exposed in backup files)
- **No backup monitoring** (know if backups are failing)

**What data could be lost?**
- User preferences and permissions (`data/` directory)
- Bot configuration customizations (`config/` directory)
- API tokens and secrets (`secrets/` directory)
- Application logs (`logs/` directory)

**Impact if server fails:**
1. Hardware failure destroys disk
2. All secrets are lost (no backup)
3. Cannot redeploy (don't remember what tokens were used)
4. Must regenerate all tokens, reconfigure all integrations
5. Days of downtime, lost institutional knowledge

**Remediation:**
**IMMEDIATELY create** `docs/deployment/runbooks/backup-restore.md`:

```markdown
# Backup and Restore Procedures

## Automated Daily Backups

1. **Install backup cron job:**
   ```bash
   # /etc/cron.daily/devrel-backup
   #!/bin/bash
   set -euo pipefail

   BACKUP_DATE=$(date +%Y%m%d)
   BACKUP_DIR="/opt/backups/devrel-integration/${BACKUP_DATE}"
   APP_DIR="/opt/devrel-integration"

   mkdir -p "${BACKUP_DIR}"

   # Backup configuration (non-sensitive, version-controlled)
   tar -czf "${BACKUP_DIR}/config.tar.gz" "${APP_DIR}/config"

   # Backup data (database, user preferences)
   tar -czf "${BACKUP_DIR}/data.tar.gz" "${APP_DIR}/data"

   # Backup secrets (ENCRYPT THIS!)
   tar -czf - "${APP_DIR}/secrets" | \
       gpg --encrypt --recipient admin@company.com > \
       "${BACKUP_DIR}/secrets.tar.gz.gpg"

   # Backup PM2 config
   cp "${APP_DIR}/ecosystem.config.js" "${BACKUP_DIR}/"

   # Backup systemd service
   cp /etc/systemd/system/devrel-integration.service "${BACKUP_DIR}/" 2>/dev/null || true

   # Copy to off-site storage (S3, rsync, etc.)
   aws s3 sync /opt/backups s3://company-backups/devrel-integration/ --sse AES256

   # Verify backup
   tar -tzf "${BACKUP_DIR}/config.tar.gz" > /dev/null
   tar -tzf "${BACKUP_DIR}/data.tar.gz" > /dev/null

   # Retention: Keep 30 days, delete older
   find /opt/backups/devrel-integration -type d -mtime +30 -exec rm -rf {} \;

   echo "Backup completed: ${BACKUP_DIR}"
   ```

2. **Make executable and test:**
   ```bash
   chmod +x /etc/cron.daily/devrel-backup
   /etc/cron.daily/devrel-backup
   ```

## Restore from Backup

### Full Server Recovery

1. **Provision new server** (follow server-setup-guide.md)

2. **Install dependencies** (Node.js, PM2, nginx)

3. **Download latest backup:**
   ```bash
   aws s3 sync s3://company-backups/devrel-integration/YYYYMMDD/ /opt/restore/
   ```

4. **Decrypt and restore secrets:**
   ```bash
   gpg --decrypt /opt/restore/secrets.tar.gz.gpg | tar -xzf - -C /opt/devrel-integration/
   chmod 600 /opt/devrel-integration/secrets/.env.*
   ```

5. **Restore configuration and data:**
   ```bash
   tar -xzf /opt/restore/config.tar.gz -C /opt/devrel-integration/
   tar -xzf /opt/restore/data.tar.gz -C /opt/devrel-integration/
   ```

6. **Fix permissions:**
   ```bash
   chown -R devrel:devrel /opt/devrel-integration
   ```

7. **Start application:**
   ```bash
   pm2 start /opt/devrel-integration/ecosystem.config.js
   ```

8. **Verify restoration:**
   ```bash
   curl http://localhost:3000/health
   pm2 logs devrel-bot --lines 20
   ```

### Testing Restore (Quarterly Requirement)

**MUST test restore every quarter to verify backups are valid:**

1. Spin up temporary test server
2. Restore latest backup
3. Verify application starts
4. Document any issues
5. Update restore procedures if needed
```

**References:** NIST SP 800-34 (Contingency Planning), SOC 2 A1.2

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Systemd Service File Has Excessive Restrictions That Will Break Application

**Severity:** HIGH
**Component:** `devrel-integration/agentic-base-bot.service` (Lines 35-43)
**Risk:** Application startup failures, permission denied errors

**Description:**
The systemd service file has overly restrictive security hardening:
```ini
NoNewPrivileges=true          # Good
PrivateTmp=true               # Good
ProtectSystem=strict          # PROBLEM
ProtectHome=true              # PROBLEM
ReadWritePaths=/opt/agentic-base/integration/logs
ReadWritePaths=/opt/agentic-base/integration/data
```

**`ProtectSystem=strict` makes the entire filesystem read-only** except explicitly allowed paths.
**`ProtectHome=true` makes all home directories inaccessible.**

**This will break:**
- npm installing dependencies (needs write to `/opt/agentic-base/integration/node_modules`)
- TypeScript compilation (needs write to `/opt/agentic-base/integration/dist`)
- Config file reading if stored in unexpected locations
- Temporary file creation outside `/tmp`

**Impact:**
Application won't start:
```
EACCES: permission denied, open '/opt/agentic-base/integration/dist/bot.js'
```

**Remediation:**
```ini
# agentic-base-bot.service
[Service]
# Allow writes to application directory
ReadWritePaths=/opt/agentic-base/integration
ReadWritePaths=/tmp

# Keep ProtectSystem=full (not strict)
ProtectSystem=full
ProtectHome=true

# Add other security hardening
NoNewPrivileges=true
PrivateTmp=true
PrivateDevices=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictRealtime=true
```

**Test before deployment:**
```bash
sudo systemctl daemon-reload
sudo systemctl start devrel-integration
sudo systemctl status devrel-integration
journalctl -u devrel-integration -n 50
```

---

### [HIGH-002] Server Setup Scripts Will Run With Root Privileges (Dangerous)

**Severity:** HIGH
**Component:** `docs/deployment/server-setup-guide.md` (Lines 46-53)
**Risk:** Privilege escalation, system compromise

**Description:**
The server setup guide instructs users to run scripts as root:
```bash
sudo ./01-initial-setup.sh
sudo ./02-security-hardening.sh
sudo ./03-install-dependencies.sh
sudo ./04-deploy-app.sh
```

Running deployment scripts as root is dangerous because:
- **If script is compromised**, attacker has root access
- **If script has bugs**, can damage system
- **No principle of least privilege** applied
- **Scripts may create files owned by root** (wrong permissions)

**These scripts download code from the internet** (npm install, git clone) and execute it as root. If an attacker compromises:
- The npm registry (supply chain attack)
- The git repository
- The server hosting Node.js binaries

They get **root access to the server.**

**Impact:**
- **Full system compromise** if any component is malicious
- **Incorrect file ownership** (files owned by root instead of `devrel` user)
- **Cannot fix permissions** without sudo

**Remediation:**
1. **Separate privilege levels:**
   ```bash
   # Run as root (requires sudo)
   sudo ./01-initial-setup.sh        # System packages
   sudo ./02-security-hardening.sh   # Firewall, SSH config
   sudo ./03-install-dependencies.sh # Node.js, PM2 global

   # Run as devrel user (NO sudo)
   ./04-deploy-app.sh                # Application code
   ```

2. **Use `SUDO_USER` variable** inside scripts:
   ```bash
   # Inside scripts that need sudo
   if [ -z "${SUDO_USER}" ]; then
       error_exit "This script must be run with sudo"
   fi

   # When creating files, use actual user (not root)
   sudo -u "${SUDO_USER}" git clone ...
   chown -R "${SUDO_USER}:${SUDO_USER}" /opt/devrel-integration
   ```

3. **Explicitly document** when sudo is required vs not required

4. **Add privilege checks** to scripts:
   ```bash
   # For scripts that need root
   if [ "$EUID" -ne 0 ]; then
       error_exit "This script must be run as root (use sudo)"
   fi

   # For scripts that should NOT be root
   if [ "$EUID" -eq 0 ]; then
       error_exit "This script must NOT be run as root"
   fi
   ```

**References:** OWASP A08:2021 - Software and Data Integrity Failures, CIS Benchmark 5.4.1

---

### [HIGH-003] No Firewall Rules Configured for Docker

**Severity:** HIGH
**Component:** Security hardening, Docker networking
**Risk:** Docker bypasses UFW firewall rules

**Description:**
The security checklist (line 15-22) and setup guide mention configuring UFW:
```bash
ufw allow ssh
ufw allow 443/tcp
ufw allow 3000/tcp
```

**Docker bypasses UFW rules by default.** Docker directly modifies iptables, ignoring UFW configuration. Even if UFW says "port 3000 is closed," Docker will expose it.

**Proof:**
```bash
# Set up UFW to deny port 3000
ufw deny 3000/tcp
ufw status
# Shows: 3000/tcp DENY Anywhere

# Start Docker container with port mapping
docker run -p 3000:3000 app

# Port 3000 is ACCESSIBLE from internet despite UFW deny rule!
```

**Impact:**
- **False sense of security** (think port is blocked, but it's open)
- **Unexpected exposure** of webhook endpoints
- **Docker published ports always public** unless bound to localhost
- **UFW configuration is ignored** for Docker containers

**Remediation:**
1. **Bind Docker ports to localhost** (CRITICAL-006):
   ```yaml
   ports:
     - "127.0.0.1:3000:3000"
   ```

2. **Configure Docker to respect UFW:**
   ```bash
   # /etc/docker/daemon.json
   {
     "iptables": false
   }

   # Restart Docker
   systemctl restart docker
   ```

3. **Use Docker's --network-mode host** and rely on UFW (less portable)

4. **Document in security-hardening script:**
   ```bash
   # 02-security-hardening.sh
   echo "Configuring Docker to respect UFW rules..."
   cat > /etc/docker/daemon.json <<EOF
   {
     "iptables": false
   }
   EOF
   systemctl restart docker
   ```

5. **Add to security checklist:**
   - [ ] Docker configured to respect UFW rules
   - [ ] Production ports bound to localhost only
   - [ ] Verified Docker doesn't bypass firewall

**References:** CIS Docker Benchmark 2.8, Docker Security Best Practices

---

### [HIGH-004] SSH Hardening Steps Are Documented But Not Automated

**Severity:** HIGH
**Component:** `docs/deployment/server-setup-guide.md` (Lines 151-155)
**Risk:** Weak SSH configuration, brute force attacks

**Description:**
The setup guide lists SSH hardening recommendations:
```bash
# Harden SSH (edit /etc/ssh/sshd_config)
# PermitRootLogin no
# PasswordAuthentication no
# PubkeyAuthentication yes
systemctl restart sshd
```

**But this is manual, commented-out, and easy to skip.** These are CRITICAL security settings that should be automated in `02-security-hardening.sh`.

**Current state:**
- Deployers must manually edit `/etc/ssh/sshd_config`
- Easy to make mistakes (syntax errors)
- Easy to skip entirely (just forget)
- No validation that settings were applied

**Impact:**
- **Root login enabled** (direct root SSH access)
- **Password authentication enabled** (vulnerable to brute force)
- **Weak SSH configuration** remains on production servers
- **Compliance violations** (CIS Benchmark requirement)

**Remediation:**
Create `docs/deployment/scripts/02-security-hardening.sh` with automated SSH hardening:

```bash
#!/bin/bash
set -euo pipefail

log_info() { echo "[INFO] $1"; }
error_exit() { echo "[ERROR] $1"; exit 1; }

log_info "Hardening SSH configuration..."

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

# Apply SSH hardening settings
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config

# Add if not present
grep -q "^ClientAliveInterval" /etc/ssh/sshd_config || \
    echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config || \
    echo "ClientAliveCountMax 2" >> /etc/ssh/sshd_config

# Validate config before restarting
sshd -t || error_exit "Invalid SSH configuration"

# Restart SSH (DANGEROUS - ensure you have alternate access)
log_info "Restarting SSH daemon..."
systemctl restart sshd || error_exit "Failed to restart SSH"

log_info "SSH hardening complete"
```

**Add safety warning:**
```bash
echo "WARNING: This will disable password authentication."
echo "Ensure you have SSH key configured BEFORE running this script."
echo "If you lose SSH access, you will need console access to recover."
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" = "yes" ] || exit 0
```

**References:** CIS Ubuntu Benchmark 5.2.x, NIST SP 800-123

---

### [HIGH-005] No Rate Limiting at Infrastructure Level

**Severity:** HIGH
**Component:** Nginx configuration, webhook endpoints
**Risk:** DoS attacks, API abuse

**Description:**
The application has rate limiting in code (`linearService.ts` circuit breaker), but there is **NO rate limiting at the infrastructure level** (nginx, firewall).

An attacker can:
1. Send thousands of webhook requests per second
2. Exhaust application memory/CPU before rate limiter kicks in
3. DDoS the health check endpoint
4. Bypass application-level rate limiting by sending malformed requests that crash before reaching rate limiter

**Missing nginx rate limiting:**
The nginx config template (lines 273-301 of server-setup-guide.md) has NO rate limiting:
```nginx
location /webhooks/ {
    proxy_pass http://127.0.0.1:3000;
    # NO RATE LIMITING!
}
```

**Impact:**
- **DoS vulnerability** at webhook endpoints
- **No protection from floods** of malicious webhooks
- **Application crashes** under load before rate limiter helps
- **No IP-based blocking** of abusive sources

**Remediation:**
Add to nginx configuration template:

```nginx
# Define rate limiting zones
limit_req_zone $binary_remote_addr zone=webhook_limit:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=30r/s;
limit_req_zone $binary_remote_addr zone=health_limit:10m rate=1r/s;

server {
    # Webhooks: 10 requests/second per IP
    location /webhooks/ {
        limit_req zone=webhook_limit burst=20 nodelay;
        limit_req_status 429;

        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Health check: 1 request/second per IP
    location /health {
        limit_req zone=health_limit burst=5 nodelay;
        proxy_pass http://127.0.0.1:3000;
    }

    # API endpoints: 30 requests/second per IP
    location / {
        limit_req zone=api_limit burst=50 nodelay;
        proxy_pass http://127.0.0.1:3000;
    }
}
```

Add to `06-setup-ssl.sh` script and document in security checklist.

**References:** OWASP A05:2021 - Security Misconfiguration, CIS Nginx Benchmark

---

### [HIGH-006] Logs May Contain Secrets (No Log Sanitization)

**Severity:** HIGH
**Component:** Logging configuration, operational procedures
**Risk:** Secret exposure in log files

**Description:**
The application logs extensively (PM2 logs, systemd journal, Docker logs), but there is **NO documentation or tooling** to prevent secrets from being logged.

**Potential secret leaks:**
- Logging full Discord messages (may contain tokens)
- Logging webhook payloads (contain signature secrets)
- Logging Linear API responses (may contain sensitive data)
- Logging error objects (may contain environment variables)
- Logging HTTP request headers (may contain Authorization headers)

**The code likely has secret scanning** (based on `README-SECURITY.md` mentioning `output-validator.ts` and `secret-scanner.ts`), but:
- No documentation of what's scanned
- No operational procedures to review logs for leaks
- No automated log scanning before sharing logs
- No guidance for support staff accessing logs

**Impact:**
- **Secrets exposed in log files** that are world-readable
- **Secrets in rotated/archived logs** (persistent exposure)
- **Secrets in backup files** (if logs are backed up)
- **Secrets shared in bug reports** (copy-paste logs to GitHub issues)
- **Secrets in log aggregation systems** (Splunk, ELK)

**Remediation:**
1. **Document log sanitization procedures** in operational runbook:
   ```markdown
   ## Viewing Logs Safely

   Before sharing logs externally, sanitize them:

   ```bash
   # Remove Discord tokens
   pm2 logs devrel-bot | sed -E 's/[A-Za-z0-9_-]{24}\.[A-Za-z0-9_-]{6}\.[A-Za-z0-9_-]{27}/DISCORD_TOKEN_REDACTED/g'

   # Remove Linear API keys
   pm2 logs devrel-bot | sed -E 's/lin_api_[A-Za-z0-9]{40,}/LINEAR_KEY_REDACTED/g'

   # Remove GitHub tokens
   pm2 logs devrel-bot | sed -E 's/gh[ps]_[A-Za-z0-9]{36,}/GITHUB_TOKEN_REDACTED/g'
   ```
   ```

2. **Add log sanitization script:**
   ```bash
   # scripts/sanitize-logs.sh
   #!/bin/bash
   # Sanitize logs before sharing
   sed -E 's/([Tt]oken|[Kk]ey|[Ss]ecret)[:=]\s*[A-Za-z0-9_\-\.]+/\1: REDACTED/g'
   ```

3. **Configure log rotation with sanitization:**
   ```bash
   # In logrotate config
   postrotate
       /opt/devrel-integration/scripts/sanitize-logs.sh /var/log/devrel/*.log
   endscript
   ```

4. **Add to security checklist:**
   - [ ] Logs reviewed for secret exposure before sharing
   - [ ] Log sanitization script available
   - [ ] Team trained on safe log handling

**References:** OWASP A09:2021 - Security Logging and Monitoring Failures

---

### [HIGH-007] No Incident Response Plan Documented

**Severity:** HIGH
**Component:** Security operations, incident response
**Risk:** Inadequate response to security incidents

**Description:**
The security checklist mentions "incident response plan" (line 178-179), and there's an "Emergency Procedures" section in `server-operations.md` (lines 342-394), but there is **NO comprehensive incident response plan.**

**What exists:**
- Basic "Security Incident" section with evidence preservation (lines 376-394)
- Emergency contacts placeholders (lines 447-451)
- Isolating server command (block all traffic)

**What's missing:**
- **Incident classification** (what qualifies as an incident?)
- **Severity levels** (how to triage incidents)
- **Escalation procedures** (who to contact, in what order)
- **Response timelines** (how quickly to respond to each severity)
- **Communication plan** (who to notify, what to say)
- **Forensic procedures** (how to investigate without destroying evidence)
- **Recovery procedures** (how to restore after incident)
- **Post-incident review** (learn from incidents)

**Incident scenarios with no documented response:**
1. Discord bot token leaked in public GitHub commit
2. Linear API key exposed in application logs
3. Unauthorized access detected in auth.log
4. Server compromised, malicious code installed
5. DDoS attack overwhelming webhook endpoints
6. Insider threat (team member with malicious intent)

**Impact:**
- **Slow response** to incidents (figuring out what to do)
- **Inconsistent response** (different people handle differently)
- **Evidence destruction** (well-meaning actions destroy forensics)
- **Incomplete response** (forget to rotate secrets, notify users, etc.)
- **No learning** from incidents (repeat mistakes)

**Remediation:**
Create `docs/deployment/runbooks/incident-response.md`:

```markdown
# Security Incident Response Plan

## Incident Severity Levels

### CRITICAL (P0)
- **Response Time:** Immediate (< 15 minutes)
- **Examples:** Active breach, data exfiltration, service down
- **Actions:** Page on-call, escalate to CTO, preserve evidence

### HIGH (P1)
- **Response Time:** < 1 hour
- **Examples:** Credential leak, unauthorized access attempt, DDoS
- **Actions:** Notify security team, begin investigation

### MEDIUM (P2)
- **Response Time:** < 4 hours
- **Examples:** Suspicious logs, failed login attempts, misconfiguration
- **Actions:** Investigate, document findings

### LOW (P3)
- **Response Time:** < 24 hours
- **Examples:** Security scan findings, outdated dependencies
- **Actions:** Create ticket, schedule fix

## Response Procedures

### 1. Detection and Triage (First 15 minutes)

- [ ] Confirm incident is real (not false positive)
- [ ] Classify severity (P0/P1/P2/P3)
- [ ] Notify on-call engineer
- [ ] Begin incident log (who, what, when)

### 2. Containment (First hour)

- [ ] Stop the bleeding (isolate compromised systems)
- [ ] Preserve evidence (copy logs, snapshots)
- [ ] Rotate compromised credentials
- [ ] Block malicious IPs/users

### 3. Investigation (Hours 1-4)

- [ ] Determine attack vector
- [ ] Identify affected systems/data
- [ ] Review logs for unauthorized access
- [ ] Interview witnesses (if insider threat)

### 4. Remediation (Hours 4-24)

- [ ] Fix root cause vulnerability
- [ ] Verify attacker is evicted
- [ ] Restore from clean backup if needed
- [ ] Deploy patches/fixes

### 5. Recovery (Days 1-7)

- [ ] Return to normal operations
- [ ] Monitor for repeat incidents
- [ ] Notify affected users (if required by law)
- [ ] Document lessons learned

### 6. Post-Incident Review (Week 1-2)

- [ ] Hold blameless postmortem
- [ ] Update runbooks based on lessons
- [ ] Implement preventive measures
- [ ] Schedule follow-up security audit

## Contact Information

### Primary Contacts
- **On-Call Engineer:** [Phone number, PagerDuty]
- **Security Team:** [Email, Slack channel]
- **CTO:** [Phone number for P0 escalation]

### External Contacts
- **Legal:** [If breach notification required]
- **PR:** [If public disclosure needed]
- **Law Enforcement:** [If crime suspected]

## Communication Templates

[Include email templates for various scenarios]
```

**References:** NIST SP 800-61r2 (Incident Handling), ISO 27035

---

### [HIGH-008] PM2 Restart Behavior May Cause Restart Loops

**Severity:** HIGH
**Component:** `devrel-integration/ecosystem.config.js` (Lines 32-75)
**Risk:** Application crash loops, resource exhaustion

**Description:**
The PM2 configuration has aggressive restart settings:
```javascript
autorestart: true,
max_restarts: 10,
min_uptime: '10s',
restart_delay: 5000,  // 5 seconds
exp_backoff_restart_delay: 100,
```

**If application fails to start** (invalid secrets, missing dependencies), PM2 will:
1. Start app
2. App crashes after 5 seconds
3. Wait 5 seconds
4. Restart (attempt 2)
5. App crashes again
6. Repeat 10 times
7. Give up

**Problems:**
- **10 restarts in ~1 minute** (5s + 5s delay × 10)
- **Exponential backoff of only 100ms** (almost no backoff)
- **Rapid resource consumption** (memory leaks multiply)
- **Log spam** (thousands of error messages)
- **Alert fatigue** (monitoring fires 10 alerts immediately)

**Compare to systemd service** (lines 24-27):
```ini
Restart=on-failure
RestartSec=10
StartLimitInterval=200
StartLimitBurst=5
```
Systemd gives up after **5 attempts in 200 seconds** (much more conservative).

**Impact:**
- **Resource exhaustion** during crash loops
- **Difficult troubleshooting** (logs move too fast)
- **Monitoring overwhelmed** (too many alerts)
- **No time to investigate** (app restarts before engineer can check)

**Remediation:**
```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    autorestart: true,

    // Conservative restart policy
    max_restarts: 5,          // Give up after 5 attempts
    min_uptime: '30s',        // Must stay up 30s to reset counter
    restart_delay: 10000,     // 10 second delay between restarts

    // Exponential backoff (100ms, 200ms, 400ms, 800ms, 1600ms)
    exp_backoff_restart_delay: 100,

    // Time to wait before giving up restart attempts (5 minutes)
    max_restart_attempts_per_window: 5,
    restart_window_length: 300000,  // 5 minutes
  }]
};
```

**Add monitoring alert:**
```javascript
// Alert if app restarts more than 3 times in 10 minutes
if (restarts_last_10_min > 3) {
  notify_on_call("DevRel bot is crash-looping");
}
```

**References:** PM2 Best Practices, SRE Site Reliability Engineering

---

## Medium Priority Issues (Address Soon After Deployment)

### [MED-001] No Monitoring or Alerting Actually Configured

**Severity:** MEDIUM
**Component:** Monitoring infrastructure
**Risk:** Incidents undetected, slow response times

**Description:**
The deployment documentation mentions monitoring multiple times:
- `server-operations.md` lines 397-415: "Monitoring Alerts" section
- `security-checklist.md` lines 84-88: Alert configuration checkboxes
- `server-setup-guide.md` line 98-105: Optional `05-setup-monitoring.sh`

**But NO monitoring is actually configured.** The "Monitoring Alerts" section is just a table of WHAT to alert on, not HOW to set up alerts.

**What exists:**
- Application exposes `/health` and `/metrics` endpoints
- PM2 has `pm2 monit` command (manual, not automated)
- Docker has `docker stats` (manual, not automated)

**What's missing:**
- No metrics collection (Prometheus, Datadog, CloudWatch)
- No alerting system (PagerDuty, Opsgenie, Slack)
- No dashboards (Grafana, Datadog)
- No uptime monitoring (external health check)
- No log aggregation (ELK, Splunk, CloudWatch Logs)

**Impact:**
- **Incidents go unnoticed** until users report them
- **No proactive detection** of issues
- **Slow mean-time-to-detection** (MTTD)
- **Cannot meet SLAs** without monitoring
- **No historical metrics** for capacity planning

**Remediation:**
Document basic monitoring setup in `docs/deployment/monitoring-setup.md`:

```markdown
# Monitoring Setup

## Option 1: Prometheus + Grafana (Self-hosted)

1. **Install Prometheus:**
   ```bash
   # docker-compose.monitoring.yml
   version: '3.8'
   services:
     prometheus:
       image: prom/prometheus:latest
       ports:
         - "9090:9090"
       volumes:
         - ./prometheus.yml:/etc/prometheus/prometheus.yml
         - prometheus-data:/prometheus
       command:
         - '--config.file=/etc/prometheus/prometheus.yml'
   ```

2. **Configure scraping:**
   ```yaml
   # prometheus.yml
   scrape_configs:
     - job_name: 'devrel-bot'
       static_configs:
         - targets: ['localhost:3000']
       metrics_path: '/metrics'
       scrape_interval: 30s
   ```

3. **Install Grafana:**
   ```bash
   docker run -d -p 3001:3000 grafana/grafana:latest
   ```

4. **Import dashboard:** [Provide Grafana JSON]

## Option 2: Cloud Monitoring (Datadog, New Relic)

1. **Install agent:**
   ```bash
   DD_API_KEY=xxx DD_SITE="datadoghq.com" bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)"
   ```

2. **Configure integration:**
   ```yaml
   # /etc/datadog-agent/conf.d/pm2.d/conf.yaml
   logs:
     - type: file
       path: /var/log/devrel/out.log
       service: devrel-bot
       source: nodejs
   ```

3. **Create monitors:** [Document alert conditions]

## Minimum Monitoring (Uptime Kuma - Free)

1. **Install Uptime Kuma:**
   ```bash
   docker run -d -p 3002:3001 louislam/uptime-kuma:latest
   ```

2. **Add health check monitor:**
   - URL: http://your-server:3000/health
   - Interval: 60 seconds
   - Notification: Discord webhook

## Critical Alerts to Configure

1. **Service down** (health check fails 3x)
2. **High error rate** (>10 errors/minute)
3. **High memory** (>80% for 5 minutes)
4. **Disk full** (>90%)
5. **Discord disconnected** (check logs)
```

---

### [MED-002] Docker Image Not Scanned for Vulnerabilities

**Severity:** MEDIUM
**Component:** `devrel-integration/Dockerfile`, CI/CD
**Risk:** Deploying vulnerable Docker images

**Description:**
The Dockerfile uses SHA-256 pinned base images (good!), but there is:
- **No vulnerability scanning** of the final image
- **No scanning of npm dependencies** in the image
- **No scanning of base image vulnerabilities**
- **No policy to prevent deploying vulnerable images**

The base image `node:18-alpine@sha256:435dca...` was pinned at some point, but:
- That SHA may now contain known vulnerabilities
- No process to update to newer secure base image
- No notification when vulnerabilities are discovered

**Impact:**
- **Deploy vulnerable containers** to production
- **Known CVEs present** in production images
- **No compliance** with vulnerability management requirements
- **Attack surface unknown** (what vulnerabilities exist?)

**Remediation:**
1. **Add Trivy scanning** to deployment scripts:
   ```bash
   # In deploy-production.sh, before deployment
   log_info "Scanning Docker image for vulnerabilities..."
   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
       aquasec/trivy:latest image --severity HIGH,CRITICAL \
       --exit-code 1 "${IMAGE_NAME}" || error_exit "Vulnerability scan failed"
   ```

2. **Scan in CI/CD pipeline** (GitHub Actions):
   ```yaml
   - name: Scan Docker image
     uses: aquasecurity/trivy-action@master
     with:
       image-ref: agentic-base-integration:latest
       severity: HIGH,CRITICAL
       exit-code: 1
   ```

3. **Update base image monthly:**
   ```bash
   # Get latest SHA for node:18-alpine
   docker pull node:18-alpine
   docker inspect node:18-alpine | jq -r '.[0].RepoDigests[0]'
   # Update Dockerfile with new SHA
   ```

4. **Document in** `docs/deployment/runbooks/vulnerability-management.md`

---

### [MED-003] Hardcoded Paths in Multiple Configuration Files

**Severity:** MEDIUM
**Component:** Ecosystem, systemd, documentation
**Risk:** Deployment failures, maintenance burden

**Description:**
Paths are hardcoded and inconsistent across files:
- PM2: `/opt/agentic-base/integration`
- Systemd: `/opt/agentic-base/integration`
- Docs: `/opt/devrel-integration`
- Docker: `/app`
- Docker volumes: `/opt/agentic-base/logs`, `/opt/agentic-base/data`

This creates:
- **Confusion** about correct path
- **Deployment failures** when paths don't match
- **Difficult to customize** installation location
- **Maintenance burden** (must update 5+ files to change path)

**Remediation:**
1. **Standardize on one path:** `/opt/devrel-integration`

2. **Create path configuration file:**
   ```bash
   # /etc/devrel-integration/paths.conf
   APP_DIR=/opt/devrel-integration
   LOGS_DIR=/var/log/devrel-integration
   DATA_DIR=/var/lib/devrel-integration
   SECRETS_DIR=/opt/devrel-integration/secrets
   CONFIG_DIR=/opt/devrel-integration/config
   ```

3. **Source in all scripts:**
   ```bash
   # At top of every script
   source /etc/devrel-integration/paths.conf || {
       APP_DIR=/opt/devrel-integration
   }
   ```

4. **Use environment variables in systemd:**
   ```ini
   [Service]
   EnvironmentFile=/etc/devrel-integration/paths.conf
   WorkingDirectory=${APP_DIR}
   ```

---

### [MED-004] No Health Check for Discord Connection

**Severity:** MEDIUM
**Component:** Health check endpoint, monitoring
**Risk:** False positives (app healthy but bot offline)

**Description:**
The `/health` endpoint checks if the HTTP server is running, but according to `verification-checklist.md` (line 86), it should also check Discord connection status:
```json
{"status":"healthy","uptime":123,"discord":"connected"}
```

**But there's no verification** that the health check actually validates Discord connection. If Discord is disconnected, the health check may still return 200 OK.

**Impact:**
- **Bot offline** but health checks pass
- **Monitoring doesn't detect** Discord disconnections
- **Manual checking required** (grep logs for "Discord connected")
- **False confidence** in system health

**Remediation:**
Verify health endpoint implementation includes Discord check:
```typescript
// In health endpoint handler
app.get('/health', (req, res) => {
  const discordStatus = client.ws.status === 0 ? 'connected' : 'disconnected';
  const linearStatus = circuitBreaker.isOpen() ? 'degraded' : 'operational';

  const isHealthy = discordStatus === 'connected' && linearStatus !== 'degraded';
  const httpStatus = isHealthy ? 200 : 503;

  res.status(httpStatus).json({
    status: isHealthy ? 'healthy' : 'unhealthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    services: {
      discord: discordStatus,
      linear: linearStatus
    }
  });
});
```

Add to monitoring: alert if `services.discord !== 'connected'` for 3 consecutive checks.

---

### [MED-005] Logs Not Encrypted at Rest

**Severity:** MEDIUM
**Component:** Log storage, backup encryption
**Risk:** Sensitive data exposure if disk compromised

**Description:**
Logs are stored in plaintext:
- `/var/log/devrel/out.log`
- `/var/log/devrel/error.log`
- Docker logs
- Backup archives

If logs contain any sensitive data (user messages, partial tokens in errors, IP addresses), they are exposed if:
- Server is compromised
- Disk is stolen
- Backup is leaked
- Log aggregation system is breached

**Remediation:**
1. **Encrypt log directory:**
   ```bash
   # Use LUKS for log directory
   cryptsetup luksFormat /dev/sdb1
   cryptsetup luksOpen /dev/sdb1 logs_encrypted
   mkfs.ext4 /dev/mapper/logs_encrypted
   mount /dev/mapper/logs_encrypted /var/log/devrel
   ```

2. **Encrypt backup archives** (already mentioned in CRITICAL-007)

3. **Use encrypted log aggregation** (TLS transport to ELK/Splunk)

4. **Add to security checklist:**
   - [ ] Logs encrypted at rest
   - [ ] Log backups encrypted
   - [ ] Log transport uses TLS

---

### [MED-006] No Network Segmentation for Docker Containers

**Severity:** MEDIUM
**Component:** Docker networking, security
**Risk:** Container escape leads to full network access

**Description:**
The production Docker Compose creates a custom network (`agentic-base-network`), but:
- No network segmentation from host
- No egress filtering (container can access anything)
- No ingress filtering (except port mappings)
- No network policy enforcement

If the container is compromised, attacker has access to:
- Entire server network
- Other Docker containers
- Cloud metadata API (169.254.169.254)
- Internal services on the host

**Remediation:**
1. **Use Docker network policies:**
   ```yaml
   # docker-compose.prod.yml
   networks:
     agentic-base-network:
       driver: bridge
       internal: false  # Allows external access (Discord, Linear APIs)
       driver_opts:
         com.docker.network.bridge.enable_ip_masquerade: "true"
         com.docker.network.bridge.enable_icc: "false"  # Disable inter-container communication
   ```

2. **Block cloud metadata API:**
   ```bash
   # On host
   iptables -A OUTPUT -d 169.254.169.254 -j DROP
   ```

3. **Implement egress filtering** (allow only Discord, Linear, GitHub APIs)

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Manual Setup Steps Duplicate Script Content

**Severity:** LOW
**Component:** Documentation organization
**Risk:** Documentation divergence, maintenance burden

**Description:**
The server-setup-guide.md contains both:
- Script-based setup (lines 39-57)
- Manual setup steps (lines 113-207)

The manual steps DUPLICATE what the scripts should do. This creates:
- **Maintenance burden** (update in two places)
- **Risk of divergence** (script does X, manual says Y)
- **Confusion** about which approach to use

**Remediation:**
- Remove manual setup steps
- OR clearly label: "Manual setup (for understanding scripts only)"
- Keep scripts as source of truth

---

### [LOW-002] No Automated Testing of Deployment Scripts

**Severity:** LOW
**Component:** Deployment automation
**Risk:** Broken deployment scripts

**Description:**
The deployment scripts have no automated tests. Changes to scripts may break deployment without anyone knowing until production deployment fails.

**Remediation:**
Add CI/CD tests that:
1. Spin up test VM
2. Run deployment scripts
3. Verify application starts
4. Verify health checks pass
5. Tear down test VM

Use GitHub Actions with Docker-in-Docker or Vagrant.

---

### [LOW-003] PM2 Logs Not Centralized

**Severity:** LOW
**Component:** Logging infrastructure
**Risk:** Difficult troubleshooting, log loss

**Description:**
PM2 logs are scattered:
- PM2 managed logs: `./logs/pm2-out.log`
- Application logs: `/var/log/devrel/out.log`
- Docker logs: via `docker logs`
- systemd logs: via `journalctl`

**Remediation:**
Centralize logs with:
- ELK stack (Elasticsearch, Logstash, Kibana)
- OR Loki + Grafana
- OR CloudWatch Logs
- OR Datadog

---

### [LOW-004] No Database Backup for `data/auth.db`

**Severity:** LOW
**Component:** Data backup
**Risk:** Loss of user permissions/preferences

**Description:**
The `.gitignore` file excludes `data/auth.db` (line 42), and the backup procedures mention backing up `data/`, but there's no specific mention of database backup.

If this is a SQLite database, it should be backed up with proper locking:
```bash
sqlite3 data/auth.db ".backup 'data/auth.db.backup'"
```

**Remediation:**
Document database-specific backup in backup runbook.

---

## Informational Notes (Best Practices)

1. **Good: SHA-256 Pinned Docker Images**
   - The Dockerfile uses SHA-256 pinned base images
   - This prevents supply chain attacks via base image tampering
   - MAINTAIN THIS: Update SHA regularly but keep pinning

2. **Good: Non-Root User in Docker**
   - Dockerfile creates and uses non-root user (UID 1001)
   - systemd service runs as non-root user
   - PM2 should also run as non-root (document this)

3. **Good: Secrets Validation Script**
   - Comprehensive validation of secret formats
   - Checks for example/placeholder values
   - Validates file permissions
   - Just needs to be actually called (CRITICAL-004)

4. **Good: Health Check Implementation**
   - Application exposes `/health`, `/ready`, `/metrics` endpoints
   - Docker Compose includes health checks
   - Just needs to actually check Discord connection (MED-004)

5. **Good: Deployment Script Safety Features**
   - Production deployment requires explicit "yes" confirmation
   - Automatic backup before deployment
   - Health check monitoring with automatic rollback
   - Clear error messages with rollback instructions

---

## Positive Findings (Things Done Well)

- **Comprehensive documentation:** Extensive runbooks, checklists, and guides
- **Security-focused:** Many security considerations documented (just not all implemented)
- **Multi-environment support:** Separate configs for dev, staging, production
- **Automated deployment:** Scripts for staging and production deployment
- **Secrets management awareness:** Strong documentation of secrets handling requirements
- **Paranoid security mindset:** Documentation shows awareness of threats
- **Resource limits:** Docker Compose configs include memory/CPU limits
- **Log rotation:** Configured in Docker Compose and documented for PM2
- **Graceful shutdown:** Uses dumb-init in Docker for proper signal handling
- **Health checks:** Application and infrastructure health monitoring designed

---

## Infrastructure Security Checklist Status

### Server Security
- [❌] SSH key-only authentication - **MANUAL STEP** (HIGH-004)
- [❌] Root login disabled - **MANUAL STEP** (HIGH-004)
- [✅] fail2ban configured - **Documented**
- [❌] Firewall enabled with deny-by-default - **Docker bypasses UFW** (HIGH-003)
- [❌] Automatic security updates - **Not in scripts**
- [❌] Audit logging enabled - **Not documented**

### Application Security
- [✅] Running as non-root user - **systemd, Dockerfile**
- [✅] Resource limits configured - **Docker Compose**
- [❌] Secrets not in scripts - **Missing template** (CRITICAL-001)
- [❌] Environment file secured - **No validation it runs** (CRITICAL-004)
- [⚠️] Logs don't expose secrets - **No procedures** (HIGH-006)

### Network Security
- [⚠️] TLS 1.2+ only - **nginx template, not automated**
- [⚠️] Strong cipher suites - **nginx template, not automated**
- [⚠️] HTTPS redirect - **nginx template, not automated**
- [⚠️] Security headers set - **nginx template, not automated**
- [❌] Internal ports not exposed - **Port 3000 exposed** (CRITICAL-006)

### Operational Security
- [❌] Backup procedure documented - **Basic only** (CRITICAL-007)
- [❌] Recovery tested - **No test schedule** (CRITICAL-007)
- [❌] Secret rotation documented - **Basic only** (CRITICAL-005)
- [❌] Incident response plan - **Incomplete** (HIGH-007)
- [⚠️] Access revocation procedure - **Not documented**

### Deployment Security
- [❌] Scripts exist in repository - **DO NOT EXIST** (CRITICAL-002)
- [❌] Secrets validation runs - **Never executes** (CRITICAL-004)
- [❌] Vulnerability scanning - **No scanning** (MED-002)
- [✅] Deployment approval required - **Explicit confirmation**
- [❌] Monitoring configured - **Not automated** (MED-001)

**Overall Checklist Completion: 25%** (6/24 fully implemented)

---

## Threat Model

### Trust Boundaries

1. **External → Application**
   - Discord API → Bot
   - Linear webhooks → Webhook server
   - GitHub/Vercel webhooks → Webhook server
   - UNTRUSTED: Webhook signatures must be verified

2. **Application → External APIs**
   - Bot → Discord API (trusted with bot token)
   - Bot → Linear API (trusted with API key)
   - SEMI-TRUSTED: APIs can be malicious or compromised

3. **Host → Container**
   - systemd/PM2 → Application
   - TRUSTED: Host can control container completely

4. **Human → Server**
   - SSH access → Root commands
   - TRUSTED: SSH users are trusted (must protect SSH keys)

### Attack Vectors

1. **Webhook Signature Bypass**
   - Attacker sends malicious webhook without valid signature
   - Application accepts unsigned webhook
   - Mitigation: Webhook signature verification (application layer)

2. **Discord Bot Token Compromise**
   - Token leaked in logs, commits, or backups
   - Attacker controls bot, sends spam, steals data
   - Mitigation: Token scanning, secrets rotation, log sanitization

3. **Server Compromise via SSH**
   - Attacker brute forces weak password
   - Attacker steals SSH key from developer laptop
   - Mitigation: SSH hardening, key rotation, MFA

4. **Supply Chain Attack**
   - Malicious npm package installed
   - Compromised Docker base image
   - Mitigation: SHA-256 pinning, vulnerability scanning, npm audit

5. **DoS via Webhook Flooding**
   - Attacker floods `/webhooks/*` with requests
   - Application crashes, memory exhaustion
   - Mitigation: Rate limiting (nginx level), circuit breakers

6. **Container Escape**
   - Vulnerability in Docker runtime
   - Attacker breaks out of container to host
   - Mitigation: Non-root user, read-only filesystem, AppArmor/SELinux

### Blast Radius Analysis

**If Discord bot token is compromised:**
- Attacker can: Read all messages in server, send messages, modify channels
- Blast radius: ENTIRE Discord server
- Recovery: Rotate token (15 minutes), review audit log, notify users
- Containment: Bot has limited Discord permissions (cannot delete server)

**If Linear API key is compromised:**
- Attacker can: Read all issues, create/modify/delete issues, access team data
- Blast radius: ENTIRE Linear workspace
- Recovery: Rotate token (15 minutes), review issue history, restore from backup
- Containment: API key scoped to one team only (if configured correctly)

**If server is fully compromised:**
- Attacker can: Steal all secrets, destroy data, pivot to other systems
- Blast radius: All integrated services (Discord, Linear, GitHub, Vercel)
- Recovery: Rotate ALL secrets, rebuild server, forensic investigation (hours to days)
- Containment: Server has limited network access (egress filtering needed)

### Residual Risks

After remediating all findings, these risks remain:

1. **Third-party service compromise** (Discord, Linear APIs hacked)
   - Mitigation: None (out of our control)
   - Acceptance: Monitor for unusual API behavior

2. **Zero-day vulnerabilities** in Node.js, Docker, Linux kernel
   - Mitigation: Keep systems updated, minimize attack surface
   - Acceptance: Monitor security advisories, patch quickly

3. **Insider threat** (malicious team member)
   - Mitigation: Access controls, audit logging, background checks
   - Acceptance: Trust but verify, monitor for anomalies

4. **Social engineering** (phishing for Discord/Linear credentials)
   - Mitigation: Security training, MFA requirement
   - Acceptance: Human error will occur, have incident response ready

---

## Recommendations

### Immediate Actions (Before Any Deployment)

1. **CREATE** `devrel-integration/secrets/.env.local.example` template (CRITICAL-001)
2. **CREATE** all deployment scripts in `docs/deployment/scripts/` (CRITICAL-002)
3. **FIX** PM2 path inconsistency in `ecosystem.config.js` (CRITICAL-003)
4. **FIX** secrets validation script invocation in deploy scripts (CRITICAL-004)
5. **DOCUMENT** secrets rotation procedures for all services (CRITICAL-005)
6. **BIND** Docker production port to localhost only (CRITICAL-006)
7. **CREATE** comprehensive backup and restore runbook (CRITICAL-007)

**Estimated Time:** 12-16 hours (2 full work days)

**BLOCKER:** Do not deploy to production until all CRITICAL issues are resolved.

### Short-Term Actions (First Week of Production)

1. Fix systemd service file restrictions (HIGH-001)
2. Implement proper sudo separation in setup scripts (HIGH-002)
3. Configure Docker to respect UFW firewall rules (HIGH-003)
4. Automate SSH hardening in security hardening script (HIGH-004)
5. Add nginx rate limiting configuration (HIGH-005)
6. Document log sanitization procedures (HIGH-006)
7. Create comprehensive incident response plan (HIGH-007)
8. Tune PM2 restart policy to prevent crash loops (HIGH-008)

**Estimated Time:** 20-30 hours (1 full work week)

### Long-Term Actions (First Month)

1. Set up monitoring and alerting (MED-001)
2. Implement Docker image vulnerability scanning (MED-002)
3. Centralize paths in configuration management (MED-003)
4. Enhance health check to validate Discord connection (MED-004)
5. Encrypt logs at rest (MED-005)
6. Implement Docker network segmentation (MED-006)

**Estimated Time:** 30-40 hours (1-1.5 work weeks)

---

## Audit Completed

**Date:** 2025-12-09
**Next Audit Recommended:** After remediating CRITICAL and HIGH issues (1-2 weeks)
**Remediation Tracking:** Create issues for each finding in your issue tracker

---

**This deployment infrastructure requires significant security work before production use. The foundations are solid (good documentation, awareness of security concerns), but critical implementation gaps exist. Address CRITICAL issues immediately before deploying to any production server.**
