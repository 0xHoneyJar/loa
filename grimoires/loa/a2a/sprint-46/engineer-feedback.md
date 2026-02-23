All good

# Sprint-46 (Cycle-035 Sprint-3) Engineer Review

> **Reviewer**: Senior Technical Lead
> **Date**: 2026-02-24
> **Verdict**: APPROVED — no required fixes

---

## Test Verification

All 79 tests pass with zero regressions:

| Suite | Tests | Status |
|-------|-------|--------|
| `test-mount-symlinks.bats` (sprint-3) | 19/19 | PASS |
| `test-mount-submodule-default.bats` (sprint-1) | 30/30 | PASS |
| `test-migration.bats` (sprint-2) | 13/13 | PASS |
| `test-stealth-expansion.bats` (sprint-2) | 17/17 | PASS |
| **Total** | **79/79** | **PASS** |

---

## Acceptance Criteria Verification

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| AC-1 | 10 symlink tests pass | PASS | Tests 1-10 in test-mount-symlinks.bats: scripts, protocols, hooks, data, schemas, CLAUDE.loa.md, reference, @-import, user_files_not_symlinked, overrides_not_symlinked |
| AC-2 | 3 Memory Stack tests pass | PASS | Tests 14-16: memory_stack_new_path, memory_stack_auto_migrate, memory_stack_submodule_safe |
| AC-3 | 3 Gitignore tests pass | PASS | Tests 17-19: loa_dir_not_gitignored, loa_cache_gitignored, symlinks_gitignored |
| AC-4 | 15-script audit with fixes | PASS | reviewer.md documents all 16 scripts (15 + check-permissions.sh). 5 updated (mount-loa.sh, butterfreezone-gen.sh, memory-setup.sh, memory-admin.sh, memory-sync.sh), rest confirmed transparent via symlink |
| AC-5 | loa-eject.sh handles submodule mode | PASS | `detect_installation_mode()` (L407-415) + `eject_submodule()` (L423-564): Phase 1 replaces all symlinks (directory, file, skill, command, settings), Phase 2 deinits submodule, Phase 3 updates .loa-version.json. Supports --dry-run. |
| AC-6 | INSTALLATION.md has CI examples | PASS | GitHub Actions (L646-660), GitLab CI (L664-672), shallow clone (L676-689), post-clone recovery (L693-698) |
| AC-7 | All PRD goals (G1-G5) validated | PASS | Implementation report Task 3.7 validates each goal with specific test references |

---

## Code Quality Assessment

### test-mount-symlinks.bats (NEW, 262 lines)

Well-structured test file with clean separation into Task 3.1, 3.2, and 3.3 sections. Good use of a `create_mock_submodule` helper and `create_test_symlinks` that mirrors the actual `mount-submodule.sh` logic. The setup/teardown pattern using `mktemp -d` with proper cleanup is correct.

The 3 bonus manifest coverage tests (11-13) that grep the production script for function existence and expected array contents are a pragmatic approach to integration-level validation without needing a full mount flow.

### mount-loa.sh — verify_mount() symlink check (L1499-1521)

The symlink health check correctly:
- Reads installation_mode from .loa-version.json
- Only activates for submodule mode
- Checks both existence (`-L`) and resolution (`-e`) of each symlink
- Falls back gracefully for real directories (vendored mode)
- Emits a warning with repair instructions rather than failing hard

### loa-eject.sh — submodule eject (L405-564)

Thorough 3-phase approach:
1. Replace symlinks with real copies from submodule source
2. Deinit submodule with cleanup of `.git/modules/` and `.gitmodules`
3. Update version manifest to standard mode

The function covers all symlink categories: directory, loa-file, per-skill, per-command, and settings. Each category handles the `--dry-run` flag. The `((replaced++)) || true` pattern avoids set -e failures on zero-increment — correct bash idiom.

### butterfreezone-gen.sh — installation_mode detection (L685-690)

Clean addition. Reads from `.loa-version.json` with `jq -r`, defaults to "unknown", and emits the value in the AGENT-CONTEXT YAML block at L906.

### Memory scripts (.loa/ -> .loa-cache/)

All three scripts (`memory-setup.sh`, `memory-admin.sh`, `memory-sync.sh`) correctly updated:
- `LOA_DIR` now points to `${PROJECT_ROOT}/.loa-cache`
- Comment explains the reason for the change
- No residual `.loa/` hardcoded paths remain (verified via grep)

### INSTALLATION.md — CI/CD section (L639-698)

Complete CI documentation with:
- GitHub Actions using `submodules: recursive` (the correct `actions/checkout@v4` parameter)
- GitLab CI using `GIT_SUBMODULE_STRATEGY: recursive`
- Shallow clone compatibility examples
- Post-clone recovery instructions

---

## Advisory Notes (non-blocking)

**ADV-1**: The `eject_submodule()` function at L546 removes `.gitmodules` if empty, but does not `git rm` it from the index. If the file was tracked, it would remain in git's staging area. This is a minor edge case since `git rm -f "$submodule_path"` at L542 typically handles `.gitmodules` via git internals, but worth noting for a future hardening pass.

**ADV-2**: The test suite (tests 11-13) validates function existence via grep, which is a code-level rather than behavioral test. These tests will break if the function is renamed but would not catch semantic regressions. This is an acceptable trade-off given the test suite also has behavioral tests (1-10, 14-19) that cover the actual symlink creation and memory stack behavior.

---

## Summary

Sprint-3 delivers exactly what the sprint plan specified. The 19 new tests comprehensively cover symlink integrity, memory stack relocation, and gitignore correctness. The 15-script audit identified and fixed the 5 scripts with hardcoded `.loa/` references. The `loa-eject.sh` submodule support is thorough with proper phase separation and dry-run support. CI/CD documentation covers the two major CI providers with shallow clone compatibility.

All 79 tests pass across all 4 suites. All 7 acceptance criteria met. All PRD goals (G1-G5) validated. Zero regressions. Approved for audit.
