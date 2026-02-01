# Memory Directory

This directory stores formalized memory entries for cross-session persistence.

## Structure

```
memory/
├── facts.yaml          # Stable project facts (permanent)
├── decisions.yaml      # Architecture decisions (permanent)
├── learnings.yaml      # Extracted patterns (90-day TTL)
├── errors.yaml         # Error-solution pairs (30-day TTL)
├── preferences.yaml    # User preferences (permanent)
└── archive/            # Expired/superseded memories
```

## Schema

Memory entries follow the schema at `.claude/schemas/memory.schema.json`.

## Example Entry

```yaml
- id: MEM-20260201-001
  category: decision
  content: |
    Use PostgreSQL for the database layer due to JSONB support.
  summary: PostgreSQL selected over SQLite
  confidence: 0.95
  source:
    session_id: abc123
    agent: designing-architecture
    timestamp: 2026-02-01T10:30:00Z
  ttl: permanent
  tags: [database, architecture]
```

## Categories

| Category | TTL | Min Confidence | Purpose |
|----------|-----|----------------|---------|
| `fact` | permanent | 0.8 | Stable project truths |
| `decision` | permanent | 0.9 | Architecture decisions |
| `learning` | 90d | 0.7 | Extracted patterns |
| `error` | 30d | 0.6 | Error-solution pairs |
| `preference` | permanent | 0.5 | User preferences |

## Related

- Protocol: `.claude/protocols/memory.md`
- Schema: `.claude/schemas/memory.schema.json`
- Config: `.loa.config.yaml` (`memory_schema` section)
