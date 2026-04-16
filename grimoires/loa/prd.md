# Product Requirements Document: Fix (( var++ )) under set -e + lint rule (QoL)

**Date**: 2026-04-16
**Cycle**: cycle-081

## 1. Problem

`(( var++ ))` exits with status 1 when `var=0` (POSIX: arithmetic evaluating to 0 is falsy). Under `set -e` or `set -euo pipefail`, this silently terminates the script. 71 unguarded sites across 15 scripts with `set -e`.

## 2. Goals

1. Add lint detector script (`lint-arithmetic-increment.sh`) matching the `lint-grep-c-fallback.sh` pattern
2. Fix all unguarded `(( var++ ))` and `(( var-- ))` in non-test `.claude/scripts/` files
3. Replacement: `var=$((var + 1))` (always exits 0)

## 3. Non-Goals

- Fixing test files (they manage their own error handling)
- Fixing sites already guarded with `|| true`

## 4. System Zone Write Authorization

Authorized for cycle-081: `.claude/scripts/*.sh`, `.claude/scripts/**/*.sh`
