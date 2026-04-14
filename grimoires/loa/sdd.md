# SDD: Spiral End-to-End — Autonomous Dispatch + Round-Robin Arbiter

**Cycle**: 070
**PRD**: `grimoires/loa/prd.md`
**Date**: 2026-04-14

---

## 1. System Architecture

### 1.1 Component Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    /spiral CLI (existing)                        │
│  spiral-orchestrator.sh                                         │
│  cmd_start() → cycle loop → seed → dispatch → harvest → gate   │
└───────────────────────┬─────────────────────────────────────────┘
                        │ invokes per cycle
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│              Dispatch Layer (MODIFIED — FR-1)                    │
│  spiral-simstim-dispatch.sh                                     │
│  OLD: setsid simstim-orchestrator.sh --preflight                │
│  NEW: claude -p "/simstim --autonomous ..." --dangerously-skip  │
│       --max-budget-usd $10 --output-format json                 │
└───────────────────────┬─────────────────────────────────────────┘
                        │ subprocess (fresh context)
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│           Simstim Autonomous Mode (NEW — FR-2)                  │
│  /simstim --autonomous "task description"                       │
│  Phases 1-8 auto-proceed, no HITL pauses                        │
│  Flatline uses arbiter instead of human prompts                 │
└───────────────────────┬─────────────────────────────────────────┘
                        │ for DISPUTED/BLOCKER findings
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│           Flatline Phase 3: Arbiter (NEW — FR-4)                │
│  flatline-orchestrator.sh                                       │
│  Phase 1: 3 models review → Phase 2: cross-score               │
│  Phase 3: arbiter sees all findings+scores, decides per-finding │
│  Rotation: PRD→Opus, SDD→GPT, Sprint→Gemini                    │
│  Cascade: designated→next→next→auto-reject                      │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 File Inventory

| File | Action | Zone | Authorization |
|------|--------|------|---------------|
| `.claude/scripts/spiral-simstim-dispatch.sh` | **Rewrite** | System | PRD cycle-070 FR-1 |
| `.claude/scripts/flatline-orchestrator.sh` | **Modify** | System | PRD cycle-070 FR-4 |
| `.claude/scripts/simstim-orchestrator.sh` | **Modify** | System | PRD cycle-070 FR-2 |
| `.claude/scripts/spiral-orchestrator.sh` | **Modify** | System | PRD cycle-070 FR-3 |
| `.loa.config.yaml` | **Modify** | State | PRD cycle-070 FR-6 |
| `tests/unit/spiral-dispatch.bats` | **New** | App | Standard |
| `tests/unit/flatline-arbiter.bats` | **New** | App | Standard |
| `tests/unit/simstim-autonomous.bats` | **New** | App | Standard |

## 2. Component Design

### 2.1 Dispatch Rewrite — `spiral-simstim-dispatch.sh` (FR-1)

**Current** (line 71): `setsid "$SIMSTIM_SCRIPT" "${simstim_flags[@]}"`
**New**: `claude -p "$prompt" <flags>`

**Dispatch flow**:

