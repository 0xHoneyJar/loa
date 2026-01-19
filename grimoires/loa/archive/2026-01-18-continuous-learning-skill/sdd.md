# Software Design Document: Continuous Learning Skill

**Version**: 1.0.0
**Date**: 2026-01-18
**Status**: Draft
**Author**: designing-architecture agent
**Cycle**: cycle-004 (Continuous Learning Skill)
**Target Version**: 0.17.0
**PRD Reference**: `grimoires/loa/prd.md`

---

## 1. Executive Summary

This SDD describes the architecture for the Continuous Learning Skill (v0.17.0), which adds:

1. **Autonomous Skill Extraction**: Detect and extract non-obvious discoveries during implementation
2. **Four Quality Gates**: Prevent low-value skill extraction (Discovery Depth, Reusability, Trigger Clarity, Verification)
3. **State Zone Skill Storage**: Extracted skills in `grimoires/loa/skills/` (never System Zone)
4. **Lifecycle Management**: `/retrospective` and `/skill-audit` commands for skill approval and pruning

**Design Philosophy**: "Compound learning over time." Agents build reusable knowledge that persists across sessions without violating Loa's Three-Zone Model.

**Research Foundation**: Voyager (Wang et al., 2023), CASCADE (2024), Reflexion (Shinn et al., 2023), SEAgent (2025).

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Loa Framework v0.17.0                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────┐   │
│  │     System Zone     │   │      State Zone      │   │    App Zone     │   │
│  │      .claude/       │   │    grimoires/loa/    │   │   src/, lib/    │   │
│  │                     │   │       .beads/        │   │                 │   │
│  │ ┌─────────────────┐ │   │                      │   │                 │   │
│  │ │  skills/        │ │   │ ┌──────────────────┐ │   │                 │   │
│  │ │  continuous-    │ │   │ │    skills/       │ │   │                 │   │
│  │ │  learning/      │◄┼───┼─┤ (extracted, active)│   │                 │   │
│  │ │  (core logic)   │ │   │ └──────────────────┘ │   │                 │   │
│  │ └─────────────────┘ │   │                      │   │                 │   │
│  │                     │   │ ┌──────────────────┐ │   │                 │   │
│  │ ┌─────────────────┐ │   │ │ skills-pending/  │ │   │                 │   │
│  │ │  protocols/     │ │   │ │ (awaiting review)│ │   │                 │   │
│  │ │  continuous-    │ │   │ └──────────────────┘ │   │                 │   │
│  │ │  learning.md    │ │   │                      │   │                 │   │
│  │ └─────────────────┘ │   │ ┌──────────────────┐ │   │                 │   │
│  │                     │   │ │ skills-archived/ │ │   │                 │   │
│  │ ┌─────────────────┐ │   │ │ (rejected/pruned)│ │   │                 │   │
│  │ │  commands/      │ │   │ └──────────────────┘ │   │                 │   │
│  │ │  retrospective  │ │   │                      │   │                 │   │
│  │ │  skill-audit    │ │   │ ┌──────────────────┐ │   │                 │   │
│  │ └─────────────────┘ │   │ │ a2a/trajectory/  │ │   │                 │   │
│  │                     │   │ │ continuous-      │ │   │                 │   │
│  │                     │   │ │ learning-*.jsonl │ │   │                 │   │
│  │                     │   │ └──────────────────┘ │   │                 │   │
│  └─────────────────────┘   └──────────────────────┘   └─────────────────┘   │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                      Skill Extraction Pipeline                         │  │
│  │                                                                        │  │
│  │  Discovery ──► Quality Gates ──► NOTES.md Check ──► Extract ──► Pending │  │
│  │     │              │                  │                │                │  │
│  │     │         ┌────┴────┐             │                │                │  │
│  │     │         │ 4 Gates │             │                │                │  │
│  │     │         │ ALL PASS│             │                │                │  │
│  │     │         └─────────┘             │                │                │  │
│  │     ▼                                 ▼                ▼                │  │
│  │  [Agent]                        [Dedup Check]    [skill-template.md]   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                      Skill Lifecycle Management                        │  │
│  │                                                                        │  │
│  │  /retrospective ──► skills-pending/ ──► /skill-audit ──► skills/      │  │
│  │        │                   │                  │              │         │  │
│  │   (manual trigger)    (staging)          (approval)     (active)      │  │
│  │                                              │                         │  │
│  │                                    ┌────────┴────────┐                │  │
│  │                                    ▼                 ▼                │  │
│  │                             skills-archived/    trajectory log        │  │
│  │                             (rejected/pruned)                         │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Overview

