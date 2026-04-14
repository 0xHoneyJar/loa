# Sprint Plan: Vision Query Health Check

**Cycle**: cycle-1 (spiral-e2e-test-001)

## Sprint 1: `--health` flag implementation

### T1.1: Add `--health` argument parsing and mutual exclusivity check
- Add `DO_HEALTH=false` variable
- Add `--health)` case in arg parser
- After parsing, validate `--health` is not combined with `--rebuild-index` or any filter flags
- Exit 2 with clear error if combined
- **AC**: `--health` accepted, `--health --tags foo` exits 2

### T1.2: Implement `_health_report()` function
- Scan `$ENTRIES_DIR/vision-*.md` files
- Parse each with `_parse_entry()`, skip quarantined entries
- Count entries by status using associative-style counting
- Find newest file mtime via `stat -c %Y` (GNU coreutils)
- Convert epoch to ISO-8601 via `date -u -d @epoch`
- Build JSON via `jq -n --argjson`
- Exit 0 if total > 0, exit 1 if total == 0
- **AC**: JSON output matches PRD schema, correct exit codes

### T1.3: Add `--health` to usage help
- Add line to `_usage()` function
- **AC**: `--help` shows `--health` option

### T1.4: Write unit tests
- Test: `--health` returns valid JSON with expected fields
- Test: `--health` reports correct total count
- Test: `--health` reports correct by_status breakdown
- Test: `--health` with empty registry exits 1 with `healthy: false`
- Test: `--health` with populated registry exits 0 with `healthy: true`
- Test: `--health --tags` exits 2 (mutual exclusivity)
- Test: `--health --rebuild-index` exits 2 (mutual exclusivity)
- Test: `--health` newest_entry_modified is valid ISO timestamp
- **AC**: All tests pass, no regressions in existing tests

## Verification

```bash
bats tests/unit/vision-query.bats
```
