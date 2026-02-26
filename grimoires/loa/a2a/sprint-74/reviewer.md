# Implementation Report: Sprint 74 — Foundation: Schema, Library, Query, Shadow Mode

**Sprint**: 1 (Global: 74)
**Cycle**: cycle-041 — Vision-Aware Planning
**Branch**: `feat/cycle-041-vision-aware-planning`

---

## Summary

Implemented the complete Vision Integration Layer foundation: shared library extraction from `bridge-vision-capture.sh`, registry schema, query script with scoring algorithm, shadow mode logging pipeline, configuration, and comprehensive tests. All 8 sprint tasks completed. **49 BATS tests passing.**

## Tasks Completed

### T1: Create `vision-lib.sh` shared library
- **File**: `.claude/scripts/vision-lib.sh` (new, 380 lines)
- Extracted 4 functions from `bridge-vision-capture.sh`: `vision_update_status()`, `vision_record_ref()`, `vision_extract_tags()`, `vision_check_lore_elevation()`
- Added 5 new functions: `vision_load_index()`, `vision_match_tags()`, `vision_sanitize_text()`, `vision_validate_entry()`, `vision_atomic_write()`
- Sources `bootstrap.sh` and `compat-lib.sh`
- jq dependency check at source time
- **Shell safety (SKP-005)**: Vision IDs validated against `^vision-[0-9]{3}$`, tags against `^[a-z][a-z0-9_-]*$`, paths validated against project root
- `_vision_require_flock()` follows same pattern as event-bus.sh (macOS keg-only path detection)

### T2: Refactor `bridge-vision-capture.sh` to source library
- **File**: `.claude/scripts/bridge-vision-capture.sh` (modified)
- Added `source "$SCRIPT_DIR/vision-lib.sh"` at top
- Error exit if `vision-lib.sh` is missing (IMP-009): `"ERROR: vision-lib.sh not found — run /update-loa to restore"`
- Entry points (`--check-relevant`, `--record-reference`, `--update-status`, main capture) all delegate to library functions
- `--check-relevant` uses `vision_extract_tags` from library for tag mapping
- **Smoke tested**: `--help`, `--check-relevant /dev/null` both work correctly

### T3: Vision Registry schema definition
- **File**: `grimoires/loa/visions/index.md` (new)
- Schema version comment: `<!-- schema_version: 1 -->`
- Table header: `| ID | Title | Source | Status | Tags | Refs |`
- `vision_validate_entry()` checks required fields: ID, Source, Status, Tags, Insight section
- Malformed entries logged and skipped, not fatal

### T4: Create `vision-registry-query.sh`
- **File**: `.claude/scripts/vision-registry-query.sh` (new, 280 lines)
- Arguments: `--tags`, `--status`, `--min-overlap`, `--max-results`, `--visions-dir`, `--json`, `--include-text`, `--shadow`
- **Tag derivation (IMP-002)**: When `--tags auto`, derives from sprint plan file paths + PRD keywords
- Scoring: `(tag_overlap * 3) + (refs * 2) + recency_bonus`
- Recency bonus: 1 if Date within 30 days, else 0 (IMP-004)
- **Shell safety (SKP-005)**: All `--tags` validated, `--visions-dir` validated under project root, `--status` checked against enum

### T5: Configuration & feature flags
- **File**: `.loa.config.yaml` — Added `vision_registry:` section with `enabled: false` default
- **File**: `.loa.config.yaml.example` — Added comprehensive `vision_registry:` section with all config keys documented
- All settings readable via `yq eval '.vision_registry.X // default'`

### T6: Shadow mode logging pipeline
- **File**: `.claude/scripts/vision-registry-query.sh` — `--shadow` mode integrated
- Shadow log output to `grimoires/loa/a2a/trajectory/vision-shadow-{date}.jsonl`
- Log format: timestamp, cycle, work_tags, matches array, shadow_cycle_number
- **File**: `grimoires/loa/visions/.shadow-state.json` (new, atomic writes via flock)
- Tracks `shadow_cycles_completed`, `last_shadow_run`, `matches_during_shadow`
- Graduation check: outputs `graduation.ready: true` when threshold met AND matches > 0

### T7: Vision reference tracking with flock
- **File**: `.claude/scripts/vision-lib.sh` — `vision_record_ref()` and `vision_update_status()` wrap in `vision_atomic_write()` which uses `flock -w 5`
- Lock file: `{index_file}.lock`
- 5-second timeout on lock acquisition
- `_vision_require_flock()` checks for flock availability with macOS Homebrew keg-only path detection

### T8: Unit tests
- **File**: `tests/unit/vision-lib.bats` (new) — 30 tests
  - `vision_load_index`: empty, valid, malformed
  - `vision_match_tags`: overlap, zero, boundary, empty
  - `vision_sanitize_text`: clean, injection, truncation, HTML entities, missing file
  - `vision_validate_entry`: valid, malformed, missing
  - `vision_extract_tags`: mapping, dedup, unrecognized
  - `_vision_validate_id`: valid/invalid formats
  - `_vision_validate_tag`: valid/invalid formats
  - `vision_update_status`: success, invalid status, invalid ID
  - `vision_record_ref`: increment, nonexistent
- **File**: `tests/unit/vision-registry-query.bats` (new) — 19 tests
  - Empty registry, matches, max-results, min-overlap, status filter
  - Scoring algorithm verification
  - Include-text mode
  - Shadow mode logging, counter increment, graduation detection
  - Input validation (invalid tags, status, unknown options)
- **Directory**: `tests/fixtures/vision-registry/` (new) — 6 fixtures
  - `index-empty.md`, `index-three-visions.md`, `index-malformed.md`
  - `entry-valid.md`, `entry-malformed.md`, `entry-injection.md`

## Test Results

```
49 tests, 49 passed, 0 failures
```

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `.claude/scripts/vision-lib.sh` | Created | ~380 |
| `.claude/scripts/vision-registry-query.sh` | Created | ~280 |
| `.claude/scripts/bridge-vision-capture.sh` | Modified | Refactored to source library |
| `grimoires/loa/visions/index.md` | Created | Schema template |
| `grimoires/loa/visions/.shadow-state.json` | Created | Initial state |
| `.loa.config.yaml` | Modified | Added vision_registry section |
| `.loa.config.yaml.example` | Modified | Added vision_registry section |
| `tests/unit/vision-lib.bats` | Created | 30 tests |
| `tests/unit/vision-registry-query.bats` | Created | 19 tests |
| `tests/fixtures/vision-registry/*.md` | Created | 6 fixtures |

## Acceptance Criteria Met

- [x] All functions callable from both write (capture) and read (query) paths
- [x] Unit tests pass (49/49)
- [x] No unquoted variables (shellcheck patterns followed)
- [x] Config reads return correct defaults when section is absent
- [x] Shadow logs written correctly, counter increments, graduation detected
- [x] Concurrent ref updates protected by flock
- [x] Capture script refactored with unchanged external behavior
- [x] All input validation (vision IDs, tags, paths, status values)
