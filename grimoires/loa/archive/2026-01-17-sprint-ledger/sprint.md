# Sprint Plan: Sprint Ledger

**Version**: 1.0
**Date**: 2026-01-17
**PRD Reference**: `grimoires/loa/prd.md`
**SDD Reference**: `grimoires/loa/sdd.md`
**Feature Branch**: `feature/skills-housekeeping`

---

## Overview

| Attribute | Value |
|-----------|-------|
| Total Sprints | 3 |
| Sprint Duration | 2.5 days each |
| Total Effort | ~600 lines across 8 files |
| Team Size | 1 developer (Claude) |
| MVP Scope | Sprints 4-5 |
| Sprint Numbers | 4, 5, 6 (continuing from existing sprint-1,2,3) |

**Problem**: Loa projects with multiple `/plan-and-analyze` cycles experience sprint number collisions. "sprint-1" in cycle A collides with "sprint-1" in cycle B, causing context confusion.

**Solution**: Append-only Sprint Ledger at `grimoires/loa/ledger.json` with global sprint numbering and cycle management.

---

## Sprint 4: Core Ledger Library

**Goal**: Implement `ledger-lib.sh` with all core functions for ledger management

**Duration**: 2.5 days

### Task 4.1: Create ledger-lib.sh Scaffold

**ID**: TASK-4.1
**Priority**: P0 (Critical)
**Effort**: ~50 lines

**Description**:
Create the core library scaffold at `.claude/scripts/ledger-lib.sh` following `constructs-lib.sh` patterns:
- `set -euo pipefail` for safety
- Color support respecting `NO_COLOR`
- Cross-platform date handling
- Source header with documentation

**Acceptance Criteria**:
- [ ] File created at `.claude/scripts/ledger-lib.sh`
- [ ] Executable permissions set
- [ ] Header matches `constructs-lib.sh` style
- [ ] `get_ledger_path()` returns `grimoires/loa/ledger.json`
- [ ] `ledger_exists()` returns 0/1 appropriately

**Technical Requirements**:
- Uses `set -euo pipefail`
- Compatible with bash 4+
- Uses jq for JSON manipulation

**Files Changed**:
- `.claude/scripts/ledger-lib.sh` (CREATE)

---

### Task 4.2: Implement Ledger Initialization

**ID**: TASK-4.2
**Priority**: P0 (Critical)
**Effort**: ~80 lines

**Description**:
Implement `init_ledger()` and `init_ledger_from_existing()` functions:
- Create new ledger with v1 schema
- Scan existing `a2a/sprint-*` directories for migration
- Set `next_sprint_number` based on highest existing sprint

**Acceptance Criteria**:
- [ ] `init_ledger()` creates valid `ledger.json`
- [ ] Creates parent directory if missing
- [ ] Sets timestamps in ISO 8601 format
- [ ] `init_ledger_from_existing()` detects existing sprints
- [ ] Highest sprint number + 1 becomes `next_sprint_number`
- [ ] Returns error if ledger already exists

**Ledger Schema** (from SDD §4.1):
```json
{
  "version": 1,
  "created": "2026-01-17T10:00:00Z",
  "last_updated": "2026-01-17T10:00:00Z",
  "next_sprint_number": 1,
  "active_cycle": null,
  "cycles": []
}
```

**Files Changed**:
- `.claude/scripts/ledger-lib.sh` (MODIFY)

---

### Task 4.3: Implement Cycle Management

**ID**: TASK-4.3
**Priority**: P0 (Critical)
**Effort**: ~100 lines

**Description**:
Implement cycle management functions:
- `get_active_cycle()` - Returns active cycle ID or "null"
- `create_cycle(label)` - Creates new cycle, returns ID
- `get_cycle_by_id(cycle_id)` - Returns cycle JSON object
- Auto-generates cycle IDs (`cycle-001`, `cycle-002`, etc.)

**Acceptance Criteria**:
- [ ] `create_cycle "MVP Development"` creates cycle-001
- [ ] Sets new cycle as `active_cycle`
- [ ] Returns error if active cycle already exists
- [ ] `get_active_cycle` returns cycle ID or "null"
- [ ] `get_cycle_by_id` returns full cycle JSON
- [ ] Cycle IDs follow `cycle-NNN` format

**Files Changed**:
- `.claude/scripts/ledger-lib.sh` (MODIFY)

