# Beads Preflight Protocol

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

Each boundary calls the health-check script for that phase, reads `.status` from its JSON, and acts per the table above. Deltas from the default mapping:

| Workflow | Invocation | Delta |
|---|---|---|
| `/sprint-plan` (Phase 0) | `.claude/scripts/beads/beads-health.sh --json` | On `NOT_INSTALLED`/`NOT_INITIALIZED`, check `update-beads-state.sh --opt-out-check` first; prompt only if no valid opt-out |
| `/implement` (Phase -2: Beads Sync) | `br sync --import-only` + `.claude/scripts/beads/update-beads-state.sh --sync-import` | Runs only when `br` is on PATH and `.beads` exists; no status branch |
| `/run` (Autonomous Preflight) | `.claude/scripts/beads/beads-health.sh --json` | Any status other than `HEALTHY`/`DEGRADED` halts with exit 1 unless `LOA_BEADS_AUTONOMOUS_OVERRIDE=true` |
| `/simstim` (Phase 0 ext.) | `.claude/scripts/beads/beads-health.sh --quick --json` | On `NOT_INSTALLED`/`NOT_INITIALIZED`, Phase 6.5 (Flatline Beads Loop) is skipped, not blocked |

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

---

## Configuration

### .loa.config.yaml

```yaml
beads:
  mode: recommended
  health_check_frequency: sprint
  opt_out:
    confirmation_interval_hours: 24
    require_reason: true
    max_consecutive: 3
  autonomous:
    requires_beads: true
    allow_degraded: true
    max_recovery_attempts: 3
  thresholds:
    jsonl_warn_size_mb: 50
    db_warn_size_mb: 100
    sync_stale_hours: 24
```

Key meanings and other valid values: `.loa.config.yaml.example` (`beads:` section).

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

**First action**: invoke the Loa-side migration repair tool. It heals the
upstream beads_rust 0.2.1-0.2.6 `NOT NULL constraint failed:
dirty_issues.marked_at` shape in-place using the SQLite recreate-and-swap
pattern, with backup-before-mutation and post-flight verify.

```bash
# Heal the dirty_issues schema (idempotent + reversible)
tools/beads-migration-repair.sh

# Or via the wrapped health-check surface
.claude/scripts/beads/beads-health.sh --repair

# Preview the SQL without mutating
tools/beads-migration-repair.sh --dry-run
```

The repair tool exit codes:
- `0` repair succeeded (or no-op when already HEALTHY)
- `1` repair failed; database auto-restored from backup
- `2` argument / I/O error
- `3` unrecoverable schema (operator action required)

If the repair tool returns `3`, the database is in a shape the
automated heal can't handle (e.g., `dirty_issues` table missing, extra
columns). Fall back to manual inspection:

```bash
# Inspect current schema
sqlite3 .beads/beads.db "PRAGMA table_info(dirty_issues);"

# Snapshot before any manual mutation
cp .beads/beads.db .beads/_manual-backup-$(date +%s).db

# Last-resort: fresh init + re-import from JSONL
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

## Provenance

Removed from rule text: cycle-105 sprint-1 (MIGRATION_NEEDED repair-tool authorship); Loa #661 (downstream) and Dicklesworthstone/beads_rust#290 (upstream, filed 2026-05-11), dirty_issues repair tracking.
