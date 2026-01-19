# Software Design Document: Sprint Ledger

**Version**: 1.0.0
**Date**: 2026-01-17
**Status**: Draft
**Author**: designing-architecture agent
**PRD Reference**: `grimoires/loa/prd.md`

---

## 1. Executive Summary

The Sprint Ledger is a lightweight append-only data structure that provides global sprint numbering and artifact lifecycle management for Loa projects. It solves the problem of sprint number collisions in multi-cycle projects by maintaining a monotonically increasing counter and mapping local sprint labels to global IDs.

**Key Design Decisions:**
- JSON file at `grimoires/loa/ledger.json` (State Zone)
- Bash library (`ledger-lib.sh`) following `constructs-lib.sh` patterns
- Backward compatible - existing projects work without ledger
- Single active cycle constraint (no parallel development tracks)

---

## 2. System Architecture

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                           LOA COMMANDS                               │
│  /plan-and-analyze  /sprint-plan  /implement  /review  /audit       │
└─────────────┬───────────────┬──────────────────┬────────────────────┘
              │               │                  │
              ▼               ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        LEDGER-LIB.SH                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │ init_ledger │  │ create_cycle│  │resolve_sprint│  │archive_cycle│ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘ │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │ get_next_   │  │ add_sprint  │  │ get_active_ │  │ get_ledger │ │
│  │ sprint_num  │  │             │  │ cycle       │  │ _status    │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    grimoires/loa/ledger.json                         │
│  {                                                                   │
│    "version": 1,                                                     │
│    "next_sprint_number": 5,                                          │
│    "active_cycle": "cycle-002",                                      │
│    "cycles": [...]                                                   │
│  }                                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
User: /implement sprint-1
         │
         ▼
┌─────────────────────┐     ┌──────────────────────┐
│ validate-sprint-id  │────▶│ Ledger exists?       │
│ (format check)      │     │                      │
└─────────────────────┘     └──────────┬───────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │ YES                                  │ NO
                    ▼                                      ▼
         ┌──────────────────┐                   ┌──────────────────┐
         │ resolve_sprint   │                   │ Legacy behavior  │
         │ "sprint-1" → 3   │                   │ (no resolution)  │
         └────────┬─────────┘                   └────────┬─────────┘
                  │                                      │
                  ▼                                      ▼
         ┌──────────────────┐                   ┌──────────────────┐
         │ a2a/sprint-3/    │                   │ a2a/sprint-1/    │
         └──────────────────┘                   └──────────────────┘
```

---

## 3. Software Stack

| Component | Technology | Version | Justification |
|-----------|------------|---------|---------------|
| Data format | JSON | - | Human-readable, jq-compatible, existing pattern |
| Library | Bash | 4.0+ | Consistent with `constructs-lib.sh`, no new dependencies |
| JSON parsing | jq | 1.6+ | Already required by Loa |
| YAML parsing | yq | 4.0+ | Already required by Loa |
| Date handling | GNU/BSD date | - | Cross-platform via `constructs-lib.sh` patterns |

**No new dependencies required.**

---

## 4. Data Architecture

### 4.1 Ledger Schema (v1)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["version", "next_sprint_number", "cycles"],
  "properties": {
    "version": {
      "type": "integer",
      "const": 1,
      "description": "Schema version for future migrations"
    },
    "created": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 timestamp of ledger creation"
    },
    "last_updated": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 timestamp of last modification"
    },
    "next_sprint_number": {
      "type": "integer",
      "minimum": 1,
      "description": "Next global sprint number to allocate (monotonic)"
    },
    "active_cycle": {
      "type": ["string", "null"],
      "description": "ID of currently active cycle, null if none"
    },
    "cycles": {
      "type": "array",
      "items": { "$ref": "#/definitions/cycle" }
    }
  },
  "definitions": {
    "cycle": {
      "type": "object",
      "required": ["id", "label", "status", "created", "sprints"],
      "properties": {
        "id": {
          "type": "string",
          "pattern": "^cycle-[0-9]{3}$",
          "description": "Unique cycle identifier (cycle-001, cycle-002, etc.)"
        },
        "label": {
          "type": "string",
          "description": "Human-readable cycle name"
        },
        "status": {
          "type": "string",
          "enum": ["active", "archived"],
          "description": "Cycle status"
        },
        "created": {
          "type": "string",
          "format": "date-time"
        },
        "archived": {
          "type": ["string", "null"],
          "format": "date-time",
          "description": "When cycle was archived, null if active"
        },
        "archive_path": {
          "type": ["string", "null"],
          "description": "Path to archived artifacts, null if active"
        },
        "prd": {
          "type": "string",
          "description": "Path to PRD file"
        },
        "sdd": {
          "type": ["string", "null"],
          "description": "Path to SDD file, null if not yet created"
        },
        "sprints": {
          "type": "array",
          "items": { "$ref": "#/definitions/sprint" }
        }
      }
    },
    "sprint": {
      "type": "object",
      "required": ["global_id", "local_label", "status"],
      "properties": {
        "global_id": {
          "type": "integer",
          "minimum": 1,
          "description": "Globally unique sprint number"
        },
        "local_label": {
          "type": "string",
          "pattern": "^sprint-[0-9]+$",
          "description": "User-facing sprint label within cycle"
        },
        "status": {
          "type": "string",
          "enum": ["planned", "in_progress", "completed"],
          "description": "Sprint status"
        },
        "created": {
          "type": "string",
          "format": "date-time"
        },
        "completed": {
          "type": ["string", "null"],
          "format": "date-time"
        }
      }
    }
  }
}
```