---

### Task 4.4: Implement Sprint Management

**ID**: TASK-4.4
**Priority**: P0 (Critical)
**Effort**: ~120 lines

**Description**:
Implement sprint management functions:
- `get_next_sprint_number()` - Returns next number (no increment)
- `allocate_sprint_number()` - Atomic increment + return
- `add_sprint(local_label)` - Adds sprint to active cycle
- `resolve_sprint(local_label)` - Maps local to global ID
- `update_sprint_status(global_id, status)` - Updates status
- `get_sprint_directory(global_id)` - Returns a2a path

**Acceptance Criteria**:
- [ ] `add_sprint "sprint-1"` allocates global ID
- [ ] `resolve_sprint "sprint-1"` returns global ID
- [ ] `resolve_sprint "sprint-47"` passes through (already global)
- [ ] Returns "UNRESOLVED" for unknown sprints
- [ ] `update_sprint_status 3 "completed"` updates ledger
- [ ] `get_sprint_directory 3` returns `grimoires/loa/a2a/sprint-3`
- [ ] Sprint statuses: `planned`, `in_progress`, `completed`

**Files Changed**:
- `.claude/scripts/ledger-lib.sh` (MODIFY)

---

### Task 4.5: Implement Query Functions

**ID**: TASK-4.5
**Priority**: P1 (High)
**Effort**: ~60 lines

**Description**:
Implement ledger query functions:
- `get_ledger_status()` - Returns JSON summary
- `get_cycle_history()` - Returns all cycles array
- `validate_ledger()` - Validates schema

**Acceptance Criteria**:
- [ ] `get_ledger_status` returns summary JSON:
  ```json
  {
    "active_cycle": "cycle-002",
    "active_cycle_label": "Skills Housekeeping",
    "current_sprint": 4,
    "current_sprint_local": "sprint-2",
    "next_sprint_number": 5,
    "total_cycles": 2,
    "archived_cycles": 1
  }
  ```
- [ ] `get_cycle_history` returns complete cycles array
- [ ] `validate_ledger` checks required fields
- [ ] Returns exit code 5 on validation failure

**Files Changed**:
- `.claude/scripts/ledger-lib.sh` (MODIFY)

---

### Task 4.6: Implement Error Handling

**ID**: TASK-4.6
**Priority**: P1 (High)
**Effort**: ~40 lines

**Description**:
Implement backup and recovery functions:
- `ensure_ledger_backup()` - Creates `.bak` before write
- `recover_from_backup()` - Restores from backup
- Consistent exit codes (0-5 per SDD §6.2)

**Acceptance Criteria**:
- [ ] Backup created at `ledger.json.bak` before writes
- [ ] Recovery restores from backup
- [ ] Exit codes match SDD §6.2:
  - 0: Success
  - 1: General error
  - 2: Ledger not found
  - 3: No active cycle
  - 4: Sprint not found
  - 5: Validation error

**Files Changed**:
- `.claude/scripts/ledger-lib.sh` (MODIFY)

---

### Task 4.7: Create /ledger Command

**ID**: TASK-4.7
**Priority**: P1 (High)
**Effort**: ~50 lines

**Description**:
Create `/ledger` command at `.claude/commands/ledger.md`:
- `/ledger` - Show current status
- `/ledger init` - Initialize ledger (existing project migration)
- Display uses `get_ledger_status()` output

**Acceptance Criteria**:
- [ ] Command created at `.claude/commands/ledger.md`
- [ ] YAML frontmatter follows existing patterns
- [ ] `/ledger` shows status summary
- [ ] `/ledger init` calls `init_ledger_from_existing()`
- [ ] Clear error if ledger already exists

**Output Format**:
```
Active Cycle: "Skills Housekeeping" (cycle-002)
Current Sprint: sprint-2 (global: 4)
Next Sprint Number: 5
Archived Cycles: 1
```

**Files Changed**:
- `.claude/commands/ledger.md` (CREATE)

---

### Task 4.8: Create Unit Tests

**ID**: TASK-4.8
**Priority**: P1 (High)
**Effort**: ~150 lines

**Description**:
Create BATS unit tests for `ledger-lib.sh` at `tests/unit/ledger-lib.bats`.

**Acceptance Criteria**:
- [ ] Test file created
- [ ] Tests for initialization functions
- [ ] Tests for cycle management
- [ ] Tests for sprint management
- [ ] Tests for query functions
- [ ] Tests for error handling
- [ ] All tests pass

