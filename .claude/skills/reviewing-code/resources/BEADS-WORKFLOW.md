# Beads Workflow (beads_rust) — reviewing-code

Referenced from `reviewing-code/SKILL.md` `<beads_workflow>`.

When beads_rust (`br`) is installed, use it to record review feedback:

### Session Start
```bash
# Import latest state from JSONL
br sync --import-only
```

### Recording Review Feedback
```bash
# Add review comment to task
br comments add <task-id> "REVIEW: [verdict] - grimoires/loa/a2a/sprint-N/engineer-feedback.md"

# Mark task status based on review outcome — exactly one of:
# If approved
br label add <task-id> review-approved
# If changes required
br label add <task-id> needs-revision
```

### Using Labels for Status
| Label | Meaning | When to Apply |
|-------|---------|---------------|
| `needs-review` | Awaiting review | Before review |
| `review-approved` | Passed review | After "All good" |
| `needs-revision` | Changes requested | After feedback |

### Session End
```bash
# Export SQLite → JSONL before commit
br sync --flush-only
```

### Agent Teams
A teammate runs no `br` command: it reports the result to the lead via SendMessage, and the lead runs it. A comment carries the verdict and the feedback file's path only — never finding text or code.
