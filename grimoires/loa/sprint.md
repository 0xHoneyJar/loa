# Sprint Plan: Cycle-077 — Fix spiral-orchestrator stdout pollution (#514)

**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Issue**: [#514](https://github.com/0xHoneyJar/loa/issues/514)
**Branch**: `fix/spiral-stdout-pollution-514`

## Sprint 1 (single sprint — targeted fix)

### Task 1: Apply stdout redirect fix
**File**: `.claude/scripts/spiral-orchestrator.sh`
**Lines**: 1010-1012

Change:
```bash
"$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" 2>/dev/null || true
```
To:
```bash
"$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" >/dev/null 2>&1 || true
```

**Acceptance criteria**:
- [ ] `>/dev/null 2>&1` replaces `2>/dev/null`
- [ ] No other lines changed in the function

### Task 2: Add guard comment above run_single_cycle
**File**: `.claude/scripts/spiral-orchestrator.sh`
**Lines**: ~980 (above function definition)

Add comment block documenting that stdout is a return channel and all commands must either capture output or redirect stdout.

**Acceptance criteria**:
- [ ] Comment placed immediately above `run_single_cycle()` definition
- [ ] References Issue #514

### Task 3: Add multi-cycle stub BATS regression test
**File**: `tests/unit/spiral-orchestrator.bats` (extend existing, ~785 lines)

Add test section at end of file with:

**Test T-MC1**: `"stub-mode completes all max_cycles without early termination"`
- Setup: config with explicit `default_max_cycles: 3` (test controls the value, not inherited)
- Run `SPIRAL_USE_STUB=1 spiral-orchestrator.sh --start`
- Assert exit code 0
- Assert `.run/spiral-state.json` `.state == "COMPLETED"`
- Assert `.stopping_condition == "cycle_budget_exhausted"`
- Assert `.cycles | length == 3` (matches the test's explicit `default_max_cycles`)
- Assert trajectory file contains `spiral_stopped` event

**Test T-MC2**: `"stopping_condition is a valid enum member"`
- After stub run, extract `stopping_condition`
- Assert it matches one of the PRD Section 8 enum values: `cycle_budget_exhausted`, `flatline_convergence`, `cost_budget_exhausted`, `wall_clock_exhausted`, `hitl_halt`, `quality_gate_failure`, `token_window_exhausted`
- Assert it does NOT contain `{`, `}`, or whitespace

**Test T-MC3**: `"run_single_cycle stdout contract: line 1=stop_reason, line 2=cycle_dir"`
- Source the orchestrator functions
- **Mocking strategy**: Create a mock `cycle-workspace.sh` in test's PATH that outputs JSON to stdout (simulating the bug trigger). Mock `simstim_phase` and `harvest_phase` as no-ops. Set up minimal state file.
- Capture all stdout from `run_single_cycle`
- **Stdout contract**: Line 1 is either empty string (continue) or a member of the stopping_condition enum. Line 2 is a directory path matching `*/cycles/*`.
- Assert exactly 2 lines emitted
- Assert line 1 is empty or matches enum (not `{`, not JSON)
- Assert line 2 is a valid directory path

**Acceptance criteria**:
- [ ] All 3 tests pass
- [ ] Tests use existing `setup`/`teardown` fixtures
- [ ] No changes to existing tests
- [ ] Tests run in <10s total

### Task 4: Verify existing tests still pass
**Command**: `bats tests/unit/spiral-orchestrator.bats`

**Acceptance criteria**:
- [ ] All existing tests pass (no regressions)
- [ ] New tests pass
- [ ] Exit code 0

### Task 5: Create PR
**Branch**: `fix/spiral-stdout-pollution-514`
**Target**: `main`

**Acceptance criteria**:
- [ ] PR references issue #514
- [ ] PR description includes root cause summary
- [ ] Review requested from @janitooor
