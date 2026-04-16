# Sprint Plan: Cycle-080 — Harden cache-manager secret detection (#530)

**Issue**: [#530](https://github.com/0xHoneyJar/loa/issues/530)
**Branch**: `fix/cache-manager-secret-patterns-530`

## Sprint 1

### Task 1: Narrow `secret` pattern in SECRET_PATTERNS array
Replace the single broad `'secret.*[=:]'` with two specific patterns.

### Task 2: Add parameterized BATS tests for each secret pattern
Individual test per pattern + false-positive regression tests.

### Task 3: Verify all tests pass + create PR
