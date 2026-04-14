# Sprint Plan: Cycle-069 — Vision Registry Graduation

**Cycle**: 069
**Issue**: #486
**PRD**: `grimoires/loa/prd.md`
**SDD**: `grimoires/loa/sdd.md`
**Date**: 2026-04-14

---

## Sprint 1: Foundation — Octal Fix, State Extensions, Query CLI

**Goal**: Fix the blocking octal bug, extend vision-lib.sh for new states, and build the query CLI with index rebuild.

### Task 1.1: Octal Bug Fix (FR-4)

**File**: `.claude/scripts/bridge-vision-capture.sh:227`
**Change**: `next_number=$((local_max + 1))` → `next_number=$((10#$local_max + 1))`
**Test**: `tests/unit/vision-octal.bats` — verify IDs 008, 009, 010+ created without error
**AC**:
- [ ] `local_max` of `008` produces `next_number=9`
- [ ] `local_max` of `009` produces `next_number=10`
- [ ] `local_max` of `099` produces `next_number=100`
- [ ] Existing vision capture flow unchanged for non-edge-case IDs

### Task 1.2: Extend vision-lib.sh States (SDD 3.3)

**File**: `.claude/scripts/vision-lib.sh`
**Changes**:
- `vision_update_status()` line 447: add `Archived|Rejected` to case statement
- `vision_validate_entry()` line 414: add `Archived|Rejected` to case statement
- `vision_load_index()` line 210: add `Archived|Rejected` to case statement
- `vision_regenerate_index_stats()`: add Archived and Rejected counts
**AC**:
- [ ] `vision_update_status` accepts Archived and Rejected
- [ ] `vision_validate_entry` validates Archived and Rejected as legal
- [ ] `vision_regenerate_index_stats` counts all 7 statuses
- [ ] No regression in existing vision tests

### Task 1.3: Vision Query CLI (FR-1, SDD 3.1)

**File**: `.claude/scripts/vision-query.sh` (new)
**Functions**: `_parse_entry()`, `_match_filters()`, `_rebuild_index()`
**Features**:
- Parse frontmatter from entry files (not index) via awk + jq --arg
- Filter by: `--tags`, `--status` (comma-list), `--source` (grep -Fi --), `--since`/`--before` (UTC ISO-8601), `--min-refs`
- Output: `--format json|table|ids`, `--count`, `--limit`
- Exit codes: 0 success, 1 no results, 2 bad args, 3 parse error, 4 I/O error
- Non-strict quarantine for malformed entries (parse_error: true)
**Test**: `tests/unit/vision-query.bats`
**AC**:
- [ ] `--tags security` returns only security-tagged visions
- [ ] `--status Captured,Exploring` returns both statuses
- [ ] `--since 2026-04-01` filters by date correctly
- [ ] `--format json` output validates with `jq .`
- [ ] `--format table` produces pipe-delimited rows
- [ ] `--source` uses fixed-string matching (no regex injection)
- [ ] Malformed entry quarantined in non-strict mode
- [ ] Exit code 1 for zero results, 2 for bad args

### Task 1.4: Index Rebuild (FR-5, SDD 3.1)

**File**: `.claude/scripts/vision-query.sh` (--rebuild-index flag)
**Features**:
- Scan all entry files, parse, generate pipe-delimited table
- Regenerate statistics section with all 7 statuses
- Atomic write via `vision_atomic_write()`
- `--dry-run` flag: diff current vs rebuilt, report discrepancies
- Scan-time consistency: mtime check pre/post parse
**AC**:
- [ ] `--rebuild-index` regenerates index.md matching actual entry files
- [ ] Statistics section counts all statuses correctly
- [ ] `--rebuild-index --dry-run` shows diff without writing
- [ ] Idempotent: running twice produces identical output
- [ ] Quarantined entries skipped with warning
- [ ] Atomic write failure (disk full, permission denied) exits with code 4 and leaves original index intact (Flatline IMP-002)

---

## Sprint 2: Lifecycle CLI + Spiral Integration

**Goal**: Build lifecycle management and wire seed_phase() full mode.

### Task 2.1: Vision Lifecycle CLI (FR-2, SDD 3.2)

