# Sprint 60 (sprint-4) Implementation Report

## Summary

Sprint 4 delivers trajectory archive and import capabilities — `trajectory-export.sh` exports cycle JSONL through the redaction pipeline into portable compressed archives, `trajectory-import.sh` reverses the process, archive-cycle integration triggers export at cycle boundaries, and compact-trajectory.sh gains state-dir archive retention enforcement.

**Smoke tests**: Export (clean), export (blocked), gzip round-trip, import — all passing.

## Tasks Completed

### Task 1: Create trajectory-export.sh (FR-3 — High)
**File**: `.claude/scripts/trajectory-export.sh` (~280 lines)

- `--cycle CYCLE_ID` required parameter with alphanumeric validation
- Collects all JSONL from `trajectory/current/` via `get_state_trajectory_dir()`
- Runs content through `redact-export.sh` (fail-closed) — blocked trajectories exit 1 with audit findings
- Streaming mode: for exports >MAX_EXPORT_SIZE_MB, processes per-entry through redaction
- Builds export with schema_version=1, summary (total_entries, date_range, agents, phases, file_count), entries array, redaction_report
- Entry schema validation: ts (ISO8601), agent, phase, action required — invalid entries logged and skipped
- Compression: gzip by default, `--no-compress` to skip
- Size check against `trajectory.archive.max_export_size_mb` config (default 50MB)
- `--git-commit` opt-in: stages file, warns about LFS for >5MB
- Moves processed JSONL to `trajectory/current/exported-{cycle}/`
- Writes output to `trajectory/archive/{cycle_id}.json[.gz]`
- Uses jq for JSON assembly (atomic tmp+mv pattern)

### Task 2: Create trajectory-import.sh (FR-3 — Medium)
**File**: `.claude/scripts/trajectory-import.sh` (~100 lines)

- Accepts `.json` or `.json.gz` files (auto-decompresses)
- Validates `schema_version: 1`
- Extracts entries into `trajectory/current/imported-{cycle}-{date}.jsonl`
- Reports import count with export metadata

### Task 3: Integrate with /archive-cycle (FR-3 — Medium)
**File**: `.claude/scripts/archive-cycle.sh` (+8 lines)

- After copying artifacts, calls `trajectory-export.sh --cycle cycle-NNN`
- Respects `trajectory.archive.git_commit` config
- Non-blocking: export failure logged as warning but doesn't block archive

### Task 4: Update compact-trajectory.sh retention (FR-3 — Low)
**File**: `.claude/scripts/compact-trajectory.sh` (+35 lines, Phase 3)

- Phase 3: scans state-dir `trajectory/archive/` for files older than ARCHIVE_DAYS
- Handles both `.json` and `.json.gz` export files
- Filesystem delete only (no git history rewriting)
- Respects existing archive_days config (default 365)
- Resolves state-dir via path-lib.sh with fallback to default

## Acceptance Criteria Status

### Task 1 (11/11):
- [x] --cycle CYCLE_ID required parameter
- [x] Collects JSONL from trajectory/current/ using get_state_trajectory_dir()
- [x] Runs through redact-export.sh (fail-closed)
- [x] Streaming mode for exports >MAX_EXPORT_SIZE_MB
- [x] Builds export with schema_version, summary, entries, redaction_report
- [x] Entry schema validation (ts, agent, phase, action required)
- [x] Compression: gzip by default
- [x] Size check against config
- [x] --git-commit opt-in with LFS warning
- [x] Moves processed JSONL to exported-{cycle}/
- [x] Writes to trajectory/archive/{cycle_id}.json[.gz]

### Task 2 (4/4):
- [x] Accepts .json or .json.gz
- [x] Validates schema_version: 1
- [x] Extracts entries into trajectory/current/imported-{cycle}-{date}.jsonl
- [x] Reports import count

### Task 3 (3/3):
- [x] Calls trajectory-export.sh --cycle after artifacts
- [x] Respects trajectory.archive.git_commit config
- [x] Non-blocking: failure logged but doesn't block

### Task 4 (3/3):
- [x] Scans trajectory/archive/ for files older than retention_days
- [x] Filesystem delete only
- [x] Respects existing retention_days config

## Files Changed

| File | Status | Lines |
|------|--------|-------|
| `.claude/scripts/trajectory-export.sh` | NEW | ~280 |
| `.claude/scripts/trajectory-import.sh` | NEW | ~100 |
| `.claude/scripts/archive-cycle.sh` | MODIFIED | +8 |
| `.claude/scripts/compact-trajectory.sh` | MODIFIED | +35 |

## Test Results

Manual smoke tests (export clean, export blocked, gzip round-trip, import validation) all passing.

## Next Steps

Proceed to `/review-sprint sprint-4` for senior technical review.
