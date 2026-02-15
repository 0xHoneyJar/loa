# Implementation Report: sprint-bug-331

**Bug**: `20260215-i331-merge-delete`
**Issue**: [#331](https://github.com/0xHoneyJar/loa/issues/331)
**Sprint**: sprint-bug-331 (global: 100)

## Summary

Added a collateral deletion safeguard to `/update-loa` that prevents upstream file cleanup from destroying downstream project files during merge.

## Changes

### Task 1: Collateral Deletion Safeguard

**File**: `.claude/commands/update-loa.md`

| Change | Description |
|--------|-------------|
| Version bump | 1.2.0 → 1.3.0 |
| Phase 5 | Changed from `git merge loa/main -m "..."` to `git merge loa/main --no-commit` |
| Phase 5.3 (NEW) | Collateral deletion safeguard — scans staged deletions, restores non-framework files from HEAD |
| Phase 5.5 (UPDATED) | Adapted from `HEAD~1` to `HEAD` references since merge is now uncommitted |
| Phase 5.7 (NEW) | Explicit commit step after all safeguards |
| Phase 5.8 (RENAMED) | Sync constructs moved from 5.6 to 5.8 to maintain ordering |
| Merge Strategy table | Updated to show `app/`, `grimoires/`, and all non-framework files as auto-preserved via Phase 5.3 |
| Error Handling table | Added entry for safeguard restoration message |

**Framework zone allowlist** (deletions permitted):
- `.claude/*`
- `.loa-version.json`
- `CLAUDE.md`
- `PROCESS.md`
- `.gitattributes`
- `INSTALLATION.md`
- `.loa.config.yaml.example`

Everything outside this list is restored from HEAD if the merge would delete it.

### Task 2: update.sh Verification

**File**: `.claude/scripts/update.sh`

Confirmed safe — line 1316 copies only `.claude/*` and line 1317 copies only `.loa-version.json`. The atomic swap approach never touches downstream files. No code changes needed.

## How the Fix Works

1. `git merge loa/main --no-commit` — stages merge without committing
2. `git diff --cached --diff-filter=D --name-only` — identifies all staged deletions
3. For each deletion, check if the file is in the framework zone allowlist
4. If not in allowlist → `git checkout HEAD -- "$file"` restores it from pre-merge state
5. Phase 5.5 handles workflow files (defense-in-depth)
6. `git commit -m "chore: update Loa framework"` — commits the safeguarded merge

## Test Verification

The fix is in a Claude Code command definition (markdown), so there's no executable code to unit test directly. The safeguard is verified by the logic:

- `git diff --cached --diff-filter=D` correctly identifies staged deletions in a `--no-commit` merge
- `git checkout HEAD -- "$file"` correctly restores files from the pre-merge branch tip
- The case statement correctly matches framework zone paths using glob patterns
- The merge commit maintains proper merge parents (merge relationship preserved)

## Acceptance Criteria Status

- [x] Phase 5 uses `--no-commit` flag
- [x] Phase 5.3 checks all staged deletions
- [x] Non-framework deletions are restored from HEAD
- [x] Framework deletions propagate normally
- [x] Merge commit created after safeguard (Phase 5.7)
- [x] update.sh confirmed safe (only copies .claude/ contents)
