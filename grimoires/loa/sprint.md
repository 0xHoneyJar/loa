# Sprint Plan: Organizational Memory Sovereignty (cycle-038)

## Overview

**PRD:** grimoires/loa/prd.md v1.1
**SDD:** grimoires/loa/sdd.md v1.1
**Sprints:** 6 (dependency-ordered)
**Scope:** FR-1 through FR-5 + learning exchange schema

---

## Sprint 1: State-Dir Resolution Foundation (global sprint-57)

**Goal**: Extend `path-lib.sh` with state-dir resolution, create state directory structure, add conformance test. This is the foundation for all other sprints.

### Task 1: Add state-dir resolution to path-lib.sh (FR-1 — High) ✅
**File**: `.claude/scripts/path-lib.sh`
**Change**: Add `_DEFAULT_STATE_DIR`, `LOA_STATE_DIR` resolution in `_read_config_paths()`, new getters: `get_state_dir()`, `get_state_beads_dir()`, `get_state_ck_dir()`, `get_state_run_dir()`, `get_state_memory_dir()`, `get_state_trajectory_dir()`
**AC**:
- [x] Resolution priority: `$LOA_STATE_DIR` env > `paths.state_dir` config > `.loa-state` default
- [x] Absolute paths: rejected by default with error; allowed when `LOA_ALLOW_ABSOLUTE_STATE=1` is set (for containers/CI with mounted volumes)
- [x] When `LOA_ALLOW_ABSOLUTE_STATE=1`, validate path exists and is writable; log warning acknowledging absolute path usage
- [x] `detect_state_layout()` returns layout version from `.loa-version.json`
- [ ] Backward compat: when layout v1, getters fall back to legacy paths *(deferred — Sprint 2 migration)*

### Task 2: Create and initialize .loa-version.json schema (FR-1 — High) ✅
**File**: `.claude/scripts/path-lib.sh` + `.claude/schemas/loa-version.schema.json`
**Change**: Define `.loa-version.json` schema with `state_layout_version` field. Add `init_version_file()` to path-lib.sh that creates the file with version 1 for fresh installs and version 2 for new state-dir installs. `ensure_state_structure()` calls this.
**AC**:
- [x] Schema: `{ "state_layout_version": 1|2, "created": "ISO8601", "last_migration": "ISO8601|null" }`
- [x] Fresh install (no legacy dirs): creates with `state_layout_version: 2`
- [x] Legacy detected (old dirs exist, no version file): creates with `state_layout_version: 1`
- [x] `detect_state_layout()` reads this file; returns 0 if missing/malformed (treat as unknown)
- [x] File created atomically (write to temp, rename)

### Task 3: Add ensure_state_structure() to path-lib.sh (FR-1 — Medium) ✅
**File**: `.claude/scripts/path-lib.sh`
**Change**: Add `ensure_state_structure()` function that creates full `.loa-state/` hierarchy and initializes version file
**AC**:
- [x] Creates: `beads/`, `ck/`, `run/bridge-reviews`, `run/mesh-cache`, `memory/archive`, `memory/sessions`, `trajectory/current`, `trajectory/archive`
- [x] Calls `init_version_file()` to ensure `.loa-version.json` exists
- [x] Idempotent: safe to call multiple times

### Task 4: Add `append_jsonl()` locking utility (SDD 3.2.1 — Medium) ✅
**File**: `.claude/scripts/path-lib.sh`
**Change**: Add `append_jsonl()` function implementing flock-based advisory locking for concurrent JSONL writers per SDD Section 3.2.1
**AC**:
- [x] `append_jsonl FILE LINE` — acquires flock on `FILE.lock`, appends LINE with newline, releases lock
- [x] Uses `flock -w 5` with 5-second timeout; returns error on timeout
- [x] O_APPEND mode for atomic kernel-level appends
- [x] Lock file created alongside data file (e.g., `observations.jsonl.lock`)
- [x] Usable by memory-writer.sh, trajectory writer, and any concurrent JSONL producer

