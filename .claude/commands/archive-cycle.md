---
name: "archive-cycle"
version: "1.0.0"
description: |
  Archive the current development cycle and prepare for a new one.
  Creates a dated archive with all cycle artifacts.

arguments:
  - name: "label"
    type: "string"
    required: true
    description: "Label for the archive (e.g., 'MVP Complete', 'v1.0 Release')"
    examples: ["MVP Complete", "v1.0 Release", "Phase 1 Done"]

context_files:
  - path: "grimoires/loa/ledger.json"
    required: true
    purpose: "Sprint Ledger - must have active cycle to archive"
  - path: "grimoires/loa/prd.md"
    required: false
    purpose: "Product Requirements to archive"
  - path: "grimoires/loa/sdd.md"
    required: false
    purpose: "Software Design to archive"
  - path: "grimoires/loa/sprint.md"
    required: false
    purpose: "Sprint Plan to archive"

pre_flight:
  - check: "file_exists"
    path: "grimoires/loa/ledger.json"
    error: "No ledger found. Run /plan-and-analyze first to create a ledger."
  - check: "script"
    script: ".claude/scripts/ledger-lib.sh"
    function: "get_active_cycle"
    expect_not: "null"
    error: "No active cycle to archive. Run /plan-and-analyze to start a new cycle."

outputs:
  - path: "grimoires/loa/archive/$ARCHIVE_PATH/"
    type: "directory"
    description: "Archive directory with dated slug"
  - path: "grimoires/loa/ledger.json"
    type: "file"
    description: "Updated ledger with archived cycle status"

mode:
  default: "foreground"
  allow_background: false
---

# Archive Development Cycle

## Purpose

Archive the current development cycle when it's complete. This preserves all cycle artifacts in a dated archive directory and allows starting fresh with `/plan-and-analyze`.

## When to Use

Use `/archive-cycle` when:
- You've completed all sprints in a development cycle
- You're pivoting to a new major feature or product direction
- You want to preserve the current state before starting new work
- You're releasing a version and want to snapshot the development state

## Invocation

```
/archive-cycle "MVP Complete"
/archive-cycle "v1.0 Release"
/archive-cycle "Phase 1 Done"
```

The label becomes part of the archive directory name (converted to slug format).

## Process

1. **Validate** - Confirm ledger exists and has active cycle
2. **Create Archive** - Create `grimoires/loa/archive/YYYY-MM-DD-{slug}/`
3. **Copy Artifacts** - Copy prd.md, sdd.md, sprint.md to archive
4. **Copy A2A** - Copy sprint directories for this cycle's sprints
5. **Update Ledger** - Mark cycle as archived, clear active_cycle
6. **Confirm** - Display archive location and next steps

## Archive Structure

```
grimoires/loa/archive/2026-01-17-mvp-complete/
├── prd.md              # Product Requirements snapshot
├── sdd.md              # Software Design snapshot
├── sprint.md           # Sprint Plan snapshot
└── a2a/
    ├── sprint-1/       # Sprint 1 artifacts (global ID)
    │   ├── reviewer.md
    │   ├── engineer-feedback.md
    │   ├── auditor-sprint-feedback.md
    │   └── COMPLETED
    ├── sprint-2/
    └── sprint-3/
```

## What Gets Preserved

| Item | Archived | Original |
|------|----------|----------|
| prd.md | ✓ Copied | Kept in place |
| sdd.md | ✓ Copied | Kept in place |
| sprint.md | ✓ Copied | Kept in place |
| a2a/sprint-N/ | ✓ Copied | Kept in place (for global ID consistency) |
| ledger.json | Updated | Status changed to "archived" |

**Note**: Original files are NOT deleted. This allows referencing previous work while starting a new cycle. Delete them manually if you want a clean slate.

## Ledger Changes

Before:
```json
{
  "active_cycle": "cycle-001",
  "cycles": [{
    "id": "cycle-001",
    "label": "MVP Development",
    "status": "active"
  }]
}
```

After:
```json
{
  "active_cycle": null,
  "cycles": [{
    "id": "cycle-001",
    "label": "MVP Development",
    "status": "archived",
    "archived": "2026-01-17T10:30:00Z",
    "archive_path": "grimoires/loa/archive/2026-01-17-mvp-complete"
  }]
}
```

## Next Steps After Archiving

After archiving, you'll typically:

1. **Start New Cycle**: Run `/plan-and-analyze` to create a new cycle
2. **Optionally Clear Files**: Delete old prd.md/sdd.md if starting fresh
3. **Continue Development**: New sprints will use global IDs continuing from where you left off

```bash
# Archive completed cycle
/archive-cycle "MVP Complete"

# Start new development cycle
/plan-and-analyze     # Creates cycle-002
/architect
/sprint-plan          # sprint-1 now maps to global sprint-4
```

## Sprint Numbering Continuity

The key benefit of archiving is global sprint continuity:

```
Cycle 1 (archived):
  sprint-1 → global 1
  sprint-2 → global 2
  sprint-3 → global 3

Cycle 2 (new):
  sprint-1 → global 4  # Continues from where cycle 1 left off
  sprint-2 → global 5
```

This prevents directory collisions and maintains a clear audit trail.

## Example Output

```
Archive Cycle
─────────────────────────────────────────────────────

Archiving: "MVP Development" (cycle-001)
Archive Label: "MVP Complete"

Creating archive at:
  grimoires/loa/archive/2026-01-17-mvp-complete/

Copied artifacts:
  ✓ prd.md
  ✓ sdd.md
  ✓ sprint.md
  ✓ a2a/sprint-1/
  ✓ a2a/sprint-2/
  ✓ a2a/sprint-3/

Updated ledger:
  ✓ Cycle status: archived
  ✓ Active cycle: cleared

─────────────────────────────────────────────────────

✓ Archive complete!

Next steps:
  /plan-and-analyze  - Start a new development cycle
  /ledger history    - View all cycles
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "No ledger found" | Project doesn't use Sprint Ledger | Run `/plan-and-analyze` first |
| "No active cycle" | Cycle already archived or not created | Run `/plan-and-analyze` to start |
| "Archive already exists" | Same slug used on same date | Use a different label |

## Related Commands

| Command | Purpose |
|---------|---------|
| `/ledger` | View current ledger status |
| `/ledger history` | View all cycles including archived |
| `/plan-and-analyze` | Start a new development cycle |
