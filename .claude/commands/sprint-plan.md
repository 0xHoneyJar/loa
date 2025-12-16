---
description: Launch the sprint planner agent to review PRD and SDD, then generate a comprehensive sprint plan
args: [background]
---

I'm launching the sprint-planner agent to create a detailed sprint plan based on your Product Requirements Document and Software Design Document.

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

The agent will:
1. **Carefully review** both `docs/prd.md` and `docs/sdd.md` to understand requirements and architecture
2. **Analyze and plan** sprint breakdown, task prioritization, and implementation sequencing
3. **Clarify uncertainties** by asking you questions with specific proposals when anything is ambiguous
4. **Validate assumptions** about team capacity, sprint duration, priorities, and dependencies
5. **Generate sprint plan** only when fully satisfied with all answers and has no remaining doubts
6. **Save output** to `docs/sprint.md`

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
  prompt="You are tasked with creating a comprehensive sprint plan based on the Product Requirements Document at docs/prd.md and the Software Design Document at docs/sdd.md.

Your process:
1. Carefully read and analyze both docs/prd.md and docs/sdd.md in their entirety
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
8. Save the final sprint plan to docs/sprint.md

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

Remember: Ask questions and seek clarity BEFORE writing. Only generate the sprint plan when you have complete confidence in the breakdown and sequencing."
/>
{{ else }}
Let me begin the sprint planning process.

You are tasked with creating a comprehensive sprint plan based on the Product Requirements Document at docs/prd.md and the Software Design Document at docs/sdd.md.

Your process:
1. Carefully read and analyze both docs/prd.md and docs/sdd.md in their entirety
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
8. Save the final sprint plan to docs/sprint.md

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

Remember: Ask questions and seek clarity BEFORE writing. Only generate the sprint plan when you have complete confidence in the breakdown and sequencing.
{{ endif }}
