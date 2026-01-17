---
name: "ledger"
version: "1.0.0"
description: |
  View and manage Sprint Ledger status.
  Provides global sprint numbering and cycle management.

arguments:
  - name: "subcommand"
    type: "string"
    required: false
    description: "Subcommand: init, history, or empty for status"
    examples: ["init", "history"]

context_files:
  - path: "grimoires/loa/ledger.json"
    required: false
    purpose: "Sprint Ledger data"

pre_flight: []

outputs:
  - path: "grimoires/loa/ledger.json"
    type: "file"
    description: "Sprint Ledger (may be created by init)"

mode:
  default: "foreground"
  allow_background: false
---

# Sprint Ledger

## Purpose

View and manage the Sprint Ledger - an append-only data structure that provides global sprint numbering across multiple `/plan-and-analyze` cycles.

## Invocation

```
/ledger              # Show current status
/ledger init         # Initialize ledger for existing project
/ledger history      # Show all cycles and sprints
```

## Subcommands

### `/ledger` (no arguments)

Shows current ledger status:

```
Sprint Ledger Status
────────────────────────────────────────
Active Cycle: "Skills Housekeeping" (cycle-002)
Current Sprint: sprint-2 (global: 4)
Next Sprint Number: 5
Archived Cycles: 1
Total Cycles: 2
```

### `/ledger init`

Initialize ledger for an existing project. Scans `grimoires/loa/a2a/sprint-*` directories to determine the next sprint number.

**Use when**: You have an existing Loa project without a ledger and want to enable global sprint tracking.

**Example output**:
```
Initialized ledger from existing project
Detected 3 existing sprints, next sprint number: 4
```

### `/ledger history`

Shows complete history of all cycles and sprints:

```
Cycle History
─────────────────────────────────────────────────────────────
cycle-001 │ MVP Development      │ archived  │ 2 sprints
          │ Created: 2026-01-10  │ Archived: 2026-01-15
─────────────────────────────────────────────────────────────
cycle-002 │ Skills Housekeeping  │ active    │ 2 sprints
          │ Created: 2026-01-17  │
```

## How It Works

The Sprint Ledger solves sprint number collisions in multi-cycle projects:

1. **Global Counter**: Every sprint gets a globally unique ID (1, 2, 3...)
2. **Local Labels**: Users still refer to "sprint-1", "sprint-2" within a cycle
3. **Resolution**: Commands like `/implement sprint-1` resolve to global IDs
4. **A2A Directories**: Use global IDs (`a2a/sprint-4/`, not `a2a/sprint-1/`)

## Ledger Location

`grimoires/loa/ledger.json` (State Zone)

## Related Commands

| Command | Purpose |
|---------|---------|
| `/archive-cycle` | Archive current cycle and start fresh |
| `/plan-and-analyze` | Creates ledger and cycle automatically |
| `/implement sprint-N` | Resolves sprint-N to global ID |

## Workflow

```bash
# New project - ledger created automatically
/plan-and-analyze
/architect
/sprint-plan          # Registers sprints in ledger
/implement sprint-1   # Resolves to global sprint-1

# After completing first cycle
/archive-cycle "MVP Complete"  # Archives cycle

# Start new cycle
/plan-and-analyze     # Creates new cycle
/sprint-plan          # sprint-1 now maps to global sprint-3
/implement sprint-1   # Resolves to global sprint-3
```

## Error Handling

| Error | Resolution |
|-------|------------|
| "Ledger already exists" | Ledger already initialized |
| "No active cycle" | Run `/plan-and-analyze` first |
| "Ledger not found" | Run `/ledger init` to create |