| Component | Location | Purpose | Owner |
|-----------|----------|---------|-------|
| continuous-learning skill | `.claude/skills/continuous-learning/` | Core extraction logic | Framework |
| continuous-learning protocol | `.claude/protocols/continuous-learning.md` | Evaluation flow, quality gates | Framework |
| skill-template.md | `.claude/skills/continuous-learning/resources/` | Template for extracted skills | Framework |
| retrospective.md | `.claude/commands/retrospective.md` | Manual extraction trigger | Framework |
| skill-audit.md | `.claude/commands/skill-audit.md` | Lifecycle management | Framework |
| skills/ | `grimoires/loa/skills/` | Active extracted skills | Project |
| skills-pending/ | `grimoires/loa/skills-pending/` | Skills awaiting approval | Project |
| skills-archived/ | `grimoires/loa/skills-archived/` | Rejected/pruned skills | Project |
| trajectory logs | `grimoires/loa/a2a/trajectory/continuous-learning-*.jsonl` | Extraction audit trail | Project |

### 2.3 Zone Compliance

**CRITICAL**: This feature MUST NOT write to System Zone for extracted skills.

| Action | Allowed Location | Forbidden Location |
|--------|------------------|-------------------|
| Create extracted skill | `grimoires/loa/skills-pending/` | `.claude/skills/` |
| Activate skill | `grimoires/loa/skills/` | `.claude/skills/` |
| Archive skill | `grimoires/loa/skills-archived/` | Any System Zone |
| Log extraction | `grimoires/loa/a2a/trajectory/` | Anywhere else |

---

## 3. Component Design

### 3.1 Continuous Learning Skill

#### 3.1.1 Directory Structure

```
.claude/skills/continuous-learning/
├── index.yaml              # Skill metadata (Level 1)
├── SKILL.md                # Core instructions (Level 2)
└── resources/              # Reference materials (Level 3)
    ├── skill-template.md   # Template for extraction
    └── examples/           # Example extracted skills
        └── nats-jetstream-consumer-durable.md
```

#### 3.1.2 index.yaml Schema

```yaml
name: "continuous-learning"
version: "1.0.0"
model: "sonnet"
color: "purple"

description: |
  Autonomous skill extraction that activates when agents discover non-obvious
  solutions through debugging, experimentation, or investigation. Extracts
  reusable knowledge into skills that persist across sessions.

triggers:
  - "/retrospective"
  - "save this as a skill"
  - "extract what we learned"
  - "create skill from discovery"

examples:
  - context: "Agent just resolved a tricky debugging issue"
    user_says: "That was a useful discovery, let's save it"
    agent_action: "Evaluate against quality gates, extract to skills-pending/"
  - context: "End of implementation session"
    user_says: "/retrospective"
    agent_action: "Analyze session for extractable discoveries, present candidates"

outputs:
  - path: "grimoires/loa/skills-pending/{skill-name}/SKILL.md"
    description: "Extracted skill awaiting approval"
  - path: "grimoires/loa/a2a/trajectory/continuous-learning-{date}.jsonl"
    description: "Extraction audit trail"

# Phase gating
phase_activation:
  enabled:
    - "/implement sprint-N"
    - "/review-sprint sprint-N"
    - "/audit-sprint sprint-N"
    - "/deploy-production"
    - "/ride"
  disabled:
    - "/plan-and-analyze"
    - "/architect"
    - "/sprint-plan"

# Protocol dependencies
protocols:
  required:
    - name: "continuous-learning"
      path: ".claude/protocols/continuous-learning.md"
      purpose: "Quality gates, extraction flow, zone compliance"
    - name: "structured-memory"
      path: ".claude/protocols/structured-memory.md"
      purpose: "NOTES.md cross-reference, session continuity"
  recommended:
    - name: "trajectory-evaluation"
      path: ".claude/protocols/trajectory-evaluation.md"
      purpose: "Extraction logging, audit trail"
```

