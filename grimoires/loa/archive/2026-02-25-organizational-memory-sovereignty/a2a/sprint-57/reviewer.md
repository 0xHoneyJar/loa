# Sprint 57 Implementation Report — State-Dir Resolution Foundation
> Cycle: cycle-038 | Local Sprint: 1 | Global Sprint: 57

## Summary

Implemented the centralized state-dir resolution layer in `path-lib.sh`, upgrading from v1.0.0 to v2.0.0. This establishes the foundation for the Three-Zone State Architecture, providing canonical path resolution for all state directories with environment variable override, config file support, absolute path safety controls, layout versioning, and concurrent JSONL operations.

## Tasks Completed

### Task 1: State-Dir Resolution in `_read_config_paths()`
**File**: `.claude/scripts/path-lib.sh` (lines 247-286)

- Priority chain: `LOA_STATE_DIR` env > `paths.state_dir` config > `.loa-state` default
- Absolute paths rejected unless `LOA_ALLOW_ABSOLUTE_STATE=1` is set
- Absolute path validation: existence check + writability check
- Relative paths automatically prefixed with `$PROJECT_ROOT/`
- Extracted `_resolve_state_dir_from_env()` helper for reuse across init paths

**AC**: All 3 precedence levels verified by unit tests (Tests 1-3).

### Task 2: `.loa-version.json` Schema + Initialization
**File**: `.claude/scripts/path-lib.sh` (lines 455-478)

- `detect_state_layout()`: Reads `.loa-version.json`, returns version number (0 if missing)
- `init_version_file()`: Atomic creation via tmp + mv pattern
  - Fresh installs: `state_layout_version: 2`
  - Legacy detection: if `.beads/`, `.run/`, or `.ck/` exist → `state_layout_version: 1`
- Schema: `{ state_layout_version, created, last_migration }`

**AC**: Verified by unit tests (Tests 7-8).

### Task 3: `ensure_state_structure()`
**File**: `.claude/scripts/path-lib.sh` (lines 484-493)

Creates full `.loa-state/` directory hierarchy:
- `beads/`, `ck/`, `run/bridge-reviews/`, `run/mesh-cache/`
- `memory/archive/`, `memory/sessions/`
- `trajectory/current/`, `trajectory/archive/`
- Calls `init_version_file()` at the end

**AC**: All 7 subdirectories verified by unit test (Test 6).

### Task 4: `append_jsonl()` Locking Utility
**File**: `.claude/scripts/path-lib.sh` (lines 499-513)

- flock-based advisory locking with 5-second timeout
- O_APPEND via `>>` for kernel-level atomicity
- Lock file created at `${file}.lock`
- Concurrent safety verified with 10 parallel writers

**AC**: Sequential writes (Test 9) and concurrent writes (Test 10) both pass.

### Task 5: Conformance Test
**File**: `tests/unit/test-state-path-conformance.sh`

- Phase 1: Advisory baseline scan — 223 hardcoded state path references found across 268 scripts
- Phase 2: Hard check — 0 failures (no scripts sourcing path-lib use raw paths)
- Excludes: path-lib.sh, bootstrap.sh, migrate-state-layout.sh, test files, beads utilities
- Establishes migration tracking baseline for Sprint 2+

**AC**: Test passes (exit 0). Baseline of 223 violations documented.

### Task 6: Config Example Updates
**File**: `.loa.config.yaml.example`

New sections added:
- `paths.state_dir: .loa-state` under paths section
- `LOA_STATE_DIR` and `LOA_ALLOW_ABSOLUTE_STATE` in env var documentation
- `trajectory:` config block (archive interval, retention)
- `memory_bootstrap:` config block (sources, quality gates)
- `redaction:` config block (strict mode, entropy threshold, allowlist)
- `migration:` config block (compat mode, lock timeout, backup)

**AC**: All new config options documented with defaults and descriptions.

### Task 7: Unit Tests
**File**: `tests/unit/test-path-lib-state.sh`

22 test cases covering all Sprint 1 features:
1. Default state directory resolution
2. Environment variable precedence over default
3. Config file precedence over default
4. Absolute path rejection without opt-in
5. Absolute path acceptance with `LOA_ALLOW_ABSOLUTE_STATE=1`
6. `ensure_state_structure()` — 7 directory assertions + version file
7. `detect_state_layout()` — missing, v1, v2 version files
8. `init_version_file()` — fresh install (v2) and legacy detection (v1)
9. `append_jsonl()` — sequential writes + lock file presence
10. `append_jsonl()` — 10 concurrent writers with JSON validity check

**AC**: 22/22 tests pass. File-based counter propagation for subshell isolation.

## Files Changed

| File | Action | Lines |
|------|--------|-------|
| `.claude/scripts/path-lib.sh` | Modified | +202 |
| `.loa.config.yaml.example` | Modified | +64 |
| `tests/unit/test-path-lib-state.sh` | Created | 285 |
| `tests/unit/test-state-path-conformance.sh` | Created | 97 |

**Total**: 4 files, +643 lines

## Test Results

```
path-lib.sh State-Dir Extension Tests: 22/22 passed, 0 failed
State Path Conformance Test: 0 hard failures, 223 advisory baseline violations
```

## Acceptance Criteria Status

- [x] `get_state_dir()` returns env > config > default with validation
- [x] Absolute paths rejected without `LOA_ALLOW_ABSOLUTE_STATE=1`
- [x] `detect_state_layout()` reads `.loa-version.json` correctly
- [x] `init_version_file()` detects legacy layout (v1) vs fresh (v2)
- [x] `ensure_state_structure()` creates full directory tree
- [x] `append_jsonl()` handles concurrent writes safely
- [x] Conformance baseline established (223 refs tracked)
- [x] Config example updated with all new options
- [x] All 22 unit tests passing

## Flatline Findings Addressed

| Finding | Status | Implementation |
|---------|--------|----------------|
| IMP-001 (migration journal) | Deferred to Sprint 2 | Sprint 2 scope |
| IMP-002 (.loa-version.json) | Implemented | Task 2: detect + init |
| IMP-003 (entropy threshold) | Config ready | Task 6: redaction config |
| IMP-004 (JSONL locking) | Implemented | Task 4: flock-based |
| SKP-001 (absolute paths) | Implemented | Task 1: LOA_ALLOW_ABSOLUTE_STATE |
| SKP-002 (migration verification) | Deferred to Sprint 2 | Sprint 2 scope |
| SKP-003 (PID lock fragile) | Implemented | Task 4: flock replaces PID |
| SKP-004 (conformance scope) | Implemented | Task 5: expanded to hooks |
| SKP-005 (redaction false positives) | Config ready | Task 6: allowlist config |
| SKP-006 (sentinel bypass) | Config ready | Task 6: strict mode config |

## Commit

```
ab00d9d feat(cycle-038): Sprint 1 — State-Dir Resolution Foundation
```
