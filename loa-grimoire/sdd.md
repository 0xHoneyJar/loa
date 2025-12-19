# Software Design Document: Loa + Hivemind OS Integration

**Version**: 1.0
**Date**: 2025-12-19
**Author**: Architecture Designer Agent
**Status**: Draft
**PRD Reference**: `loa-grimoire/prd.md` v2.0

---

## 1. Executive Summary

This document describes the technical architecture for integrating Loa (Laboratory Executor) with Hivemind OS (Organizational Memory). The integration enables:

1. **Bidirectional Context Flow**: Hivemind knowledge informs Loa decisions; Loa learnings flow back
2. **Mode-Aware Execution**: Creative vs Secure modes with confirmation gates
3. **Automatic Candidate Surfacing**: ADR/Learning candidates captured during execution
4. **Skill Integration**: Hivemind skills symlinked and auto-loaded

### Architecture Decisions Summary

| Decision | Chosen Approach | Rationale |
|----------|-----------------|-----------|
| **Implementation Strategy** | Modified `/setup` with modular checkbox UX | Engaging, non-overwhelming, expandable |
| **Context Query Mechanism** | Hivemind's existing agents (symlinked) | Thorough, intentional, parallel research |
| **Mode Detection Triggers** | Phase-based rules (v1) | Predictable, simple, expandable later |
| **Candidate Surfacing Trigger** | Batch at end of phase, non-blocking | Maintains flow state, comprehensive |
| **Skill Symlink Strategy** | Symlink folders with validation | Clean, maintainable, graceful fallback |

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           LOA FRAMEWORK                              │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                     LEGBA INTEGRATION LAYER                      │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │ │
│  │  │ Setup Module │  │ Mode Manager │  │ Candidate    │           │ │
│  │  │ (Extended)   │  │              │  │ Surfacer     │           │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │ │
│  │  │ Context      │  │ Skill        │  │ Analytics    │           │ │
│  │  │ Injector     │  │ Symlinker    │  │ Tracker      │           │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘           │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                        LOA AGENTS                                │ │
│  │  PRD → SDD → Sprint → Implement → Review → Audit → Deploy       │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ Symlinks + MCP
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        HIVEMIND OS                                   │
│  ┌──────────────────────────┐  ┌──────────────────────────────────┐ │
│  │         LIBRARY          │  │         LABORATORY               │ │
│  │  ┌────────────────────┐  │  │  ┌────────────────────────────┐  │ │
│  │  │ decisions/ (ADRs)  │  │  │  │ experiments/               │  │ │
│  │  │ timeline/ (ERRs)   │  │  │  │ audits/                    │  │ │
│  │  │ knowledge/         │  │  │  │ logs/                      │  │ │
│  │  │ ecosystem/         │  │  │  └────────────────────────────┘  │ │
│  │  └────────────────────┘  │  │                                  │ │
│  └──────────────────────────┘  └──────────────────────────────────┘ │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    HIVEMIND SKILLS (28)                          │ │
│  │  lib-* (governance) | lab-* (domain) | execution modes          │ │
│  └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              │ MCP Integration
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                           LINEAR                                     │
│  Product Homes │ Cycles │ Issues │ ADR/Learning Candidates          │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Directory Structure

