# /skill-audit

## Purpose

Review and manage extracted skills lifecycle. Approve pending skills, reject low-quality ones, prune unused skills, and view statistics.

## Invocation

```
/skill-audit --pending
/skill-audit --approve <skill-name>
/skill-audit --reject <skill-name>
/skill-audit --prune
/skill-audit --stats
```

## Agent

Activates `continuous-learning` skill from `.claude/skills/continuous-learning/`.

## Subcommands

| Subcommand | Action | Output |
|------------|--------|--------|
| `--pending` | List skills awaiting approval | Table with name, date, agent |
| `--approve <name>` | Move skill to active | Confirmation, trajectory log |
| `--reject <name>` | Move to archived with reason | Reason prompt, trajectory log |
| `--prune` | Review for low-value skills | Pruning report, confirmations |
| `--stats` | Show skill usage statistics | Usage counts, match rates |

---

## --pending

List all skills in `grimoires/loa/skills-pending/` awaiting approval.

### Usage

```
/skill-audit --pending
```

### Output

```markdown
## Pending Skills

| Skill | Extracted By | Date | Quality Gates |
|-------|--------------|------|---------------|
| nats-consumer-durable | implementing-tasks | 2026-01-18 | 4/4 PASS |
| typescript-type-guard | reviewing-code | 2026-01-17 | 4/4 PASS |

Total: 2 skills pending

**Actions**:
- `/skill-audit --approve <name>` to approve
- `/skill-audit --reject <name>` to reject
```

### No Pending Skills

```markdown
## Pending Skills

No skills pending approval.

Run `/retrospective` to extract skills from discoveries.
```

---

## --approve

Move a skill from `skills-pending/` to `skills/` (active).

### Usage

```
/skill-audit --approve nats-consumer-durable
```

### Workflow

```
grimoires/loa/skills-pending/{name}/
          │
          ▼
    /skill-audit --approve {name}
          │
          ├──► Validate skill exists
          ├──► Move to grimoires/loa/skills/{name}/
          ├──► Log "approval" event to trajectory
          └──► Notify user
```

### Output

```markdown
## Skill Approved

✓ **nats-consumer-durable** moved to active skills

**Path**: `grimoires/loa/skills/nats-consumer-durable/SKILL.md`
**Logged**: Approval event written to trajectory

The skill is now active and available for retrieval in future sessions.
```

### Trajectory Entry

```json
{
  "timestamp": "2026-01-18T15:00:00Z",
  "type": "approval",
  "skill_name": "nats-consumer-durable",
  "approved_by": "user",
  "source_path": "grimoires/loa/skills-pending/nats-consumer-durable/SKILL.md",
  "destination_path": "grimoires/loa/skills/nats-consumer-durable/SKILL.md"
}
```

### Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| "Skill not found" | Doesn't exist in pending | Check name with `--pending` |
| "Already approved" | Exists in skills/ | No action needed |

---

## --reject

Move a skill from `skills-pending/` to `skills-archived/` with reason.

### Usage

```
/skill-audit --reject nats-consumer-durable
```

### Workflow

```
grimoires/loa/skills-pending/{name}/
          │
          ▼
    /skill-audit --reject {name}
          │
          ├──► Prompt for rejection reason
          ├──► Move to grimoires/loa/skills-archived/{name}/
          ├──► Log "rejection" event with reason to trajectory
          └──► Notify user
```

### Interaction

```markdown
## Reject Skill

Rejecting: **nats-consumer-durable**

Please provide a reason for rejection:
```

User provides reason, then:

```markdown
## Skill Rejected

✗ **nats-consumer-durable** archived

**Reason**: "Too specific to this project's NATS configuration"
**Path**: `grimoires/loa/skills-archived/nats-consumer-durable/SKILL.md`
**Logged**: Rejection event written to trajectory
```

### Trajectory Entry

```json
{
  "timestamp": "2026-01-18T15:00:00Z",
  "type": "rejection",
  "skill_name": "nats-consumer-durable",
  "reason": "Too specific to this project's NATS configuration",
  "rejected_by": "user",
  "source_path": "grimoires/loa/skills-pending/nats-consumer-durable/SKILL.md",
  "destination_path": "grimoires/loa/skills-archived/nats-consumer-durable/SKILL.md"
}
```

---

## --prune

Review active skills for pruning based on age and usage.

### Usage

```
/skill-audit --prune
```

### Pruning Criteria

| Criterion | Threshold | Action |
|-----------|-----------|--------|
| **Age without use** | > 90 days since last match | Suggest archive |
| **Low match count** | < 2 matches total | Suggest archive |
| **Superseded** | Newer skill covers same problem | Suggest merge or archive |

