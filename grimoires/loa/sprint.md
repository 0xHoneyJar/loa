# Sprint Plan: Cycle-071 — Spiral Harness Architecture

**Cycle**: 071
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Date**: 2026-04-14

---

## Sprint 1: Evidence Library + Flight Recorder

**Goal**: Build the evidence verification and flight recorder infrastructure.

### Task 1.1: `spiral-evidence.sh` — Evidence Library

**File**: `.claude/scripts/spiral-evidence.sh` (new)
**Functions**:
- `_init_flight_recorder()` — create JSONL file, set seq=0
- `_record_action()` — append entry with seq, timestamp, phase, actor, checksums, cost
- `_record_failure()` — record gate failure with reason
- `_record_evidence()` — record artifact verification
- `_verify_artifact()` — check file exists, min size, return sha256
- `_verify_flatline_output()` — check valid JSON, has consensus_summary
- `_verify_review_verdict()` — check APPROVED or CHANGES_REQUIRED
- `_get_cumulative_cost()` — sum cost_usd from flight recorder
- `_summarize_flatline()` — extract findings summary for prompt cascading
**AC**:
- [ ] Flight recorder JSONL created at cycle_dir/flight-recorder.jsonl
- [ ] Entries append-only (never modify existing)
- [ ] Seq numbers monotonically increase
- [ ] Checksums computed via sha256sum
- [ ] Missing artifact → return 1 + recorded failure
- [ ] Invalid Flatline JSON → return 1 + recorded failure
- [ ] APPROVED verdict detected, CHANGES_REQUIRED detected, missing verdict → return 1
- [ ] Cumulative cost sums correctly from JSONL entries
- [ ] Flatline summary extracts HIGH_CONSENSUS + BLOCKER descriptions

### Task 1.2: Evidence Tests

**File**: `tests/unit/spiral-evidence.bats` (new)
**AC**:
- [ ] Flight recorder init creates file with 600 permissions
- [ ] _record_action appends valid JSONL
- [ ] Seq numbers increment monotonically
- [ ] _verify_artifact passes for valid file, fails for missing/empty
- [ ] _verify_flatline_output passes for valid consensus, fails for invalid
- [ ] _verify_review_verdict detects "All good", "CHANGES_REQUIRED", missing verdict
- [ ] _get_cumulative_cost sums correctly
- [ ] _summarize_flatline extracts findings text

---

## Sprint 2: Harness Orchestrator + Integration

**Goal**: Build the harness, wire it into dispatch, run E2E.

### Task 2.1: `spiral-harness.sh` — Main Orchestrator

**File**: `.claude/scripts/spiral-harness.sh` (new)
**Interface**: `--task`, `--cycle-dir`, `--cycle-id`, `--branch`, `--budget`, `--seed-context`
**Features**:
- Sources `spiral-evidence.sh` for flight recorder
- Sequences 6 phases + 6 gates
- Each phase calls scoped `claude -p` with bounded prompt
- Each gate calls bash scripts (Flatline, Bridgebuilder) or independent `claude -p` (Review, Audit)
- `_run_gate()` with retry (max 3) + circuit breaker
- Flatline findings cascade to next phase's prompt via `_summarize_flatline()`
- Budget enforcement via `_get_cumulative_cost()` check before each phase
**AC**:
- [ ] Phases execute in correct order: DISCOVERY → FLATLINE_PRD → ARCHITECTURE → FLATLINE_SDD → PLANNING → FLATLINE_SPRINT → IMPLEMENT → REVIEW → AUDIT → PR → BRIDGEBUILDER
- [ ] Each `claude -p` call uses `--allow-dangerously-skip-permissions --dangerously-skip-permissions`
- [ ] Flatline gates call `flatline-orchestrator.sh` directly (bash, not LLM)
- [ ] Review/Audit are independent sessions (diff-based, no implementation context)
- [ ] Gate failure retries preceding phase (max 3)
- [ ] 3 consecutive failures → circuit breaker halt
- [ ] Budget exceeded → halt with BUDGET_EXCEEDED in flight recorder

### Task 2.2: Scoped Prompts

**In**: `spiral-harness.sh`
**Prompts for**: Discovery, Architecture, Planning, Implementation, Review, Audit
**AC**:
- [ ] Each prompt instructs ONE task only (no "run the whole pipeline")
- [ ] Each prompt includes "Do NOT" constraints for out-of-scope actions
- [ ] Architecture prompt includes Flatline PRD findings summary
- [ ] Planning prompt includes Flatline SDD findings summary
- [ ] Review prompt receives git diff, not implementation session context
- [ ] All prompts constructed via `jq --arg` (safe)

### Task 2.3: Dispatch Integration

**File**: `.claude/scripts/spiral-simstim-dispatch.sh` (modify)
**Change**: Replace `claude -p "$prompt"` with `spiral-harness.sh` invocation
**AC**:
- [ ] Dispatch calls harness with correct args (task, cycle-dir, branch, budget)
- [ ] Harness exit code flows through to dispatch exit handling
- [ ] Sidecar emission reads artifacts from harness output
- [ ] Flight recorder copied to cycle_dir for HARVEST

### Task 2.4: Config

**File**: `.loa.config.yaml`
**AC**:
- [ ] `spiral.harness.enabled: true`
- [ ] Budget keys: planning_budget_usd, implement_budget_usd, review_budget_usd, audit_budget_usd
- [ ] max_phase_retries: 3
- [ ] evidence_dir: .run/spiral-evidence

### Task 2.5: Harness Tests

**File**: `tests/unit/spiral-harness.bats` (new)
**AC**:
- [ ] Arg parsing validates required flags
- [ ] Phase sequencing calls in correct order (mock claude -p with stub)
- [ ] Gate retry on failure (mock failing gate → retry → pass)
- [ ] Circuit breaker after 3 failures
- [ ] Budget check prevents overspend
- [ ] Evidence dir created with proper permissions

### Task 2.6: Regression Tests

**AC**:
- [ ] All existing spiral tests pass (44)
- [ ] All existing vision tests pass (190)
- [ ] All cycle-070 tests pass (38)

---

## Dependencies

```
T1.1 (evidence lib) → T1.2 (evidence tests)
                    → T2.1 (harness uses evidence)
T2.1 (harness) → T2.2 (prompts)
              → T2.3 (dispatch integration)
              → T2.4 (config)
              → T2.5 (harness tests)
              → T2.6 (regression)
```
