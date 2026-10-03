# Beads Workflow (beads_rust) — auditing-security

Referenced from `auditing-security/SKILL.md` `<beads_workflow>`.

When `br` is installed: `br sync --import-only` at session start, `br sync --flush-only` at session end. Record the result — `br comments add <task-id> "SECURITY AUDIT: [verdict] - grimoires/loa/a2a/sprint-N/auditor-sprint-feedback.md"`, labelled `security`, `security-approved` or `security-blocked`. Log a discovered vulnerability as its own issue: `.claude/scripts/beads/log-discovered-issue.sh "<sprint-epic-id>" "Security: [description]" bug 0`, then `br label add <new-issue-id> security`. Protocol: `.claude/protocols/beads-integration.md`.

### Agent Teams
A teammate runs no `br` command: it reports the result to the lead via SendMessage, and the lead runs it. A comment carries the verdict and the feedback file's path only — never finding text or code.
