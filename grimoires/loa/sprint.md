# Sprint Plan: Cycle-070 — Spiral End-to-End Autonomous

**Cycle**: 070
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Date**: 2026-04-14

---

## Sprint 1: Dispatch + Autonomous Simstim

**Goal**: Rewrite dispatch to use `claude -p`, add `--autonomous` flag, wire config, implement branch chaining.

### Task 1.1: Config — `spiral.enabled` + Task Passthrough (FR-3)

**File**: `.claude/scripts/spiral-orchestrator.sh`, `.loa.config.yaml`
**Changes**:
- Add `spiral.enabled: true` to config
- `cmd_start()` accepts task as positional arg, stores in `spiral-state.json`
- Add `spiral.max_budget_per_cycle_usd`, `spiral.max_total_budget_usd`, `spiral.step_timeouts.*` to config
**AC**:
- [ ] `spiral.enabled: true` in config
- [ ] `/spiral --start "task"` stores task in state
- [ ] `spiral.max_budget_per_cycle_usd` defaults to 10
- [ ] `spiral.max_total_budget_usd` defaults to 50

### Task 1.2: Dispatch Rewrite — `claude -p` (FR-1)

**File**: `.claude/scripts/spiral-simstim-dispatch.sh` (rewrite)
**Changes**:
- Replace `setsid simstim-orchestrator.sh` with `claude -p` invocation
- Validate `claude` CLI on PATH (exit 127 if missing)
- Prompt construction via `jq --arg` (safe, no shell expansion)
- Output parsing: `--output-format json`, regex PR URL extraction
- `--dangerously-skip-permissions` + `--max-budget-usd` from config
- `--model opus` for planning quality
- stdout → `cycle_dir/claude-stdout.json`, stderr → `cycle_dir/claude-stderr.log`
- Mid-cycle failure semantics per PRD IMP-002 exit code table
- Branch name passed to subprocess prompt (not created in parent — Bridgebuilder MEDIUM-3)
**AC**:
- [ ] `claude` not on PATH → exit 127
- [ ] Prompt includes task + seed context + cycle ID + branch instruction
- [ ] `--max-budget-usd` from `spiral.max_budget_per_cycle_usd`
- [ ] `--dangerously-skip-permissions` passed
- [ ] stdout/stderr captured to cycle_dir
- [ ] PR URL extracted from output JSON via regex
- [ ] Missing PR URL → `completed_no_pr` (not failure)
- [ ] Exit 126/127 → abort spiral
- [ ] Dispatch wrapped in `timeout(1)` using `spiral.step_timeouts.simstim_sec` (Flatline SDD SKP-006)

### Task 1.3: Simstim `--autonomous` Flag (FR-2)

**File**: `.claude/scripts/simstim-orchestrator.sh`
**Changes**:
- Accept `--autonomous` in preflight arg parsing (~line 922)
- Export `SIMSTIM_AUTONOMOUS=1` env var
- Record `"mode": "autonomous"` in simstim-state.json
**AC**:
- [ ] `--autonomous` flag accepted without error
- [ ] `SIMSTIM_AUTONOMOUS=1` exported
- [ ] State JSON records `"mode": "autonomous"`
- [ ] Existing HITL mode unaffected when flag absent

### Task 1.4: Branch Chaining + PR Idempotency (FR-5)

**File**: `.claude/scripts/spiral-simstim-dispatch.sh`
**Changes**:
- Compute branch name `feat/spiral-{id}-cycle-{N}`
- Check existing branch via `git rev-parse --verify` (idempotency, SKP-005)
- Check existing PR via `gh pr list --head <branch>` (idempotency)
- Pass parent PR URL from previous cycle's sidecar to dispatch prompt
- Prompt instructs subprocess to reference parent PR in description
**AC**:
- [ ] Branch name follows `feat/spiral-{id}-cycle-{N}` pattern
- [ ] Existing branch detected and reused
- [ ] Existing PR detected and not duplicated
- [ ] Parent PR URL passed to subsequent cycles

### Task 1.5: Status Artifact + Cumulative Budget (IMP-007, Bridgebuilder MEDIUM-5)

**File**: `.claude/scripts/spiral-simstim-dispatch.sh`
**Changes**:
- Write `.run/spiral-status.txt` after each cycle (human-readable)
- Track cumulative spend in `spiral-state.json` field `budget.spent_usd`
- Before dispatch: check `spent_usd >= max_total_budget_usd` → halt
**AC**:
- [ ] `.run/spiral-status.txt` updated after each cycle
- [ ] Status shows cycle number, state, last PR, budget remaining
- [ ] Cumulative spend tracked in state JSON
- [ ] Budget exceeded → spiral halts with `budget_exceeded`

### Task 1.6: Sprint 1 Tests

**File**: `tests/unit/spiral-dispatch.bats` (new), `tests/unit/simstim-autonomous.bats` (new)
**AC**:
- [ ] Dispatch: claude CLI validation, prompt construction, output parsing, exit codes
- [ ] Dispatch: branch idempotency, budget passthrough
- [ ] Autonomous: flag detection, env var export, state recording

---

## Sprint 2: Round-Robin Flatline Arbiter

**Goal**: Add Phase 3 arbiter to Flatline, with rotation, cascade fallback, and trajectory logging.

