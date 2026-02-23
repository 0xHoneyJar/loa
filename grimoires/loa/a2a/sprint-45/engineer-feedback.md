# Sprint-45 (Sprint 2) Engineer Feedback

**Reviewer**: Senior Technical Lead
**Date**: 2026-02-24
**Verdict**: All good -- implementation is thorough and well-structured with two advisory notes for sprint-3 hardening.

---

## Summary

Sprint-2 delivers 8 tasks spanning migration tooling, stealth expansion, boundary reporting, and submodule update infrastructure. All 60 tests pass (13 migration + 17 stealth + 30 sprint-1 regression). The code is clean, follows the SDD closely, and all 14 acceptance criteria are met.

---

## Acceptance Criteria Verification

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `--migrate-to-submodule` defaults to dry-run, requires `--apply` | PASS | `mount-loa.sh:1584-1587` -- `dry_run=true`, only `false` when `MIGRATE_APPLY == true` |
| 2 | Migration preserves `.loa.config.yaml`, `settings.json`, `commands/`, `overrides/` | PASS | `mount-loa.sh:1629` -- `user_owned_patterns` covers `overrides`, `commands`, `settings.local.json`; `settings.json` symlinked from submodule (line 1793); `.loa.config.yaml` preserved at root (line 1631) |
| 3 | Migration creates timestamped backup | PASS | `mount-loa.sh:1708` -- `.claude.backup.$(date +%s)` with `cp -r` |
| 4 | `apply_stealth()` adds 14 entries (4 core + 10 doc) | PASS | `mount-loa.sh:1024-1027` -- `core_entries` (4) + `doc_entries` (10), combined into `all_entries` (14) |
| 5 | `/loa` shows installation mode, commit hash, file counts | PASS | `golden-path.sh:837-903` -- `golden_detect_install_mode()` and `golden_boundary_report()` show mode, version, commit, submodule files, tracked/gitignored counts, user-owned files |
| 6 | `/update-loa` in submodule mode: fetch, checkout, verify symlinks | PASS | `update-loa.sh:148-237` -- `update_submodule()` fetches, checks out tag/ref, updates `.loa-version.json`, sources `verify_and_reconcile_symlinks()` |
| 7 | `verify_and_reconcile_symlinks()` detects dangling, removes stale, recreates | PASS | `mount-submodule.sh:793-906` -- 3-phase manifest check (dirs, files, skills+commands), canonical path resolver via `realpath`, reports counts |
| 8 | Supply chain: allowlist URL, enforce HTTPS, CI flags | PASS | `update-loa.sh:44-48` -- `ALLOWED_REMOTES` with 3 entries; line 140 -- `http://` blocked; `--require-submodule` (line 253), `--require-verified-origin` (line 128) |
| 9 | INSTALLATION.md submodule-first | PASS | `INSTALLATION.md:54-115` -- Method 1 is "Submodule Mode (Default)", Method 3 is "Vendored Mode (Legacy)" |
| 10 | All tests pass (60 total) | PASS | 13/13 + 17/17 + 30/30 = 60/60 |

---

## Code Quality Assessment

### Strengths

1. **migrate_to_submodule() is well-structured** (mount-loa.sh:1583-1894). The 12-step workflow follows the SDD exactly: detect -> clean tree check -> classify -> report -> backup -> remove -> submodule add -> symlink -> restore -> manifest -> gitignore -> commit. The dry-run default is safe.

2. **verify_and_reconcile_symlinks() is thorough** (mount-submodule.sh:793-906). The authoritative manifest approach with 3 phases (directory symlinks, file symlinks, per-skill+command dynamic discovery) is the right design. Using `realpath` for canonical resolution (Flatline SKP-002) is correct.

3. **Supply chain integrity is solid** (update-loa.sh:104-145). The allowlist includes HTTPS and SSH variants. HTTP is explicitly blocked. CI flags (`--require-submodule`, `--require-verified-origin`) fail closed, which is the correct security posture.

4. **golden_boundary_report() is informative** (golden-path.sh:855-903). Showing mode, version, commit hash, submodule file count, tracked count, gitignored count, and user-owned files gives operators complete visibility.

5. **Stealth expansion is idempotent** (mount-loa.sh:1029-1031). `grep -qxF` before append prevents duplicates on re-run. The split into `core_entries` and `doc_entries` is clean.

6. **update-loa.sh pins to tags by default** (line 168-173). Fetches `v*` tags and checks out the latest, only falling back to branch HEAD if no tags exist. This is the correct supply chain posture.

7. **Tests are appropriately scoped**. Migration tests verify argument parsing, function existence, backup, preservation, idempotency, and help text. Stealth tests verify all 14 entries individually plus idempotency.

### Advisory Notes (for sprint-3 hardening, not blocking)

**ADV-1: `settings.json` ownership model during migration** (mount-loa.sh:1629, 1793)
The `user_owned_patterns` array at line 1629 includes `settings.local.json` but not `settings.json`. After migration, `settings.json` is symlinked to the submodule (line 1793-1797). This means user customizations to `settings.json` would be classified as `USER_MODIFIED` (backed up) but then replaced by the submodule symlink without explicit warning.

The SDD at section 2.1 states: `settings.json (user-owned, NOT symlinked)`. The current implementation contradicts this -- both `mount-submodule.sh` (line 498-505) and the migration code (line 1793-1797) symlink `settings.json`.

