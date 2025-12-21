# Session End Protocol

Before ending a development session, follow this checklist to ensure clean state handoff.

## Beads Sync Checklist

### 1. Update In-Progress Work

Check for any tasks still marked as in-progress:

```bash
bd list --status in_progress --json
```

For each task:
- If completed: `bd close <id> --reason "Completed in this session"`
- If partially done: `bd update <id> --notes "SESSION END: [progress notes, what's left to do]"`

### 2. File Discovered Work

Create issues for any TODOs, bugs, or follow-ups noted during the session:

```bash
# Create discovered issue
bd create "Discovered: [issue description]" -t bug -p 2 --json

# Link to relevant task if applicable
bd dep add <new-id> <related-task-id> --type discovered-from
```

### 3. Sync to Git

Commit the Beads database changes:

```bash
# Sync beads state
bd sync

# Stage and commit
git add .beads/beads.jsonl
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
bd ready --json  # Next actionable tasks
bd stats         # Overall progress summary
```

## Session Summary Template

Before ending, provide a summary:

```markdown
## Session Summary

### Completed
- [x] Task bd-xxxx: [description]
- [x] Task bd-yyyy: [description]

### In Progress
- [ ] Task bd-zzzz: [description] - [what's left]

### Discovered Issues
- bd-aaaa: [new bug/debt discovered]

### Next Session
Run `bd ready` to see: [brief description of next priorities]
```

## Memory Decay (Monthly Maintenance)

For older closed issues (30+ days), run compaction to save context:

```bash
# Analyze candidates for compaction
bd compact --analyze --json > candidates.json

# Review candidates manually, then apply
bd compact --apply --id <id> --summary <summary-file>
```

This preserves essential information while reducing context size.

## Drift Detection (Established Repos)

For `repo_mode: established` repositories, run drift detection before ending session:

```bash
# Run drift check
.claude/scripts/detect-drift.sh

# Or with verbose output
.claude/scripts/detect-drift.sh --verbose

# Auto-create Beads issues for drift
.claude/scripts/detect-drift.sh --create-issues
```

Review any drift issues and note them in the session summary.

## Compaction Check (Weekly Maintenance)

For repos with substantial Beads history, check if compaction is needed:

```bash
# Check closed issue count
CLOSED_COUNT=$(bd list --status closed --json 2>/dev/null | jq 'length')

if [ "$CLOSED_COUNT" -gt 50 ]; then
  echo "Consider compaction: $CLOSED_COUNT closed issues"
  echo "Run: bd compact --analyze --json"
fi
```

Compaction summarizes old closed issues to save context window tokens while preserving essential information.

## Established Repo Session Checklist

For `repo_mode: established`, verify before ending:

- [ ] All modified files have test coverage
- [ ] Change plans documented in `loa-grimoire/plans/`
- [ ] No red flags left unaddressed
- [ ] Drift detection run
- [ ] Discovered issues filed with `discovered-from` links
- [ ] Tests pass (same count as session start)

## Quick Reference

| Action | Command |
|--------|---------|
| Check in-progress | `bd list --status in_progress --json` |
| Complete task | `bd close <id> --reason "..."` |
| Add session notes | `bd update <id> --notes "SESSION: ..."` |
| Create discovered issue | `bd create "Discovered: ..." -t bug --json` |
| Sync to git | `.claude/scripts/beads/sync-to-git.sh` |
| See next work | `bd ready --json` |
| Check drift | `.claude/scripts/detect-drift.sh` |
| Validate change plan | `.claude/scripts/validate-change-plan.sh <plan.json>` |