```
project-root/
├── .claude/
│   ├── agents/                    # Loa agents (unchanged)
│   │   ├── prd-architect.md
│   │   ├── architecture-designer.md
│   │   ├── sprint-planner.md
│   │   ├── sprint-task-implementer.md
│   │   ├── senior-tech-lead-reviewer.md
│   │   ├── devops-crypto-architect.md
│   │   ├── paranoid-auditor.md
│   │   └── devrel-translator.md
│   │
│   ├── commands/                  # Extended commands
│   │   ├── setup.md               # Extended with Hivemind connection
│   │   ├── plan-and-analyze.md    # Extended with context injection
│   │   ├── architect.md           # Extended with ADR surfacing
│   │   └── ...
│   │
│   ├── skills/                    # Symlinked from Hivemind
│   │   ├── lab-cubquests-game-design -> ...
│   │   ├── lab-frontend-design-systems -> ...
│   │   └── ...
│   │
│   ├── lib/                       # NEW: Shared utilities
│   │   ├── hivemind-connection.md # Connection helpers
│   │   ├── mode-manager.md        # Mode detection/switching
│   │   ├── context-injector.md    # Query patterns
│   │   └── candidate-surfacer.md  # ADR/Learning detection
│   │
│   ├── .mode                      # Mode state file (JSON)
│   └── settings.local.json        # MCP configuration
│
├── .hivemind/                     # Symlink → ../hivemind-library
│   ├── library/                   # Read-only organizational memory
│   ├── laboratory/                # Experiments and audits
│   └── .claude/
│       └── skills/                # Source for skill symlinks
│
├── loa-grimoire/                  # Loa artifacts
│   ├── prd.md
│   ├── sdd.md
│   ├── sprint.md
│   ├── a2a/
│   │   ├── integration-context.md # Extended with Hivemind data
│   │   └── ...
│   └── analytics/
│
├── .loa-setup-complete            # Setup marker (gitignored)
└── .gitignore                     # Includes .hivemind/, .claude/.mode
```

---

## 3. Component Design

### 3.1 Extended Setup Module (`/setup`)

The setup command is extended with modular, checkbox-based UX for Hivemind connection.

#### 3.1.1 Setup Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    /setup COMMAND FLOW                              │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Phase 1: Welcome & Analytics │
              │  (Existing Loa setup)         │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Phase 2: Hivemind Connection │
              │  ☐ Connect to Hivemind OS     │
              │    → Enables org memory       │
              │    → Auto-loads skills        │
              └───────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │ If checked                    │ If skipped
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────┐
│ Phase 2a: Detect Path   │     │ Continue without        │
│ ../hivemind-library?    │     │ Hivemind integration    │
│ Custom path?            │     └─────────────────────────┘
└─────────────────────────┘
              │
              ▼
┌─────────────────────────┐
│ Phase 2b: Create Symlink│
│ .hivemind → path        │
│ Validate symlink works  │
└─────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Phase 3: Project Configuration (Checkbox Grid)                     │
│                                                                     │
│  Project Type (select one):                                         │
│  ☐ Frontend      ☐ Contracts     ☐ Indexer                         │
│  ☐ Game Design   ☐ Cross-Domain  ☐ Backend                         │
│                                                                     │
│  Optional Integrations:                                             │
│  ☐ Link Product Home (Linear)                                       │
│  ☐ Link Experiment (from Hivemind)                                  │
└─────────────────────────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────┐
│ Phase 4: Skill Symlinks │
│ Based on project type   │
│ Validate each symlink   │
└─────────────────────────┘
              │
              ▼
┌─────────────────────────┐
│ Phase 5: Mode Selection │
│ Initial mode based on   │
│ project type            │
│ Store in .claude/.mode  │
└─────────────────────────┘
              │
              ▼
┌─────────────────────────┐
│ Phase 6: MCP Servers    │
│ (Existing Loa setup)    │
└─────────────────────────┘
              │
              ▼
         Setup Complete
```

#### 3.1.2 Setup Command Extension

**File**: `.claude/commands/setup.md`

```markdown
## Hivemind Integration (Phase 2)

If user selects "Connect to Hivemind OS":

1. **Detect Hivemind Path**
   ```bash
   # Check default location
   if [ -d "../hivemind-library" ]; then
       HIVEMIND_PATH="../hivemind-library"
   else
       # Ask for custom path
       read -p "Hivemind path: " HIVEMIND_PATH
   fi
   ```

2. **Create Symlink**
   ```bash
   ln -sf "$HIVEMIND_PATH" .hivemind

   # Validate
   if [ -d ".hivemind/library" ]; then
       echo "✓ Hivemind connected"
   else
       echo "✗ Symlink failed, continuing without Hivemind"
   fi
   ```

