# Sprint-45 (Sprint 2) Implementation Report

**Cycle**: 035 — Minimal Footprint by Default: Submodule-First Installation
**Sprint**: 2 — Migration + Polish
**Branch**: feat/cycle-030-ux-redesign
**Date**: 2026-02-24

---

## Task Summary

| Task | Status | Files Modified | Lines Changed |
|------|--------|----------------|---------------|
| 2.1: `--migrate-to-submodule` command | DONE | `mount-loa.sh` | +178 (new function + arg parser) |
| 2.2: `apply_stealth()` expansion (4 -> 14) | DONE | `mount-loa.sh` | +8, -4 |
| 2.3: `get_memory_stack_path()` utility | DONE | `mount-submodule.sh` | +28 |
| 2.4: `/loa` status boundary report | DONE | `golden-path.sh` | +63 |
| 2.5: `/update-loa` submodule support | DONE | `update-loa.sh` (NEW) | +232 |
| 2.6: `verify_and_reconcile_symlinks()` | DONE | `mount-submodule.sh` | +143 |
| 2.7: Documentation updates | DONE | `INSTALLATION.md`, `README.md`, `PROCESS.md` | +74, -20 |
| 2.8: Migration + stealth tests | DONE | `test-migration.bats`, `test-stealth-expansion.bats` (NEW) | +211 |

---

## Task Details

### Task 2.1: Implement `--migrate-to-submodule` command

**File**: `.claude/scripts/mount-loa.sh`

**Changes**:
- Added `MIGRATE_TO_SUBMODULE=false` and `MIGRATE_APPLY=false` variables
- Added `--migrate-to-submodule` and `--apply` to argument parser
- Added help text for migration flags
- Added `migrate_to_submodule()` function (~140 lines) with workflow:
  - Detect current mode from `.loa-version.json`
  - Require clean working tree (error with `git stash` instruction)
  - Discovery phase: classify files as FRAMEWORK / USER_MODIFIED / USER_OWNED
  - Print classification report
  - DRY RUN mode exits after report (default, Flatline SKP-004)
  - APPLY mode: backup -> git rm -> submodule add -> symlinks -> restore -> commit
- Added routing in `main()` to call `migrate_to_submodule` when flag is set

### Task 2.2: Expand `apply_stealth()` from 4 to 14 entries

**File**: `.claude/scripts/mount-loa.sh` (lines ~1006-1020)

**Changes**:
- Replaced single `entries` array with `core_entries` (4) + `doc_entries` (10)
- Core: `grimoires/loa/`, `.beads/`, `.loa-version.json`, `.loa.config.yaml`
- Doc: `PROCESS.md`, `CHANGELOG.md`, `INSTALLATION.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE.md`, `BUTTERFREEZONE.md`, `.reviewignore`, `.trufflehog.yaml`, `.gitleaksignore`
- Combined into `all_entries` for iteration
- Log shows total count: `Stealth mode applied (14 entries)`
- Idempotent: `grep -qxF` before append (unchanged)

### Task 2.3: Implement Memory Stack relocation utility

**File**: `.claude/scripts/mount-submodule.sh` (new function before `relocate_memory_stack`)

**Changes**:
- Added `get_memory_stack_path()` function
- Checks `.loa-cache/` (new location, priority 1) then `.loa/` (legacy, priority 2)
- Detects `.loa/` as submodule vs Memory Stack data via `.gitmodules` check
- Returns path on stdout, exit 0 if found, exit 1 if no Memory Stack
- Reusable: uses `PROJECT_ROOT` with fallback to `git rev-parse --show-toplevel`

### Task 2.4: Implement `/loa` status boundary report

**File**: `.claude/scripts/golden-path.sh`

**Changes**:
- Added `golden_detect_install_mode()` function: returns "submodule" | "vendored" | "unknown"
- Added `golden_boundary_report()` function: generates multi-line report including:
  - Installation mode
  - Framework version
  - Commit hash (submodule mode)
  - Submodule path and file count
  - Tracked `.claude/` file count
  - Gitignored `.claude/` file count
  - User-owned tracked files list

### Task 2.5: Implement `/update-loa` submodule support

**File**: `.claude/scripts/update-loa.sh` (NEW, 232 lines)

**Changes**:
- Created unified update script that detects mode and routes appropriately
- Submodule mode: `git fetch` -> checkout tag/ref -> update `.loa-version.json` -> reconcile symlinks
- Vendored mode: delegates to existing `update.sh`
- Supply chain integrity (Flatline SKP-005):
  - Allowlist of expected remote URLs
  - HTTPS enforcement
  - Commit hash recording in `.loa-version.json`
- CI flags: `--require-submodule`, `--require-verified-origin`
- Pins to tagged releases by default (not branch HEAD)

### Task 2.6: Implement `verify_and_reconcile_symlinks()`

**File**: `.claude/scripts/mount-submodule.sh`

