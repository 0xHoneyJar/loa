# Beads Integration Protocol (beads_rust / br)

> **Version**: Compatible with Loa v1.0.0+
> **Binary**: `br` (beads_rust)
> **Repository**: https://github.com/Dicklesworthstone/beads_rust

---

## Philosophy

beads_rust is a **non-invasive** issue tracker designed for AI agent workflows. It:

- **NEVER** executes git commands
- **NEVER** auto-commits or auto-syncs
- **NEVER** runs background daemons
- **ALWAYS** requires explicit sync operations

This aligns with Loa's Three-Zone architecture where the State Zone (`.beads/`) is project-owned and all framework operations are auditable via trajectory logs.

---

## Storage Architecture

```
.beads/
├── beads.db        # SQLite database (primary storage, fast queries)
├── issues.jsonl    # JSONL export (git-friendly, one issue per line)
├── config.yaml     # Project configuration (user-owned)
└── metadata.json   # Workspace metadata
```

**Key Principle**: SQLite is the source of truth for local operations. JSONL is the interchange format for git collaboration. Explicit `br sync` commands transfer between them.

---

## Command Reference

### Issue Lifecycle

| Action | Command | Notes |
|--------|---------|-------|
| Initialize workspace | `br init` | Creates `.beads/` directory |
| Create issue | `br create "Title" --type <type> --priority <0-4> --json` | Returns created issue |
| Quick capture | `br q "Title"` | Minimal creation, returns ID only |
| Show details | `br show <id> --json` | Full issue with comments |
| Update issue | `br update <id> --status <status> --json` | Modify any field |
| Close issue | `br close <id> --reason "Description" --json` | Mark complete |
| Reopen | `br reopen <id>` | Revert to open status |
| Delete | `br delete <id>` | Tombstone (soft delete) |

### Issue Types

| Type | Usage |
|------|-------|
| `epic` | Sprint-level container |
| `task` | Standard work item |
| `bug` | Defect or regression |
| `feature` | New functionality |

### Priority Levels

| Priority | Meaning | SLA Guidance |
|----------|---------|--------------|
| P0 | Critical | Drop everything |
| P1 | High | Current sprint |
| P2 | Medium | Soon |
| P3 | Low | Backlog |
| P4 | Minimal | Nice to have |

### Status Values

| Status | Meaning |
|--------|---------|
| `open` | Not started |
| `in_progress` | Actively working |
| `closed` | Complete |
| `deferred` | Postponed |

---

## Querying

| Action | Command |
|--------|---------|
| List all issues | `br list --json` |
| Ready work (unblocked) | `br ready --json` |
| Blocked issues | `br blocked --json` |
| Full-text search | `br search "query" --json` |
| Filter by status | `br list --status open --json` |
| Filter by priority | `br list --priority 0-1 --json` |
| Filter by assignee | `br list --assignee "email" --json` |
| Stale issues | `br stale --days 30 --json` |
| Count by field | `br count --by status` |

### Complex Queries with jq

```bash
# High priority open issues
br list --json | jq '[.[] | select(.status == "open" and .priority <= 1)]'

# Issues in a specific sprint (by label)
br list --json | jq '[.[] | select(.labels[]? | contains("sprint:3"))]'

# My assigned issues
br list --json | jq --arg me "$(git config user.email)" '[.[] | select(.assignee == $me)]'

# Recently updated
br list --json | jq 'sort_by(.updated_at) | reverse | limit(10; .[])'
```

---

## Dependencies

| Action | Command |
|--------|---------|
| Add blocker | `br dep add <blocked-id> <blocker-id>` |
| Remove dependency | `br dep remove <blocked-id> <blocker-id>` |
| List dependencies | `br dep list <id>` |
| View dependency tree | `br dep tree <id>` |
| Find circular deps | `br dep cycles` |

### Dependency Semantics

beads_rust supports only **blocking** dependencies: Issue A cannot be closed until Issue B is closed.

```bash
# Task beads-xyz is blocked by beads-abc
br dep add beads-xyz beads-abc

# Now beads-xyz won't appear in `br ready` until beads-abc is closed
```

---

## Labels (Semantic Relationships)

Since beads_rust only supports blocking dependencies, use **labels** for semantic relationships:

| Relationship | Label Convention | Example |
|--------------|------------------|---------|
| Discovered during work | `discovered-during:<parent-id>` | `discovered-during:beads-a1b2` |
| Related issue | `related-to:<id>` | `related-to:beads-c3d4` |
| Part of epic | `epic:<epic-id>` | `epic:beads-sprint3` |
| Sprint membership | `sprint:<n>` | `sprint:3` |
| Needs review | `needs-review` | - |
| Review approved | `review-approved` | - |
| Security concern | `security` | - |
| Security approved | `security-approved` | - |
| Technical debt | `tech-debt` | - |

### Label Commands

```bash
# Add labels
br label add <id> label1 label2 label3

# Remove label
br label remove <id> label

# List issue's labels
br label list <id>

# List all labels in project
br label list-all

# Query by label
br list --json | jq '[.[] | select(.labels[]? == "needs-review")]'
```

---