### Task 5: Conformance test (FR-1 — Medium) ✅
**File**: `tests/unit/test-state-path-conformance.sh`
**Change**: Create test that verifies no script uses hardcoded `.beads/`, `.run/`, `.ck/` outside resolution layer
**AC**:
- [x] Allowlist: `path-lib.sh`, `migrate-state-layout.sh`, `bootstrap.sh`, test files, docs
- [x] Scans `.claude/scripts/*.sh` AND `.claude/hooks/*.sh` (expanded scope per SKP-004)
- [x] Ignores comments (lines starting with `#`) to reduce false positives
- [x] Positive check: scripts that source path-lib.sh must use `get_state_*` functions (not raw paths)
- [x] Exit 0 on pass, exit 1 with file:line on failure

### Task 6: Add state_dir to config example (FR-1 — Low) ✅
**File**: `.loa.config.yaml.example`
**Change**: Add `state_dir: .loa-state` under `paths:` section. Add `trajectory.archive`, `memory.bootstrap`, `migration`, and `redaction` config blocks.
**AC**:
- [x] All new config keys documented with comments
- [x] Default values match SDD v1.1 specification
- [x] `LOA_ALLOW_ABSOLUTE_STATE` documented with use case (containers/CI)

### Task 7: Unit tests for path-lib.sh extensions (FR-1 — Medium) ✅
**File**: `tests/unit/test-path-lib-state.sh`
**Change**: Test state-dir resolution with env var, config, and default scenarios
**AC**:
- [x] Test: env var takes precedence over config
- [x] Test: config takes precedence over default
- [x] Test: absolute path rejected by default (exit code + error message)
- [x] Test: absolute path accepted when `LOA_ALLOW_ABSOLUTE_STATE=1`
- [x] Test: `ensure_state_structure()` creates all expected dirs
- [x] Test: `detect_state_layout()` returns correct version (v1 legacy, v2 new, 0 missing)
- [x] Test: `.loa-version.json` created correctly for fresh vs legacy scenarios
- [x] Test: `append_jsonl()` writes atomically with lock
- [x] Test: `append_jsonl()` handles concurrent callers (background processes)

---

## Sprint 2: Migration Script + Mount Integration (global sprint-58)

**Goal**: Create the state layout migration script and integrate with mount-submodule.sh. Users can consolidate scattered state after this sprint.

### Task 1: Create migrate-state-layout.sh (FR-5 — High)
**File**: `.claude/scripts/migrate-state-layout.sh`
**Change**: New script implementing copy-verify-switch migration with platform-aware compat modes, journal-based crash recovery, and robust locking
**AC**:
- [ ] `--dry-run` (default): shows what would move with file counts and sizes
- [ ] `--apply`: executes migration with verification
- [ ] `--compat-mode auto|resolution|symlink|copy`: platform-aware selection
- [ ] Robust locking: use `flock` where available, fall back to `mkdir`-based lock; lock file at repo root `.loa-migration.lock` (NOT inside migration target)
- [ ] Lock includes PID, hostname, timestamp; stale lock detection (process not running → safe to override with warning)
- [ ] Journal-based crash recovery: write journal marker (`.loa-state/.migration-journal`) before each source move; on restart, resume from journal position (per SDD 3.7)
- [ ] Verification: sha256 checksums of copied files (not just file counts); byte-size comparison as fast pre-check
- [ ] Atomic cutover: stage to `.loa-state/.migration-staging/` temp dir, then rename into place
- [ ] Rollback: on verification failure, remove staged copies; original sources untouched until verified
- [ ] Trap on EXIT: release lock + cleanup partial staging dir
- [ ] Platform detection: tests symlink support in temp dir
- [ ] Sources: `.beads/` → `beads/`, `.ck/` → `ck/`, `.run/` → `run/`, `grimoires/loa/memory/` → `memory/`
- [ ] Updates `.loa-version.json` with `state_layout_version: 2` on success
- [ ] SQLite files (beads): verify integrity with `sqlite3 DB "PRAGMA integrity_check"` after copy

