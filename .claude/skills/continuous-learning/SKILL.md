---
name: continuous-learning
description: |
  Autonomous skill extraction from debugging discoveries. Activates when agents
  find non-obvious solutions through investigation, experimentation, or trial-and-error.
  Captures these discoveries as reusable skills for future sessions.
author: Loa Framework
version: 1.0.0
loa-agent-scope:
  - implementing-tasks
  - reviewing-code
  - auditing-security
  - deploying-infrastructure
---

# Continuous Learning Skill

## Overview

The Continuous Learning Skill enables agents to autonomously extract reusable patterns from debugging discoveries. Rather than losing hard-won knowledge at session end, this skill captures high-value insights as structured documents that inform future work.

### Research Foundation

This implementation draws from established agent learning research:

- **Voyager** (Wang et al., 2023): Open-ended skill library discovery
- **CASCADE** (2024): Meta-skills for compound learning
- **Reflexion** (Shinn et al., 2023): Verbal reinforcement learning
- **SEAgent** (2025): Trial-and-error in software environments

### Problem Addressed

Agents routinely discover non-obvious solutions through debugging, but this knowledge is lost when:
- Context windows compact or clear
- Sessions end without explicit knowledge capture
- Similar problems are re-investigated from scratch

The Continuous Learning Skill transforms ephemeral discoveries into persistent, retrievable knowledge.

---

## Activation Triggers

The skill activates when ANY of these conditions are detected:

### Trigger 1: Non-Obvious Solution Discovery

Agent completed debugging where the solution wasn't immediately apparent from the error message or documentation.

**Signals**:
- Multiple investigation steps before resolution
- Solution differs from first hypothesis
- Required reading source code or experimentation

### Trigger 2: Workaround Through Investigation

Agent found a workaround through trial-and-error or systematic investigation rather than known solution.

**Signals**:
- Tested multiple approaches before success
- Solution involved undocumented behavior
- Required combining information from multiple sources

### Trigger 3: Non-Apparent Root Cause

Agent resolved an error where the root cause wasn't clear from initial symptoms.

**Signals**:
- Error message was misleading or generic
- Actual cause was upstream of reported location
- Required tracing through multiple layers

### Trigger 4: Project-Specific Patterns

Agent learned patterns specific to this codebase through experimentation.

**Signals**:
- Pattern doesn't exist in general documentation
- Specific to this project's architecture or conventions
- Would be valuable for future agents in this codebase

---

## Integration with Loa Architecture

### Three-Zone Model Compliance

| Zone | Access | Usage |
|------|--------|-------|
| System Zone (`.claude/`) | READ | Load skill definition, protocol |
| State Zone (`grimoires/loa/`) | READ/WRITE | Write extracted skills, trajectory logs |
| App Zone (`src/`, etc.) | READ | Analyze code for extraction context |

**CRITICAL**: Extracted skills MUST write to State Zone only:
- Pending: `grimoires/loa/skills-pending/{skill-name}/SKILL.md`
- Active: `grimoires/loa/skills/`
- Archived: `grimoires/loa/skills-archived/`

### NOTES.md Integration

Cross-reference extracted skills with NOTES.md to prevent duplicates:

1. Before extraction, check `## Learnings` section
2. If similar pattern exists, UPDATE rather than create new skill
3. Add reference to NOTES.md: `## Learnings` entry pointing to skill

**NOTES.md Entry Format**:
```markdown
## Learnings
- [NATS JetStream] Use durable consumers for persistent state → See `skills/nats-jetstream-consumer-durable`
```

### Agent Tagging

Each extracted skill must include the extracting agent:

```yaml
loa-agent: implementing-tasks  # or reviewing-code, auditing-security, etc.
```

This enables filtering skills by agent context for more relevant retrieval.

---

## Quality Gates

All four gates must PASS before skill extraction proceeds. See `.claude/protocols/continuous-learning.md` for detailed criteria.

### Gate 1: Discovery Depth

**Question**: Did the agent actually discover something through investigation?

| Signal | PASS | FAIL |
|--------|------|------|
| Investigation steps | Multiple steps, hypothesis changes | Direct solution from docs |
| Time investment | Significant debugging effort | Quick lookup |
| Learning curve | Non-obvious solution | Obvious in hindsight |

### Gate 2: Reusability

**Question**: Will this help future sessions with similar problems?

