# Product Requirements Document: Sprint Ledger

**Version**: 1.0.0
**Date**: 2026-01-17
**Status**: Approved
**Author**: discovering-requirements agent
**Feature Branch**: `feature/skills-housekeeping`

---

## 1. Problem Statement

Loa projects with multiple `/plan-and-analyze` cycles experience context confusion:

1. **Sprint Number Collisions**: When a project has multiple PRD/SDD cycles, sprint numbers restart (sprint-1, sprint-2...) for each cycle, causing conflicts in `grimoires/loa/a2a/sprint-N/`
2. **No Global Counter**: There's no append-only, monotonically increasing sprint identifier across the entire project lifecycle
3. **Artifact Confusion**: Multiple `prd.md`, `sdd.md`, `sprint.md` files with no clear "current" vs "archived" distinction
4. **Context Loss**: Agents don't know which planning artifacts are active vs historical
5. **Beads/Git Insufficient**: These track changes but don't provide a semantic ledger of sprint progression

> "loa getting confused with the context in projects where there may be a dozen /plan-and-analyze" - User feedback

**This PRD itself demonstrates the problem**: The previous PRD (Auto-Update Check) was overwritten because there's no archiving mechanism.

## 2. Vision & Goals

### Vision
An append-only Sprint Ledger that provides a single source of truth for sprint numbering and artifact lifecycle across all project phases.

### Goals

| Goal | Success Metric | Priority |
|------|----------------|----------|
| Global sprint counter | Zero sprint number collisions | P0 |
| Artifact archiving | 100% of completed artifacts archived | P1 |
| Context clarity | Agents always know current vs historical | P0 |
| Audit trail | Complete history of all sprints | P2 |

### Non-Goals

- Replacing Beads for task tracking
- Replacing git for version control
- Complex branching/merging of sprint timelines

## 3. User Stories

### US-1: As a developer, I want sprint numbers to always increment
**Acceptance Criteria:**
- Global counter persists in `grimoires/loa/ledger.json`
- `sprint-N` always means the Nth sprint ever in this project
- No two sprints share the same number

### US-2: As a developer, I want to archive completed PRD/SDD cycles
**Acceptance Criteria:**
- `/archive-cycle` command moves current artifacts to dated archive
- Archive location: `grimoires/loa/archive/YYYY-MM-DD-{slug}/`
- Archived artifacts remain readable but marked inactive

### US-3: As an agent, I want to know which artifacts are current
**Acceptance Criteria:**
- Ledger tracks "active" PRD, SDD, sprint plan
- Clear pointer to current working context
- Historical entries marked as archived

### US-4: As a developer, I want local naming mapped to global IDs
**Acceptance Criteria:**
- "Feature X sprint 1" internally maps to global `sprint-47`
- Ledger stores both human label and global ID
- Commands accept either format

## 4. Technical Design

### 4.1 Sprint Ledger File

**Location**: `grimoires/loa/ledger.json`

```json
{
  "version": 1,
  "created": "2026-01-17T10:00:00Z",
  "last_updated": "2026-01-17T15:30:00Z",
  "next_sprint_number": 4,
  "active_cycle": "cycle-002",
  "cycles": [
    {
      "id": "cycle-001",
      "label": "MVP Development",
      "status": "archived",
      "created": "2026-01-10T10:00:00Z",
      "archived": "2026-01-15T12:00:00Z",
      "archive_path": "grimoires/loa/archive/2026-01-15-mvp/",
      "prd": "grimoires/loa/archive/2026-01-15-mvp/prd.md",
      "sdd": "grimoires/loa/archive/2026-01-15-mvp/sdd.md",
      "sprints": [
        {"global_id": 1, "local_label": "sprint-1", "status": "completed"},
        {"global_id": 2, "local_label": "sprint-2", "status": "completed"}
      ]
    },
    {
      "id": "cycle-002",
      "label": "Skills Housekeeping",
      "status": "active",
      "created": "2026-01-17T10:00:00Z",
      "prd": "grimoires/loa/prd.md",
      "sdd": "grimoires/loa/sdd.md",
      "sprints": [
        {"global_id": 3, "local_label": "sprint-1", "status": "completed"},
        {"global_id": 4, "local_label": "sprint-2", "status": "in_progress"}
      ]
    }
  ]
}
```

### 4.2 Key Properties

| Property | Description |
|----------|-------------|
| **Append-only** | Entries never deleted, only status changes |
| **Monotonic** | `next_sprint_number` only increments |
| **Single active** | Only one cycle can be `active` at a time |
| **Immutable IDs** | `global_id` never changes once assigned |