**Test Categories** (30+ tests):
```bash
# Initialization
@test "init_ledger creates valid ledger"
@test "init_ledger fails if already exists"
@test "init_ledger_from_existing detects sprints"

# Cycle management
@test "create_cycle generates sequential IDs"
@test "create_cycle sets active_cycle"
@test "get_active_cycle returns ID"

# Sprint management
@test "allocate_sprint_number increments"
@test "add_sprint adds to active cycle"
@test "resolve_sprint maps local to global"
@test "resolve_sprint passes through global"
@test "update_sprint_status changes status"

# Query functions
@test "get_ledger_status returns summary"
@test "validate_ledger rejects invalid"

# Error handling
@test "ensure_ledger_backup creates backup"
@test "recover_from_backup restores"
```

**Files Changed**:
- `tests/unit/ledger-lib.bats` (CREATE)

---

### Sprint 4 Summary

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| TASK-4.1: Scaffold | P0 | ~50 lines | Pending |
| TASK-4.2: Initialization | P0 | ~80 lines | Pending |
| TASK-4.3: Cycle management | P0 | ~100 lines | Pending |
| TASK-4.4: Sprint management | P0 | ~120 lines | Pending |
| TASK-4.5: Query functions | P1 | ~60 lines | Pending |
| TASK-4.6: Error handling | P1 | ~40 lines | Pending |
| TASK-4.7: /ledger command | P1 | ~50 lines | Pending |
| TASK-4.8: Unit tests | P1 | ~150 lines | Pending |

**Sprint 4 Deliverables**:
- Complete `ledger-lib.sh` (~450 lines)
- `/ledger` command
- Unit tests (30+ tests)

**Sprint 4 Exit Criteria**:
- [ ] All ledger-lib.sh functions implemented
- [ ] `/ledger` command works
- [ ] All unit tests pass
- [ ] Manual test: create ledger, add cycle, add sprint, resolve sprint

---

## Sprint 5: Command Integration

**Goal**: Integrate ledger with existing Loa commands for seamless sprint tracking

**Duration**: 2.5 days

**Prerequisites**: Sprint 4 complete

### Task 5.1: Modify validate-sprint-id.sh

**ID**: TASK-5.1
**Priority**: P0 (Critical)
**Effort**: ~30 lines

**Description**:
Extend `validate-sprint-id.sh` to resolve local to global IDs when ledger exists.

**Acceptance Criteria**:
- [ ] Sources `ledger-lib.sh`
- [ ] Output includes resolution: `VALID|global_id=3|local_label=sprint-1`
- [ ] Returns `VALID|global_id=NEW` for new sprints
- [ ] Falls back to legacy behavior without ledger
- [ ] Backward compatible

**Files Changed**:
- `.claude/scripts/validate-sprint-id.sh` (MODIFY)

---

### Task 5.2: Modify /plan-and-analyze

**ID**: TASK-5.2
**Priority**: P0 (Critical)
**Effort**: ~40 lines

**Description**:
Update `/plan-and-analyze` command to initialize ledger and create cycles:
- Create ledger if not exists
- Create new cycle with PRD label
- Prompt to archive if active cycle exists

**Acceptance Criteria**:
- [ ] Initializes ledger on first run
- [ ] Creates cycle with label from PRD title
- [ ] If active cycle exists, prompts: "Archive current cycle or continue?"
- [ ] Updates cycle's `prd` field with path
- [ ] Backward compatible (works without changes for existing users)

**Files Changed**:
- `.claude/commands/plan-and-analyze.md` (MODIFY)

---

### Task 5.3: Modify /sprint-plan

**ID**: TASK-5.3
**Priority**: P0 (Critical)
**Effort**: ~30 lines

**Description**:
Update `/sprint-plan` command to register sprints in ledger.

**Acceptance Criteria**:
- [ ] Calls `add_sprint()` for each sprint created
- [ ] Logs: "Registered sprint-1 as global sprint-N"
- [ ] Updates cycle's `sdd` field
- [ ] Works without ledger (legacy mode)

**Files Changed**:
- `.claude/commands/sprint-plan.md` (MODIFY)

---

### Task 5.4: Modify /implement

**ID**: TASK-5.4
**Priority**: P0 (Critical)
**Effort**: ~30 lines

