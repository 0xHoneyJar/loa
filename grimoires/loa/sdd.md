# Software Design Document: Compound Learning System

**Version:** 1.0  
**Date:** 2025-01-30  
**Author:** Architecture Agent  
**Status:** Draft  
**PRD Reference:** `grimoires/loa/prd.md`

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [System Architecture](#system-architecture)
3. [Component Design](#component-design)
4. [Data Architecture](#data-architecture)
5. [API Specifications](#api-specifications)
6. [Command Specifications](#command-specifications)
7. [Algorithm Design](#algorithm-design)
8. [Error Handling Strategy](#error-handling-strategy)
9. [Testing Strategy](#testing-strategy)
10. [Development Phases](#development-phases)
11. [Risks & Mitigation](#risks--mitigation)
12. [Open Questions](#open-questions)

---

## Executive Summary

This document specifies the technical architecture for the Compound Learning System, extending Loa's existing continuous learning infrastructure to enable cross-session pattern detection, batch retrospectives, and an apply-verify feedback loop.

### Design Principles

1. **Zone Compliance**: All writes to State Zone (`grimoires/loa/`)
2. **Offline-First**: No external API dependencies
3. **Incremental Extension**: Build on existing trajectory/skill infrastructure
4. **Human Oversight**: AGENTS.md changes require approval
5. **Streaming Analysis**: Handle large log files without memory exhaustion

### Technology Stack

| Component | Technology | Version | Rationale |
|-----------|------------|---------|-----------|
| Runtime | Bash + Claude Code | N/A | Native to Loa execution environment |
| Data Format | JSONL | N/A | Existing trajectory format, streaming-friendly |
| Pattern Matching | Layered (see below) | N/A | Use best available tool, graceful fallback |
| Similarity | ck / Memory Stack / Jaccard | N/A | Semantic when available, keyword fallback |
| Storage | Filesystem | N/A | Portable, no database required |

### Semantic Search Integration

The Compound Learning System uses a **layered similarity strategy** that leverages Loa's optional semantic tools when available, with graceful fallback to keyword-based matching.

#### Available Tools

| Tool | Purpose | Detection | Fallback |
|------|---------|-----------|----------|
| **ck** | Code semantic search | `which ck` | grep patterns |
| **Memory Stack** | Text embeddings (sentence-transformers) | `.loa.config.yaml: memory.enabled` | Jaccard similarity |
| **qmd** | Grimoire/skill search (BM25 + vector + rerank) | `which qmd` | grep + keyword match |

#### Similarity Resolution Order

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SIMILARITY STRATEGY                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  FOR CODE-RELATED PATTERNS:                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                     │
│  │ ck avail?│─YES─▶│ck --hybrid│    │ Semantic │                     │
│  │          │      │ search   │────▶│ similarity│                    │
│  └────┬─────┘     └──────────┘     └──────────┘                     │
│       │ NO                                                           │
│       ▼                                                              │
│  ┌──────────┐     ┌──────────┐                                      │
│  │ grep +   │────▶│ Keyword  │                                      │
│  │ patterns │     │ Jaccard  │                                      │
│  └──────────┘     └──────────┘                                      │
│                                                                      │
│  FOR LEARNING/SKILL SIMILARITY:                                      │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                     │
│  │ Memory   │─YES─▶│ Embed    │────▶│ Cosine   │                     │
│  │ Stack?   │      │ texts    │     │ similarity│                    │
│  └────┬─────┘     └──────────┘     └──────────┘                     │
│       │ NO                                                           │
│       ▼                                                              │
│  ┌──────────┐     ┌──────────┐                                      │
│  │ Keyword  │────▶│ Jaccard  │                                      │
│  │ extract  │     │ > 0.6    │                                      │
│  └──────────┘     └──────────┘                                      │
│                                                                      │
│  FOR GRIMOIRE/NOTES SEARCH:                                          │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐                     │
│  │qmd avail?│─YES─▶│qmd_query │────▶│ Ranked   │                     │
│  │          │      │ (hybrid) │     │ results  │                     │
│  └────┬─────┘     └──────────┘     └──────────┘                     │
│       │ NO                                                           │
│       ▼                                                              │
│  ┌──────────┐     ┌──────────┐                                      │
│  │ grep -r  │────▶│ Pattern  │                                      │
│  │ grimoires│     │ match    │                                      │
│  └──────────┘     └──────────┘                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

#### Configuration

```yaml
# .loa.config.yaml
compound_learning:
  similarity:
    # Prefer semantic tools when available
    prefer_semantic: true
    
    # ck integration for code patterns
    ck:
      enabled: auto  # auto | true | false
      threshold: 0.7
      
    # Memory Stack integration for text embeddings  
    memory_stack:
      enabled: auto  # auto | true | false
      model: all-MiniLM-L6-v2
      threshold: 0.35
      
    # qmd integration for grimoire search
    qmd:
      enabled: auto  # auto | true | false
      search_mode: hybrid  # hybrid | semantic | keyword
      
    # Fallback settings
    fallback:
      jaccard_threshold: 0.6
      min_keyword_overlap: 3
```

#### Tool Detection Script

```bash
#!/bin/bash
# .claude/scripts/detect-semantic-tools.sh

detect_semantic_tools() {
  local tools=()
  
  # Check ck
  if command -v ck &> /dev/null; then
    tools+=("ck")
  fi
  
  # Check Memory Stack
  if python3 -c "import sentence_transformers" 2>/dev/null; then
    if yq -e '.memory.enabled' .loa.config.yaml 2>/dev/null | grep -q true; then
      tools+=("memory_stack")
    fi
  fi
  
  # Check qmd
  if command -v qmd &> /dev/null; then
    tools+=("qmd")
  fi
  
  echo "${tools[@]}"
}

# Export for use in compound learning scripts
export SEMANTIC_TOOLS=$(detect_semantic_tools)
```

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        COMPOUND LEARNING SYSTEM                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌───────────┐ │
│  │  Trajectory │     │   Pattern   │     │   Skill     │     │  NOTES.md │ │
│  │    Logs     │────▶│  Detector   │────▶│  Generator  │────▶│ /AGENTS.md│ │
│  │   (JSONL)   │     │   Engine    │     │   Engine    │     │  Updates  │ │
│  └─────────────┘     └──────┬──────┘     └──────┬──────┘     └───────────┘ │
│                             │                   │                          │
│                             ▼                   ▼                          │
│                      ┌─────────────┐     ┌─────────────┐                   │
│                      │  Pattern    │     │  Learning   │                   │
│                      │  Candidates │     │  Registry   │                   │
│                      │  (JSON)     │     │  (JSON)     │                   │
│                      └─────────────┘     └─────────────┘                   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                      FEEDBACK LOOP SUBSYSTEM                            ││
│  │  ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐      ││
│  │  │  Apply   │────▶│  Track   │────▶│  Verify  │────▶│ Reinforce│      ││
│  │  │ Learning │     │ Usage    │     │ Outcome  │     │ /Demote  │      ││
│  │  └──────────┘     └──────────┘     └──────────┘     └──────────┘      ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Zone Architecture (Three-Zone Model)

> From PRD: "Must maintain Zone compliance (all writes to State Zone)" (prd.md:L99)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            ZONE COMPLIANCE MAP                                │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                               │
│  SYSTEM ZONE (.claude/)                    READ ONLY                          │
│  ├── skills/continuous-learning/           Source skill definition            │
│  ├── commands/retrospective.md             Extend with --batch                │
│  ├── protocols/continuous-learning.md      Quality gate criteria              │
│  └── scripts/                              Helper scripts (read)              │
│                                                                               │
│  STATE ZONE (grimoires/loa/)               READ/WRITE ← ALL OUTPUTS           │
│  ├── NOTES.md                              Session continuity + learnings     │
│  ├── a2a/trajectory/*.jsonl                Append new event types             │
│  ├── a2a/compound/                         NEW: Compound learning state       │
│  │   ├── patterns.json                     Detected patterns registry         │
│  │   ├── learnings.json                    Learning effectiveness tracking    │
│  │   ├── synthesis-queue.json              Pending AGENTS.md proposals        │
│  │   └── review-markers/                   Phase completion markers           │
│  ├── skills-pending/                       New compound skills                │
│  ├── skills/                               Approved skills                    │
│  └── skills-archived/                      Deprecated/merged skills           │
│                                                                               │
│  APP ZONE (src/, lib/, app/)               READ ONLY                          │
│  └── (No compound learning writes)                                            │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                         COMPOUND LEARNING FLOW                                  │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  Phase 1: COMPOUND REVIEW (nightly, 22:30)                                     │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐     │
│  │ Collect │───▶│ Analyze │───▶│ Detect  │───▶│ Extract │───▶│ Write   │     │
│  │ Trajec- │    │ Events  │    │ Patterns│    │Learnings│    │ Marker  │     │
│  │ tories  │    │         │    │         │    │         │    │         │     │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘     │
│                                                                                 │
│  Phase 2: COMPOUND SHIP (nightly, 23:00)                                       │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐     │
│  │ Check   │───▶│ Load    │───▶│ Select  │───▶│ Execute │───▶│ Create  │     │
│  │ Marker  │    │Learnings│    │ Task    │    │ /run    │    │ PR      │     │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘    └─────────┘     │
│                                                                                 │
│  Phase 3: FEEDBACK LOOP (during implementation)                                │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐                    │
│  │ Match   │───▶│ Apply   │───▶│ Track   │───▶│ Verify  │                    │
│  │Learnings│    │ in Code │    │ Usage   │    │ Outcome │                    │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘                    │
│                                                                                 │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Design

### Component 1: Batch Retrospective Engine

**Purpose**: Extends `/retrospective` to analyze trajectory logs across multiple sessions.

**Interface**:
```bash
/retrospective --batch [--days N] [--sprint N] [--output json|markdown]
```

**Input Sources**:
```
grimoires/loa/a2a/trajectory/*.jsonl     # All trajectory logs
grimoires/loa/skills/                    # Existing skills (for dedup)
grimoires/loa/NOTES.md                   # Existing learnings (for dedup)
```

**Output Targets**:
```
grimoires/loa/a2a/compound/patterns.json      # Detected patterns
grimoires/loa/skills-pending/{name}/SKILL.md  # New compound skills
grimoires/loa/a2a/trajectory/compound-*.jsonl # Audit trail
```

**State Diagram**:
```
[IDLE] ─────▶ [COLLECTING] ─────▶ [ANALYZING] ─────▶ [DETECTING]
                   │                    │                 │
                   │                    │                 ▼
                   │                    │          [QUALITY_GATES]
                   │                    │                 │
                   │                    │                 ▼
                   │                    │          [EXTRACTING]
                   │                    │                 │
                   ▼                    ▼                 ▼
              [ERROR]              [ERROR]           [COMPLETE]
```

**Internal Components**:

| Sub-Component | Responsibility | Input | Output |
|---------------|----------------|-------|--------|
| TrajectoryCollector | Gather JSONL files by date range | Date range | Event stream |
| EventParser | Parse and normalize events | JSONL lines | Typed events |
| PatternMatcher | Find recurring patterns | Event stream | Pattern candidates |
| QualityGate | Apply 4-gate filter | Candidates | Qualified patterns |
| SkillGenerator | Create skill markdown | Qualified patterns | Skill files |

### Component 2: Cross-Session Pattern Detector

**Purpose**: Core algorithm identifying patterns that span multiple sessions.

> From PRD: "Identifies repeated error→solution pairs across sessions" (prd.md:L166)

**Architecture**:
```
┌────────────────────────────────────────────────────────────────────┐
│                    PATTERN DETECTOR ENGINE                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐          │
│  │  Keyword    │     │  Signature  │     │  Clustering │          │
│  │  Extractor  │────▶│  Generator  │────▶│   Engine    │          │
│  └─────────────┘     └─────────────┘     └─────────────┘          │
│         │                   │                   │                  │
│         ▼                   ▼                   ▼                  │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐          │
│  │ Error Terms │     │ Event Sig   │     │  Clusters   │          │
│  │ Solution    │     │ (hash)      │     │ (similar    │          │
│  │ Terms       │     │             │     │  events)    │          │
│  └─────────────┘     └─────────────┘     └─────────────┘          │
│                                                 │                  │
│                                                 ▼                  │
│                                          ┌─────────────┐          │
│                                          │  Pattern    │          │
│                                          │  Candidates │          │
│                                          └─────────────┘          │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

**Pattern Types Detected**:

| Pattern Type | Detection Method | Example |
|--------------|------------------|---------|
| Repeated Error | Same error signature, same fix | NATS reconnection 5 times |
| Convergent Solution | Different errors, same solution | Multiple paths → durable consumer |
| Anti-Pattern | Repeated mistake before fix | Forgot `await` 3 times |
| Project Convention | Same approach across contexts | Always use `errorBoundary` wrapper |

**Similarity Algorithm** (Layered: Semantic → Keyword fallback):

```python
def calculate_similarity(event_a, event_b, semantic_tools=None):
    """
    Layered similarity using best available tool.
    Returns 0.0-1.0 similarity score.
    
    Priority:
    1. Memory Stack (sentence-transformers) if available
    2. ck (for code-related events) if available  
    3. Jaccard keyword fallback
    """
    semantic_tools = semantic_tools or detect_semantic_tools()
    
    # For code-related events, prefer ck
    if is_code_event(event_a) and 'ck' in semantic_tools:
        return ck_similarity(event_a, event_b)
    
    # For text/learning similarity, prefer Memory Stack
    if 'memory_stack' in semantic_tools:
        return embedding_similarity(event_a, event_b)
    
    # Fallback: Jaccard on keywords
    return jaccard_similarity(event_a, event_b)


def ck_similarity(event_a, event_b):
    """
    Use ck --hybrid for code semantic similarity.
    Extracts code snippets and compares via ck index.
    """
    # Extract code references from events
    code_a = extract_code_refs(event_a)
    code_b = extract_code_refs(event_b)
    
    # Use ck to find semantic similarity
    result = subprocess.run(
        ['ck', '--hybrid', '--threshold', '0.7', code_a],
        capture_output=True, text=True
    )
    
    # Check if code_b appears in similar results
    return 1.0 if code_b in result.stdout else 0.0


def embedding_similarity(event_a, event_b):
    """
    Use sentence-transformers for text embedding similarity.
    Leverages Memory Stack if configured.
    """
    from sentence_transformers import SentenceTransformer
    
    model = SentenceTransformer('all-MiniLM-L6-v2')
    
    text_a = event_a.error + " " + event_a.solution
    text_b = event_b.error + " " + event_b.solution
    
    embeddings = model.encode([text_a, text_b])
    
    # Cosine similarity
    from numpy import dot
    from numpy.linalg import norm
    return dot(embeddings[0], embeddings[1]) / (norm(embeddings[0]) * norm(embeddings[1]))


def jaccard_similarity(event_a, event_b):
    """
    Fallback: Jaccard similarity on extracted keywords.
    """
    keywords_a = extract_keywords(event_a.error + event_a.solution)
    keywords_b = extract_keywords(event_b.error + event_b.solution)
    
    intersection = len(keywords_a & keywords_b)
    union = len(keywords_a | keywords_b)
    
    return intersection / union if union > 0 else 0.0
```

**Clustering Configuration**:
```yaml
pattern_detection:
  # Thresholds vary by tool
  similarity_threshold:
    ck: 0.7              # Higher threshold for semantic
    memory_stack: 0.35   # sentence-transformers typical
    jaccard: 0.6         # Keyword overlap
  min_occurrences: 2     # Minimum times seen to be a pattern
  max_age_days: 90       # Ignore patterns older than this
  exclude_agents: []     # Agents to exclude from analysis
```

### Component 3: Learning Application Tracker

**Purpose**: Track when and how learnings are applied during implementation.

> From PRD: "Log `learning_applied` events to trajectory" (prd.md:L177)

**Event Schema**:
```json
{
  "timestamp": "2025-01-30T10:30:00Z",
  "type": "learning_applied",
  "agent": "implementing-tasks",
  "skill_id": "nats-jetstream-consumer-durable",
  "task_context": "sprint-4-task-2",
  "application_type": "explicit",
  "confidence": 0.9,
  "code_location": "src/services/messaging.ts:L45"
}
```

**Application Types**:

| Type | Description | Detection Method |
|------|-------------|------------------|
| `explicit` | Agent referenced skill by name | String match in response |
| `implicit` | Agent used pattern without reference | Code similarity analysis |
| `prompted` | Morning context suggested skill | User accepted suggestion |

**Integration Points**:
- `/implement` phase: Automatic tracking
- `/ride` mode: Track during codebase exploration
- Morning context: Track acceptance/dismissal

### Component 4: Effectiveness Feedback Loop

**Purpose**: Verify whether applied learnings actually helped.

> From PRD: "Define 'helped' signals: task completed faster, fewer errors, no revert" (prd.md:L186)

**Feedback Signals**:

| Signal | Weight | Detection |
|--------|--------|-----------|
| Task completed | +3 | Task status in trajectory |
| No errors during task | +2 | Absence of error events |
| No revert of changes | +2 | Git history check |
| Task completed faster | +1 | Compare to similar tasks |
| User positive feedback | +3 | Explicit `/feedback` command |
| User negative feedback | -5 | Explicit `/feedback` command |

**Learning Score Calculation**:
```python
def calculate_effectiveness(learning_id):
    """
    Returns effectiveness score 0-100.
    Used for retrieval ranking and pruning decisions.
    """
    applications = get_applications(learning_id)
    
    total_score = 0
    for app in applications:
        signals = get_feedback_signals(app.task_id)
        weighted_sum = sum(s.weight * s.value for s in signals)
        total_score += weighted_sum
    
    # Normalize to 0-100
    max_possible = len(applications) * 11  # Max positive signals
    return int((total_score / max_possible) * 100) if applications else 50
```

**Effectiveness Tiers**:

| Score | Tier | Action |
|-------|------|--------|
| 80-100 | High | Increase retrieval priority |
| 50-79 | Medium | Normal retrieval |
| 20-49 | Low | Flag for review |
| 0-19 | Ineffective | Queue for pruning |

### Component 5: Learning Synthesis Engine

**Purpose**: Consolidate related skills into AGENTS.md guidance.

> From PRD: "Cluster related skills by semantic similarity... Human approval workflow" (prd.md:L195-197)

**Architecture**:
```
┌────────────────────────────────────────────────────────────────────┐
│                    SYNTHESIS ENGINE                                 │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Input: 3+ related skills                                          │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ skill-a: NATS reconnection handling                          │  │
│  │ skill-b: NATS JetStream durability                           │  │
│  │ skill-c: NATS consumer patterns                              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            │                                       │
│                            ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ CLUSTERING: Jaccard(keywords) > 0.4                          │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            │                                       │
│                            ▼                                       │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ SYNTHESIS: Extract common pattern + specific applications    │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                            │                                       │
│                            ▼                                       │
│  Output: AGENTS.md proposal                                        │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ "## NATS Best Practices                                      │  │
│  │ When using NATS in this codebase:                            │  │
│  │ - Always use durable consumers for persistent state          │  │
│  │ - Configure explicit reconnection handlers                   │  │
│  │ - See skills/nats-* for implementation details"              │  │
│  └─────────────────────────────────────────────────────────────┘  │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

**Proposal Format** (stored in `synthesis-queue.json`):
```json
{
  "id": "synth-2025-01-30-001",
  "created": "2025-01-30T10:00:00Z",
  "status": "pending",
  "source_skills": [
    "nats-reconnection-handling",
    "nats-jetstream-durability",
    "nats-consumer-patterns"
  ],
  "proposed_text": "## NATS Best Practices\n...",
  "target_file": "AGENTS.md",
  "target_section": "## Technical Conventions",
  "confidence": 0.85,
  "evidence": {
    "skill_count": 3,
    "total_applications": 12,
    "average_effectiveness": 78
  }
}
```

**Human Approval Workflow**:
```
┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐
│ Pending │───▶│ Review  │───▶│ Approve/│───▶│ Applied/│
│         │    │ Prompt  │    │ Modify/ │    │ Rejected│
│         │    │         │    │ Reject  │    │         │
└─────────┘    └─────────┘    └─────────┘    └─────────┘
```

### Component 6: Morning Context Loader

**Purpose**: Load relevant learnings at session start.

> From PRD: "Overhead < 5 seconds" (prd.md:L209)

**Algorithm**:
```python
def load_morning_context(task_context):
    """
    Returns max 5 most relevant learnings for current task.
    Must complete in < 5 seconds.
    """
    # 1. Extract task keywords (50ms)
    task_keywords = extract_keywords(task_context)
    
    # 2. Query learning registry (100ms)
    candidates = query_learnings(
        keywords=task_keywords,
        min_effectiveness=50,
        max_age_days=30
    )
    
    # 3. Rank by relevance × effectiveness (50ms)
    ranked = sorted(candidates, 
                    key=lambda l: l.relevance * l.effectiveness,
                    reverse=True)
    
    # 4. Return top 5 (immediate)
    return ranked[:5]
```

**Output Format** (presented to agent):
```markdown
📚 **Before you begin...**

Based on yesterday's work and this task's context, consider:

1. **[HIGH]** NATS JetStream consumer durability
   → Always use durable consumers for restart persistence
   
2. **[MED]** TypeScript strict mode edge cases
   → Check `strictNullChecks` behavior with optional chaining

Apply these learnings? [Y/n/select]
```

---

## Data Architecture

### Directory Structure

```
grimoires/loa/
├── NOTES.md                          # Session continuity (existing)
├── prd.md                            # Product requirements
├── sdd.md                            # This document
├── a2a/
│   ├── trajectory/                   # Existing trajectory logs
│   │   ├── implementing-tasks-2025-01-30.jsonl
│   │   ├── compound-learning-2025-01-30.jsonl  # NEW
│   │   └── ...
│   └── compound/                     # NEW: Compound learning state
│       ├── patterns.json             # Detected patterns registry
│       ├── learnings.json            # Learning effectiveness tracking
│       ├── synthesis-queue.json      # Pending AGENTS.md proposals
│       ├── config.json               # Runtime configuration
│       └── review-markers/           # Phase completion markers
│           └── .loa-review-complete-2025-01-30
├── skills/                           # Active skills (existing)
├── skills-pending/                   # Pending approval (existing)
└── skills-archived/                  # Archived skills (existing)
```

### Schema: patterns.json

```json
{
  "version": "1.0",
  "last_updated": "2025-01-30T10:00:00Z",
  "patterns": [
    {
      "id": "pat-001",
      "type": "repeated_error",
      "signature": "nats-consumer-lost-messages",
      "first_seen": "2025-01-15T08:00:00Z",
      "last_seen": "2025-01-29T14:00:00Z",
      "occurrence_count": 5,
      "sessions": ["2025-01-15", "2025-01-18", "2025-01-22", "2025-01-25", "2025-01-29"],
      "error_keywords": ["NATS", "consumer", "messages", "lost", "restart"],
      "solution_keywords": ["durable", "consumer", "name", "persist"],
      "confidence": 0.92,
      "extracted_to_skill": "nats-jetstream-consumer-durable",
      "status": "active"
    }
  ]
}
```

### Schema: learnings.json

```json
{
  "version": "1.0",
  "last_updated": "2025-01-30T10:00:00Z",
  "learnings": [
    {
      "id": "nats-jetstream-consumer-durable",
      "source": "pattern",
      "source_pattern_id": "pat-001",
      "created": "2025-01-29T15:00:00Z",
      "effectiveness_score": 78,
      "applications": [
        {
          "timestamp": "2025-01-30T09:00:00Z",
          "task_id": "sprint-4-task-2",
          "type": "explicit",
          "outcome": "success",
          "feedback_signals": {
            "task_completed": true,
            "no_errors": true,
            "no_revert": true
          }
        }
      ],
      "retrieval_count": 12,
      "last_retrieved": "2025-01-30T09:00:00Z"
    }
  ]
}
```

### Schema: synthesis-queue.json

```json
{
  "version": "1.0",
  "proposals": [
    {
      "id": "synth-2025-01-30-001",
      "status": "pending",
      "created": "2025-01-30T10:00:00Z",
      "source_skills": ["skill-a", "skill-b", "skill-c"],
      "proposed_text": "## Section Title\n\nContent here...",
      "target_file": "AGENTS.md",
      "target_section": "## Technical Conventions",
      "confidence": 0.85,
      "reviewed_at": null,
      "review_decision": null,
      "review_notes": null
    }
  ]
}
```

### Trajectory Event Types (New)

| Event Type | Purpose | Trigger |
|------------|---------|---------|
| `compound_review_start` | Batch review began | `/compound-review` |
| `compound_review_complete` | Batch review finished | `/compound-review` |
| `pattern_detected` | New cross-session pattern | Pattern detector |
| `learning_extracted` | Compound skill created | Quality gates pass |
| `learning_applied` | Skill used in task | Implementation |
| `learning_verified` | Feedback received | Task completion |
| `synthesis_proposed` | AGENTS.md update queued | Synthesis engine |
| `synthesis_approved` | Proposal accepted | Human approval |
| `synthesis_rejected` | Proposal rejected | Human decision |

### Review Marker Format

**File**: `grimoires/loa/a2a/compound/review-markers/.loa-review-complete-YYYY-MM-DD`

```json
{
  "timestamp": "2025-01-30T22:45:00Z",
  "review_type": "nightly",
  "days_analyzed": 1,
  "patterns_detected": 3,
  "learnings_extracted": 2,
  "trajectory_log": "compound-learning-2025-01-30.jsonl"
}
```

---

## API Specifications

### Internal APIs

These are function signatures for the compound learning components.

#### TrajectoryReader API

```typescript
interface TrajectoryReader {
  /**
   * Stream trajectory events within date range.
   * Uses JSONL streaming to handle large files.
   */
  streamEvents(options: {
    startDate: Date;
    endDate: Date;
    agents?: string[];
    eventTypes?: string[];
  }): AsyncIterator<TrajectoryEvent>;
  
  /**
   * Get summary statistics for date range.
   */
  getSummary(startDate: Date, endDate: Date): TrajectorySummary;
}
```

#### PatternDetector API

```typescript
interface PatternDetector {
  /**
   * Detect patterns from event stream.
   * Returns candidates meeting similarity threshold.
   */
  detectPatterns(events: TrajectoryEvent[]): PatternCandidate[];
  
  /**
   * Calculate similarity between two events.
   */
  calculateSimilarity(a: TrajectoryEvent, b: TrajectoryEvent): number;
  
  /**
   * Cluster similar events into pattern groups.
   */
  clusterEvents(events: TrajectoryEvent[], threshold: number): EventCluster[];
}
```

#### LearningRegistry API

```typescript
interface LearningRegistry {
  /**
   * Register a new learning from pattern detection.
   */
  register(learning: Learning): string;
  
  /**
   * Query learnings by keyword relevance.
   */
  query(options: {
    keywords: string[];
    minEffectiveness?: number;
    maxAgeDays?: number;
    limit?: number;
  }): Learning[];
  
  /**
   * Record learning application.
   */
  recordApplication(learningId: string, application: LearningApplication): void;
  
  /**
   * Update effectiveness score after feedback.
   */
  updateEffectiveness(learningId: string, signals: FeedbackSignals): void;
}
```

#### SynthesisEngine API

```typescript
interface SynthesisEngine {
  /**
   * Find clusters of related skills.
   */
  findClusters(skills: Skill[], minClusterSize: number): SkillCluster[];
  
  /**
   * Generate AGENTS.md proposal from cluster.
   */
  generateProposal(cluster: SkillCluster): SynthesisProposal;
  
  /**
   * Apply approved proposal to target file.
   */
  applyProposal(proposalId: string, modifications?: string): void;
}
```

---

## Command Specifications

### Command: `/retrospective --batch`

**Extension of existing `/retrospective` command.**

```
Usage: /retrospective --batch [options]

Options:
  --days N        Analyze last N days (default: 7)
  --sprint N      Analyze sprint N (overrides --days)
  --output FORMAT Output format: markdown (default) or json
  --dry-run       Show what would be extracted without writing
  --min-confidence N  Minimum pattern confidence (default: 0.6)
  --force         Skip confirmation prompts

Examples:
  /retrospective --batch --days 14
  /retrospective --batch --sprint 3 --output json
  /retrospective --batch --dry-run
```

**Workflow**:
```
1. COLLECT: Gather trajectory files for date range
2. PARSE: Stream events, extract error/solution pairs
3. DETECT: Run pattern detection algorithm
4. GATE: Apply quality gates to each pattern
5. PRESENT: Show findings with confidence scores
6. CONFIRM: Get user approval (unless --force)
7. EXTRACT: Write approved patterns to skills-pending/
8. LOG: Write compound-learning trajectory events
```

### Command: `/compound-review`

**New command for Phase 1 of compound cycle.**

> From PRD FR-1: "This is Phase 1 of the two-phase compound cycle" (prd.md:L134)

```
Usage: /compound-review [options]

Options:
  --days N        Lookback window (default: 1 for nightly use)
  --full          Full synthesis including AGENTS.md proposals
  --skip-marker   Don't write completion marker

Output:
  - Updates NOTES.md ## Learnings section
  - Writes to grimoires/loa/a2a/compound/patterns.json
  - Creates .loa-review-complete marker
  - Logs to trajectory
```

### Command: `/compound-ship`

**New command for Phase 2 of compound cycle.**

> From PRD FR-7: "Autonomously implements the next priority item" (prd.md:L216)

```
Usage: /compound-ship [options]

Options:
  --priority ITEM   Specific item to implement
  --dry-run         Preview without execution
  --max-attempts N  Max iteration attempts (default: 25)
  --skip-marker     Don't require review marker

Workflow:
  1. Check for .loa-review-complete marker
  2. Load fresh learnings from NOTES.md
  3. Select priority item from backlog (or --priority)
  4. Create feature branch: feature/{priority-slug}
  5. Execute: /plan-and-analyze → /architect → /sprint-plan → /run
  6. Create draft PR on success
```

### Command: `/compound`

**Unified orchestration command.**

```
Usage: /compound [options]

Options:
  --review-only   Just extract learnings, skip ship
  --ship-only     Skip review, use existing learnings
  --force         Run ship even without review marker
  --gap-minutes N Minutes between phases (default: 30)

Default behavior:
  1. Run /compound-review
  2. Wait gap-minutes
  3. Run /compound-ship
```

### Command: `/synthesize-learnings`

**Manual trigger for synthesis engine.**

```
Usage: /synthesize-learnings [options]

Options:
  --min-cluster N   Minimum skills per cluster (default: 3)
  --threshold N     Similarity threshold (default: 0.4)
  --dry-run         Show proposals without queuing
  --approve ID      Approve pending proposal

Output:
  - Queues proposals to synthesis-queue.json
  - Presents proposals for human review
```

---

## Algorithm Design

### Algorithm 1: Keyword Extraction

**Purpose**: Extract meaningful terms from error messages and solutions.

```python
def extract_keywords(text: str) -> set[str]:
    """
    Extract meaningful keywords from text.
    Filters stopwords, normalizes, and deduplicates.
    """
    # Tokenize
    tokens = re.findall(r'\b[a-zA-Z][a-zA-Z0-9_-]+\b', text.lower())
    
    # Filter stopwords
    stopwords = {'the', 'a', 'an', 'is', 'was', 'were', 'be', 'been', 
                 'being', 'have', 'has', 'had', 'do', 'does', 'did',
                 'will', 'would', 'could', 'should', 'may', 'might',
                 'must', 'can', 'to', 'of', 'in', 'for', 'on', 'with',
                 'at', 'by', 'from', 'as', 'into', 'through', 'during',
                 'before', 'after', 'above', 'below', 'between', 'under',
                 'again', 'further', 'then', 'once', 'here', 'there',
                 'when', 'where', 'why', 'how', 'all', 'each', 'few',
                 'more', 'most', 'other', 'some', 'such', 'no', 'nor',
                 'not', 'only', 'own', 'same', 'so', 'than', 'too',
                 'very', 'just', 'also', 'now', 'and', 'but', 'or', 'if',
                 'because', 'until', 'while', 'although', 'this', 'that',
                 'these', 'those', 'it', 'its'}
    
    filtered = [t for t in tokens if t not in stopwords and len(t) > 2]
    
    # Technical term boost (keep as-is)
    # Common patterns: camelCase, snake_case, kebab-case
    
    return set(filtered)
```

### Algorithm 2: Pattern Similarity (Layered)

**Purpose**: Calculate similarity between two trajectory events using best available tool.

> See: [Semantic Search Integration](#semantic-search-integration) for tool detection and fallback logic.

**Layered Resolution**:

```python
def pattern_similarity(event_a: Event, event_b: Event) -> float:
    """
    Layered similarity: semantic tools → keyword fallback.
    
    Resolution order:
    1. ck (code events) → threshold 0.7
    2. Memory Stack (text) → threshold 0.35  
    3. Jaccard (fallback) → threshold 0.6
    """
    tools = detect_semantic_tools()
    
    # Code patterns: prefer ck
    if is_code_event(event_a) and 'ck' in tools:
        return ck_hybrid_similarity(event_a, event_b)
    
    # Text patterns: prefer Memory Stack embeddings
    if 'memory_stack' in tools:
        return embedding_cosine_similarity(event_a, event_b)
    
    # Fallback: Jaccard on keywords
    return jaccard_similarity(
        extract_keywords(event_a),
        extract_keywords(event_b)
    )
```

**Fallback: Jaccard Similarity**:

```python
def jaccard_similarity(set_a: set, set_b: set) -> float:
    """
    Jaccard similarity coefficient (keyword fallback).
    Returns 0.0-1.0 similarity score.
    """
    if not set_a and not set_b:
        return 0.0
    
    intersection = len(set_a & set_b)
    union = len(set_a | set_b)
    
    return intersection / union
```

**qmd Integration for Grimoire Search**:

```python
def search_related_learnings(query: str) -> list[Learning]:
    """
    Search grimoires/skills for related learnings.
    Uses qmd if available, grep fallback.
    """
    tools = detect_semantic_tools()
    
    if 'qmd' in tools:
        # Hybrid search: BM25 + vector + rerank
        result = subprocess.run(
            ['qmd', 'query', query, '--collection', 'grimoires'],
            capture_output=True, text=True
        )
        return parse_qmd_results(result.stdout)
    
    # Fallback: grep
    result = subprocess.run(
        ['grep', '-r', '-l', query, 'grimoires/loa/skills/'],
        capture_output=True, text=True
    )
    return parse_grep_results(result.stdout)
```

### Algorithm 3: Event Clustering

**Purpose**: Group similar events into pattern clusters.

```python
def cluster_events(events: list[Event], threshold: float) -> list[Cluster]:
    """
    Single-linkage clustering based on keyword similarity.
    Returns clusters of related events.
    """
    clusters = []
    used = set()
    
    for i, event_a in enumerate(events):
        if i in used:
            continue
            
        cluster = [event_a]
        used.add(i)
        
        for j, event_b in enumerate(events[i+1:], start=i+1):
            if j in used:
                continue
                
            similarity = jaccard_similarity(
                event_a.keywords,
                event_b.keywords
            )
            
            if similarity >= threshold:
                cluster.append(event_b)
                used.add(j)
        
        if len(cluster) >= 2:  # Minimum cluster size
            clusters.append(Cluster(events=cluster))
    
    return clusters
```

### Algorithm 4: Quality Gate Evaluation

**Purpose**: Determine if a pattern qualifies for extraction.

```python
def evaluate_quality_gates(pattern: Pattern) -> QualityResult:
    """
    Apply four quality gates to pattern candidate.
    All gates must pass for extraction.
    """
    results = {}
    
    # Gate 1: Discovery Depth
    # Pattern must span multiple sessions with investigation
    results['discovery_depth'] = (
        pattern.occurrence_count >= 2 and
        pattern.unique_sessions >= 2 and
        pattern.avg_investigation_steps >= 2
    )
    
    # Gate 2: Reusability
    # Pattern must be generalizable, not one-off
    results['reusability'] = (
        pattern.keyword_overlap >= 0.5 and  # Solutions share keywords
        pattern.context_diversity >= 2       # Different contexts, same fix
    )
    
    # Gate 3: Trigger Clarity
    # Pattern must have clear activation conditions
    results['trigger_clarity'] = (
        len(pattern.error_keywords) >= 3 and
        pattern.error_consistency >= 0.7     # Errors are similar
    )
    
    # Gate 4: Verification
    # Pattern solutions must be confirmed working
    results['verification'] = (
        pattern.success_rate >= 0.8 and      # 80%+ solutions worked
        pattern.has_code_evidence            # Solution in code
    )
    
    return QualityResult(
        passed=all(results.values()),
        gates=results
    )
```

### Algorithm 5: Morning Context Relevance Ranking

**Purpose**: Rank learnings by relevance to current task.

```python
def rank_learnings_for_task(task: Task, learnings: list[Learning]) -> list[Learning]:
    """
    Rank learnings by relevance × effectiveness.
    Returns top 5 most relevant learnings.
    """
    task_keywords = extract_keywords(task.description + task.context)
    
    scored = []
    for learning in learnings:
        # Calculate relevance (keyword overlap)
        relevance = jaccard_similarity(task_keywords, learning.keywords)
        
        # Get effectiveness (normalized 0-1)
        effectiveness = learning.effectiveness_score / 100
        
        # Recency boost (decay over 30 days)
        days_old = (now() - learning.last_retrieved).days
        recency = max(0, 1 - (days_old / 30))
        
        # Combined score
        score = (relevance * 0.5) + (effectiveness * 0.3) + (recency * 0.2)
        
        if score > 0.3:  # Minimum relevance threshold
            scored.append((score, learning))
    
    # Sort by score descending
    scored.sort(reverse=True, key=lambda x: x[0])
    
    # Return top 5
    return [learning for _, learning in scored[:5]]
```

---

## Error Handling Strategy

### Error Categories

| Category | Examples | Handling |
|----------|----------|----------|
| Data Corruption | Malformed JSONL, invalid JSON | Skip entry, log warning |
| Missing Files | No trajectory logs, missing NOTES.md | Graceful degradation, create if needed |
| Timeout | Pattern detection exceeds time | Return partial results |
| Capacity | Too many events to process | Sample or time-bound |

### Error Recovery

```python
def safe_read_trajectory(file_path: str) -> Iterator[Event]:
    """
    Read trajectory file with corruption handling.
    """
    line_number = 0
    try:
        with open(file_path, 'r') as f:
            for line in f:
                line_number += 1
                try:
                    event = json.loads(line)
                    yield Event.from_dict(event)
                except json.JSONDecodeError:
                    log_warning(f"Skipping malformed line {line_number} in {file_path}")
                    continue
    except FileNotFoundError:
        log_warning(f"Trajectory file not found: {file_path}")
        return
    except PermissionError:
        log_error(f"Permission denied: {file_path}")
        raise
```

### Graceful Degradation

| Scenario | Degraded Behavior |
|----------|-------------------|
| Pattern detection fails | Use single-session retrospective |
| Similarity calculation fails | Fall back to exact keyword match |
| Synthesis engine fails | Skip AGENTS.md proposals, keep skills |
| Morning context timeout | Skip context loading, proceed without |

---

## Testing Strategy

### Unit Tests

| Component | Test Cases |
|-----------|------------|
| KeywordExtractor | Stopword filtering, technical terms, edge cases |
| JaccardSimilarity | Empty sets, identical sets, partial overlap |
| EventClustering | Single event, no clusters, large clusters |
| QualityGates | Each gate pass/fail, boundary conditions |
| RelevanceRanking | Empty learnings, all relevant, none relevant |

### Integration Tests

| Test | Description |
|------|-------------|
| BatchRetrospective | End-to-end with sample trajectory files |
| PatternPersistence | Patterns survive read/write cycle |
| LearningFeedback | Application → verification → score update |
| SynthesisWorkflow | Cluster → propose → approve → apply |

### Performance Tests

| Test | Target | Method |
|------|--------|--------|
| Trajectory streaming | 100MB in < 30s | Benchmark with large file |
| Pattern detection | 10K events in < 60s | Timing test |
| Morning context | < 5s total | End-to-end timing |

### Test Data

Located in `grimoires/loa/a2a/test-fixtures/`:
```
test-fixtures/
├── trajectory-small.jsonl    # 100 events
├── trajectory-medium.jsonl   # 10K events
├── trajectory-large.jsonl    # 100K events
├── patterns-sample.json      # Expected pattern output
└── learnings-sample.json     # Expected learning output
```

---

## Development Phases

### Phase 1: MVP (Week 1-2)

**Goal**: `/retrospective --batch` working with pattern detection.

| Task | Effort | Dependencies |
|------|--------|--------------|
| TrajectoryReader implementation | 2d | None |
| Keyword extraction | 1d | None |
| Jaccard similarity | 1d | Keyword extraction |
| Event clustering | 2d | Jaccard similarity |
| Quality gates | 1d | Event clustering |
| Skill generation | 1d | Quality gates |
| CLI integration | 1d | All above |
| Testing | 2d | All above |

**Deliverables**:
- `/retrospective --batch --days N` functional
- Pattern detection with keyword similarity
- Quality gates applied
- Skills written to `skills-pending/`

### Phase 2: Compound Cycle (Week 3-4)

**Goal**: `/compound-review` and `/compound-ship` working.

| Task | Effort | Dependencies |
|------|--------|--------------|
| Review marker system | 1d | Phase 1 |
| NOTES.md integration | 1d | Phase 1 |
| `/compound-review` command | 2d | Marker system |
| `/compound-ship` scaffolding | 2d | Review command |
| `/run` integration | 2d | Ship scaffolding |
| `/compound` orchestration | 1d | Review + ship |
| Testing | 2d | All above |

**Deliverables**:
- `/compound-review` extracts and marks complete
- `/compound-ship` loads learnings and executes
- `/compound` runs both phases

### Phase 3: Feedback Loop (Week 5-6)

**Goal**: Learning application tracking and effectiveness feedback.

| Task | Effort | Dependencies |
|------|--------|--------------|
| LearningRegistry implementation | 2d | Phase 1 |
| Application tracking events | 1d | Registry |
| `/implement` integration | 2d | Tracking |
| Feedback signal detection | 2d | Application tracking |
| Effectiveness scoring | 1d | Feedback signals |
| Effectiveness reports | 1d | Scoring |
| Testing | 2d | All above |

**Deliverables**:
- `learning_applied` events in trajectory
- `learning_verified` events with outcomes
- Effectiveness scores in `learnings.json`

### Phase 4: Synthesis & Context (Week 7-8)

**Goal**: Learning synthesis and morning context loading.

| Task | Effort | Dependencies |
|------|--------|--------------|
| Skill clustering | 2d | Phase 1 |
| Proposal generation | 2d | Clustering |
| Human approval workflow | 1d | Proposals |
| `/synthesize-learnings` command | 1d | All above |
| Morning context algorithm | 1d | Phase 3 |
| Session start integration | 1d | Morning context |
| Scheduling helper scripts | 1d | Phase 2 |
| Documentation | 2d | All phases |

**Deliverables**:
- `/synthesize-learnings` with proposals
- Morning context loading (< 5s)
- Setup scripts for cron/launchd

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| False positive patterns | High | Medium | Quality gates, human review, confidence thresholds |
| Performance with large logs | Medium | High | Streaming analysis, time bounds, sampling |
| Keyword matching too coarse | Medium | Medium | Tunable thresholds, future embedding upgrade |
| AGENTS.md drift | Low | High | Human approval required, audit trail |
| Marker race conditions | Low | Medium | Atomic file operations, timestamps |

---

## Open Questions

### Questions for Human Input

1. **Scheduling mechanism**: ~~Should we rely purely on external cron/launchd, or build minimal scheduling into Loa itself?~~ **RESOLVED**: End-of-cycle trigger (after all sprints complete), not external cron.

2. **Embedding upgrade path**: ~~At what point should we invest in embedding-based similarity?~~ **RESOLVED**: Layered approach implemented - use ck/Memory Stack/qmd when available, Jaccard fallback. See [Semantic Search Integration](#semantic-search-integration).

3. **AGENTS.md sections**: What sections of AGENTS.md should be candidates for synthesis updates? All of it, or specific sections like "## Technical Conventions"?

4. **Pruning strategy**: What's the right threshold for pruning ineffective learnings? Current proposal is effectiveness < 20% after 3+ applications.

5. **Multi-project patterns**: Should compound learning work across projects (e.g., patterns that apply to all TypeScript projects), or stay project-scoped?

6. **qmd collection setup**: Should compound learning auto-create a `grimoires` collection in qmd, or require manual setup? Recommend auto-create on first `/retrospective --batch`.

---

## Appendix A: File Formats

### Trajectory Event (existing format extended)

```json
{
  "timestamp": "2025-01-30T10:30:00Z",
  "agent": "implementing-tasks",
  "phase": "implement",
  "action": "debug_resolution",
  "error": {
    "message": "Consumer not durable, messages lost on restart",
    "type": "runtime",
    "code": "NATS_CONSUMER_LOST"
  },
  "solution": {
    "description": "Added durable consumer name to JetStream config",
    "code_change": "consumer: { durable_name: 'my-consumer' }",
    "verified": true
  },
  "investigation_steps": 4,
  "hypothesis_changes": 2
}
```

### Skill File (existing format)

```markdown
---
name: nats-jetstream-consumer-durable
description: Use durable consumers for NATS JetStream message persistence
loa-agent: implementing-tasks
created: 2025-01-30
source: compound-learning
source_pattern: pat-001
effectiveness_score: 78
---

# NATS JetStream Durable Consumer Pattern

## Problem
Messages lost after process restart when using NATS JetStream consumers.

## Trigger Conditions
- Using NATS JetStream
- Consumer restarting or redeploying
- Messages not being replayed

## Root Cause
Non-durable consumers lose their position on disconnect.

## Solution
Configure durable consumer with explicit name:
\```typescript
const consumer = await js.consumers.get('my-stream', 'my-durable-name');
\```

## Verification
\```bash
nats consumer info my-stream my-durable-name
\```

## Related
- See NOTES.md learnings section
- Related skills: nats-reconnection-handling
```

---

*Generated by Architecture Agent*  
*Source: grimoires/loa/prd.md*