3. **Update integration-context.md**
   ```markdown
   ## Hivemind Integration

   ### Connection Status
   - **Hivemind Path**: .hivemind → {resolved_path}
   - **Connection Date**: {timestamp}
   - **Status**: Connected
   ```
```

#### 3.1.3 Project Type → Mode Mapping

| Project Type | Initial Mode | Skills Auto-Loaded |
|--------------|--------------|-------------------|
| `frontend` | Creative | `lab-frontend-design-systems`, `lab-creative-mode-operations`, brand skills |
| `contracts` | Secure | `lab-contract-lifecycle-management`, `lab-security-mode-operations`, `lib-hitl-gate-patterns` |
| `indexer` | Secure | `lab-envio-indexer-patterns`, `lab-thj-ecosystem-overview` |
| `game-design` | Creative | `lab-cubquests-game-design`, `lab-cubquests-visual-identity`, brand skills |
| `backend` | Creative | `lab-thj-ecosystem-overview`, `lib-orchestration-patterns` |
| `cross-domain` | Creative | All above + `lib-feedback-loop-design` |

---

### 3.2 Mode Manager

#### 3.2.1 Mode State File

**File**: `.claude/.mode`

```json
{
  "current_mode": "creative",
  "set_at": "2025-12-19T10:30:00Z",
  "project_type": "cross-domain",
  "mode_switches": []
}
```

#### 3.2.2 Mode Detection Rules (Phase-Based, v1)

| Phase | Mode Rule |
|-------|-----------|
| PRD (`/plan-and-analyze`) | Use project type setting |
| Architecture (`/architect`) | Use project type setting |
| Sprint Planning (`/sprint-plan`) | Use project type setting |
| Implementation (`/implement`) | Use project type setting |
| Review (`/review-sprint`) | Always Secure (code validation) |
| Audit (`/audit`, `/audit-sprint`) | Always Secure |
| Deploy (`/deploy-production`) | Always Secure |

#### 3.2.3 Mode Confirmation Flow

**Trigger**: Phase requires different mode than `current_mode`

```
┌─────────────────────────────────────────────┐
│ Mode mismatch detected                      │
│                                             │
│ Current mode: Creative                      │
│ Phase requires: Secure                      │
│                                             │
│ "You're about to enter a Secure mode phase. │
│  This adds HITL gates for approvals.        │
│  Switch to Secure mode?"                    │
│                                             │
│ [Yes, switch]  [Stay in Creative]           │
└─────────────────────────────────────────────┘
```

**Implementation**:

```markdown
## Mode Check (at phase start)

1. Read `.claude/.mode` for current mode
2. Determine required mode for this phase
3. If mismatch:
   - Show confirmation with benefits of switching
   - If confirmed: Update `.mode`, load appropriate skills
   - If declined: Proceed with warning
4. Log mode switch to `mode_switches` array
```

---

### 3.3 Context Injector

The context injector uses Hivemind's existing agent pattern for thorough, parallel research.

#### 3.3.1 Query Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CONTEXT INJECTION FLOW                           │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Phase Start (e.g., PRD)      │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Extract Keywords             │
              │  - From problem statement     │
              │  - From project type          │
              │  - From experiment context    │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Spawn Parallel Research      │
              │  Agents (Hivemind pattern)    │
              └───────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ @decision-    │   │ @timeline-    │   │ @technical-   │
│ archaeologist │   │ navigator     │   │ reference-    │
│               │   │               │   │ finder        │
│ Search ADRs   │   │ Search ERRs   │   │ Search docs   │
│ for keywords  │   │ experiments   │   │ ecosystem     │
└───────────────┘   └───────────────┘   └───────────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Synthesize Results           │
              │  - Deduplicate                │
              │  - Rank by relevance          │
              │  - Format for injection       │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Inject into Agent Prompt     │
              │                               │
              │  "Based on organizational     │
              │   context:                    │
              │   - ADR-042 establishes...    │
              │   - Previous experiment       │
              │     ERR-2024-XXX showed..."   │
              └───────────────────────────────┘
```