```bash
_dispatch_cycle() {
  local cycle_dir="$1" cycle_id="$2" task="$3" seed_context="$4"

  # 1. Validate claude CLI
  if ! command -v claude &>/dev/null; then
    error "claude CLI not found on PATH"
    return 127
  fi

  # 2. Build prompt
  local prompt
  prompt=$(_build_dispatch_prompt "$task" "$seed_context" "$cycle_id")

  # 3. Read budget from config
  # Note: spiral-orchestrator.sh uses spiral.budget_cents (cents, default 2000) for
  # the spiral-level stopping condition. Per-cycle dispatch uses dollars for claude -p.
  # Convert: budget_cents / 100, capped by max_budget_per_cycle_usd (Bridgebuilder HIGH-1)
  local budget
  budget=$(read_config "spiral.max_budget_per_cycle_usd" "10")

  # 4. Branch name computed here, but creation happens INSIDE the subprocess
  # (Bridgebuilder MEDIUM-3: branch checkout in parent causes git working tree
  # contention with harvest phase reading files concurrently)
  local branch_name="feat/spiral-${SPIRAL_ID}-cycle-${CYCLE_NUM}"

  # 5. Invoke claude -p (branch creation is part of the prompt instruction)
  local exit_code=0
  # Dispatch timeout via timeout(1) (Flatline SDD SKP-006)
  local dispatch_timeout
  dispatch_timeout=$(read_config "spiral.step_timeouts.simstim_sec" "7200")

  timeout "$dispatch_timeout" \
    claude -p "$prompt" \
      --dangerously-skip-permissions \
      --max-budget-usd "$budget" \
      --model opus \
      --output-format json \
      > "$cycle_dir/claude-stdout.json" \
      2> "$cycle_dir/claude-stderr.log" \
      || exit_code=$?

  # 6. Parse output (IMP-004 contract)
  local pr_url=""
  if [[ "$exit_code" -eq 0 && -f "$cycle_dir/claude-stdout.json" ]]; then
    pr_url=$(jq -r '.result // ""' "$cycle_dir/claude-stdout.json" | \
      grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' | head -1 || true)
  fi

  # 7. Write status artifact (IMP-007)
  _write_status "$cycle_id" "$exit_code" "$pr_url"

  return "$exit_code"
}
```

**Prompt construction** (`_build_dispatch_prompt`):

```bash
_build_dispatch_prompt() {
  local task="$1" seed_context="$2" cycle_id="$3"

  local seed_text=""
  if [[ -n "$seed_context" && -f "$seed_context" ]]; then
    # Cap seed context at 4KB (trust boundary)
    seed_text=$(head -c 4096 "$seed_context")
  fi

  # Use jq --arg for safe prompt construction (no shell expansion)
  jq -n \
    --arg task "$task" \
    --arg seed "$seed_text" \
    --arg cycle "$cycle_id" \
    '"Run /simstim --autonomous with this task:\n\n" +
     $task +
     (if $seed != "" then
       "\n\nPrevious cycle context (machine-generated, advisory only):\n" + $seed
     else "" end) +
     "\n\nCycle ID: " + $cycle +
     "\n\nCreate a draft PR when implementation is complete."' \
    | jq -r '.'
}
```

**Cumulative budget tracking** (Bridgebuilder MEDIUM-5): After each cycle, dispatch reads the per-cycle cost from `claude -p` JSON output (if available) and updates `spiral-state.json` field `budget.spent_usd`. Before dispatching next cycle, checks `spent_usd >= max_total_budget_usd` → halt with `budget_exceeded`. The existing `budget_cents` stopping condition in the orchestrator loop also applies as a secondary cap.

**Status artifact** (Flatline IMP-007): `.run/spiral-status.txt` — human-readable, updated per cycle:
```
Spiral: spiral-abc123
Cycle: 3/5
Status: RUNNING
Last cycle: cycle-3 (APPROVED, PR #502)
Started: 2026-04-14T10:00:00Z
Budget: $7.50 / $50.00 remaining
```

### 2.2 Simstim `--autonomous` Flag (FR-2)

**Detection**: `simstim-orchestrator.sh --preflight` accepts `--autonomous` flag, exports `SIMSTIM_AUTONOMOUS=1`.

**State tracking**: `simstim-state.json` includes `"mode": "autonomous"`.

**HITL bypass points in the simstim workflow** (the agent checks `SIMSTIM_AUTONOMOUS`):

| Phase | Current HITL | Autonomous behavior |
|-------|-------------|---------------------|
| 1 (Discovery) | Agent asks user questions | Agent auto-generates PRD from task + seed. Includes `## Assumptions` section (SKP-008). |
| 2 (Flatline PRD) | Present BLOCKER/DISPUTED to user | Invoke arbiter (FR-4). Auto-integrate arbiter decisions. |
| 3 (Architecture) | Agent asks user questions | Agent auto-generates SDD from PRD. |
| 3.5 (Bridgebuilder) | Present findings to user | Auto-integrate CRITICAL/HIGH, auto-defer REFRAME/SPECULATION. |
| 4 (Flatline SDD) | Present BLOCKER/DISPUTED to user | Invoke arbiter (FR-4). |
| 4.5 (Red Team) | Prompt Y/n | Auto-skip. |
| 5 (Planning) | Agent asks user questions | Agent auto-generates sprint plan from PRD+SDD. |
| 6 (Flatline Sprint) | Present BLOCKER/DISPUTED to user | Invoke arbiter (FR-4). |
| 7 (Implementation) | Prompt Continue? | Auto-proceed to `/run sprint-plan`. |

