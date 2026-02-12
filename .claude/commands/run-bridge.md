---
name: run-bridge
description: Autonomous excellence loop with iterative Bridgebuilder review
output: Bridge state, grounded truth, vision entries, PR trail
command_type: skill
skill: run-bridge
---

# /run-bridge — Autonomous Excellence Loop

## Purpose

Run an iterative improvement loop: execute sprint plan, invoke Bridgebuilder review,
parse findings, generate new sprint plan from findings, repeat until insights flatline.
Every iteration leaves a GitHub trail and captures speculative insights.

## Invocation

```
/run-bridge                    # Default: 3 iterations
/run-bridge --depth 5          # Up to 5 iterations
/run-bridge --per-sprint       # Per-sprint review granularity
/run-bridge --resume           # Resume interrupted bridge
/run-bridge --from sprint-plan # Start from existing sprint plan
```

## Arguments

| Argument | Description | Default |
|----------|-------------|---------|
| `--depth N` | Maximum iterations (1-5) | 3 |
| `--per-sprint` | Review after each sprint vs full plan | false |
| `--resume` | Resume from interrupted bridge | false |
| `--from PHASE` | Start from phase (sprint-plan) | — |

## Outputs

| Path | Description |
|------|-------------|
| `.run/bridge-state.json` | Bridge iteration state |
| `grimoires/loa/ground-truth/` | Grounded Truth output |
| `grimoires/loa/visions/` | Vision registry entries |
| PR comments | Per-iteration Bridgebuilder reviews |

## Prerequisites

- `run_bridge.enabled: true` in `.loa.config.yaml`
- Sprint plan exists (`grimoires/loa/sprint.md`)
- Not on a protected branch (main, master, etc.)

## Loop Termination

The bridge loop terminates when:
1. **Flatline detected**: Severity score drops below threshold for N consecutive iterations
2. **Max depth reached**: Configured depth limit hit
3. **Timeout**: Per-iteration or total timeout exceeded
4. **HALTED**: Circuit breaker triggered by error

## Related

- `/run sprint-plan` — Execute all sprints (used within bridge iterations)
- `/run-bridge --resume` — Resume interrupted bridge
- `/run-status` — Check current run mode progress
- `/loa` — View bridge state and next steps