#### 3.1.3 SKILL.md Structure

The SKILL.md follows Loa's 3-level architecture with YAML frontmatter:

```yaml
---
name: continuous-learning
description: |
  Autonomous skill extraction and continuous learning for Loa Framework. Activates when:
  (1) Agent completed debugging with non-obvious solution discovery
  (2) Found workaround through investigation or trial-and-error
  (3) Resolved error where root cause wasn't immediately apparent
  (4) Learned project-specific patterns through experimentation
author: 0xHoneyJar
version: 1.0.0
loa-agent-scope: implementing-tasks, reviewing-code, auditing-security, deploying-infrastructure
---
```

**Key Sections**:
1. Overview - Purpose and research foundation
2. Activation Triggers - When skill activates
3. Integration with Loa Architecture - Zone compliance
4. Quality Gates - Four validation criteria
5. Workflow - Automatic and manual modes
6. Skill Format - Template reference
7. Phase Gating - Enabled/disabled phases
8. Skill Lifecycle - Staging, activation, pruning
9. Configuration - `.loa.config.yaml` options
10. Integration with Trajectory Evaluation - Logging format

---

### 3.2 Quality Gates System

#### 3.2.1 Gate Definitions

| Gate | Question | Pass Criteria | Fail Criteria |
|------|----------|---------------|---------------|
| **Discovery Depth** | Was this non-obvious? | Required investigation, trial-and-error, debugging | Documentation lookup, first Google result |
| **Reusability** | Will this help future tasks? | Generalizable pattern, applies to multiple contexts | One-off solution, project-specific hack |
| **Trigger Clarity** | Can triggers be precisely described? | Exact error messages, specific symptoms | Vague symptoms, "sometimes happens" |
| **Verification** | Has solution been verified? | Tested in current session, confirmed working | Theoretical only, untested |

#### 3.2.2 Gate Evaluation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    DISCOVERY DETECTED                            │
│           (error resolved, workaround found, etc.)               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GATE 1: Discovery Depth                       │
│                                                                  │
│  Was this non-obvious?                                          │
│  - Documentation lookup? → FAIL → Skip extraction               │
│  - Required investigation? → PASS                                │
│  - Trial-and-error discovery? → PASS                             │
└─────────────────────────────────────────────────────────────────┘
                              │ PASS
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GATE 2: Reusability                           │
│                                                                  │
│  Will this help future tasks?                                   │
│  - One-off solution? → FAIL → Skip extraction                   │
│  - Applies to single context? → FAIL                            │
│  - Generalizable pattern? → PASS                                 │
└─────────────────────────────────────────────────────────────────┘
                              │ PASS
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GATE 3: Trigger Clarity                       │
│                                                                  │
│  Can trigger conditions be precisely described?                 │
│  - Vague symptoms? → FAIL → Skip extraction                     │
│  - Exact error messages? → PASS                                  │
│  - Clear context indicators? → PASS                              │
└─────────────────────────────────────────────────────────────────┘
                              │ PASS
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GATE 4: Verification                          │
│                                                                  │
│  Has the solution been verified?                                │
│  - Theoretical only? → FAIL → Skip extraction                   │
│  - Tested in session? → PASS                                     │
│  - Confirmed working? → PASS                                     │
└─────────────────────────────────────────────────────────────────┘
                              │ ALL PASS
                              ▼
                    Continue to extraction
