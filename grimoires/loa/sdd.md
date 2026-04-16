# Software Design Document: Harden cache-manager secret detection (#530)

**Date**: 2026-04-16
**Issue**: [#530](https://github.com/0xHoneyJar/loa/issues/530)
**Cycle**: cycle-080

## 1. Pattern Change

**Current** (line 32): `'secret.*[=:]'`
- Matches: `secret_scanning: true` (false positive), `kind: Secret` (false positive)

**Proposed**: `'(^|[^a-zA-Z_])secret[_]?(key|value|token|password)?[[:space:]]*[=:]'`
- Requires `secret` to NOT be preceded by a letter/underscore (pseudo word boundary)
- Optionally followed by `_key`, `_value`, `_token`, `_password`
- Then whitespace + `=` or `:`
- Rejects: `secret_key=abc`, `"secret": "pass"`, `secret_value: x`
- Allows: `secret_scanning: true` (preceded by nothing problematic, but `_scanning` doesn't match suffix list)

Actually, simpler approach: use two narrower patterns instead of one broad one:
1. `'secret[_]?(key|value|token|password)[[:space:]]*[=:]'` — `secret_key=`, `secret_value:`, etc.
2. `'"secret"[[:space:]]*[=:]'` — JSON `"secret": "value"` (quoted key)

This catches actual secrets while excluding `secret_scanning`, `kind: Secret`, compound words.

## 2. Test additions

Extend `tests/unit/cache-manager.bats` with:
- Individual tests per pattern (PRIVATE.KEY, BEGIN RSA, password, secret variants, api_key, apikey, access_token, bearer)
- False-positive regression tests for `secret_scanning`, `kind: Secret`
