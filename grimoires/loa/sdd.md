# Software Design Document: Fix spiral-orchestrator stdout pollution (Issue #514)

**Date**: 2026-04-16
**PRD**: `grimoires/loa/prd.md`
**Issue**: [#514](https://github.com/0xHoneyJar/loa/issues/514)
**Cycle**: cycle-077

## 1. Architecture Overview

This is a targeted bug fix in `.claude/scripts/spiral-orchestrator.sh`. No new components or architectural changes.

### Affected Component

`run_single_cycle()` (lines 982-1069) uses stdout as a two-line return channel:
- Line 1: stop_reason (empty = continue)
- Line 2: cycle_dir (for SEED chaining)

`run_cycle_loop()` (lines 1073-1103) captures this output via command substitution and parses with `head -1`/`tail -1`.

### Root Cause

`cycle-workspace.sh init` called at line 1012 outputs JSON to stdout. Only stderr is redirected (`2>/dev/null`). The JSON's opening `{` becomes `$stop_reason`, triggering early termination.

## 2. Changes

### Change 1: Redirect workspace init stdout (PRIMARY FIX)

**File**: `.claude/scripts/spiral-orchestrator.sh` line 1012
**Before**:
```bash
"$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" 2>/dev/null || true
```
**After**:
```bash
"$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" >/dev/null 2>&1 || true
```

### Change 2: Guard comment on return channel

Add a comment block above `run_single_cycle` warning that stdout is a return channel:
```bash
# WARNING: stdout is the return channel (line 1=stop_reason, line 2=cycle_dir).
# Any command within this function that writes to stdout will corrupt the return
# value. All helper invocations MUST either: (a) capture output in a variable,
# (b) redirect to a file, or (c) redirect stdout to /dev/null.
# See: Issue #514 (cycle-workspace.sh init stdout pollution).
```

### Change 3: Regression test

New BATS test file or extension of existing spiral tests:
- Test: stub-mode with `max_cycles: 3` completes all 3 cycles
- Assert: `stopping_condition` matches enum pattern `^[a-z_]+$`
- Assert: `stopping_condition` is `cycle_budget_exhausted` (not `"{"`)
- Assert: `cycle_index` equals `max_cycles`
- Assert: trajectory contains `spiral_stopped` event

## 3. Stdout Audit — Function Disposition Table

Every function/command called directly (not via command substitution) within `run_single_cycle` body:

| Line | Call | Stdout Behavior | Disposition |
|------|------|----------------|-------------|
| 1003 | `jq -n '{...}'` | **Captured** into `$init_harvest` | SAFE — command substitution |
| 1004 | `append_cycle_record` | Calls `atomic_state_write` which writes to file, no echo | SAFE |
| 1007 | `write_checkpoint` | Calls `atomic_state_write` which writes to file, no echo | SAFE |
| 1010-1012 | `cycle-workspace.sh init` | **LEAKS JSON** (`jq -n` at ws:215) | **FIX** — add `>/dev/null` |
| 1014 | `write_checkpoint` | Same as line 1007 | SAFE |
| 1017-1018 | `seed_phase` | All printfs go to `> "$seed_file"`, logs to stderr | SAFE |
| 1019 | `update_phase` | Writes to file via jq + mv, no echo | SAFE |
| 1020 | `write_checkpoint` | Same as above | SAFE |
| 1023 | `update_phase` | Same as above | SAFE |
| 1024-1025 | `simstim_phase` | `log` goes to stderr, stub `cat` goes to files, `emit_cycle_outcome_sidecar` has `>/dev/null` | SAFE |
| 1026 | `write_checkpoint` | Same as above | SAFE |
| 1028-1032 | `harvest_phase` | **Captured** into `$harvest_result` | SAFE — command substitution |
| 1035-1050 | `atomic_state_write` | Writes to file, no echo | SAFE |
| 1052 | `write_checkpoint` | Same as above | SAFE |
| 1055 | `update_phase` | Same as above | SAFE |
| 1057 | `evaluate_stopping_conditions` | **Captured** into `$stop_reason` | SAFE — command substitution |
| 1058 | `write_checkpoint` | Same as above | SAFE |
| 1060-1062 | `log_trajectory` | Writes to file with `>>`, no echo | SAFE |
| 1064 | `write_checkpoint` | Same as above | SAFE |

**Audit result**: Only one polluter — `cycle-workspace.sh init` at line 1012. The `jq -n` at line 1003 is captured into `$init_harvest` via command substitution and is SAFE.

**Call-site impact analysis** (Flatline IMP-001): `cycle-workspace.sh init` is called from exactly one location in the codebase (spiral-orchestrator.sh:1012). The orchestrator calls it for side effects only (directory creation + symlink wiring). The JSON status output (`{initialized: true, ...}`) is informational and never consumed by the orchestrator. No other callers within `run_single_cycle` depend on this output. The redirect is safe.

**Discarded output documentation** (Flatline IMP-004): The `>/dev/null` discards `cycle-workspace.sh`'s informational JSON status (`{initialized: true, cycle_id: ..., cycle_dir: ...}`). This is safe because: (a) the orchestrator verifies workspace creation via `write_checkpoint` and directory existence, not via the JSON return, (b) workspace init failures are already masked by `|| true`, and (c) the JSON duplicates information already available in `.run/spiral-state.json`.

## 4. Test Strategy

### Test file location

Check if `tests/unit/spiral-orchestrator.bats` exists; extend it. Otherwise create `tests/unit/spiral-orchestrator-multicycle.bats`.

### Test case: multi-cycle stub completion

```bash
@test "stub-mode completes all N cycles without early termination" {
    # Setup: create minimal config with max_cycles=3, stub mode
    # Run: SPIRAL_USE_STUB=1 spiral-orchestrator.sh --start
    # Assert:
    #   - exit code 0
    #   - .run/spiral-state.json .state == "COMPLETED"
    #   - .run/spiral-state.json .stopping_condition matches ^[a-z_]+$
    #   - .run/spiral-state.json .stopping_condition == "cycle_budget_exhausted"
    #   - .run/spiral-state.json .cycles | length == 3
    #   - trajectory contains spiral_stopped event
}
```

### Test case: stopping_condition is a valid enum value (Flatline IMP-002)

```bash
VALID_STOP_CONDITIONS="cycle_budget_exhausted flatline_convergence cost_budget_exhausted wall_clock_exhausted hitl_halt quality_gate_failure token_window_exhausted"

@test "stopping_condition is a valid enum member, not JSON fragment" {
    # Run stub-mode spiral
    # Extract stopping_condition from state JSON
    # Assert it is a member of VALID_STOP_CONDITIONS
}
```

### Test case: run_single_cycle stdout containment (Flatline IMP-003/IMP-006)

```bash
@test "run_single_cycle emits exactly two lines to stdout" {
    # Source spiral-orchestrator.sh functions
    # Capture all stdout from run_single_cycle into a variable
    # Assert: exactly 2 lines (stop_reason + cycle_dir)
    # Assert: line 1 is empty or matches VALID_STOP_CONDITIONS enum
    # Assert: line 2 is a valid path
    # This catches transitive stdout pollution from any sub-function
}
```

### Test case: non-stub path smoke test (Flatline IMP-009)

```bash
@test "workspace init stdout does not leak in non-stub mode" {
    # Mock simstim dispatch to avoid real claude -p
    # But use real cycle-workspace.sh init
    # Assert: no stdout pollution
}
```

## 5. System Zone Write Justification

Per PRD Section 7, this cycle is authorized to modify:
- `.claude/scripts/spiral-orchestrator.sh` — stdout redirect + guard comment
- `tests/unit/spiral-orchestrator*.bats` — regression test (new or extended)
