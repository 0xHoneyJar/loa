# Sprint Plan: Cycle-081 — Fix (( var++ )) under set -e

**Branch**: `fix/arithmetic-increment-set-e`

## Sprint 1

### Task 1: Create lint detector script
`.claude/scripts/lint-arithmetic-increment.sh` — detect `(( var++ ))` and `(( var-- ))` without `|| true` guard in scripts with `set -e`.

### Task 2: Bulk fix all unguarded sites
Mechanical sed replacement across 15 scripts, ~71 sites.

### Task 3: Verify tests pass + create PR
