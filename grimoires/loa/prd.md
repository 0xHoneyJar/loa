# Product Requirements Document: Harden cache-manager secret detection (#530)

**Date**: 2026-04-16
**Issue**: [#530](https://github.com/0xHoneyJar/loa/issues/530)
**Cycle**: cycle-080

## 1. Problem Statement

PR #525 broadened `cache-manager.sh` secret patterns from `KEY.*=` to `KEY.*[=:]` to catch JSON/YAML secrets. The bare `secret.*[=:]` pattern now false-positives on legitimate content: `{"secret_scanning": true}`, `kind: Secret` (K8s), `"no_secret": false`, code comments.

## 2. Goals

1. Narrow the `secret` pattern with word-boundary-like anchoring to reduce false positives
2. Add parameterized BATS tests covering all 9 secret patterns individually
3. Add false-positive regression tests for known legitimate content

## 3. Non-Goals

- Porting the full allowlist mechanism from `adversarial-review.sh` (overkill for cache-manager's simpler detect-and-reject model)
- Changing patterns other than `secret.*[=:]` (the others are specific enough)

## 4. Success Criteria

| ID | Criterion | Verification |
|----|-----------|-------------|
| SC-1 | `{"secret_scanning": true}` does NOT trigger rejection | BATS test |
| SC-2 | `kind: Secret` (K8s manifest) does NOT trigger rejection | BATS test |
| SC-3 | `secret_key=abc123` DOES trigger rejection | BATS test |
| SC-4 | `"secret": "mypassword"` DOES trigger rejection | BATS test |
| SC-5 | All 9 secret patterns have individual test coverage | BATS test |
| SC-6 | All existing cache-manager tests pass | CI green |

## 5. System Zone Write Authorization

Authorized for cycle-080: `.claude/scripts/cache-manager.sh`, `tests/unit/cache-manager.bats`
