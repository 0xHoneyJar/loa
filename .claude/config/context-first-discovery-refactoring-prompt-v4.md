# Discovering Requirements → Context-First Discovery Refactoring Prompt

<context>
You are refactoring the `discovering-requirements` skill to implement a **Context-First Discovery** workflow that eliminates redundant questions by ingesting developer-supplied documentation before the interview phase.

**Problem Statement:**
Currently, `/plan-and-analyze` asks many low-level questions that developers must answer manually, even when the answers exist in project documentation, meeting notes, or design files. This creates a poor developer experience and misses opportunities to leverage existing context.

**Solution:**
Add a "Phase 0: Context Synthesis" that:
1. Scans a designated context directory for existing documentation
2. Maps discovered information to the 7 Discovery Phases
3. Only asks questions for gaps, ambiguities, or strategic decisions
4. Cites source documents when summarizing existing knowledge

**Design Principles:**
- Developer shifts from "data entry" → "editor/reviewer"
- Claude demonstrates understanding before asking questions
- Large context sets trigger parallel subagent processing
- All claims grounded with file:line citations

**Naming Convention:**
This refactor uses Anthropic's recommended gerund naming (verb + -ing):
- Skill: `discovering-requirements` (not `prd-architect`)
- Action-based names describe capability, not role
</context>

---

## Directory Convention

<directory_structure>
Establish a standard location for pre-discovery context:

```
loa-grimoire/
├── context/                      # NEW: Pre-discovery context directory
│   ├── README.md                 # Instructions for developers
│   ├── vision.md                 # Product vision, mission, goals
│   ├── users.md                  # User personas, research, interviews
│   ├── requirements.md           # Existing requirements, feature lists
│   ├── technical.md              # Technical constraints, stack preferences
│   ├── competitors.md            # Competitive analysis, market research
│   ├── meetings/                 # Meeting notes, stakeholder interviews
│   │   └── *.md
│   └── references/               # External docs, specs, designs
│       └── *.*
├── prd.md                        # Output (generated)
└── ...
```

**Key Points:**
- Directory is optional - workflow gracefully handles missing context
- Supports any markdown files, not just predefined names
- Nested directories supported for organization
- Non-markdown files (images, PDFs) noted but not parsed
</directory_structure>

<context_readme_template>
Create `loa-grimoire/context/README.md` as a guide for developers:

