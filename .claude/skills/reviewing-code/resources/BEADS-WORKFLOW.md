# Beads Workflow (beads_rust) — reviewing-code

Referenced from `reviewing-code/SKILL.md` `<beads_workflow>`.

When beads_rust (`br`) is installed, use it to record review feedback:

### Session Start
```bash
br sync --import-only  # Import latest state from JSONL
```

### Recording Review Feedback
```bash
# Add review comment to task
br comments add <task-id> "REVIEW: [feedback summary]"

# Mark task status based on review outcome
br label add <task-id> review-approved     # If approved
br label add <task-id> needs-revision       # If changes required
```

### Using Labels for Status
| Label | Meaning | When to Apply |
|-------|---------|---------------|
| `needs-review` | Awaiting review | Before review |
| `review-approved` | Passed review | After "All good" |
| `needs-revision` | Changes requested | After feedback |

### Session End
```bash
br sync --flush-only  # Export SQLite → JSONL before commit
```
