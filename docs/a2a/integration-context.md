# Integration Context for Onomancer Bot

> This file provides context for agents implementing sprint tasks to ensure proper Linear issue tracking
> and organizational workflow integration.

**Last Updated**: 2025-12-13
**Project**: Onomancer Bot - DevRel Documentation Automation

---

## Linear Configuration

### Team Information

| Setting | Value |
|---------|-------|
| **Team Name** | Laboratory |
| **Team ID** | `466d92ac-5b8d-447d-9d2b-cc320ee23b31` |
| **Team Icon** | :ruggy: |

### Project Information

| Setting | Value |
|---------|-------|
| **Project Name** | Onomancer Bot |
| **Project ID** | `e72f3606-6f8c-4a19-8d19-4d717c7da992` |
| **Project URL** | https://linear.app/honeyjar/project/onomancer-bot-f08d8a92443d |
| **Lead** | jani |
| **Status** | In Progress |

---

## Label Configuration

### Required Labels for All Issues

When creating Linear issues, use these labels:

**Agent Labels** (who did the work):
- `agent:implementer` - Sprint implementation work
- `agent:reviewer` - Code review work
- `agent:devops` - Infrastructure and deployment work
- `agent:auditor` - Security audit findings
- `agent:planner` - Sprint planning work

**Type Labels** (what kind of work):
- `type:feature` - New functionality
- `type:bugfix` - Bug fixes
- `type:refactor` - Code improvements
- `type:infrastructure` - DevOps/deployment work
- `type:security` - Security-related work
- `type:audit-finding` - Security audit findings
- `type:planning` - Planning documentation

**Sprint Labels**:
- `sprint:sprint-1` - Google Workspace Foundation
- `sprint:sprint-2` - Transformation Pipeline Core
- `sprint:sprint-3` - Discord Commands Integration
- `sprint:sprint-4` - Security Controls & Testing

**Source Labels**:
- `source:discord` - From Discord feedback
- `source:internal` - Internal/agent-generated

---

## Issue Creation Guidelines

### Parent Issue Template

When implementing a sprint task, create a parent issue with this structure:

```
Title: [Sprint Task Title from docs/sprint.md]

Description:
**Sprint Task Implementation**

[Copy task description from sprint.md verbatim]

**Acceptance Criteria:**
[Copy ALL acceptance criteria from sprint.md]

**Sprint:** [sprint-name]

**Implementation Tracking:** docs/a2a/[sprint-name]/reviewer.md

---

**Status Updates:**
- Todo: Not started
- In Progress: Implementation ongoing
- In Review: Awaiting senior lead review
- Done: Approved and complete
```

### Sub-Issue Template

For major components (>3 files or complex features), create sub-issues:

```
Title: [Component] [Component Name]

Description:
**Component:** [Name]

**Purpose:** [What this component does]

**Files to modify:**
- [List of files]

**Key Decisions:**
- [Decision 1]
- [Decision 2]

**Testing:**
- [Test approach]

**Parent Task:** [Parent issue URL]
```

---

## Commit Message Format

Use this format for commits related to Linear issues:

```
[LAB-XXX] Short description

Longer description if needed.

Related: https://linear.app/honeyjar/issue/LAB-XXX
```

---

## Discord Integration

This project does not currently have Discord source URLs for tasks.
When implementing features that originated from Discord feedback, include:

```markdown
**Source Discussion:** [Discord message](https://discord.com/channels/...)
```

---

## Workflow States

Linear workflow states for the Laboratory team:

| State | Description |
|-------|-------------|
| Todo | Not started |
| In Progress | Implementation ongoing |
| In Review | Awaiting review |
| Done | Completed |
| Canceled | No longer needed |

---

## Related Documents

- PRD: `docs/prd.md`
- SDD: `docs/sdd.md`
- Sprint Plan: `docs/sprint.md`
- Implementation Reports: `docs/a2a/sprint-N/reviewer.md`

---

## MCP Tools Available

The following Linear MCP tools are available for issue management:

- `mcp__linear__create_issue` - Create new issues
- `mcp__linear__update_issue` - Update existing issues
- `mcp__linear__create_comment` - Add comments to issues
- `mcp__linear__list_issues` - Query issues
- `mcp__linear__get_issue` - Get issue details
- `mcp__linear__list_issue_labels` - List available labels
- `mcp__linear__list_issue_statuses` - List workflow states