```markdown
# Discovery Context

Place any existing documentation here before running `/plan-and-analyze`.
The PRD architect will read these files and only ask questions about gaps.

## Suggested Files (all optional)

| File | Contents |
|------|----------|
| `vision.md` | Product vision, mission, problem statement, goals |
| `users.md` | User personas, research findings, interview notes |
| `requirements.md` | Feature lists, user stories, acceptance criteria |
| `technical.md` | Tech stack preferences, constraints, integrations |
| `competitors.md` | Competitive analysis, market positioning |
| `meetings/*.md` | Stakeholder interview notes, meeting summaries |

## Tips

- Raw notes are fine - Claude will synthesize
- Include contradictions - Claude will ask for clarification
- More context = fewer questions
- Empty directory = full discovery interview
```
</context_readme_template>

---

## Script: Context Assessment

<script_note>
**Integration with v4.1 Scripts:**
The v4.1 refactor includes `context-check.sh` for general context size assessment.
This discovery-specific script extends that pattern for the `/plan-and-analyze` workflow,
adding file categorization and discovery-phase mapping.
</script_note>

<script>
Create `.claude/scripts/assess-discovery-context.sh`:

```bash
#!/bin/bash
# assess-discovery-context.sh
# Purpose: Assess available context files for PRD discovery
# Usage: ./assess-discovery-context.sh [context_dir]
# Returns: JSON summary of available context
# Note: Complements context-check.sh with discovery-specific logic

set -euo pipefail

CONTEXT_DIR="${1:-loa-grimoire/context}"

# Check if directory exists
if [ ! -d "$CONTEXT_DIR" ]; then
    echo '{"status":"NO_CONTEXT_DIR","files":[],"total_lines":0}'
    exit 0
fi

# Count markdown files
MD_FILES=$(find "$CONTEXT_DIR" -name "*.md" -type f 2>/dev/null | grep -v README.md || true)
FILE_COUNT=$(echo "$MD_FILES" | grep -c . || echo "0")

if [ "$FILE_COUNT" -eq "0" ]; then
    echo '{"status":"EMPTY","files":[],"total_lines":0}'
    exit 0
fi

# Calculate total lines
TOTAL_LINES=$(echo "$MD_FILES" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

# Determine size category
if [ "$TOTAL_LINES" -lt 500 ]; then
    SIZE="SMALL"
elif [ "$TOTAL_LINES" -lt 2000 ]; then
    SIZE="MEDIUM"
else
    SIZE="LARGE"
fi

# List files with line counts
FILES_JSON=$(echo "$MD_FILES" | while read -r f; do
    lines=$(wc -l < "$f")
    name=$(basename "$f")
    echo "{\"name\":\"$name\",\"path\":\"$f\",\"lines\":$lines}"
done | paste -sd "," -)

echo "{\"status\":\"$SIZE\",\"file_count\":$FILE_COUNT,\"total_lines\":$TOTAL_LINES,\"files\":[$FILES_JSON]}"
```

**Returns:**
```json
{"status":"MEDIUM","file_count":4,"total_lines":847,"files":[
  {"name":"vision.md","path":"loa-grimoire/context/vision.md","lines":124},
  {"name":"users.md","path":"loa-grimoire/context/users.md","lines":289},
  ...
]}
```
</script>

---

## Command Update: plan-and-analyze.md

<command_update>
Update `.claude/commands/plan-and-analyze.md`:

```yaml
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
Launch structured PRD discovery with automatic context ingestion.

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
```
</command_update>

---

## SKILL.md Refactoring

<skill_update>
Update `.claude/skills/discovering-requirements/SKILL.md`:

```markdown
---
parallel_threshold: 2000  # Lines before using subagents for context
timeout_minutes: 90
---

# Discovering Requirements

<objective>
Synthesize existing project documentation and conduct targeted discovery 
interviews to produce a comprehensive PRD at `loa-grimoire/prd.md`.
</objective>

<persona>
**Role**: Senior Product Manager | 15 years | Enterprise & Startup | User-Centered Design
**Approach**: Read first, ask second. Demonstrate understanding before requesting input.
</persona>

<kernel_framework>
## Task
Produce comprehensive PRD by:
1. Ingesting all context from `loa-grimoire/context/`
2. Mapping existing information to 7 discovery phases
3. Conducting targeted interviews for gaps only
4. Generating PRD with full traceability to sources

## Context
- **Input**: `loa-grimoire/context/*.md` (optional), developer interview
- **Output**: `loa-grimoire/prd.md`
- **Integration**: `loa-grimoire/a2a/integration-context.md` (if exists)

## Constraints
- DO NOT ask questions answerable from provided context
- DO cite sources: `> From vision.md:12: "exact quote"`
- DO present understanding for confirmation before proceeding
- DO ask for clarification on contradictions, not assumptions
- DO limit questions to 2-3 per phase maximum

## Verification
PRD traces every requirement to either:
- Source document (file:line citation)
- Interview response (phase:question reference)
</kernel_framework>

<workflow>
## Phase -1: Context Assessment

Run context assessment:
```bash
./.claude/scripts/assess-discovery-context.sh
```

| Result | Strategy |
|--------|----------|
| `NO_CONTEXT_DIR` | Create directory, offer guidance, proceed to full interview |
| `EMPTY` | Proceed to full 7-phase interview |
| `SMALL` (<500 lines) | Sequential ingestion, then targeted interview |
| `MEDIUM` (500-2000) | Sequential ingestion, then targeted interview |
| `LARGE` (>2000) | Parallel subagent ingestion, then targeted interview |

## Phase 0: Context Synthesis (NEW)

**If context files exist:**

### Step 1: Ingest All Context
Read every `.md` file in `loa-grimoire/context/` (and subdirectories).

### Step 2: Create Context Map
Internally categorize discovered information:

```xml
<context_map>
  <phase name="problem_vision">
    <found source="vision.md:1-45">
      Product vision, mission statement, core problem
    </found>
    <gap>Success metrics not defined</gap>
  </phase>
  
  <phase name="goals_metrics">
    <found source="vision.md:47-52">
      High-level goals mentioned
    </found>
    <gap>No quantifiable success criteria</gap>
    <gap>Timeline not specified</gap>
  </phase>
  
  <phase name="users_stakeholders">
    <found source="users.md:1-289">
      3 personas defined with jobs-to-be-done
    </found>
    <ambiguity>Persona priorities unclear - which is primary?</ambiguity>
  </phase>
  
  <!-- Continue for all 7 phases -->
</context_map>
```

### Step 3: Present Understanding
Before asking ANY questions, present a synthesis:

```markdown
## What I've Learned From Your Documentation

I've reviewed 4 files (847 lines) from your context directory.

### Problem & Vision
> From vision.md:12-15: "We're building a decentralized identity 
> platform that gives users control over their personal data..."

I understand the core problem is [summary]. The vision is [summary].

### Users & Stakeholders  
> From users.md:23-45: "Primary persona: Privacy-conscious professionals..."

You've defined 3 personas: [list with 1-line each].

### What I Still Need to Understand
1. **Success Metrics**: What quantifiable outcomes define success?
2. **Persona Priority**: Which user persona should we optimize for first?
3. **Timeline**: What are the key milestones and deadlines?

Should I proceed with these clarifying questions, or would you like to 
correct my understanding first?
```

## Phase 0.5: Targeted Interview

**For each gap/ambiguity identified:**

1. State what you know (with citation)
2. State what's missing or unclear  
3. Ask focused question (max 2-3 per phase)

**Example:**
```markdown
### Goals & Success Metrics

I found high-level goals in vision.md:
> "Achieve product-market fit within 12 months"

However, I didn't find specific success metrics. 

**Questions:**
1. What metrics would indicate product-market fit for this product?
2. Are there intermediate milestones (3-month, 6-month)?
```

## Phases 1-7: Conditional Discovery

For each phase, follow this logic:

```
IF phase fully covered by context:
  → Summarize understanding with citations
  → Ask: "Is this accurate? Any corrections?"
  → Move to next phase

ELSE IF phase partially covered:
  → Summarize what's known (with citations)
  → Ask only about gaps (max 2-3 questions)
  → Move to next phase

ELSE IF phase not covered:
  → Conduct full discovery for this phase
  → Ask 2-3 questions at a time
  → Iterate until complete
```

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
- Technical constraints

### Phase 6: Scope & Prioritization
- MVP definition
- Phase 1 vs future scope
- Out of scope (explicit)

### Phase 7: Risks & Dependencies
- Technical risks
- Business risks
- External dependencies
- Mitigation strategies

## Phase 8: PRD Generation

Only generate PRD when:
- [ ] All 7 phases have sufficient coverage
- [ ] All ambiguities resolved
- [ ] Developer confirms understanding is accurate

Generate PRD with source tracing:
```markdown
## 1. Problem Statement

[Content derived from vision.md:12-30 and Phase 1 interview]

> Source: vision.md:12-15, confirmed in Phase 1 Q2
```
</workflow>

<parallel_execution>
## Large Context Handling (>2000 lines)

If context assessment returns `LARGE`:

### Spawn Parallel Ingestors
```
Task(subagent_type="Explore", prompt="
CONTEXT INGESTION: Problem & Vision

Read these files: [vision.md, any *vision* or *problem* files]
Extract and summarize:
- Core problem statement
- Product vision
- Mission/purpose
- 'Why now' factors

Return as structured summary with file:line citations.
")
```

Spawn 4 parallel ingestors:
1. **Vision Ingestor**: Problem, vision, mission
2. **User Ingestor**: Personas, research, journeys
3. **Requirements Ingestor**: Features, stories, specs
4. **Technical Ingestor**: Constraints, stack, integrations

### Consolidate
Merge summaries into unified context map before proceeding.
</parallel_execution>

<output_format>
PRD structure with source tracing - see `resources/templates/prd-template.md`

Each section must include:
```markdown
> **Sources**: vision.md:12-30, users.md:45-67, Phase 3 Q1-Q2
```
</output_format>

<success_criteria>
- **Specific**: Every PRD requirement traced to source (file:line or phase:question)
- **Measurable**: Questions reduced by 50%+ when context provided
- **Achievable**: Synthesis completes before any interview questions
- **Relevant**: Developer confirms understanding before proceeding
- **Time-bound**: Context synthesis <5 min for SMALL/MEDIUM
</success_criteria>

<uncertainty_protocol>
- If context files contradict each other → Ask developer to clarify
- If context is ambiguous → State interpretation, ask for confirmation
- If context seems outdated → Ask if still accurate
- Never assume → Always cite or ask
</uncertainty_protocol>

<grounding_requirements>
Every claim about existing context must include citation:
- Format: `> From {filename}:{line}: "exact quote"`
- Summaries must reference source range: `(vision.md:12-45)`
- PRD sections must list all sources used
</grounding_requirements>
```
</skill_update>

---

## index.yaml Update

<index_update>
Update `.claude/skills/discovering-requirements/index.yaml`:

```yaml
name: "discovering-requirements"
version: "2.0.0"
model: "sonnet"
color: "purple"

description: |
  Use this skill IF user invokes `/plan-and-analyze` OR needs to create a PRD.
  
  CONTEXT-FIRST: Automatically ingests existing documentation from 
  `loa-grimoire/context/` before interviewing. Only asks questions for 
  gaps, ambiguities, and strategic decisions.
  
  Produces comprehensive PRD at `loa-grimoire/prd.md` with full source tracing.

triggers:
  - "/plan-and-analyze"
  - "create prd"
  - "define requirements"
  - "product discovery"

examples:
  - context: "Developer has existing documentation"
    user_says: "/plan-and-analyze"
    agent_action: |
      1. Run context assessment script
      2. Ingest all files from loa-grimoire/context/
      3. Present understanding with citations
      4. Ask only gap-filling questions
      5. Generate PRD with source tracing
  
  - context: "No existing documentation"
    user_says: "/plan-and-analyze"
    agent_action: |
      1. Note empty context directory
      2. Offer to create context/README.md
      3. Proceed with full 7-phase discovery
      4. Generate PRD

inputs:
  - name: "context_dir"
    type: "directory"
    path: "loa-grimoire/context/"
    required: false

outputs:
  - path: "loa-grimoire/prd.md"
    description: "Product Requirements Document with source tracing"

dependencies: []

parallel_execution:
  enabled: true
  threshold: 2000  # Lines before spawning parallel ingestors
  strategy: "by_category"  # vision, users, requirements, technical
```
</index_update>

---

## Edge Cases

<edge_cases>
Handle these scenarios explicitly:

| Scenario | Behavior |
|----------|----------|
| No context directory | Create it, add README.md, proceed to full interview |
| Empty context directory | Note it, proceed to full interview |
| Only README.md exists | Treat as empty, proceed to full interview |
| Contradictory information | List contradictions, ask developer to clarify |
| Outdated information | Ask "Is this still accurate?" before using |
| Very large files (>1000 lines) | Summarize key sections, note full file available |
| Non-markdown files | Note existence, explain can't parse |
| Partial coverage | Conduct mini-interviews for gaps only |
| Developer disagrees with synthesis | Allow corrections, update understanding |
</edge_cases>

---

## Validation Checklist

<validation>
### Command
- [ ] `context_files` includes glob patterns for context directory
- [ ] `pre_flight` runs context assessment script
- [ ] Soft warning if PRD already exists

### SKILL.md
- [ ] Phase -1 runs context assessment script
- [ ] Phase 0 synthesizes before any questions
- [ ] Context map uses XML structure for reliability
- [ ] Understanding presented with citations
- [ ] Questions limited to 2-3 per phase
- [ ] Parallel execution for >2000 lines
- [ ] PRD includes source tracing
- [ ] Under 500 lines total

### Script
- [ ] Handles missing directory gracefully
- [ ] Returns JSON for reliable parsing
- [ ] Categorizes by size (SMALL/MEDIUM/LARGE)
- [ ] Lists all files with line counts

### Developer Experience
- [ ] Can run with zero context (full interview)
- [ ] Can run with partial context (targeted interview)
- [ ] Can run with full context (confirmation only)
- [ ] Always sees understanding before questions
- [ ] Can correct misunderstandings
</validation>

---

## Example Interaction

<example>
**Scenario**: Developer has vision.md and users.md in context directory

```
User: /plan-and-analyze

Claude: I've found 2 context files (413 lines total) in loa-grimoire/context/.
Let me review them before we begin...

---

## What I've Learned From Your Documentation

### Problem & Vision
> From vision.md:8-12: "Current identity systems force users to trust 
> centralized authorities with their personal data. We're building a 
> decentralized alternative that puts users in control."

I understand you're solving the problem of centralized identity control.
Your vision is a decentralized identity platform prioritizing user sovereignty.

### Users & Stakeholders
> From users.md:15-89: Three personas defined:
> 1. "Privacy-conscious professional" - primary concern: data ownership
> 2. "Enterprise compliance officer" - primary concern: regulatory compliance  
> 3. "Developer integrating identity" - primary concern: simple APIs

You've defined 3 user personas with clear jobs-to-be-done.

### What's Missing
I didn't find information about:
- **Success metrics**: How will you measure product-market fit?
- **Technical constraints**: Any blockchain/protocol preferences?
- **Timeline**: Key milestones and deadlines?
- **Scope**: What's MVP vs. future phases?

**Is my understanding accurate so far?** I'd like to confirm before 
asking about the gaps.

User: Yes, that's accurate. For metrics, we want 10k users in 6 months.

Claude: Great, I've noted that success metric.

> Confirmed: vision.md understanding accurate
> Added: Success metric = 10k users in 6 months (Phase 2, user input)

**Remaining gaps to discuss:**
1. Technical constraints - any preferences on blockchain, protocols?
2. Timeline - what are the intermediate milestones?
3. MVP scope - which features are must-have vs. nice-to-have?

Let's start with technical constraints...
```
</example>