### Task 2: Update mount-submodule.sh for state structure (FR-1 — Medium)
**File**: `.claude/scripts/mount-submodule.sh`
**Change**: After grimoire structure creation, call `ensure_state_structure()`. Check layout version and prompt for migration if old layout detected.
**AC**:
- [ ] Calls `ensure_state_structure()` after grimoire setup
- [ ] Detects layout v1 with old dirs present → prints migration suggestion
- [ ] Does NOT auto-migrate (prompt only)

### Task 3: Update .gitignore management (FR-1 — Low)
**File**: `.claude/scripts/mount-loa.sh` (stealth mode section)
**Change**: Replace 5 separate gitignore entries with single `.loa-state/` entry
**AC**:
- [ ] Stealth mode adds `.loa-state/` to gitignore
- [ ] During migration grace period, old entries kept alongside
- [ ] After successful migration (layout v2), old entries can be cleaned

### Task 4: Migration tests (FR-5 — Medium)
**File**: `tests/unit/test-migrate-state-layout.sh`
**Change**: Test migration scenarios: dry-run, apply, rollback on failure, platform detection, crash recovery
**AC**:
- [ ] Test: dry-run shows correct plan without moving files
- [ ] Test: apply moves files and verifies checksums (not just counts)
- [ ] Test: simulated failure triggers rollback (staged copies removed, originals intact)
- [ ] Test: flock/mkdir lock prevents concurrent migration
- [ ] Test: stale lock (dead PID) detected and overridden with warning
- [ ] Test: journal-based resume after interrupted migration
- [ ] Test: compat mode auto-detection works
- [ ] Test: SQLite integrity verified after copy
- [ ] Test: symlinks and file permissions preserved during migration

---

## Sprint 3: Redaction Pipeline (global sprint-59)

**Goal**: Create the shared fail-closed redaction pipeline used by trajectory export, memory bootstrap, and learning proposals.

### Task 1: Create redact-export.sh (FR-3/FR-4 — High)
**File**: `.claude/scripts/redact-export.sh`
**Change**: New script implementing three-tier detection (BLOCK/REDACT/FLAG), allowlist sentinel protection with strict parsing, entropy analysis with defined algorithm, and fail-closed semantics
**AC**:
- [ ] Reads stdin, writes stdout (pipe-friendly)
- [ ] Exit 0: clean content; Exit 1: blocked (BLOCK finding); Exit 2: error
- [ ] `--strict` flag (default true): fail-closed
- [ ] `--audit-file PATH`: writes JSON audit report
- [ ] `--allow-pattern REGEX`: operator override for false positives (logged to audit)
- [ ] `REDACT_ALLOWLIST_FILE` config: file of patterns to skip (one regex per line)
- [ ] Input validation: reject binary content (NUL bytes), enforce 50MB max, UTF-8 only
- [ ] BLOCK rules: AWS keys (`AKIA`), GitHub PATs (`ghp_/gho_/ghs_/ghr_`), JWTs (`eyJ`), Bearer tokens, private keys, `sk-` keys, Slack webhooks, Stripe keys (`sk_live_/pk_live_`), Twilio SIDs, SendGrid keys
- [ ] REDACT rules: absolute paths (Unix/Windows/tilde), emails, `.env` assignments, IPv4 addresses
- [ ] FLAG rules: token/password params, high-entropy strings
- [ ] Entropy detection: Shannon entropy, min 20 chars, threshold ≥4.5 bits/char, skip known safe patterns (sha256 hashes, UUIDs)
- [ ] Allowlist sentinel protection: strict format `<!-- redact-allow:CATEGORY -->...<!-- /redact-allow -->`, BLOCK rules ALWAYS override sentinels (sentinels only protect REDACT/FLAG), no nesting allowed, malformed sentinels treated as plain text
- [ ] Post-redaction safety check: scan output for missed `ghp_`, `gho_`, `AKIA`, `eyJ`, `sk_live_` prefixes; block on any match

