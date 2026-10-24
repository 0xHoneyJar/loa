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

**NOTES.md rotation (cycle-121)**: as part of archiving, move completed-cycle
Decision Log entries and ship records from `grimoires/loa/NOTES.md` into the
cycle archive (pattern: `grimoires/loa/archive/<date>-notes-<label>.md`), keep
the live file to current-cycle state + open blockers + observations, and
re-run `bash .claude/scripts/grimoire-index.sh` so the `## notes` index section
reflects the pruned file.

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

## Record Branch (`.claude/scripts/record-branch.sh`)

The gitignored records (a2a sprint directories, audits, Flatline and prompt records, NOTES and its archive, the cycle's results batches and lite tree) are published on `record/<cycle id>`, built after the cycle PR merges and before this archive step:

```bash
.claude/scripts/record-branch.sh --cycle N --head <merge sha> --prev <previous record> --stage "stage 1" --dry-run   # size table
.claude/scripts/record-branch.sh --cycle N --head <merge sha> --prev <previous record> --stage "stage 1"
.claude/scripts/run-mode-ice.sh push origin record/<cycle id>
```

It builds in a temporary index (the working tree and real index are untouched), refuses symlinks and paths leaving the repository, scans the added paths (credential-shaped hits are never bypassable; other hits need `--accept-scan <scan_tree>`), commits with the parents `--prev` and `--head` (both must already be on origin) and moves the ref by compare-and-swap. `--manifest FILE` and `--add PATH` change what is recorded; `--help` lists every option and exit code.

## Script Contract (`.claude/scripts/archive-cycle.sh`)

The script that performs the archive (`archive-cycle.sh [--cycle N] [--retention N] [--force] [--dry-run]`) follows these rules (bug 20261021-ba367a, issue #1263):

| Rule | Behaviour |
|------|-----------|
| Default cycle | Without `--cycle`, the ledger's `active_cycle` number. When `active_cycle` is null, the highest-numbered cycle whose `status` is not `archived`. The run is refused (exit 1) when every cycle is archived, or when the newest cycle is archived while an older one is not, which marks a stale entry. With no ledger, 1. `--cycle N` always overrides. |
| Completeness gate | A cycle with any sprint whose `status` is not `completed` is refused (exit 1, nothing written) unless `--force` is passed. `--dry-run` reports what the gate would do. |
| Ledger update | After a real archive the live ledger gets the changes below, under the `ledger-lib.sh` lock and through `_write_ledger`. When `ledger-lib.sh` is missing, the run is refused before anything is written. `archive_path` is relative to the repo root, or absolute with a WARN when the archive lies outside it. The `ledger.json` copied into the archive is the pre-update ledger. `--dry-run` never writes. |
| Path safety | A ledger cycle id must be a plain slug (`cycle-N` or `cycle-N-<letters, digits, . _ ->`, no `..`), or the run is refused. The archive directory must not exist yet: it is created without `-p`, so an earlier archive is never overwritten and two concurrent runs cannot write the same one. To re-archive, remove the old directory first (`git rm` if tracked). |
| Options | An unknown option, such as the typo `--dryrun`, exits 1 with usage and writes nothing. |
| Retention default | Keep every archive. Pruning happens only when `--retention N` or `compound_learning.archive.retention_cycles` names N > 0 (the CLI wins over the yaml key); the newest N are kept by mtime. |
| Tracked protection | A directory holding any git-tracked file is never deleted: it is kept with `[WARN] tracked archive kept: <path>; prune it with git`, and the dry run lists it apart from the deletion list. Outside a git work tree, or without git, the mtime rule alone applies. Any other git failure, such as dubious ownership, keeps every archive with a WARN. |

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
| "N incomplete sprint(s); refusing to archive" | A sprint of the cycle is not `completed` | Finish the sprint, or pass `--force` to archive anyway |
| "every cycle in the ledger is archived" / "the newest cycle (…) is archived but an older cycle (…) is not" | No safe default cycle | Pass `--cycle N` explicitly |
| "archive already exists: …" | The cycle's archive directory is already present | Remove it (`git rm` if tracked) to re-archive, or pass another `--cycle` |
| "ledger cycle id is not a safe slug" | The ledger id contains `/`, `..` or other characters | Fix the id in the ledger |
| "unknown option: …" | A mistyped flag | Check `--help` |
| "Archive already exists" | Same slug used on same date | Use a different label |

## Related Commands

| Command | Purpose |
|---------|---------|
| `/ledger` | View current ledger status |
| `/ledger history` | View all cycles including archived |
| `/plan-and-analyze` | Start a new development cycle |
