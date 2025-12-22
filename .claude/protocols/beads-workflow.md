# Beads Workflow Protocol

Beads (`bd`) is a git-backed graph memory system used for sprint lifecycle management in Loa v4.

## Core Concepts

### Hash-based IDs
All Loa issues use hash-based IDs: `bd-xxxx` (4-6 hex chars)
- Collision-resistant
- Merge-friendly
- Never create sequential IDs manually

### Issue Hierarchy
- **Epic**: Sprint-level container (e.g., `bd-a3f8` = Sprint 1)
- **Task**: Work item within sprint (`bd-a3f8.1`, `bd-a3f8.2`)
- **Subtask**: Granular steps (`bd-a3f8.1.1`)

### Dependency Types

| Type | Usage in Loa |
|------|--------------|
| `blocks` | Task cannot start until blocker is closed (hard dependency) |
| `parent-child` | Sprint epic to tasks hierarchy |
| `discovered-from` | Bug/debt found during implementation |
| `related` | Cross-sprint references, documentation links (soft dependency) |

### Ready Detection
`bd ready` returns tasks with no open blockers - the next actionable work.

### Git-backed Storage
- Source of truth: `.beads/beads.jsonl`
- Synced via git for collaboration
- Memory decay: `bd compact` summarizes old closed issues to save context

## Workflow Commands

| Action | Command |
|--------|---------|
| Find ready work | `bd ready --json` |
| Find ready work (prioritized) | `bd ready --sort priority --json` |
| Get task details | `bd show <id> --json` |
| Start work | `bd update <id> --status in_progress` |
| Complete task | `bd close <id> --reason "description"` |
| Log discovered work | `bd create "title" -t bug --json` |
| Link discovered work | `bd dep add <new-id> <parent-id> --type discovered-from` |
| View sprint tree | `bd dep tree <sprint-epic-id>` |
| Check blockers | `bd blocked --json` |
| List all issues | `bd list --json` |
| Get stats | `bd stats` |

## Sprint Epic Creation

```bash
# Create sprint epic
bd create "Sprint N: [Theme]" -t epic -p 1 --json

# Create tasks as children (auto-assigns hierarchical IDs)
bd create "Task title" -t task -p <priority> -d "Description" --json

# Add blocking dependencies
bd dep add <dependent-id> <blocker-id> --type blocks

# Visualize sprint structure
bd dep tree <sprint-epic-id>
```

## Implementation Workflow

### Starting Work
```bash
# Find next ready task
bd ready --limit 1 --json | jq '.[0]'

# Mark as in-progress
bd update <id> --status in_progress --json
```

### During Implementation
```bash
# When discovering bugs or tech debt
NEW_ID=$(bd create "Discovered: [issue]" -t bug -p 2 --json | jq -r '.id')
bd dep add $NEW_ID <current-task-id> --type discovered-from
```

### Completing Work
```bash
bd close <id> --reason "Implemented in commit <sha>"
```

## Review Workflow

### Finding Review Items
```bash
# Find tasks needing review
bd list --status in_progress --json | jq '[.[] | select(.labels | contains(["needs-review"]))]'
```

### Recording Feedback
```bash
# Add review notes directly to issue
bd update <id> --notes "REVIEW: [feedback details]"
```

### Approval Flow
- **Approve**: `bd close <id> --reason "Code review approved"`
- **Request changes**: `bd update <id> --status open` + add notes

## Uncertainty Protocol

If a task ID is missing or the graph state is ambiguous:

1. State: "I cannot find issue `<id>` in the Beads graph"
2. Run `bd list --json` to verify available issues
3. Ask for clarification rather than assuming

Never guess at task IDs or state. The graph is source of truth.

## Session End Checklist

Before ending session:

1. **Update in-progress work**:
   ```bash
   bd list --status in_progress --json
   ```
   For each: either close or add status notes

2. **File discovered work**:
   Create issues for any TODOs, bugs, or follow-ups noted during session

3. **Sync to git**:
   ```bash
   bd sync
   git add .beads/beads.jsonl
   git commit -m "chore(beads): sync issue state"
   git push
   ```

4. **Verify clean state**:
   ```bash
   bd ready --json  # Show what's next for future sessions
   ```

## Memory Decay (Compaction)

Run periodically for closed issues older than 30 days:

```bash
# Analyze candidates for compaction
bd compact --analyze --json > candidates.json

# Review candidates, then apply
bd compact --apply --id <id> --summary <summary-file>
```

## Priority Levels

| Priority | Meaning | Usage |
|----------|---------|-------|
| 0 | No priority | Background/optional work |
| 1 | Urgent | Sprint epics, blocking issues |
| 2 | High | Core sprint tasks |
| 3 | Normal | Standard tasks |
| 4 | Low | Nice-to-have, polish |

## Task Types

| Type | Usage |
|------|-------|
| `epic` | Sprint container |
| `task` | Standard work item |
| `bug` | Discovered defect |
| `chore` | Maintenance/cleanup |
| `docs` | Documentation |

## Integration with Loa Phases

| Phase | Beads Usage |
|-------|-------------|
| `/sprint-plan` | Creates sprint epic + tasks |
| `/implement sprint-N` | Queries `bd ready`, updates status |
| `/review-sprint sprint-N` | Reviews tasks, records feedback via notes |
| `/audit-sprint sprint-N` | Final verification, closes epic |

## Coexistence with sprint.md

During transition, `loa-grimoire/sprint.md` remains as human-readable archive:
- Beads is source of truth for task state
- sprint.md provides overview and context
- Both are kept in sync by agents

## Helper Scripts

Located in `.claude/scripts/beads/`:

| Script | Purpose |
|--------|---------|
| `get-sprint-tasks.sh` | List all tasks under a sprint epic |
| `create-sprint-epic.sh` | Create new sprint epic |
| `get-ready-by-priority.sh` | Get ready work sorted by priority |

## Guiding Principles

1. **Determinism over parsing**: Always use `bd` commands with `--json` flag; never parse `.beads/*.jsonl` directly
2. **Atomic updates**: One `bd` command per state change; avoid complex bash pipelines
3. **Explicit uncertainty**: Agents must say "I don't know" when graph state is ambiguous
4. **Progressive disclosure**: Reference this protocol; don't duplicate in every SKILL.md
5. **Graceful coexistence**: Keep sprint.md as optional human-readable archive during transition