#### 3.3.2 Research Agent Pattern (from Hivemind `/ask`)

```markdown
## Parallel Research Agents

When context injection is needed, spawn these agents in parallel:

### @decision-archaeologist
Purpose: Find relevant ADRs
Search: `.hivemind/library/decisions/`
Pattern: Keywords from problem statement
Returns: List of relevant ADRs with summaries

### @timeline-navigator
Purpose: Find past experiments and events
Search: `.hivemind/library/timeline/`, `.hivemind/laboratory/`
Pattern: Similar experiment types
Returns: ERRs, experiment outcomes

### @technical-reference-finder
Purpose: Find architectural context
Search: `.hivemind/library/ecosystem/`, `.hivemind/library/knowledge/`
Pattern: Technical domain keywords
Returns: Relevant docs, Learning Memos

### @gap-tracker-agent (P1)
Purpose: Surface known gaps
Search: `.hivemind/library/timeline/GAP_TRACKER.md`
Pattern: Domain-related gaps
Returns: Relevant gaps to address
```

#### 3.3.3 Context Injection by Phase

| Phase | Context Sources | Injection Point |
|-------|-----------------|-----------------|
| PRD | ADRs, experiments, Learning Memos | Before discovery questions |
| Architecture | Ecosystem docs, contract registry, ADRs | Before design decisions |
| Sprint | Linear cycles, Knowledge Experts | Before task breakdown |
| Implementation | Domain skills, brand context, security patterns | Before coding |
| Review | Past audit findings, security Learning Memos | Before code review |

---

### 3.4 Candidate Surfacer

#### 3.4.1 Detection Patterns

**ADR Candidate Detection**:
```
Triggers:
- "We decided to use X instead of Y"
- "Choosing X over Y because Z"
- "After comparing, we selected X"
- Architecture phase decisions
- Trade-off discussions

Extraction:
- Decision statement
- Alternatives considered
- Rationale given
- Trade-offs mentioned
```

**Learning Candidate Detection**:
```
Triggers:
- "We discovered that X works better"
- "This pattern proved more effective"
- "Lesson learned: X"
- Implementation phase insights
- Review feedback patterns

Extraction:
- Pattern description
- Context/conditions
- Evidence (code refs, test results)
- Recommended application
```

#### 3.4.2 Surfacing Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CANDIDATE SURFACING FLOW                         │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Phase Execution              │
              │  (Agent generates content)    │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Batch Collection             │
              │  (During phase, accumulate    │
              │   decision/learning patterns) │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Phase End Trigger            │
              │  (e.g., SDD written)          │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Review Candidates            │
              │  Show summary to user:        │
              │  "Found 3 ADR candidates,     │
              │   2 Learning candidates"      │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  User Confirmation            │
              │  "Submit to Linear?"          │
              │  [Submit all] [Review first]  │
              │  [Skip for now]               │
              └───────────────────────────────┘
                              │ If submit
                              ▼
              ┌───────────────────────────────┐
              │  Create Linear Issues         │
              │  - Project: Product Home      │
              │  - Labels: adr-candidate      │
              │  - Template: filled           │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Continue to Next Phase       │
              │  (Non-blocking)               │
              └───────────────────────────────┘
```

#### 3.4.3 Linear Issue Templates

**ADR Candidate**:
```markdown
Title: [ADR-Candidate] {Decision Summary}
Project: {Product Home ID from integration-context.md}
Labels: adr-candidate, sprint:{current-sprint}, agent:architect

Body:
## [ADR-Candidate] {Decision Title}

**Source**: Loa Architecture Phase
**Sprint**: {sprint-name}
**Date**: {timestamp}

### Decision
{Extracted decision statement}

