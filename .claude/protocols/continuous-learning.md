# Continuous Learning Protocol

> Autonomous skill extraction for Loa Framework
>
> Research Foundation: Voyager (Wang et al., 2023), CASCADE (2024), Reflexion (Shinn et al., 2023), SEAgent (2025)

## Purpose

Agents lose discovered knowledge when sessions end. When an agent spends significant time debugging a non-obvious issue and discovers the root cause, that knowledge exists only in the conversation history. This protocol enables persistent skill extraction that survives across sessions.

## Evaluation Flow

A discovery is extracted only after all four quality gates below pass, in order (Discovery Depth, Reusability, Trigger Clarity, Verification), then a NOTES.md cross-reference check: an exact match in the Decision Log or Technical Debt sections skips extraction, a partial match gets linked from the extracted skill, and no match proceeds.

Extraction: generate the skill from `skill-template.md`, write it to `grimoires/loa/skills-pending/{name}/SKILL.md`, log the extraction event to the trajectory log, and update NOTES.md's Session Log.

## Quality Gates

### Gate 1: Discovery Depth

**Question**: Was this non-obvious?

| Indicator | Verdict | Example |
|-----------|---------|---------|
| Solution found via documentation lookup | FAIL | "The docs say to add this config option" |
| First Google result provided answer | FAIL | "Stack Overflow top answer worked" |
| Required multiple debugging attempts | PASS | "Tried 4 approaches before this worked" |
| Trial-and-error discovery | PASS | "Experimented with different settings" |
| Required reading source code | PASS | "Had to trace through the library code" |

**Configuration** (`.loa.config.yaml`):
```yaml
continuous_learning:
  min_discovery_depth: 2  # 1=any, 2=moderate, 3=significant
```

### Gate 2: Reusability

**Question**: Will this help future tasks?

| Indicator | Verdict | Example |
|-----------|---------|---------|
| Project-specific hardcoded value | FAIL | "Set timeout to 5000ms for this API" |
| One-time configuration | FAIL | "Add this env var for local dev" |
| Pattern applies to technology | PASS | "All JetStream consumers need this" |
| Error message is common | PASS | "This error happens in many contexts" |
| Workaround is generalizable | PASS | "This approach works for any async retry" |

### Gate 3: Trigger Clarity

**Question**: Can trigger conditions be precisely described?

| Indicator | Verdict | Example |
|-----------|---------|---------|
| "Sometimes it doesn't work" | FAIL | Vague symptom |
| "It feels slow" | FAIL | Subjective symptom |
| Exact error message captured | PASS | "Error: CONSUMER_ALREADY_EXISTS" |
| Specific conditions documented | PASS | "After process restart with durable=false" |
| Clear reproduction steps | PASS | "1. Start consumer 2. Restart process 3. Observe" |

### Gate 4: Verification

**Question**: Has the solution been verified?

| Indicator | Verdict | Example |
|-----------|---------|---------|
| "This should work" | FAIL | Untested theory |
| "I read it fixes this" | FAIL | No verification |
| Tested in current session | PASS | "Applied fix, verified working" |
| Test passes after change | PASS | "Unit test now passes" |
| Production behavior confirmed | PASS | "Deployed and monitored" |

## Phase Gating

Continuous learning activates only during implementation and operational phases.

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

## Zone Compliance

Extracted skills MUST NOT write to System Zone; the write-guard hooks documented in `zone-system.md` enforce this boundary generally. This protocol's specific paths:

| Action | Allowed Location | Forbidden Location |
|--------|------------------|-------------------|
| Create extracted skill | `grimoires/loa/skills-pending/` | `.claude/skills/` |
| Activate approved skill | `grimoires/loa/skills/` | `.claude/skills/` |
| Archive rejected skill | `grimoires/loa/skills-archived/` | Any System Zone |
| Log extraction event | `grimoires/loa/a2a/trajectory/` | Anywhere else |

### State Zone Directory Structure

```
grimoires/loa/
├── skills/                       # Active skills (approved)
├── skills-pending/               # Skills awaiting approval
└── skills-archived/              # Rejected/pruned skills
```

## Trajectory Logging

All skill extraction events are logged to `grimoires/loa/a2a/trajectory/continuous-learning-{YYYY-MM-DD}.jsonl`.

### Event Types

| Event Type | When Logged | Required Fields |
|------------|-------------|-----------------|
| `extraction` | Skill created in pending | skill_name, quality_gates, agent, phase |
| `approval` | Skill moved to active | skill_name, approved_by |
| `rejection` | Skill archived | skill_name, reason, rejected_by |
| `prune` | Skill removed via pruning | skill_name, prune_reason, age_days |
| `match` | Skill triggered in future session | skill_name, context, confidence |

### JSONL Schema

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

## Configuration Reference

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

  # Quality gate thresholds
  min_discovery_depth: 2      # 1=any, 2=moderate, 3=significant
  require_verification: true

  # Cross-reference behavior
  check_notes_md: true
  deduplicate: true

  # Pruning
  prune_after_days: 90
  prune_min_matches: 2
```

## Skill Lifecycle

```
Extract → skills-pending/ → Review → skills/ (or archive)
                              │
                    ┌────────┴────────┐
                    ▼                 ▼
               skills/          skills-archived/
              (approved)        (rejected/pruned)
```

### States

| State | Location | Description |
|-------|----------|-------------|
| Pending | `skills-pending/` | Awaiting human review via `/skill-audit --pending` |
| Active | `skills/` | Approved and available for matching |
| Archived | `skills-archived/` | Rejected or pruned, retained for audit |

### Pruning Criteria

Skills may be pruned when:
- Age > 90 days without a match
- Match count < 2 (low value)
- Superseded by newer skill (merge recommended)

## Related Protocols

- `.claude/protocols/structured-memory.md` - NOTES.md integration
- `.claude/protocols/trajectory-evaluation.md` - Reasoning audit trail
- `.claude/protocols/session-continuity.md` - Session recovery
