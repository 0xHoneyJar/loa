---
description: Launch the PRD architect agent to define goals, requirements, scope, and generate a Product Requirements Document (PRD)
args: [background]
---

I'm launching the prd-architect agent to help you create a comprehensive Product Requirements Document.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

## Pre-flight Check: Setup Verification

Before proceeding, verify that Loa setup is complete:

1. Check if `.loa-setup-complete` marker file exists in the project root
2. If the marker file **does NOT exist**:
   - Display this message:
     ```
     Loa setup has not been completed for this project.

     Please run `/setup` first to:
     - Configure MCP integrations
     - Initialize project analytics

     After setup is complete, run `/plan-and-analyze` again.
     ```
   - **STOP** - Do not proceed with PRD creation
3. If the marker file **exists**, proceed with the PRD process

---

The agent will guide you through a structured discovery process to:
1. **Define goals** - Clarify what you want to achieve and why
2. **Define requirements** - Identify functional and non-functional requirements
3. **Identify scope** - Determine what's in scope, out of scope, and prioritize features
4. **Research and refine** - Gather context, ask clarifying questions, and validate assumptions
5. **Generate PRD** - Create a comprehensive document at `loa-grimoire/prd.md`

The PRD architect will ask targeted questions across these phases:
- Problem & Vision
- Goals & Success Metrics
- User & Stakeholder Context
- Functional Requirements
- Technical & Non-Functional Requirements
- Scope & Prioritization
- Risks & Dependencies

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="prd-architect"
  prompt="Help the user create a comprehensive Product Requirements Document (PRD). Guide them through structured discovery to define goals, requirements, and scope. Ask targeted questions across all phases: Problem & Vision, Goals & Success Metrics, User & Stakeholder Context, Functional Requirements, Technical & Non-Functional Requirements, Scope & Prioritization, and Risks & Dependencies. Once you have complete information, generate a detailed PRD and save it to loa-grimoire/prd.md.

## CRITICAL: Setup Check (Phase -1)

BEFORE doing anything else, check if `.loa-setup-complete` marker file exists:

```bash
ls -la .loa-setup-complete 2>/dev/null
```

If the file does NOT exist, display this message and STOP:
```
Loa setup has not been completed for this project.

Please run `/setup` first to:
- Configure MCP integrations
- Initialize project analytics

After setup is complete, run `/plan-and-analyze` again.
```

If the file EXISTS, proceed with the PRD process.

## Analytics Update (Phase Final)

After successfully saving the PRD to loa-grimoire/prd.md, update analytics.

**First, check user type**:
```bash
USER_TYPE=$(cat .loa-setup-complete 2>/dev/null | grep -o '\"user_type\": *\"[^\"]*\"' | cut -d'\"' -f4)
```

**If USER_TYPE is \"oss\"**: Skip analytics update entirely and complete the PRD process.

**If USER_TYPE is \"thj\"**: Proceed with analytics update:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.prd.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")
jq --arg ts \"$TIMESTAMP\" '
  .phases.prd.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the PRD process successfully."
/>
{{ else }}
## Phase -1: Setup Verification

First, check if `.loa-setup-complete` marker file exists:

```bash
ls -la .loa-setup-complete 2>/dev/null
```

If the file does NOT exist, display this message and STOP:
```
Loa setup has not been completed for this project.

Please run `/setup` first to:
- Configure MCP integrations
- Initialize project analytics

After setup is complete, run `/plan-and-analyze` again.
```

If the file EXISTS, proceed with Phase 0.

---

## Phase 0: Begin Discovery

Help the user create a comprehensive Product Requirements Document (PRD). Guide them through structured discovery to define goals, requirements, and scope. Ask targeted questions across all phases: Problem & Vision, Goals & Success Metrics, User & Stakeholder Context, Functional Requirements, Technical & Non-Functional Requirements, Scope & Prioritization, and Risks & Dependencies. Once you have complete information, generate a detailed PRD and save it to loa-grimoire/prd.md.

---

## Phase Final: Analytics Update

After successfully saving the PRD to loa-grimoire/prd.md, update analytics.

**First, check user type**:
```bash
cat .loa-setup-complete 2>/dev/null | grep -o '"user_type": *"[^"]*"' | cut -d'"' -f4
```

**If user_type is "oss"**: Skip analytics update entirely and complete the PRD process.

**If user_type is "thj"**: Proceed with analytics update:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.prd.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" '
  .phases.prd.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Then regenerate the summary by reading usage.json and updating summary.md with current values.

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the PRD process successfully.
{{ endif }}
