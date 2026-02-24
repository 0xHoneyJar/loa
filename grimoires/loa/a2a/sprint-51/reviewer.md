# Sprint 8 (sprint-51): Excellence Hardening — Implementation Report

> Cycle: cycle-035
> Sprint: sprint-8 (global: sprint-51)
> Source: Bridgebuilder Part 8 Code Review (Issue #402)

## Summary

All 7 findings from the Bridgebuilder Part 8 code review have been addressed. Every finding was fixed regardless of severity level — the goal was excellence, not minimum compliance.

## Task Implementation

### Task 8.1: Fix path traversal blind spot (F-001, LOW)

**File**: `.claude/scripts/lib/symlink-manifest.sh:198`

**Before**: Pattern matched `*../*` and `*/../*` but missed trailing `..` (e.g., `.claude/constructs/..`).

**After**: Added `|| [[ "$link" == *.. ]]` to catch all traversal patterns including trailing `..`.

**Test coverage**: Existing test "rejects path traversal in link" + new alignment test "both schema and runtime reject path traversal with .." validates trailing `..` specifically.

### Task 8.2: Schema pattern enforcement (F-002, LOW)

**File**: `.claude/schemas/construct-manifest.schema.json:29,46`

**Change**: Added `"pattern": "^\\.claude/"` to both `directories[].link` and `files[].link` properties in the JSON Schema.

**Impact**: Schema validation now rejects manifests where link paths don't start with `.claude/` at parse time, before runtime validation even runs. Defense in depth.

### Task 8.3: flock-based migration lock (F-003, MEDIUM)

**File**: `.claude/scripts/mount-submodule.sh:193-218`

**Before**: PID-only lock — susceptible to PID recycling race condition where a stale lock from PID 12345 could block a new process that was assigned the same PID.

**After**:
- **Primary**: `flock -n 200` on the lock file descriptor — automatically releases on process death.
- **Fallback**: PID + epoch timestamp with 1-hour staleness threshold for systems without `flock`.
- `command -v flock` check selects the appropriate strategy at runtime.

### Task 8.4: Dead logic removal (F-004, LOW)

**File**: `.claude/scripts/mount-loa.sh:1684`

**Before**: `if [[ "$feasibility_pass" == "true" ]] || [[ ${#feasibility_failures[@]} -eq 0 ]]; then`

**After**: `if [[ "$feasibility_pass" == "true" ]]; then`

**Rationale**: `feasibility_pass` is only set to `"false"` when a failure is added to the array, making the two conditions logically equivalent. The redundant check created ambiguity for future maintainers.

### Task 8.5: Batched jq invocations (F-005, LOW)

**File**: `.claude/scripts/lib/symlink-manifest.sh:151-170`

**Before**: Per-entry jq loop: `1 + 2N` process forks (1 for count, 2 per entry for link+target).

**After**: 2 jq invocations total using `@tsv` output and process substitution `< <(...)`:
```bash
while IFS=$'\t' read -r link target; do
  _validate_and_add_construct_entry "$link" "$target" "$pack_name" "$repo_root"
done < <(jq -r '(.symlinks.directories // [])[] | [.link, .target] | @tsv' "$manifest_file" 2>/dev/null)
```

Process substitution keeps the `while` loop in the current shell, preserving global array writes to `MANIFEST_CONSTRUCT_SYMLINKS`.

### Task 8.6: Configurable remote allowlist (F-006, LOW)

**File**: `.claude/scripts/update-loa.sh:43-57`

**Before**: Hardcoded `ALLOWED_REMOTES` array with 3 0xHoneyJar URLs — blocked fork users from using `/update-loa`.

**After**:
- Reads `update.allowed_remotes[]` from `.loa.config.yaml` if available.
- Falls back to original hardcoded defaults when no config exists or config is empty.
- Added documented example to `.loa.config.yaml.example`.

### Task 8.7: Schema-runtime alignment tests (F-007, SPECULATION)

**File**: `.claude/scripts/tests/test-construct-manifest.bats` (4 new tests)

New tests:
1. `alignment: both schema and runtime reject link outside .claude/` — verifies both layers reject `src/malicious`
2. `alignment: both schema and runtime reject path traversal with ..` — verifies trailing `..` caught by runtime
3. `alignment: both schema and runtime reject absolute path link` — verifies `/etc/passwd` rejected by both
4. `alignment: schema pattern field exists on both link properties` — structural assertion that pattern constraint exists

When `ajv` or `jsonschema` CLI is available, tests validate against the actual schema. Otherwise, they fall back to verifying the schema has the pattern constraint and that runtime rejects the invalid input.

## Test Results

| Suite | Tests | Result |
|-------|-------|--------|
| test-construct-manifest.bats | 17 (13 existing + 4 new) | 17/17 PASS |
| test-mount-symlinks.bats | 21 | 21/21 PASS |
| test-zone-guard-symlinks.bats | 12 | 12/12 PASS |
| test-eject-portability.bats | 6 | 6/6 PASS |
| test-mount-submodule-default.bats | 30 | 30/30 PASS |
| test-migration.bats | 13 | 13/13 PASS |
| test-stealth-expansion.bats | 17 | 17/17 PASS |
| **Total** | **116** | **116/116 PASS** |

Zero regressions. 4 new tests added.

## Files Changed

| File | Lines Added | Lines Removed | Change Type |
|------|-------------|---------------|-------------|
| `.claude/scripts/lib/symlink-manifest.sh` | 11 | 14 | Security fix + perf |
| `.claude/schemas/construct-manifest.schema.json` | 4 | 2 | Schema hardening |
| `.claude/scripts/mount-submodule.sh` | 21 | 8 | Lock mechanism upgrade |
| `.claude/scripts/mount-loa.sh` | 1 | 1 | Dead code removal |
| `.claude/scripts/update-loa.sh` | 13 | 4 | Configurable allowlist |
| `.claude/scripts/tests/test-construct-manifest.bats` | 120 | 0 | Alignment tests |
| `.loa.config.yaml.example` | 10 | 0 | Config documentation |

## Finding Traceability

| Finding | Severity | Task | Status |
|---------|----------|------|--------|
| F-001: Path traversal misses trailing `..` | LOW | 8.1 | FIXED |
| F-002: Schema no `.claude/` prefix enforcement | LOW | 8.2 | FIXED |
| F-003: PID-based lock susceptible to recycling | MEDIUM | 8.3 | FIXED |
| F-004: Dead logic in feasibility check | LOW | 8.4 | FIXED |
| F-005: O(n^2) jq invocations per manifest | LOW | 8.5 | FIXED |
| F-006: Hardcoded remote allowlist blocks forks | LOW | 8.6 | FIXED |
| F-007: Schema-runtime validation gap | SPECULATION | 8.7 | TESTED |
