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

## Getting Started

You can provide as much context as you want when invoking simstim:

```bash
# Simple invocation
/simstim

# With context — works great!
/simstim I want to build a user authentication system with OAuth2,
         JWT tokens, and role-based access control

# For large context, use the context directory
# Put files in grimoires/loa/context/ first, then:
/simstim
```

### How It Works

Simstim guides you through 8 phases:

1. **Phases 1-6** are interactive — you answer questions and make decisions
2. **Phase 7** runs autonomously via `/run sprint-plan`
3. Each phase completes fully before the next begins

**Note**: Simstim has its own workflow structure and does NOT use Claude Code's Plan Mode.

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
| 0 | PREFLIGHT | Validate config, check state, **beads health** |
| 1 | DISCOVERY | Create PRD interactively |
| 2 | FLATLINE PRD | Multi-model review of PRD |
| 3 | ARCHITECTURE | Create SDD interactively |
| 4 | FLATLINE SDD | Multi-model review of SDD |
| 5 | PLANNING | Create sprint plan interactively |
| 6 | FLATLINE SPRINT | Multi-model review of sprint plan |
| 6.5 | FLATLINE BEADS | Iterative task graph refinement (v1.28.0) |
| 7 | IMPLEMENTATION | Autonomous execution via /run sprint-plan |
| 8 | COMPLETE | Summary and cleanup |

## Flatline Beads Loop (v1.28.0)

Phase 6.5 runs the "Check your beads N times, implement once" pattern when beads_rust is installed:

```bash
# Automatically triggered after FLATLINE SPRINT if:
# 1. beads_rust (br) is installed
# 2. Beads have been created from sprint tasks
# 3. flatline.beads_loop is enabled in config (default: true)
```

### What Happens

1. **Export**: Current beads are exported to JSON
2. **Review**: Flatline Protocol reviews task graph for:
   - Granularity problems (tasks too large/vague)
   - Dependency issues (missing, cycles, ordering)
   - Completeness gaps (missing tasks)
   - Clarity problems (ambiguous acceptance criteria)
3. **Apply**: HIGH_CONSENSUS suggestions auto-integrate
4. **Iterate**: Repeat until changes < 5% for 2 consecutive iterations
5. **Sync**: Final state synced to git

### Progress Display

```
FLATLINE BEADS LOOP
════════════════════════════════════════════════════════════

Iteration 1/6...
  HIGH_CONSENSUS: 3, DISPUTED: 1, BLOCKERS: 0
  Change: 15%

Iteration 2/6...
  HIGH_CONSENSUS: 1, DISPUTED: 0, BLOCKERS: 0
  Change: 8%

Iteration 3/6...
  HIGH_CONSENSUS: 0, DISPUTED: 0, BLOCKERS: 0
  Change: 2%

FLATLINE DETECTED
════════════════════════════════════════════════════════════
Task graph stabilized after 3 iterations.
```

### Skip Conditions

The phase is skipped when:
- beads_rust not installed (silent skip)
- No beads created from sprint tasks
- `simstim.flatline.beads_loop: false` in config
- User chooses to skip when prompted

## Flatline Integration (HITL Mode)

During Flatline review phases (2, 4, 6, 6.5), findings are categorized:

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

## Beads-First Preflight (v1.29.0)

Phase 0 includes comprehensive beads health checking. Beads task tracking is the EXPECTED DEFAULT.

### Preflight Check

```bash
health=$(.claude/scripts/beads/beads-health.sh --quick --json)
status=$(echo "$health" | jq -r '.status')
```

### Status Handling

| Status | Action |
|--------|--------|
| `HEALTHY` | Proceed silently |
| `DEGRADED` | Warn about Phase 6.5 impact, proceed |
| `NOT_INSTALLED`/`NOT_INITIALIZED` | Warn that Phase 6.5 will be skipped |
| `MIGRATION_NEEDED`/`UNHEALTHY` | Warn, recommend fix, proceed |

### Phase 6.5 Impact

If beads unavailable, Phase 6.5 (FLATLINE BEADS) will be skipped:

```
Beads Health: NOT_INSTALLED
Phase 6.5 (Flatline Beads Loop) will be skipped.

To enable full workflow:
  cargo install beads_rust && br init

Continuing without beads...
```

### Protocol Reference

See `.claude/protocols/beads-preflight.md` for full specification.

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
    beads_loop: true    # Enable Flatline Beads Loop (v1.28.0)
    phases:
      - prd
      - sdd
      - sprint
      - beads

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