## Comments

```bash
# Add comment
br comments add <id> "Comment text"

# List comments
br comments list <id>
```

Use comments for:
- Progress updates
- Review feedback
- Audit trail entries
- Discovered context

---

## Sync Operations

### The Sync Model

```
┌─────────────────┐         br sync          ┌─────────────────┐
│                 │ ──────────────────────── │                 │
│   beads.db      │   --flush-only (export)  │  issues.jsonl   │
│   (SQLite)      │ ◄────────────────────────│  (Git-tracked)  │
│                 │   --import-only (import) │                 │
└─────────────────┘                          └─────────────────┘
        │                                            │
        │ Fast local queries                         │ Git operations
        ▼                                            ▼
   Agent Operations                           Team Collaboration
```

### Sync Commands

| Command | Direction | Use Case |
|---------|-----------|----------|
| `br sync --flush-only` | DB → JSONL | Before git commit |
| `br sync --import-only` | JSONL → DB | After git pull |
| `br sync` | Bidirectional | Full reconciliation |
| `br sync --status` | Check only | Verify state |

### Sync Protocol for Loa Agents

**Session Start:**
```bash
# Always import latest state
br sync --import-only 2>/dev/null || br init
```

**After Write Operations:**
```bash
# After creating/updating/closing issues
br sync --flush-only
```

**Before Git Commit:**
```bash
br sync --flush-only
git add .beads/
git commit -m "Update task graph: [summary]"
```

**After Git Pull:**
```bash
git pull origin main
br sync --import-only
```

---

## Configuration

### Project Config (`.beads/config.yaml`)

```yaml
# Issue ID prefix (default: "beads")
id:
  prefix: "beads"

# Default values for new issues
defaults:
  priority: 2
  type: "task"
  assignee: ""

# Output formatting
output:
  color: true
  date_format: "%Y-%m-%d"

# Sync behavior
sync:
  auto_import: false  # Always false for beads_rust
  auto_flush: false   # Always false for beads_rust
```

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `BEADS_DB` | Override database path |
| `RUST_LOG` | Logging level (debug, info, warn, error) |

---

## Uncertainty Protocol

When task state is ambiguous or unclear:

1. **State uncertainty explicitly:**
   ```
   "I cannot verify that issue <id> exists in the beads graph."
   ```

2. **Verify with query:**
   ```bash
   br show <id> --json 2>/dev/null || echo "Issue not found"
   ```

3. **If not found, check for similar:**
   ```bash
   br list --json | jq '.[] | select(.id | contains("<partial>"))'
   ```

4. **Ask for clarification** rather than assuming

5. **NEVER fabricate** issue IDs or states

---

## Error Handling

### Check Installation

```bash
if ! command -v br &>/dev/null; then
  echo "ERROR: beads_rust (br) not installed"
  echo "Install: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh | bash"
  exit 1
fi
```

### Check Initialization

```bash
if [ ! -d ".beads" ]; then
  echo "Initializing beads workspace..."
  br init
fi
```

### Handle Sync Conflicts

```bash
# Check for issues
br doctor

# If JSONL has conflicts after merge
br sync --import-only --force  # Careful: may lose local changes

# Check sync status
br sync --status
```

---

## Diagnostics

```bash
# Health check
br doctor

# Project statistics
br stats

# Version info
br --version
```

---

## Integration with Loa Workflows

### Session Start (Hook)
```bash
.claude/scripts/beads/install-br.sh
br init 2>/dev/null || br sync --import-only
```

### `/sprint-plan`
```bash
EPIC_ID=$(br create "Sprint N: Theme" --type epic --priority 1 --json | jq -r '.id')
# Create tasks with epic label
```

### `/implement`
```bash
br sync --import-only
TASK=$(br ready --json | jq -r '.[0].id')
br update "$TASK" --status in_progress
# ... implement ...
br close "$TASK" --reason "Implemented"
br sync --flush-only
```

### `/review-sprint`
```bash
br comments add <id> "REVIEW: [feedback]"
br label add <id> review-approved
br sync --flush-only
```

### Session End
```bash
br sync --flush-only
git add .beads/
# Commit with other changes
```

---

## Limitations

beads_rust intentionally does NOT support:

| Feature | Reason | Workaround |
|---------|--------|------------|
| Background daemon | Non-invasive philosophy | Explicit sync |
| Auto-commit | Git safety | Manual git operations |
| MCP server | Focused scope | CLI with `--json` |
| Semantic compaction | Simplicity | Manual archival |
| Linear/Jira sync | Focused scope | External integration |
| `br prime` | Original beads feature | `loa-prime.sh` script |

---

## Quick Reference Card

```bash
# Session start
br sync --import-only

# Find work
br ready --json | jq '.[0]'

# Claim task
br update beads-xxx --status in_progress

# Log progress
br comments add beads-xxx "Progress update"

# Discover issue
br create "Found: bug" --type bug -p 2 --json
br label add beads-new discovered-during:beads-xxx

# Complete task
br close beads-xxx --reason "Done: summary"

# Session end
br sync --flush-only
git add .beads/ && git commit -m "Update tasks"
```
