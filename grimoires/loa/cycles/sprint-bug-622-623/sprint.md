# sprint-bug-622-623 — spiral orchestrator multi-cycle bugfix bundle

**Type**: bug-fix micro-sprint (paired)
**Source**: zkSoju issues [#622](https://github.com/0xHoneyJar/loa/issues/622) + [#623](https://github.com/0xHoneyJar/loa/issues/623)
**Severity**: HIGH (both block multi-cycle `/spiral --start` usage)
**Branch**: `feature/spiral-orchestrator-bugfixes-622-623`
**Built on**: main @ 7d151df (post-cycle-094 close)

## Bundling rationale

Both bugs live in `.claude/scripts/spiral-orchestrator.sh`. Both have repro steps + diagnosis + suggested fixes from the reporter (zkSoju). Together they make multi-cycle spiral runs structurally usable: #622 lets `/spiral --start` actually run during normal hours; #623 ensures cycles 2..N land on distinct branches. Fixing them in a single PR is proportional — same file, shared test harness, shared CI lane.

## Acceptance Criteria

### #622 — `check_token_window` doesn't gate on `spiral.scheduling.enabled`

- [ ] **AC-622-1**: With `spiral.scheduling.enabled: false` (default), `check_token_window()` returns 1 (don't stop) regardless of `windows[0].end_utc` and current time.
- [ ] **AC-622-2**: Existing `enabled: true` + `strategy: continuous` path continues to short-circuit at the strategy check (no regression).
- [ ] **AC-622-3**: Existing `enabled: true` + `strategy: fill` + window-end past path continues to return 0 (DO stop) — i.e., the original feature still works when actually configured to use windowed scheduling.
- [ ] **AC-622-4**: BATS regression tests cover all three branches above.

### #623 — `SPIRAL_ID` + `SPIRAL_CYCLE_NUM` not exported per cycle

- [ ] **AC-623-1**: `spiral-orchestrator.sh` exports `SPIRAL_ID` from state file (next to existing `SPIRAL_TASK` export at line ~1272).
- [ ] **AC-623-2**: `spiral-orchestrator.sh` exports `SPIRAL_CYCLE_NUM` per cycle (driven by the existing cycle index counter).
- [ ] **AC-623-3**: A multi-cycle `/spiral --start` simulation produces distinct branch names per cycle: `feat/spiral-{spiral_id}-cycle-1`, `feat/spiral-{spiral_id}-cycle-2`, `feat/spiral-{spiral_id}-cycle-3` (where `{spiral_id}` is a stable per-spiral identifier, not `unknown`).
- [ ] **AC-623-4**: BATS regression test asserts the env vars are exported AND distinct per cycle.

### Cumulative

- [ ] All existing spiral-* BATS tests stay green
- [ ] No new findings expected in security audit (test-only + 2 surgical export adds + 1 short-circuit guard)

## Technical Tasks

### Task 1 — #622 fix

- [ ] **T1.1**: Add `enabled` short-circuit at top of `check_token_window()` in `.claude/scripts/spiral-orchestrator.sh:408`. The function currently reads `strategy` first; insert the `enabled` check above that.
  ```bash
  check_token_window() {
      local enabled
      enabled=$(read_config "spiral.scheduling.enabled" "false")
      [[ "$enabled" != "true" ]] && return 1  # Scheduling disabled — never gate

      local strategy
      strategy=$(read_config "spiral.scheduling.strategy" "fill")
      [[ "$strategy" == "continuous" ]] && return 1
      ...
  }
  ```
- [ ] **T1.2**: Add 3 BATS tests in a new (or existing) test file:
  - `enabled: false` → returns 1 regardless of window state
  - `enabled: true` + `strategy: continuous` → returns 1 (existing behavior)
  - `enabled: true` + `strategy: fill` + window past → returns 0 (existing behavior preserved)

### Task 2 — #623 fix

- [ ] **T2.1**: Export `SPIRAL_ID` next to `SPIRAL_TASK` in `spiral-orchestrator.sh` (search for the existing `export SPIRAL_TASK` to find the location).
- [ ] **T2.2**: Export `SPIRAL_CYCLE_NUM` per cycle. Either inside `simstim_phase()` or its caller `run_single_cycle()` — wherever the cycle index is canonically incremented.
- [ ] **T2.3**: Add BATS regression test that:
  - Sources/invokes the orchestrator's cycle iteration in test mode
  - Captures the env vars from the dispatch subprocess (e.g., via a stub `spiral-simstim-dispatch.sh` that echoes `$SPIRAL_ID`/`$SPIRAL_CYCLE_NUM` into a fixture)
  - Asserts SPIRAL_ID is set + non-empty + non-`unknown`
  - Asserts SPIRAL_CYCLE_NUM increments across cycles

## Risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| `enabled` config key historically defaulted differently | Low | Medium | Verify `.loa.config.yaml.example` shows `enabled: false` as the documented default; matches issue claim |
| `SPIRAL_CYCLE_NUM` increment site is tangled in a larger cycle-tracking refactor | Low-Med | Low | Existing state file already tracks `cycle_index` (issue references line 142, line 976); just propagate as env var |
| BATS test for env-export timing requires real subprocess dispatch | Medium | Low | Use a stub dispatch script that captures env to a fixture file; standard pattern from existing spiral BATS tests |

## Source-issue verbatim ACs

- **AC-622** (verbatim from #622 suggested fix): `check_token_window` "should honor `scheduling.enabled`". Documented above as AC-622-1..4.
- **AC-623** (verbatim from #623 suggested fix): "Two surgical exports: SPIRAL_ID after init_state, SPIRAL_CYCLE_NUM per cycle inside simstim_phase()". Documented above as AC-623-1..4.

## Implementation report path

`grimoires/loa/a2a/sprint-bug-622-623/reviewer.md`
