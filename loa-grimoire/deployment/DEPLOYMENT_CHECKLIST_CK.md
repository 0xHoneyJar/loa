# Deployment Checklist: ck Semantic Search Integration

**Version**: v0.8.0
**Date**: 2025-12-27

---

## Pre-Deployment Checks

### 1. Code Quality

- [ ] All tests pass (`tests/run-unit-tests.sh`)
- [ ] CI/CD validation passes (`validate-ck-integration.sh`)
- [ ] Protocol validation passes (`validate-protocols.sh`)
- [ ] No linting errors in shell scripts
- [ ] All scripts have `set -euo pipefail`

### 2. Security Audit

- [ ] Sprint 1 security audit: APPROVED
- [ ] Sprint 2 security audit: APPROVED
- [ ] Sprint 3 security audit: APPROVED
- [ ] Sprint 4 security audit: APPROVED
- [ ] Sprint 5 security audit: APPROVED
- [ ] No hardcoded credentials in any files
- [ ] No secrets in test fixtures
- [ ] Proper file permissions (no world-writable)

### 3. Documentation

- [ ] CHANGELOG.md updated with v0.8.0 entry
- [ ] RELEASE_NOTES_CK_INTEGRATION.md created
- [ ] MIGRATION_GUIDE_CK.md created
- [ ] INSTALLATION.md mentions ck installation
- [ ] README.md updated with semantic search references
- [ ] All 8 protocol documents complete

### 4. Backward Compatibility

- [ ] All existing commands work without ck installed
- [ ] No breaking changes to public API
- [ ] Graceful fallback to grep when ck unavailable
- [ ] User experience parity confirmed

---

## Deployment Steps

### Step 1: Final Validation

```bash
# Run full test suite
./tests/run-unit-tests.sh

# Run CI/CD validation
./.claude/scripts/validate-ck-integration.sh

# Run protocol validation
./.claude/scripts/validate-protocols.sh
```

**Expected**: All checks pass (warnings acceptable, failures block deployment)

### Step 2: Generate Checksums

```bash
# Generate checksums for System Zone files
./.claude/scripts/update.sh --checksums-only

# Verify checksums generated
cat .claude/checksums.json | head -20
```

**Expected**: `.claude/checksums.json` updated with SHA-256 hashes

### Step 3: Update Version

```bash
# Update .loa-version.json
jq '.framework_version = "0.8.0" | .last_updated = "2025-12-27"' \
  .loa-version.json > .loa-version.json.tmp && \
  mv .loa-version.json.tmp .loa-version.json
```

### Step 4: Create Release Commit

```bash
# Stage all changes
git add -A

# Create release commit
git commit -m "chore: bump version to v0.8.0

feat: ck semantic search integration

- Add optional semantic code search via ck tool
- Add Ghost Feature detection (documented but unimplemented)
- Add Shadow System classification (undocumented code)
- Add 8 new protocol documents
- Add 6 new scripts for search orchestration
- Add 127 tests (unit, integration, edge cases)
- Add comprehensive documentation (release notes, migration guide)

No breaking changes. Full backward compatibility maintained.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Step 5: Create Git Tag

```bash
# Create annotated tag
git tag -a v0.8.0 -m "v0.8.0: ck Semantic Search Integration

Highlights:
- Optional semantic code search (ck)
- Ghost Feature detection
- Shadow System classification
- 8 new protocols
- 127 tests

Full backward compatibility. No breaking changes."
```

### Step 6: Push to Remote

```bash
# Push commits
git push origin main

# Push tags
git push origin v0.8.0
```

### Step 7: Create GitHub Release

1. Navigate to: https://github.com/0xHoneyJar/loa/releases/new
2. Select tag: `v0.8.0`
3. Title: `v0.8.0: ck Semantic Search Integration`
4. Description: Copy from RELEASE_NOTES_CK_INTEGRATION.md
5. Mark as latest release
6. Publish release

---

## Post-Deployment Verification

### 1. Fresh Clone Test

```bash
# Clone fresh copy
git clone https://github.com/0xHoneyJar/loa.git loa-test
cd loa-test

# Verify version
cat .loa-version.json | jq '.framework_version'
# Expected: "0.8.0"

# Verify checksums exist
ls -la .claude/checksums.json

# Run validation
./.claude/scripts/validate-ck-integration.sh
```

### 2. Mount Test (Existing Repo)

```bash
# In a separate test repository
curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash

# Verify installation
ls -la .claude/
ls -la loa-grimoire/

# Run /setup and verify ck status shown
```

### 3. Upgrade Test (From v0.7.x)

```bash
# In a v0.7.x installation
./.claude/scripts/update.sh

# Verify migration completed
cat .loa-version.json | jq '.framework_version'
# Expected: "0.8.0"

# Verify new files present
ls -la .claude/protocols/negative-grounding.md
ls -la .claude/scripts/search-orchestrator.sh
```

---

## Rollback Procedure

If critical issues are discovered post-deployment:

### Option A: Revert Commit

```bash
# Revert the release commit
git revert HEAD
git push origin main

# Delete the tag
git tag -d v0.8.0
git push origin :refs/tags/v0.8.0
```

### Option B: Patch Release

```bash
# Create hotfix branch
git checkout -b hotfix/0.8.1

# Fix issues
# ...

# Tag and release
git tag -a v0.8.1 -m "v0.8.1: Hotfix for [issue]"
git push origin hotfix/0.8.1 --tags
```

---

## Success Criteria

| Criterion | Status |
|-----------|--------|
| All tests pass | [ ] |
| CI/CD validation passes | [ ] |
| Security audits approved | [ ] |
| Documentation complete | [ ] |
| Checksums generated | [ ] |
| Version updated | [ ] |
| Tag created | [ ] |
| GitHub release published | [ ] |
| Fresh clone verified | [ ] |
| Mount test verified | [ ] |
| Upgrade test verified | [ ] |

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Developer | | | |
| Reviewer | | | |
| Security | | | |
| Release Manager | | | |

---

Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
