# Implementation Report — Sprint 58 (Cycle 038, Local Sprint 2)

**Sprint**: Migration Script + Mount Integration
**Date**: 2026-02-24
**Commit**: fbda6ef

## Summary

Sprint 2 delivers the state layout migration script and integrates it with mount-submodule.sh and mount-loa.sh. It also addresses the Sprint 1 audit MEDIUM finding (workspace-escape validation) and the review observation (duplicated validation logic).

## Tasks Completed

### Task 0: Sprint 1 Audit MEDIUM Fix — Workspace-Escape Validation
**File**: `.claude/scripts/path-lib.sh`
- Added `LOA_STATE_DIR` workspace-escape validation to `_validate_paths()` (lines 314-326)
- Uses `realpath -m` to canonicalize path, then checks prefix against `$PROJECT_ROOT`
- Skips validation when `LOA_ALLOW_ABSOLUTE_STATE=1` (intentionally outside workspace)
- Refactored `_read_config_paths()` to delegate state-dir env validation to `_resolve_state_dir_from_env()` instead of duplicating the logic (review observation)

### Task 1: Create migrate-state-layout.sh (FR-5 — High)
**File**: `.claude/scripts/migrate-state-layout.sh`
- `--dry-run` (default): Shows migration plan with file counts, sizes, SQLite integrity status
- `--apply`: Executes copy-verify-switch migration with full verification
- `--compat-mode auto|resolution|symlink|copy`: Platform-aware selection
  - `auto`: Tests symlink support in temp dir, resolves to `resolution` or `copy`
  - `resolution`: Removes old dirs after verified migration (cleanest)
  - `symlink`: Replaces old dirs with symlinks (backward compat)
  - `copy`: Keeps both locations (safest)
- Locking: JSON lock file at repo root with PID, hostname, timestamp. Stale lock detection via `kill -0`. `--force` flag to override.
- Journal-based crash recovery: `.loa-state/.migration-journal.json` tracks per-source state (pending → copying → verified → migrated). Resume from last checkpoint on re-run.
- Verification: sha256 checksums of all files, file count comparison, permission comparison via `stat -c %a`
- Atomic staging: Copies to `.loa-state/.migration-staging/{target}/` first, then moves into place
- Rollback: On verification failure, staged copies removed, originals untouched
- EXIT trap: Releases lock, clears maintenance marker, removes staging dir
- SQLite: `PRAGMA integrity_check` on all `.db` files after copy
- Maintenance marker: `.loa-state/.maintenance` prevents concurrent script access during migration
- Updates `.loa-version.json` with `state_layout_version: 2` on success
- Sources: `.beads/` → `beads/`, `.ck/` → `ck/`, `.run/` → `run/`, `grimoires/loa/memory/` → `memory/`

### Task 2: Update mount-submodule.sh for state structure (FR-1 — Medium)
**File**: `.claude/scripts/mount-submodule.sh`
- `init_state_zone()` now calls `ensure_state_structure()` after grimoire setup (via sourcing bootstrap.sh in subshell)
- Detects layout v1 via `detect_state_layout()` and prints migration suggestion with commands
- Does NOT auto-migrate (prompt only, per AC)

### Task 3: Update .gitignore management (FR-1 — Low)
**File**: `.claude/scripts/mount-loa.sh`
- Added `.loa-state/` and `.run/` to stealth mode `core_entries` array
- Old entries (`.beads/`, `.ck/`) kept alongside during migration grace period
- `sync_zones()` now calls `ensure_state_structure()` to create `.loa-state/` on vendored mount

### Task 4: Migration tests (FR-5 — Medium)
**File**: `tests/unit/test-migrate-state-layout.sh`
- 16 assertions across 9 test scenarios:
  1. Dry run: Doesn't create migration, preserves originals
  2. Apply: Migrates files with sha256 checksum verification, removes originals in resolution mode
  3. Rollback: Simulated failure (read-only target) preserves originals
  4. Lock: Active PID prevents concurrent migration
  5. Stale lock: Dead PID detected and overridden with --force
  6. Journal resume: Picks up from last verified source, cleans up journal after completion
  7. Compat auto-detection: Works on current platform
  8. SQLite integrity: Creates valid DB, verifies integrity after copy
  9. Permissions: 755 and 644 permissions preserved through migration

## Test Results

| Test Suite | Result |
|------------|--------|
| test-path-lib-state.sh | 22/22 PASS |
| test-state-path-conformance.sh | 0 hard failures, 225 baseline |
| test-migrate-state-layout.sh | 16/16 PASS |

## Files Changed

| File | Change |
|------|--------|
| `.claude/scripts/path-lib.sh` | +16 lines (workspace-escape validation + refactor) |
| `.claude/scripts/migrate-state-layout.sh` | +480 lines (new file) |
| `.claude/scripts/mount-submodule.sh` | +27 lines (state structure init) |
| `.claude/scripts/mount-loa.sh` | +14 lines (gitignore + state init) |
| `tests/unit/test-migrate-state-layout.sh` | +397 lines (new file) |
