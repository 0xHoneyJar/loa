# Deployment Report: Bare Metal Server Deployment

**Date**: December 15, 2024
**Server**: ns5036138 (Ubuntu, 125GB RAM)
**Branch**: trrfrm-ggl
**Status**: SUCCESS

---

## Summary

Successfully deployed Onomancer Bot to bare metal server. Several code and configuration fixes were required during deployment that should be incorporated into the main codebase to prevent drift.

---

## Fixes Applied During Deployment

### 1. Token Validation Regex Too Strict

**File**: `src/utils/secrets.ts`
**Commit**: `3d31d7e`

**Problem**: Discord and Linear token validation regex patterns were too strict, rejecting valid production tokens.

**Fix**: Relaxed regex patterns to accommodate varying token lengths:

```typescript
// Before
DISCORD_BOT_TOKEN: {
  pattern: /^[MN][A-Za-z\d]{23}\.[\w-]{6}\.[\w-]{27}$/,
},
LINEAR_API_TOKEN: {
  pattern: /^lin_api_[a-f0-9]{40}$/,
},

// After
DISCORD_BOT_TOKEN: {
  pattern: /^[MN][A-Za-z\d]{20,30}\.[\w-]{5,10}\.[\w-]{25,40}$/,
},
LINEAR_API_TOKEN: {
  pattern: /^lin_api_[A-Za-z0-9]{30,50}$/,
},
```

---

### 2. Missing Non-TypeScript Assets in dist

**File**: `src/database/schema.sql`
**Commit**: `327beae` (runbook update)

**Problem**: TypeScript compiler doesn't copy `.sql` files to `dist/`. Bot fails with "Schema file not found" error.

**Fix**: Manual copy after build:
```bash
cp src/database/schema.sql dist/database/
```

**Recommended Permanent Fix**: Add postbuild script to `package.json`:
```json
{
  "scripts": {
    "postbuild": "cp src/database/schema.sql dist/database/"
  }
}
```

---

### 3. DOC_ROOT Path Resolution Incorrect

**File**: `src/handlers/interactions.ts:295`
**Commit**: `19bc98a`

**Problem**: Path `../../../docs` from `dist/handlers/` resolved to `/opt/docs` instead of `/opt/devrel-integration/docs`.

**Fix**: Changed to `../../docs`:

```typescript
// Before
const DOC_ROOT = path.resolve(__dirname, '../../../docs');

// After
const DOC_ROOT = path.resolve(__dirname, '../../docs');
```

---

### 4. Missing Configuration File

**File**: `config/folder-ids.json`
**Commit**: `9dfa563` (runbook update)

**Problem**: Bot requires `config/folder-ids.json` for Google Drive integration, but only example file exists in repo.

**Fix**: Create from example with actual folder IDs:
```bash
cp config/folder-ids.json.example config/folder-ids.json
# Edit with actual Google Drive folder IDs
```

**Structure**:
```json
{
  "leadership": "folder_id",
  "product": "folder_id",
  "marketing": "folder_id",
  "devrel": "folder_id",
  "originals": "folder_id"
}
```

---

### 5. PM2 Environment Variables Not Loading

**Problem**: PM2's `env_file` directive doesn't reliably load environment variables.

**Fix**: Source env file before starting PM2:
```bash
set -a && source secrets/.env.local && set +a
pm2 start ecosystem.config.js --env production
```

**Note**: This is documented in the runbook but should be emphasized more prominently.

---

### 6. SSH Service Name on Ubuntu

**Problem**: Runbook references `sshd.service` which doesn't exist on Ubuntu/Debian.

**Fix**: Use `ssh.service` instead:
```bash
# Ubuntu/Debian
sudo systemctl restart ssh

# RHEL/CentOS
sudo systemctl restart sshd
```

---

## Server Directory Structure After Deployment

```
/opt/devrel-integration/
├── config/
│   ├── folder-ids.json          # Created from example
│   ├── folder-ids.json.example
│   └── ...
├── data/
│   └── auth.db                  # Created at runtime
├── dist/
│   ├── bot.js
│   ├── database/
│   │   └── schema.sql           # Manually copied
│   └── ...
├── docs/
│   ├── prd.md
│   ├── sdd.md
│   ├── sprint.md
│   └── a2a/
├── logs/
│   ├── pm2-combined.log
│   ├── pm2-error.log
│   └── pm2-out.log
├── secrets/
│   ├── .env.local               # chmod 600
│   └── gcp-service-account.json # chmod 600
├── src/
└── ...
```

---

## Recommended Codebase Changes

### High Priority (Prevent Deployment Failures)

1. **Add postbuild script** to copy non-TypeScript assets:
   ```json
   "postbuild": "cp src/database/schema.sql dist/database/"
   ```

2. **Verify DOC_ROOT fix** is in main branch (commit `19bc98a`)

3. **Verify token regex fix** is in main branch (commit `3d31d7e`)

### Medium Priority (Improve Developer Experience)

4. **Create `config/folder-ids.json` template** with placeholder values in repo

5. **Update ecosystem.config.js** to better handle env file loading or document the source workaround

6. **Add pre-deploy validation script** that checks:
   - All required config files exist
   - All required env vars are set
   - Build artifacts are complete

### Low Priority (Documentation)

7. **Update runbook** with Ubuntu-specific SSH service name note

---

## Verification Commands

After deployment, verify with:

```bash
# Process running
pm2 status

# No errors
pm2 logs agentic-base-bot --err --lines 20

# Health check
curl -s http://localhost:3000/health | jq .status

# Discord connection
pm2 logs agentic-base-bot --lines 50 | grep "logged in as"

# Test commands in Discord
/help
/doc prd
/show-sprint
```

---

## Next Steps

1. Merge fixes from `trrfrm-ggl` branch to main
2. Add `postbuild` script to package.json
3. Test deployment on fresh server using updated runbook
4. Consider containerization (Docker) for more reproducible deployments

---

*Report generated during deployment session, December 15, 2024*
