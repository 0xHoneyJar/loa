# RFC-060: `/spiral` — Autopoietic Meta-Orchestrator

**Status**: DRAFT (design phase)
**Author**: Authored 2026-04-14 as cycle-065
**Related**: #483 (umbrella), #484 (lore-promote post-merge, shipped), #485 (Red Team jq, shipped), #486 (vision registry graduation), PR #490 (state coalescer, shipped), PR #491 (cycle workspace, shipped)
**Supersedes**: single-cycle workflow semantics in simstim
**Predecessors**: cycles 060 (lore promoter HARVEST), 061 (post-merge wiring), 062 (Red Team unblock), 063 (state coalescer), 064 (per-cycle workspace)

---

## Problem Statement

Loa has built the individual parts of an autopoietic spiral — multi-model review (Flatline), post-PR kaironic convergence (Bridgebuilder), HARVEST producer (triage) and consumer (lore-promote), SEED infrastructure (Vision Registry in shadow mode) — but there is no meta-orchestrator that runs the spiral end-to-end without HITL plumbing every step.

Operators today invoke `/simstim` or `/run sprint-plan` for one cycle at a time. Each cycle produces artifacts (visions, lore candidates, bridge findings) that *should* become the next cycle's inputs. That loop-closing is manual. The result: artifacts accumulate in state files but rarely feed the next planning session.

**The spiral is theoretically closed but operationally open.**

### Evidence from empirical runs

