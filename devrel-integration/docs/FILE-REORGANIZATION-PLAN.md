# DevRel Integration File Reorganization Plan

**Version:** 1.0.0
**Created:** 2025-12-14
**Status:** DRAFT - Awaiting Approval
**Risk Level:** LOW (only documentation files being moved)

---

## Executive Summary

This plan reorganizes documentation files in `devrel-integration/` to improve discoverability while **avoiding any breaking changes** to code, builds, or deployment processes.

### Key Principle: ZERO BREAKING CHANGES

- **NO source code modifications**
- **NO config file relocations**
- **NO build system changes**
- **ONLY documentation files are moved**
- **ALL cross-references updated atomically**

---

## Current State Analysis

### Files at Root Level

| File | Category | Can Move? | Reason |
|------|----------|-----------|--------|
| `README.md` | Documentation | NO | Standard entry point for directory |
| `README-SECURITY.md` | Documentation | MAYBE | Security visibility benefit at root |
| `SLASH-COMMANDS-DEPLOYMENT.md` | Documentation | YES | Operational docs belong in `docs/` |
| `ecosystem.config.js` | Config | NO | PM2 requires root location |
| `docker-compose*.yml` (4 files) | Config | NO | Docker requires root location |
| `Dockerfile` | Build | NO | Build system requirement |
| `package.json` | Build | NO | Node.js requirement |
| `package-lock.json` | Build | NO | Node.js requirement |
| `tsconfig.json` | Build | NO | TypeScript requirement |
| `jest.config.js` | Build | NO | Jest requirement |
| `agentic-base-bot.service` | Deployment | YES | Systemd template, not actively used |

### Config Directory - DO NOT TOUCH

The `config/` directory has **5 hardcoded source code references**:

```typescript
// src/cron/dailyDigest.ts:27
path.join(__dirname, '../../config/discord-digest.yml')

// src/services/rbac.ts:32
path.join(__dirname, '../../config/rbac-config.yaml')

// src/services/secrets-rotation-monitor.ts:43
path.join(__dirname, '../../config/secrets-rotation-policy.yaml')

// src/utils/userPreferences.ts:160
path.join(__dirname, '../../config')

// src/schedulers/permission-audit.ts
path.join(__dirname, '../../config/google-service-account.json')
```

Plus Docker and Terraform references:
- `Dockerfile:29` - `COPY config/ ./config/`
- `docker-compose.yml:25` - `./config:/app/config:ro`
- `terraform/modules/workspace/*.tf` - Multiple `../config/` references

**VERDICT: Config directory stays exactly where it is.**

---

## Proposed Changes

### Phase 1: Move SLASH-COMMANDS-DEPLOYMENT.md to docs/

**File:** `SLASH-COMMANDS-DEPLOYMENT.md`
**Destination:** `docs/SLASH-COMMANDS-DEPLOYMENT.md`
**Risk:** LOW

#### Why Move?
- Operational deployment documentation belongs with other docs
- Improves discoverability in `docs/` directory
- No code references this file

#### References to Update

| File | Line | Current Reference | New Reference |
|------|------|-------------------|---------------|
| (none found) | - | - | - |

#### Internal Paths in File (DO NOT UPDATE)
The file contains hardcoded deployment paths like:
- `/home/merlin/Documents/thj/code/agentic-base` (line 25)
- `/opt/devrel-integration/` (lines 48, 53, 63, etc.)

These are **deployment instructions**, not file references. They tell users where to deploy code on the server. **DO NOT CHANGE THESE.**

---

### Phase 2: Move agentic-base-bot.service (OPTIONAL)

**File:** `agentic-base-bot.service`
**Destination:** `docs/deployment/agentic-base-bot.service`
**Risk:** LOW

#### Why Move?
- This is a systemd service template file
- Currently **NOT USED** - deployment uses `ecosystem.config.js` with PM2 instead
- Keeping it as reference documentation

#### References to Update

