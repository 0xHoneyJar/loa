# Implementation Report: Sprint 5 (sprint-18) — Test Coverage and Documentation

**Sprint**: sprint-18 (sprint-5 of cycle-027, Bridge Iteration 2)
**Source**: Bridgebuilder review bridge-20260219-7f28c4, iteration 1 (LOW findings)
**Date**: 2026-02-19

---

## Summary

All 4 tasks completed addressing 3 LOW findings. Also discovered and fixed a pre-existing bug where `enabled: false` in config was silently ignored due to yq's `//` operator treating boolean false as falsy. Test count increased from 24 to 27 unit tests.

---

## Task Implementation

### BB-422: Make CONFIG_FILE Injectable via Environment Variable (low-1)

**Status**: COMPLETED

**Changes**: `.claude/scripts/qmd-context-query.sh:26`
- Changed `CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"` to `CONFIG_FILE="${QMD_CONFIG_FILE:-${PROJECT_ROOT}/.loa.config.yaml}"`
- When `QMD_CONFIG_FILE` env var is set, the script uses that path instead of the default
- Default behavior unchanged when env var is unset

**Bug Found**: While implementing the injectable test, discovered that `yq -r '.qmd_context.enabled // true'` was broken — the `//` operator in jq/yq means "if null **or false**, use right operand", so `false // true` evaluates to `true`. The `enabled: false` config flag was silently ignored. Fixed by using `yq -r '.qmd_context.enabled'` directly and checking for `"false"` string in bash.

**Verification**: `test_disabled_returns_empty()` now exercises the real disabled config path via `QMD_CONFIG_FILE` injection and confirms `[]` output.

---

### BB-423: Add --skill Override Precedence Tests (low-2)

**Status**: COMPLETED

**Changes**: `.claude/scripts/qmd-context-query-tests.sh`
- Added 3 new tests:
  1. `test_skill_override_wins_over_default`: Creates temp config with skill override budget 500 and default 3000, verifies skill override is loaded
  2. `test_cli_budget_wins_over_skill_override`: Verifies explicit `--budget` flag wins over skill override from config
  3. `test_invalid_skill_rejected`: Verifies `--skill '../inject'` produces a WARNING and is rejected

**Verification**: All 3 tests use `QMD_CONFIG_FILE` injection for isolated config testing.

---

### BB-424: Add Config Skill Override Cross-Reference Documentation (low-3)

**Status**: COMPLETED

**Changes**: `.loa.config.yaml.example:1661-1667`
- Added 5-line comment above `skill_overrides:` mapping each key to its skill invocation:
  - `implement` -> `/implement` (implementing-tasks/SKILL.md)
  - `review_sprint` -> `/review-sprint` (reviewing-code/SKILL.md)
  - `ride` -> `/ride` (riding-codebase/SKILL.md)
  - `run_bridge` -> `/run-bridge` (bridge-orchestrator.sh)
  - `gate0` -> `preflight.sh run_integrity_checks()`

---

### BB-425: Full Test Suite Validation

**Status**: COMPLETED

| Suite | Previous | Current | Delta |
|-------|----------|---------|-------|
| Unit tests | 24 | 27 | +3 |
| Integration tests | 22 | 22 | 0 |
| **Total** | **46** | **49** | **+3** |

All 49 tests pass. Zero regressions. The disabled config test now exercises the real code path instead of passing unconditionally.

---

## Files Changed

| File | Lines Changed | Type |
|------|---------------|------|
| `.claude/scripts/qmd-context-query.sh` | +2 -2 | Config injectable + enabled flag fix |
| `.claude/scripts/qmd-context-query-tests.sh` | +55 -5 | 3 new tests + disabled test rewrite |
| `.loa.config.yaml.example` | +5 | Cross-reference documentation |

---

## Bonus Fix: enabled: false Bug

The `QMD_CONFIG_FILE` injection exposed a pre-existing bug that the previous no-op test could not catch:

**Bug**: `yq -r '.qmd_context.enabled // true'` always returned `true` even when config had `enabled: false`
**Root Cause**: yq's `//` (alternative) operator treats boolean `false` as falsy, same as `null`
**Fix**: Changed to `yq -r '.qmd_context.enabled'` and compare result string to `"false"` in bash
**Impact**: Config disable flag now actually works
