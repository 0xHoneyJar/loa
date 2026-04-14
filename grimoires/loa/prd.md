# Product Requirements Document: Vision Query Health Check

**Cycle**: cycle-1 (spiral-e2e-test-001)
**Branch**: feat/spiral-spiral-e2e-test-001-cycle-1

## Overview

Add a `--health` flag to `vision-query.sh` that provides a JSON health report of the Vision Registry. This enables automated monitoring, preflight checks, and integration with other scripts that need to verify registry state.

## Goals

1. Report total vision entry count
2. Report entries grouped by status (Captured, Exploring, Proposed, Implemented, Deferred, Archived, Rejected)
3. Report last-modified timestamp of the newest entry file
4. Exit 0 if entries exist, exit 1 if registry is empty
5. Output as machine-readable JSON

## Non-Goals

- Modifying any existing query/filter behavior
- Adding health checks to other vision scripts
- Reporting disk usage or file integrity beyond counts

## Success Metrics

- `--health` returns correct JSON matching entry file reality
- Exit codes match specification (0 = healthy, 1 = empty)
- All existing tests continue to pass (no regressions)
- New tests cover: populated registry, empty registry, JSON schema correctness

## Functional Requirements

### FR-1: `--health` flag
When `--health` is passed, the script bypasses normal query/filter logic and outputs a JSON health report, then exits.

### FR-2: JSON output schema
```json
{
  "total": 9,
  "by_status": {
    "Captured": 6,
    "Exploring": 1,
    "Proposed": 0,
    "Implemented": 1,
    "Deferred": 0,
    "Archived": 0,
    "Rejected": 0
  },
  "newest_entry_modified": "2026-04-14T06:00:00Z",
  "healthy": true
}
```

### FR-3: Exit codes
- 0: At least one entry exists (`healthy: true`)
- 1: No entries found (`healthy: false, total: 0`)

### FR-4: Mutual exclusivity
`--health` is incompatible with query filters (`--tags`, `--status`, `--source`, etc.) and `--rebuild-index`. If combined, exit 2 with error message.

## Technical Constraints

- Must use existing `_parse_entry()` for status extraction
- Must use `jq --arg` / `--argjson` for safe JSON construction
- Must follow existing exit code conventions
- Must use `stat` for file modification timestamps (portable)