### Task 2.1: Arbiter Model Selection (FR-4)

**File**: `.claude/scripts/flatline-orchestrator.sh`
**Changes**:
- New function `_select_arbiter()` with phase-based rotation
- Config reading via `mapfile` for YAML list (Bridgebuilder HIGH-2)
- Defaults: opus/gpt-5.3-codex/gemini-2.5-pro
**AC**:
- [ ] PRD phase → opus selected
- [ ] SDD phase → gpt-5.3-codex selected
- [ ] Sprint phase → gemini-2.5-pro selected
- [ ] Empty config → defaults used

### Task 2.2: Arbiter Prompt + Invocation (FR-4)

**File**: `.claude/scripts/flatline-orchestrator.sh`
**Changes**:
- Build arbiter prompt: document excerpt + all findings + all scores
- Invoke via model-adapter.sh `--mode review` (Bridgebuilder LOW-6)
- Parse JSON decisions array from arbiter response
- Max tokens from `flatline_protocol.autonomous_arbiter.max_arbiter_tokens`
**AC**:
- [ ] Prompt includes document, findings, and scores
- [ ] model-adapter.sh invoked with correct `--mode review` interface
- [ ] Arbiter response parsed as JSON decisions array
- [ ] Malformed JSON → treated as model failure (cascade)

### Task 2.3: Provider Cascade (FR-4, SKP-006)

**File**: `.claude/scripts/flatline-orchestrator.sh`
**Changes**:
- `_invoke_arbiter_with_cascade()`: try designated → next → next → auto-reject
- Each fallback logged to trajectory
**AC**:
- [ ] Designated model fails → cascades to next in rotation
- [ ] All 3 fail → conservative auto-reject with logged rationale
- [ ] Each cascade attempt logged

### Task 2.4: Decision Application (FR-4)

**File**: `.claude/scripts/flatline-orchestrator.sh`
**Changes**:
- After arbiter returns, modify consensus JSON:
  - `accept` → move finding to `high_consensus` (arbiter-accepted)
  - `reject` → move to new `arbiter_rejected` array
- Recalculate `consensus_summary` counts
**AC**:
- [ ] Accepted findings appear in `high_consensus` with `arbiter_accepted: true`
- [ ] Rejected findings appear in `arbiter_rejected`
- [ ] Summary counts updated correctly
- [ ] Original findings preserved (not overwritten)

### Task 2.5: Trajectory Logging (FR-4, NFR-4)

**File**: `.claude/scripts/flatline-orchestrator.sh`
**Changes**:
- Log each decision to `grimoires/loa/a2a/trajectory/flatline-arbiter-{date}.jsonl`
- Include: finding_id, phase, arbiter_model, decision, rationale, cascade_attempts
**AC**:
- [ ] Each arbiter decision logged as separate JSONL line
- [ ] Includes finding_id, model, decision, rationale
- [ ] File created with umask 077

### Task 2.6: Config Gate + Integration (FR-6)

**File**: `.loa.config.yaml`, `.claude/scripts/flatline-orchestrator.sh`
**Changes**:
- `flatline_protocol.autonomous_arbiter.enabled` config gate
- Arbiter only invoked when gate is true AND `SIMSTIM_AUTONOMOUS=1`
- Config defaults: enabled: false, rotation: [opus, gpt-5.3-codex, gemini-2.5-pro]
**AC**:
- [ ] `autonomous_arbiter.enabled: false` → arbiter skipped
- [ ] `autonomous_arbiter.enabled: true` + `SIMSTIM_AUTONOMOUS=1` → arbiter runs
- [ ] HITL mode unaffected regardless of config

### Task 2.7: Sprint 2 Tests

**File**: `tests/unit/flatline-arbiter.bats` (new)
**AC**:
- [ ] Arbiter rotation tested for all 3 phases
- [ ] Cascade fallback tested (1 failure, 2 failures, all failures)
- [ ] Decision parsing tested (valid JSON, malformed JSON)
- [ ] Config gate tested (enabled/disabled)
- [ ] Trajectory logging tested

### Task 2.8: Regression Tests

**AC**:
- [ ] All existing spiral tests pass (44)
- [ ] All existing vision tests pass (190)
- [ ] All existing Flatline scoring tests pass (if any)

---

## Dependencies

```
T1.1 (config) ─────→ T1.2 (dispatch rewrite)
                      T1.3 (autonomous flag)
                      T1.4 (branch chaining) ──→ T1.5 (status + budget)
                                                  T1.6 (sprint 1 tests)

T2.1 (arbiter select) ─→ T2.2 (prompt + invoke) ─→ T2.3 (cascade)
                                                     T2.4 (decision apply)
                                                     T2.5 (trajectory)
T2.6 (config gate) ─────────────────────────────────→ T2.7 (tests)
                                                       T2.8 (regression)
```

## Verification Criteria

- Dispatch invokes `claude -p` with correct flags (validated in test, not E2E)
- `--autonomous` flag flows through to simstim state
- Arbiter rotation produces correct model per phase
- Provider cascade works through 3 levels to auto-reject
- All existing tests pass
- Branch naming follows pattern, PR idempotency works
- Budget tracking prevents overspend
