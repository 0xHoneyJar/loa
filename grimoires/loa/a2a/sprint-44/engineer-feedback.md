# Sprint 44 (sprint-1) Engineer Feedback

> Reviewer: Senior Technical Lead (Claude Opus 4.6)
> Date: 2026-02-24
> Cycle: cycle-035 — Minimal Footprint by Default
> Sprint: Foundation — Default Flip + Symlinks + Gitignore

## Verdict: Conditional Pass — 2 Required Fixes, 3 Advisories

The implementation is solid overall. All 30 tests pass. The core architecture is correct: submodule default flip, flag inversion, graceful degradation, mount lock, Memory Stack relocation, missing symlinks, and gitignore collision resolution are all present and well-structured. Two issues require fixes before merge; three additional items are advisories for improvement.

---

## Required Fixes

### RF-1: Hidden files (dotfiles) dropped during Memory Stack relocation

**File**: `/home/merlin/Documents/thj/code/loa/.claude/scripts/mount-submodule.sh`
**Lines**: 165-167

**Problem**: The glob `"$source"/*` on line 167 does NOT match hidden files (dotfiles). If `.loa/` contains files like `.gitkeep`, `.cache`, `.env`, etc., they will not be copied. However, `find "$source" -type f` on line 165 counts ALL files including hidden ones. This produces a count mismatch causing a spurious verification failure and rollback, even though the operation was partially successful.

**Scenario**: User has `.loa/.gitkeep` and `.loa/data/embeddings.db`. The `find` counts 2 files. The `cp -r "$source"/*` copies only `data/embeddings.db` (1 file). Verification finds 1 != 2, rolls back, and the user gets a confusing error.

**Fix**:
```bash
# Line 167: Replace glob with explicit find-based copy or use dotglob
# Option A (preferred — portable):
if ! cp -r "$source"/. "$target"/ 2>/dev/null; then

# Option B (bash-specific):
# shopt -s dotglob
# if ! cp -r "$source"/* "$target"/ 2>/dev/null; then
# shopt -u dotglob
```

Using `"$source"/.` copies the CONTENTS of the source directory including hidden files, which is the POSIX-portable idiom for this operation. This is the recommended fix.

**Severity**: HIGH — data loss scenario. If the Memory Stack directory contains any dotfiles (which is common for cache directories), relocation will always fail.

---

### RF-2: EXIT trap override silently drops the `_exit_handler`

**File**: `/home/merlin/Documents/thj/code/loa/.claude/scripts/mount-loa.sh`
**Lines**: 169, 1563

**Problem**: Line 169 sets `trap '_exit_handler' EXIT` for structured error handling. Line 1563 sets `trap 'release_mount_lock' EXIT` which **replaces** the previous EXIT trap entirely. If the script fails after line 1563 but before `exec` to mount-submodule.sh (e.g., during `check_mode_conflicts` on line 1572), the `_exit_handler` will not run, and the user gets no structured error JSON output.

This also means: if `preflight_submodule_environment` passes but falls through to vendored mode for any other reason, the `_exit_handler` is gone for the entire vendored path. Any error in the vendored flow after this point produces an unstructured failure.

**Fix**: Combine both handlers in the trap:
```bash
# Line 1563: Replace:
trap 'release_mount_lock' EXIT

# With:
trap 'release_mount_lock; _exit_handler' EXIT
```

Or more defensively, wrap `_exit_handler` so it captures exit code before `release_mount_lock` modifies state:
```bash
trap 'local _ec=$?; release_mount_lock; exit $_ec' EXIT
```

Since `_exit_handler` checks `$?` at entry, the simplest correct fix is:
```bash
trap 'release_mount_lock; _exit_handler' EXIT
```

**Severity**: MEDIUM — affects error reporting quality in the submodule-to-vendored fallback path and the check_mode_conflicts error path.

---

## Advisories (Non-Blocking)

### ADV-1: Regex dot in grep patterns for `.loa` matching

**File**: `/home/merlin/Documents/thj/code/loa/.claude/scripts/mount-loa.sh:1406`
**File**: `/home/merlin/Documents/thj/code/loa/.claude/scripts/mount-submodule.sh:142`

Both files use `grep -q ".loa"` or `grep -q "$source"` (where `$source=".loa"`) to check `.gitmodules`. The `.` in `.loa` is a regex wildcard that matches any character, so it would also match hypothetical entries like `xloa` or `aloa`. This is a correctness nitpick -- in practice `.gitmodules` will never have such entries.

**Recommendation**: Use `grep -qF ".loa"` (fixed string) or `grep -q '\.loa'` (escaped dot) for correctness.

### ADV-2: `cp -r` error suppressed on empty source directory