**Implementation**: This is NOT code in `simstim-orchestrator.sh` — it's behavioral guidance for the LLM agent running `/simstim`. The `--autonomous` flag signals to the agent that it should auto-proceed rather than waiting for human input. The flag is passed through the dispatch prompt: `"Run /simstim --autonomous"`.

The `simstim-orchestrator.sh` changes are minimal:
1. Accept `--autonomous` flag in preflight arg parsing (~line 922)
2. Export `SIMSTIM_AUTONOMOUS=1` env var
3. Record `"mode": "autonomous"` in state JSON

### 2.3 Flatline Phase 3: Round-Robin Arbiter (FR-4)

**Location**: `flatline-orchestrator.sh`, new section after consensus calculation (~line 1235).

**Trigger**: Only when `flatline_protocol.autonomous_arbiter.enabled: true` AND `SIMSTIM_AUTONOMOUS=1` (autonomous mode). In HITL mode, existing behavior unchanged — human decides on blockers. (Bridgebuilder MEDIUM-4: corrected from erroneous `hitl` trigger condition.)

**Flow**:

```
Consensus calculated (line 1235)
  ↓
if autonomous_arbiter.enabled AND (disputed_count > 0 OR blocker_count > 0):
  ↓
  Select arbiter model (rotation based on phase)
  ↓
  Build arbiter prompt: document + all findings + all scores
  ↓
  Invoke arbiter via model-adapter.sh (single API call)
  ↓
  Parse arbiter decisions JSON
  ↓
  Apply decisions: accept→move to high_consensus, reject→remove from blockers
  ↓
  Log all decisions to trajectory
  ↓
  Recalculate consensus summary with arbiter modifications
```

**Arbiter model selection**:

```bash
_select_arbiter() {
  local phase="$1"
  # read_config returns YAML list as newline-delimited string, not bash array
  # (Bridgebuilder HIGH-2: must use mapfile, not direct indexing)
  local rotation_raw
  rotation_raw=$(read_config "flatline_protocol.autonomous_arbiter.rotation" "")
  local rotation=()
  if [[ -n "$rotation_raw" ]]; then
    mapfile -t rotation < <(echo "$rotation_raw" | sed 's/^- //')
  fi

  # Defaults if config empty
  [[ ${#rotation[@]} -lt 3 ]] && rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")

  # Phase-based selection
  case "$phase" in
    prd)    echo "${rotation[0]}" ;;
    sdd)    echo "${rotation[1]}" ;;
    sprint) echo "${rotation[2]}" ;;
    *)      echo "${rotation[0]}" ;;
  esac
}
```

**Arbiter prompt structure**:

```
You are the arbiter for this Flatline review. You have seen all models'
independent reviews and cross-scores. For each DISPUTED or BLOCKER finding,
make a final decision.

Document under review: [phase] - [truncated document, max 2K tokens]

Findings requiring your decision:
[JSON array of disputed + blocker findings with all scores]

For each finding, respond with a JSON array:
[{"finding_id": "...", "decision": "accept"|"reject", "rationale": "..."}]

Decide based on: (1) strength of evidence, (2) severity of concern,
(3) whether the concern is already addressed elsewhere in the document.
Err on the side of accepting well-reasoned suggestions and rejecting
concerns that are theoretical without practical impact.
```

**Arbiter invocation** via model-adapter.sh:

