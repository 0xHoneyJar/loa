# Recursive JIT Context Protocol

**Version**: 1.0.0
**Status**: Active
**Date**: 2026-01-22

## Overview

The Recursive JIT Context Protocol extends Loa's existing JIT retrieval system with patterns from Recursive Language Models research. It provides semantic result caching, intelligent condensation, and early-exit coordination for recursive subagent workflows.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Recursive JIT Context System                      │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐      │
│  │  Semantic   │  │ Condensation│  │  Early-Exit │  │  Semantic │      │
│  │   Cache     │  │   Engine    │  │ Coordinator │  │  Recovery │      │
│  │ cache-      │  │ condense.sh │  │ Marker file │  │ recover   │      │
│  │ manager.sh  │  │             │  │ protocol    │  │ --query   │      │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └─────┬─────┘      │
│         │                │                │                │            │
│         └────────────────┴────────────────┴────────────────┘            │
│                                   │                                      │
│                           Integration Layer                              │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Semantic Result Cache

Caches results from skill invocations and subagent work to avoid redundant computation.

**Key Features**:
- Semantic key generation from paths + query + operation
- mtime-based invalidation when source files change
- TTL-based expiration (default: 30 days)
- LRU eviction when cache exceeds size limit
- Integrity verification with SHA256 hashes
- Secret pattern detection on write

**Usage**:
```bash
# Generate cache key
key=$(.claude/scripts/cache-manager.sh generate-key \
  --paths "src/auth.ts,src/user.ts" \
  --query "security vulnerabilities" \
  --operation "audit")

# Check cache before work
if result=$(.claude/scripts/cache-manager.sh get --key "$key"); then
  # Cache hit - use cached result
  echo "$result"
else
  # Cache miss - do work and cache result
  result=$(do_expensive_work)
  .claude/scripts/cache-manager.sh set --key "$key" --condensed "$result"
fi
```

### 2. Condensation Engine

Compresses results to minimal representations while preserving essential information.

**Strategies**:

| Strategy | Target Tokens | Best For |
|----------|---------------|----------|
| `structured_verdict` | ~50 | Audit results, code reviews |
| `identifiers_only` | ~20 | Search results, file listings |
| `summary` | ~100 | Documentation, explanations |

**Usage**:
```bash
# Condense audit result
.claude/scripts/condense.sh condense \
  --strategy structured_verdict \
  --input audit-result.json \
  --externalize \
  --output-dir .claude/cache/full

# Estimate savings
.claude/scripts/condense.sh estimate --input result.json --json
```

### 3. Early-Exit Coordinator

Enables first-to-finish wins pattern for parallel subagent execution.

**Protocol**:
1. Parent initializes session
2. Subagents register and check periodically
3. First success signals and writes result
4. Parent polls for winner
5. Other subagents detect signal and exit early

**File-Based Coordination**:
```
.claude/cache/early-exit/{session_id}/
├── WINNER/              # Atomic mkdir = signal
├── winner_agent         # ID of winning agent
├── signal_time          # Timestamp of signal
├── agents/              # Registered agents
│   ├── agent-1
│   └── agent-2
└── results/             # Agent results
    └── agent-1.json
```

**Usage**:
```bash
# Parent: Initialize
.claude/scripts/early-exit.sh cleanup session-123

# Subagent: Check periodically
if .claude/scripts/early-exit.sh check session-123; then
  # Continue working
else
  # Someone else won - exit
  exit 0
fi

# Subagent: Signal victory
.claude/scripts/early-exit.sh signal session-123 agent-1
echo '{"result":"found"}' | .claude/scripts/early-exit.sh write-result session-123 agent-1

# Parent: Wait for winner
.claude/scripts/early-exit.sh poll session-123 --timeout 30000
.claude/scripts/early-exit.sh read-winner session-123
.claude/scripts/early-exit.sh cleanup session-123
```

### 4. Semantic Recovery Enhancement

