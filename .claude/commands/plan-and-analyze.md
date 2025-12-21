---
name: "plan-and-analyze"
version: "1.0.0"
description: |
  Create comprehensive Product Requirements Document through structured discovery.
  7-phase discovery process to define goals, requirements, and scope.

arguments: []

agent: "discovering-requirements"
agent_path: "skills/discovering-requirements/"

context_files:
  - path: "loa-grimoire/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and knowledge sources"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

outputs:
  - path: "loa-grimoire/prd.md"
    type: "file"
    description: "Product Requirements Document"

mode:
  default: "foreground"
  allow_background: true
---

# Plan and Analyze

## Purpose

Create a comprehensive Product Requirements Document (PRD) through structured 7-phase discovery. Transform ambiguous product ideas into actionable requirements.

## Invocation

```
/plan-and-analyze
/plan-and-analyze background
```

## Agent

Launches `discovering-requirements` from `skills/discovering-requirements/`.

See: `skills/discovering-requirements/SKILL.md` for full workflow details.

## Prerequisites

- Setup completed (`.loa-setup-complete` exists)
- Run `/setup` first if not configured

## Workflow

1. **Pre-flight**: Verify setup is complete
2. **Integration Context**: Check for organizational knowledge sources
3. **Discovery Phases**: 7-phase structured questioning
4. **Confirmation**: Summarize understanding, get user approval
5. **Generation**: Create PRD at `loa-grimoire/prd.md`
6. **Analytics**: Update usage metrics (THJ users only)

## Discovery Phases

### Phase 1: Problem & Vision
- What problem are we solving, and for whom?
- What does success look like from the user's perspective?
- What's the broader vision this fits into?

### Phase 2: Goals & Success Metrics
- What are the specific, measurable goals?
- How will we know this is successful? (KPIs, metrics)
- What constraints or limitations exist?

### Phase 3: User & Stakeholder Context
- Who are the primary users?
- What are the key user personas and their needs?
- Who are the stakeholders, and what are their priorities?

### Phase 4: Functional Requirements
- What are the must-have features vs. nice-to-have?
- What are the critical user flows and journeys?
- What integrations or dependencies exist?

### Phase 5: Technical & Non-Functional Requirements
- What are the performance, scalability requirements?
- What are the security, privacy considerations?
- What platforms must be supported?

### Phase 6: Scope & Prioritization
- What's explicitly in scope for this release?
- What's explicitly out of scope?
- What's the MVP vs. future iterations?

### Phase 7: Risks & Dependencies
- What are the key risks or unknowns?
- What dependencies exist?
- What assumptions are we making?

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/prd.md` | Product Requirements Document |

## PRD Sections

The generated PRD includes:
- Executive Summary
- Problem Statement
- Goals & Success Metrics
- User Personas & Use Cases
- Functional Requirements (with acceptance criteria)
- Non-Functional Requirements
- User Experience
- Technical Considerations
- Scope & Prioritization
- Success Criteria
- Risks & Mitigation
- Timeline & Milestones
- Appendix

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Loa setup has not been completed" | Missing `.loa-setup-complete` | Run `/setup` first |

## Next Step

After PRD is complete: `/architect` to create Software Design Document
