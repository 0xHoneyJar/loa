---
name: "plan-and-analyze"
version: "3.0.0"
description: |
  Launch PRD discovery with automatic codebase grounding and context ingestion.
  For brownfield projects, automatically runs /ride analysis before PRD creation.
  Reads existing documentation from grimoires/loa/context/ before interviewing.
  Initializes Sprint Ledger and creates development cycle automatically.

  Use --fresh flag to force re-running /ride even if recent reality exists.

arguments:
  - name: "--fresh"
    type: "flag"
    required: false
    description: "Force re-run of /ride analysis even if recent reality exists"

agent: "discovering-requirements"
agent_path: "skills/discovering-requirements/"

context_files:
  # GPT review instructions (conditional - only exists if enabled)
  - path: ".claude/context/gpt-review-active.md"
    required: false
    purpose: "GPT cross-model review instructions (if enabled)"

  # Priority 1: Reality files (codebase understanding from /ride)
  - path: "grimoires/loa/reality/extracted-prd.md"
    required: false
    priority: 1
    purpose: "Extracted requirements from existing codebase"

  - path: "grimoires/loa/reality/extracted-sdd.md"
    required: false
    priority: 1
    purpose: "Extracted architecture from existing codebase"

  - path: "grimoires/loa/reality/component-inventory.md"
    required: false
    priority: 1
    purpose: "Component inventory from codebase analysis"

  - path: "grimoires/loa/consistency-report.md"
    required: false
    priority: 1
    purpose: "Code consistency analysis"

  # Priority 2: User-provided context
  - path: "grimoires/loa/context/*.md"
    required: false
    recursive: true
    priority: 2
    purpose: "Pre-existing project documentation for synthesis"

  - path: "grimoires/loa/context/**/*.md"
    required: false
    priority: 2
    purpose: "Meeting notes, references, nested docs"

  - path: "grimoires/loa/a2a/integration-context.md"
    required: false
    priority: 2
    purpose: "Organizational context and conventions"

  # Ledger (for cycle awareness)
  - path: "grimoires/loa/ledger.json"
    required: false
    purpose: "Sprint Ledger for cycle management"

pre_flight:
  - check: "file_not_exists"
    path: "grimoires/loa/prd.md"
    error: "PRD already exists. Delete or rename grimoires/loa/prd.md to restart discovery."
    soft: true  # Warn but allow override

  - check: "script"
    script: ".claude/scripts/detect-codebase.sh"
    store_result: "codebase_detection"
    purpose: "Detect if codebase is GREENFIELD or BROWNFIELD for /ride integration"

  - check: "script"
    script: ".claude/scripts/assess-discovery-context.sh"
    store_result: "context_assessment"
    purpose: "Assess available context for synthesis strategy"

outputs:
  - path: "grimoires/loa/prd.md"
    type: "file"
    description: "Product Requirements Document"
  - path: "grimoires/loa/ledger.json"
    type: "file"
    description: "Sprint Ledger (created if needed)"

mode:
  default: "foreground"
  allow_background: false  # Interactive by nature
---

# Plan and Analyze

## Purpose

Launch structured PRD discovery with automatic codebase grounding and context ingestion. For brownfield projects (existing codebases), automatically runs `/ride` analysis before PRD creation to ensure requirements are grounded in code reality.

## Codebase Grounding (Phase -0.5)

For brownfield projects (>10 source files OR >500 lines of code):

1. **Auto-detects** codebase type (GREENFIELD vs BROWNFIELD)
2. **Runs /ride** automatically if brownfield and no recent reality exists
3. **Uses cached reality** if <7 days old (configurable)
4. **Loads reality files** as highest-priority context

### Grounding Decision Flow

```
BROWNFIELD + no reality → Run /ride (Phase -0.5)
BROWNFIELD + fresh reality (<7 days) → Use cached (skip /ride)
BROWNFIELD + stale reality (>7 days) → Prompt user
BROWNFIELD + --fresh flag → Force re-run /ride
GREENFIELD → Skip directly to Phase -1
```

### Using --fresh Flag

