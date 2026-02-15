# Sprint: bug-331 — Fix /update-loa collateral deletion

**Bug**: `20260215-i331-merge-delete`
**Issue**: [#331](https://github.com/0xHoneyJar/loa/issues/331)
**Severity**: CRITICAL
**Global Sprint ID**: 100

## Sprint Goal

Prevent `/update-loa` from deleting downstream project files when merging upstream changes that include file cleanup.

## Tasks

### Task 1: Add collateral deletion safeguard to /update-loa command

**File**: `.claude/commands/update-loa.md`

**Changes**:
1. Modify Phase 5 to use `git merge loa/main --no-commit` instead of direct merge
2. Add new Phase 5.3: Collateral Deletion Safeguard
   - After merge (before commit), identify all staged deletions via `git diff --cached --diff-filter=D --name-only`
   - Define framework zone allowlist: `.claude/**`, `.loa-version.json`, `CLAUDE.md`, `PROCESS.md`, `.gitattributes`, `INSTALLATION.md`, `.loa.config.yaml.example`
   - For any deletion outside the framework zone, restore the file from HEAD: `git checkout HEAD -- <file>`
   - Log count of restored files
3. Phase 5.5 (.github/workflows/ revert) is subsumed by the more general safeguard but should remain as defense-in-depth

**Acceptance Criteria**:
- [ ] Phase 5 uses `--no-commit` flag
- [ ] Phase 5.3 checks all staged deletions
- [ ] Non-framework deletions are restored from HEAD
- [ ] Framework deletions propagate normally
- [ ] Merge commit created after safeguard

### Task 2: Verify update.sh is not affected

**File**: `.claude/scripts/update.sh`

**Verification**: Confirm that `update.sh` Stage 5 (Atomic Swap) only touches `.claude/` and `.loa-version.json`. No code changes needed — just verification and documentation comment if helpful.

**Acceptance Criteria**:
- [ ] update.sh confirmed safe (only copies .claude/ contents)

## Out of Scope

- Changing the fundamental merge-based approach to staging-based
- Adding .gitattributes rules for all possible downstream paths
- Fixing the downstream project's current state (manual recovery needed)
