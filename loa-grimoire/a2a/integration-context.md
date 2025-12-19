# Integration Context

This file stores integration IDs and configuration for the Loa framework's external service connections. Agents reference this file when creating issues, tracking work, or interacting with external services.

## Linear Configuration

### Team: Laboratory

| Field | Value |
|-------|-------|
| Team ID | `466d92ac-5b8d-447d-9d2b-cc320ee23b31` |
| Team Key | `LAB` |

### Project: Loa Feedback

| Field | Value |
|-------|-------|
| Project ID | `7939289a-4a48-4615-abb6-8780416f1b7d` |
| Project URL | https://linear.app/honeyjar/project/loa-feedback-e1d3d533bc4f |
| Purpose | Developer feedback collection from /feedback command |

## Label Taxonomy

Standard labels for consistent organization across all agents:

### Agent Labels (who did the work)
- `agent:implementer` - Sprint implementation work
- `agent:reviewer` - Code review work
- `agent:devops` - Infrastructure and deployment work
- `agent:auditor` - Security audit findings
- `agent:planner` - Sprint planning work

### Type Labels (what kind of work)
- `type:feature` - New functionality
- `type:bugfix` - Bug fixes
- `type:refactor` - Code improvements
- `type:infrastructure` - DevOps/deployment work
- `type:security` - Security-related work
- `type:audit-finding` - Security audit findings
- `type:planning` - Planning documentation
- `type:feedback` - Developer feedback submissions

### Priority Labels (for audit findings)
- `priority:critical` - Must fix immediately (blocking)
- `priority:high` - Must fix before production

### Sprint Labels
- `sprint:sprint-1`, `sprint:sprint-2`, etc.

### Source Labels (where work originated)
- `source:discord` - From Discord feedback
- `source:internal` - Internal/agent-generated
- `source:feedback` - From /feedback command

## Issue Templates

### Feedback Issue Template

```markdown
## Developer Feedback

**Framework Version**: {version}
**Developer**: {git_user_name} <{git_user_email}>
**Date**: {submission_date}

### Ratings

| Aspect | Rating (1-5) |
|--------|--------------|
| Overall Experience | {overall_rating} |
| Documentation | {docs_rating} |
| Agent Quality | {agent_rating} |
| Workflow Clarity | {workflow_rating} |

### Feedback

{feedback_text}

### Analytics Summary

{analytics_summary}
```

## Commit Message Templates

### Implementation Commits
```
feat(sprint-N): {description}

- Task: {task_id}
- Files: {file_count} modified
- Tests: {test_status}

Co-Authored-By: Claude Code <noreply@anthropic.com>
```

### Feedback Commits
```
docs(feedback): submit developer feedback

- Rating: {overall_rating}/5
- Framework: v{version}
```

## Workflow State Mappings

| Loa State | Linear State |
|-----------|--------------|
| Not started | Backlog |
| In progress | In Progress |
| Review | In Review |
| Completed | Done |
| Blocked | Blocked |

---

*Last updated: Sprint 1 implementation*
