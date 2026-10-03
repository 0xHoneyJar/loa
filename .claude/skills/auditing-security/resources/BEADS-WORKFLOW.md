# Beads Workflow (beads_rust) — auditing-security

Referenced from `auditing-security/SKILL.md` `<beads_workflow>`.

When `br` is installed: `br sync --import-only` at session start, `br sync --flush-only` at session end. Record the result — `br comments add <task-id> "SECURITY AUDIT: [verdict] - [summary]"`, labelled `security`, `security-approved` or `security-blocked`. Log a discovered vulnerability as its own issue: `.claude/scripts/beads/log-discovered-issue.sh "<sprint-epic-id>" "Security: [description]" bug 0`, then `br label add <new-issue-id> security`. Protocol: `.claude/protocols/beads-integration.md`.
