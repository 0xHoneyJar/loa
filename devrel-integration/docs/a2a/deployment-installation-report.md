# DevRel Integration Bot - Installation Report

**Deployment Date**: 2025-12-09
**Server**: 15.235.228.10 (hivemind)
**Domain**: ainmdilis.com
**Bot Name**: Onomancer#6505
**Final Status**: ✅ DEPLOYED AND OPERATIONAL

---

## Executive Summary

The DevRel Integration Bot was successfully deployed to production after resolving 12 distinct issues during the installation process. The deployment involved security hardening, SSL configuration, and multiple application configuration fixes. Total deployment time was approximately 2 hours including troubleshooting.

---

## Deployment Environment

| Component | Version/Details |
|-----------|-----------------|
| OS | Debian Trixie (13/testing) |
| Node.js | v20.19.6 |
| PM2 | Latest (global) |
| nginx | Latest |
| SSL | Let's Encrypt (auto-renewal) |
| Monitoring | Uptime Kuma (Docker) |

---

## Issues Encountered and Resolutions

### Issue #1: Missing `software-properties-common` Package

**Symptom**:
```
E: Unable to locate package software-properties-common
```

**Cause**: Debian Trixie doesn't include `software-properties-common` - it's Ubuntu-specific.

**Resolution**: Skipped this package and installed remaining dependencies directly:
```bash
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
```

---

### Issue #2: UFW Script Syntax Error

**Symptom**:
```
./02-security-hardening.sh: line 148: syntax error near unexpected token `)'
```

**Cause**: Escaped quote in UFW comment `'HTTP (Let\'s Encrypt)'` caused bash parsing error.

**Resolution**: Ran UFW commands manually with simplified comment:
```bash
sudo ufw allow 80/tcp comment 'HTTP LetsEncrypt'
echo "y" | sudo ufw enable
```

---

### Issue #3: Node.js Version Conflict (nvm vs system)

**Symptom**:
```
$ node --version
v18.20.8  # Expected v20.x
```

**Cause**: User had nvm installed with Node 18 taking precedence over system Node 20.

**Resolution**:
- System Node 20 was at `/usr/bin/node`
- nvm Node 18 was at `/home/debian/.nvm/versions/node/v18.20.8/bin/node`
- Used explicit paths for devrel user who doesn't have nvm:
```bash
sudo -u devrel bash -c 'cd /opt/devrel-integration && /usr/bin/npm install'
```

---

### Issue #4: Application Directory Permissions

**Symptom**:
```
[ERROR] This script must NOT be run as root. Run as the devrel user.
```
Then:
```
/bin/bash: ./04-deploy-app.sh: Permission denied
```

**Cause**: Files copied as root, devrel user couldn't access them.

**Resolution**:
```bash
sudo chown -R devrel:devrel /opt/devrel-integration
sudo chmod 750 /opt/devrel-integration
sudo chmod 700 /opt/devrel-integration/secrets
```

---

### Issue #5: Missing `helmet` TypeScript Types

**Symptom**:
```
error TS2307: Cannot find module 'helmet' or its corresponding type declarations.
```

**Cause**: `helmet` package and its types weren't in dependencies.

**Resolution**:
```bash
sudo -u devrel bash -c 'cd /opt/devrel-integration && npm install helmet @types/helmet'
```

---

### Issue #6: Node.js Version Incompatibility (v18 vs v20 required)

**Symptom**:
```
TypeError: Cannot read properties of undefined (reading 'get')
at Object.<anonymous> (/opt/devrel-integration/node_modules/webidl-conversions/lib/index.js:325:94)
```

**Cause**: Several npm packages required Node 20+ but Node 18 was being used.

**Resolution**: Upgraded Node.js to v20 via NodeSource and rebuilt:
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo -u devrel bash -c 'cd /opt/devrel-integration && rm -rf node_modules && npm install && npm run build'
```

---

### Issue #7: PM2 Not Loading Environment Variables

**Symptom**:
```
Error: No accessToken or apiKey provided to the LinearClient
```

**Cause**: PM2's `env_file` option in ecosystem.config.js wasn't loading the .env.local file before module initialization.

**Resolution**: Used dotenv preload with explicit path:
```bash
sudo -u devrel bash -c 'cd /opt/devrel-integration && DOTENV_CONFIG_PATH=./secrets/.env.local pm2 start dist/bot.js --name agentic-base-bot --node-args="-r dotenv/config"'
```

---

### Issue #8: Environment Variable Name Mismatch

**Symptom**:
```
Error: No accessToken or apiKey provided to the LinearClient
```

**Cause**: Code expected `LINEAR_API_TOKEN` but env file had `LINEAR_API_KEY`.

**Resolution**: Added correct variable name to env file:
```bash
sudo sed -i 's/LINEAR_API_KEY=/LINEAR_API_TOKEN=/' /opt/devrel-integration/secrets/.env.local
```

---

### Issue #9: Discord Bot Token Validation Regex Too Strict

**Symptom**:
```
FATAL: Invalid format for DISCORD_BOT_TOKEN
Expected: Discord bot token format
```

