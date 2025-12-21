---
name: "plan-and-analyze"
version: "2.0.0"
description: |
  Launch PRD discovery with automatic context ingestion.
  Reads existing documentation from loa-grimoire/context/ before interviewing.

arguments: []

agent: "discovering-requirements"
agent_path: "skills/discovering-requirements/"

context_files:
  # Core context (always attempt to read)
  - path: "loa-grimoire/context/*.md"
    required: false
    recursive: true
    purpose: "Pre-existing project documentation for synthesis"

  # Nested context
  - path: "loa-grimoire/context/**/*.md"
    required: false
    purpose: "Meeting notes, references, nested docs"

  # Integration context (if exists)
  - path: "loa-grimoire/a2a/integration-context.md"
    required: false
    purpose: "Organizational context and conventions"

pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "file_not_exists"
    path: "loa-grimoire/prd.md"
    error: "PRD already exists. Delete or rename loa-grimoire/prd.md to restart discovery."
    soft: true  # Warn but allow override

  - check: "script"
    script: ".claude/scripts/assess-discovery-context.sh"
    store_result: "context_assessment"
    purpose: "Assess available context for synthesis strategy"

outputs:
  - path: "loa-grimoire/prd.md"
    type: "file"
    description: "Product Requirements Document"

mode:
  default: "foreground"
  allow_background: false  # Interactive by nature
---

# Plan and Analyze

## Purpose

Launch structured PRD discovery with automatic context ingestion. Transforms ambiguous product ideas into comprehensive, actionable requirements.

## Context-First Behavior

1. Scans `loa-grimoire/context/` for existing documentation
2. Synthesizes found documents into understanding
3. Maps to 7 discovery phases
4. Only asks questions for gaps and strategic decisions

## Invocation

```bash
/plan-and-analyze
```

## Pre-Discovery Setup (Optional)

```bash
# Create context directory
mkdir -p loa-grimoire/context

# Add any existing docs
cp ~/project-docs/vision.md loa-grimoire/context/
cp ~/project-docs/user-research.md loa-grimoire/context/users.md

# Then run discovery
/plan-and-analyze
```

## Context Directory Structure

```
loa-grimoire/context/
├── README.md           # Instructions for developers
├── vision.md           # Product vision, mission, goals
├── users.md            # User personas, research, interviews
├── requirements.md     # Existing requirements, feature lists
├── technical.md        # Technical constraints, stack preferences
├── competitors.md      # Competitive analysis, market research
├── meetings/           # Meeting notes, stakeholder interviews
│   └── *.md
└── references/         # External docs, specs, designs
    └── *.*
```

All files are optional. The more context provided, the fewer questions asked.

## Discovery Phases

### Phase 0: Context Synthesis (NEW)
- Reads all files from `loa-grimoire/context/`
- Maps discovered information to 7 phases
- Presents understanding with citations
- Identifies gaps requiring clarification

### Phase 1: Problem & Vision
- Core problem being solved
- Product vision and mission
- Why now? Why you?

### Phase 2: Goals & Success Metrics
- Business objectives
- Quantifiable success criteria
- Timeline and milestones

### Phase 3: User & Stakeholder Context
- Primary and secondary personas
- User journey and pain points
- Stakeholder requirements

### Phase 4: Functional Requirements
- Core features and capabilities
- User stories with acceptance criteria
- Feature prioritization

### Phase 5: Technical & Non-Functional
- Performance requirements
- Security and compliance
- Integration requirements

### Phase 6: Scope & Prioritization
- MVP definition
- Phase 1 vs future scope
- Out of scope (explicit)

### Phase 7: Risks & Dependencies
- Technical risks
- Business risks
- External dependencies

## Context Size Handling

| Size | Lines | Strategy |
|------|-------|----------|
| SMALL | <500 | Sequential ingestion, targeted interview |
| MEDIUM | 500-2000 | Sequential ingestion, targeted interview |
| LARGE | >2000 | Parallel subagent ingestion |

## Prerequisites

- Setup completed (`.loa-setup-complete` exists)
- Run `/setup` first if not configured

## Outputs

| Path | Description |
|------|-------------|
| `loa-grimoire/prd.md` | Product Requirements Document with source tracing |

## PRD Source Tracing

Generated PRD includes citations:
```markdown
## 1. Problem Statement

[Content derived from vision.md:12-30 and Phase 1 interview]

> Sources: vision.md:12-15, confirmed in Phase 1 Q2
```

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Loa setup has not been completed" | Missing `.loa-setup-complete` | Run `/setup` first |
| "PRD already exists" | `loa-grimoire/prd.md` exists | Delete/rename existing PRD |

## Next Step

After PRD is complete: `/architect` to create Software Design Document
