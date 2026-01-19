# Product Requirements Document: Continuous Learning Skill

**Document Version**: 1.0.0
**Created**: 2026-01-18
**Status**: APPROVED
**Cycle**: cycle-004 (Continuous Learning Skill)
**Target Version**: v0.17.0

---

## Executive Summary

Implement autonomous skill extraction and continuous learning capability for Loa Framework. This enhancement enables Loa agents to extract debugging insights, workarounds, and patterns discovered during implementation phases into reusable skills that persist across sessions and projects.

**Research Foundation**: Based on Voyager (Wang et al., 2023), CASCADE (2024), Reflexion (Shinn et al., 2023), and SEAgent (2025) demonstrating that agents with persistent skill libraries outperform agents that start fresh.

---

## Problem Statement

### Current State

Loa agents currently lose discovered knowledge when sessions end. When an agent spends significant time debugging a non-obvious issue and discovers the root cause, that knowledge exists only in the conversation history. Future sessions encountering the same issue must rediscover the solution from scratch.

### Impact

1. **Repeated debugging cycles** - Same issues rediscovered multiple times
2. **Lost institutional knowledge** - Project-specific patterns not captured
3. **Inefficient cross-project learning** - Discoveries in one project don't benefit others
4. **No compound improvement** - Agent capability remains static over time

### Value Proposition

For interconnected projects, cross-project knowledge transfer is particularly valuable. A NATS JetStream configuration discovered in one project should automatically inform future NATS work across all projects.

---

## Solution Overview

### Core Concept

Create a `continuous-learning` skill that activates during implementation phases to:

1. **Detect** discoveries made through debugging, experimentation, or investigation
2. **Evaluate** discoveries against quality gates (non-obvious, reusable, precise triggers, verified)
3. **Extract** qualifying knowledge into standardized skill files
4. **Persist** skills in the State Zone for future session retrieval
5. **Manage** skill lifecycle through approval, activation, and pruning workflows

### Architecture Compliance

This feature respects Loa's Three-Zone Model:

| Zone | Usage | Example Paths |
|------|-------|---------------|
| System | Core skill logic (immutable) | `.claude/skills/continuous-learning/` |
| State | Extracted skills (mutable) | `grimoires/loa/skills/`, `grimoires/loa/skills-pending/` |

**Critical Constraint**: Never write extracted skills to `.claude/skills/` (System Zone). All extracted skills go to `grimoires/loa/skills/` (State Zone).

---

## Functional Requirements

### FR-1: Skill Directory Structure

Create the following directory structure:

```
.claude/skills/continuous-learning/
├── index.yaml                    # Skill metadata
├── SKILL.md                      # Main skill definition
└── resources/
    └── skill-template.md         # Template for extracted skills

grimoires/loa/
├── skills/                       # Active skills (initially empty)
├── skills-pending/               # Skills awaiting approval (initially empty)
└── skills-archived/              # Rejected/pruned skills (initially empty)
```

**Acceptance Criteria**:
- [ ] `.claude/skills/continuous-learning/` directory exists with index.yaml, SKILL.md, resources/
- [ ] `grimoires/loa/skills/` directory exists (can be empty/.gitkeep)
- [ ] `grimoires/loa/skills-pending/` directory exists (can be empty/.gitkeep)
- [ ] `grimoires/loa/skills-archived/` directory exists (can be empty/.gitkeep)

### FR-2: Continuous Learning Protocol

Create protocol document governing extraction, validation, and persistence.

**Location**: `.claude/protocols/continuous-learning.md`

**Content Requirements**:
- Evaluation flow diagram (ASCII or Mermaid)
- Four quality gates with pass/fail criteria
- Phase restrictions table
- Zone compliance rules
- Trajectory logging format
- Configuration reference

**Acceptance Criteria**:
- [ ] Protocol document exists at specified location
- [ ] All four quality gates documented
- [ ] Phase gating table complete
- [ ] Zone compliance section present

### FR-3: Continuous Learning Skill Definition

Create the main skill that activates during implementation phases.

**Location**: `.claude/skills/continuous-learning/SKILL.md`

**Activation Triggers**:
1. Agent completed debugging with non-obvious solution discovery
2. Found workaround through investigation or trial-and-error
3. Resolved error where root cause wasn't immediately apparent
4. Learned project-specific patterns through experimentation

**Phase Gating**:
| Phase | Active | Rationale |
|-------|--------|-----------|
| `/implement sprint-N` | YES | Primary discovery context |
| `/review-sprint sprint-N` | YES | Review insights valuable |
| `/audit-sprint sprint-N` | YES | Security patterns valuable |
| `/deploy-production` | YES | Infrastructure discoveries |
| `/ride` | YES | Codebase analysis discoveries |
| `/plan-and-analyze` | NO | Requirements, not implementation |
| `/architect` | NO | Design decisions, not debugging |
| `/sprint-plan` | NO | Planning, not implementation |

**Acceptance Criteria**:
- [ ] SKILL.md exists with YAML frontmatter
- [ ] Activation triggers clearly defined
- [ ] Phase gating table present
- [ ] Integration with structured memory documented
- [ ] Agent tagging format specified