### Context
{Why this decision was needed - from SDD}

### Alternatives Considered
{Extracted from agent reasoning}

### Rationale
{Why this approach was chosen}

### Trade-offs
{Pros and cons mentioned}

### References
- Loa SDD: `loa-grimoire/sdd.md#{section}`
- Related ADRs: {links if referenced}

---
*Auto-surfaced by Loa. Review in biweekly Hivemind cycle.*
```

---

### 3.5 Skill Symlinker

#### 3.5.1 Symlink Creation

```bash
# During /setup, after Hivemind connection

SKILL_SOURCE=".hivemind/.claude/skills"
SKILL_TARGET=".claude/skills"

# Create target directory if needed
mkdir -p "$SKILL_TARGET"

# Symlink based on project type
case "$PROJECT_TYPE" in
  frontend)
    ln -sf "$SKILL_SOURCE/lab-frontend-design-systems" "$SKILL_TARGET/"
    ln -sf "$SKILL_SOURCE/lab-creative-mode-operations" "$SKILL_TARGET/"
    # Brand skills
    ln -sf "$SKILL_SOURCE/lab-cubquests-brand-identity" "$SKILL_TARGET/"
    ln -sf "$SKILL_SOURCE/lab-henlo-brand-identity" "$SKILL_TARGET/"
    ;;
  contracts)
    ln -sf "$SKILL_SOURCE/lab-contract-lifecycle-management" "$SKILL_TARGET/"
    ln -sf "$SKILL_SOURCE/lab-security-mode-operations" "$SKILL_TARGET/"
    ln -sf "$SKILL_SOURCE/lib-hitl-gate-patterns" "$SKILL_TARGET/"
    ;;
  # ... other project types
esac
```

#### 3.5.2 Symlink Validation

```bash
# On phase start, validate symlinks