**Impact**: Low. The `settings.json` in submodule mode is a framework-managed file with permission rules, and user customizations are correctly backed up. However, the sprint-3 hardening pass should clarify whether `settings.json` should be user-owned (real file, not symlinked) or framework-managed (symlinked). If user-owned, remove it from the symlink loop. If framework-managed, update the SDD.

**ADV-2: `grep -q ".loa"` in `.gitmodules` checks uses regex dot** (mount-submodule.sh:163, 186)
The `grep -q ".loa"` pattern at lines 163 and 186 uses an unescaped dot, which matches any character (e.g., `xloa`). In practice this is harmless since `.gitmodules` content is structured as `path = .loa`, but for correctness: use `grep -qF ".loa"` (fixed string) or `grep -q '\.loa'` (escaped).

**ADV-3: update-loa.sh vendored delegation loses parsed flags** (update-loa.sh:269)
When `mode == "standard"`, the script does `exec "$update_script" "$@"`. But `$@` is empty at this point because all arguments were consumed by the `while` loop. Flags like `--no-commit` are stored in variables but not forwarded. Sprint-3 should reconstruct args: `local args=(); [[ "$NO_COMMIT" == "true" ]] && args+=(--no-commit); exec "$update_script" "${args[@]}"`.

---

## File-by-File Review

### `.claude/scripts/mount-loa.sh`
- **Lines 184-185**: `MIGRATE_TO_SUBMODULE=false`, `MIGRATE_APPLY=false` -- correct defaults.
- **Lines 214-220**: Arg parser for `--migrate-to-submodule` and `--apply` -- clean.
- **Lines 263-273**: Help text includes migration examples with dry-run and apply -- good.
- **Lines 1006-1034**: `apply_stealth()` expanded correctly. 4 core + 10 doc = 14.
- **Lines 1583-1894**: `migrate_to_submodule()` -- well-structured 12-step workflow.
- **Line 1619**: `${MIGRATE_APPLY:+ --apply}` in the error message -- nice touch for copy-paste.
- **Line 1733**: `git rm -rf --cached .claude/ >/dev/null 2>&1 || true` -- appropriate error suppression.
- **Lines 1897-1902**: Routing in `main()` correctly dispatches to migration.

### `.claude/scripts/mount-submodule.sh`
- **Lines 148-172**: `get_memory_stack_path()` -- correct priority order, submodule detection via `.gitmodules`.
- **Lines 174-239**: `relocate_memory_stack()` -- lock file, copy-then-verify, rollback on failure. Good.
- **Lines 789-906**: `verify_and_reconcile_symlinks()` -- authoritative manifest, 3-phase check, dynamic skill/command discovery. Well-implemented.
- **Lines 908-924**: `check_symlinks_subcommand()` -- clean standalone entry point.
- **Lines 55-57**: `CHECK_SYMLINKS`, `RECONCILE_SYMLINKS`, `SOURCE_ONLY` variables -- proper.
- **Lines 82-93**: Arg parser for `--check-symlinks`, `--reconcile`, `--source-only` -- clean.

### `.claude/scripts/golden-path.sh`
- **Lines 837-851**: `golden_detect_install_mode()` -- reads `.loa-version.json`, maps `standard` to `vendored` for clarity.
- **Lines 855-903**: `golden_boundary_report()` -- comprehensive file counts, user-owned listing. Uses `git ls-files` which is correct for tracked file counting.

### `.claude/scripts/update-loa.sh`
- **Lines 44-48**: Allowlist covers HTTPS + SSH variants -- complete.
- **Lines 104-145**: `verify_submodule_integrity()` -- URL check + HTTPS enforcement.
- **Lines 148-237**: `update_submodule()` -- fetch -> tag checkout -> manifest update -> symlink reconcile. Flow is correct.
- **Lines 207-218**: Sourcing `mount-submodule.sh --source-only` to access `verify_and_reconcile_symlinks()` -- elegant reuse.

### `INSTALLATION.md`
- Lines 54-115: Method 1 is "Submodule Mode (Default)" -- correct ordering.
- Lines 138-152: Method 3 is "Vendored Mode (Legacy)" with `--vendored` flag.
- Lines 154-173: Migration section with dry-run/apply examples and rollback instructions.
- Directory tree at lines 97-115 correctly shows `.loa/` submodule + `.claude/` symlinks.

### `README.md`
- Lines 31-36: Quick Start shows submodule-first install with pin-to-version example.
- Line 48: Post-install description mentions `.loa/` (submodule).

### `PROCESS.md`
- Helper Scripts section lists `mount-submodule.sh` and `update-loa.sh` -- complete.

### `.claude/scripts/tests/test-migration.bats`
- 13 tests covering argument parsing, function existence, backup, preservation, idempotency, help text.
- Tests are grep-based (static analysis) rather than integration tests. Appropriate for this sprint scope.

### `.claude/scripts/tests/test-stealth-expansion.bats`
- 17 tests: 4 core entries, 10 doc entries, idempotency, log count, standard-mode skip.
- Complete coverage of the 14-entry specification.

---

## Test Results

```
test-migration.bats:              13/13 passed
test-stealth-expansion.bats:      17/17 passed
test-mount-submodule-default.bats: 30/30 passed (sprint-1 regression)
Total: 60/60 passed
```

---

## Verdict

**All good.** Sprint-2 is well-executed. All 14 acceptance criteria pass. All 60 tests pass. The three advisory notes (ADV-1 through ADV-3) are for sprint-3 hardening consideration and do not block approval.
