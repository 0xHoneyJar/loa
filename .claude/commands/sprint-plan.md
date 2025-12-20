---
description: Launch the sprint planner agent to review PRD and SDD, then generate a comprehensive sprint plan
args: [background]
---

I'm launching the sprint-planner agent to create a detailed sprint plan based on your Product Requirements Document and Software Design Document.

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

     After setup is complete, run `/sprint-plan` again.
     ```
   - **STOP** - Do not proceed with sprint planning
3. If the marker file **exists**, proceed with the planning process

---

The agent will:
1. **Carefully review** both `loa-grimoire/prd.md` and `loa-grimoire/sdd.md` to understand requirements and architecture
2. **Analyze and plan** sprint breakdown, task prioritization, and implementation sequencing
3. **Clarify uncertainties** by asking you questions with specific proposals when anything is ambiguous
4. **Validate assumptions** about team capacity, sprint duration, priorities, and dependencies
5. **Generate sprint plan** only when fully satisfied with all answers and has no remaining doubts
6. **Save output** to `loa-grimoire/sprint.md`

The sprint planner will cover:
- Sprint structure and duration (2.5-day sprints or customized)
- Task breakdown with clear acceptance criteria
- Priority and sequencing of features
- Developer assignments and workload distribution
- Dependencies and blockers
- Testing and quality assurance requirements
- Sprint goals and success metrics
- Risk mitigation strategies

{{ if "background" in $ARGUMENTS }}
Running in background mode. Use `/tasks` to monitor progress.

<Task
  subagent_type="sprint-planner"
  prompt="You are tasked with creating a comprehensive sprint plan based on the Product Requirements Document at loa-grimoire/prd.md and the Software Design Document at loa-grimoire/sdd.md.

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

After setup is complete, run `/sprint-plan` again.
```

If the file EXISTS, proceed with the sprint planning process.

---

Your process:
1. Carefully read and analyze both loa-grimoire/prd.md and loa-grimoire/sdd.md in their entirety
2. Understand the product requirements, technical architecture, and implementation approach
3. Break down the work into sprints with specific, actionable tasks
4. For ANY uncertainties, ambiguities, or areas where clarification is needed:
   - Ask the user specific questions
   - Present 2-3 concrete proposals with pros/cons when multiple approaches are valid
   - Seek clarification on priorities, team size, sprint duration, MVP scope, etc.
   - Wait for their decision before proceeding
5. Validate all assumptions about:
   - Team capacity and available developers
   - Sprint duration (default is 2.5-day sprints, but confirm)
   - Feature prioritization and MVP scope
   - Technical dependencies and sequencing
   - Testing and QA requirements
6. Only when you are completely satisfied with all answers and have NO remaining doubts or uncertainties, proceed to write the sprint plan
7. Generate a detailed, comprehensive sprint plan
8. Save the final sprint plan to loa-grimoire/sprint.md

The sprint plan should include:
- Sprint Overview (goals, duration, team structure)
- Sprint Breakdown:
  - Sprint number and goals
  - Tasks with clear descriptions and acceptance criteria
  - Estimated effort/complexity
  - Developer assignments
  - Dependencies and prerequisites
  - Testing requirements
- MVP Definition and scope
- Feature prioritization rationale
- Risk assessment and mitigation
- Success metrics per sprint
- Dependencies and blockers
- Buffer time for unknowns

Format each task clearly with:
- Task ID and title
- Detailed description
- Acceptance criteria (specific, measurable)
- Estimated effort
- Assigned to (developer role or name)
- Dependencies
- Testing requirements

## Analytics Update (Phase Final)

After successfully saving the sprint plan to loa-grimoire/sprint.md, update analytics.

**First, check user type**:
```bash
USER_TYPE=$(cat .loa-setup-complete 2>/dev/null | grep -o '\"user_type\": *\"[^\"]*\"' | cut -d'\"' -f4)
```

**If USER_TYPE is \"oss\"**: Skip analytics update entirely and complete the sprint planning process.

**If USER_TYPE is \"thj\"**: Proceed with analytics update:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.sprint_planning.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")
jq --arg ts \"$TIMESTAMP\" '
  .phases.sprint_planning.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the sprint planning process successfully.

Remember: Ask questions and seek clarity BEFORE writing. Only generate the sprint plan when you have complete confidence in the breakdown and sequencing."
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

After setup is complete, run `/sprint-plan` again.
```

If the file EXISTS, proceed with Phase 0.

---

## Phase 0: Begin Sprint Planning

You are tasked with creating a comprehensive sprint plan based on the Product Requirements Document at loa-grimoire/prd.md and the Software Design Document at loa-grimoire/sdd.md.

Your process:
1. Carefully read and analyze both loa-grimoire/prd.md and loa-grimoire/sdd.md in their entirety
2. Understand the product requirements, technical architecture, and implementation approach
3. Break down the work into sprints with specific, actionable tasks
4. For ANY uncertainties, ambiguities, or areas where clarification is needed:
   - Ask the user specific questions
   - Present 2-3 concrete proposals with pros/cons when multiple approaches are valid
   - Seek clarification on priorities, team size, sprint duration, MVP scope, etc.
   - Wait for their decision before proceeding
5. Validate all assumptions about:
   - Team capacity and available developers
   - Sprint duration (default is 2.5-day sprints, but confirm)
   - Feature prioritization and MVP scope
   - Technical dependencies and sequencing
   - Testing and QA requirements
6. Only when you are completely satisfied with all answers and have NO remaining doubts or uncertainties, proceed to write the sprint plan
7. Generate a detailed, comprehensive sprint plan
8. Save the final sprint plan to loa-grimoire/sprint.md

The sprint plan should include:
- Sprint Overview (goals, duration, team structure)
- Sprint Breakdown:
  - Sprint number and goals
  - Tasks with clear descriptions and acceptance criteria
  - Estimated effort/complexity
  - Developer assignments
  - Dependencies and prerequisites
  - Testing requirements
- MVP Definition and scope
- Feature prioritization rationale
- Risk assessment and mitigation
- Success metrics per sprint
- Dependencies and blockers
- Buffer time for unknowns

Format each task clearly with:
- Task ID and title
- Detailed description
- Acceptance criteria (specific, measurable)
- Estimated effort
- Assigned to (developer role or name)
- Dependencies
- Testing requirements

---

## Phase Final: Analytics Update

After successfully saving the sprint plan to loa-grimoire/sprint.md, update analytics.

**First, check user type**:
```bash
cat .loa-setup-complete 2>/dev/null | grep -o '"user_type": *"[^"]*"' | cut -d'"' -f4
```

**If user_type is "oss"**: Skip analytics update entirely and complete the sprint planning process.

**If user_type is "thj"**: Proceed with analytics update:

1. Read and validate loa-grimoire/analytics/usage.json
2. Update the following fields:
   - Set `phases.sprint_planning.completed_at` to current ISO timestamp
   - Increment `totals.phases_completed` by 1
   - Increment `totals.commands_executed` by 1
3. Regenerate loa-grimoire/analytics/summary.md with updated data

Use safe jq patterns with --arg for variable injection:
```bash
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg ts "$TIMESTAMP" '
  .phases.sprint_planning.completed_at = $ts |
  .totals.phases_completed += 1 |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Then regenerate the summary by reading usage.json and updating summary.md with current values.

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the sprint planning process successfully.

Remember: Ask questions and seek clarity BEFORE writing. Only generate the sprint plan when you have complete confidence in the breakdown and sequencing.
{{ endif }}