### 4.2 Example Ledger

```json
{
  "version": 1,
  "created": "2026-01-10T10:00:00Z",
  "last_updated": "2026-01-17T15:30:00Z",
  "next_sprint_number": 5,
  "active_cycle": "cycle-002",
  "cycles": [
    {
      "id": "cycle-001",
      "label": "MVP Development",
      "status": "archived",
      "created": "2026-01-10T10:00:00Z",
      "archived": "2026-01-15T12:00:00Z",
      "archive_path": "grimoires/loa/archive/2026-01-15-mvp-development/",
      "prd": "grimoires/loa/archive/2026-01-15-mvp-development/prd.md",
      "sdd": "grimoires/loa/archive/2026-01-15-mvp-development/sdd.md",
      "sprints": [
        {"global_id": 1, "local_label": "sprint-1", "status": "completed", "created": "2026-01-10T12:00:00Z", "completed": "2026-01-12T18:00:00Z"},
        {"global_id": 2, "local_label": "sprint-2", "status": "completed", "created": "2026-01-12T18:00:00Z", "completed": "2026-01-15T12:00:00Z"}
      ]
    },
    {
      "id": "cycle-002",
      "label": "Skills Housekeeping",
      "status": "active",
      "created": "2026-01-17T10:00:00Z",
      "archived": null,
      "archive_path": null,
      "prd": "grimoires/loa/prd.md",
      "sdd": "grimoires/loa/sdd.md",
      "sprints": [
        {"global_id": 3, "local_label": "sprint-1", "status": "completed", "created": "2026-01-17T11:00:00Z", "completed": "2026-01-17T14:00:00Z"},
        {"global_id": 4, "local_label": "sprint-2", "status": "in_progress", "created": "2026-01-17T14:00:00Z", "completed": null}
      ]
    }
  ]
}
```

### 4.3 Directory Structure

```
grimoires/loa/
├── ledger.json                    # Sprint Ledger (source of truth)
├── prd.md                         # Current cycle PRD
├── sdd.md                         # Current cycle SDD
├── sprint.md                      # Current sprint plan
├── NOTES.md                       # Agentic memory
├── a2a/
│   ├── index.md                   # Audit trail index
│   ├── trajectory/                # Agent reasoning logs
│   ├── audits/                    # Codebase audits
│   ├── sprint-1/                  # Global sprint 1 (cycle-001)
│   ├── sprint-2/                  # Global sprint 2 (cycle-001)
│   ├── sprint-3/                  # Global sprint 3 (cycle-002)
│   ├── sprint-4/                  # Global sprint 4 (cycle-002)
│   ├── deployment-report.md
│   └── deployment-feedback.md
└── archive/
    └── 2026-01-15-mvp-development/
        ├── prd.md
        ├── sdd.md
        ├── sprint.md
        └── a2a/                   # Archived sprint artifacts
            ├── sprint-1/          # Copied, not moved (global IDs preserved)
            └── sprint-2/
```

---

## 5. Component Design

### 5.1 ledger-lib.sh

**Location**: `.claude/scripts/ledger-lib.sh`

