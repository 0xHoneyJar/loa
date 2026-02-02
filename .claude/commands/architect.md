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
  - path: ".claude/context/gpt-review-active.md"
    required: false
    purpose: "GPT cross-model review instructions (if enabled)"
  - path: "grimoires/loa/prd.md"
    required: true
    purpose: "Product requirements for design basis"
  - path: "grimoires/loa/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and knowledge sources"

pre_flight:
  - check: "file_exists"
    path: "grimoires/loa/prd.md"
    error: "PRD not found. Run /plan-and-analyze first."

outputs:
  - path: "grimoires/loa/sdd.md"
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

- PRD created (`grimoires/loa/prd.md` exists)
- Run `/plan-and-analyze` first if PRD is missing

## Workflow

1. **Pre-flight**: Verify setup and PRD exist
2. **PRD Analysis**: Carefully read and analyze requirements
3. **Design**: Architect system, components, APIs, data models
4. **Clarification**: Ask questions with proposals for ambiguities
5. **Validation**: Confirm assumptions with user
6. **Generation**: Create SDD at `grimoires/loa/sdd.md`
7. **Analytics**: Update usage metrics (THJ users only)

## Arguments

| Argument | Description | Required |
|----------|-------------|----------|
| `background` | Run as subagent for parallel execution | No |

## Outputs

| Path | Description |
|------|-------------|
| `grimoires/loa/sdd.md` | Software Design Document |

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
| "PRD not found" | Missing prd.md | Run `/plan-and-analyze` first |

## Architect Style

The architect will:
- Ask clarifying questions before making assumptions
- Present 2-3 proposals with pros/cons for uncertain decisions
- Explain technical tradeoffs clearly
- Only generate SDD when confident in all decisions

## Flatline Protocol Integration (v1.17.0)

After SDD generation completes, the Flatline Protocol may execute automatically for adversarial multi-model review.

### Automatic Trigger Conditions

The postlude runs if ALL conditions are met:
- `flatline_protocol.enabled: true` in `.loa.config.yaml`
- `flatline_protocol.auto_trigger: true` in `.loa.config.yaml`
- `flatline_protocol.phases.sdd: true` in `.loa.config.yaml`

### What Happens

1. **Knowledge Retrieval**: Searches local grimoires for relevant patterns and decisions
2. **Phase 1**: 4 parallel API calls (GPT review, Opus review, GPT skeptic, Opus skeptic)
3. **Phase 2**: Cross-scoring between models
4. **Consensus**: Categorizes improvements as HIGH_CONSENSUS, DISPUTED, or LOW_VALUE
5. **Presentation**: Shows results and offers integration options

### Output

Results are saved to `grimoires/loa/a2a/flatline/sdd-review.json`

### Manual Alternative

If auto-trigger is disabled, run manually:
```bash
/flatline-review sdd
```

## Next Step

After SDD is complete: `/sprint-plan` to break down work into sprints
