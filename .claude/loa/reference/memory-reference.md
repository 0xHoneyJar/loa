# Persistent Memory Reference

> Extracted from CLAUDE.loa.md for token efficiency. See: `.claude/loa/CLAUDE.loa.md` for inline summary.

## How It Works (v1.28.0)

Session-spanning observation storage with progressive disclosure for cross-session recall.

1. **Memory Writer Hook**: Captures observations from tool outputs when learning signals detected
2. **Observations File**: Stored in `grimoires/loa/memory/observations.jsonl`
3. **Progressive Disclosure**: Query at different detail levels to manage token budget

## Learning Signals

Automatically captured: discovered, learned, fixed, resolved, pattern, insight

## Query Interface

```bash
# Token-efficient index (~50 tokens per entry)
.claude/scripts/memory-query.sh --index

# Summary view (~200 tokens per entry)
.claude/scripts/memory-query.sh --summary --limit 5

# Full details (~500 tokens)
.claude/scripts/memory-query.sh --full obs-1234567890-abc123

# Filter by type
.claude/scripts/memory-query.sh --type learning

# Free-text search
.claude/scripts/memory-query.sh "authentication pattern"
```

## Configuration

```yaml
memory:
  enabled: true
  max_observations: 10000
  capture:
    discoveries: true
    errors: true
```