**Pattern**: Follows `constructs-lib.sh` conventions:
- `set -euo pipefail`
- Functions return values via `echo`, status via exit codes
- Colors respect `NO_COLOR` environment variable
- Cross-platform date handling

#### Core Functions

```bash
# =============================================================================
# Ledger Path Functions
# =============================================================================

get_ledger_path()
# Returns: "grimoires/loa/ledger.json"

ledger_exists()
# Returns: 0 if ledger exists, 1 if not

# =============================================================================
# Initialization Functions
# =============================================================================

init_ledger()
# Creates new ledger.json if not exists
# Scans existing a2a/sprint-* directories to set next_sprint_number
# Returns: 0 on success, 1 on error

init_ledger_from_existing()
# Migration helper: creates ledger from existing project state
# Detects highest sprint number from a2a/sprint-* directories
# Returns: 0 on success, 1 on error

# =============================================================================
# Cycle Management
# =============================================================================

get_active_cycle()
# Returns: Cycle ID (e.g., "cycle-002") or "null" if none active

create_cycle(label)
# Args: $1 - Human-readable label for the cycle
# Creates new cycle entry, sets as active
# Returns: New cycle ID (e.g., "cycle-003")

archive_cycle(slug)
# Args: $1 - Slug for archive directory (e.g., "mvp-complete")
# Archives active cycle to grimoires/loa/archive/YYYY-MM-DD-{slug}/
# Sets active_cycle to null
# Returns: Archive path

get_cycle_by_id(cycle_id)
# Args: $1 - Cycle ID
# Returns: JSON object of cycle or "null"

# =============================================================================
# Sprint Management
# =============================================================================

get_next_sprint_number()
# Returns: Next global sprint number (integer)
# Note: Does NOT increment counter, use allocate_sprint_number for that

allocate_sprint_number()
# Increments next_sprint_number and returns the allocated number
# This is atomic: read + increment + write
# Returns: Allocated sprint number (integer)

add_sprint(local_label)
# Args: $1 - Local label (e.g., "sprint-1")
# Allocates global ID, adds to active cycle
# Returns: Global sprint ID (integer)

resolve_sprint(local_label)
# Args: $1 - Local label (e.g., "sprint-1") or global (e.g., "sprint-47")
# Resolves to global sprint ID within active cycle
# Returns: Global sprint ID or "UNRESOLVED" if not found

update_sprint_status(global_id, status)
# Args: $1 - Global sprint ID, $2 - New status
# Updates sprint status in ledger
# Returns: 0 on success, 1 on error

get_sprint_directory(global_id)
# Args: $1 - Global sprint ID
# Returns: Path to a2a directory (e.g., "grimoires/loa/a2a/sprint-3")

# =============================================================================
# Query Functions
# =============================================================================

get_ledger_status()
# Returns: JSON object with summary:
# {
#   "active_cycle": "cycle-002",
#   "active_cycle_label": "Skills Housekeeping",
#   "current_sprint": 4,
#   "current_sprint_local": "sprint-2",
#   "next_sprint_number": 5,
#   "total_cycles": 2,
#   "archived_cycles": 1
# }

get_cycle_history()
# Returns: JSON array of all cycles with summary info

# =============================================================================
# Validation Functions
# =============================================================================

validate_ledger()
# Validates ledger.json against schema
# Returns: 0 if valid, 1 if invalid with error message

ensure_ledger_backup()
# Creates backup before write operations
# Location: grimoires/loa/ledger.json.bak
```

### 5.2 validate-sprint-id.sh (Modified)

**Current behavior**: Validates format only (`sprint-N`)

**New behavior**: If ledger exists, also resolves local to global:

```bash
# Current output
echo "VALID"

# New output (when ledger exists)
echo "VALID|global_id=3|local_label=sprint-1"

# Or if sprint not found in ledger
echo "VALID|global_id=NEW|local_label=sprint-1"
```

### 5.3 Command Modifications

#### /plan-and-analyze

**Pre-flight addition**:
```yaml
pre_flight:
  - check: "script"
    script: "ledger-preflight.sh"
    action: "prompt_archive_or_create"
```

**Logic**:
1. If no ledger exists → Initialize ledger, create cycle
2. If ledger exists with active cycle → Prompt: "Archive current cycle or continue?"
3. If ledger exists with no active cycle → Create new cycle

