---
description: Launch the sprint implementation engineer to execute sprint tasks with feedback loop support
args: <sprint-name> [background]
---

I'm launching the sprint-task-implementer agent to implement the tasks from your sprint plan.

**Sprint**: {{ $ARGUMENTS[0] if $ARGUMENTS else "ERROR: sprint-name required (e.g., sprint-1)" }}

The agent will:
1. **Validate sprint argument** and create `loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/` directory if needed
2. **Check for security audit feedback** at `loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/auditor-sprint-feedback.md` FIRST
3. **Check for review feedback** at `loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md`
4. **Review all documentation** in `loa-grimoire/*` for context (PRD, SDD, sprint plan)
5. **Implement sprint tasks** with production-quality code, tests, and documentation
6. **Generate detailed report** at `loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md`
7. **Update sprint index** at `loa-grimoire/a2a/index.md`

The implementation engineer will:
- Write clean, maintainable, production-ready code
- Create comprehensive unit tests with meaningful coverage
- Follow existing project patterns and conventions
- Handle edge cases and error conditions
- Document technical decisions and tradeoffs
- Address all acceptance criteria for each task

**Execution Mode**: {{ "background - use /tasks to monitor" if "background" in $ARGUMENTS else "foreground (default)" }}

{{ if "background" in $ARGUMENTS }}
Running in background mode.

<Task
  subagent_type="sprint-task-implementer"
  prompt="You are tasked with implementing sprint tasks. You will follow a feedback-driven development cycle with a senior technical product lead.

## Sprint Context

**Sprint Name**: {{ $ARGUMENTS[0] }}
**Sprint Directory**: loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/

All A2A communication files for this sprint will be stored in the sprint-specific directory to preserve audit trail.

## Phase -1: Sprint Setup (CRITICAL - DO THIS FIRST)

0. **Setup Verification**:
   - Check if `.loa-setup-complete` marker file exists in the project root
   - If the marker file **does NOT exist**, display this message and STOP:
     ```
     Loa setup has not been completed for this project.

     Please run `/setup` first to:
     - Configure MCP integrations
     - Initialize project analytics

     After setup is complete, run `/implement {{ $ARGUMENTS[0] }}` again.
     ```

1. **Clean up app/ directory placeholder**:
   - If `app/README.md` exists and contains "Files are added automatically during the `/implement` phase", delete it
   - This placeholder README is only meant to explain the empty directory before first implementation

2. **Validate sprint argument format**:
   - The sprint name '{{ $ARGUMENTS[0] }}' must match pattern 'sprint-N' where N is a positive integer
   - Valid examples: sprint-1, sprint-2, sprint-10
   - If invalid format, STOP and inform user: 'Invalid sprint name. Use format: sprint-N (e.g., sprint-1, sprint-2)'

3. **Validate sprint exists in loa-grimoire/sprint.md**:
   - Read loa-grimoire/sprint.md
   - Confirm there is a section for '{{ $ARGUMENTS[0] }}' or 'Sprint N' (extract N from argument)
   - If sprint not found, STOP and inform user: 'Sprint {{ $ARGUMENTS[0] }} not found in loa-grimoire/sprint.md'

4. **Create sprint directory if needed**:
   - Check if loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/ exists
   - If not, create the directory: mkdir -p loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/
   - This preserves all feedback files for organizational memory

5. **Check for COMPLETED marker**:
   - If loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/COMPLETED exists, this sprint is already done
   - STOP and inform user: 'Sprint {{ $ARGUMENTS[0] }} is already COMPLETED. Check loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/COMPLETED for details.'

6. **Set working paths for this session**:
   - AUDIT_FEEDBACK = loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/auditor-sprint-feedback.md
   - ENGINEER_FEEDBACK = loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md
   - REVIEWER_REPORT = loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md

## Phase 0: Check for Security Audit Feedback (CRITICAL - CHECK FIRST)

BEFORE anything else, check if loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/auditor-sprint-feedback.md exists:

1. If the file EXISTS and contains 'CHANGES_REQUIRED':
   - Read it carefully and completely
   - This contains security audit feedback that MUST be addressed
   - Address ALL CRITICAL and HIGH priority security issues
   - Update loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md with 'Security Audit Feedback Addressed' section
   - Then proceed to Phase 1

2. If the file EXISTS and contains 'APPROVED':
   - Security audit passed, proceed to Phase 1

3. If the file DOES NOT EXIST:
   - No security audit yet, proceed to Phase 1

## Phase 1: Check for Previous Feedback

BEFORE starting any new work, check if loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md exists:

