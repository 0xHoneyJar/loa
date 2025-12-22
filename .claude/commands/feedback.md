---
name: "feedback"
version: "1.1.0"
description: |
  Submit developer feedback about Loa experience with auto-attached analytics.
  Posts to Linear with project metrics. THJ developers only.

command_type: "survey"

arguments: []

integrations:
  required:
    - name: "linear"
      scopes: [issues, projects]
      error: "Linear integration required for /feedback. Run /config to set up, or open a GitHub issue instead."

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "content_contains"
    path: ".loa-setup-complete"
    pattern: '"user_type":\\s*"thj"'
    error: |
      The /feedback command is only available for THJ team members.

      For issues or feature requests, please open a GitHub issue at:
      https://github.com/0xHoneyJar/loa/issues

  - check: "script"
    script: ".claude/scripts/validate-mcp.sh linear"
    error: |
      Linear MCP is not configured. The /feedback command requires Linear to submit feedback.

      To configure Linear:
        .claude/scripts/mcp-registry.sh setup linear

      Or open a GitHub issue instead:
        https://github.com/0xHoneyJar/loa/issues

outputs:
  - path: "Linear issue/comment"
    type: "external"
    description: "Feedback posted to Linear"
  - path: "loa-grimoire/analytics/pending-feedback.json"
    type: "file"
    description: "Safety backup if submission fails"

mode:
  default: "foreground"
  allow_background: false
---

# Feedback

## Purpose

Collect developer feedback on the Loa experience and post to Linear with attached analytics. Helps improve the framework through structured user input.

## Invocation

```
/feedback
```

## Prerequisites

- Setup completed (`.loa-setup-complete` exists)
- User type is `thj` (THJ team member)

## Workflow

### Phase 0: Check for Pending Feedback

Check if there's pending feedback from a previous failed submission. Offer to submit pending feedback or start fresh.

### Phase 1: Survey

Collect responses to 4 questions with progress indicators:

1. **What would you change about Loa?** (free text)
2. **What did you love about using Loa?** (free text)
3. **Rate this build vs other approaches** (1-5 scale)
4. **How comfortable was the process?** (A-E multiple choice)

### Phase 2: Prepare Submission

- Load analytics from `loa-grimoire/analytics/usage.json`
- Gather project context (name, developer info)
- Save pending feedback as safety backup

### Phase 3: Linear Submission

- Search for existing feedback issue in "Loa Feedback" project
- Create new issue or add comment to existing one
- Include full analytics in collapsible details block

### Phase 4: Update Analytics

- Record submission in `feedback_submissions` array
- Delete pending feedback file
- Regenerate summary

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| None | | |

## Outputs

| Path | Description |
|------|-------------|
| Linear issue | Feedback posted to "Loa Feedback" project |
| `loa-grimoire/analytics/pending-feedback.json` | Backup if submission fails |

## Survey Questions

| # | Question | Type |
|---|----------|------|
| 1 | What's one thing you would change? | Free text |
| 2 | What's one thing you loved? | Free text |
| 3 | How does this build compare? | 1-5 rating |
| 4 | How comfortable was the process? | A-E choice |

## Linear Issue Format

```markdown
## Feedback Submission - {timestamp}

**Developer**: {name} ({email})
**Project**: {project_name}

### Survey Responses
1. **What would you change?** {response}
2. **What did you love?** {response}
3. **Rating vs other builds**: {rating}/5
4. **Process comfort level**: {choice}

### Analytics Summary
| Metric | Value |
|--------|-------|
| Framework Version | {version} |
| Phases Completed | {count} |
| Sprints Completed | {count} |

<details>
<summary>Full Analytics JSON</summary>
{analytics_json}
</details>
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Setup not completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "Only available for THJ" | User type is `oss` | Open GitHub issue instead |
| "Linear submission failed" | MCP error | Feedback saved to pending file |

## OSS Users

For issues or feature requests, open a GitHub issue at:
https://github.com/0xHoneyJar/loa/issues
