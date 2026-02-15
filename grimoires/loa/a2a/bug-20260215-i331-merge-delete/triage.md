# Bug Triage: cycle-014 merge deletes 933 downstream project files

**Bug ID**: `20260215-i331-merge-delete`
**Issue**: [#331](https://github.com/0xHoneyJar/loa/issues/331)
**Severity**: CRITICAL (P0)
**Reporter**: @zkSoju
**Triaged**: 2026-02-15

## Problem Statement

Running `/update-loa` from main after cycle-014 attempts to delete **933 files** (177,233 lines) from downstream projects, including all application source code. A naive merge would **destroy the entire downstream application**.

## Root Cause

The `/update-loa` command (`.claude/commands/update-loa.md`) instructs Claude to execute `git merge loa/main`. When cycle-014 cleaned non-framework files from the Loa repo, git's 3-way merge interprets those removals as intentional deletions and propagates them to downstream projects.

### Protection Gap

| Path | Protected? | Mechanism |
|------|-----------|-----------|
| `README.md` | Yes | `.gitattributes` merge=ours |
| `CHANGELOG.md` | Yes | `.gitattributes` merge=ours |
| `.github/workflows/` | Yes | `.gitattributes` merge=ours + Phase 5.5 revert |
| `app/`, `src/`, `lib/` | **NO** | Nothing |
| `grimoires/` | **NO** | Nothing |
| `components/`, `hooks/`, `types/` | **NO** | Nothing |
| `.loa.config.yaml` | **NO** | Nothing |

### Safe Path Exists

`.claude/scripts/update.sh` uses an atomic swap approach that ONLY copies `.claude/` contents. This path is already safe. The bug is exclusively in the merge-based `/update-loa` command path.

## Evidence

- **Repro**: Run `/update-loa` on `0xHoneyJar/midi-interface` after cycle-014 merge to main
- **Impact**: 334 project source files + 77 .claude/ construct files marked for deletion
- **Output**: `957 files changed, 3565 insertions(+), 177233 deletions(-)`
- **Workaround**: `git merge -s ours --no-commit` + selective `git checkout loa/main -- <file>`

## Fix Strategy

### Approach: Collateral Deletion Safeguard

Add a **post-merge, pre-commit deletion safeguard** to `/update-loa`:

1. Change `git merge loa/main` to `git merge loa/main --no-commit`
2. After merge but before commit, scan for deleted files outside the framework zone
3. Restore any non-framework files from HEAD (pre-merge state)
4. Then commit

**Framework zone allowlist** (deletions OK):
- `.claude/**`
- `.loa-version.json`
- `CLAUDE.md`
- `PROCESS.md`
- `.gitattributes`
- `INSTALLATION.md`
- `.loa.config.yaml.example`

Any deletion outside this list is restored from HEAD before commit.

### Files to Modify

| File | Change |
|------|--------|
| `.claude/commands/update-loa.md` | Replace Phase 5 with safeguarded merge; add Phase 5.3 (deletion safeguard) |
| `.gitattributes` | No change needed if safeguard is implemented in command |

## Acceptance Criteria

1. `/update-loa` merging from a branch that deleted non-framework files does NOT delete downstream project files
2. Framework file updates (`.claude/**`) still propagate correctly
3. Merge commit maintains proper git history (merge parent)
4. Phase 5.5 (.github/workflows/ revert) still works
5. Downstream project files that were never in upstream are unaffected (no regression)

## Test Strategy

Verify the safeguard by testing:
- Mock merge where upstream deleted app/ files — downstream app/ preserved
- Mock merge where upstream updated .claude/ files — .claude/ updated correctly
- Mock merge where upstream deleted .claude/ files — deletions propagate (framework zone)
- Existing Phase 5.5 workflow revert still functions