#### /sprint-plan

**Modification**: After sprint plan is created, register in ledger:

```bash
# In sprint-plan skill workflow
if ledger_exists; then
    local global_id=$(add_sprint "sprint-1")
    echo "Registered sprint-1 as global sprint-${global_id}"
fi
```

#### /implement, /review-sprint, /audit-sprint

**Modification**: Resolve sprint ID before processing:

```bash
# In pre-flight or early workflow
local input_sprint="$1"  # e.g., "sprint-1"

if ledger_exists; then
    local global_id=$(resolve_sprint "$input_sprint")
    if [[ "$global_id" == "UNRESOLVED" ]]; then
        echo "Error: Sprint '$input_sprint' not found in active cycle"
        exit 1
    fi
    SPRINT_DIR="grimoires/loa/a2a/sprint-${global_id}"
else
    # Legacy: use input directly
    SPRINT_DIR="grimoires/loa/a2a/${input_sprint}"
fi
```

### 5.4 New Commands

#### /ledger

**Location**: `.claude/commands/ledger.md`

```yaml
---
name: "ledger"
version: "1.0.0"
description: "View and manage Sprint Ledger status"

arguments:
  - name: "subcommand"
    type: "string"
    required: false
    description: "Subcommand: init, history, or empty for status"
    examples: ["init", "history"]

pre_flight: []

outputs:
  - path: "grimoires/loa/ledger.json"
    type: "file"
    description: "Sprint Ledger (may be created)"
---
```

**Subcommands**:
- `/ledger` - Show current status
- `/ledger init` - Initialize ledger for existing project
- `/ledger history` - Show all cycles and sprints

#### /archive-cycle

**Location**: `.claude/commands/archive-cycle.md`

```yaml
---
name: "archive-cycle"
version: "1.0.0"
description: "Archive current cycle and prepare for new /plan-and-analyze"

arguments:
  - name: "label"
    type: "string"
    required: true
    description: "Label for archive (becomes directory slug)"
    examples: ["mvp-complete", "phase-1-done"]

pre_flight:
  - check: "file_exists"
    path: "grimoires/loa/ledger.json"
    error: "No ledger found. Run /ledger init first."
  - check: "script"
    script: "check-active-cycle.sh"
    error: "No active cycle to archive."

outputs:
  - path: "grimoires/loa/archive/$DATE-$LABEL/"
    type: "directory"
    description: "Archived cycle artifacts"
---
```

---

## 6. API Specifications

### 6.1 ledger-lib.sh Function Signatures

| Function | Args | Returns | Exit Code |
|----------|------|---------|-----------|
| `get_ledger_path` | - | Path string | 0 |
| `ledger_exists` | - | - | 0=exists, 1=not |
| `init_ledger` | - | - | 0=success, 1=error |
| `get_active_cycle` | - | Cycle ID or "null" | 0 |
| `create_cycle` | label | Cycle ID | 0=success, 1=error |
| `archive_cycle` | slug | Archive path | 0=success, 1=error |
| `get_next_sprint_number` | - | Integer | 0 |
| `allocate_sprint_number` | - | Integer | 0 |
| `add_sprint` | local_label | Global ID | 0=success, 1=error |
| `resolve_sprint` | local_label | Global ID or "UNRESOLVED" | 0 |
| `update_sprint_status` | global_id, status | - | 0=success, 1=error |
| `get_sprint_directory` | global_id | Path string | 0 |
| `get_ledger_status` | - | JSON object | 0 |
| `validate_ledger` | - | - | 0=valid, 1=invalid |

### 6.2 Error Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error / Invalid state |
| 2 | Ledger not found |
| 3 | No active cycle |
| 4 | Sprint not found |
| 5 | Validation error |

---

## 7. Error Handling Strategy

### 7.1 Ledger Corruption Recovery

```bash
# In ledger-lib.sh
ensure_ledger_backup() {
    local ledger_path=$(get_ledger_path)
    if [[ -f "$ledger_path" ]]; then
        cp "$ledger_path" "${ledger_path}.bak"
    fi
}

recover_from_backup() {
    local ledger_path=$(get_ledger_path)
    local backup_path="${ledger_path}.bak"
    if [[ -f "$backup_path" ]]; then
        cp "$backup_path" "$ledger_path"
        echo "Recovered ledger from backup"
        return 0
    fi
    return 1
}
```