```bash
# Force re-run /ride even if recent reality exists
/plan-and-analyze --fresh
```

## Context-First Behavior

1. **Codebase grounding**: Loads reality files from `/ride` (if brownfield)
2. Scans `grimoires/loa/context/` for existing documentation
3. Synthesizes all sources with reality as highest priority
4. Maps to 7 discovery phases
5. Only asks questions for gaps and strategic decisions

## Invocation

```bash
# Standard invocation (auto-detects and grounds)
/plan-and-analyze

# Force fresh codebase analysis
/plan-and-analyze --fresh
```

## Pre-Discovery Setup (Optional)

```bash
# Create context directory
mkdir -p grimoires/loa/context

# Add any existing docs
cp ~/project-docs/vision.md grimoires/loa/context/
cp ~/project-docs/user-research.md grimoires/loa/context/users.md

# Then run discovery
/plan-and-analyze
```

## Context Directory Structure

```
grimoires/loa/context/
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
- Reads all files from `grimoires/loa/context/`
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

- No prerequisites - this is the entry point for new projects
- For brownfield projects, `/ride` runs automatically (no manual step needed)
- Use `/mount` only if you need manual control over codebase analysis

## Outputs

| Path | Description |
|------|-------------|
| `grimoires/loa/prd.md` | Product Requirements Document with source tracing |

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
| "PRD already exists" | `grimoires/loa/prd.md` exists | Delete/rename existing PRD |
| "/ride failed" | Codebase analysis error | Retry, skip, or abort via prompt |
| "/ride timeout" | Analysis took >20 minutes | Use cached if exists, or skip |

### /ride Error Recovery

If `/ride` fails during brownfield grounding:

1. **Retry**: Re-run `/ride` analysis
2. **Skip**: Proceed without codebase grounding (not recommended)
3. **Abort**: Cancel `/plan-and-analyze` entirely

If you choose Skip, a warning is logged to `NOTES.md` blockers section.

## Sprint Ledger Integration

This command automatically manages the Sprint Ledger:

1. **First Run**: Initializes `grimoires/loa/ledger.json` if not exists
2. **Creates Cycle**: Registers a new development cycle with PRD title as label
3. **Active Cycle Check**: If a cycle is already active, prompts to archive or continue

### Ledger Behavior

```bash
# First run on new project
/plan-and-analyze
# → Creates ledger.json
# → Creates cycle-001 with PRD title

# Second run (new cycle)
/plan-and-analyze
# → Prompts: "Active cycle exists. Archive 'MVP Development' or continue?"
# → If archive: Archives cycle, creates cycle-002
# → If continue: Continues with existing cycle
```

### Commands for Ledger Management

| Command | Purpose |
|---------|---------|
| `/ledger` | View current ledger status |
| `/ledger history` | View all cycles |
| `/archive-cycle "label"` | Archive current cycle manually |

## Flatline Protocol Integration (v1.17.0)

After PRD generation completes, the Flatline Protocol may execute automatically for adversarial multi-model review.

### Automatic Trigger Conditions

The postlude runs if ALL conditions are met:
- `flatline_protocol.enabled: true` in `.loa.config.yaml`
- `flatline_protocol.auto_trigger: true` in `.loa.config.yaml`
- `flatline_protocol.phases.prd: true` in `.loa.config.yaml`

### What Happens

1. **Knowledge Retrieval**: Searches local grimoires for relevant context
2. **Phase 1**: 4 parallel API calls (GPT review, Opus review, GPT skeptic, Opus skeptic)
3. **Phase 2**: Cross-scoring between models
4. **Consensus**: Categorizes improvements as HIGH_CONSENSUS, DISPUTED, or LOW_VALUE
5. **Presentation**: Shows results and offers integration options

### Output

Results are saved to `grimoires/loa/a2a/flatline/prd-review.json`

### Manual Alternative

If auto-trigger is disabled, run manually:
```bash
/flatline-review prd
```

### Error Handling

If Flatline fails, the PRD is still valid. A warning is surfaced but workflow continues.

## Next Step

After PRD is complete: `/architect` to create Software Design Document
