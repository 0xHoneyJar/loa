# Documentation Directory Refactoring Plan

**Date**: December 15, 2024
**Branch**: trrfrm-ggl
**Status**: PLANNING

---

## Executive Summary

This plan addresses the consolidation of documentation into `devrel-integration/docs/` to eliminate directory drift between the deployment server and codebase. The refactoring involves two scopes:

1. **Code Changes** (CRITICAL) - Fix runtime path references in bot code
2. **Documentation Updates** (MEDIUM) - Update references in CLAUDE.md, README.md, and agent prompts

---

## Scope Analysis

### Scope 1: Code Files Requiring Changes (CRITICAL - Runtime Impact)

These files contain hardcoded paths that affect bot functionality at runtime:

| File | Line | Current Path | Issue | Fix Required |
|------|------|--------------|-------|--------------|
| `src/handlers/commands.ts` | 247 | `../../../docs` | **WRONG** - Resolves outside project | Change to `../../docs` |
| `src/handlers/interactions.ts` | 296 | `../../docs` | **CORRECT** - Already fixed | None |

**Analysis**:
- `commands.ts` runs from `dist/handlers/commands.js`
- `path.resolve('/opt/devrel-integration/dist/handlers', '../../../docs')` = `/opt/docs` (WRONG)
- `path.resolve('/opt/devrel-integration/dist/handlers', '../../docs')` = `/opt/devrel-integration/docs` (CORRECT)

### Scope 2: Framework Documentation (MEDIUM - No Runtime Impact)

These files reference `docs/` paths in the base framework. They describe the generic workflow but don't affect the devrel-integration deployment:

**Root-level files:**
- `CLAUDE.md` - 100+ references to `docs/`
- `README.md` - 30+ references to `docs/`
- `.gitignore` - References to ignored docs paths
- `.trufflehog.yaml` - Security scanning ignore paths
- `.gitleaksignore` - Secret scanning ignore paths

**Agent/Command definitions:**
- `.claude/agents/prd-architect.md`
- `.claude/agents/architecture-designer.md`
- `.claude/agents/sprint-planner.md`
- `.claude/agents/sprint-task-implementer.md`
- `.claude/agents/devops-crypto-architect.md`
- `.claude/agents/senior-tech-lead-reviewer.md`
- `.claude/agents/paranoid-auditor.md`
- `.claude/commands/review-sprint.md`
- `.claude/commands/implement.md`
- `.claude/commands/audit-sprint.md`
- `.claude/commands/audit-deployment.md`
- `.claude/commands/translate.md`
- `.claude/commands/audit.md`

---

## Decision Required: Documentation Strategy

### Option A: Dual Documentation Structure (Recommended)

Keep the base framework documentation pointing to `docs/` as the generic pattern, but update **devrel-integration specific** code and documentation to use `devrel-integration/docs/`.

**Rationale**:
- The base framework (`agentic-base`) is a template for creating projects
- Each project instantiation would have its own `docs/` directory structure
- `devrel-integration/` is just one such project instance
- Changing 100+ references in agent prompts would break the template nature

**Changes Required**:
1. Fix `commands.ts` path (1 line)
2. Update `devrel-integration/docs/DEPLOYMENT_RUNBOOK.md` to clarify docs location
3. Keep CLAUDE.md/README.md referencing generic `docs/` structure

### Option B: Full Migration to devrel-integration/docs/

Update ALL references to point to `devrel-integration/docs/`.

**Rationale**:
- Single source of truth
- No confusion about where docs live

**Problems**:
- Breaks the template nature of agentic-base
- 100+ file changes across agent definitions
- Makes framework less reusable for other projects

---

## Recommended Implementation Plan

### Phase 1: Critical Code Fix (Immediate)

**File**: `devrel-integration/src/handlers/commands.ts:247`

```typescript
// Before (WRONG)
const DOC_ROOT = path.resolve(__dirname, '../../../docs');

// After (CORRECT)
const DOC_ROOT = path.resolve(__dirname, '../../docs');
```

**Verification**:
```bash
# On server after deployment
node -e "const path = require('path'); console.log(path.resolve('/opt/devrel-integration/dist/handlers', '../../docs'))"
# Should output: /opt/devrel-integration/docs
```

### Phase 2: Deployment Documentation (Immediate)

Update `devrel-integration/docs/DEPLOYMENT_RUNBOOK.md` with:

1. Clear statement that docs live in `devrel-integration/docs/`
2. Server directory structure showing docs location
3. Verification command for /doc command

### Phase 3: Framework Documentation (Deferred)

**Decision**: Do NOT update CLAUDE.md, README.md, or agent prompts.

**Rationale**: The base framework describes a generic pattern where each project has its own `docs/` directory. The devrel-integration is one such project, and its docs correctly live in `devrel-integration/docs/`.

Add a clarifying note to CLAUDE.md:

```markdown
**Note**: This is a base framework repository. When using this framework:
- Framework-level docs (generic patterns): `docs/`
- Project-specific docs: `<project>/docs/` (e.g., `devrel-integration/docs/`)
```

---

## Security Audit Checklist

Before implementing, verify:

- [ ] Path traversal protection still works after change
- [ ] DOC_ROOT validation prevents `..` injection
- [ ] File whitelist (`prd`, `sdd`, `sprint`) is enforced
- [ ] No user input directly concatenated with paths
- [ ] Resolved path checked against allowed directory

**Current security in `commands.ts`**:
```typescript
// Line 265-270 - Path traversal protection
if (!docPath.startsWith(DOC_ROOT)) {
  logger.error('Path traversal attempt detected', {
    user: message.author.id,
    docType,
```

This protection will continue to work with the new path.

---

## Testing Plan

### Local Testing
```bash
cd devrel-integration
npm run build
# Verify path resolution
node -e "const path = require('path'); console.log('DOC_ROOT:', path.resolve(__dirname + '/dist/handlers', '../../docs'))"
```

### Server Testing
```bash
# After deployment
curl -s http://localhost:3000/health | jq .status
# Test /doc command in Discord
/doc prd
/doc sdd
/doc sprint
```

---

## Rollback Plan

If issues arise:
```bash
# Revert the single line change
git checkout HEAD~1 -- devrel-integration/src/handlers/commands.ts
npm run build
pm2 restart agentic-base-bot
```

---

## Next Steps

1. **User Approval**: Confirm Option A (dual structure) or Option B (full migration)
2. **Implement Phase 1**: Fix commands.ts path
3. **Deploy to Server**: Pull changes, rebuild, restart PM2
4. **Verify**: Test /doc command in Discord
5. **Document**: Update runbook with verification steps

---

*Plan created by DevOps and Auditor agents, December 15, 2024*