```bash
_invoke_arbiter() {
  local arbiter_model="$1"
  local prompt_file="$2"
  local max_tokens
  max_tokens=$(read_config "flatline_protocol.autonomous_arbiter.max_arbiter_tokens" "4000")

  # model-adapter.sh uses --mode (not --agent) and --model for provider:id
  # (Bridgebuilder LOW-6: corrected interface to match actual adapter API)
  "$SCRIPT_DIR/model-adapter.sh" \
    --mode "review" \
    --model "$arbiter_model" \
    --input "$prompt_file" \
    --timeout 120 \
    --max-tokens "$max_tokens"
}
```

**Design tradeoff** (Bridgebuilder REFRAME): The spiral's multi-cycle nature means auto-reject + defer could replace the arbiter — deferred concerns resurface next cycle with fresh context. But the arbiter integrates good suggestions immediately ($0.50/phase) vs waiting a full cycle to re-discover them. Teams that prefer the cheaper defer-and-iterate pattern can disable the arbiter via config.

**Provider cascade** (Flatline SKP-006):

```bash
_invoke_arbiter_with_cascade() {
  local phase="$1" prompt_file="$2"
  local rotation=("opus" "gpt-5.3-codex" "gemini-2.5-pro")

  # Determine starting index from phase
  local start_idx
  case "$phase" in
    prd) start_idx=0 ;;
    sdd) start_idx=1 ;;
    sprint) start_idx=2 ;;
    *) start_idx=0 ;;
  esac

  # Try designated arbiter, then cascade
  for i in 0 1 2; do
    local idx=$(( (start_idx + i) % 3 ))
    local model="${rotation[$idx]}"

    local result
    result=$(_invoke_arbiter "$model" "$prompt_file" 2>/dev/null) && {
      log "Arbiter: $model decided (phase: $phase)"
      echo "$result"
      return 0
    }
    log "WARNING: Arbiter $model failed, cascading..."
  done

  # All models failed — conservative fallback
  log "WARNING: All arbiter models failed, auto-rejecting blockers"
  _fallback_reject_all "$prompt_file"
}
```

**Decision application**: After arbiter returns decisions, modify the consensus JSON:
- `accept` → move finding from `blockers`/`disputed` to `high_consensus` (arbiter-accepted)
- `reject` → remove from `blockers`/`disputed`, add to a new `arbiter_rejected` array

**Trajectory logging**: Each arbiter decision logged to `grimoires/loa/a2a/trajectory/flatline-arbiter-{date}.jsonl`:
```json
{
  "type": "flatline_arbiter",
  "phase": "prd",
  "arbiter_model": "opus",
  "finding_id": "SKP-001",
  "original_classification": "BLOCKER",
  "decision": "accept",
  "rationale": "Valid security concern...",
  "cascade_attempts": 1,
  "timestamp": "2026-04-14T..."
}
```

### 2.4 Spiral Config + Task Passthrough (FR-3)

**`spiral-orchestrator.sh` changes**:

1. `cmd_start()` accepts task as positional arg: `/spiral --start "Build feature X"`
2. Task stored in `spiral-state.json` as `"task": "Build feature X"`
3. Each cycle reads task from state and passes to dispatch
4. `spiral.enabled: true` checked at startup (existing pattern)

### 2.5 Branch Chaining (FR-5)

**Per-cycle branch creation** in dispatch wrapper:

```bash
local branch_name="feat/spiral-${SPIRAL_ID}-cycle-${CYCLE_NUM}"

# Idempotency: check existing branch/PR (SKP-005)
if git rev-parse --verify "$branch_name" &>/dev/null; then
  log "Branch $branch_name already exists, reusing"
  git checkout "$branch_name"
else
  git checkout -b "$branch_name"
fi
```

**PR chaining**: The dispatch prompt includes instruction to reference parent PR:
```
If this is cycle 2+, reference the parent PR in the description:
Parent: #{parent_pr_number}
```

Parent PR number read from previous cycle's `cycle-outcome.json` sidecar `pr_url` field.

## 3. Security Design

| Input | Risk | Mitigation |
|-------|------|------------|
| Task text (from user) | Prompt injection into `claude -p` | Task comes from user who invoked `/spiral` — trusted by definition |
| Seed context (from HARVEST) | Indirect prompt injection | `vision_sanitize_text()` applied; prefixed "machine-generated, advisory only" |
| `--dangerously-skip-permissions` | Unrestricted tool access | Same user workspace, same permissions. Safety hooks (`block-destructive-bash.sh`) still active. |
| Arbiter prompt | Manipulation via crafted findings | Findings come from our own Flatline models, not external input |
| Config values | Path injection | `read_config` returns strings passed to `--arg` in jq, not shell-expanded |