### 4.3 Directory Structure

```
grimoires/loa/
├── ledger.json              # Sprint Ledger (source of truth)
├── prd.md                   # Current PRD (active cycle)
├── sdd.md                   # Current SDD (active cycle)
├── sprint.md                # Current sprint plan (active cycle)
├── a2a/
│   ├── sprint-3/            # Uses GLOBAL sprint number
│   └── sprint-4/
└── archive/
    └── 2026-01-15-mvp/      # Archived cycle
        ├── prd.md
        ├── sdd.md
        ├── sprint.md
        └── a2a/
            ├── sprint-1/    # Preserved with original numbers
            └── sprint-2/
```

### 4.4 Sprint ID Resolution

When user says "sprint-1" in active cycle:
1. Look up active cycle in ledger
2. Find sprint with `local_label: "sprint-1"`
3. Resolve to `global_id: 3`
4. A2A directory: `grimoires/loa/a2a/sprint-3/`

### 4.5 New Commands

| Command | Purpose |
|---------|---------|
| `/ledger` | Show current ledger status |
| `/ledger init` | Initialize ledger for existing project |
| `/archive-cycle [label]` | Archive current cycle and start fresh |
| `/ledger history` | Show all cycles and sprints |

### 4.6 Modified Commands

| Command | Change |
|---------|--------|
| `/plan-and-analyze` | Creates new cycle if none active, or prompts to archive |
| `/sprint-plan` | Allocates next global sprint number |
| `/implement sprint-N` | Resolves local to global ID |
| `/review-sprint sprint-N` | Resolves local to global ID |
| `/audit-sprint sprint-N` | Resolves local to global ID |

## 5. Migration Strategy

### For Existing Projects

```bash
/ledger init
```

This will:
1. Create `ledger.json` with `next_sprint_number` based on existing `a2a/sprint-*` directories
2. Create cycle entry for current artifacts
3. No file moves required

### For New Projects

Ledger created automatically on first `/plan-and-analyze`.

## 6. Implementation Phases

### Phase 1: Core Ledger (Sprint 1)
- [ ] Create `ledger.json` schema
- [ ] Implement `ledger-lib.sh` with core functions
- [ ] Add ledger initialization to `/plan-and-analyze`
- [ ] Update `/sprint-plan` to use global numbering

### Phase 2: Sprint Resolution (Sprint 2)
- [ ] Update `/implement` for ID resolution
- [ ] Update `/review-sprint` for ID resolution
- [ ] Update `/audit-sprint` for ID resolution
- [ ] Add `/ledger` status command

### Phase 3: Archiving (Sprint 3)
- [ ] Implement `/archive-cycle` command
- [ ] Create archive directory structure
- [ ] Update ledger with archive entries
- [ ] Add `/ledger history` command

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ledger corruption | High | JSON schema validation, backup on write |
| Migration breaks existing | High | Non-destructive init, preserve current structure |
| Complexity overhead | Medium | Make ledger optional via config |
| Agent confusion during transition | Medium | Clear error messages, fallback to legacy behavior |

## 8. Success Criteria

- [ ] Zero sprint number collisions in multi-cycle projects
- [ ] Agents correctly identify active vs archived artifacts
- [ ] `/ledger` command shows clear project history
- [ ] Migration works on existing Loa projects without data loss

## 9. Open Questions

1. **Should archived cycles be gitignored?** Current thinking: No, keep for audit trail
2. **Max archive retention?** Suggest: Unlimited, user manages cleanup
3. **Support for parallel cycles?** Current thinking: No, single active cycle only

### Resolved

- **Ledger location**: `grimoires/loa/ledger.json` ✅
  - Rationale: Keeps all project memory in State Zone, aligns with gitignore, enables coherent archiving

---

## Appendix A: Example Ledger Operations

### Initialize
```bash
/ledger init
# Creates ledger.json, scans existing sprints
```

### Check Status
```bash
/ledger
# Output:
# Active Cycle: "Skills Housekeeping" (cycle-002)
# Current Sprint: sprint-2 (global: 4)
# Next Sprint Number: 5
# Archived Cycles: 1
```

### Archive and Start Fresh
```bash
/archive-cycle "MVP Complete"
# Archives current cycle to grimoires/loa/archive/2026-01-17-mvp-complete/
# Clears active prd.md, sdd.md, sprint.md
# Ready for new /plan-and-analyze
```

---

*PRD generated by discovering-requirements agent*
*Source: User feedback on sprint confusion in multi-cycle projects*
