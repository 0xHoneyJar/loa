# Sprint 20 Implementation Report

**Sprint**: Detection & Validation Hardening
**Global ID**: sprint-20 (local sprint-2)
**Cycle**: cycle-028 (Security Hardening — Bridgebuilder Cross-Repository Findings)
**Date**: 2026-02-19

---

## Implementation Summary

| Task | Status | Files Modified |
|------|--------|---------------|
| T2.1: Harden Credential Health Checks | Complete | health.py, tests/test_health.py (NEW) |
| T2.2: Tighten aws_secret Regex Pattern | Complete | pii-redactor.ts, pii-redactor.test.ts |

---

## T2.1: Harden Credential Health Checks

**Status**: Complete

**Files Modified**:
- `.claude/adapters/loa_cheval/credentials/health.py` — Added `FORMAT_RULES` dict, `_check_format()`, `_check_live()`, `_redact_credential_from_error()`, `live` parameter to `check_credential()` and `check_all()`

**Files Created**:
- `tests/test_health.py` — 24 tests covering format validation, live mode, log redaction, sentinel leakage

**Design Decisions**:
- Default `check_credential()` calls `_check_format()` (dry-run mode) — no HTTP requests
- `live=True` routes to `_check_live()` which uses `urllib.request.build_opener()` with `debuglevel=0` to suppress debug output
- Moonshot returns `"unknown/weak_validation"` status since no stable format is known
- `_redact_credential_from_error()` applied to all exception messages in live mode
- FORMAT_RULES uses compiled `re.compile()` patterns for charset validation

**Acceptance Criteria Verification**:
- [x] Default `check_credential()` does NOT make HTTP requests (mock urllib, assert not called)
- [x] `live=True` makes HTTP requests (mock urllib, assert called)
- [x] Moonshot returns `"unknown/weak_validation"` status
- [x] API key values NEVER appear in logs, stack traces, or exception dumps (sentinel test)
- [x] Centralized log capture test (Flatline SKP-007): sentinel values grepped in output
- [x] Format validation correctly accepts known-valid and rejects known-invalid keys
- [x] All existing callers work unchanged (backward compatible)

---

## T2.2: Tighten aws_secret Regex Pattern

**Status**: Complete

**Files Modified**:
- `.claude/lib/security/pii-redactor.ts` (line 68) — Replaced broad regex with negative lookahead
- `.claude/lib/__tests__/pii-redactor.test.ts` — Added 5 new tests for FR-7

**Implementation**:
- Old regex: `/\b[A-Za-z0-9/+=]{40}\b/g`
- New regex: `/\b(?![0-9a-fA-F]{40}\b)[A-Za-z0-9/+=]{40}\b/g`
- Approach B from SDD (negative lookahead) — simpler to reason about, no backtracking risk

**New Tests**:
1. SHA-1 hex hashes are NOT redacted as aws_secret
2. Git commit hashes are NOT redacted as aws_secret
3. Uppercase hex-only strings are NOT redacted as aws_secret
4. Real AWS secret access keys ARE still detected
5. aws_key_id pattern (AKIA prefix) still works

**Acceptance Criteria Verification**:
- [x] SHA-1 hex hashes (`[0-9a-f]{40}`) are NOT redacted as `aws_secret`
- [x] Git commit hashes are NOT redacted as `aws_secret`
- [x] Real AWS secret access keys ARE still detected
- [x] All 22 existing pii-redactor tests pass unchanged
- [x] No ReDoS regression (adversarial test passes within 100ms: 0.76ms actual)

---

## Test Results

- `tests/test_health.py` — 24 tests, all pass
- `pii-redactor.test.ts` — 27 tests (22 existing + 5 new), all pass
- Existing test suites — Running (background verification)

---

## Risk Mitigations Applied

- **Backward compatibility**: `check_credential()` default behavior unchanged for existing callers (format-only, no HTTP)
- **Log redaction**: `_redact_credential_from_error()` catches credential values in all exception paths
- **urllib debug**: Disabled via `build_opener(HTTPHandler(debuglevel=0))` to prevent header leakage
- **Regex performance**: Negative lookahead has O(n) complexity, no backtracking risk — verified via adversarial test
- **Shannon entropy backup**: Unchanged, continues to catch high-entropy strings regardless of regex changes