```

#### 3.2.3 Gate Configuration

```yaml
# .loa.config.yaml
continuous_learning:
  quality_gates:
    discovery_depth:
      min_level: 2              # 1=any, 2=moderate, 3=significant
      require_investigation: true
    reusability:
      require_generalization: true
      min_applicable_contexts: 2
    trigger_clarity:
      require_error_message: false  # Either error or symptoms
      require_symptoms: true
    verification:
      require_session_test: true
```

---

### 3.3 Skill Template

#### 3.3.1 Template Location

```
.claude/skills/continuous-learning/resources/skill-template.md
```

#### 3.3.2 Template Schema

```yaml
---
name: {kebab-case-name}
description: |
  {Semantically-optimized description for retrieval matching.
  Include exact error messages, technology names, symptoms.}
loa-agent: {implementing-tasks|reviewing-code|auditing-security|deploying-infrastructure}
extracted-from: {sprint-N-task-M or session-context}
extraction-date: {YYYY-MM-DD}
version: 1.0.0
tags:
  - {technology}
  - {category}
---
```

**Required Sections**:

| Section | Purpose | Format |
|---------|---------|--------|
| Problem | What this skill solves | Prose, specific symptoms |
| Trigger Conditions | When to apply | Error messages, symptoms, context |
| Root Cause | Why it happens | Brief explanation |
| Solution | How to fix | Step-by-step with code |
| Verification | How to confirm | Commands, expected output |
| Anti-Patterns | What NOT to do | Bad examples with explanations |
| Related Memory | NOTES.md cross-refs | Links to decisions, debt |
| Changelog | Version history | Table format |

---

### 3.4 Commands

#### 3.4.1 /retrospective Command

**Location**: `.claude/commands/retrospective.md`

**Purpose**: Trigger manual learning retrospective at end of session or after significant work.

**Workflow**:

```
┌──────────────────────────────────────────────────────────────────┐
│                    /retrospective Workflow                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Step 1: Session Analysis                                        │
│  ├── Review conversation for discoveries                         │
│  ├── Identify error resolutions                                  │
│  ├── Identify workarounds implemented                            │
│  └── Identify patterns learned                                   │
│                                                                   │
│  Step 2: Quality Gate Evaluation                                 │
│  ├── For each candidate discovery:                               │
│  │   ├── Evaluate Discovery Depth                                │
│  │   ├── Evaluate Reusability                                    │
│  │   ├── Evaluate Trigger Clarity                                │
│  │   └── Evaluate Verification                                   │
│  └── Present findings with confidence levels                     │
│                                                                   │
│  Step 3: Cross-Reference Check                                   │
│  ├── Search NOTES.md Decision Log                                │
│  ├── Search NOTES.md Technical Debt                              │
│  └── Skip if exact match, link if partial                        │
│                                                                   │
│  Step 4: Skill Extraction (for approved candidates)              │
│  ├── Generate skill using template                               │
│  ├── Write to grimoires/loa/skills-pending/{name}/SKILL.md       │
│  ├── Log to trajectory                                           │
│  └── Update NOTES.md Session Continuity                          │
│                                                                   │
│  Step 5: Summary                                                 │
│  ├── List skills extracted                                       │
│  ├── List skills skipped (with reasons)                          │
│  └── Provide next steps                                          │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

**Options**:

| Option | Description | Example |
|--------|-------------|---------|
| `--scope <agent>` | Limit to specific agent context | `/retrospective --scope implementing-tasks` |
| `--force` | Skip quality gate prompts | `/retrospective --force` |

#### 3.4.2 /skill-audit Command

**Location**: `.claude/commands/skill-audit.md`

**Purpose**: Review and manage extracted skills lifecycle.

