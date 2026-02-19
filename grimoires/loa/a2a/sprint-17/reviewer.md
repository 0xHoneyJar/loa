# Implementation Report: Sprint 4 (sprint-17) — Security and Correctness Hardening

**Sprint**: sprint-17 (sprint-4 of cycle-027, Bridge Iteration 2)
**Source**: Bridgebuilder review bridge-20260219-7f28c4, iteration 1
**Date**: 2026-02-19

---

## Summary

All 4 tasks completed: 1 HIGH and 3 MEDIUM Bridgebuilder findings addressed with surgical changes to 2 files. Zero test regressions (46/46 pass).

---

## Task Implementation

### BB-418: Wire load_bridge_context() into Orchestration Loop (high-1)

**Status**: COMPLETED

**Changes**: `.claude/scripts/bridge-orchestrator.sh`
- Added `load_bridge_context()` call before `SIGNAL:BRIDGEBUILDER_REVIEW` in the iteration loop (new step 2c)
- Extracts sprint goal from `sprint.md` first header as query argument
- Logs context size when QMD context is available
- Falls back to empty string when script missing or disabled (graceful no-op preserved)
- Updated step numbering (2d->2e->2f->2g) to accommodate new step

**Verification**: `BRIDGE_CONTEXT` variable is now set before review, and the `[CONTEXT]` log line confirms it.

---

### BB-419: Escape rel_path in Grep Tier JSON Construction (medium-1)

**Status**: COMPLETED

**Changes**: `.claude/scripts/qmd-context-query.sh:390-395`
- Added `jq -Rs` escaping for `rel_path` before JSON embedding, matching the existing `snippet` escaping pattern on line 384
- Strip outer quotes after escaping for clean embedding into JSON string template
- Falls back to `"unknown"` if jq escaping fails

**Verification**: Filenames containing quotes, backslashes, or special characters now produce valid JSON instead of silent data loss.

---

### BB-420: Validate --skill Argument with Regex (medium-2)

**Status**: COMPLETED

**Changes**: `.claude/scripts/qmd-context-query.sh:97-102`
- Added regex validation `^[a-z_-]+$` immediately after `--skill` argument parsing
- Invalid values emit a WARNING to stderr and reset SKILL to empty string
- Valid skill names (implement, review_sprint, ride, run_bridge, gate0) all match the regex

**Verification**: Defense-in-depth at the boundary -- invalid input is rejected before reaching yq interpolation.

---

### BB-421: Prevent Symlink Traversal in Grep Tier (medium-3)

**Status**: COMPLETED

**Changes**: `.claude/scripts/qmd-context-query.sh:380-385`
- Added per-file `realpath` validation inside the grep results loop
- Each match file has its resolved path checked against `PROJECT_ROOT` prefix
- Symlinks pointing outside PROJECT_ROOT are silently excluded
- Non-symlink paths within PROJECT_ROOT continue to work unchanged

**Verification**: Both the directory-level check (lines 367-371) and the per-file check (new lines 380-385) now validate paths, preventing symlink traversal bypass.

---

## Test Results

| Suite | Count | Status |
|-------|-------|--------|
| Unit tests | 24/24 | PASS |
| Integration tests | 22/22 | PASS |
| **Total** | **46/46** | **ALL PASS** |

---

## Files Changed

| File | Lines Changed | Type |
|------|---------------|------|
| `.claude/scripts/bridge-orchestrator.sh` | +10 | Wire dead code into loop |
| `.claude/scripts/qmd-context-query.sh` | +16 | Security hardening (3 fixes) |

---

## Findings Addressed

| Finding ID | Severity | Title | Resolution |
|------------|----------|-------|------------|
| high-1 | HIGH | Dead code load_bridge_context() | Wired into iteration loop |
| medium-1 | MEDIUM | Unescaped rel_path in JSON | Added jq -Rs escaping |
| medium-2 | MEDIUM | Unsanitized --skill argument | Added regex validation |
| medium-3 | MEDIUM | Symlink traversal in grep tier | Added per-file realpath check |