**Changes**:
- Added `verify_and_reconcile_symlinks()` function (~100 lines)
  - Authoritative manifest with 3 phases: directory symlinks, file/nested symlinks, per-skill symlinks
  - Dynamic per-skill and per-command symlink discovery
  - Canonical path resolver via `realpath` (Flatline SKP-002)
  - Detects dangling -> removes -> recreates from manifest
  - Reports counts: ok, dangling, missing, fixed
- Added `check_symlinks_subcommand()` for standalone health check
- Added `--check-symlinks`, `--reconcile`, `--source-only` arguments
- Added `CHECK_SYMLINKS`, `RECONCILE_SYMLINKS`, `SOURCE_ONLY` variables
- Updated main() routing for subcommands

### Task 2.7: Update documentation

**Files**: `INSTALLATION.md`, `README.md`, `PROCESS.md`

**INSTALLATION.md changes**:
- Rewritten intro to list 3 methods: submodule (default), clone template, vendored (legacy)
- Method 1 rewritten as "Submodule Mode (Default)" with:
  - One-line install (same curl command, now routes to submodule)
  - Manual install steps using `git submodule add`
  - Pin to version examples
  - Updated "What Gets Installed" directory tree showing `.loa/` submodule + symlinks
- Added "Method 3: Vendored Mode (Legacy)" with `--vendored` flag
- Added "Migrating from Vendored to Submodule" section with dry-run/apply examples

**README.md changes**:
- Updated Quick Start install command with submodule context
- Added pin-to-version example
- Updated post-install description to mention `.loa/` submodule

**PROCESS.md changes**:
- Updated Helper Scripts section to include `mount-submodule.sh` and `update-loa.sh`

### Task 2.8: Migration tests + stealth tests

**Files**:
- `.claude/scripts/tests/test-migration.bats` (NEW, 97 lines)
- `.claude/scripts/tests/test-stealth-expansion.bats` (NEW, 114 lines)

**test-migration.bats** (13 tests):
- Argument parser: `--migrate-to-submodule`, `--apply`, variable defaults
- Function exists: `migrate_to_submodule()`
- Backup creation, settings preservation, commands preservation, overrides preservation
- Already-submodule exit, dry-run no-modify
- Help text coverage

**test-stealth-expansion.bats** (17 tests):
- Core entries (4): grimoires/loa/, .beads/, .loa-version.json, .loa.config.yaml
- Doc entries (10): PROCESS.md through .gitleaksignore
- Idempotency: grep -qxF
- Entry count in log
- Standard mode skips stealth

---

## Test Results

```
test-migration.bats:              13/13 passed
test-stealth-expansion.bats:      17/17 passed
test-mount-submodule-default.bats: 30/30 passed (sprint-1, regression check)
```

**Total: 60/60 tests passed. Zero regressions.**

---

## Acceptance Criteria Checklist

- [x] `/mount --migrate-to-submodule` defaults to dry-run mode; requires `--apply` to execute (Flatline SKP-004)
- [x] Migration preserves: `.loa.config.yaml`, `.claude/settings.json`, `.claude/commands/`, `.claude/overrides/`
- [x] Migration creates timestamped backup at `.claude.backup.{timestamp}/`
- [x] Migration with `--dry-run` (default) shows classification report without changes
- [x] Migration requires clean working tree (dirty -> error with `git stash` instruction)
- [x] Migration classifies files: FRAMEWORK (remove), USER_MODIFIED (flag), USER_OWNED (preserve)
- [x] Single-command rollback documented: `git checkout <pre-migration-commit>`
- [x] `apply_stealth()` adds 14 entries (4 core + 10 doc) -- no duplicates on re-run
- [x] `/loa` shows installation mode (submodule vs vendored), commit hash, file counts
- [x] `/update-loa` in submodule mode: fetches, checks out, verifies symlinks
- [x] `verify_and_reconcile_symlinks()` detects dangling symlinks, removes stale, recreates from manifest
- [x] Supply chain integrity: allowlist expected remote URL, enforce HTTPS, record commit hash (Flatline SKP-005)
- [x] CI mode: `--require-submodule` + `--require-verified-origin` flags fail closed on mismatch
- [x] INSTALLATION.md updated with submodule-first quickstart

---

## Files Modified/Created

| File | Action | Zone |
|------|--------|------|
| `.claude/scripts/mount-loa.sh` | Modified | System |
| `.claude/scripts/mount-submodule.sh` | Modified | System |
| `.claude/scripts/golden-path.sh` | Modified | System |
| `.claude/scripts/update-loa.sh` | Created | System |
| `.claude/scripts/tests/test-migration.bats` | Created | System |
| `.claude/scripts/tests/test-stealth-expansion.bats` | Created | System |
| `INSTALLATION.md` | Modified | Root |
| `README.md` | Modified | Root |
| `PROCESS.md` | Modified | Root |
| `grimoires/loa/a2a/sprint-45/reviewer.md` | Created | State |