validate_skills() {
    for skill in .claude/skills/*; do
        if [ -L "$skill" ]; then
            if [ ! -e "$skill" ]; then
                echo "Warning: Broken symlink $skill"
                # Attempt repair
                repair_symlink "$skill"
            fi
        fi
    done
}

repair_symlink() {
    local skill="$1"
    local name=$(basename "$skill")
    local source=".hivemind/.claude/skills/$name"

    if [ -d "$source" ]; then
        rm "$skill"
        ln -sf "$source" "$skill"
        echo "Repaired: $skill"
    else
        echo "Cannot repair: source not found"
    fi
}
```

#### 3.5.3 Skill Auto-Loading

Skills use the existing Hivemind pattern - they auto-activate based on keywords:

| Skill | Trigger Keywords |
|-------|-----------------|
| `lab-cubquests-game-design` | quest, badge, activity, xp |
| `lab-frontend-design-systems` | component, design system, UI |
| `lab-contract-lifecycle-management` | contract, deploy, audit |
| `lab-creative-mode-operations` | creative, iterate, explore |
| `lab-security-mode-operations` | secure, approver, gate |
| `lib-orchestration-patterns` | context, spawn, agent |

---

## 4. Data Flow

### 4.1 Complete Integration Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         COMPLETE DATA FLOW                          │
└─────────────────────────────────────────────────────────────────────┘

HIVEMIND SEED CYCLE
       │
       │ User Truth Canvases clustered
       ▼
┌──────────────────┐
│ Team Decision    │◄────── Biweekly review
│ "Let's try X"    │
└──────────────────┘
       │
       │ Experiment created in Linear
       ▼
┌──────────────────┐     ┌──────────────────┐
│ /setup           │────►│ integration-     │
│                  │     │ context.md       │
│ • Hivemind link  │     │ • Experiment ID  │
│ • Project type   │     │ • Product Home   │
│ • Skills loaded  │     │ • Mode: Creative │
└──────────────────┘     └──────────────────┘
       │
       ▼
┌──────────────────┐     ┌──────────────────┐
│ /plan-and-analyze│────►│ prd.md           │
│                  │     │                  │
│ Context injected:│     │ References:      │
│ • ADR-042        │     │ • ADR-042        │
│ • Past experiment│     │ • Experiment     │
└──────────────────┘     └──────────────────┘
       │
       ▼
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ /architect       │────►│ sdd.md           │────►│ Linear Issues    │
│                  │     │                  │     │                  │
│ Decisions made   │     │ Design documented│     │ [ADR-Candidate]  │
│ Surfacing batch  │     │                  │     │ Decision X       │
└──────────────────┘     └──────────────────┘     └──────────────────┘
       │
       ▼
┌──────────────────┐
│ /sprint-plan     │
│ /implement       │
│ /review-sprint   │
│                  │
│ Patterns found   │
│ Surfacing batch  │
└──────────────────┘
       │
       │ Learnings detected
       ▼
┌──────────────────┐
│ Linear Issues    │
│                  │
│ [Learning-       │
│  Candidate]      │
│ Pattern Y        │
└──────────────────┘
       │
       │ Ship & Measure
       ▼
┌──────────────────┐
│ FEEDBACK LOOP    │
│ • Usage data     │
│ • User feedback  │
└──────────────────┘
       │
       │ Biweekly review
       ▼
┌──────────────────┐
│ Team Reviews     │
│ Candidates       │
│                  │
│ • Approve ADRs   │
│ • Graduate       │
│   Learnings      │
└──────────────────┘
       │
       │ Graduates to Library
       ▼
┌──────────────────┐
│ HIVEMIND LIBRARY │
│                  │
│ • New ADRs       │
│ • Learning Memos │
│ • Updated ERRs   │
└──────────────────┘
       │
       │ Available for next cycle
       └────────────────────────────────────►
```

### 4.2 File I/O Summary

| Component | Reads | Writes |
|-----------|-------|--------|
| Setup | `../hivemind-library` existence, `.claude/settings.local.json` | `.hivemind` symlink, `.claude/.mode`, `integration-context.md`, `.loa-setup-complete` |
| Mode Manager | `.claude/.mode` | `.claude/.mode` (updates) |
| Context Injector | `.hivemind/library/*`, `integration-context.md` | (memory only, injects into agent) |
| Candidate Surfacer | Agent output (SDD, sprint reports) | Linear via MCP |
| Skill Symlinker | `.hivemind/.claude/skills/*` | `.claude/skills/*` symlinks |

---

## 5. API Contracts

### 5.1 Integration Context Schema

**File**: `loa-grimoire/a2a/integration-context.md`

```markdown
## Linear Integration

### Team Configuration
- **Team ID**: {uuid}
- **Project ID**: {uuid} (Product Home)

### Standard Labels
- `agent:implementer`, `agent:reviewer`, `agent:devops`, `agent:auditor`, `agent:planner`
- `type:feature`, `type:bugfix`, `type:refactor`, `type:infrastructure`, `type:security`, `type:audit-finding`, `type:planning`
- `priority:critical`, `priority:high`
- `sprint:sprint-N`
- `source:discord`, `source:internal`

## Hivemind Integration (NEW)

### Connection Status
- **Hivemind Path**: .hivemind → {resolved_path}
- **Connection Date**: {timestamp}
- **Status**: Connected | Disconnected | Not Configured

### Project Configuration
- **Project Type**: frontend | contracts | indexer | game-design | backend | cross-domain
- **Current Mode**: creative | secure

### Product Home (P1)
- **Project ID**: {uuid}
- **Project Name**: {name}
- **Product Labels**: Product → {label1}, Product → {label2}

### Linked Experiment (P1)
- **Experiment ID**: {Linear issue ID}
- **Hypothesis**: {text}
- **Success Criteria**: {text}
- **User Truth Canvas**: {link}

### Loaded Skills
- {skill-1}
- {skill-2}
- ...
```

### 5.2 Mode State Schema

**File**: `.claude/.mode`

```json
{
  "$schema": "mode-state-v1",
  "current_mode": "creative",
  "set_at": "2025-12-19T10:30:00Z",
  "project_type": "cross-domain",
  "mode_switches": [
    {
      "from": "creative",
      "to": "secure",
      "reason": "Entering review phase",
      "phase": "review-sprint",
      "timestamp": "2025-12-19T14:00:00Z",
      "confirmed": true
    }
  ]
}
```

### 5.3 Linear MCP Usage

**Creating ADR Candidate**:
```typescript
mcp__linear__create_issue({
  teamId: "{from integration-context.md}",
  title: "[ADR-Candidate] {decision summary}",
  projectId: "{Product Home ID}",
  labelIds: ["{adr-candidate-label-id}", "{sprint-label-id}"],
  description: "{ADR template filled}"
})
```

**Creating Learning Candidate**:
```typescript
mcp__linear__create_issue({
  teamId: "{from integration-context.md}",
  title: "[Learning-Candidate] {pattern summary}",
  projectId: "{Product Home ID}",
  labelIds: ["{learning-candidate-label-id}", "{sprint-label-id}"],
  description: "{Learning template filled}"
})
```

---

## 6. Error Handling

### 6.1 Graceful Degradation

| Failure | Impact | Fallback |
|---------|--------|----------|
| Hivemind symlink broken | No context injection | Loa proceeds without org context, logs warning |
| Skill symlink broken | Skill not loaded | Skip skill, log warning, attempt repair |
| Linear MCP unavailable | No candidate surfacing | Queue candidates, retry later, write to local file |
| Mode file corrupted | Mode state lost | Reset to project type default, log reset |
| Context query timeout | Delayed injection | Proceed without context, show "context unavailable" |

### 6.2 Error Messages

```markdown
## Warning: Hivemind Disconnected

The `.hivemind` symlink appears broken or missing.
Loa will continue without organizational context.

To reconnect: Run `/setup` and select "Connect to Hivemind OS"

---

## Warning: Skill Not Found

Skill `lab-cubquests-game-design` symlink is broken.
Attempting repair...

✓ Repaired successfully
  OR
✗ Could not repair. Run `/setup` to reconfigure skills.

---

## Notice: Linear Unavailable

Could not connect to Linear to submit candidates.
3 candidates saved locally to `loa-grimoire/pending-candidates.json`

Run `/setup` to check MCP configuration, then:
`/submit-candidates` to retry submission
```

---

## 7. Security Considerations

### 7.1 Gitignore Additions

```gitignore
# Hivemind Integration
.hivemind/                    # Symlink to org memory (not committed)
.claude/.mode                 # Mode state (per-developer)

# Existing Loa ignores
.loa-setup-complete
loa-grimoire/analytics/
```

### 7.2 Data Protection

| Data Type | Protection |
|-----------|------------|
| Hivemind content | Never committed, accessed via symlink only |
| Mode state | Local only, not shared between developers |
| Linear credentials | Via MCP, stored in `.claude/settings.local.json` |
| Candidate content | Sent to Linear only, not stored locally beyond session |

### 7.3 Access Control

- **Read-only Hivemind access**: Loa only reads from `.hivemind/library/` and `.hivemind/laboratory/`
- **No Hivemind writes**: Candidates go to Linear, not directly to Hivemind
- **Team reviews**: Human-in-the-loop for graduating candidates to Library

---

## 8. Testing Strategy

### 8.1 Unit Tests

| Component | Test Cases |
|-----------|------------|
| Symlink Creation | Valid path, invalid path, already exists, permission denied |
| Mode Manager | Read state, write state, detect mismatch, switch confirmed, switch declined |
| Context Injector | Keywords extraction, ADR search, result synthesis |
| Candidate Detection | ADR patterns, Learning patterns, false positives |

### 8.2 Integration Tests

| Flow | Validation |
|------|------------|
| Setup → Hivemind Connection | Symlink created, skills loaded, mode set |
| PRD → Context Injection | ADRs found, injected into prompt |
| Architecture → ADR Surfacing | Decisions detected, issues created |
| Mode Switch | Confirmation shown, skills reloaded |

### 8.3 Pilot Validation (CubQuests + Set & Forgetti)

| Criteria | Validation Method |
|----------|-------------------|
| Hivemind context in PRD | ADRs referenced in prd.md |
| Mode switching works | Mode file shows switches |
| ADR candidates surfaced | Linear issues exist |
| Learning candidates surfaced | Linear issues exist |
| Gap identified | Gap candidate or notepad entry |

---

## 9. Deployment Plan

### 9.1 Implementation Sprints

**Sprint 1: Foundation**
- Extended `/setup` with Hivemind connection
- Project type selection and mode initialization
- Basic skill symlink creation
- Mode state file management

**Sprint 2: Context Injection**
- Research agent spawning pattern
- ADR/experiment/Learning query implementation
- Context injection at PRD phase
- Fallback handling for disconnected state

**Sprint 3: Candidate Surfacing**
- ADR candidate pattern detection
- Learning candidate pattern detection
- Linear issue creation
- Batch review UX at phase end

**Sprint 4: Polish & Pilot**
- Skill validation and repair
- Mode confirmation UX
- Analytics integration
- CubQuests + Set & Forgetti pilot run

### 9.2 Rollout Strategy

1. **Internal testing**: Soju runs full Loa cycle with integration
2. **Pilot refinement**: Adjust based on friction points
3. **Team review**: Biweekly Hivemind cycle reviews pilot candidates
4. **Graduate learnings**: Document patterns discovered during pilot
5. **Wider rollout**: Enable for other THJ projects

---

## 10. Open Questions (Deferred)

1. **Agent Isolation**: Hivemind agents running in Loa context via symlinks vs separate invocation
2. **Brand Document Versioning**: How to handle updates mid-project
3. **GAP Candidate Maintenance**: Requires Hivemind improvements
4. **Claude Chrome Integration**: Design iteration patterns (P2)

---

## 11. Appendices

### A. Hivemind `/ask` Command Pattern Reference

The context query mechanism is modeled on Hivemind's `/ask` command:

```markdown
## Question Classification

1. Historical: "What did we decide about X?"
2. Status: "What's the current state of X?"
3. Comparative: "How does X relate to Y?"
4. Exploratory: "What do we know about X?"

## Agent Spawning

For thorough research, spawn parallel agents:
- @product-researcher: Product context
- @decision-archaeologist: ADRs
- @timeline-navigator: ERRs, experiments
- @people-entity-resolver: Team expertise
- @technical-reference-finder: Docs, specs
- @gap-tracker-agent: Known gaps
- @linear-context-explorer: Linear state
- @analytics-explorer: Usage data

## Synthesis

Combine results into coherent answer with:
- Primary findings
- Supporting evidence
- Confidence level
- Gaps identified
```

### B. Skill Categories Reference

| Category | Skills | Auto-Load Keywords |
|----------|--------|-------------------|
| **Governance** | `lib-source-fidelity-application`, `lib-orchestration-patterns`, `lib-adr-surfacing`, `lib-feedback-loop-design`, `lib-hitl-gate-patterns` | verify, context, decision, feedback, gate |
| **Game Design** | `lab-cubquests-game-design`, `lab-cubquests-visual-identity` | quest, badge, activity |
| **Frontend** | `lab-frontend-design-systems`, brand identity skills | component, design system, UI |
| **Infrastructure** | `lab-envio-indexer-patterns`, `lab-contract-lifecycle-management`, `lab-thj-ecosystem-overview` | contract, indexer, deploy |
| **Execution** | `lab-creative-mode-operations`, `lab-security-mode-operations` | creative, secure |

---

*Document generated by Architecture Designer Agent*
*Based on PRD v2.0 and architecture decisions from discovery phase*
