# Implementation Report — Sprint 21 (Sprint 3: Audit Integrity + State Verification + Eval Coverage)

**Cycle**: cycle-028 — Security Hardening
**Sprint**: sprint-3 (global sprint-21)
**Date**: 2026-02-19

---

## Task 3.1: Fix Audit Logger Crash Recovery Size Tracking ✅

**Finding**: FR-4 (High) — `currentSize` tracked using `string.length` (UTF-16 code units) instead of actual UTF-8 byte count, causing drift with multi-byte characters.

### Changes

**File**: `.claude/lib/security/audit-logger.ts`

1. **Added `statSync` import** (line 19): Added to `node:fs` imports for accurate file size reads.

2. **Fixed `doAppend()` size tracking** (line 178): Changed `this.currentSize += line.length` to `this.currentSize += Buffer.byteLength(line, "utf-8")`. This correctly accounts for multi-byte UTF-8 characters (emoji = 4 bytes, CJK = 3 bytes) instead of counting UTF-16 code units.

3. **Fixed `recoverFromCrash()` size tracking** (lines 317-321): Replaced manual `line.length + 1` accumulation loop with `statSync(this.logPath).size` after recovery. This provides exact byte-accurate size regardless of file content encoding.

### Tests Added

**File**: `.claude/lib/__tests__/audit-logger.test.ts` — 3 new tests

| Test | Description |
|------|-------------|
| `FR-4: currentSize matches statSync after crash recovery` | Verifies size accuracy after corrupted line truncation |
| `FR-4: multi-byte UTF-8 entries do not cause size drift` | Tests with emoji (🎉🔥🚀) and CJK (漢字テスト) data |
| `FR-4: partial last line recovery — size equals file size` | Verifies size after torn-write recovery |

**All 19 audit-logger tests pass** (15 existing + 3 new).

---

## Task 3.2: Add HMAC Verification for Run State Files ✅

**Finding**: FR-5 (Medium) — Run state files (`.run/*.json`) have no integrity verification, allowing undetected tampering.

### New File: `.claude/scripts/run-state-verify.sh`

Implements HMAC-SHA256 signing and verification with 4 subcommands:

| Subcommand | Description |
|------------|-------------|
| `init <run_id>` | Generate per-run key in `~/.claude/.run-keys/{run_id}.key` (mode 0600) |
| `sign <file> <run_id>` | Add `_hmac` and `_key_id` fields to state JSON |
| `verify <file>` | Verify HMAC with safety checks (exit 0=valid, 1=tampered, 2=unsigned) |
| `cleanup [--stale --max-age 7d]` | Remove orphaned keys |

### Safety Features

- **`verify_file_safety()`**: Hardcoded trusted base from `git rev-parse --show-toplevel`/.run
- **Symlink detection**: `-L` check rejects symlinked state files
- **Ownership verification**: Checks file UID matches current user
- **Permission verification**: Accepts 600/640/644/660/664 (no world-write)
- **JSON canonicalization**: `jq -cS 'del(._hmac, ._key_id)'` ensures whitespace/key-order independence
- **Graceful degradation**: Missing key returns exit 2 (unsigned), not crash
- **Permission preservation**: Sign preserves original file permissions after rewrite

### Tests: `tests/test_run_state_verify.sh`

| Test | Description |
|------|-------------|
| Sign + verify round-trip | Basic HMAC sign then verify succeeds |
| Tampered content detection | Modified state detected as tampered (exit 1) |
| Missing key handling | Missing key returns exit 2, not crash |
| Symlink detection | Symlinked state files rejected |
| Base directory enforcement | Files outside `.run/` rejected |
| JSON canonicalization | Reformatted JSON still verifies |
| Concurrent runs | Different run_ids with independent keys |

**All 7 HMAC verification tests pass.**

---

## Task 3.3: Add refreshToken Test Coverage to Auth Eval Fixture ✅

**Finding**: FR-6 (Medium) — `refreshToken` function has zero test coverage in eval fixture.

### Changes

**File**: `evals/fixtures/buggy-auth-ts/tests/auth.test.ts`

Added `describe('refreshToken', ...)` block with 4 tests:

| Test | Description |
|------|-------------|
| `should refresh token after valid login` | Token refreshes successfully, returns new token |
| `should return null when no login has occurred` | No token = null return |
| `should return null for expired token` | Expired tokens cannot be refreshed |
| `should update token expiry on refresh` | Expiry extends on successful refresh |

**Note**: The eval fixture's intentional bugs (hardcoded JWT secret, TOCTOU race, no email validation) are NOT fixed — tests document observable behavior per acceptance criteria.

**All 8 eval fixture tests pass** (4 existing + 4 new).

---

## Test Summary

| Suite | Before | After | Status |
|-------|--------|-------|--------|
| audit-logger.test.ts | 16 tests | 19 tests | ✅ All pass |
| test_run_state_verify.sh | 0 tests (NEW) | 7 tests | ✅ All pass |
| buggy-auth-ts auth.test.ts | 4 tests | 8 tests | ✅ All pass |
| pii-redactor.test.ts | 27 tests | 27 tests | ✅ No regression |

## Files Changed

| File | Action | Task |
|------|--------|------|
| `.claude/lib/security/audit-logger.ts` | Modified | 3.1 |
| `.claude/lib/__tests__/audit-logger.test.ts` | Modified | 3.1 |
| `.claude/scripts/run-state-verify.sh` | **NEW** | 3.2 |
| `tests/test_run_state_verify.sh` | **NEW** | 3.2 |
| `evals/fixtures/buggy-auth-ts/tests/auth.test.ts` | Modified | 3.3 |