| File | Line | Current Reference | New Reference |
|------|------|-------------------|---------------|
| `docs/DISASTER-RECOVERY.md` | ~line 38 | Mentions as "Git artifact" | Update path if referenced |

#### Decision: DEFER
This file is not actively used. Moving it adds complexity with minimal benefit. **Recommend keeping at root for now.**

---

### Phase 3: Organize docs/ Subdirectories (FUTURE)

For better organization, consider creating subdirectories in `docs/`:

```
docs/
├── operations/           # Deployment, disaster recovery, slash commands
│   ├── DEPLOYMENT_RUNBOOK.md
│   ├── DISASTER-RECOVERY.md
│   ├── SLASH-COMMANDS-DEPLOYMENT.md
│   └── CREDENTIALS_SETUP_GUIDE.md
├── security/             # Security documentation
│   ├── ANTHROPIC-API-SECURITY.md
│   ├── DISCORD-SECURITY.md
│   ├── GDPR-COMPLIANCE.md
│   └── secrets-rotation.md
├── architecture/         # Architecture and integration
│   ├── devrel-integration-architecture.md
│   ├── integration-architecture.md
│   └── LINEAR_INTEGRATION.md
├── guides/               # User guides and playbooks
│   ├── USER_GUIDE.md
│   ├── team-playbook.md
│   └── tool-setup.md
└── reference/            # Schema and technical reference
    ├── DATABASE-SCHEMA.md
    ├── DOCUMENT-FRONTMATTER.md
    ├── RATE-LIMITING-GUIDE.md
    └── TRANSFORMATION_PIPELINE.md
```

**VERDICT: DEFER** - This requires updating many cross-references. Not recommended for this iteration.

---

## Implementation Plan

### Pre-Flight Checks

```bash
# 1. Verify current git status is clean
cd /home/merlin/Documents/thj/code/agentic-base
git status

# 2. Create backup branch
git checkout -b file-reorg-backup
git checkout trrfrm-ggl

# 3. Verify no references to SLASH-COMMANDS-DEPLOYMENT.md in source code
grep -r "SLASH-COMMANDS-DEPLOYMENT" devrel-integration/src/
# Expected: No results

# 4. Verify no references in other documentation
grep -r "SLASH-COMMANDS-DEPLOYMENT" devrel-integration/docs/
grep -r "SLASH-COMMANDS-DEPLOYMENT" devrel-integration/README.md
# Document any findings
```

### Step 1: Move the File

```bash
cd /home/merlin/Documents/thj/code/agentic-base/devrel-integration

# Move the file
git mv SLASH-COMMANDS-DEPLOYMENT.md docs/SLASH-COMMANDS-DEPLOYMENT.md
```

### Step 2: Verify No Breaking References

```bash
# Search entire repository for references
grep -r "SLASH-COMMANDS-DEPLOYMENT" .

# Expected results:
# - docs/SLASH-COMMANDS-DEPLOYMENT.md (the file itself)
# - This plan document (if committed)
```

### Step 3: Update Any Documentation References

If any documentation references the old path, update them:

```bash
# Example (only if needed):
# sed -i 's|SLASH-COMMANDS-DEPLOYMENT.md|docs/SLASH-COMMANDS-DEPLOYMENT.md|g' README.md
```

### Step 4: Verify Build Still Works

```bash
cd /home/merlin/Documents/thj/code/agentic-base/devrel-integration

# Build the project
npm run build

# Run tests
npm test

# Verify no errors
echo "Build verification: $?"
```

### Step 5: Commit Changes

```bash
git add -A
git commit -m "docs: move SLASH-COMMANDS-DEPLOYMENT.md to docs/ directory

- Reorganize deployment documentation for better discoverability
- No code changes, only documentation file location
- All cross-references verified and updated"
```

---

## Rollback Plan

If any issues are discovered:

```bash
# Option 1: Revert the commit
git revert HEAD

# Option 2: Reset to backup branch
git checkout file-reorg-backup
git branch -D trrfrm-ggl
git checkout -b trrfrm-ggl

# Option 3: Manual restore
git mv docs/SLASH-COMMANDS-DEPLOYMENT.md SLASH-COMMANDS-DEPLOYMENT.md
git commit -m "revert: restore SLASH-COMMANDS-DEPLOYMENT.md to root"
```