### FR-4: Skill Template

Create template for extracted skills ensuring consistent format.

**Location**: `.claude/skills/continuous-learning/resources/skill-template.md`

**Required Sections**:
- YAML frontmatter (name, description, loa-agent, extracted-from, extraction-date, version, tags)
- Problem statement
- Trigger Conditions (error messages, symptoms, context)
- Root Cause explanation
- Solution (step-by-step with code)
- Verification steps
- Anti-Patterns
- Related Resources
- Related Memory (NOTES.md cross-references)
- Changelog

**Acceptance Criteria**:
- [ ] Template exists at specified location
- [ ] All required sections present
- [ ] YAML frontmatter includes all metadata fields
- [ ] Placeholder syntax clear for agent to fill

### FR-5: /retrospective Command

Create command to trigger manual learning retrospective.

**Location**: `.claude/commands/retrospective.md`

**Workflow**:
1. Session Analysis - Review conversation for discoveries
2. Quality Gate Evaluation - Present candidates with assessment
3. Cross-Reference Check - Check NOTES.md for existing coverage
4. Skill Extraction - Write approved skills to `skills-pending/`
5. Summary - Present extraction report

**Options**:
- `--scope <agent>`: Limit extraction to specific agent context
- `--force`: Skip quality gate prompts

**Acceptance Criteria**:
- [ ] Command file exists at specified location
- [ ] Five-step workflow documented
- [ ] Options documented with usage examples
- [ ] Integration with NOTES.md documented
- [ ] Example conversation flow provided

### FR-6: /skill-audit Command

Create command to review and manage extracted skills.

**Location**: `.claude/commands/skill-audit.md`

**Subcommands**:
- `--pending`: List skills awaiting approval
- `--approve <skill-name>`: Move skill to active
- `--reject <skill-name>`: Archive skill with reason
- `--prune`: Review and archive low-value skills
- `--stats`: Show skill usage statistics

**Acceptance Criteria**:
- [ ] Command file exists at specified location
- [ ] All subcommands documented
- [ ] Approval workflow moves files correctly
- [ ] Rejection logs reason to trajectory
- [ ] Pruning criteria documented

### FR-7: Quality Gates

Implement four quality gates for skill extraction:

| Gate | Question | Pass Criteria |
|------|----------|---------------|
| Discovery Depth | Was this non-obvious? | Required investigation, not documentation lookup |
| Reusability | Will this help future tasks? | Generalizable, not one-off |
| Trigger Clarity | Can triggers be precisely described? | Exact error messages or clear symptoms |
| Verification | Has solution been verified? | Tested and confirmed in session |

**Acceptance Criteria**:
- [ ] All four gates documented in protocol
- [ ] Each gate has clear pass/fail criteria
- [ ] Skill extraction requires ALL gates to pass
- [ ] Quality assessment shown during `/retrospective`

### FR-8: Configuration Schema

Add configuration options to `.loa.config.yaml`.

```yaml
continuous_learning:
  enabled: true
  auto_extract: true          # false = /retrospective only
  require_approval: true      # false = skip pending, write to skills/
  skills_dir: grimoires/loa/skills
  pending_dir: grimoires/loa/skills-pending
  archive_dir: grimoires/loa/skills-archived
  min_discovery_depth: 2      # 1=any, 2=moderate, 3=significant
  require_verification: true
  check_notes_md: true
  deduplicate: true
  prune_after_days: 90
  prune_min_matches: 2
```

**Acceptance Criteria**:
- [ ] Configuration schema documented
- [ ] Default values specified
- [ ] Each option has description
- [ ] CLAUDE.md updated with configuration section

### FR-9: Structured Memory Integration

Integrate with existing NOTES.md protocol:

1. **Cross-reference check** before extraction (avoid duplication)
2. **Session Continuity update** when skill extracted
3. **Decision Log linking** when skill relates to architectural decision

**Acceptance Criteria**:
- [ ] Cross-reference check documented in protocol
- [ ] Session Continuity table format updated
- [ ] Decision Log cross-reference format specified

### FR-10: Trajectory Logging

Log all learning events to `grimoires/loa/a2a/trajectory/continuous-learning-{date}.jsonl`:

```json
{
  "timestamp": "2026-01-18T14:30:00Z",
  "type": "extraction|approval|rejection|prune",
  "agent": "implementing-tasks",
  "phase": "implement",
  "task": "sprint-N-task-M",
  "skill_name": "skill-name",
  "quality_gates": {
    "discovery_depth": "PASS",
    "reusability": "PASS",
    "trigger_clarity": "PASS",
    "verification": "PASS"
  },
  "outcome": "created|approved|rejected|pruned"
}
```

**Acceptance Criteria**:
- [ ] JSONL format specified
- [ ] All event types documented
- [ ] Integration with existing trajectory system
- [ ] File naming convention matches existing pattern

---

## Non-Functional Requirements

### NFR-1: Zone Compliance

- MUST NOT write to `.claude/skills/` (System Zone)
- MUST write all extracted skills to `grimoires/loa/` (State Zone)
- MUST pass integrity verification after implementation

### NFR-2: Backward Compatibility

