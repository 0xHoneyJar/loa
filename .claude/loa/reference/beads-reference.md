# Beads-First Architecture Reference

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## Philosophy (v1.29.0)

**Beads task tracking is the EXPECTED DEFAULT, not an optional enhancement.**

*"We're building spaceships. Safety of operators and users is paramount."*

Working without beads is treated as an **abnormal state** requiring explicit, time-limited acknowledgment. Health checks run at every workflow boundary.

## Health Check

```bash
# Check beads status
.claude/scripts/beads/beads-health.sh --json
```

| Status | Exit Code | Meaning | Action |
|--------|-----------|---------|--------|
| `HEALTHY` | 0 | All checks pass | Proceed |
| `NOT_INSTALLED` | 1 | br binary not found | Prompt install |
| `NOT_INITIALIZED` | 2 | No .beads directory | Prompt br init |
| `MIGRATION_NEEDED` | 3 | Schema incompatible | Must fix |
| `DEGRADED` | 4 | Partial functionality | Warn, proceed |
| `UNHEALTHY` | 5 | Critical issues | Must fix |

## Autonomous Mode

**Autonomous mode REQUIRES beads** (unless overridden):

```bash
# /run preflight will HALT if beads unavailable
/run sprint-1  # Blocked if beads.autonomous.requires_beads: true

# Override (not recommended)
export LOA_BEADS_AUTONOMOUS_OVERRIDE=true
# Or set beads.autonomous.requires_beads: false in config
```

## Opt-Out Workflow

When beads unavailable, users can acknowledge and continue (24h expiry):

```bash
# Record opt-out with reason
.claude/scripts/beads/update-beads-state.sh --opt-out "Reason"

# Check if opt-out is valid
.claude/scripts/beads/update-beads-state.sh --opt-out-check
```

## Configuration

```yaml
beads:
  mode: recommended  # required | recommended | disabled
  opt_out:
    confirmation_interval_hours: 24
    require_reason: true
  autonomous:
    requires_beads: true
```

**Protocol**: `.claude/protocols/beads-preflight.md`

## Flatline Beads Loop (v1.28.0)

Iterative multi-model refinement of task graphs. "Check your beads N times, implement once."

### How It Works

1. Export beads to JSON (`br list --json`)
2. Run Flatline Protocol review on task graph
3. Apply HIGH_CONSENSUS suggestions automatically
4. Repeat until changes "flatline" (< 5% change for 2 iterations)
5. Sync final state to git

### Usage

```bash
# Manual invocation
.claude/scripts/beads-flatline-loop.sh --max-iterations 6 --threshold 5

# In simstim workflow (Phase 6.5)
# Automatically runs after FLATLINE SPRINT phase when beads_rust is installed
```

### Configuration

```yaml
simstim:
  flatline:
    beads_loop: true    # Enable Flatline Beads Loop
```

Requires beads_rust (`br`). See: https://github.com/Dicklesworthstone/beads_rust