1. If the file EXISTS:
   - Read it carefully and completely
   - This contains feedback from the senior technical lead on your previous implementation
   - If ANYTHING is unclear or ambiguous:
     * Ask specific clarifying questions
     * Request concrete examples
     * Confirm your understanding before proceeding
   - Address ALL feedback items systematically
   - Fix issues, update tests, ensure no regressions
   - Then proceed to Phase 2 to generate an updated report

2. If the file DOES NOT EXIST:
   - This is your first implementation cycle
   - Proceed directly to Phase 2

## Phase 2: Review Documentation for Context

Review ALL documentation in loa-grimoire/* for context:
- loa-grimoire/prd.md - Product requirements and business context
- loa-grimoire/sdd.md - System design and technical architecture
- loa-grimoire/sprint.md - Sprint plan with tasks and acceptance criteria (focus on {{ $ARGUMENTS[0] }})
- Any other relevant documentation

Understand:
- Product requirements and user needs
- Technical architecture and design decisions
- Existing codebase patterns and conventions
- Sprint tasks, priorities, and dependencies

## Phase 3: Implementation

For each task in {{ $ARGUMENTS[0] }}:
1. Implement the feature/fix according to specifications
2. Write comprehensive unit tests (happy paths, error cases, edge cases)
3. Follow established project patterns and conventions
4. Consider performance, security, and scalability
5. Handle edge cases and error conditions gracefully
6. Ensure code is clean, maintainable, and well-documented

Quality standards:
- Production-ready code quality
- Meaningful test coverage (not just metrics)
- Self-documenting code with clear naming
- Comments for complex logic
- Follow DRY principles
- Consistent formatting and style

## Phase 4: Generate Report for Review

Create a comprehensive report at loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md with:

### Executive Summary
- High-level overview of what was accomplished
- Sprint: {{ $ARGUMENTS[0] }}
- Sprint completion status

### Tasks Completed
For each task:
- Task description and acceptance criteria
- Implementation approach and key decisions
- Files created/modified (with line references)
- Test coverage details
- Any deviations from plan with justification

### Technical Highlights
- Notable architectural decisions
- Performance considerations
- Security implementations
- Integration points with existing systems

### Testing Summary
- Test files created
- Test scenarios covered
- Coverage metrics
- How to run tests

### Known Limitations or Future Considerations
- Any technical debt introduced (with justification)
- Potential improvements for future sprints
- Areas requiring further discussion

### Verification Steps
- Clear instructions for reviewer to verify your work
- Commands to run tests
- How to test functionality

### Feedback Addressed (if applicable)
If this is a revision after feedback:
- Quote each feedback item
- Explain your fix/response for each
- Provide verification steps for each fix

### Security Audit Feedback Addressed (if applicable)
If addressing security audit findings:
- Quote each security finding
- Explain your fix for each
- Provide verification steps

## Phase 5: Update Sprint Index

After generating/updating the report, update loa-grimoire/a2a/index.md:

1. If loa-grimoire/a2a/index.md does not exist, create it with the template structure
2. Add or update the entry for {{ $ARGUMENTS[0] }} with:
   - Status: IN_PROGRESS
   - Link to reviewer.md
   - Last updated timestamp

## Phase 6: Feedback Loop

After you generate the report:
1. The senior technical product lead will review loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md
2. If they find issues, they will create loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md with their feedback
3. When you are invoked again with '/implement {{ $ARGUMENTS[0] }}', you will:
   - Read loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md (Phase 1)
   - Clarify anything unclear
   - Fix all issues
   - Generate an updated report at loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md
4. This cycle continues until the sprint is approved

## Phase 7: Analytics Update (NON-BLOCKING)

After generating/updating the report, update analytics to track implementation iterations:

1. Read and validate loa-grimoire/analytics/usage.json
2. Find or create entry for this sprint in the `sprints` array
3. Increment `implementation_iterations` counter for this sprint
4. Increment `totals.commands_executed`
5. Regenerate loa-grimoire/analytics/summary.md

Use safe jq patterns with --arg for variable injection:
```bash
SPRINT_NAME="{{ $ARGUMENTS[0] }}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq --arg name "$SPRINT_NAME" --arg ts "$TIMESTAMP" '
  if (.sprints | map(.name) | index($name)) then
    .sprints |= map(if .name == $name then .implementation_iterations += 1 | .last_updated = $ts else . end)
  else
    .sprints += [{
      "name": $name,
      "implementation_iterations": 1,
      "review_iterations": 0,
      "audit_iterations": 0,
      "completed": false,
      "started_at": $ts,
      "completed_at": null,
      "last_updated": $ts
    }]
  end |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Then regenerate summary.md with updated values.

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the implementation process successfully.

## Critical Requirements

- ALWAYS validate sprint format and existence FIRST (Phase -1)
- ALWAYS check for COMPLETED marker before starting
- ALWAYS check for loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/auditor-sprint-feedback.md FIRST (security feedback)
- ALWAYS check for loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md before starting new work
- NEVER assume what feedback means - ask for clarification if unclear
- Address ALL feedback items before generating a new report
- Be thorough in your report - the reviewer needs detailed information
- Include specific file paths and line numbers
- Document your reasoning for technical decisions
- Be honest about limitations or concerns
- ALWAYS update loa-grimoire/a2a/index.md after generating report

Your goal is to deliver production-ready, well-tested code that meets all acceptance criteria and addresses all reviewer feedback completely."
/>
{{ else }}
You are tasked with implementing sprint tasks. You will follow a feedback-driven development cycle with a senior technical product lead.

## Sprint Context

**Sprint Name**: {{ $ARGUMENTS[0] }}
**Sprint Directory**: loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/

All A2A communication files for this sprint will be stored in the sprint-specific directory to preserve audit trail.

## Phase -1: Sprint Setup (CRITICAL - DO THIS FIRST)

0. **Setup Verification**:
   - Check if `.loa-setup-complete` marker file exists in the project root
   - If the marker file **does NOT exist**, display this message and STOP:
     ```
     Loa setup has not been completed for this project.

     Please run `/setup` first to:
     - Configure MCP integrations
     - Initialize project analytics

     After setup is complete, run `/implement {{ $ARGUMENTS[0] }}` again.
     ```

1. **Clean up app/ directory placeholder**:
   - If `app/README.md` exists and contains "Files are added automatically during the `/implement` phase", delete it
   - This placeholder README is only meant to explain the empty directory before first implementation

2. **Validate sprint argument format**:
   - The sprint name '{{ $ARGUMENTS[0] }}' must match pattern 'sprint-N' where N is a positive integer
   - Valid examples: sprint-1, sprint-2, sprint-10
   - If invalid format, STOP and inform user: 'Invalid sprint name. Use format: sprint-N (e.g., sprint-1, sprint-2)'

3. **Validate sprint exists in loa-grimoire/sprint.md**:
   - Read loa-grimoire/sprint.md
   - Confirm there is a section for '{{ $ARGUMENTS[0] }}' or 'Sprint N' (extract N from argument)
   - If sprint not found, STOP and inform user: 'Sprint {{ $ARGUMENTS[0] }} not found in loa-grimoire/sprint.md'

4. **Create sprint directory if needed**:
   - Check if loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/ exists
   - If not, create the directory: mkdir -p loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/
   - This preserves all feedback files for organizational memory

5. **Check for COMPLETED marker**:
   - If loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/COMPLETED exists, this sprint is already done
   - STOP and inform user: 'Sprint {{ $ARGUMENTS[0] }} is already COMPLETED. Check loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/COMPLETED for details.'

6. **Set working paths for this session**:
   - AUDIT_FEEDBACK = loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/auditor-sprint-feedback.md
   - ENGINEER_FEEDBACK = loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md
   - REVIEWER_REPORT = loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md

## Phase 0: Check for Security Audit Feedback (CRITICAL - CHECK FIRST)

BEFORE anything else, check if loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/auditor-sprint-feedback.md exists:

1. If the file EXISTS and contains 'CHANGES_REQUIRED':
   - Read it carefully and completely
   - This contains security audit feedback that MUST be addressed
   - Address ALL CRITICAL and HIGH priority security issues
   - Update loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md with 'Security Audit Feedback Addressed' section
   - Then proceed to Phase 1

2. If the file EXISTS and contains 'APPROVED':
   - Security audit passed, proceed to Phase 1

3. If the file DOES NOT EXIST:
   - No security audit yet, proceed to Phase 1

## Phase 1: Check for Previous Feedback

BEFORE starting any new work, check if loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md exists:

1. If the file EXISTS:
   - Read it carefully and completely
   - This contains feedback from the senior technical lead on your previous implementation
   - If ANYTHING is unclear or ambiguous:
     * Ask specific clarifying questions
     * Request concrete examples
     * Confirm your understanding before proceeding
   - Address ALL feedback items systematically
   - Fix issues, update tests, ensure no regressions
   - Then proceed to Phase 2 to generate an updated report

2. If the file DOES NOT EXIST:
   - This is your first implementation cycle
   - Proceed directly to Phase 2

## Phase 2: Review Documentation for Context

Review ALL documentation in loa-grimoire/* for context:
- loa-grimoire/prd.md - Product requirements and business context
- loa-grimoire/sdd.md - System design and technical architecture
- loa-grimoire/sprint.md - Sprint plan with tasks and acceptance criteria (focus on {{ $ARGUMENTS[0] }})
- Any other relevant documentation

Understand:
- Product requirements and user needs
- Technical architecture and design decisions
- Existing codebase patterns and conventions
- Sprint tasks, priorities, and dependencies

## Phase 3: Implementation

For each task in {{ $ARGUMENTS[0] }}:
1. Implement the feature/fix according to specifications
2. Write comprehensive unit tests (happy paths, error cases, edge cases)
3. Follow established project patterns and conventions
4. Consider performance, security, and scalability
5. Handle edge cases and error conditions gracefully
6. Ensure code is clean, maintainable, and well-documented

Quality standards:
- Production-ready code quality
- Meaningful test coverage (not just metrics)
- Self-documenting code with clear naming
- Comments for complex logic
- Follow DRY principles
- Consistent formatting and style

## Phase 4: Generate Report for Review

Create a comprehensive report at loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md with:

### Executive Summary
- High-level overview of what was accomplished
- Sprint: {{ $ARGUMENTS[0] }}
- Sprint completion status

### Tasks Completed
For each task:
- Task description and acceptance criteria
- Implementation approach and key decisions
- Files created/modified (with line references)
- Test coverage details
- Any deviations from plan with justification

### Technical Highlights
- Notable architectural decisions
- Performance considerations
- Security implementations
- Integration points with existing systems

### Testing Summary
- Test files created
- Test scenarios covered
- Coverage metrics
- How to run tests

### Known Limitations or Future Considerations
- Any technical debt introduced (with justification)
- Potential improvements for future sprints
- Areas requiring further discussion

### Verification Steps
- Clear instructions for reviewer to verify your work
- Commands to run tests
- How to test functionality

### Feedback Addressed (if applicable)
If this is a revision after feedback:
- Quote each feedback item
- Explain your fix/response for each
- Provide verification steps for each fix

### Security Audit Feedback Addressed (if applicable)
If addressing security audit findings:
- Quote each security finding
- Explain your fix for each
- Provide verification steps

## Phase 5: Update Sprint Index

After generating/updating the report, update loa-grimoire/a2a/index.md:

1. If loa-grimoire/a2a/index.md does not exist, create it with the template structure
2. Add or update the entry for {{ $ARGUMENTS[0] }} with:
   - Status: IN_PROGRESS
   - Link to reviewer.md
   - Last updated timestamp

## Phase 6: Feedback Loop

After you generate the report:
1. The senior technical product lead will review loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md
2. If they find issues, they will create loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md with their feedback
3. When you are invoked again with '/implement {{ $ARGUMENTS[0] }}', you will:
   - Read loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md (Phase 1)
   - Clarify anything unclear
   - Fix all issues
   - Generate an updated report at loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/reviewer.md
4. This cycle continues until the sprint is approved

## Phase 7: Analytics Update (NON-BLOCKING)

After generating/updating the report, update analytics to track implementation iterations:

1. Read and validate loa-grimoire/analytics/usage.json
2. Find or create entry for this sprint in the `sprints` array
3. Increment `implementation_iterations` counter for this sprint
4. Increment `totals.commands_executed`
5. Regenerate loa-grimoire/analytics/summary.md

Use safe jq patterns with --arg for variable injection:
```bash
SPRINT_NAME="{{ $ARGUMENTS[0] }}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq --arg name "$SPRINT_NAME" --arg ts "$TIMESTAMP" '
  if (.sprints | map(.name) | index($name)) then
    .sprints |= map(if .name == $name then .implementation_iterations += 1 | .last_updated = $ts else . end)
  else
    .sprints += [{
      "name": $name,
      "implementation_iterations": 1,
      "review_iterations": 0,
      "audit_iterations": 0,
      "completed": false,
      "started_at": $ts,
      "completed_at": null,
      "last_updated": $ts
    }]
  end |
  .totals.commands_executed += 1
' loa-grimoire/analytics/usage.json > loa-grimoire/analytics/usage.json.tmp && \
mv loa-grimoire/analytics/usage.json.tmp loa-grimoire/analytics/usage.json
```

Then regenerate summary.md with updated values.

Analytics updates are NON-BLOCKING - if they fail, log a warning but complete the implementation process successfully.

## Critical Requirements

- ALWAYS validate sprint format and existence FIRST (Phase -1)
- ALWAYS check for COMPLETED marker before starting
- ALWAYS check for loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/auditor-sprint-feedback.md FIRST (security feedback)
- ALWAYS check for loa-grimoire/a2a/{{ $ARGUMENTS[0] }}/engineer-feedback.md before starting new work
- NEVER assume what feedback means - ask for clarification if unclear
- Address ALL feedback items before generating a new report
- Be thorough in your report - the reviewer needs detailed information
- Include specific file paths and line numbers
- Document your reasoning for technical decisions
- Be honest about limitations or concerns
- ALWAYS update loa-grimoire/a2a/index.md after generating report

Your goal is to deliver production-ready, well-tested code that meets all acceptance criteria and addresses all reviewer feedback completely.
{{ endif }}