**File**: `/home/merlin/Documents/thj/code/loa/.claude/scripts/mount-submodule.sh:167`

If `.loa/` exists but is empty (0 files), `cp -r "$source"/*` will fail because the glob expands to nothing (or to the literal `*` string with `set -u`). The `2>/dev/null` suppresses this, and then `source_count` is 0, `target_count` is 0, so verification "passes" and the empty directory is removed. This works correctly by accident, but the logic is fragile.

**Recommendation**: Add an early return for empty directories:
```bash
if [[ "$source_count" -eq 0 ]]; then
  rm -rf "$source"
  log "Memory Stack was empty, removed .loa/"
  rm -f "$migration_lock"
  return 0
fi
```

### ADV-3: Test depth is surface-level (grep-only tests)

All 30 tests are grep-based (checking that strings/patterns exist in the source files) rather than integration tests that actually execute the mount flow. This is acceptable for sprint-1 as a smoke test suite, but it means:

- No test actually runs `mount-loa.sh` with `--vendored` and verifies `SUBMODULE_MODE` is false at runtime
- No test runs the Memory Stack relocation against a real temp directory
- No test verifies symlinks are actually created end-to-end

These should be added in sprint-2 or sprint-3. The current tests verify code structure, not behavior.

---

## Acceptance Criteria Verification

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `/mount` with no flags routes to submodule | PASS | `mount-loa.sh:183` sets `SUBMODULE_MODE=true`; `main()` at line 1560-1574 routes to `route_to_submodule()` |
| 2 | `/mount --vendored` routes to standard mode | PASS | `mount-loa.sh:217-219` sets `SUBMODULE_MODE=false`; `main()` skips submodule block |
| 3 | `/mount --submodule` is no-op with deprecation | PASS | `mount-loa.sh:212-216` logs deprecation warning, does not change `SUBMODULE_MODE` |
| 4 | All 5 missing symlinks added | PASS | `mount-submodule.sh:404-443` adds hooks, data, reference, learnings, feedback-ontology via `safe_symlink()` |
| 5 | `.loa/` NOT in `.gitignore` | PASS | `.gitignore:73-76` replaced `.loa/` with `.loa-cache/` and added comment explaining why |
| 6 | `.loa-cache/` IS in `.gitignore` | PASS | `.gitignore:76` contains `.loa-cache/` |
| 7 | Symlink entries in downstream .gitignore | PASS | `mount-submodule.sh:690-735` `update_gitignore_for_submodule()` adds 11 entries |
| 8 | Graceful degradation (git unavailable) | PASS | `mount-loa.sh:1370-1373` checks `command -v git`, sets fallback reason, returns 1 |
| 9 | Graceful degradation (symlinks unsupported) | PASS | `mount-loa.sh:1396-1402` tests `ln -sf`, sets fallback reason, returns 1 |
| 10 | Fallback reason in `.loa-version.json` | PASS | `mount-loa.sh:1422-1429` `record_fallback_reason()` uses jq to write field; called at line 1607-1609 |
| 11 | Mount lock prevents concurrency | PASS | `mount-loa.sh:1342-1361` PID-based lock at `.claude/.mount-lock` with stale detection |
| 12 | Memory Stack copy-then-verify-then-switch | CONDITIONAL | Logic correct but RF-1 (dotfile bug) breaks it for directories with hidden files |
| 13 | CI guard for uninitialized submodule | PASS | `mount-loa.sh:1405-1416` detects `CI=true` + missing `.loa/.claude`, prints exact fix |
| 14 | All 30 tests pass | PASS | Verified via `bats` execution: `30 tests, 30 passed, 0 failed` |

---

## Security Review

- **No command injection vectors found.** All variables in command positions are properly quoted.
- **Symlink traversal prevention intact.** All new symlinks use `safe_symlink()` which delegates to `validate_symlink_target()` (checks realpath stays within repo root).
- **Mount lock uses PID-based detection** with stale cleanup -- appropriate for this use case.
- **Migration lock** in `relocate_memory_stack()` also uses PID-based detection.
- **`umask 077`** is set in mount-submodule.sh for secure temp file creation.
- **`--no-verify`** on git commits is existing behavior, not new.

---

## Summary

The implementation is well-executed with good error handling, clear separation of concerns, and proper security practices. The two required fixes are:

1. **RF-1** (HIGH): Use `cp -r "$source"/. "$target"/` instead of `"$source"/*` to capture dotfiles during Memory Stack relocation.
2. **RF-2** (MEDIUM): Combine EXIT trap handlers so `_exit_handler` is not silently dropped when mount lock trap is set.

Once these are addressed, the sprint is ready for audit.