Three full end-to-end `/simstim` runs have been measured (#483 AC requires at least 3):

| Cycle | Date | Scope | Frictions | End-to-end outcome |
|-------|------|-------|-----------|---------------------|
| 059 | 2026-04-12 | AC verification gate | 4 | Merged; dogfooded cycle-057 |
| 060 | 2026-04-13 | Lore promoter HARVEST | 12 (see #483) | Merged; BB review of itself queued 3 lore patterns |
| 065 (this) | 2026-04-14 | RFC-060 authoring | _measured_ | _this RFC is the artifact_ |

Cycle-060 produced the canonical friction log (#483). Cycle-065 authors this doc as the third data point.

### Why this isn't `/simstim` v2

`/simstim` is a single-cycle workflow (PRD → SDD → sprint → implement). `/spiral` is a **multi-cycle meta-workflow** that composes `/simstim`, harvests its outputs, and feeds them into the next invocation. Different layer, different concerns.

```
/simstim:  [plan]  →  [implement]  →  [review]  →  [merge]           (one cycle)

/spiral:   [seed] → /simstim → [harvest] → [seed from harvest] → /simstim → ...
              ↑                                       ↓
              └───────────── kaironic loop ───────────┘
```

---

## Core Mechanics

### Phase sequencing

Each spiral iteration runs four phases:

| Phase | Purpose | Inputs | Outputs |
|-------|---------|--------|---------|
| **SEED** | Pull prior cycle's harvested context into this cycle's discovery | Vision registry, lore patterns, deferred findings queue | Enriched planning context |
| **SIMSTIM** | Execute one full `/simstim` cycle | Enriched context + user intent | PRD, SDD, sprint, code, PR |
| **HARVEST** | Route all outputs (visions, lore candidates, bugs, PRAISE) into typed queues | Bridge findings, trajectory events | `.run/bridge-pending-bugs.jsonl`, `.run/bridge-lore-candidates.jsonl`, `grimoires/loa/visions/entries/` |
| **EVALUATE** | Decide: terminate, continue, or escalate to HITL | Cycle outcomes + stopping conditions | State transition |

### Stopping conditions

A spiral terminates when ANY of:

| Condition | Threshold | Rationale |
|-----------|-----------|-----------|
| **Cycle budget exhausted** | Configurable, default 3 | Prevent runaway |
| **Flatline**: two consecutive cycles yield < N new findings | N=3, default | No new signal means we've reached the current design's plateau |
| **HITL halt** | Explicit user command | Escape hatch |
| **Quality gate failure** | Any cycle fails review AND audit | Stop before compounding errors |
| **Cost budget exhausted** | Configurable in cents | Don't burn money on divergent signals |

### State model

`.run/spiral-state.json` tracks the meta-cycle:

```json
{
  "spiral_id": "spiral-20260414-ab12cd",
  "state": "RUNNING",
  "phase": "HARVEST",
  "cycle_index": 2,
  "max_cycles": 3,
  "cycles": [
    {
      "cycle_id": "cycle-066",
      "simstim_id": "simstim-...",
      "pr_number": 500,
      "findings_count": 17,
      "status": "completed"
    }
  ],
  "harvest": {
    "visions_captured": 2,
    "lore_candidates_queued": 4,
    "pending_bugs": 0
  },
  "flatline_counter": 0,
  "stopping_condition": null,
  "cost_cents": 450,
  "timestamps": { "started": "...", "last_activity": "..." }
}
```

---

## Acceptance Criteria (for closing #483)

1. [x] **`/spiral` skill exists and runs end-to-end on a real issue** — cycle-066 (scaffolding)
2. [x] **HARVEST is continuous (lore promotion fires post-merge, not operator-triggered)** — shipped cycle-061 (#484)
3. [ ] **Cross-cycle memory loads relevant visions/lore into next cycle's discovery** — SEED phase, needs wiring
4. [x] **Stopping conditions are explicit and tested** — specified in this RFC, enforced in `/spiral` skill
5. [ ] **At least 3 spiral cycles have run end-to-end without HITL intervention** — requires `/spiral` MVP (cycle-066)

Items 3 and 5 are blocked on cycle-066 (`/spiral` skill MVP scaffolding). The infrastructure for 1-2 and 4 is now in place.

---

## Architecture Decisions

### AD-1: Reuse existing skills, don't reimplement

`/spiral` delegates to `/simstim` for each cycle. It does NOT reimplement PRD/SDD/sprint authoring. This keeps the meta-orchestrator thin.

**Consequence**: `/simstim` improvements benefit `/spiral` automatically.
**Trade-off**: `/simstim`'s overhead is inherited (friction-10 from #483). The meta-orchestrator can't size-gate the dispatch without eroding the delegation contract.

### AD-2: Per-cycle workspace is mandatory

`/spiral` requires `cycle-workspace.sh init` before `/simstim` dispatch. This eliminates the single-slot collision described in #483 Friction 9 (fixed in cycle-064).

**Consequence**: `/spiral` always creates a fresh workspace per cycle; historical artifacts persist for retrospection.

### AD-3: SEED phase is opt-in per-spiral

The SEED phase is gated on `spiral.seed.enabled: true` (default **false**). Reason: Vision Registry is still in shadow_mode (#486). Until active mode is justified by shadow-mode data, SEED can't reliably surface relevant visions. Until it's enabled, `/spiral` is effectively "sequential /simstim cycles with shared HARVEST queues" — still more than what we have today.

**Upgrade path**: when #486 graduates, flip `spiral.seed.enabled: true` globally.

### AD-4: Stopping conditions are composable

Each stopping condition is a separate predicate; the spiral halts on the first match. This makes the exit policy debuggable and lets operators disable specific conditions (e.g., "run until I say stop, ignore flatline").

**Consequence**: configuration becomes sprawling. Mitigated with sensible defaults in `.loa.config.yaml.example`.

### AD-5: HITL escape at every phase boundary

Between PHASE_END and PHASE_START, `/spiral` checks for `.run/spiral-halt` sentinel. If present, halts gracefully, archives state, surfaces a summary. No forcible termination mid-phase (except circuit breaker in embedded `/simstim`).

**Consequence**: operator can always stop without data loss.

### AD-6: Kaironic convergence at spiral level mirrors cycle level

The same flatline-detection logic used in `bridge-orchestrator.sh` for iteration-level convergence applies at the spiral level for cycle-level convergence. "Two consecutive low-signal cycles" is the meta-analog of "two consecutive low-signal iterations" in the bridge loop.

**Consequence**: consistent mental model across scales. The "kaironic" nature of Loa's design propagates through abstraction layers.

---

## Schema: `.loa.config.yaml` `spiral:` block

```yaml
# =============================================================================
# /spiral Meta-Orchestrator (cycle-066, RFC-060 #483)
# =============================================================================
# Autonomous multi-cycle development loop. Each iteration runs a full /simstim
# cycle, harvests outputs (visions, lore, bridge findings), then seeds the
# next cycle's discovery with the harvest. Terminates on cycle budget,
# flatline, cost budget, quality gate failure, or HITL halt.
spiral:
  # Master switch — default OFF. /spiral exits early with guidance when false.
  enabled: false

  # Default cycle budget for a spiral run
  default_max_cycles: 3

  # Kaironic convergence: two consecutive cycles below this many new findings
  # trigger flatline termination. Mirrors the bridge-orchestrator pattern.
  flatline:
    min_new_findings_per_cycle: 3
    consecutive_low_cycles: 2

  # Cost budget (cents). Summed across all embedded /simstim + review calls.
  budget_cents: 2000  # $20 per spiral

  # SEED phase: pull prior cycle outputs into this cycle's discovery context.
  # Gated separately because Vision Registry is in shadow_mode (#486).
  seed:
    enabled: false
    include_visions: true
    include_lore: true
    include_deferred_findings: true
    max_seed_tokens: 2000

  # HITL halt sentinel file — creating this file mid-spiral halts gracefully
  halt_sentinel: ".run/spiral-halt"
```

---

## Migration Path

| Cycle | Work | Outcome |
|-------|------|---------|
| 061 | lore-promote post-merge wiring | ✅ shipped v1.81.0 |
| 062 | Red Team jq fix | ✅ shipped v1.81.1 |
| 063 | State coalescer | ✅ shipped v1.81.2 |
| 064 | Per-cycle workspace | ✅ shipped v1.82.0 |
| **065 (this)** | **RFC-060 formal design doc** | **In progress** |
| 066 | `/spiral` skill MVP scaffolding | Pending |
| 067+ | SEED phase wiring, stopping-condition tests | Pending |

---

## Open Questions (HITL decisions needed)

1. **Q: Should `/spiral` default to `enabled: false` in shipped config?** (Recommendation: **YES**. Same pattern as `vision_registry`, `run_mode`, `red_team`. Progressive rollout.)
2. **Q: Should HITL approval be required between spiral cycles by default?** (Recommendation: **NO for MVP**. Autonomous is the point. Add `spiral.hitl_between_cycles: true` config flag for opt-in conservatism.)
3. **Q: What happens when embedded `/simstim` halts mid-spiral?** (Recommendation: `/spiral` state transitions to `HALTED`, surfaces the failure, does NOT auto-retry. Operator resolves and re-invokes.)
4. **Q: Should the spiral log to `grimoires/loa/a2a/trajectory/spiral-{date}.jsonl`?** (Recommendation: **YES**. Mirrors the trajectory convention used elsewhere. Durable cross-session record.)

---

## Security Considerations

1. **Runaway risk**: a spiral with no stopping condition is a runaway agent. Cycle budget + cost budget + flatline + HITL halt are defense-in-depth. All are mandatory; none can be disabled individually (only overridden with explicit values).

2. **Credential budget**: each cycle consumes Anthropic API credits. The cost budget (`spiral.budget_cents`) is tracked across all embedded invocations and halts the spiral before exhaustion. A spiral that exceeds budget exits with clear diagnostic, not silently.

3. **State tampering**: `.run/spiral-state.json` is read/write by the spiral's skill and the orchestrator. The mutation-logger hook (v1.37.0) already logs state mutations. No new attack surface introduced.

4. **HARVEST integrity**: lore promotion from `.run/bridge-lore-candidates.jsonl` already has its own review gate (threshold mode with floor 2). `/spiral` inherits that gate; no bypass.

5. **SEED integrity**: visions pulled into discovery context are treated as *advisory*, never authoritative. The `discovering-requirements` skill already applies factual-grounding rules to all context inputs.

---

## Testing Strategy

- Unit tests (BATS): spiral-state.sh functions, stopping-condition predicates, flatline counter
- Integration test: run a mock spiral against a sandbox repo, verify state transitions and cycle count
- Recursive validation: this RFC itself was authored as cycle-065 using the new cycle-workspace (cycle-064). The third end-to-end `/simstim`-style cycle per #483 AC.

---

## Non-goals

- Multi-repo spirals (one repo per spiral)
- Spiral composition across users (single operator per spiral)
- Automatic merging of PRs created by embedded /simstim (HITL gate at PR merge is preserved)
- Real-time observability UI (trajectory JSONL is sufficient for v1)
- Auto-re-run on embedded halt (operator resolves)

---

## Why "kaironic" is the right word

Chronos is calendar time. Kairos is the right moment. The spiral is kaironic because it exits when the moment for termination has arrived — not after a fixed number of seconds, not after a fixed number of dollar spent, but when the signal says "this is as far as this configuration can take us." The flatline detector, the review+audit gate, and the HITL halt are all kaironic sensors: they say "now" rather than "at time T."

This is the design pattern that Loa has been converging on since the Bridgebuilder kaironic loop (v1.35.0). `/spiral` generalizes it one level up.
