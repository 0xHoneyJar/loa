# Semantic Cache Protocol

**Version**: 1.0.0
**Status**: Active
**Date**: 2026-01-22

## Overview

The Semantic Cache provides cross-session caching of skill results and subagent outputs. It uses semantic key generation to enable cache hits across similar queries and mtime-based invalidation to ensure freshness.

## Cache Architecture

```
.claude/cache/
├── .gitignore           # Excludes all cache data
├── index.json           # Cache index with metadata
├── results/             # Condensed result files
│   └── {key}.json
├── full/                # Externalized full results
│   └── {hash}.json
└── early-exit/          # Early-exit coordination
    └── {session_id}/
```

## Index Schema

```json
{
  "schema_version": "1.0.0",
  "created_at": "2026-01-22T00:00:00Z",
  "entries": {
    "{cache_key}": {
      "created_at": 1737500000,
      "cached_mtime": 1737500000,
      "source_paths": ["src/auth.ts", "src/user.ts"],
      "integrity_hash": "sha256...",
      "full_result_path": ".claude/cache/full/abc123.json",
      "hit_count": 5,
      "last_hit": 1737600000
    }
  },
  "stats": {
    "hits": 42,
    "misses": 18,
    "invalidations": 3
  }
}
```

## Key Generation

Cache keys are generated from three components:

1. **Paths**: Sorted, deduplicated list of source files
2. **Query**: Normalized (lowercase, trimmed) query string
3. **Operation**: Skill or operation name

```bash
# Key formula
key = sha256(sorted_paths + "|" + normalized_query + "|" + operation)

# Example
.claude/scripts/cache-manager.sh generate-key \
  --paths "src/user.ts,src/auth.ts" \
  --query "Find SQL injection" \
  --operation "security-audit"

# Same key regardless of path order
.claude/scripts/cache-manager.sh generate-key \
  --paths "src/auth.ts,src/user.ts" \
  --query "find sql injection" \
  --operation "security-audit"
```

## Invalidation Rules

### 1. mtime-Based Invalidation

When any source file is modified after the cache entry was created, the entry is invalidated on read.

```bash
# Entry created at mtime 1000
# src/auth.ts modified at mtime 1500
# Next get() invalidates automatically
```

### 2. TTL-Based Expiration

Entries older than TTL (default: 30 days) are invalidated on read.

```bash
# Configure TTL
recursive_jit.cache.ttl_days: 30

# Or via environment
LOA_CACHE_TTL_DAYS=7
```

### 3. Manual Invalidation

Invalidate by path pattern:

```bash
.claude/scripts/cache-manager.sh invalidate --paths "src/auth/*"
```

### 4. Integrity Verification

Each entry stores a SHA256 hash of the content. On read, the hash is verified. Mismatches trigger invalidation.

## Security

### Secret Detection

The cache rejects content containing common secret patterns:

- `PRIVATE.KEY`, `BEGIN RSA`, `BEGIN EC PRIVATE`
- `password=`, `secret=`, `api_key=`, `apikey=`
- `access_token=`, `bearer=`

```bash
# This will fail
.claude/scripts/cache-manager.sh set \
  --key abc \
  --condensed '{"password": "secret123"}'
# Error: Secret patterns detected
```

### File Permissions

Cache files inherit directory permissions. For sensitive environments, restrict `.claude/cache/` access.

## Operations

### Get

```bash
# Returns cached content on hit, error on miss
result=$(.claude/scripts/cache-manager.sh get --key "$key")
exit_code=$?

# Exit codes:
# 0 - Cache hit, content on stdout
# 1 - Cache miss (any reason)
```

### Set

```bash
.claude/scripts/cache-manager.sh set \
  --key "$key" \
  --condensed '{"verdict":"PASS"}' \
  --sources "src/auth.ts,src/user.ts" \
  --full ./full-result.json
```

### Delete

```bash
.claude/scripts/cache-manager.sh delete --key "$key"
```

### Stats

```bash
.claude/scripts/cache-manager.sh stats --json
# {
#   "enabled": true,
#   "entries": 42,
#   "hits": 156,
#   "misses": 48,
#   "invalidations": 12,
#   "hit_rate_pct": "76.47",
#   "size_mb": "2.34",
#   "max_size_mb": "100"
# }
```

### Cleanup

LRU eviction when cache exceeds size limit:

```bash
.claude/scripts/cache-manager.sh cleanup --max-size-mb 50
```

### Clear

Remove all cache entries:

```bash
.claude/scripts/cache-manager.sh clear
```

## Configuration

```yaml
# .loa.config.yaml
recursive_jit:
  cache:
    enabled: true          # Master toggle
    max_size_mb: 100       # LRU eviction threshold
    ttl_days: 30           # Entry expiration
```

**Environment Overrides** (highest priority):
- `LOA_CACHE_ENABLED=false` - Disable cache
- `LOA_CACHE_MAX_SIZE_MB=50` - Override size limit
- `LOA_CACHE_TTL_DAYS=7` - Override TTL

## Integration with Condensation

The cache works with the condensation engine:

```bash
# Condense result and cache
condensed=$(.claude/scripts/condense.sh condense \
  --strategy structured_verdict \
  --input result.json \
  --externalize \
  --output-dir .claude/cache/full)

.claude/scripts/cache-manager.sh set \
  --key "$cache_key" \
  --condensed "$condensed"
```

The `--externalize` flag stores full results separately, with condensed output containing a reference to the full file.

## Best Practices

1. **Key Design**: Include all inputs that affect output in the key
2. **Source Tracking**: Always provide `--sources` for mtime invalidation
3. **Externalization**: Use for results >1KB to keep index compact
4. **Cleanup**: Run periodic cleanup to prevent unbounded growth
5. **Monitoring**: Check `stats` periodically to tune TTL and size

## Troubleshooting

### Low Hit Rate

- Keys may be too specific - normalize queries more aggressively
- Source files changing frequently - consider longer-lived cache keys
- TTL too short - increase for stable codebases

### Cache Corruption

```bash
# Verify and rebuild
.claude/scripts/cache-manager.sh clear
# Cache will rebuild naturally
```

### Performance Issues

```bash
# Check size
.claude/scripts/cache-manager.sh stats

# Aggressive cleanup
.claude/scripts/cache-manager.sh cleanup --max-size-mb 20
```