**Cause**: Validation regex `/^[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}$/` was too strict for newer Discord token format (72 chars vs expected 59).

**Resolution**: Updated regex in `src/utils/secrets.ts`:
```javascript
// Old
pattern: /^[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}$/

// New
pattern: /^[MN][A-Za-z\d]{20,30}\.[\w-]{5,10}\.[\w-]{25,45}$/
```

---

### Issue #10: Linear API Token Validation Regex Too Strict

**Symptom**:
```
FATAL: Invalid format for LINEAR_API_TOKEN
Expected: Linear API token format
```

**Cause**: Validation regex expected lowercase hex `/^lin_api_[a-f0-9]{40}$/` but token had mixed case alphanumeric.

**Resolution**: Updated regex in `src/utils/secrets.ts`:
```javascript
// Old
pattern: /^lin_api_[a-f0-9]{40}$/

// New
pattern: /^lin_api_[A-Za-z0-9]{30,50}$/
```

---

### Issue #11: Missing Database Schema File

**Symptom**:
```
Schema file not found: /opt/devrel-integration/dist/database/schema.sql
```

**Cause**: TypeScript build doesn't copy `.sql` files to `dist/` directory.

**Resolution**: Manually copied schema file:
```bash
sudo mkdir -p /opt/devrel-integration/dist/database
sudo cp /opt/devrel-integration/src/database/schema.sql /opt/devrel-integration/dist/database/
sudo chown devrel:devrel /opt/devrel-integration/dist/database/schema.sql
```

---

### Issue #12: Missing Required Discord Configuration

**Symptom**:
```
FATAL: Missing required [API_KEY REDACTED]
```
and
```
Role validation failed: developer role ID not configured
```

**Cause**: Missing required environment variables:
- `DISCORD_DIGEST_CHANNEL_ID`
- `DEVELOPER_ROLE_ID`
- `ADMIN_ROLE_ID`

**Resolution**: Created Discord roles and added all required IDs to `.env.local`:
```bash
DISCORD_DIGEST_CHANNEL_ID=<channel_id>
DEVELOPER_ROLE_ID=<role_id>
ADMIN_ROLE_ID=<role_id>
```

---

## Recommendations for Future Deployments

### 1. Update Deployment Scripts
- Remove `software-properties-common` dependency for Debian compatibility
- Fix UFW comment quoting issue
- Add schema.sql copy step to build process

### 2. Update Token Validation
The strict regex patterns should be relaxed in the codebase to accommodate token format variations:
- Discord tokens can vary in length
- Linear tokens use mixed-case alphanumeric

### 3. Improve Environment Variable Handling
- Document exact expected variable names (e.g., `LINEAR_API_TOKEN` not `LINEAR_API_KEY`)
- Consider using dotenv loading earlier in the application bootstrap

### 4. Add Pre-flight Checks
Create a validation script that checks:
- All required env vars are present
- Token formats are valid
- Discord roles exist
- Database schema files are in place

### 5. Update Documentation
- Add Debian Trixie-specific notes
- Document the nvm conflict resolution
- Include exact token format requirements

---

## Final Configuration

### Environment Variables Required
```
DISCORD_BOT_TOKEN=<token>
DISCORD_CLIENT_ID=<id>
DISCORD_GUILD_ID=<id>
DISCORD_DIGEST_CHANNEL_ID=<id>
DEVELOPER_ROLE_ID=<id>
ADMIN_ROLE_ID=<id>
LINEAR_API_TOKEN=<token>
LINEAR_TEAM_ID=<uuid>
LINEAR_WEBHOOK_SECRET=<secret>
NODE_ENV=production
PORT=3000
```

### PM2 Start Command
```bash
sudo -u devrel bash -c 'cd /opt/devrel-integration && DOTENV_CONFIG_PATH=./secrets/.env.local pm2 start dist/bot.js --name agentic-base-bot --node-args="-r dotenv/config"'
```

### Services Running
- **PM2**: agentic-base-bot (auto-restart on boot via systemd)
- **nginx**: Reverse proxy with SSL termination
- **Uptime Kuma**: Monitoring (Docker container)
- **fail2ban**: Brute-force protection
- **UFW**: Firewall (ports 22, 80, 443)

---

## Verification Checklist

- [x] SSH access working
- [x] Firewall active (UFW)
- [x] fail2ban running
- [x] Node.js v20 installed
- [x] Application built successfully
- [x] PM2 process running
- [x] Auto-restart configured (systemd)
- [x] nginx reverse proxy configured
- [x] SSL certificate installed (Let's Encrypt)
- [x] Health endpoint responding (https://ainmdilis.com/health)
- [x] Discord bot online (Onomancer#6505)
- [x] Linear API connected
- [x] Monitoring running (Uptime Kuma)

---

## Contact & Support

For issues with this deployment:
1. Check logs: `sudo -u devrel pm2 logs agentic-base-bot`
2. Verify status: `sudo -u devrel pm2 status`
3. Check health: `curl https://ainmdilis.com/health`

---

*Report generated: 2025-12-09*
*Deployment executed via `/deploy-go` command*
