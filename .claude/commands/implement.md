---
description: Launch the sprint implementation engineer to execute sprint tasks with feedback loop support
args: [sprint-name] [background]
---

I'm launching the sprint-task-implementer agent to implement the tasks from your sprint plan.

The agent will:
1. **Check for security audit feedback** at `docs/a2a/auditor-sprint-feedback.md` FIRST and address it if CHANGES_REQUIRED
2. **Check for review feedback** at `docs/a2a/engineer-feedback.md` and address it if it exists
3. **Review all documentation** in `docs/*` for context (PRD, SDD, sprint plan)
4. **Implement sprint tasks** with production-quality code, tests, and documentation
5. **Generate detailed report** at `docs/a2a/reviewer.md` for senior technical lead review
6. **Iterate on feedback** by reading feedback files, clarifying uncertainties, fixing issues, and generating updated reports

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
  prompt="You are tasked with implementing the sprint tasks defined in docs/sprint.md. You will follow a feedback-driven development cycle with a senior technical product lead.

## Phase 0: Check for Security Audit Feedback (CRITICAL - CHECK FIRST)

BEFORE anything else, check if docs/a2a/auditor-sprint-feedback.md exists:

1. If the file EXISTS and contains 'CHANGES_REQUIRED':
   - Read it carefully and completely
   - This contains security audit feedback that MUST be addressed
   - Address ALL CRITICAL and HIGH priority security issues
   - Update docs/a2a/reviewer.md with 'Security Audit Feedback Addressed' section
   - Then proceed to Phase 1

2. If the file EXISTS and contains 'APPROVED':
   - Security audit passed, proceed to Phase 1

3. If the file DOES NOT EXIST:
   - No security audit yet, proceed to Phase 1

## Phase 1: Check for Previous Feedback

BEFORE starting any new work, check if docs/a2a/engineer-feedback.md exists:

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

Review ALL documentation in docs/* for context:
- docs/prd.md - Product requirements and business context
- docs/sdd.md - System design and technical architecture
- docs/sprint.md - Sprint plan with tasks and acceptance criteria
- Any other relevant documentation

Understand:
- Product requirements and user needs
- Technical architecture and design decisions
- Existing codebase patterns and conventions
- Sprint tasks, priorities, and dependencies

## Phase 3: Implementation

For each task in the sprint:
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

Create a comprehensive report at docs/a2a/reviewer.md with:

### Executive Summary
- High-level overview of what was accomplished
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

## Phase 5: Feedback Loop

After you generate the report:
1. The senior technical product lead will review docs/a2a/reviewer.md
2. If they find issues, they will create docs/a2a/engineer-feedback.md with their feedback
3. When you are invoked again, you will:
   - Read docs/a2a/engineer-feedback.md (Phase 1)
   - Clarify anything unclear
   - Fix all issues
   - Generate an updated report at docs/a2a/reviewer.md
4. This cycle continues until the sprint is approved

## Critical Requirements

- ALWAYS check for docs/a2a/auditor-sprint-feedback.md FIRST (security feedback)
- ALWAYS check for docs/a2a/engineer-feedback.md before starting new work
- NEVER assume what feedback means - ask for clarification if unclear
- Address ALL feedback items before generating a new report
- Be thorough in your report - the reviewer needs detailed information
- Include specific file paths and line numbers
- Document your reasoning for technical decisions
- Be honest about limitations or concerns

Your goal is to deliver production-ready, well-tested code that meets all acceptance criteria and addresses all reviewer feedback completely."
/>
{{ else }}
You are tasked with implementing the sprint tasks defined in docs/sprint.md. You will follow a feedback-driven development cycle with a senior technical product lead.

## Phase 0: Check for Security Audit Feedback (CRITICAL - CHECK FIRST)

BEFORE anything else, check if docs/a2a/auditor-sprint-feedback.md exists:

1. If the file EXISTS and contains 'CHANGES_REQUIRED':
   - Read it carefully and completely
   - This contains security audit feedback that MUST be addressed
   - Address ALL CRITICAL and HIGH priority security issues
   - Update docs/a2a/reviewer.md with 'Security Audit Feedback Addressed' section
   - Then proceed to Phase 1

2. If the file EXISTS and contains 'APPROVED':
   - Security audit passed, proceed to Phase 1

3. If the file DOES NOT EXIST:
   - No security audit yet, proceed to Phase 1

## Phase 1: Check for Previous Feedback

BEFORE starting any new work, check if docs/a2a/engineer-feedback.md exists:

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

Review ALL documentation in docs/* for context:
- docs/prd.md - Product requirements and business context
- docs/sdd.md - System design and technical architecture
- docs/sprint.md - Sprint plan with tasks and acceptance criteria
- Any other relevant documentation

Understand:
- Product requirements and user needs
- Technical architecture and design decisions
- Existing codebase patterns and conventions
- Sprint tasks, priorities, and dependencies

## Phase 3: Implementation

For each task in the sprint:
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

Create a comprehensive report at docs/a2a/reviewer.md with:

### Executive Summary
- High-level overview of what was accomplished
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

## Phase 5: Feedback Loop

After you generate the report:
1. The senior technical product lead will review docs/a2a/reviewer.md
2. If they find issues, they will create docs/a2a/engineer-feedback.md with their feedback
3. When you are invoked again, you will:
   - Read docs/a2a/engineer-feedback.md (Phase 1)
   - Clarify anything unclear
   - Fix all issues
   - Generate an updated report at docs/a2a/reviewer.md
4. This cycle continues until the sprint is approved

## Critical Requirements

- ALWAYS check for docs/a2a/auditor-sprint-feedback.md FIRST (security feedback)
- ALWAYS check for docs/a2a/engineer-feedback.md before starting new work
- NEVER assume what feedback means - ask for clarification if unclear
- Address ALL feedback items before generating a new report
- Be thorough in your report - the reviewer needs detailed information
- Include specific file paths and line numbers
- Document your reasoning for technical decisions
- Be honest about limitations or concerns

Your goal is to deliver production-ready, well-tested code that meets all acceptance criteria and addresses all reviewer feedback completely.
{{ endif }}
