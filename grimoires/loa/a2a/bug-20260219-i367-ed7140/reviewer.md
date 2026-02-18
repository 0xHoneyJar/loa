# Implementation Report: sprint-bug-5

**Bug ID**: bug-20260219-i367-ed7140
**GitHub Issue**: #367
**Branch**: fix/bridgebuilder-esm-crash
**Date**: 2026-02-19

## Summary

Fixed two bugs in the Bridgebuilder review skill:
1. **ESM crash**: `loadReviewIgnore()` used CommonJS `require("path")` and `require("fs")` in an ESM module, causing runtime crash
2. **Stale model default**: Config hardcoded `claude-sonnet-4-5-20250929` instead of current `claude-sonnet-4-6`

## Tasks Completed

### Task 1: Fix require() → ESM imports in truncation.ts

**File**: `.claude/skills/bridgebuilder-review/resources/core/truncation.ts`

Replaced three CommonJS `require()` calls with the ESM imports already present at the top of the file:
- `require("path").join(root, ".reviewignore")` → `resolve(root, ".reviewignore")`
- `require("fs").existsSync(reviewignorePath)` → `existsSync(reviewignorePath)`
- `require("fs").readFileSync(reviewignorePath, "utf-8")` → `readFileSync(reviewignorePath, "utf-8")`

The ESM imports (`existsSync`, `readFileSync` from `node:fs`, `resolve` from `node:path`) were already declared at the top of the file — the `require()` calls were simply legacy code that was never migrated when the package switched to ESM.

### Task 2: Update default model in config.ts + TOKEN_BUDGETS

**Files**:
- `.claude/skills/bridgebuilder-review/resources/config.ts` — Changed default model from `claude-sonnet-4-5-20250929` to `claude-sonnet-4-6`
- `.claude/skills/bridgebuilder-review/resources/core/truncation.ts` — Added `claude-sonnet-4-6` entry to `TOKEN_BUDGETS` (kept old entry for backward compat)

### Task 3: Add tests

**File**: `.claude/skills/bridgebuilder-review/resources/__tests__/truncation.test.ts`

Added 8 new tests:

**loadReviewIgnore (5 tests)**:
- Returns LOA_EXCLUDE_PATTERNS when no .reviewignore exists
- Merges .reviewignore patterns with LOA_EXCLUDE_PATTERNS
- Normalizes directory patterns (trailing / becomes /**)
- Skips blank lines and comments
- Avoids duplicate patterns

**getTokenBudget (3 tests)**:
- Returns correct budget for claude-sonnet-4-6
- Returns correct budget for claude-sonnet-4-5-20250929 (backward compat)
- Returns default budget for unknown model

**File**: `.claude/skills/bridgebuilder-review/resources/__tests__/config.test.ts`
- Updated default model assertion to expect `claude-sonnet-4-6`

### Task 4: Rebuild dist/

Ran `npm run build` to regenerate compiled output. Verified:
- Zero `require()` calls in `dist/core/truncation.js`
- `claude-sonnet-4-6` present in both dist/config.js and dist/core/truncation.js

## Test Results

```
ℹ tests 340
ℹ suites 90
ℹ pass 340
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
```

All 340 tests pass including 8 new tests.

## Files Changed

| File | Change |
|------|--------|
| `resources/core/truncation.ts` | ESM fix + TOKEN_BUDGETS entry |
| `resources/config.ts` | Default model update |
| `resources/__tests__/truncation.test.ts` | 8 new tests |
| `resources/__tests__/config.test.ts` | Updated assertion |
| `dist/config.js` | Rebuilt |
| `dist/config.js.map` | Rebuilt |
| `dist/core/truncation.js` | Rebuilt |
| `dist/core/truncation.js.map` | Rebuilt |
| `dist/core/truncation.d.ts.map` | Rebuilt |
| `grimoires/loa/ledger.json` | Bugfix cycle tracking |

## Risk Assessment

**Low risk**. Both fixes are straightforward:
- The ESM fix replaces `require()` with imports already declared in the same file
- The model default change aligns with the current Claude model family
- Backward compatibility maintained via existing TOKEN_BUDGETS entries
- All 340 existing + new tests pass
