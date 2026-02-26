# Engineer Feedback — Sprint 1 (Global Sprint-74): Vision-Aware Planning

**Reviewer**: Senior Technical Lead
**Date**: 2026-02-26
**Verdict**: Conditional Pass — 2 gaps to address, 3 advisory notes

---

## Summary

Overall strong implementation. All 8 tasks are structurally complete, the code is clean and well-organized, and 49/49 tests pass. The extraction from `bridge-vision-capture.sh` into `vision-lib.sh` is well done with no duplication. Configuration, schema template, and shadow mode pipeline are all present. Two acceptance criteria gaps need to be addressed before merge, plus three advisory code quality notes.

---

## Task-by-Task Verification

### T1: `vision-lib.sh` shared library — PASS
- **File**: `.claude/scripts/vision-lib.sh` (570 lines)
- All 9 functions present: `vision_load_index`, `vision_match_tags`, `vision_extract_tags`, `vision_sanitize_text`, `vision_validate_entry`, `vision_update_status`, `vision_record_ref`, `vision_check_lore_elevation`, `vision_atomic_write`
- Sources `bootstrap.sh` and `compat-lib.sh` (lines 36-43)
- jq dependency check at source time (line 46)
- Double-source guard with `_VISION_LIB_LOADED` (line 22)
- SKP-005 validation: ID regex `^vision-[0-9]{3}$` (line 93), tag regex `^[a-z][a-z0-9_-]*$` (line 103), directory traversal check (line 111)
- Variables are properly quoted throughout

### T2: Refactor `bridge-vision-capture.sh` — PASS
- **File**: `.claude/scripts/bridge-vision-capture.sh` (299 lines)
- Sources `vision-lib.sh` at line 31 with error exit if missing (lines 27-30)
- Old inline functions removed — no `update_vision_status()`, `record_reference()`, `extract_pr_tags()`, or `check_relevant_visions()` definitions found
- Entry points preserved: `--check-relevant` (line 38), `--record-reference` (line 107), `--update-status` (line 121), main capture mode (line 134+)
- Delegates to library: `vision_extract_tags` (line 99), `vision_record_ref` (line 116), `vision_update_status` (line 130)

### T3: Vision Registry schema — PASS
- **File**: `grimoires/loa/visions/index.md` (16 lines)
- Schema version comment present: `<!-- schema_version: 1 -->` (line 1)
- Table header matches spec: `| ID | Title | Source | Status | Tags | Refs |` (line 6)
- `vision_validate_entry()` checks all 5 required fields: ID, Source, Status, Tags, Insight section (lines 392-396)
- Invalid entries logged and skipped per malformed fixture test (lines 85-96 of vision-lib.bats)

### T4: `vision-registry-query.sh` — PASS with gap (see Issue 1)
- **File**: `.claude/scripts/vision-registry-query.sh` (382 lines)
- Sources `vision-lib.sh` with error exit (lines 32-36)
- All arguments supported: `--tags`, `--status`, `--min-overlap`, `--max-results`, `--visions-dir`, `--json`, `--include-text`, `--shadow`, `--shadow-cycle`, `--shadow-phase`
- Tag auto-derivation (lines 151-187): sprint file paths + PRD keywords, deduplication
- Scoring formula correct: `(overlap * 3) + (refs * 2) + recency_bonus` (line 263)
- Recency bonus: 1 if within 30 days (lines 248-259)
- Sort: score descending, tie-break by ID (line 288)
- Empty registry returns `[]` (lines 196-203)
- jq + yq dependency check (lines 39-45)
- SKP-005: tags validated against `^[a-z][a-z0-9_,-]*$` (line 125), status enum check (lines 138-145), directory validation (lines 133-135)

### T5: Configuration & feature flags — PASS
- **File**: `.loa.config.yaml.example` — vision_registry section with all config keys and defaults (lines 1512-1539): `enabled`, `shadow_mode`, `shadow_cycles_before_prompt`, `status_filter`, `min_tag_overlap`, `max_visions_per_session`, `ref_elevation_threshold`, `propose_requirements`
- **File**: `.loa.config.yaml` — vision_registry section with `enabled: false` (lines 84-94)
- Config readable via `yq eval '.vision_registry.shadow_cycles_before_prompt // 2'` — confirmed at line 352 of query script

### T6: Shadow mode logging pipeline — PASS
- Shadow log: `grimoires/loa/a2a/trajectory/vision-shadow-{date}.jsonl` (line 306)
- Log format includes: timestamp, cycle, phase, work_tags, matches, shadow_cycle_number (lines 323-331)
- Shadow state file: `grimoires/loa/visions/.shadow-state.json` with atomic writes (lines 336-349)
- Tracks `shadow_cycles_completed`, `last_shadow_run`, `matches_during_shadow` (lines 337-341)
- Graduation check with configurable threshold (lines 352-363)

### T7: Flock-guarded atomic writes — PASS with gap (see Issue 2)
- `vision_atomic_write()` at lines 143-158 wraps callback in flock subshell
- Lock file: `{target_file}.lock` (line 149)
- 5-second timeout: `flock -w 5 200` (line 152)
- Used by `vision_update_status` (line 472) and `vision_record_ref` (line 535)
- `_vision_require_flock()` handles macOS Homebrew keg-only paths (lines 57-84)

