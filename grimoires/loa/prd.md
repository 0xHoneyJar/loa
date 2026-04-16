# Product Requirements Document: Fix spiral-orchestrator stub-mode early termination (Issue #514)

**Date**: 2026-04-16
**Status**: Draft
**Issue**: [#514](https://github.com/0xHoneyJar/loa/issues/514)
**Cycle**: cycle-077

## 1. Problem Statement

`spiral-orchestrator.sh` terminates after cycle 1 of N with a malformed `stopping_condition` value of `"{"`. The root cause is stdout pollution from `cycle-workspace.sh init`, whose `jq -n '{initialized: true, ...}'` output leaks into `run_single_cycle`'s stdout return channel. Since `run_cycle_loop` uses `head -1` on that output to determine `$stop_reason`, the opening brace `{` of the JSON is interpreted as a non-empty stop reason, triggering early termination.

This affects both stub mode (`SPIRAL_USE_STUB=1`) and potentially real dispatch mode, making multi-cycle spirals impossible.

## 2. Goals

1. **Fix the immediate bug**: Prevent `cycle-workspace.sh init` stdout from polluting `run_single_cycle`'s return channel
2. **Harden the pattern**: Audit all commands called within `run_single_cycle` for similar stdout leaks
3. **Add regression guard**: BATS test that validates multi-cycle stub runs complete all N cycles
4. **Document the fragility**: Add a comment in `run_single_cycle` warning that stdout is a return channel

## 3. Non-Goals

- Refactoring the stdout-as-return-channel pattern to use an explicit output file (noted as future improvement, not in scope)
- Changes to `cycle-workspace.sh` itself (it correctly outputs JSON — the caller must handle it)
- Changes to real-dispatch (`SPIRAL_REAL_DISPATCH=1`) behavior beyond what the fix naturally covers

## 4. Success Criteria

| ID | Criterion | Verification |
|----|-----------|-------------|
| SC-1 | `SPIRAL_USE_STUB=1` with `max_cycles: 3` completes all 3 cycles | BATS test |
| SC-2 | `stopping_condition` in state JSON is one of the documented enum values (see Section 8) | BATS test: assert value is member of enum |
| SC-3 | `spiral_stopped` trajectory event is logged with correct condition | BATS test assertion |
| SC-4 | No other stdout polluters exist in `run_single_cycle` body — explicit disposition per function | Audit table in SDD with SAFE/FIXED/REDIRECTED per call |
| SC-5 | All existing spiral-orchestrator BATS tests pass | CI green |
| SC-6 | `jq -n` at line 1003 (`init_harvest`) verified as captured or redirected | Audit table entry |
| SC-7 | `stopping_condition` value is a valid JSON string (not a JSON fragment) | BATS test: `jq -e '.stopping_condition | test("^[a-z_]+$")'` |

## 5. Technical Context

### Root Cause (confirmed by issue #514 comment)

`run_single_cycle` (line ~982) uses stdout as a two-line return channel:
- Line 1: `$stop_reason` (empty string = continue, non-empty = stop condition name)
- Line 2: `$cycle_dir` (path for SEED chaining to next cycle)

At line 1010-1012, `cycle-workspace.sh init` is called with only stderr redirected:
```bash
with_step_timeout "workspace_init" "$t_workspace" \
    "$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" 2>/dev/null || true
```

`cycle-workspace.sh` `cmd_init()` (line 215-218) outputs:
```bash
jq -n --arg id "$id" --arg cycle_dir "$CYCLES_DIR/$id" \
    '{initialized: true, cycle_id: $id, cycle_dir: $cycle_dir}'
```

This pretty-printed JSON's `{` becomes the first line of `run_single_cycle`'s output, which `head -1` captures as `$stop_reason`. Since `[[ -n "{" ]]` is true, the loop terminates.

### Fix

One-line: redirect stdout alongside stderr at the call site:
```diff
-    "$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" 2>/dev/null || true
+    "$SCRIPT_DIR/cycle-workspace.sh" init "$cycle_id" >/dev/null 2>&1 || true
```

### Audit scope

Other commands in `run_single_cycle` (lines 983-1069) that could leak stdout:
- `seed_phase` — internal function, needs audit
- `simstim_phase` — internal function, needs audit
- `harvest_phase` — captured into `$harvest_result` via command substitution (safe)
- `evaluate_stopping_conditions` — captured into `$stop_reason` via command substitution (safe)
- `write_checkpoint` — needs audit
- `update_phase` — needs audit
- `log_trajectory` — needs audit
- `append_cycle_record` — needs audit
- `atomic_state_write` — needs audit
- `jq -n` at line 1003 — **NOT captured**, likely safe if writing to stderr but needs verification

## 6. Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Other stdout polluters exist in `run_single_cycle` | Medium | Systematic audit of all function calls in the body |
| Fix breaks `cycle-workspace.sh` consumers that depend on stdout output | Low | `cycle-workspace.sh` is called for side effects only by the orchestrator; other consumers (if any) invoke it directly |
| `jq -n` at line 1003 also leaks | Medium | Verify it's captured or redirected |

## 7. System Zone Write Authorization

This fix requires editing `.claude/scripts/spiral-orchestrator.sh` which is in the System Zone (`.claude/`). This is authorized per this PRD for cycle-077 scope only.

**Files to modify:**
- `.claude/scripts/spiral-orchestrator.sh` — redirect stdout at workspace init call site + audit comments

**Files to create:**
- `tests/unit/spiral-orchestrator-multicycle.bats` (or extend existing test file) — regression test

## 8. Stopping Condition Enum (authoritative)

Valid values for `stopping_condition` in `.run/spiral-state.json`:

| Value | Meaning |
|-------|---------|
| `cycle_budget_exhausted` | `max_cycles` reached |
| `flatline_convergence` | N consecutive cycles below `min_new_findings_per_cycle` |
| `cost_budget_exhausted` | `budget_cents` exceeded |
| `wall_clock_exhausted` | `wall_clock_seconds` exceeded |
| `hitl_halt` | `.run/spiral-halt` sentinel detected |
| `quality_gate_failure` | Both review AND audit failed |

Any value outside this enum is a bug. Tests MUST validate membership.

## 9. Flatline PRD Review Decisions (cycle-077)

**HIGH_CONSENSUS (5 — auto-integrated):** IMP-001 through IMP-005. Enum defined (Section 8), SC-4/SC-6/SC-7 added.

**DISPUTED (1 — rejected):**
- IMP-010: `>/dev/null 2>&1` silences diagnostics. **Rejected** — pre-existing `2>/dev/null || true` already suppresses both stderr and exit code. Adding stdout suppression doesn't reduce observability. Follow-up: consider structured error logging for workspace init in a separate issue.

**BLOCKERS (7 — all rejected):**
- SKP-001 x2 (refactor return channel, scores 910/850): **Rejected** — valid long-term concern but out of scope for targeted bug fix. Follow-up issue to be filed for return-channel refactor.
- SKP-002 (audit methodology, 750): **Rejected** — addressed by SC-4 requiring explicit disposition table per function.
- SKP-002 (malformed fix snippet, 940): **Rejected** — false positive. `2>&1` was misread as HTML entity by the tertiary model.
- SKP-006 (narrow test coverage, 730): **Rejected** — addressed by auto-integrated IMP-003 (real-dispatch regression path).
- SKP-003 (assumes single polluter, 720): **Rejected** — addressed by SC-6 (explicit `jq -n` line 1003 verification).
- SKP-003 (`|| true` suppresses failures, 760): **Rejected** — pre-existing behavior, not introduced by this fix.
