# PRD: Spiral End-to-End — Autonomous Dispatch + Round-Robin Arbiter

**Cycle**: 070
**Parent**: RFC-060 (#483), cycles 063-069
**Depends on**: PR #496 (cycle-069, Vision Registry graduation)
**Date**: 2026-04-14

**Flatline PRD Review (2026-04-14, 3-model consensus, 100% agreement)**:
- 6 HIGH_CONSENSUS auto-integrated (quality metrics, failure semantics, cost hard stop, output schema, status artifact, graceful stop)
- 6 blockers overridden (permissions mitigated, quality parity metrics added, crash recovery exists, MVP bar valid, provider fallback, assumptions section)
- 2 blockers rejected (output parsing already addressed, trajectory logging already safe)

---

## 1. Problem Statement

The spiral infrastructure (cycles 063-069) has all the machinery — state machine, stopping conditions, HARVEST contract, crash recovery, Vision Registry seed context — but cannot run a real multi-cycle loop. Two gaps:

1. **Dispatch gap**: `spiral-simstim-dispatch.sh` calls `simstim-orchestrator.sh` as a shell script, but simstim is an LLM-driven workflow. Each cycle needs a Claude Code session to drive PRD→SDD→Sprint→Implement→Review→Audit. Fix: invoke `claude -p` (non-interactive CLI) per cycle.

2. **HITL bottleneck**: Simstim pauses for Flatline blocker decisions. An autonomous spiral can't pause for human input mid-cycle. Fix: add `--autonomous` simstim mode with a round-robin Flatline arbiter that replaces HITL blocker prompts with model-arbitrated decisions.

Together these close the loop: the user runs `/spiral --start "Build X"`, walks away, and returns to a completed PR with Bridgebuilder review.

> Source: `spiral-simstim-dispatch.sh:71` — calls shell script, not LLM
> Source: `simstim SKILL.md Phase 2` — HITL blocker prompts block autonomous execution

## 2. Goals & Success Metrics

| # | Goal | Metric | Target |
|---|------|--------|--------|
| G1 | `/spiral --start` runs real multi-cycle loop | At least 1 real cycle completes (PRD→PR) | Functional |
| G2 | Each cycle dispatches via `claude -p` subprocess | Subprocess invoked, produces artifacts, exits | Traceable in trajectory |
| G3 | Simstim `--autonomous` auto-proceeds through all phases | No HITL pauses during autonomous execution | Functional |
| G4 | Flatline round-robin arbiter replaces HITL blocker prompts | Arbiter model decides per-finding, rotates per phase | Quality parity with HITL |
| G5 | Cost safety: per-cycle budget cap | `--max-budget-usd` enforced per cycle | Default $10 |
| G6 | Branch chaining: each cycle creates linked PR | PR description references parent cycle's PR | Functional |
| G7 | No regression in existing spiral/simstim tests | All existing tests pass | 190+ tests green |

**Non-goals**: parallel spiral cycles, real-time progress UI, modifying the quality gates themselves (review/audit pipeline preserved).

**Quality parity contract** (Flatline IMP-001): "Quality parity with HITL" is measured by:
- Flatline arbiter decisions logged with full rationale (auditable post-hoc)
- Review/audit cycle preserved (same gates as HITL mode)
- Rollback trigger: if 2 consecutive cycles produce CHANGES_REQUIRED from review, spiral halts and escalates to HITL
- First 3 cycles of any new spiral run generate comparison metrics vs HITL baselines in trajectory

**Graceful stop/resume** (Flatline IMP-009): `/spiral --halt` sets state to HALTED, which is checked between cycles. The currently-running `claude -p` subprocess completes its cycle (not killed mid-work), but no new cycle starts. `/spiral --resume` continues from the halted state.

## 3. User & Stakeholder Context

**Primary user**: Loa maintainer who runs `/spiral --start "Graduate the Vision Registry"`, walks away, and returns to a PR with Bridgebuilder review posted.

**The contract**: The autonomous pipeline must produce the same quality artifacts as the HITL pipeline. The round-robin arbiter ensures multi-model adversarial review happens — just without human blocking.

## 4. Functional Requirements

### FR-1 — `claude -p` Dispatch in spiral-simstim-dispatch.sh

Replace the shell-script invocation at line 71 with a `claude -p` subprocess call:

```bash
claude -p "$prompt" \
  --dangerously-skip-permissions \
  --max-budget-usd "$budget" \
  --model opus \
  --output-format json \
  2>"$cycle_dir/claude-stderr.log"
```

**Prompt construction**: The dispatch prompt must include:
- The task description (from spiral config or CLI arg)
- Seed context (from `seed-context.md` if available)
- Instruction to run `/simstim --autonomous` with the task
- Instruction to create a PR on completion

**Subprocess isolation**:
- Each cycle gets its own `claude -p` invocation (fresh context window)
- `--dangerously-skip-permissions` for autonomous operation
- `--max-budget-usd` from `spiral.max_budget_per_cycle_usd` config (default: $10)
- stdout captured for artifact extraction, stderr logged to `cycle_dir/claude-stderr.log`
- Exit code: 0 = success (PR created), non-zero = cycle failed

**Output parsing**: `--output-format json` returns structured output. Parse for:
- PR URL (extract from final message)
- Artifact presence (reviewer.md, auditor-sprint-feedback.md in working dir)

**Timeout**: Wrapped by spiral's `with_step_timeout` using `spiral.step_timeouts.simstim_sec` (default: 7200 = 2 hours).

**Mid-cycle failure semantics** (Flatline IMP-002): When `claude -p` subprocess fails:
- Exit 0: success — harvest artifacts
- Exit 1-125: application error — mark cycle failed, proceed to HARVEST (fail-closed quality gate stops spiral)
- Exit 124: timeout from `timeout(1)` — same as application error
- Exit 126/127: CLI not found/executable — abort spiral with `dispatch_error`
- Partial artifacts: if PR was created but review/audit incomplete, the PR URL is still harvested and logged. Next cycle's seed context includes the partial state.

**Output parsing contract** (Flatline IMP-004): `claude -p --output-format json` returns structured JSON. Define strict completion schema:
```json
{"type": "result", "result": "<final message text>"}
```
Parse PR URL via regex `https://github.com/[^/]+/[^/]+/pull/[0-9]+` from result text. If no PR URL found after successful exit, log warning and mark cycle as `completed_no_pr`. Fail hard only on malformed JSON (not missing PR URL — the subprocess may have succeeded but not created a PR if review/audit failed).

### FR-2 — Simstim `--autonomous` Flag

New flag for the simstim workflow that auto-proceeds through all phases:

**Structured assumptions** (Flatline SKP-008): Autonomous PRD generation MUST include an `## Assumptions` section listing what the agent assumed in the absence of human Q&A. This surfaces potential misunderstandings for the Flatline arbiter to catch.

| Phase | HITL Behavior | Autonomous Behavior |
|-------|--------------|---------------------|
| 1 (Discovery) | Interactive Q&A | Auto-generate PRD from task description + seed context (with ## Assumptions) |
| 2 (Flatline PRD) | Present blockers | Arbiter decides (FR-4) |
| 3 (Architecture) | Interactive Q&A | Auto-generate SDD from PRD |
| 3.5 (Bridgebuilder) | Present findings | Auto-integrate accepted, auto-defer REFRAME |
| 4 (Flatline SDD) | Present blockers | Arbiter decides (FR-4) |
| 4.5 (Red Team) | Prompt Y/n | Auto-skip (red team is opt-in) |
| 5 (Planning) | Interactive Q&A | Auto-generate sprint plan from PRD+SDD |
| 6 (Flatline Sprint) | Present blockers | Arbiter decides (FR-4) |
| 7 (Implementation) | Prompt Continue? | Auto-proceed to `/run sprint-plan` |

**Detection**: The `--autonomous` flag sets `SIMSTIM_AUTONOMOUS=1` env var, which simstim checks at each HITL decision point.

**State tracking**: `simstim-state.json` records `"mode": "autonomous"` for recovery.

### FR-3 — `spiral.enabled` Config + Task Passthrough

Wire `spiral.enabled: true` in config. Add `spiral.task` field for the task description that passes through to each cycle's simstim:

```yaml
spiral:
  enabled: true
  task: "Graduate the Vision Registry"  # Set by /spiral --start or config
  max_budget_per_cycle_usd: 10
  step_timeouts:
    seed_sec: 30
    simstim_sec: 7200
    harvest_sec: 60
```

The `/spiral --start "task description"` CLI stores the task in `.run/spiral-state.json` and passes it to each cycle's dispatch prompt.

### FR-4 — Flatline Round-Robin Arbiter

New Phase 3 in the Flatline Protocol for autonomous decision-making:

**Current flow** (Phase 1 → Phase 2 → HITL):
```
Phase 1: 3 models review independently
Phase 2: 3 models cross-score
→ HIGH_CONSENSUS: auto-integrate
→ DISPUTED: present to human
→ BLOCKER: present to human
```

**New flow** (Phase 1 → Phase 2 → Phase 3 arbiter):
```
Phase 1: 3 models review independently
Phase 2: 3 models cross-score
Phase 3: Arbiter model sees all findings + scores, decides per-finding
→ HIGH_CONSENSUS: auto-integrate (unchanged)
→ DISPUTED: arbiter decides accept/reject with rationale
→ BLOCKER: arbiter decides override(+rationale)/reject with rationale
```

**Arbiter rotation** (round-robin per Flatline phase):

| Flatline Phase | Arbiter Model | Rationale |
|---------------|---------------|-----------|
| PRD review | Opus | Strongest architectural reasoning |
| SDD review | GPT | Different perspective for architecture |
| Sprint review | Gemini | Third perspective for planning |

Rotation prevents any single model's biases from dominating across the full pipeline. The arbiter has seen all other models' scores, so it makes an informed decision — not a vote, but a reasoned judgment with full context.

**Arbiter prompt**: Receives:
- The original document being reviewed
- All findings (with scores from all models)
- Consensus classification (HIGH_CONSENSUS, DISPUTED, BLOCKER)
- Instruction: "For each DISPUTED or BLOCKER finding, decide: ACCEPT (integrate the suggestion), REJECT (with rationale). Your decision is final for this phase."

**Output**: JSON array of decisions:
```json
[
  {"finding_id": "SKP-001", "decision": "accept", "rationale": "Valid security concern..."},
  {"finding_id": "IMP-005", "decision": "reject", "rationale": "Already addressed by..."}
]
```

**Trajectory logging**: All arbiter decisions logged with full context (finding, scores, rationale) to `grimoires/loa/a2a/trajectory/flatline-arbiter-{date}.jsonl`.

**Config gate**:
```yaml
flatline_protocol:
  autonomous_arbiter:
    enabled: true
    rotation: [opus, gpt-5.3-codex, gemini-2.5-pro]
```

**Fallback** (Flatline SKP-006): If arbiter call fails (timeout, API error), cascade to next model in rotation. If all 3 fail, fall back to conservative auto-reject for BLOCKERs. Log each fallback attempt to trajectory.

**Provider cascade**: Opus fails → try GPT → try Gemini → auto-reject. This 3-model cascade ensures arbiter availability even with single-provider outages.

### FR-5 — Branch Chaining for Multi-Cycle PRs

Each spiral cycle creates a new branch and PR that chains back to the previous:

**Branch naming**: `feat/spiral-{spiral_id}-cycle-{N}` (e.g., `feat/spiral-abc123-cycle-1`)

**Idempotency** (Flatline SKP-005): Before creating branch, check `git branch --list "feat/spiral-*-cycle-$N"`. Before creating PR, check `gh pr list --head <branch> --json number`. If branch/PR already exist, reuse them instead of creating duplicates.

**PR description includes**:
- Parent PR reference: `Parent: #NNN` (links to previous cycle's PR)
- Cycle number and spiral ID for traceability
- Seed context summary (what findings from the previous cycle informed this one)

**Implementation in dispatch wrapper**:
1. Before invoking `claude -p`, create the branch from current HEAD
2. Pass `--branch` info to the simstim prompt
3. After cycle completes, harvest the PR URL from the subprocess output
4. Store in `cycle-outcome.json` sidecar as `pr_url` field
5. Next cycle's seed context includes the previous PR URL for linking

### FR-6 — Config Extensions

```yaml
spiral:
  enabled: true
  task: ""                              # Set dynamically by --start
  max_budget_per_cycle_usd: 10          # Per-cycle cost cap
  max_total_budget_usd: 50              # Spiral-level hard stop (Flatline IMP-003)
  status_file: ".run/spiral-status.txt" # Lightweight status artifact (Flatline IMP-007)
  step_timeouts:
    seed_sec: 30
    simstim_sec: 7200                   # 2 hours per cycle
    harvest_sec: 60

flatline_protocol:
  autonomous_arbiter:
    enabled: false                      # Opt-in (graduates to true when proven)
    rotation:
      - opus
      - gpt-5.3-codex
      - gemini-2.5-pro
    fallback: "reject"                  # Conservative fallback on arbiter failure
    max_arbiter_tokens: 4000            # Budget for arbiter response
```

## 5. Technical & Non-Functional Requirements

| NFR | Requirement |
|-----|-------------|
| NFR-1 | `claude` CLI must be on PATH (validated at dispatch time) |
| NFR-2 | Each cycle subprocess fully isolated (own context, own state) |
| NFR-3 | Arbiter API call budget: single call per Flatline phase (~$0.50) |
| NFR-4 | All arbiter decisions logged to trajectory JSONL |
| NFR-5 | Existing HITL mode unchanged — autonomous is opt-in via flag |
| NFR-6 | `--dangerously-skip-permissions` only used in spiral subprocess, not main session |

## 6. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `claude -p` subprocess fails mid-cycle | Medium | Medium | HARVEST fail-closed; cycle marked failed; spiral continues to next |
| Arbiter makes poor decisions | Medium | Medium | Trajectory logging enables post-hoc review; fallback to conservative reject |
| Context window insufficient for single cycle | Low | High | Simstim autonomous uses same phases; context managed by Claude Code |
| Cost overrun across cycles | Medium | Low | Per-cycle budget cap + spiral-level hard stop (IMP-003) |
| `--dangerously-skip-permissions` security concern | Low | Medium | Subprocess runs in same directory with same user permissions; no escalation |

**Dependencies**: PR #496 (Vision Registry, seed_phase full mode), `claude` CLI on PATH.

## 7. Acceptance Criteria

- [ ] `spiral-simstim-dispatch.sh` invokes `claude -p` with correct flags
- [ ] `claude` CLI availability validated before dispatch (exit 127 if missing)
- [ ] Per-cycle budget cap enforced via `--max-budget-usd`
- [ ] Subprocess stdout/stderr captured to cycle_dir logs
- [ ] Simstim `--autonomous` flag auto-proceeds through all phases
- [ ] Autonomous discovery generates PRD from task + seed context without Q&A
- [ ] Autonomous Flatline uses arbiter instead of HITL prompts
- [ ] Arbiter rotation: Opus→PRD, GPT→SDD, Gemini→Sprint
- [ ] Arbiter decisions logged to trajectory with full context
- [ ] Arbiter fallback to conservative reject on failure
- [ ] `spiral.enabled: true` wired in config
- [ ] `spiral.task` passes through to dispatch prompt
- [ ] Each cycle creates a new branch `feat/spiral-{id}-cycle-{N}`
- [ ] PR description chains back to parent PR
- [ ] All existing tests pass (190+)
- [ ] New tests cover: dispatch invocation, autonomous flag, arbiter rotation, branch chaining
- [ ] E2E: 1 real spiral cycle with `SPIRAL_REAL_DISPATCH=1` produces a PR

### Sources

- `.claude/scripts/spiral-simstim-dispatch.sh` (dispatch wrapper)
- `.claude/scripts/spiral-orchestrator.sh` (cycle loop, seed_phase)
- `.claude/scripts/flatline-orchestrator.sh` (Flatline phases 1-2, new phase 3)
- `.claude/scripts/simstim-orchestrator.sh` (simstim state + preflight)
- `.claude/skills/simstim-workflow/SKILL.md` (simstim phases)