## 4. Error Handling

### 4.1 Dispatch Failure Recovery

| Exit Code | Meaning | Spiral Action |
|-----------|---------|---------------|
| 0 | Success | Harvest artifacts, continue |
| 1-125 | Application error | Mark cycle failed, HARVEST (fail-closed gate stops spiral) |
| 124 | Timeout | Same as application error |
| 126/127 | CLI missing | Abort spiral with `dispatch_error` |

### 4.2 Arbiter Failure Recovery

| Failure | Action |
|---------|--------|
| Designated model timeout | Cascade to next model in rotation |
| All 3 models fail | Conservative auto-reject for all BLOCKERs |
| Malformed arbiter JSON | Log error, treat as model failure, cascade |
| Arbiter accepts everything | Valid — arbiter has full context to make this call |

### 4.3 Quality Parity Rollback (IMP-001)

If 2 consecutive cycles produce CHANGES_REQUIRED from review:
1. Spiral halts with `quality_escalation` state
2. Status artifact updated: "ESCALATED — 2 consecutive review failures"
3. User must run `/spiral --resume` with HITL override to continue

## 5. Testing Strategy

### 5.1 Test Files

| File | Coverage |
|------|----------|
| `tests/unit/spiral-dispatch.bats` | FR-1: claude CLI validation, prompt construction, output parsing, exit code handling, branch idempotency |
| `tests/unit/flatline-arbiter.bats` | FR-4: arbiter rotation, cascade fallback, decision parsing, trajectory logging |
| `tests/unit/simstim-autonomous.bats` | FR-2: autonomous flag detection, state recording, env var export |

### 5.2 Key Test Cases

**Dispatch**:
- `claude` not on PATH → exit 127
- Prompt includes task + seed context + cycle ID
- Output JSON parsed for PR URL regex
- Missing PR URL → `completed_no_pr` (not failure)
- Branch already exists → reuse (idempotent)
- Budget passed through from config

**Arbiter**:
- PRD phase → Opus selected as arbiter
- SDD phase → GPT selected
- Sprint phase → Gemini selected
- Designated model fails → cascades to next
- All 3 fail → conservative auto-reject
- Arbiter decisions modify consensus JSON correctly
- Each decision logged to trajectory

**Autonomous**:
- `--autonomous` flag sets `SIMSTIM_AUTONOMOUS=1`
- State records `"mode": "autonomous"`
- Flag survives preflight and reaches state JSON

## 6. Implementation Order

### Sprint 1: Dispatch + Autonomous Simstim
1. **T1.1**: `spiral.enabled` config + task passthrough in spiral-orchestrator.sh
2. **T1.2**: Rewrite `spiral-simstim-dispatch.sh` — `claude -p` invocation, prompt construction, output parsing
3. **T1.3**: `--autonomous` flag in simstim-orchestrator.sh (flag parsing, env var, state)
4. **T1.4**: Branch chaining + PR idempotency in dispatch wrapper
5. **T1.5**: Status artifact (`.run/spiral-status.txt`)
6. **T1.6**: Tests for dispatch + autonomous flag

### Sprint 2: Round-Robin Arbiter
7. **T2.1**: Arbiter model selection (`_select_arbiter`) with phase-based rotation
8. **T2.2**: Arbiter prompt construction + invocation via model-adapter.sh
9. **T2.3**: Provider cascade (`_invoke_arbiter_with_cascade`)
10. **T2.4**: Decision application — modify consensus JSON (accept/reject)
11. **T2.5**: Trajectory logging for arbiter decisions
12. **T2.6**: Config gate (`flatline_protocol.autonomous_arbiter.enabled`)
13. **T2.7**: Tests for arbiter rotation, cascade, decision parsing
14. **T2.8**: Config updates + integration test
