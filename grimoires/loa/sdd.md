# Software Design Document: Fix spiral-harness budget boundary (#515)

**Date**: 2026-04-16
**PRD**: `grimoires/loa/prd.md`
**Issue**: [#515](https://github.com/0xHoneyJar/loa/issues/515)
**Cycle**: cycle-078

## 1. Changes

### Change 1: Strict-greater comparison in `_check_budget` (PRIMARY)

**File**: `.claude/scripts/spiral-evidence.sh` line 222

**Before**: `'$spent >= $max'` — blocks when spent equals max
**After**: `'$spent > $max'` — allows phase to START at exact budget

This is the minimal fix: a phase that starts when `spent == max` will run with its own per-phase `--max-budget-usd` cap from `_invoke_claude`. It can't overshoot the total because `claude -p` enforces per-call budgets.

### Change 2: Audit reserve in harness pipeline

**File**: `.claude/scripts/spiral-harness.sh`

Add an `AUDIT_RESERVE` variable that reduces the effective budget cap for pre-AUDIT phases:

```bash
# Reserve audit budget from the total so AUDIT always has headroom
AUDIT_RESERVE="$AUDIT_BUDGET"  # $2 by default
```

Modify `_invoke_claude` to use an effective budget when the phase is NOT AUDIT:
- Pre-AUDIT phases: check against `TOTAL_BUDGET - AUDIT_RESERVE`
- AUDIT phase: check against `TOTAL_BUDGET` (full cap)

Implementation: pass the effective cap to `_check_budget` based on phase name.

### Change 3: Raise light profile default budget

**File**: `.claude/scripts/spiral-harness.sh` line 159

**Before**: `TOTAL_BUDGET=10`
**After**: `TOTAL_BUDGET=12`

This matches observed real-world cumulative costs and provides margin.

### Change 4: Regression tests

**File**: `tests/unit/spiral-evidence.bats` — extend with:
- Test: `_check_budget` passes when spent equals exactly max (boundary case)
- Test: `_check_budget` fails when spent exceeds max

**File**: `tests/unit/spiral-harness.bats` — extend with:
- Test: light profile default budget is 12 (not 10)

## 2. System Zone Write Authorization

Per PRD Section 7. Files: `.claude/scripts/spiral-evidence.sh`, `.claude/scripts/spiral-harness.sh`, test files.