**Subcommands**:

| Subcommand | Action | Output |
|------------|--------|--------|
| `--pending` | List skills in skills-pending/ | Table with name, date, agent |
| `--approve <name>` | Move skill to skills/ | Confirmation, trajectory log |
| `--reject <name>` | Move to skills-archived/ | Reason prompt, trajectory log |
| `--prune` | Review for low-value skills | Pruning report, confirmations |
| `--stats` | Show skill statistics | Usage counts, match rates |

**Approval Workflow**:

```
skills-pending/{name}/SKILL.md
          │
          ▼
    /skill-audit --approve {name}
          │
          ├──► Move to skills/{name}/SKILL.md
          ├──► Log "approval" to trajectory
          └──► Notify user
```

**Rejection Workflow**:

```
skills-pending/{name}/SKILL.md
          │
          ▼
    /skill-audit --reject {name}
          │
          ├──► Prompt for reason
          ├──► Move to skills-archived/{name}/SKILL.md
          ├──► Log "rejection" with reason to trajectory
          └──► Notify user
```

**Pruning Criteria** (run via `--prune`):

| Criterion | Threshold | Action |
|-----------|-----------|--------|
| Age without use | > 90 days | Suggest archive |
| Low match count | < 2 matches | Suggest archive |
| Superseded | Newer skill exists | Suggest merge or archive |

---

### 3.5 Trajectory Logging

#### 3.5.1 Log Location

```
grimoires/loa/a2a/trajectory/continuous-learning-{YYYY-MM-DD}.jsonl
```

#### 3.5.2 Event Types

| Event Type | When Logged | Required Fields |
|------------|-------------|-----------------|
| `extraction` | Skill created in pending | skill_name, quality_gates, agent, phase |
| `approval` | Skill moved to active | skill_name, approved_by |
| `rejection` | Skill archived | skill_name, reason, rejected_by |
| `prune` | Skill removed via pruning | skill_name, prune_reason, age_days |
| `match` | Skill triggered in future session | skill_name, context, confidence |

#### 3.5.3 JSONL Schema

```json
{
  "timestamp": "2026-01-18T14:30:00Z",
  "type": "extraction",
  "agent": "implementing-tasks",
  "phase": "implement",
  "task": "sprint-1-task-3",
  "skill_name": "nats-jetstream-consumer-durable",
  "quality_gates": {
    "discovery_depth": {"status": "PASS", "level": 2, "reason": "Required trial-and-error"},
    "reusability": {"status": "PASS", "reason": "Applies to all JetStream consumers"},
    "trigger_clarity": {"status": "PASS", "error_message": "Consumer not receiving messages"},
    "verification": {"status": "PASS", "tested": true}
  },
  "outcome": "created",
  "output_path": "grimoires/loa/skills-pending/nats-jetstream-consumer-durable/SKILL.md"
}
```

---

### 3.6 Configuration Schema

#### 3.6.1 Full Configuration

```yaml
# .loa.config.yaml
continuous_learning:
  # Master toggle
  enabled: true

  # Extraction behavior
  auto_extract: true          # false = /retrospective only
  require_approval: true      # false = skip pending, write directly to skills/

  # Paths (relative to project root)
  skills_dir: grimoires/loa/skills
  pending_dir: grimoires/loa/skills-pending
  archive_dir: grimoires/loa/skills-archived
  trajectory_file: grimoires/loa/a2a/trajectory/continuous-learning-{date}.jsonl

  # Quality gate thresholds
  min_discovery_depth: 2      # 1=any, 2=moderate, 3=significant
  require_verification: true

  # Cross-reference behavior
  check_notes_md: true
  deduplicate: true

  # Pruning
  prune_after_days: 90
  prune_min_matches: 2
  auto_prune: false           # true = prune automatically during /skill-audit

  # Metrics
  track_matches: true
  match_log: grimoires/loa/a2a/skill-matches.jsonl
```