- MUST work in projects without existing skills directories
- MUST gracefully handle missing configuration
- MUST NOT break existing `/implement` workflow

### NFR-3: Performance

- Skill extraction MUST NOT significantly slow down implementation phases
- Quality gate evaluation SHOULD complete in under 5 seconds

### NFR-4: Documentation

- MUST update CLAUDE.md with new commands and configuration
- MUST update CHANGELOG.md for v0.17.0
- MUST include example extracted skills in resources/

---

## Out of Scope

1. **Automatic skill activation** - Skills in `skills-pending/` require manual approval
2. **Cross-project skill sharing** - Skills are project-local (future enhancement)
3. **Skill versioning conflicts** - No merge strategy for competing skills
4. **Machine learning optimization** - Rule-based extraction only
5. **Skill marketplace** - No publishing or discovery infrastructure

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Skills extracted per cycle | >= 3 | Count files in `skills/` |
| Quality gate pass rate | > 80% | Trajectory analysis |
| Skill reuse rate | > 50% | Match log analysis |
| False positive rate | < 20% | Pruning statistics |

---

## Implementation Order

1. Create directory structure (`grimoires/loa/skills/`, `skills-pending/`, `skills-archived/`)
2. Create `.claude/protocols/continuous-learning.md`
3. Create `.claude/skills/continuous-learning/index.yaml`
4. Create `.claude/skills/continuous-learning/SKILL.md`
5. Create `.claude/skills/continuous-learning/resources/skill-template.md`
6. Create `.claude/commands/retrospective.md`
7. Create `.claude/commands/skill-audit.md`
8. Update `.loa.config.yaml` with configuration schema
9. Update `CLAUDE.md` with new commands and configuration
10. Update `CHANGELOG.md` for v0.17.0
11. Run integrity verification
12. Create example extracted skill in `resources/examples/`

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Over-extraction of low-value skills | Clutter, noise | Quality gates, pruning workflow |
| Zone boundary violation | Integrity failure | Pre-commit validation, clear documentation |
| Duplicate skills | Inconsistency | NOTES.md cross-reference, deduplication |
| Stale skills | Incorrect solutions | Pruning workflow, version tracking |

---

## Stakeholder Approval

| Role | Name | Status |
|------|------|--------|
| Product Owner | User | APPROVED |
| Technical Lead | Loa Framework | PENDING |
| Security | Loa Framework | PENDING |

---

## Appendix A: Research References

1. **Voyager** (Wang et al., 2023) - "Voyager: An Open-Ended Embodied Agent with Large Language Models"
2. **CASCADE** (2024) - Meta-skills for compound learning
3. **Reflexion** (Shinn et al., 2023) - "Reflexion: Language Agents with Verbal Reinforcement Learning"
4. **SEAgent** (2025) - Trial-and-error learning in software environments

---

## Appendix B: Example Extracted Skill

```markdown
---
name: nats-jetstream-consumer-durable
description: |
  Fix for NATS JetStream consumer losing position after restart. Use when
  consumer stops receiving messages after process restart. Implements durable
  consumer name for persistent subscription state.
loa-agent: implementing-tasks
extracted-from: sprint-7-task-3
extraction-date: 2026-01-18
version: 1.0.0
tags:
  - nats
  - jetstream
  - messaging
---

# NATS JetStream Consumer Position Lost After Restart

## Problem

Consumer stops receiving messages after process restart. All messages published
during downtime are lost because consumer doesn't remember its position.

## Trigger Conditions

### Symptoms
- Consumer works initially, fails after restart
- No error messages - just silent message loss
- Works fine when consuming from beginning

### Context
- **Technology Stack**: NATS JetStream
- **Environment**: Any with process restarts
- **Timing**: After consumer process restart

## Root Cause

Ephemeral consumers don't persist their position. On restart, a new ephemeral
consumer is created with no memory of previous position.

## Solution

### Step 1: Add Durable Name

```typescript
const sub = await js.subscribe('orders.>', {
  durable: 'my-service-orders', // Add this line
  deliverTo: createInbox(),
});
```

## Verification

```bash
nats consumer info ORDERS my-service-orders
```

Expected: Consumer shows persistent state with ack position.

## Anti-Patterns

### Don't: Use ephemeral consumers for persistent processing

```typescript
// BAD - position lost on restart
const sub = await js.subscribe('orders.>');
```
```

---

## Appendix C: Files to Create/Modify

### New Files
```
.claude/skills/continuous-learning/index.yaml
.claude/skills/continuous-learning/SKILL.md
.claude/skills/continuous-learning/resources/skill-template.md
.claude/protocols/continuous-learning.md
.claude/commands/retrospective.md
.claude/commands/skill-audit.md
grimoires/loa/skills/.gitkeep
grimoires/loa/skills-pending/.gitkeep
grimoires/loa/skills-archived/.gitkeep
```

### Modified Files
```
.loa.config.yaml
CHANGELOG.md
CLAUDE.md
```

---

*PRD generated by discovering-requirements agent*
*Source: Continuous Learning Skill Analysis (grimoires/loa/context/extracted/loa-continuous-learning/)*