Extends tiered recovery with query-based section selection.

**Levels**:

| Level | Tokens | Content |
|-------|--------|---------|
| 1 | ~100 | Session Continuity only |
| 2 | ~500 | + Decision Log + Active beads |
| 3 | ~2000 | Full NOTES.md + Trajectory |

**Semantic Mode** (with `--query`):
- Uses `ck` for semantic search when available
- Falls back to keyword grep
- Selects most relevant sections within token budget

**Usage**:
```bash
# Positional recovery (default)
.claude/scripts/context-manager.sh recover 2

# Semantic recovery
.claude/scripts/context-manager.sh recover 2 --query "authentication flow"
```

## Integration Patterns

### Pattern 1: Cached Skill Invocation

```bash
# Before invoking a skill, check cache
cache_key=$(.claude/scripts/cache-manager.sh generate-key \
  --paths "$target_files" \
  --query "$user_query" \
  --operation "$skill_name")

if cached=$(.claude/scripts/cache-manager.sh get --key "$cache_key"); then
  # Use cached result
  echo "$cached"
else
  # Invoke skill
  result=$(invoke_skill "$skill_name" "$target_files" "$user_query")

  # Condense and cache
  condensed=$(.claude/scripts/condense.sh condense \
    --strategy structured_verdict \
    --input <(echo "$result") \
    --externalize)

  .claude/scripts/cache-manager.sh set \
    --key "$cache_key" \
    --condensed "$condensed" \
    --sources "$target_files"
fi
```

### Pattern 2: Parallel Subagent Racing

```bash
session_id="audit-$(date +%s)"
.claude/scripts/early-exit.sh cleanup "$session_id"

# Launch parallel subagents
for agent in security-scanner test-adequacy architecture-validator; do
  (
    .claude/scripts/early-exit.sh register "$session_id" "$agent"

    while .claude/scripts/early-exit.sh check "$session_id"; do
      result=$(run_check "$agent")
      if [[ -n "$result" ]]; then
        .claude/scripts/early-exit.sh signal "$session_id" "$agent"
        echo "$result" | .claude/scripts/early-exit.sh write-result "$session_id" "$agent"
        break
      fi
    done
  ) &
done

# Wait for first winner
.claude/scripts/early-exit.sh poll "$session_id" --timeout 60000
winner_result=$(.claude/scripts/early-exit.sh read-winner "$session_id" --json)

.claude/scripts/early-exit.sh cleanup "$session_id"
```

### Pattern 3: Semantic Context Recovery

```bash
# After /clear or new session, recover with query
if [[ -n "$last_topic" ]]; then
  .claude/scripts/context-manager.sh recover 2 --query "$last_topic"
else
  .claude/scripts/context-manager.sh recover 1
fi
```

## Configuration

```yaml
# .loa.config.yaml
recursive_jit:
  cache:
    enabled: true
    max_size_mb: 100
    ttl_days: 30
  condensation:
    default_strategy: structured_verdict
    max_condensed_tokens: 50
  recovery:
    semantic_enabled: true
    fallback_to_positional: true
    prefer_ck: true
  early_exit:
    enabled: true
    grace_period_seconds: 5
```

## Performance Targets

| Metric | Target | Validation |
|--------|--------|------------|
| Cache hit rate | >30% (30 days) | `cache-manager.sh stats` |
| Context reduction | 30-40% | Condensation benchmarks |
| Cache lookup | <100ms | Performance tests |
| Condensation | <50ms | Performance tests |

## Backward Compatibility

All new features are additive and opt-in:
- Existing JIT retrieval works unchanged
- Cache disabled by default in new projects
- Recovery without `--query` uses positional mode
- Early-exit only active when explicitly initialized

## Related Documentation

- `jit-retrieval.md` - Base JIT retrieval protocol
- `session-continuity.md` - Session lifecycle
- `context-compaction.md` - Compaction rules
- `semantic-cache.md` - Cache operations detail
