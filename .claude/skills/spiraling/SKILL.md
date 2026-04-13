# Spiraling — /spiral Autopoietic Meta-Orchestrator

## Status

**MVP scaffolding (v0.1.0)**. This skill provides the state machine, stopping-condition enforcement, and CLI surface for `/spiral`. **Cycle dispatch is not yet wired** — `--start` initializes state and validates config but does not yet invoke embedded `/simstim` cycles. That lands in a follow-up cycle (067+).

Use this skill today for:
- Understanding the spiral state model
- Testing stopping-condition logic
- Preparing `.loa.config.yaml` for production use

Full autonomous multi-cycle dispatch coming soon.

## Reference

- RFC-060 design doc: `grimoires/loa/proposals/rfc-060-spiral.md`
- Umbrella issue: #483
- Script: `.claude/scripts/spiral-orchestrator.sh`

## Usage

```bash
/spiral --start                                        # Start with config defaults
/spiral --start --max-cycles 5 --budget-cents 3000     # Explicit overrides
/spiral --start --dry-run                              # Validate config only
/spiral --status                                       # Human-readable status
/spiral --status --json                                # Full JSON state
/spiral --halt --reason "operator check"               # Graceful halt
/spiral --resume                                       # Resume a HALTED spiral
/spiral --check-stop                                   # Evaluate stopping conditions only
```

## State Machine

```
(no state) --[--start]--> RUNNING --[stop condition]--> COMPLETED
                             |
                             +--[--halt]--> HALTED --[--resume]--> RUNNING
                             |
                             +--[quality gate fail]--> FAILED
```

## Phase Sequence (per cycle)

```
SEED → SIMSTIM → HARVEST → EVALUATE → (next cycle OR terminate)
```

- **SEED**: pull prior cycle outputs (visions, lore) into this cycle's discovery
- **SIMSTIM**: delegate to `/simstim` for the full plan→code→PR flow
- **HARVEST**: trigger post-merge pipeline to route bridge findings/lore/bugs
- **EVALUATE**: check stopping conditions, decide continue or terminate

## Stopping Conditions

A spiral terminates when ANY of:

| Condition | Default | Floor | Rationale |
|-----------|---------|-------|-----------|
| `cycle_budget_exhausted` | 3 cycles | 50 | Primary runaway backstop |
| `flatline_convergence` | 2 consecutive cycles < 3 findings | — | Kaironic signal: plateau reached |
| `cost_budget_exhausted` | $20 | $100 | Credit exhaustion guard |
| `wall_clock_exhausted` | 8h | 24h | Second backstop for plateau-at-N |
| `hitl_halt` | sentinel file | — | Operator escape hatch |
| `quality_gate_failure` | review AND audit fail | — | Prevent error compounding |

**Safety floor note**: the floors (50 cycles / $100 / 24h) are hardcoded. Operators can relax values within those floors but cannot disable stopping conditions entirely.

## Configuration

```yaml
spiral:
  enabled: false             # Master switch (default off)
  default_max_cycles: 3
  flatline:
    min_new_findings_per_cycle: 3
    consecutive_low_cycles: 2
  budget_cents: 2000         # $20 per spiral (floor: $100)
  wall_clock_seconds: 28800  # 8h (floor: 24h)
  seed:
    enabled: false           # Vision registry must be active (#486) first
    include_visions: true
    include_lore: true
    include_deferred_findings: true
    max_seed_tokens: 2000
  halt_sentinel: ".run/spiral-halt"
```

## HITL Halt

Create the sentinel file at any time to halt gracefully at the next phase boundary:

```bash
echo "reason text" > .run/spiral-halt
```

Or use the CLI:

```bash
/spiral --halt --reason "need to review approach"
```

State persists. `--resume` picks up where the spiral stopped.

## Trajectory Logging

All spiral events log to `grimoires/loa/a2a/trajectory/spiral-{date}.jsonl`:

- `spiral_started`
- `spiral_cycle_started`
- `spiral_phase_completed`
- `spiral_stopped` (with condition)
- `spiral_halted`
- `spiral_resumed`

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Validation error |
| 2 | Feature disabled in config |
| 3 | State conflict |
| 4 | Stopping condition triggered (not an error — a natural outcome) |
| 5 | HITL halt requested |

## Relationship to Other Skills

| Skill | Role | Lifecycle |
|-------|------|-----------|
| `/simstim` | Single-cycle workflow | Invoked BY `/spiral` each cycle |
| `/run sprint-plan` | Autonomous implementation of one sprint plan | Invoked BY `/simstim` Phase 7 |
| `/bug` | Bug triage + implement | Alternative single-cycle entry point (not spiral-driven) |
| `/run-bridge` | Iterative sprint-level improvement | Orthogonal — runs inside `/simstim` or standalone |

`/spiral` is the meta-layer that composes these. It does NOT reimplement any of them.

## Known Limitations (v0.1.0)

- Embedded `/simstim` dispatch is stubbed — `--start` initializes state only
- SEED phase context-loading not yet wired (blocked on vision registry graduation #486)
- No auto-retry on embedded cycle failure (operator resolves, then `--resume`)
- Single-operator, single-repo only
