# Sprint Plan: Cycle-078 — Fix spiral-harness budget boundary (#515)

**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Issue**: [#515](https://github.com/0xHoneyJar/loa/issues/515)
**Branch**: `fix/harness-budget-boundary-515`

## Sprint 1 (single sprint)

### Task 1: Change `>=` to `>` in `_check_budget`
**File**: `.claude/scripts/spiral-evidence.sh` line 222
- Change `'$spent >= $max'` to `'$spent > $max'`
- Update error message to match: `>` not `>=`

### Task 2: Add audit reserve logic to harness
**File**: `.claude/scripts/spiral-harness.sh`
- Add `AUDIT_RESERVE="$AUDIT_BUDGET"` after line 59
- Modify `_invoke_claude` to pass `TOTAL_BUDGET - AUDIT_RESERVE` for non-AUDIT phases
- AUDIT phase passes `TOTAL_BUDGET` directly

### Task 3: Raise light profile default budget to $12
**File**: `.claude/scripts/spiral-harness.sh` line 159
- Change `TOTAL_BUDGET=10` to `TOTAL_BUDGET=12`

### Task 4: Add regression tests
**Files**: `tests/unit/spiral-evidence.bats`, `tests/unit/spiral-harness.bats`
- T-BUD1: `_check_budget` passes when spent equals exactly max (the #515 boundary)
- T-BUD2: `_check_budget` fails when spent strictly exceeds max
- T-BUD3: light profile default budget is 12

### Task 5: Verify all tests pass + create PR
- Run `bats tests/unit/spiral-evidence.bats tests/unit/spiral-harness.bats`
- Create PR referencing #515