### Workflow

1. Scan `grimoires/loa/skills/` for all active skills
2. Check trajectory logs for match events
3. Calculate age and match count for each skill
4. Present pruning candidates
5. Confirm each prune action

### Output

```markdown
## Pruning Review

Analyzing active skills...

### Pruning Candidates

| Skill | Age (days) | Matches | Reason |
|-------|------------|---------|--------|
| old-webpack-config | 120 | 0 | Age > 90 days, no matches |
| legacy-babel-fix | 95 | 1 | Age > 90 days, low matches |

### Recommendations

1. **old-webpack-config**: Archive (unused for 120 days)
2. **legacy-babel-fix**: Archive (low value, 1 match in 95 days)

Would you like to:
- Archive all candidates: `/skill-audit --prune --confirm`
- Review individually: `/skill-audit --reject <name>`
- Skip pruning: No action
```

### Trajectory Entry

```json
{
  "timestamp": "2026-01-18T15:00:00Z",
  "type": "prune",
  "skill_name": "old-webpack-config",
  "prune_reason": "Age > 90 days with 0 matches",
  "age_days": 120,
  "match_count": 0,
  "destination_path": "grimoires/loa/skills-archived/old-webpack-config/SKILL.md"
}
```

---

## --stats

Show statistics for all extracted skills.

### Usage

```
/skill-audit --stats
```

### Output

```markdown
## Skill Statistics

### Overview

| Status | Count |
|--------|-------|
| Active | 5 |
| Pending | 2 |
| Archived | 3 |
| **Total** | **10** |

### Active Skills

| Skill | Agent | Created | Matches | Last Match |
|-------|-------|---------|---------|------------|
| nats-consumer-durable | implementing-tasks | 2026-01-10 | 7 | 2026-01-18 |
| postgres-connection-pool | implementing-tasks | 2026-01-05 | 4 | 2026-01-15 |
| react-memo-deps | reviewing-code | 2026-01-08 | 3 | 2026-01-17 |
| csrf-token-refresh | auditing-security | 2026-01-12 | 2 | 2026-01-14 |
| docker-cache-bust | deploying-infrastructure | 2026-01-03 | 1 | 2026-01-03 |

### By Agent

| Agent | Skills | Matches |
|-------|--------|---------|
| implementing-tasks | 2 | 11 |
| reviewing-code | 1 | 3 |
| auditing-security | 1 | 2 |
| deploying-infrastructure | 1 | 1 |

### Match Rate

- **Total matches**: 17
- **Match rate**: 3.4 matches/skill
- **Most matched**: nats-consumer-durable (7)
- **Least matched**: docker-cache-bust (1)
```

---

## File Operations

### Directory Structure

```
grimoires/loa/
├── skills/                    # Active skills
│   └── {skill-name}/
│       └── SKILL.md
├── skills-pending/            # Awaiting approval
│   └── {skill-name}/
│       └── SKILL.md
└── skills-archived/           # Rejected or pruned
    └── {skill-name}/
        └── SKILL.md
```

### File Movement

All operations use standard file operations:
- Create directory if needed
- Move SKILL.md to new location
- Log to trajectory

---

## Trajectory Logging

All audit actions are logged to:
```
grimoires/loa/a2a/trajectory/continuous-learning-{YYYY-MM-DD}.jsonl
```

### Event Types

| Type | When | Key Fields |
|------|------|------------|
| `approval` | Skill approved | skill_name, approved_by |
| `rejection` | Skill rejected | skill_name, reason, rejected_by |
| `prune` | Skill pruned | skill_name, prune_reason, age_days, match_count |
| `match` | Skill used in session | skill_name, context, confidence |

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Skill not found" | Wrong name | Use `--pending` or `--stats` to list |
| "Already approved" | In skills/ | No action needed |
| "Already archived" | In skills-archived/ | Manually move if needed |
| "Trajectory directory missing" | First use | Creates automatically |

---

## Configuration

Options in `.loa.config.yaml`:

```yaml
continuous_learning:
  pruning:
    enabled: true
    age_threshold_days: 90     # Archive after N days
    min_match_count: 2         # Minimum matches to keep
    auto_prune: false          # Require confirmation
```

---

## Related Commands

| Command | Purpose |
|---------|---------|
| `/retrospective` | Extract new skills |
| `/implement` | Primary discovery context |

## Protocol Reference

See `.claude/protocols/continuous-learning.md` for:
- Complete lifecycle documentation
- Zone compliance rules
- Trajectory schema
