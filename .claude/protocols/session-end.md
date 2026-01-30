# Session End Protocol

Before ending a development session, follow this checklist to ensure clean state handoff.

## beads_rust Sync Checklist

### 1. Update In-Progress Work

Check for any tasks still marked as in-progress:

```bash
br list --status in_progress --json
```

For each task:
- If completed: `br close <id> --reason "Completed in this session"`
- If partially done: `br comments add <id> "SESSION END: [progress notes, what's left to do]"`

### 2. File Discovered Work

Create issues for any TODOs, bugs, or follow-ups noted during the session:

```bash
# Create discovered issue
NEW=$(br create "Discovered: [issue description]" --type bug --priority 2 --json | jq -r '.id')

# Link to relevant task with semantic label
br label add $NEW "discovered-during:<related-task-id>"
```

### 3. Sync to Git

Export and commit beads_rust state:

```bash
# Export to JSONL (explicit sync)
br sync --flush-only

# Stage and commit
git add .beads/beads.left.jsonl .beads/beads.left.meta.json
git commit -m "chore(beads): sync issue state"

# Push if appropriate
git push
```

Or use the helper script:
```bash
.claude/scripts/beads/sync-to-git.sh "end of session sync"
```

### 4. Verify Clean State

Show what's ready for the next session:

```bash
br ready --json  # Next actionable tasks
br stats         # Overall progress summary
```

## Session Summary Template

Before ending, provide a summary:

```markdown
## Session Summary

### Completed
- [x] Task br-xxxx: [description]
- [x] Task br-yyyy: [description]

### In Progress
- [ ] Task br-zzzz: [description] - [what's left]

### Discovered Issues
- br-aaaa: [new bug/debt discovered]

### Next Session
Run `br ready` to see: [brief description of next priorities]
```

## Memory Decay (Monthly Maintenance)

For older closed issues (30+ days), run compaction to save context:

```bash
# Analyze candidates for compaction
br compact --analyze --json > candidates.json

# Review candidates manually, then apply
br compact --apply --id <id> --summary <summary-file>
```

This preserves essential information while reducing context size.

## Quick Reference

| Action | Command |
|--------|---------|
| Check in-progress | `br list --status in_progress --json` |
| Complete task | `br close <id> --reason "..."` |
| Add session notes | `br comments add <id> "SESSION: ..."` |
| Create discovered issue | `br create "Discovered: ..." --type bug --json` |
| Sync to git | `.claude/scripts/beads/sync-to-git.sh` |
| See next work | `br ready --json` |