| Signal | PASS | FAIL |
|--------|------|------|
| Generalizability | Applies to common patterns | One-off edge case |
| Trigger clarity | Clear when to apply | Vague conditions |
| Solution portability | Works across contexts | Hyper-specific |

### Gate 3: Trigger Clarity

**Question**: Can the skill be reliably retrieved when needed?

| Signal | PASS | FAIL |
|--------|------|------|
| Symptom specificity | Clear error messages/patterns | Generic symptoms |
| Context definition | Defined technology/environment | Unclear scope |
| False positive risk | Low false matches | High noise potential |

### Gate 4: Verification

**Question**: Is the solution proven to work?

| Signal | PASS | FAIL |
|--------|------|------|
| Testing evidence | Verified in this session | Theoretical only |
| Reproduction steps | Clear verification commands | Missing validation |
| Edge cases | Known limitations documented | Unknown failure modes |

---

## Workflow

### Automatic Mode (During Implementation)

During `/implement`, `/review-sprint`, `/audit-sprint`, `/deploy-production`, or `/ride`:

1. **Monitor**: Watch for activation triggers during work
2. **Flag**: When trigger detected, note in trajectory log
3. **Queue**: Add to extraction queue (don't interrupt flow)
4. **Prompt**: At natural break, evaluate quality gates
5. **Extract**: If all gates pass, write to `skills-pending/`

### Manual Mode (/retrospective Command)

At session end or milestone:

1. **Review**: Scan conversation for discovery signals
2. **Candidates**: Present potential extractions with gate assessment
3. **Approve**: User selects which to extract
4. **Write**: Extract approved skills to `skills-pending/`

---

## Skill Format

Use the template at `resources/skill-template.md` for all extracted skills.

### Required Sections

1. **YAML Frontmatter**: Metadata for retrieval
2. **Problem**: Clear statement of the issue
3. **Trigger Conditions**: When to apply this skill
4. **Root Cause**: Why the problem occurs
5. **Solution**: Step-by-step resolution
6. **Verification**: How to confirm success
7. **Anti-Patterns**: Common mistakes to avoid
8. **Related Memory**: NOTES.md cross-references

### Example

See `resources/examples/nats-jetstream-consumer-durable.md` for a complete example.

---

## Phase Gating

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

---

## Skill Lifecycle

```
[Discovery] → [Extraction] → [Pending] → [Active] → [Archived]
                                 ↓
                            [Rejected]
```

### States

| State | Location | Description |
|-------|----------|-------------|
| Pending | `grimoires/loa/skills-pending/` | Awaiting human approval |
| Active | `grimoires/loa/skills/` | Available for retrieval |
| Archived | `grimoires/loa/skills-archived/` | Deprecated or superseded |

### Transitions

- **Pending → Active**: `/skill-audit --approve {skill-name}`
- **Pending → Archived**: `/skill-audit --reject {skill-name}`
- **Active → Archived**: `/skill-audit --prune` (age + no matches)

---

## Configuration

In `.loa.config.yaml`:

```yaml
continuous_learning:
  enabled: true                    # Master toggle
  auto_extract: false              # Require user confirmation (recommended)
  quality_gate_threshold: 4        # All 4 gates must pass
  prune_after_days: 90             # Archive unused skills after N days
  min_match_count: 0               # Minimum retrievals to avoid pruning
  trajectory_logging: true         # Log extraction events
```

---

## Integration with Trajectory Evaluation

All skill extraction events are logged to trajectory:

**Location**: `grimoires/loa/a2a/trajectory/continuous-learning-{date}.jsonl`

**Event Types**:
- `extraction`: Skill extracted to pending
- `approval`: Skill approved to active
- `rejection`: Skill rejected to archived
- `prune`: Skill pruned due to age/non-use
- `match`: Skill retrieved for a problem

**Example Entry**:
```json
{
  "timestamp": "2026-01-18T10:30:00Z",
  "event": "extraction",
  "skill": "nats-jetstream-consumer-durable",
  "agent": "implementing-tasks",
  "gates": {"depth": true, "reusability": true, "trigger": true, "verification": true},
  "source": "sprint-7-task-3"
}
```

---

## Protocol Reference

See `.claude/protocols/continuous-learning.md` for:
- Detailed quality gate criteria with examples
- Zone compliance enforcement
- Pre-commit hook for validation
- Complete trajectory schema
