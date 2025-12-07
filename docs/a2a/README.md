# Agent-to-Agent (A2A) Communication

This directory contains files that enable agents to communicate and coordinate with each other.

## Files

### `integration-context.md` (Optional)
**Created by**: `context-engineering-expert` agent (via `/integrate-org-workflow`)
**Read by**: All downstream agents

When this file exists, it provides organizational workflow context to all agents:
- Available tools (Discord, Linear, Google Docs, etc.)
- Knowledge sources (LEARNINGS library, user personas, community feedback)
- Context preservation requirements (how to link back to source discussions)
- Team structure and roles
- Documentation locations

**All agents check for this file before starting their work** and adapt their behavior based on the organizational integration context provided.

### `integration-context.md.template`
Template for generating the integration context file. The `context-engineering-expert` agent uses this as a starting point and customizes it based on organizational discovery.

### `reviewer.md`
**Created by**: `sprint-task-implementer` agent
**Read by**: `senior-tech-lead-reviewer` agent (and human reviewers)

Implementation report containing:
- Tasks completed
- Files created/modified
- Test coverage details
- Technical decisions made
- Verification steps performed
- How previous feedback was addressed (if applicable)

### `engineer-feedback.md`
**Created by**: Senior technical lead (human or `senior-tech-lead-reviewer` agent)
**Read by**: `sprint-task-implementer` agent

Review feedback containing:
- Issues found in implementation
- Required changes
- Clarifications needed
- Quality concerns
- Approval status

## Workflow

### Phase 0: Integration (Optional)
```
/integrate-org-workflow
    ↓
context-engineering-expert creates integration-context.md
    ↓
All downstream agents read this file and adapt behavior
```

### Phases 4-5: Implementation Feedback Loop
```
/implement sprint-1
    ↓
sprint-task-implementer creates reviewer.md
    ↓
Human or senior-tech-lead-reviewer reviews code and report
    ↓
Creates engineer-feedback.md with feedback or approval
    ↓ (if feedback provided)
/implement sprint-1 (again)
    ↓
sprint-task-implementer reads feedback, fixes issues
    ↓
Updates reviewer.md with changes
    ↓
(repeat until approved)
```

## Notes

- These files enable **stateless agent invocations** - each agent reads context from files rather than maintaining conversation history
- The `integration-context.md` file makes the framework **org-aware** while remaining **workflow-agnostic** when used standalone
- The feedback loop files enable **iterative quality improvement** without blocking progress
