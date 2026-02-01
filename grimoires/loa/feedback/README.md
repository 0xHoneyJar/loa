# Loa Feedback Directory

This directory stores compound learnings captured from development sessions.

## File Format

Files should be named by date: `YYYY-MM-DD.yaml`

Example:
```yaml
schema_version: 1
date: "2026-01-31"
cycle: "cycle-002"

learnings:
  - id: L-0001
    timestamp: "2026-01-31T10:30:00Z"
    type: pattern  # pattern | gap | friction | improvement | anti_pattern
    title: "Brief title (max 200 chars)"
    context: "When/where this was discovered"
    trigger: "What conditions indicate this applies"
    solution: "The pattern/solution discovered"
    verified: true
    quality_gates:
      discovery_depth: 7    # 1-10
      reusability: 8        # 1-10
      trigger_clarity: 9    # 1-10
      verification: 8       # 1-10
    effectiveness:
      applied_count: 0
      success_rate: 0.0
    source:
      sprint: "sprint-1"
      task: "T1.2"
      agent: "implementing-tasks"
    tags:
      - relevant-tag
```

## Schema

See `.claude/schemas/learnings.schema.json` for full schema definition.

## Querying

Learnings are indexed by the oracle system:

```bash
# Index all learnings
.claude/scripts/loa-learnings-index.sh index

# Query learnings
.claude/scripts/anthropic-oracle.sh query "search terms" --scope loa
```

## Integration

Learnings captured here feed into the recursive improvement loop:
1. Feedback captured via `/feedback` or `/retrospective`
2. Oracle indexes learnings
3. Future queries surface relevant patterns
4. Patterns inform skill execution
5. Better execution generates better feedback

---

*Part of Loa's Compound Learning System (v1.10.0)*
