# Implementation Report — Sprint 9

**Sprint**: Bridge Iteration — Metering Correctness and Test Coverage
**Global ID**: sprint-9 (local: sprint-5, cycle-026)
**Source**: Bridgebuilder bridge-20260218-1402f0, iteration 1 (severity 17.0)
**Date**: 2026-02-18

## Summary

Addressed 6 findings from Bridgebuilder iteration 1 review. All fixes are surgical — targeted at specific correctness, resilience, and coverage issues identified during enriched code review.

## Task Status

| Task | Finding | Status | Files |
|------|---------|--------|-------|
| 5.1 | BB-401 (HIGH) | Complete | rate_limiter.py |
| 5.2 | BB-404 (MEDIUM) | Complete | google_adapter.py |
| 5.3 | BB-405 (MEDIUM) | Complete | cheval.py |
| 5.4 | BB-403 (LOW) | Complete | google_adapter.py |
| 5.5 | BB-406 (MEDIUM) | Complete | test_pricing_extended.py |
| 5.6 | reframe-1 | Complete | rate_limiter.py |

## Detailed Changes

### Task 5.1: Fix time.monotonic() cross-process bug (BB-401 HIGH)

**File**: `.claude/adapters/loa_cheval/metering/rate_limiter.py`

Replaced all `time.monotonic()` with `time.time()` in persisted state:
- `check()` — `time.time()` for refill
- `record()` — atomic write uses `time.time()`
- `_default_state()` — fresh state uses `time.time()`

Added module docstring: advisory semantics, clock choice rationale, BudgetEnforcer as enforcing layer.

### Task 5.2: Fix token estimation (BB-404 MEDIUM)

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

- Added `input_text_length` parameter to `_parse_response()`
- `_complete_standard()` calculates input text length from `request.messages`
- Input tokens estimated from input text, output from response content

### Task 5.3: Fix budget fallback path (BB-405 MEDIUM)

**File**: `.claude/adapters/cheval.py`

- Wrapped fallback `adapter.complete()` in `try/finally`
- On success: `post_call(result)` runs normally
- On failure: logs `budget_post_call_skipped` warning, no phantom cost recorded

### Task 5.4: Remove dead code (BB-403 LOW)

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Removed unused `client = _detect_http_client_for_get()` in `poll_interaction()`. Function definition retained for `health_check()`.

### Task 5.5: Add test coverage (BB-406 MEDIUM)

**File**: `.claude/adapters/tests/test_pricing_extended.py`

10 new tests:
- `TestRemainderAccumulator` (5): carry, large remainder, zero, independent scopes, clear
- `TestOverflowGuard` (5): normal, remainder, near MAX_SAFE_PRODUCT, overflow ValueError, zero

### Task 5.6: Document advisory semantics (reframe-1)

**File**: `.claude/adapters/loa_cheval/metering/rate_limiter.py`

Module docstring + per-method docstrings clarifying advisory check, atomic record, BudgetEnforcer as hard gate.

## Test Results

- **Python**: 363 passed, 9 skipped, 0 failed (+10 new tests)
- **Regressions**: None

## Acceptance Criteria: 22/22 met