**File**: `.claude/scripts/vision-lifecycle.sh` (new)
**Commands**: `promote`, `archive`, `reject`, `explore`, `propose`, `defer`
**Features**:
- Global lifecycle lock (`grimoires/loa/visions/.lifecycle.lock`) wraps entire command via `flock -w 10` (10s timeout). Stale lock recovery: flock is kernel-level — lock auto-releases on process death (Flatline IMP-001). No PID file needed since flock handles crash recovery natively.
- Promote: ordered writes (lore append → status update → index rebuild → trajectory)
- Archive/Reject: add reason to frontmatter, update status
- Reject requires `--reason`
- Input sanitization: `_sanitize_reason()` strips `|`, newlines, control chars
- Terminal state blocking (Implemented, Archived, Rejected) → exit code 5
- Exit codes: 0-5 per SDD spec
**Test**: `tests/unit/vision-lifecycle.bats`
**AC**:
- [ ] `promote vision-003` creates lore entry + updates status to Implemented + rebuilds index
- [ ] Lore path delegated to `vision_append_lore_entry()` (not hardcoded)
- [ ] `promote` on terminal state exits with code 5
- [ ] `reject` without `--reason` exits with code 2
- [ ] `archive --reason "stale"` adds Archived-Reason to frontmatter
- [ ] Reason text with `|` and newlines is sanitized
- [ ] Double-promote is idempotent
- [ ] Partial promote failure (crash after lore append, before status update) recoverable by re-running (Flatline IMP-003, SDD 5.1)
- [ ] `defer` transitions Proposed → Deferred
- [ ] Global lifecycle lock prevents concurrent operations

### Task 2.2: seed_phase() Full Mode (FR-3, SDD 3.5)

**File**: `.claude/scripts/spiral-orchestrator.sh` (modify seed_phase())
**Changes**: Replace demotion fallback at line ~515 with registry query logic
**Features**:
- Tag derivation from HARVEST sidecar with deterministic mapping (SDD 7.2)
- Sidecar validation: `jq -e '.findings | type == "array"'`
- Fallback to `spiral.seed.default_tags` config
- Query: `vision-query.sh --tags <tags> --status Captured,Exploring,Proposed --format json --limit <max>`
- Zero results → cold start (not degraded)
- Relevance scoring via jq float arithmetic (zero-tag safe)
- Budget enforcement: 4KB, drop lowest-ranked visions
- Structured seed context JSON per SDD 2.3 schema
- Trajectory: `seed_full` event with query params and stats
**Test**: `tests/unit/vision-seed-full.bats`
**AC**:
- [ ] With HARVEST sidecar: tags derived from findings categories
- [ ] Without sidecar: falls back to default_tags
- [ ] Invalid sidecar (missing findings): falls back with warning
- [ ] `vision_registry.enabled` checked before querying — falls back to degraded if disabled (Flatline SKP-010)
- [ ] Zero query results: cold-start, logs `seed_cold`
- [ ] Budget exceeded: lowest-ranked visions dropped, `truncated: true`
- [ ] Relevance scoring: jq float math, zero-tag-safe
- [ ] Seed context JSON validates against schema
- [ ] Trajectory event logged with query parameters

### Task 2.3: Config Updates (FR-6, SDD 7.1)

**File**: `.loa.config.yaml`
**Changes**:
- `vision_registry.enabled: true` (was false)
- `spiral.seed.mode: "full"` (was "degraded")
- Add `spiral.seed.default_tags` and `spiral.seed.max_seed_visions`
**AC**:
- [ ] Config keys present and correctly typed
- [ ] `read_config` resolves new keys with defaults

### Task 2.4: Run Existing Tests

**AC**:
- [ ] All existing vision tests pass
- [ ] All existing spiral tests pass
- [ ] No regressions

---

## Dependencies

```
T1.1 (octal fix)     ─┐
T1.2 (state extend)   ├─→ T1.3 (query CLI) ─→ T1.4 (rebuild)
                       │                           │
                       └───────────────────────────┘
                                                    │
                            T2.1 (lifecycle) ←──────┘
                            T2.2 (seed full) ←── T1.3
                            T2.3 (config)
                            T2.4 (regression)
```

## Verification Criteria

- All new tests pass (4 test files)
- All existing tests pass (no regression)
- `vision-query.sh --rebuild-index` fixes the current index drift
- `vision-lifecycle.sh promote` creates a real lore entry
- `seed_phase()` full mode queries registry and produces structured context
- Octal bug verified fixed for IDs 008, 009