#### 3.6.2 Default Behavior

When configuration is missing, use these defaults:

| Setting | Default | Rationale |
|---------|---------|-----------|
| `enabled` | `true` | Feature active by default |
| `auto_extract` | `true` | Automatic evaluation during implementation |
| `require_approval` | `true` | Human review before activation |
| `min_discovery_depth` | `2` | Moderate investigation required |
| `require_verification` | `true` | Solution must be tested |
| `prune_after_days` | `90` | Three months without use |

---

## 4. Integration Design

### 4.1 Integration with Structured Memory (NOTES.md)

#### 4.1.1 Cross-Reference Check

Before extracting a skill, check NOTES.md for existing coverage:

```python
# Pseudocode for cross-reference check
def check_notes_md(discovery):
    notes = read_file("grimoires/loa/NOTES.md")

    # Check Decision Log
    for decision in notes.decisions:
        if similarity(discovery.description, decision.description) > 0.8:
            return CrossRefResult(
                type="EXACT_MATCH",
                ref=f"Decision #{decision.id}",
                action="SKIP_EXTRACTION"
            )
        elif similarity(discovery.description, decision.description) > 0.5:
            return CrossRefResult(
                type="PARTIAL_MATCH",
                ref=f"Decision #{decision.id}",
                action="LINK_IN_SKILL"
            )

    # Check Technical Debt
    for debt in notes.technical_debt:
        if similarity(discovery.description, debt.description) > 0.8:
            return CrossRefResult(
                type="EXACT_MATCH",
                ref=f"TD-{debt.id}",
                action="SKIP_EXTRACTION"
            )

    return CrossRefResult(type="NO_MATCH", action="PROCEED")
```

#### 4.1.2 Session Continuity Update

When a skill is extracted, update NOTES.md Session Log:

```markdown
## Session Log

| Timestamp | Event | Outcome |
|-----------|-------|---------|
| 2026-01-18T14:30:00Z | Extracted skill: nats-jetstream-consumer-durable | Pending approval |
```

### 4.2 Integration with Trajectory Evaluation

#### 4.2.1 Learning Events

All skill extraction events are logged using the existing trajectory format:

```jsonl
{"ts":"2026-01-18T14:30:00Z","agent":"implementing-tasks","phase":"skill_extraction","skill_name":"nats-jetstream-consumer-durable","quality_gates":{"discovery_depth":"PASS","reusability":"PASS","trigger_clarity":"PASS","verification":"PASS"},"outcome":"created"}
```

#### 4.2.2 New Trajectory Phases

| Phase | When | Fields |
|-------|------|--------|
| `skill_extraction` | Skill created | skill_name, quality_gates, outcome |
| `skill_approval` | Skill activated | skill_name, approved_by |
| `skill_rejection` | Skill archived | skill_name, reason |
| `skill_match` | Skill triggered | skill_name, context, confidence |

### 4.3 Integration with Existing Skills

#### 4.3.1 Phase Gating

The continuous-learning skill respects Loa's phase gating:

| Command | continuous-learning Active | Rationale |
|---------|---------------------------|-----------|
| `/implement sprint-N` | YES | Primary discovery context |
| `/review-sprint sprint-N` | YES | Review insights valuable |
| `/audit-sprint sprint-N` | YES | Security patterns valuable |
| `/deploy-production` | YES | Infrastructure discoveries |
| `/ride` | YES | Codebase analysis discoveries |
| `/plan-and-analyze` | NO | Requirements, not debugging |
| `/architect` | NO | Design decisions, not debugging |
| `/sprint-plan` | NO | Planning, not debugging |

#### 4.3.2 Agent Tagging

Extracted skills include the originating Loa agent:

```yaml
---
name: nats-jetstream-consumer-durable
loa-agent: implementing-tasks      # Originating agent
extracted-from: sprint-7-task-3    # Source context
---
```

---

## 5. Security Considerations

