# /simstim - HITL Accelerated Development Workflow

## Purpose

Orchestrate the complete Loa development cycle with integrated Flatline Protocol reviews at each stage. Human drives planning phases interactively while HIGH_CONSENSUS findings auto-integrate.

*"Experience the AI's work while maintaining your own consciousness."* — Gibson, Neuromancer

### Key Difference from /autonomous

| Aspect | /autonomous | /simstim |
|--------|-------------|----------|
| Designed for | AI operators (Clawdbot) | Human operators (YOU) |
| Planning phases | Minimal interaction, AI-driven | YOU drive interactively |
| Flatline results | BLOCKER halts workflow | BLOCKER shown to you, you decide |
| Implementation | Integrated into workflow | Hands off to /run sprint-plan |

## Usage

```bash
# Full cycle from scratch
/simstim

# Skip to specific phase (requires existing artifacts)
/simstim --from architect       # Skip PRD (requires existing PRD)
/simstim --from sprint-plan     # Skip PRD + SDD
/simstim --from run             # Skip all planning, just run sprints

# Resume interrupted workflow
/simstim --resume

# Preview planned phases
/simstim --dry-run

# Abort and clean up
/simstim --abort
```

## Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--from <phase>` | Start from specific phase | - |
| `--resume` | Continue from interruption | false |
| `--abort` | Clean up state and exit | false |
| `--dry-run` | Show plan without executing | false |

### Flag Mutual Exclusivity

- `--from` and `--resume` **cannot be used together**
  - `--from` starts fresh from a phase (ignores existing state)
  - `--resume` continues from last checkpoint (requires existing state)
- `--abort` takes precedence over all other flags
- `--dry-run` can be combined with any flag

## Phases

| Phase | Name | Description |
|-------|------|-------------|
| 0 | PREFLIGHT | Validate configuration, check state |
| 1 | DISCOVERY | Create PRD interactively |
| 2 | FLATLINE PRD | Multi-model review of PRD |
| 3 | ARCHITECTURE | Create SDD interactively |
| 4 | FLATLINE SDD | Multi-model review of SDD |
| 5 | PLANNING | Create sprint plan interactively |
| 6 | FLATLINE SPRINT | Multi-model review of sprint plan |
| 7 | IMPLEMENTATION | Autonomous execution via /run sprint-plan |
| 8 | COMPLETE | Summary and cleanup |

## Flatline Integration (HITL Mode)

During Flatline review phases (2, 4, 6), findings are categorized:

| Category | Criteria | Action |
|----------|----------|--------|
| HIGH_CONSENSUS | Both models >700 | Auto-integrate (no prompt) |
| DISPUTED | Score delta >300 | Present to you for decision |
| BLOCKER | Skeptic concern >700 | Present to you for decision (NOT auto-halt) |
| LOW_VALUE | Both <400 | Skip silently |

### DISPUTED Handling

```
DISPUTED: [suggestion]
GPT scored 650, Opus scored 350.

[A]ccept / [R]eject / [S]kip?
```

### BLOCKER Handling

```
BLOCKER: [concern]
Severity: 750

[O]verride (requires rationale) / [R]eject / [D]efer?
```

If you choose Override, you must provide a rationale that is logged to the trajectory.

## State Management

Simstim tracks progress in `.run/simstim-state.json`:

```json
{
  "simstim_id": "simstim-20260203-abc123",
  "state": "RUNNING",
  "phase": "flatline_sdd",
  "phases": {
    "preflight": "completed",
    "discovery": "completed",
    "flatline_prd": "completed",
    "architecture": "completed",
    "flatline_sdd": "in_progress",
    ...
  },
  "artifacts": {
    "prd": {"path": "grimoires/loa/prd.md", "checksum": "sha256:..."},
    "sdd": {"path": "grimoires/loa/sdd.md", "checksum": "sha256:..."}
  }
}
```

### Resuming After Interruption

If your session is interrupted (timeout, Ctrl+C, etc.):

1. State is automatically saved to `.run/simstim-state.json`
2. Run `/simstim --resume` to continue
3. Artifact checksums are validated (detects manual edits)
4. Workflow resumes from last incomplete phase

**Example Resume Session:**
```bash
# Session interrupted during SDD creation
# Later, in new session:
/simstim --resume

# Output:
# ════════════════════════════════════════════════════════════
#      Resuming Simstim Workflow
# ════════════════════════════════════════════════════════════
#
# Simstim ID: simstim-20260203-abc123
# Started: 2026-02-03T10:00:00Z
# Last Activity: 2026-02-03T11:30:00Z
#
# Completed Phases:
#   ✓ PREFLIGHT
#   ✓ DISCOVERY (PRD created)
#   ✓ FLATLINE PRD (3 integrated, 1 disputed)
#
# Resuming from: ARCHITECTURE
# ════════════════════════════════════════════════════════════
```