**Description**:
Update `/implement` command to resolve sprint IDs via ledger.

**Acceptance Criteria**:
- [ ] Resolves `sprint-1` to global ID
- [ ] Uses correct a2a directory (`sprint-N` where N is global)
- [ ] Updates sprint status to `in_progress`
- [ ] Falls back to legacy behavior without ledger
- [ ] Clear error for unresolved sprints

**Files Changed**:
- `.claude/commands/implement.md` (MODIFY)

---

### Task 5.5: Modify /review-sprint

**ID**: TASK-5.5
**Priority**: P0 (Critical)
**Effort**: ~25 lines

**Description**:
Update `/review-sprint` command to resolve sprint IDs.

**Acceptance Criteria**:
- [ ] Resolves sprint ID via ledger
- [ ] Uses correct a2a directory
- [ ] Works without ledger (legacy mode)

**Files Changed**:
- `.claude/commands/review-sprint.md` (MODIFY)

---

### Task 5.6: Modify /audit-sprint

**ID**: TASK-5.6
**Priority**: P0 (Critical)
**Effort**: ~30 lines

**Description**:
Update `/audit-sprint` command to resolve sprint IDs and update status on approval.

**Acceptance Criteria**:
- [ ] Resolves sprint ID via ledger
- [ ] Uses correct a2a directory
- [ ] On "APPROVED", updates sprint status to `completed`
- [ ] Works without ledger (legacy mode)

**Files Changed**:
- `.claude/commands/audit-sprint.md` (MODIFY)

---

### Task 5.7: Create Integration Tests

**ID**: TASK-5.7
**Priority**: P1 (High)
**Effort**: ~100 lines

**Description**:
Create BATS integration tests at `tests/integration/ledger-workflow.bats`.

**Acceptance Criteria**:
- [ ] Test: New project → /plan-and-analyze creates ledger
- [ ] Test: Multi-cycle → Archive and start new
- [ ] Test: Sprint resolution → /implement uses correct directory
- [ ] Test: Backward compatibility → Commands work without ledger
- [ ] All tests pass

**Test Cases** (15+ tests):
```bash
@test "new project creates ledger on /plan-and-analyze"
@test "/sprint-plan registers sprints"
@test "/implement resolves sprint-1 to global ID"
@test "/review-sprint uses correct directory"
@test "/audit-sprint completes sprint"
@test "backward compatible without ledger"
@test "archive cycle moves artifacts"
@test "ledger init on existing project"
```

**Files Changed**:
- `tests/integration/ledger-workflow.bats` (CREATE)

---

### Sprint 5 Summary

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| TASK-5.1: validate-sprint-id.sh | P0 | ~30 lines | Pending |
| TASK-5.2: /plan-and-analyze | P0 | ~40 lines | Pending |
| TASK-5.3: /sprint-plan | P0 | ~30 lines | Pending |
| TASK-5.4: /implement | P0 | ~30 lines | Pending |
| TASK-5.5: /review-sprint | P0 | ~25 lines | Pending |
| TASK-5.6: /audit-sprint | P0 | ~30 lines | Pending |
| TASK-5.7: Integration tests | P1 | ~100 lines | Pending |

**Sprint 5 Deliverables**:
- Modified commands with ledger integration
- Integration tests (15+ tests)
- Full backward compatibility

**Sprint 5 Exit Criteria**:
- [ ] All commands resolve sprint IDs via ledger
- [ ] New projects automatically get ledger
- [ ] Existing projects work without ledger
- [ ] All integration tests pass
- [ ] Manual test: Full cycle from /plan-and-analyze to /audit-sprint

---

## Sprint 6: Archiving & Documentation

**Goal**: Implement archive functionality and complete documentation

**Duration**: 2.5 days

**Prerequisites**: Sprint 5 complete

### Task 6.1: Implement archive_cycle()

**ID**: TASK-6.1
**Priority**: P0 (Critical)
**Effort**: ~80 lines

**Description**:
Implement `archive_cycle(slug)` function in ledger-lib.sh:
- Creates archive directory at `grimoires/loa/archive/YYYY-MM-DD-{slug}/`
- Copies current prd.md, sdd.md, sprint.md
- Copies relevant a2a/sprint-* directories
- Updates ledger with archive status
- Clears active_cycle

