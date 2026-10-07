# Beads Workflow (beads_rust) — auditing-security

Referenced from `auditing-security/SKILL.md` `<beads_workflow>`.

When `br` is installed: `br sync --import-only` at session start, `br sync --flush-only` at session end. Record the result:

```bash
br comments add <task-id> "SECURITY AUDIT: [verdict] - grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md"
br label add <task-id> security
# then exactly one of:
# If approved
br label add <task-id> security-approved
# If changes required
br label add <task-id> security-blocked
```
A re-review or re-audit adds its round's label and `br label add` never removes the other, so a task can carry both: the latest `SECURITY AUDIT:` comment is the verdict of record (with the feedback file and the COMPLETED marker), a label only history.

Log a discovered vulnerability as its own issue: `.claude/scripts/beads/log-discovered-issue.sh "<sprint-epic-id>" "Security: <criterion> (see auditor-sprint-feedback.md)" bug 0` — the criterion only, never the finding text or its file (the flushed JSONL is committed; the location stays in the feedback file), then `br label add <new-issue-id> security`. Protocol: `.claude/protocols/beads-integration.md`.

### Agent Teams
A teammate runs no `br` command: it reports the result to the lead via SendMessage, and the lead runs it. A comment carries the verdict and the feedback file's path only — never finding text or code.
