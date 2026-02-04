# Beads Preflight Protocol

> **Version**: 1.29.0
> **Status**: Beads-First Architecture
> **Philosophy**: "We're building spaceships. Safety of operators and users is paramount."

---

## Overview

The Beads Preflight Protocol ensures task tracking infrastructure is available at workflow boundaries. Beads are the **expected default**, not an optional enhancement. Working without beads is treated as an **abnormal state** requiring explicit, time-limited acknowledgment.

---

## Design Principles

1. **Beads are Expected**: Health checks run at every workflow boundary
2. **Explicit Opt-Out**: Users must acknowledge working without beads
3. **Time-Limited Acknowledgment**: Opt-out expires (default: 24h)
4. **Autonomous Safety**: Autonomous mode REQUIRES beads (unless overridden)
5. **Graceful Degradation**: Multiple recovery paths
6. **Full Auditability**: All decisions logged to trajectory

---

## Health Check Status Codes

| Code | Status | Meaning | Action |
|------|--------|---------|--------|
| 0 | HEALTHY | All checks pass | Proceed |
| 1 | NOT_INSTALLED | br binary not found | Prompt for install |
| 2 | NOT_INITIALIZED | No .beads directory | Prompt for br init |
| 3 | MIGRATION_NEEDED | Schema incompatible | Prompt for migration |
| 4 | DEGRADED | Partial functionality | Warn, offer recovery |
| 5 | UNHEALTHY | Critical issues | Block until resolved |

---

## Workflow Integration Points

### A. /sprint-plan (Phase 0)

```bash
# Run health check
health=$(.claude/scripts/beads/beads-health.sh --json)
status=$(echo "$health" | jq -r '.status')

case "$status" in
  HEALTHY)
    # Proceed with sprint planning
    ;;
  DEGRADED)
    # Warn user, offer quick fix, proceed
    echo "Beads health: DEGRADED"
    echo "Recommendations: $(echo "$health" | jq -r '.recommendations[]')"
    ;;
  NOT_INSTALLED|NOT_INITIALIZED)
    # Check for valid opt-out
    opt_out=$(.claude/scripts/beads/update-beads-state.sh --opt-out-check 2>/dev/null || echo "NO_OPT_OUT")
    if [[ "$opt_out" != "OPT_OUT_VALID"* ]]; then
      # Prompt user for decision
      # See "Opt-Out Workflow" below
    fi
    ;;
  UNHEALTHY|MIGRATION_NEEDED)
    # Must address before proceeding
    echo "Beads health: $status - must resolve before continuing"
    ;;
esac
```

### B. /implement (Phase -2: Beads Sync)

```bash
# Import latest state from git
if command -v br &>/dev/null && [[ -d .beads ]]; then
  br sync --import-only
  .claude/scripts/beads/update-beads-state.sh --sync-import
fi
```

### C. /run (Autonomous Preflight)

```bash
# Autonomous mode requires beads (unless overridden)
if [[ "$mode" == "autonomous" ]]; then
  health=$(.claude/scripts/beads/beads-health.sh --json)
  status=$(echo "$health" | jq -r '.status')

  if [[ "$status" != "HEALTHY" && "$status" != "DEGRADED" ]]; then
    if [[ "${LOA_BEADS_AUTONOMOUS_OVERRIDE:-}" != "true" ]]; then
      echo "HALT: Autonomous mode requires beads (status: $status)"
      echo "Override with: export LOA_BEADS_AUTONOMOUS_OVERRIDE=true"
      exit 1
    fi
  fi
fi
```

### D. /simstim (Phase 0 Extension)

```bash
# Check beads availability
health=$(.claude/scripts/beads/beads-health.sh --quick --json)
status=$(echo "$health" | jq -r '.status')

if [[ "$status" == "NOT_INSTALLED" || "$status" == "NOT_INITIALIZED" ]]; then
  echo "Note: Beads not available. Phase 6.5 (Flatline Beads Loop) will be skipped."
fi
```

---

## Opt-Out Workflow

### Trigger Conditions

Opt-out prompt appears when:
1. Beads unavailable (NOT_INSTALLED or NOT_INITIALIZED)
2. No valid opt-out exists (none, or expired)

### Interactive Mode

```yaml
questions:
  - question: "Beads is not available. How would you like to proceed?"
    header: "Beads"
    options:
      - label: "Install beads (Recommended)"
        description: "Install beads_rust for task tracking"
      - label: "Continue without beads"
        description: "Acknowledge and proceed (expires in 24h)"
      - label: "Abort"
        description: "Cancel current operation"
```

### If "Continue without beads" Selected

1. Prompt for reason (if `beads.opt_out.require_reason: true`)
2. Record opt-out with expiry
3. Log to trajectory
4. Proceed with workflow