**Acceptance Criteria**:
- [ ] Creates dated archive directory
- [ ] Copies all current cycle artifacts
- [ ] Updates cycle status to "archived"
- [ ] Sets archive_path in cycle entry
- [ ] Clears active_cycle to null
- [ ] Original a2a directories preserved (for global ID consistency)

**Archive Structure**:
```
grimoires/loa/archive/2026-01-17-mvp-complete/
├── prd.md
├── sdd.md
├── sprint.md
└── a2a/
    ├── sprint-1/
    └── sprint-2/
```

**Files Changed**:
- `.claude/scripts/ledger-lib.sh` (MODIFY)

---

### Task 6.2: Create /archive-cycle Command

**ID**: TASK-6.2
**Priority**: P0 (Critical)
**Effort**: ~50 lines

**Description**:
Create `/archive-cycle` command at `.claude/commands/archive-cycle.md`.

**Acceptance Criteria**:
- [ ] Requires label argument: `/archive-cycle "MVP Complete"`
- [ ] Pre-flight: Validates ledger exists
- [ ] Pre-flight: Validates active cycle exists
- [ ] Calls `archive_cycle()` with slug
- [ ] Clears current prd.md, sdd.md, sprint.md (optional: keeps for reference)
- [ ] Shows confirmation message

**Files Changed**:
- `.claude/commands/archive-cycle.md` (CREATE)

---

### Task 6.3: Implement /ledger history

**ID**: TASK-6.3
**Priority**: P1 (High)
**Effort**: ~40 lines

**Description**:
Add `history` subcommand to `/ledger` command.

**Acceptance Criteria**:
- [ ] `/ledger history` shows all cycles
- [ ] Shows cycle label, status, dates, sprint count
- [ ] Format: table or list
- [ ] Uses `get_cycle_history()` function

**Output Format**:
```
Cycle History:
─────────────────────────────────────────────────────
cycle-001 │ MVP Development      │ archived │ 2 sprints
          │ Created: 2026-01-10  │ Archived: 2026-01-15
─────────────────────────────────────────────────────
cycle-002 │ Skills Housekeeping  │ active   │ 2 sprints
          │ Created: 2026-01-17  │
```

**Files Changed**:
- `.claude/commands/ledger.md` (MODIFY)

---

### Task 6.4: Update CLAUDE.md Documentation

**ID**: TASK-6.4
**Priority**: P1 (High)
**Effort**: ~40 lines

**Description**:
Add Sprint Ledger documentation to CLAUDE.md.

**Acceptance Criteria**:
- [ ] Section added under "Key Protocols" or new section
- [ ] Documents ledger location and schema
- [ ] Documents new commands: `/ledger`, `/archive-cycle`
- [ ] Documents sprint resolution behavior
- [ ] Documents backward compatibility

**Files Changed**:
- `CLAUDE.md` (MODIFY)

---

### Task 6.5: Update README.md

**ID**: TASK-6.5
**Priority**: P2 (Medium)
**Effort**: ~20 lines

**Description**:
Add brief Sprint Ledger mention to README.md.

**Acceptance Criteria**:
- [ ] Brief description in features section
- [ ] Link to CLAUDE.md for details

**Files Changed**:
- `README.md` (MODIFY)

---

### Task 6.6: Add Archive Tests

**ID**: TASK-6.6
**Priority**: P1 (High)
**Effort**: ~50 lines

**Description**:
Add archive-specific tests to integration test suite.

**Acceptance Criteria**:
- [ ] Test: Archive creates correct directory structure
- [ ] Test: Archive copies all artifacts
- [ ] Test: Ledger updated with archive status
- [ ] Test: Can start new cycle after archive
- [ ] All tests pass

**Files Changed**:
- `tests/integration/ledger-workflow.bats` (MODIFY)

---

### Sprint 6 Summary

| Task | Priority | Effort | Status |
|------|----------|--------|--------|
| TASK-6.1: archive_cycle() | P0 | ~80 lines | Pending |
| TASK-6.2: /archive-cycle | P0 | ~50 lines | Pending |
| TASK-6.3: /ledger history | P1 | ~40 lines | Pending |
| TASK-6.4: CLAUDE.md docs | P1 | ~40 lines | Pending |
| TASK-6.5: README.md | P2 | ~20 lines | Pending |
| TASK-6.6: Archive tests | P1 | ~50 lines | Pending |