### 5.1 Zone Compliance Verification

**Pre-commit Hook** (recommended):

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Check for Zone violations
if git diff --cached --name-only | grep -q "^\.claude/skills/.*/SKILL\.md$"; then
    # Verify it's not an extracted skill
    for file in $(git diff --cached --name-only | grep "^\.claude/skills/.*/SKILL\.md$"); do
        if grep -q "extracted-from:" "$file"; then
            echo "ERROR: Extracted skill $file cannot be committed to System Zone"
            echo "Move to grimoires/loa/skills/ instead"
            exit 1
        fi
    done
fi
```

### 5.2 Skill Content Validation

Extracted skills are validated before creation:

| Check | Purpose | Action on Fail |
|-------|---------|----------------|
| No credentials | Prevent secret leakage | Block extraction, warn user |
| No absolute paths | Ensure portability | Convert to `${PROJECT_ROOT}` |
| Template compliance | Ensure consistency | Prompt for missing sections |

### 5.3 Approval Workflow

Skills go through human review by default:

```
Extract → skills-pending/ → Human Review → skills/ (or archive)
```

This prevents:
- Low-quality skills polluting the skill library
- Incorrect solutions being applied automatically
- Stale knowledge persisting without validation

---

## 6. Performance Considerations

### 6.1 Extraction Overhead

Quality gate evaluation should complete in under 5 seconds:

| Operation | Target Time | Implementation |
|-----------|-------------|----------------|
| Session analysis | < 2s | Scan recent conversation only |
| Quality gate evaluation | < 1s | Simple rule-based checks |
| NOTES.md cross-reference | < 1s | In-memory search |
| Template generation | < 1s | String interpolation |

### 6.2 Storage Efficiency

Extracted skills are stored as individual markdown files:

- **Average skill size**: ~2KB
- **Target skill count per project**: 10-50
- **Total storage**: < 100KB

### 6.3 Lazy Loading

Skills are loaded on-demand, not at startup:

```python
# Skills loaded only when relevant context detected
if session_context.matches(skill.triggers):
    load_skill(skill)
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

| Test | File | Purpose |
|------|------|---------|
| Quality gate evaluation | `tests/unit/quality-gates.bats` | Gate pass/fail logic |
| Template generation | `tests/unit/skill-template.bats` | Correct YAML/markdown output |
| Zone compliance | `tests/unit/zone-compliance.bats` | Verify no System Zone writes |
| Configuration parsing | `tests/unit/config-parsing.bats` | Default values, validation |

### 7.2 Integration Tests

| Test | File | Purpose |
|------|------|---------|
| /retrospective flow | `tests/integration/retrospective.bats` | End-to-end extraction |
| /skill-audit approve | `tests/integration/skill-audit.bats` | Approval workflow |
| /skill-audit reject | `tests/integration/skill-audit.bats` | Rejection workflow |
| Cross-reference check | `tests/integration/notes-crossref.bats` | NOTES.md deduplication |

### 7.3 Test Scenarios (EDD)

**Scenario 1: Happy Path - Skill Extraction**
1. Agent resolves non-obvious error
2. All quality gates pass
3. Skill created in skills-pending/
4. Trajectory logged

**Scenario 2: Edge Case - Duplicate Detection**
1. Agent discovers solution already in NOTES.md
2. Cross-reference check finds exact match
3. Extraction skipped, user notified
4. Link suggested instead

**Scenario 3: Error Handling - Gate Failure**
1. Agent attempts extraction
2. Discovery Depth gate fails (documentation lookup)
3. Extraction skipped with explanation
4. Trajectory logged with failure reason

---

## 8. Implementation Order

### Phase 1: Core Infrastructure (Sprint 1)

| Task | Files | Acceptance Criteria |
|------|-------|---------------------|
| Create directory structure | `grimoires/loa/skills/`, etc. | Directories exist with .gitkeep |
| Create protocol document | `.claude/protocols/continuous-learning.md` | All sections complete |
| Create index.yaml | `.claude/skills/continuous-learning/index.yaml` | Valid YAML, all fields |