### State File Location

State is stored in `.run/simstim-state.json`:

```json
{
  "simstim_id": "simstim-20260203-abc123",
  "schema_version": 1,
  "state": "RUNNING",
  "phase": "architecture",
  "timestamps": {
    "started": "2026-02-03T10:00:00Z",
    "last_activity": "2026-02-03T11:30:00Z"
  },
  "phases": {
    "preflight": "completed",
    "discovery": "completed",
    "flatline_prd": "completed",
    "architecture": "in_progress",
    ...
  },
  "artifacts": {
    "prd": {
      "path": "grimoires/loa/prd.md",
      "checksum": "sha256:abc123..."
    }
  }
}
```

### Artifact Drift Detection

If you manually edit an artifact after completing a phase:

```
⚠️ Artifact drift detected:

prd.md (grimoires/loa/prd.md)
  Expected: sha256:abc123...
  Actual:   sha256:def456...

This file was modified since the last session.

[R]e-review with Flatline
[C]ontinue without re-review
[A]bort
```

**Recommendations:**
- Choose **Re-review** if you made substantive changes that need quality validation
- Choose **Continue** for minor formatting or typo fixes
- Choose **Abort** if you need to start fresh

## Error Recovery

### Phase Failure

If a phase fails unexpectedly:

```
Phase ARCHITECTURE encountered an error: [message]

[R]etry - Attempt phase again
[S]kip - Mark as skipped, continue
[A]bort - Save state and exit
```

**Skip restrictions:**
- Cannot skip DISCOVERY (PRD required for SDD)
- Cannot skip ARCHITECTURE (SDD required for Sprint)

### Flatline Timeout

If Flatline API times out:
- Review phase is marked "skipped"
- Workflow continues to next planning phase
- Warning logged to trajectory

## Configuration

Enable in `.loa.config.yaml`:

```yaml
simstim:
  enabled: true

  # Flatline behavior in HITL mode
  flatline:
    auto_accept_high_consensus: true
    show_disputed: true
    show_blockers: true
    phases:
      - prd
      - sdd
      - sprint

  # Default options
  defaults:
    timeout_hours: 24

  # Phase skipping behavior
  skip_phases:
    prd_if_exists: false
    sdd_if_exists: false
    sprint_if_exists: false
```

## Outputs

| Artifact | Path | Description |
|----------|------|-------------|
| PRD | `grimoires/loa/prd.md` | Product Requirements Document |
| SDD | `grimoires/loa/sdd.md` | Software Design Document |
| Sprint | `grimoires/loa/sprint.md` | Sprint Plan |
| State | `.run/simstim-state.json` | Workflow state (ephemeral) |
| PR | GitHub | Draft PR from /run sprint-plan |

## Troubleshooting

### "simstim.enabled is false"

Enable in config:
```yaml
simstim:
  enabled: true
```

### "State conflict detected"

Previous workflow exists. Choose:
- `/simstim --resume` to continue
- `/simstim --abort` then `/simstim` to start fresh

### "Missing prerequisite"

Using `--from` but required artifact doesn't exist:
- `--from architect` requires `grimoires/loa/prd.md`
- `--from sprint-plan` requires both PRD and SDD
- `--from run` requires PRD, SDD, and sprint.md

### "Flatline unavailable"

Flatline API issues. Options:
- Wait and retry
- Continue without Flatline review (quality risk)
- Check API keys and network

### Resume Issues

**"No state file found"**

Cannot resume - no previous workflow exists:
```bash
# Start a new workflow instead
/simstim
```

**"Schema version mismatch"**

State file from older Loa version. Automatic migration attempted:
```bash
# If migration fails, start fresh
/simstim --abort
/simstim
```

**"State conflict detected"**

A previous workflow exists. Options:
```bash
# Continue the existing workflow
/simstim --resume

# Or abandon and start fresh
/simstim --abort
/simstim
```

**"Implementation incomplete"**

Previous `/run sprint-plan` hit a circuit breaker. On resume:
```bash
# Will invoke /run-resume instead of fresh /run sprint-plan
/simstim --resume
```

## Related Commands

- `/plan-and-analyze` - Standalone PRD creation
- `/architect` - Standalone SDD creation
- `/sprint-plan` - Standalone sprint planning
- `/run sprint-plan` - Autonomous implementation
- `/flatline-review` - Manual Flatline invocation
