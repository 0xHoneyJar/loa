---
name: "architect"
version: "1.0.0"
description: |
  Create comprehensive Software Design Document based on PRD.
  System architecture, tech stack, data models, APIs, security design.

arguments: []

agent: "designing-architecture"
agent_path: "skills/designing-architecture/"

context_files:
  - path: "loa-grimoire/prd.md"
    required: true
    purpose: "Product requirements for design basis"
  - path: "loa-grimoire/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and knowledge sources"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "file_exists"
    path: "loa-grimoire/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."

outputs:
  - path: "loa-grimoire/sdd.md"
    type: "file"
    description: "Software Design Document"

mode:
  default: "foreground"
  allow_background: true
---

# Architect

## Purpose

Create a comprehensive Software Design Document (SDD) based on the Product Requirements Document. Designs system architecture, technology stack, data models, APIs, and security architecture.

## Invocation

```
/architect
/architect background
```

## Agent

Launches `designing-architecture` from `skills/designing-architecture/`.

See: `skills/designing-architecture/SKILL.md` for full workflow details.

## Prerequisites

- Setup completed (`.loa-setup-complete` exists)
- PRD created (`loa-grimoire/prd.md` exists)
- Run `/plan-and-analyze` first if PRD is missing

## Workflow

1. **Pre-flight**: Verify setup and PRD exist
2. **PRD Analysis**: Carefully read and analyze requirements
3. **Design**: Architect system, components, APIs, data models
4. **Clarification**: Ask questions with proposals for ambiguities
5. **Validation**: Confirm assumptions with user
6. **Generation**: Create SDD at `loa-grimoire/sdd.md`
7. **Analytics**: Update usage metrics (THJ users only)

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/sdd.md` | Software Design Document |

## SDD Sections

The generated SDD includes:
- Executive Summary
- System Architecture (high-level components and interactions)
- Technology Stack (with justification for choices)
- Component Design (detailed breakdown of each component)
- Data Architecture (database schema, data models, storage)
- API Design (endpoints, contracts, authentication)
- Security Architecture (auth, encryption, threat mitigation)
- Integration Points (external services, APIs, dependencies)
- Scalability & Performance (caching, load balancing)
- Deployment Architecture (infrastructure, CI/CD, environments)
- Development Workflow (Git strategy, testing, code review)
- Technical Risks & Mitigation Strategies
- Future Considerations & Technical Debt Management

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Loa setup has not been completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "PRD not found" | Missing prd.md | Run `/plan-and-analyze` first |

## Architect Style

The architect will:
- Ask clarifying questions before making assumptions
- Present 2-3 proposals with pros/cons for uncertain decisions
- Explain technical tradeoffs clearly
- Only generate SDD when confident in all decisions

## Next Step

After SDD is complete: `/sprint-plan` to break down work into sprints