### Phase 2: Skill Definition (Sprint 2)

| Task | Files | Acceptance Criteria |
|------|-------|---------------------|
| Create SKILL.md | `.claude/skills/continuous-learning/SKILL.md` | Complete instructions |
| Create skill template | `.claude/skills/.../resources/skill-template.md` | All required sections |
| Create example skill | `.claude/skills/.../resources/examples/` | Demonstrates format |

### Phase 3: Commands (Sprint 3)

| Task | Files | Acceptance Criteria |
|------|-------|---------------------|
| Create /retrospective | `.claude/commands/retrospective.md` | 5-step workflow |
| Create /skill-audit | `.claude/commands/skill-audit.md` | All subcommands |
| Trajectory logging | Integration | JSONL format, all event types |

### Phase 4: Integration & Documentation (Sprint 4)

| Task | Files | Acceptance Criteria |
|------|-------|---------------------|
| Configuration schema | `.loa.config.yaml` | Documented with defaults |
| CLAUDE.md updates | `CLAUDE.md` | New commands, config section |
| CHANGELOG entry | `CHANGELOG.md` | v0.17.0 release notes |
| Unit tests | `tests/unit/*.bats` | All tests pass |
| Integration tests | `tests/integration/*.bats` | All tests pass |

---

## 9. Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Over-extraction of low-value skills | Noise, clutter | Medium | Quality gates, manual approval |
| Zone boundary violation | Integrity failure | Low | Pre-commit hooks, clear documentation |
| Duplicate skills | Inconsistency | Medium | NOTES.md cross-reference, deduplication |
| Stale skills | Incorrect solutions | Medium | Pruning workflow, version tracking |
| Performance degradation | Slow implementation | Low | Lazy loading, efficient evaluation |

---

## 10. Future Considerations

### 10.1 Out of Scope (This Release)

- Cross-project skill sharing
- Skill versioning conflicts and merging
- Machine learning optimization of quality gates
- Skill marketplace or publishing

### 10.2 Potential Future Enhancements

| Enhancement | Description | Priority |
|-------------|-------------|----------|
| Skill federation | Share skills across projects | P2 |
| Semantic matching | ML-based skill retrieval | P3 |
| Skill analytics | Usage patterns, effectiveness | P2 |
| Auto-pruning | Automatic removal of stale skills | P3 |

---

## Appendix A: File Manifest

### New Files

```
.claude/skills/continuous-learning/
├── index.yaml
├── SKILL.md
└── resources/
    ├── skill-template.md
    └── examples/
        └── nats-jetstream-consumer-durable.md

.claude/protocols/continuous-learning.md

.claude/commands/
├── retrospective.md
└── skill-audit.md

grimoires/loa/
├── skills/.gitkeep
├── skills-pending/.gitkeep
└── skills-archived/.gitkeep

tests/unit/
├── quality-gates.bats
├── skill-template.bats
├── zone-compliance.bats
└── config-parsing.bats

tests/integration/
├── retrospective.bats
├── skill-audit.bats
└── notes-crossref.bats
```

### Modified Files

```
.loa.config.yaml        # Add continuous_learning section
CLAUDE.md               # Add commands and configuration
CHANGELOG.md            # v0.17.0 entry
```

---

## Appendix B: Glossary

| Term | Definition |
|------|------------|
| **Extracted Skill** | Reusable knowledge captured from debugging sessions |
| **Quality Gate** | Validation criterion that must pass for extraction |
| **Skill Lifecycle** | States: pending → active → archived |
| **Discovery Depth** | Measure of investigation required to find solution |
| **Cross-Reference** | Link between skill and existing NOTES.md entry |

---

*SDD generated by designing-architecture agent*
*PRD Reference: grimoires/loa/prd.md*