### 7.2 Fallback Behavior

When ledger operations fail, commands should fall back to legacy behavior:

```bash
resolve_sprint_safe() {
    local input="$1"

    if ! ledger_exists; then
        # Legacy: return input as-is
        echo "${input#sprint-}"
        return 0
    fi

    local result
    result=$(resolve_sprint "$input" 2>/dev/null) || {
        # Fallback on error
        echo "${input#sprint-}"
        return 0
    }

    echo "$result"
}
```

---

## 8. Testing Strategy

### 8.1 Unit Tests

**Location**: `tests/unit/ledger-lib.bats`

```bash
# Test categories:
# - Initialization (init_ledger, init_ledger_from_existing)
# - Cycle management (create_cycle, archive_cycle, get_active_cycle)
# - Sprint management (add_sprint, resolve_sprint, allocate_sprint_number)
# - Query functions (get_ledger_status, get_cycle_history)
# - Validation (validate_ledger)
# - Error handling (corruption recovery, fallback behavior)
```

**Target**: 30+ unit tests

### 8.2 Integration Tests

**Location**: `tests/integration/ledger-workflow.bats`

```bash
# Test scenarios:
# - New project: /plan-and-analyze creates ledger and cycle
# - Multi-cycle: Archive and start new cycle
# - Sprint resolution: /implement sprint-1 resolves correctly
# - Migration: /ledger init on existing project
# - Backward compatibility: Commands work without ledger
```

**Target**: 15+ integration tests

---

## 9. Development Phases

### Phase 1: Core Ledger (Sprint 1)
**Deliverables**:
- [ ] `ledger-lib.sh` with core functions
- [ ] `ledger.schema.json` for validation
- [ ] `/ledger` command (status only)
- [ ] Unit tests for ledger-lib.sh

**Acceptance Criteria**:
- `init_ledger` creates valid ledger.json
- `create_cycle` and `add_sprint` work correctly
- `resolve_sprint` maps local to global IDs
- All unit tests pass

### Phase 2: Command Integration (Sprint 2)
**Deliverables**:
- [ ] Modify `/plan-and-analyze` to initialize ledger
- [ ] Modify `/sprint-plan` to register sprints
- [ ] Modify `/implement`, `/review-sprint`, `/audit-sprint` for resolution
- [ ] `/ledger init` for migration
- [ ] Integration tests

**Acceptance Criteria**:
- New projects automatically get ledger
- Sprint commands resolve IDs correctly
- Existing projects can migrate via `/ledger init`
- Backward compatible (works without ledger)

### Phase 3: Archiving (Sprint 3)
**Deliverables**:
- [ ] `/archive-cycle` command
- [ ] `/ledger history` subcommand
- [ ] Archive directory structure
- [ ] Documentation updates

**Acceptance Criteria**:
- Archive creates dated directory with all artifacts
- Ledger updated with archive status
- History shows complete project timeline

---

## 10. Risks & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Ledger corruption during write | Low | High | Backup before write, atomic operations |
| Migration breaks existing sprints | Medium | High | Non-destructive init, preserve directories |
| Agent confusion with dual ID system | Medium | Medium | Clear logging, consistent terminology |
| Performance with large history | Low | Low | JSON is efficient, history rarely read |
| Concurrent access conflicts | Low | Medium | Single-user tool, no locking needed |

---

## 11. Open Questions (Resolved in SDD)

| Question | Resolution |
|----------|------------|
| Schema version migrations | Version field enables future migrations |
| Archive A2A handling | Copy sprint directories to archive, keep originals |
| Global ID in directory name | Yes, `a2a/sprint-{global_id}/` for clarity |
| Fallback behavior | Commands work without ledger (legacy mode) |

---

## 12. Future Considerations

### 12.1 Potential Enhancements
- **Cycle branching**: Support parallel development tracks (complex, deferred)
- **Ledger sync**: Sync ledger state via Beads or git hooks
- **Analytics**: Track cycle duration, sprint velocity

### 12.2 Technical Debt
- Consider migration to SQLite if JSON becomes unwieldy (unlikely)
- Add JSON Schema validation to CI pipeline

---

*SDD generated by designing-architecture agent*
*Grounded in: prd.md (Sprint Ledger requirements)*
*Pattern reference: constructs-lib.sh (existing library conventions)*
