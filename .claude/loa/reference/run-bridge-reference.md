# Run Bridge Reference — Autonomous Excellence Loop

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## How It Works (v1.35.0)

```
PREFLIGHT → JACK_IN → ITERATING ↔ ITERATING → FINALIZING → JACKED_OUT
                ↓           ↓                      ↓
              HALTED ← ← HALTED ← ← ← ← ← ← HALTED
                ↓
          ITERATING (resume) or JACKED_OUT (abandon)
```

Each iteration: Run sprint-plan → Bridgebuilder review → Parse findings → Flatline check → GitHub trail → Vision capture. Loop terminates when severity-weighted score drops below threshold for consecutive iterations (kaironic termination).

## Usage

```bash
/run-bridge                    # Default: 3 iterations
/run-bridge --depth 5          # Up to 5 iterations
/run-bridge --per-sprint       # Per-sprint review granularity
/run-bridge --resume           # Resume interrupted bridge
/run-bridge --from sprint-plan # Start from existing sprint plan
```

## Bridge State Recovery

Check `.run/bridge-state.json`:

| State | Meaning | Action |
|-------|---------|--------|
| `ITERATING` | Active bridge loop | Continue autonomously |
| `HALTED` | Stopped due to error | Await `/run-bridge --resume` |
| `FINALIZING` | Post-loop GT + RTFM | Continue autonomously |
| `JACKED_OUT` | Completed | No action |

## Key Components

| Component | Script |
|-----------|--------|
| Orchestrator | `bridge-orchestrator.sh` |
| State Machine | `bridge-state.sh` |
| Findings Parser | `bridge-findings-parser.sh` |
| Vision Capture | `bridge-vision-capture.sh` |
| GitHub Trail | `bridge-github-trail.sh` |
| Ground Truth | `ground-truth-gen.sh` |

## Lore Knowledge Base

Cultural and philosophical context in `.claude/data/lore/`:

| Category | Entries | Description |
|----------|---------|-------------|
| Mibera | Core, Cosmology, Rituals, Glossary | Mibera network mysticism framework |
| Neuromancer | Concepts, Mappings | Gibson's Sprawl trilogy mappings |

Skills query lore at invocation time via `index.yaml`. Use `short` fields inline, `context` for teaching moments.

## Configuration

```yaml
run_bridge:
  enabled: true
  defaults:
    depth: 3
    flatline_threshold: 0.05
    consecutive_flatline: 2
```
