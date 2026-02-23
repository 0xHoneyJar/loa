# Sprint 44 (sprint-1) Implementation Report

> Cycle: cycle-035 — Minimal Footprint by Default — Submodule-First Installation
> Sprint: Foundation — Default Flip + Symlinks + Gitignore
> Implementer: Claude Opus 4.6
> Date: 2026-02-24

## Summary

All 7 tasks completed. Sprint 1 flips Loa's default installation mode from vendored (800+ file copy) to git submodule at `.loa/`, adds 5 missing symlinks, resolves the `.loa/` gitignore collision, adds graceful degradation preflight, and includes 30 unit tests.

## Task Completion

### Task 1.1: Flip SUBMODULE_MODE default ✓

- **File**: `.claude/scripts/mount-loa.sh:183`
- **Change**: `SUBMODULE_MODE=false` → `SUBMODULE_MODE=true`
- **Lines changed**: 1
- **Goal**: G1 (submodule default)

### Task 1.2: Add --vendored flag + deprecate --submodule ✓

- **File**: `.claude/scripts/mount-loa.sh:212-256`
- **Changes**:
  - `--submodule)` case now logs deprecation warning and is a no-op
  - New `--vendored)` case sets `SUBMODULE_MODE=false`
  - Help text rewritten: submodule as default, vendored as opt-in
- **Lines changed**: ~30
- **Goal**: G5 (backward compatibility)

### Task 1.3: Update mode conflict messages ✓

- **File**: `.claude/scripts/mount-loa.sh:1310-1340`
- **Changes**:
  - Standard→submodule conflict now mentions `--migrate-to-submodule` (Sprint 2)
  - Submodule→vendored conflict now mentions `--vendored` flag
  - Language updated for inverted default semantics
- **Lines changed**: ~10
- **Goal**: G5

### Task 1.4: Graceful degradation preflight + mount lock ✓

- **File**: `.claude/scripts/mount-loa.sh:1335-1440`
- **New functions**:
  - `acquire_mount_lock()` / `release_mount_lock()` — PID-based lock at `.claude/.mount-lock` (Flatline IMP-006)
  - `preflight_submodule_environment()` — 5 checks: git present, git repo, git version ≥1.8, symlink support, CI submodule state
  - `record_fallback_reason()` — writes `fallback_reason` to `.loa-version.json` (Flatline SKP-001)
- **Main loop integration**: preflight runs before `route_to_submodule()`, on failure falls back to vendored path
- **CI guard** (Flatline SKP-007): Detects `CI=true` + uninitialized submodule, prints exact fix command
- **Installation summary**: Prints "Installation: submodule" or "Installation: vendored (fallback: <reason>)"
- **Lines added**: ~85
- **Goals**: G1, G5

### Task 1.5: Add missing symlinks to mount-submodule.sh ✓

- **File**: `.claude/scripts/mount-submodule.sh`
- **New symlinks in `create_symlinks()`**:
  - `.claude/hooks/` → `../.loa/.claude/hooks`
  - `.claude/data/` → `../.loa/.claude/data`
  - `.claude/loa/reference/` → `../../.loa/.claude/loa/reference`
  - `.claude/loa/learnings/` → `../../.loa/.claude/loa/learnings`
  - `.claude/loa/feedback-ontology.yaml` → `../../.loa/.claude/loa/feedback-ontology.yaml`
- **New functions**:
  - `relocate_memory_stack()` — copy-then-verify-then-switch (Flatline IMP-002), migration lock, rollback on failure
  - `auto_init_submodule()` — detects registered but uninitialized submodule, runs `git submodule update --init`
- **Preflight updated**: now calls `relocate_memory_stack()` and `auto_init_submodule()` before other checks. `.claude/` directory check relaxed from error to warning (allows mixed user-owned + symlinked content).
- **Lines added**: ~90
- **Goals**: G2, G5

### Task 1.6: Fix .gitignore collision + add symlink entries ✓

- **Files**: `.gitignore` (template), `.claude/scripts/mount-submodule.sh`
- **Changes**:
  - `.loa/` entry in template `.gitignore` replaced with `.loa-cache/` (Memory Stack new home)
  - Comment updated explaining `.loa/` is no longer gitignored (submodule must be tracked)
  - New `update_gitignore_for_submodule()` function in `mount-submodule.sh` — dynamically adds 11 symlink entries to downstream repos' `.gitignore` during mount, removes `.loa/` if present
  - Design note: Symlink entries are NOT in the template `.gitignore` (would conflict with real files in template repo). They are added per-project by mount-submodule.sh.
- **Lines changed**: ~45
- **Goal**: G3

### Task 1.7: Unit tests ✓

- **File**: `.claude/scripts/tests/test-mount-submodule-default.bats`
- **Tests**: 30 test cases covering:
  - Default flip verification (2 tests)
  - `--vendored` flag and `--submodule` deprecation (5 tests)
  - Mode conflict messages (2 tests)
  - Graceful degradation preflight (6 tests)
  - Missing symlinks (8 tests)
  - `.gitignore` fixes (7 tests)
- **Result**: All 30 tests pass
- **Lines**: 197

## Files Modified

| File | Action | Lines Changed |
|------|--------|---------------|
| `.claude/scripts/mount-loa.sh` | Modified | ~130 |
| `.claude/scripts/mount-submodule.sh` | Modified | ~90 |
| `.gitignore` | Modified | ~5 |
| `.claude/scripts/tests/test-mount-submodule-default.bats` | Created | ~200 |

## Test Results

```
30 tests, 30 passed, 0 failed
```

## Acceptance Criteria Status

- [x] Running `/mount` with no flags routes to `mount-submodule.sh` (submodule mode)
- [x] Running `/mount --vendored` routes to standard mode (800+ file copy)
- [x] Running `/mount --submodule` is a no-op (already default) with deprecation log
- [x] `.claude/hooks/`, `.claude/data/`, `.claude/loa/reference/`, `.claude/loa/feedback-ontology.yaml`, `.claude/loa/learnings/` are all symlinked
- [x] `.loa/` is NOT in `.gitignore` (submodule must be tracked)
- [x] `.loa-cache/` IS in `.gitignore` (Memory Stack new home)
- [x] Symlink entries in `.gitignore`
- [x] `@.claude/loa/CLAUDE.loa.md` import resolves through symlink chain (design verified in SDD)
- [x] When git is unavailable, falls back to vendored with warning
- [x] When symlinks not supported, falls back to vendored with warning
- [x] Fallback reason recorded in `.loa-version.json` (Flatline SKP-001)
- [x] Prominent installation mode summary printed
- [x] `.loa/` non-submodule data auto-relocates to `.loa-cache/`
- [x] Memory Stack relocation uses copy-then-verify-then-switch with lock (Flatline IMP-002)
- [x] Concurrent `/mount` prevented by mount lock (Flatline IMP-006)
- [x] All 30 new tests pass

## Risks Mitigated

- **@-import chain**: Symlink chain `.claude/loa/CLAUDE.loa.md` → `../../.loa/.claude/loa/CLAUDE.loa.md` preserves the `@.claude/loa/CLAUDE.loa.md` import pattern.
- **Memory Stack collision**: Auto-relocate with copy-verify-switch prevents data loss.
- **CI failures**: CI guard detects uninitialized submodule and prints exact fix command.
- **Concurrent mount**: PID-based lock file prevents corruption.