### T8: Unit tests — PASS
- **File**: `tests/unit/vision-lib.bats` — 30 tests, all passing
  - `vision_load_index`: empty, missing, valid (3 visions), malformed (skips)
  - `vision_match_tags`: overlap, full, zero, single, empty
  - `vision_sanitize_text`: insight extraction, injection strip, HTML entities, truncation, missing file
  - `vision_validate_entry`: valid, malformed, missing
  - `vision_extract_tags`: path mapping, dedup, unrecognized
  - SKP-005: valid/invalid IDs, valid/invalid tags
  - `vision_update_status`: success, invalid status, invalid ID
  - `vision_record_ref`: increment, nonexistent vision
- **File**: `tests/unit/vision-registry-query.bats` — 19 tests, all passing
  - Script existence, help, arg validation
  - Empty registry, missing registry
  - Matching, min-overlap, max-results, status filter
  - Scoring algorithm, matched_tags output
  - include-text, omit insight field
  - Shadow mode: JSONL write, counter increment, graduation detection
  - SKP-005: invalid status, unknown options
- **File**: `tests/fixtures/vision-registry/` — all 6 fixtures present:
  - `index-empty.md`, `index-three-visions.md`, `index-malformed.md`
  - `entry-valid.md`, `entry-malformed.md`, `entry-injection.md`

---

## Issues to Address

### Issue 1 (GAP): Missing `--tags auto` test
**Severity**: Medium
**Location**: `tests/unit/vision-registry-query.bats`
**Sprint plan T4 acceptance**: "Auto-tag derivation tested with example paths."

There is no test for the `--tags auto` derivation path. The auto-derivation logic reads `grimoires/loa/sprint.md` and `grimoires/loa/prd.md`, extracts file paths, and maps them to tags via `vision_extract_tags`. This code path (lines 151-187 of `vision-registry-query.sh`) is completely untested.

**Fix**: Add a test that creates a minimal `sprint.md` with `**File**: \`flatline-orchestrator.sh\`` entries and a `prd.md` with architecture keywords in the test tmpdir, then runs with `--tags auto` and verifies the derived tags produce expected matches.

### Issue 2 (GAP): Missing concurrent/parallel writer test for flock
**Severity**: Medium
**Location**: `tests/unit/vision-lib.bats`
**Sprint plan T7 acceptance**: "Concurrent ref updates don't corrupt counters (tested with parallel writers)"

There is no test verifying that concurrent flock-guarded writes produce correct results. The flock implementation looks correct, but the acceptance criterion explicitly requires a parallel writer test.

**Fix**: Add a test that spawns N background `vision_record_ref` calls against the same vision, waits for all to complete, then verifies the final ref count equals initial + N. Example:
```bash
@test "vision_record_ref: concurrent writers don't corrupt" {
    load_vision_lib
    cp "$FIXTURES/index-three-visions.md" "$TEST_TMPDIR/index.md"
    # vision-001 starts at refs=4, run 5 parallel increments
    for i in $(seq 1 5); do
        vision_record_ref "vision-001" "bridge-concurrent-$i" "$TEST_TMPDIR" &
    done
    wait
    refs=$(grep "^| vision-001 " "$TEST_TMPDIR/index.md" | awk -F'|' '{print $7}' | xargs)
    [ "$refs" -eq 9 ]
}
```

---

## Advisory Notes (non-blocking)

### Advisory 1: `return` in subshell pattern
**Location**: `.claude/scripts/vision-lib.sh` lines 154, 462, 503
**Context**: Per the project's own memory from PR #215: "`return` in bash subshells silently becomes `exit` -- use `exit` explicitly per Google bash style guide." The `_do_update_status` (line 462) and `_do_record_ref` (line 503) functions use `return 1` but are executed inside the `vision_atomic_write` flock subshell. The behavior is correct (subshell exits with code 1) but contradicts the established project convention. Consider changing to `exit 1` for consistency, or documenting that these are functions called inside subshells.

### Advisory 2: Path traversal prefix matching edge case
**Location**: `.claude/scripts/vision-lib.sh` line 126
**Context**: The path validation `"$canon_dir" != "$canon_root"*` uses prefix matching. If `PROJECT_ROOT=/home/user/project`, then `/home/user/project-evil/` would pass. More precise: `"$canon_dir" != "$canon_root"/* && "$canon_dir" != "$canon_root"`. Low risk in practice because the default visions dir is `grimoires/loa/visions` which is deep inside the project, and the directory must exist. But worth hardening for defense-in-depth.

### Advisory 3: Shadow log JSONL append is not flock-guarded
**Location**: `.claude/scripts/vision-registry-query.sh` line 333
**Context**: `echo "$shadow_entry" >> "$shadow_log"` appends to the JSONL log without flock protection. The shadow state file IS flock-guarded (line 346), but the log file is not. For a single-line append, POSIX guarantees atomicity for writes under PIPE_BUF (4096 bytes), so this is likely safe for typical entries. But if entries exceed PIPE_BUF or the file is on NFS, corruption is possible. Consider wrapping the append in the same flock as the state update.

---

## Strengths

- Clean extraction architecture: `vision-lib.sh` is the single source of truth, both `bridge-vision-capture.sh` and `vision-registry-query.sh` delegate cleanly
- Comprehensive input validation (SKP-005): ID regex, tag regex, status enum, directory traversal check
- Injection defense in depth: `vision_sanitize_text` uses allowlist extraction (Insight section only), HTML entity decoding, pattern stripping, indirect instruction filtering, and truncation
- Good test fixture design: malformed index, injection entry, and valid entry cover the key scenarios
- Shadow mode graduation is well-designed: configurable threshold, atomic state persistence, JSON flag output for callers
- 49 tests all green with no flaky behavior