---

## Verification Checklist

### Before Migration

- [ ] Git working directory is clean
- [ ] Backup branch created
- [ ] Searched for all references to files being moved
- [ ] Documented all references that need updating
- [ ] Team notified of planned changes (if applicable)

### After Migration

- [ ] File exists at new location
- [ ] File does NOT exist at old location
- [ ] `npm run build` succeeds
- [ ] `npm test` passes
- [ ] No broken links in documentation (manual check)
- [ ] Git diff shows only expected changes
- [ ] Committed with clear message

### Post-Deployment Verification

- [ ] Documentation accessible in GitHub/GitLab UI
- [ ] No team members report broken links
- [ ] No CI/CD pipeline failures

---

## Files NOT Being Moved (Reference)

These files MUST stay at their current locations:

### Root Level (Required by Tools)

| File | Required By | Consequence if Moved |
|------|-------------|---------------------|
| `ecosystem.config.js` | PM2 | Bot won't start |
| `docker-compose.yml` | Docker | Container builds fail |
| `docker-compose.*.yml` | Docker | Environment deploys fail |
| `Dockerfile` | Docker | Image builds fail |
| `package.json` | Node.js | All npm commands fail |
| `package-lock.json` | Node.js | Dependency resolution fails |
| `tsconfig.json` | TypeScript | Build fails |
| `jest.config.js` | Jest | Tests fail |
| `README.md` | Convention | Loses directory documentation |

### Config Directory (Hardcoded in Source)

| File | Referenced By |
|------|---------------|
| `config/discord-digest.yml` | `src/cron/dailyDigest.ts:27` |
| `config/rbac-config.yaml` | `src/services/rbac.ts:32` |
| `config/secrets-rotation-policy.yaml` | `src/services/secrets-rotation-monitor.ts:43` |
| `config/user-preferences.json` | `src/utils/userPreferences.ts:160` |
| `config/google-service-account.json` | `src/schedulers/permission-audit.ts` |
| `config/folder-structure.json` | `terraform/modules/workspace/*.tf` |
| `config/folder-ids.json` | `terraform/modules/workspace/*.tf` |

---

## Decision Matrix

| File | Move? | Effort | Risk | Benefit | Decision |
|------|-------|--------|------|---------|----------|
| `SLASH-COMMANDS-DEPLOYMENT.md` | YES | Low | Low | Medium | APPROVE |
| `agentic-base-bot.service` | NO | Low | Low | Low | DEFER |
| `README-SECURITY.md` | NO | Medium | Medium | Low | REJECT |
| `config/*` | NO | High | Critical | None | REJECT |
| Restructure `docs/` subdirs | NO | High | Medium | Medium | DEFER |

---

## Approval

- [ ] Plan reviewed by team lead
- [ ] No objections raised
- [ ] Approved for implementation

**Approved By:** ________________
**Date:** ________________

---

## Appendix A: Full Reference Search Results

```bash
# Command used:
grep -rn "SLASH-COMMANDS-DEPLOYMENT" /home/merlin/Documents/thj/code/agentic-base/devrel-integration/

# Results:
# (none found outside the file itself)
```

## Appendix B: Config File Reference Audit

Full list of config file references in source code:

```
src/cron/dailyDigest.ts:27:    const configPath = path.join(__dirname, '../../config/discord-digest.yml');
src/services/rbac.ts:32:       const configPath = path.join(__dirname, '../../config/rbac-config.yaml');
src/services/secrets-rotation-monitor.ts:43: policyPath || path.join(__dirname, '../../config/secrets-rotation-policy.yaml')
src/utils/userPreferences.ts:160: this.preferencesDir = preferencesDir || path.join(__dirname, '../../config');
src/schedulers/permission-audit.ts: path.join(__dirname, '../../config/google-service-account.json')
```

---

*End of Plan*