### Task 2: Create redaction test fixtures (FR-3 — Medium)
**Files**: `tests/fixtures/redaction/` (10 files)
**Change**: Create test fixtures for each detection category including bypass attempts
**AC**:
- [ ] `aws-key.txt`: BLOCK expected
- [ ] `github-pat.txt`: BLOCK expected
- [ ] `jwt.txt`: BLOCK expected
- [ ] `slack-webhook.txt`: BLOCK expected (new pattern)
- [ ] `abs-path.txt`: REDACT expected
- [ ] `email.txt`: REDACT expected
- [ ] `clean.txt`: PASS expected
- [ ] `allowlisted.txt`: PASS (sentinel protected REDACT content)
- [ ] `sentinel-bypass-attempt.txt`: BLOCK expected (sentinel wrapping a secret — sentinels don't override BLOCK)
- [ ] `high-entropy.txt`: FLAG expected (random base64 string ≥20 chars)

### Task 3: Redaction pipeline tests (FR-3 — Medium)
**File**: `tests/unit/test-redact-export.sh`
**Change**: Test each detection rule against fixtures, test fail-closed behavior, test allowlist, test operator override, test sentinel security
**AC**:
- [ ] Each fixture produces expected exit code
- [ ] BLOCK findings halt output (no stdout on exit 1)
- [ ] REDACT findings replace with `<redacted-*>` placeholders
- [ ] Allowlisted content preserved through redaction (REDACT/FLAG only)
- [ ] Sentinel-wrapped BLOCK content is STILL blocked (sentinels don't override BLOCK)
- [ ] Nested sentinels treated as plain text (not honored)
- [ ] Malformed sentinels treated as plain text (not honored)
- [ ] `--allow-pattern` overrides specific patterns with audit log entry
- [ ] Audit file written with correct finding counts
- [ ] Post-redaction check catches any missed patterns
- [ ] Binary input rejected (exit 2)
- [ ] Input >50MB rejected (exit 2)
- [ ] Entropy detection: triggers on random base64 ≥20 chars, ignores sha256 hashes and UUIDs
- [ ] Operator override logged to audit file

---

## Sprint 4: Trajectory Archive + Import (global sprint-60)

**Goal**: Create trajectory export/import scripts and integrate with /archive-cycle.

### Task 1: Create trajectory-export.sh (FR-3 — High)
**File**: `.claude/scripts/trajectory-export.sh`
**Change**: New script that exports trajectory JSONL to portable format with redaction, supporting streaming for large files
**AC**:
- [ ] `--cycle CYCLE_ID` required parameter
- [ ] Collects all JSONL from `trajectory/current/` using `get_state_trajectory_dir()`
- [ ] Runs content through `redact-export.sh` (fail-closed)
- [ ] Streaming mode: for exports >10MB, process per-entry through redaction (not load all into memory)
- [ ] Builds export with schema_version, summary, entries, redaction_report
- [ ] Trajectory entry schema validation: `timestamp` (ISO8601), `phase` (enum), `content` (string), `session_id` (optional)
- [ ] Compression: gzip by default (configurable)
- [ ] Size check against `trajectory.archive.max_export_size_mb`
- [ ] `--git-commit` opt-in: stages file for git (warns about LFS for >5MB)
- [ ] Moves processed JSONL to `trajectory/current/exported-{cycle}/`
- [ ] Writes output to `trajectory/archive/{cycle_id}.json.gz`
- [ ] Uses `append_jsonl()` for any JSONL writes

### Task 2: Create trajectory-import.sh (FR-3 — Medium)
**File**: `.claude/scripts/trajectory-import.sh`
**Change**: New script that imports exported trajectory files
**AC**:
- [ ] Accepts `.json` or `.json.gz` files
- [ ] Validates `schema_version: 1`
- [ ] Extracts entries into `trajectory/current/imported-{cycle}-{date}.jsonl`
- [ ] Reports import count

### Task 3: Integrate with /archive-cycle (FR-3 — Medium)
**Change**: Update archive-cycle workflow to trigger trajectory export at cycle boundary
**AC**:
- [ ] After copying artifacts, calls `trajectory-export.sh --cycle $CYCLE_ID`
- [ ] Respects `trajectory.archive.git_commit` config
- [ ] Non-blocking: export failure logged but doesn't block archive

### Task 4: Update compact-trajectory.sh retention (FR-3 — Low)
**File**: `.claude/scripts/compact-trajectory.sh`
**Change**: Add archive retention enforcement — delete exports >365d from `trajectory/archive/`
**AC**:
- [ ] Scans `trajectory/archive/` for files older than retention_days
- [ ] Filesystem delete only (no git history rewriting)
- [ ] Respects existing retention_days config

---

## Sprint 5: Memory Pipeline Activation (global sprint-61) ✅

**Goal**: Activate the dormant memory pipeline with deterministic bootstrap and updated query paths.

### Task 1: Create memory-bootstrap.sh (FR-2 — High) ✅
**File**: `.claude/scripts/memory-bootstrap.sh`
**Change**: New script extracting observations from 4 deterministic sources
**AC**:
- [x] Source 1: trajectory `phase: "cite"` or `phase: "learning"` entries
- [x] Source 2: flatline HIGH_CONSENSUS findings from `*-review.json`
- [x] Source 3: sprint feedback (auditor + engineer) structured findings
- [x] Source 4: bridge findings (CRITICAL + HIGH severity)
- [x] Default: writes to `observations-staged.jsonl`
- [x] `--import`: runs redaction, merges staged into `observations.jsonl`
- [x] Quality gates: confidence ≥0.7, content hash dedup, min 10 chars, category validation
- [x] Sampling report: counts per source + 3 sample entries displayed
- [x] `--source SOURCE`: bootstrap from single source only
- [x] Uses `append_jsonl()` for all JSONL writes (concurrent-safe)

### Task 2: Update memory-writer.sh hook (FR-2 — Medium) ✅
**File**: `.claude/hooks/memory-writer.sh`
**Change**: Use `get_state_memory_dir()` from path-lib.sh instead of hardcoded path, use `append_jsonl()` for concurrent safety
**AC**:
- [x] Sources `path-lib.sh` for path resolution
- [x] Writes to `$(get_state_memory_dir)/observations.jsonl` via `append_jsonl()`
- [x] Falls back to legacy path if path-lib not available

### Task 3: Update memory-query.sh (FR-2 — Medium) ✅
**File**: `.claude/scripts/memory-query.sh`
**Change**: Use `get_state_memory_dir()` for observation file location
**AC**:
- [x] Sources `path-lib.sh` for path resolution
- [x] Reads from `$(get_state_memory_dir)/observations.jsonl`
- [x] Progressive disclosure unchanged: `--index` <50, `--summary` <200, `--full` <500

### Task 4: Memory bootstrap tests (FR-2 — Medium) ✅
**File**: `tests/unit/test-memory-bootstrap.sh`
**Change**: Test extraction from each source, quality gates, staging/import flow
**AC**:
- [x] Test: trajectory extraction picks only cite/learning phases
- [x] Test: flatline extraction picks only high_consensus items
- [x] Test: quality gate rejects low-confidence entries
- [x] Test: content hash dedup prevents duplicates
- [x] Test: --import runs redaction and appends to observations.jsonl
- [x] Test: blocked content prevents import (fail-closed)

---

## Sprint 6: Federated Learning Exchange (global sprint-62)

**Goal**: Define the learning exchange schema and update /propose-learning for upstream flow.

### Task 1: Create learning-exchange schema (FR-4 — High)
**File**: `.claude/schemas/learning-exchange.schema.json`
**Change**: JSON Schema for privacy-safe learning exchange format
**AC**:
- [x] Schema validates: learning_id pattern, category enum, confidence range, privacy fields
- [x] `privacy.contains_file_paths`, `privacy.contains_secrets`, `privacy.contains_pii` all `const: false`
- [x] `quality_gates`: depth, reusability, trigger_clarity, verification (1-10)
- [x] `redaction_report`: rules_applied, items_redacted, items_blocked

### Task 2: Update /propose-learning skill (FR-4 — High)
**Change**: Update the propose-learning skill to use learning-exchange schema and redaction pipeline
**AC**:
- [x] Generates `.loa-learning-proposal.yaml` in schema-compliant format
- [x] Runs content through `redact-export.sh` before output
- [x] Validates against `learning-exchange.schema.json`
- [x] Includes `redaction_report` field
- [x] Quality gates enforced: depth ≥7, reusability ≥7, trigger_clarity ≥6, verification ≥6

### Task 3: Downstream learning import in update-loa.sh (FR-4 — Medium)
**File**: `.claude/scripts/update-loa.sh`
**Change**: After submodule update, check for new upstream learnings and import to local memory
**AC**:
- [x] Checks `.claude/data/upstream-learnings/` for new `.yaml` files
- [x] Validates against learning-exchange schema
- [x] Imports valid learnings into local `observations.jsonl` via `append_jsonl()`
- [x] Logs import count to trajectory

### Task 4: Learning exchange integration tests (FR-4 — Medium)
**File**: `tests/unit/test-learning-exchange.sh`
**Change**: Test schema validation, redaction, quality gates
**AC**:
- [x] Test: valid learning passes schema validation
- [x] Test: learning with file paths blocked by redaction
- [x] Test: learning below quality gates rejected
- [x] Test: import from upstream learnings works

---

## Dependency Graph

```
Sprint 1 (Foundation)
  │
  ├──→ Sprint 2 (Migration)
  │
  │    Sprint 3 (Redaction) ← standalone
  │      │
  ├──→ Sprint 4 (Trajectory) ← depends on 1 + 3
  │      │
  ├──→ Sprint 5 (Memory) ← depends on 1 + 3
  │      │
  └──→ Sprint 6 (Learning Exchange) ← depends on 3 + 5
```

**Parallelization opportunity:** Sprints 2 and 3 can run in parallel after Sprint 1 completes. Sprints 4 and 5 can run in parallel after Sprint 3 completes.

---

## Flatline Sprint Integration Log

All 10 findings from Flatline Sprint review integrated:

| ID | Score | Finding | Integration |
|----|-------|---------|-------------|
| SKP-001 | 900 | Absolute path rejection breaks containers/CI | Sprint 1 Task 1: Added `LOA_ALLOW_ABSOLUTE_STATE` opt-in |
| SKP-002 | 880 | Migration verification insufficient (file count only) | Sprint 2 Task 1: sha256 checksums, SQLite integrity, atomic staging |
| SKP-003 | 760 | PID lock fragile, can deadlock | Sprint 2 Task 1: flock/mkdir-based locking, stale detection, lock outside target |
| SKP-004 | 720 | Conformance test scope too narrow | Sprint 1 Task 5: Expanded to hooks dir, positive check for getter usage, comment ignore |
| SKP-005 | 790 | Redaction false positive/negative risk | Sprint 3 Task 1: Operator override, allowlist file, defined threat model per SDD |
| SKP-006 | 840 | Allowlist sentinel bypass vector | Sprint 3 Task 1: BLOCK overrides sentinel, no nesting, strict format, bypass tests |
| IMP-001 | 855 | Migration needs journal/resume for interrupted runs | Sprint 2 Task 1: Journal-based crash recovery per SDD 3.7 |
| IMP-002 | 810 | .loa-version.json undefined but referenced | Sprint 1 Task 2: New task — schema + initialization logic |
| IMP-003 | 805 | Entropy detection needs algorithm/threshold | Sprint 3 Task 1: Shannon entropy, min 20 chars, ≥4.5 bits/char threshold |
| IMP-004 | 805 | JSONL concurrent writers need locking | Sprint 1 Task 4: New task — `append_jsonl()` with flock |