**Sprint 6 Deliverables**:
- Archive functionality
- `/archive-cycle` command
- `/ledger history` subcommand
- Complete documentation

**Sprint 6 Exit Criteria**:
- [ ] Archive creates correct directory structure
- [ ] `/archive-cycle` command works
- [ ] `/ledger history` shows complete timeline
- [ ] CLAUDE.md fully documented
- [ ] All tests pass

---

## File Change Summary

| File | Sprint | Action | Lines |
|------|--------|--------|-------|
| `.claude/scripts/ledger-lib.sh` | 4, 6 | CREATE | ~530 |
| `.claude/commands/ledger.md` | 4, 6 | CREATE | ~90 |
| `.claude/commands/archive-cycle.md` | 6 | CREATE | ~50 |
| `.claude/scripts/validate-sprint-id.sh` | 5 | MODIFY | +30 |
| `.claude/commands/plan-and-analyze.md` | 5 | MODIFY | +40 |
| `.claude/commands/sprint-plan.md` | 5 | MODIFY | +30 |
| `.claude/commands/implement.md` | 5 | MODIFY | +30 |
| `.claude/commands/review-sprint.md` | 5 | MODIFY | +25 |
| `.claude/commands/audit-sprint.md` | 5 | MODIFY | +30 |
| `tests/unit/ledger-lib.bats` | 4 | CREATE | ~150 |
| `tests/integration/ledger-workflow.bats` | 5, 6 | CREATE | ~150 |
| `CLAUDE.md` | 6 | MODIFY | +40 |
| `README.md` | 6 | MODIFY | +20 |

**Total**: ~1,200 lines across 13 files

---

## Dependencies

```
Sprint 4 (Core Ledger Library)
├── TASK-4.1 (scaffold)
├── TASK-4.2 (initialization) [depends on 4.1]
├── TASK-4.3 (cycles) [depends on 4.2]
├── TASK-4.4 (sprints) [depends on 4.3]
├── TASK-4.5 (queries) [depends on 4.4]
├── TASK-4.6 (errors) [depends on 4.2]
├── TASK-4.7 (/ledger) [depends on 4.5]
└── TASK-4.8 (unit tests) [depends on 4.1-4.6]

Sprint 5 (Command Integration) [depends on Sprint 4]
├── TASK-5.1 (validate-sprint-id) [depends on 4.4]
├── TASK-5.2 (/plan-and-analyze) [depends on 4.2, 4.3]
├── TASK-5.3 (/sprint-plan) [depends on 4.4]
├── TASK-5.4 (/implement) [depends on 5.1]
├── TASK-5.5 (/review-sprint) [depends on 5.1]
├── TASK-5.6 (/audit-sprint) [depends on 5.1]
└── TASK-5.7 (integration tests) [depends on 5.1-5.6]

Sprint 6 (Archiving) [depends on Sprint 5]
├── TASK-6.1 (archive_cycle) [depends on 4.3]
├── TASK-6.2 (/archive-cycle) [depends on 6.1]
├── TASK-6.3 (/ledger history) [depends on 4.5]
├── TASK-6.4 (CLAUDE.md) [depends on all]
├── TASK-6.5 (README.md) [depends on 6.4]
└── TASK-6.6 (archive tests) [depends on 6.1, 6.2]
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Ledger corruption | Low | High | Backup before write, atomic operations |
| Migration breaks existing | Medium | High | Non-destructive init, preserve directories |
| Agent confusion dual IDs | Medium | Medium | Clear logging, consistent terminology |
| jq version compatibility | Low | Medium | Use common jq 1.6+ features only |
| Command modification breaks | Medium | Medium | Backward compatible fallback |

---

## Success Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Sprint collisions | 0 | Test multi-cycle project |
| Test coverage | >80% | BATS test assertions |
| Backward compatibility | 100% | Run without ledger |
| Command overhead | <100ms | Time resolution function |
| Migration success | 100% | Test `/ledger init` on existing |

---

## Next Steps

After sprint plan approval:
1. Run `/implement sprint-4` to start Sprint 4
2. After Sprint 4 complete: `/review-sprint sprint-4`
3. After approval: `/audit-sprint sprint-4`
4. Continue with Sprint 5, Sprint 6
5. Merge to main

---

**Document Version**: 1.0
**Created**: 2026-01-17
**Status**: READY FOR IMPLEMENTATION
