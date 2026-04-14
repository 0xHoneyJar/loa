# SDD: Vision Query Health Check

**Cycle**: cycle-1 (spiral-e2e-test-001)

## Design

### Approach

Add a `--health` flag to `vision-query.sh` that short-circuits before the normal query/filter pipeline. The health check scans all entry files using the existing `_parse_entry()` function, aggregates status counts, finds the newest file modification timestamp, and outputs a JSON report.

### Implementation Plan

1. **Argument parsing**: Add `--health` flag (`DO_HEALTH=false`) alongside existing flags
2. **Mutual exclusivity check**: After arg parsing, validate `--health` is not combined with filters or `--rebuild-index`
3. **Health function** `_health_report()`:
   - Scan `$ENTRIES_DIR/vision-*.md` files
   - Parse each with `_parse_entry()`, count valid entries by status
   - Track newest file mtime via `stat -c %Y` (GNU) with fallback
   - Build JSON with `jq -n --argjson`
   - Set `healthy: true/false` based on total > 0
4. **Exit codes**: 0 if total > 0, 1 if total == 0

### JSON Schema

```json
{
  "total": <int>,
  "by_status": {
    "Captured": <int>,
    "Exploring": <int>,
    "Proposed": <int>,
    "Implemented": <int>,
    "Deferred": <int>,
    "Archived": <int>,
    "Rejected": <int>
  },
  "newest_entry_modified": "<ISO-8601 or null>",
  "healthy": <bool>
}
```

### File Modifications

| File | Change |
|------|--------|
| `.claude/scripts/vision-query.sh` | Add `--health` flag, `_health_report()` function |
| `tests/unit/vision-query.bats` | Add tests for `--health` |

### Exit Code Mapping

| Scenario | Exit |
|----------|------|
| `--health` with entries | 0 |
| `--health` with no entries | 1 |
| `--health` combined with filters | 2 |
