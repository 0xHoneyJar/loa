---
parallel_threshold: 2000
timeout_minutes: 480
zones:
  system:
    path: .claude
    permission: read
  state:
    paths: [grimoires/loa, .beads, .run]
    permission: read-write
  app:
    paths: [src, lib, app]
    permission: read-write
---

# Run Bridge — Autonomous Excellence Loop

## Overview

The Run Bridge skill orchestrates an iterative improvement loop:

1. Execute sprint plan via `/run sprint-plan`
2. Invoke Bridgebuilder review on the resulting changes
3. Parse findings into structured JSON
4. Generate a new sprint plan from findings
5. Repeat until findings "flatline" (kaironic termination)

Each iteration leaves a GitHub trail (PR comments, vision links) and captures
speculative insights in the Vision Registry. On completion, Grounded Truth is
regenerated and RTFM validation runs as a final gate.

## Workflow

### Phase 0: Input Guardrails

Check danger level (high) — requires explicit opt-in:
- `run_bridge.enabled: true` in `.loa.config.yaml`
- Not on a protected branch

### Phase 1: Argument Parsing

| Argument | Flag | Default |
|----------|------|---------|
| depth | `--depth N` | 3 (max 5) |
| per_sprint | `--per-sprint` | false |
| resume | `--resume` | false |
| from | `--from PHASE` | — |

### Phase 2: Orchestrator Invocation

Invoke `bridge-orchestrator.sh` with translated flags:

```bash
.claude/scripts/bridge-orchestrator.sh \
  --depth "$depth" \
  ${per_sprint:+--per-sprint} \
  ${resume:+--resume} \
  ${from:+--from "$from"}
```

The orchestrator manages the state machine:

```
PREFLIGHT → JACK_IN → ITERATING ↔ ITERATING → FINALIZING → JACKED_OUT
                         ↓                        ↓
                       HALTED                    HALTED
```

### Phase 3: Iteration Loop

For each iteration, the orchestrator emits SIGNAL lines that this skill
interprets and acts on:

| Signal | Action |
|--------|--------|
| `GENERATE_SPRINT_FROM_FINDINGS` | Create sprint plan from parsed findings |
| `RUN_SPRINT_PLAN` | Execute `/run sprint-plan` |
| `RUN_PER_SPRINT` | Execute per-sprint mode |
| `BRIDGEBUILDER_REVIEW` | Invoke Bridgebuilder on changes |
| `VISION_CAPTURE` | Run `bridge-vision-capture.sh` |
| `GITHUB_TRAIL` | Run `bridge-github-trail.sh` |
| `FLATLINE_CHECK` | Evaluate flatline condition |

### Phase 4: Finalization

After loop termination (flatline or max depth):

1. **Ground Truth Update**: Run `ground-truth-gen.sh --mode checksums`
2. **RTFM Gate**: Test GT index.md, README.md, new protocol docs
   - All PASS → continue
   - FAILURE → generate 1 fix sprint, re-test (max 1 retry)
   - Second FAILURE → log warning, continue
3. **Final PR Update**: Update PR body with complete bridge summary

### Phase 5: Progress Reporting

Report final metrics from `.run/bridge-state.json`:
- Total iterations completed
- Total sprints executed
- Total files changed
- Total findings addressed
- Total visions captured
- Flatline status

## Configuration

```yaml
run_bridge:
  enabled: true
  defaults:
    depth: 3
    per_sprint: false
    flatline_threshold: 0.05
    consecutive_flatline: 2
  timeouts:
    per_iteration_hours: 4
    total_hours: 24
  github_trail:
    post_comments: true
    update_pr_body: true
  ground_truth:
    enabled: true
  vision_registry:
    enabled: true
    auto_capture: true
  rtfm:
    enabled: true
    max_fix_iterations: 1
  lore:
    enabled: true
    categories:
      - mibera
      - neuromancer
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "run_bridge.enabled is not true" | Config not set | Set `run_bridge.enabled: true` |
| "Cannot run bridge on protected branch" | On main/master | Switch to feature branch |
| "Sprint plan not found" | Missing sprint.md | Run `/sprint-plan` first |
| "Per-iteration timeout exceeded" | Single iteration too slow | Reduce sprint scope |
| "Total timeout exceeded" | Overall time limit hit | Resume with `/run-bridge --resume` |

## Constraints

- C-BRIDGE-001: ALWAYS use `/run sprint-plan` within bridge iterations
- C-BRIDGE-002: ALWAYS post Bridgebuilder review as PR comment
- C-BRIDGE-003: ALWAYS ensure GT claims cite file:line references
- C-BRIDGE-004: ALWAYS use YAML format for lore entries
- C-BRIDGE-005: ALWAYS include source bridge iteration and PR in vision entries