```bash
.claude/scripts/beads/update-beads-state.sh --opt-out "Reason: ..."
```

### Opt-Out Expiry

- Default: 24 hours
- Configurable via `beads.opt_out.confirmation_interval_hours`
- When expired: Re-prompt on next workflow invocation
- Max consecutive: 3 (configurable, generates warning)

### Autonomous Mode

In autonomous mode, beads unavailable causes HALT:

```bash
# Unless explicitly overridden in config:
# beads.autonomous.requires_beads: false
```

---

## Configuration

### .loa.config.yaml

```yaml
beads:
  # Mode: required | recommended | disabled
  mode: recommended

  # Health check frequency: session | sprint | phase
  health_check_frequency: sprint

  # Opt-out configuration
  opt_out:
    confirmation_interval_hours: 24
    require_reason: true
    max_consecutive: 3

  # Autonomous mode configuration
  autonomous:
    requires_beads: true
    allow_degraded: true
    max_recovery_attempts: 3

  # Size/staleness thresholds
  thresholds:
    jsonl_warn_size_mb: 50
    db_warn_size_mb: 100
    sync_stale_hours: 24
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `LOA_BEADS_OPT_OUT_HOURS` | Override opt-out expiry hours |
| `LOA_BEADS_MAX_OPT_OUTS` | Override max consecutive opt-outs |
| `LOA_BEADS_AUTONOMOUS_OVERRIDE` | Allow autonomous without beads |
| `LOA_BEADS_JSONL_WARN_MB` | JSONL size warning threshold |
| `LOA_BEADS_DB_WARN_MB` | Database size warning threshold |
| `LOA_BEADS_SYNC_STALE_HOURS` | Sync staleness threshold |

---

## State File Schema

### .run/beads-state.json

```json
{
  "schema_version": 1,
  "health": {
    "status": "HEALTHY|DEGRADED|...",
    "last_check": "ISO-8601",
    "last_healthy": "ISO-8601",
    "consecutive_failures": 0,
    "details": {}
  },
  "opt_out": {
    "active": false,
    "reason": null,
    "acknowledged_at": null,
    "expires_at": null,
    "consecutive_opt_outs": 0,
    "history": []
  },
  "recovery": {
    "last_attempt": null,
    "attempts_since_healthy": 0,
    "history": []
  },
  "sync": {
    "last_import": null,
    "last_flush": null
  }
}
```

---

## Trajectory Logging

All beads preflight events are logged to:
`grimoires/loa/a2a/trajectory/beads-preflight-{date}.jsonl`

### Event Schema

```json
{
  "timestamp": "ISO-8601",
  "type": "beads_preflight",
  "workflow": "sprint-plan|implement|run|simstim",
  "health_status": "HEALTHY|DEGRADED|...",
  "action": "PROCEED|HALT|OPT_OUT|RECOVERED",
  "opt_out_reason": null,
  "mode": "interactive|autonomous"
}
```

---

## Recovery Paths

### NOT_INSTALLED Recovery

```bash
# Option 1: Install via script
.claude/scripts/beads/install-br.sh

# Option 2: Install via cargo
cargo install beads_rust

# Option 3: Opt-out (time-limited)
.claude/scripts/beads/update-beads-state.sh --opt-out "Reason"
```

### NOT_INITIALIZED Recovery

```bash
br init
```

### MIGRATION_NEEDED Recovery

```bash
# Check current schema
sqlite3 .beads/beads.db "PRAGMA table_info(issues);"

# Manual migration if needed
# (br typically handles this automatically on upgrade)
br doctor
```

### DEGRADED Recovery

```bash
# Run doctor for diagnosis
br doctor

# Sync if stale
br sync

# Archive if large
# (Manual process - export old issues, archive)
```

### UNHEALTHY Recovery

```bash
# Check for corruption
br doctor

# If corrupted, restore from backup
cp .beads/beads.db.bak .beads/beads.db

# Or reinitialize (loses local state not in JSONL)
rm -rf .beads
br init
br sync --import-only
```

---

## Quick Reference

```bash
# Health check
.claude/scripts/beads/beads-health.sh --json

# Record opt-out
.claude/scripts/beads/update-beads-state.sh --opt-out "Reason"

# Check opt-out validity
.claude/scripts/beads/update-beads-state.sh --opt-out-check

# Show state
.claude/scripts/beads/update-beads-state.sh --show

# Update health
.claude/scripts/beads/update-beads-state.sh --health HEALTHY
```

---

## Related

- `.claude/protocols/beads-integration.md` - beads_rust command reference
- `.claude/scripts/beads/beads-health.sh` - Health check implementation
- `.claude/scripts/beads/update-beads-state.sh` - State management
- `.claude/scripts/beads-flatline-loop.sh` - Flatline beads iteration
