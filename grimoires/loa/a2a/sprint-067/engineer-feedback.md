# Engineer Feedback — Cycle-067 Sprint Review

**Reviewer**: Senior Tech Lead (automated)
**Date**: 2026-04-14
**Verdict**: ~~CHANGES_REQUIRED~~ → APPROVED (re-review)
**Branch**: `feat/cycle-067-spiral-finish`
**PR**: #494

---

## Overall Assessment

Strong implementation. The HARVEST adapter is production-grade (clean review, no issues). The orchestrator behavioral changes are architecturally sound — quality gate truth table, crash handler async safety, checkpoint monotonicity, and PID guard are all correctly implemented. 57 tests pass. However, **3 missing tests** and **1 weak assertion** prevent approval.

## Critical Issues (must fix)

### 1. Missing T35: `seed_phase` full-mode degradation test

**Location**: `tests/unit/spiral-orchestrator.bats` (absent)
**AC reference**: sprint.md T2.1: "seed_phase(): full mode without Vision Registry → degrades to degraded + warning (T35)"

The implementation exists at `spiral-orchestrator.sh:515-519` — when `spiral.seed.mode: full` is configured, the function logs a WARNING and downgrades to degraded mode. But no test verifies this path.

**Required**: Add test T35 that:
- Sets config `spiral.seed.mode: full`
- Calls `seed_phase` with a previous cycle dir
- Asserts WARNING is logged
- Asserts `seed_mode_transition` trajectory event emitted
- Asserts seed-context.md is still written (degraded behavior)

### 2. Missing test: `SPIRAL_STUB_FINDINGS` malformed input

**Location**: `tests/integration/spiral-e2e.bats` or `tests/unit/spiral-orchestrator.bats` (absent)
**AC reference**: sprint.md T2.1: "simstim_phase(): deterministic findings via SPIRAL_STUB_FINDINGS env var. Valid values: integer >= 0. Malformed/empty → default 3 (Flatline IMP-005)"

Implementation at `spiral-orchestrator.sh:578-582` validates the env var. No test exercises the malformed-input path.

**Required**: Add test that:
- Sets `SPIRAL_STUB_FINDINGS="not_a_number"`
- Runs a single cycle
- Asserts findings count defaults to 3 (check sidecar or cycle record)

### 3. Missing test: checkpoint monotonicity rejection

**Location**: `tests/unit/spiral-orchestrator.bats` (absent)
**AC reference**: sprint.md T1.6: "write_checkpoint() with CHECKPOINT_ORDER array + monotonicity guard (Bridgebuilder HIGH-2)"

`write_checkpoint` at `spiral-orchestrator.sh:211-233` enforces ordering, but no test directly verifies that a backward transition (e.g., HARVEST → SEED) is rejected with error.

**Required**: Add test that:
- Creates state with a cycle at checkpoint HARVEST
- Calls `write_checkpoint $cycle_id "SEED"` (backward)
- Asserts function returns non-zero
- Asserts error message contains "Non-monotonic"

## Non-Critical Improvements (recommended, non-blocking)

### 4. E2E seed-context.md content assertion is weak

**Location**: `tests/integration/spiral-e2e.bats:115`
**Current**: `[ -f "$PROJECT_ROOT/cycles/$cycle_2_id/seed-context.md" ]` — existence only
**Better**: Add `grep -q "Review: APPROVED" "$PROJECT_ROOT/cycles/$cycle_2_id/seed-context.md"` to verify content includes previous cycle verdict.

### 5. `cmd_start` should call `check_pid_guard()` instead of inline RUNNING check

**Location**: `spiral-orchestrator.sh:886-892`
**Current**: Simple `state == RUNNING → error` check
**Better**: Replace with `check_pid_guard` call (lines 303-337), which handles stale RUNNING with dead PID. Currently, a user who runs `--start` after a crash (instead of `--resume`) gets blocked until they manually clean state. The `check_pid_guard` function already handles this correctly but isn't wired into `cmd_start`.
**Non-blocking**: `--resume` handles this path correctly, so it's a UX improvement, not a correctness issue.

## Adversarial Analysis

### Concerns Identified (minimum 3)

1. **Missing test coverage for 3 documented ACs** — sprint.md explicitly lists T35, SPIRAL_STUB_FINDINGS validation, and checkpoint monotonicity guard as acceptance criteria. Implementation exists but test evidence is absent. `spiral-orchestrator.sh:515-519`, `spiral-orchestrator.sh:578-582`, `spiral-orchestrator.sh:211-233`.

2. **`with_step_timeout` silently degrades to no-op for all bash functions** — `spiral-orchestrator.sh:286` skips timeout for `type -t == function`. This means ALL phase functions (seed, simstim, harvest, evaluate) run without step-level timeouts. Only the wall-clock provides safety. For the stub this is fine, but when real dispatch arrives in cycle-068, `simstim_phase` will still be a function, not an external command. The step timeout for simstim (3600s) will never fire.

3. **`run_single_cycle` at 87 lines exceeds 50-line complexity threshold** — `spiral-orchestrator.sh:720-807`. The function handles 7 checkpoint writes, 4 phase calls, 2 state updates, and stop-condition evaluation. While logically cohesive, extracting the phase dispatch into a helper would improve readability and testability.

### Assumptions Challenged (minimum 1)

- **Assumption**: Stub-backed cycles are fast enough that step timeouts are irrelevant
- **Risk if wrong**: When real dispatch replaces the stub in cycle-068, `simstim_phase` will still be a bash function, so `with_step_timeout` will still skip it. The 3600s simstim timeout will never fire. This means a hung real simstim dispatch could block the spiral indefinitely (only wall-clock kills it after 24h).
- **Recommendation**: Document this as a known limitation for cycle-068. When real dispatch is wired, `simstim_phase` should invoke the subprocess via an external wrapper script (not a bash function) so timeout can wrap it. Or refactor `with_step_timeout` to use a subshell approach for functions.

### Alternatives Not Considered (minimum 1)

- **Alternative**: Use bash `SECONDS` variable + background watchdog instead of `timeout(1)` for step-level limits. This would work for both functions and external commands.
- **Tradeoff**: More complex implementation, but eliminates the function-vs-external distinction entirely. Also avoids the macOS portability issue with `timeout`.
- **Verdict**: Current approach is justified for cycle-067 (stub is fast, wall-clock is sufficient). Revisit for cycle-068 when real dispatch needs step timeouts.

## Previous Feedback Status

N/A — first review of this sprint.

## Re-Review (same session)

All 3 blocking issues resolved in commit `d006d20`:
- T35 added: seed full-mode degradation ✓
- T41 added: SPIRAL_STUB_FINDINGS malformed input ✓
- T42 added: checkpoint monotonicity rejection ✓
- E2E seed-context.md content assertion strengthened ✓

60/60 tests passing. **All good (with noted non-blocking concerns).**

Concerns documented but non-blocking. See Adversarial Analysis above.
- cmd_start PID guard gap: `--resume` handles this correctly, UX improvement only
- with_step_timeout function limitation: documented for cycle-068
- run_single_cycle length: cohesive, acceptable at 87 lines
