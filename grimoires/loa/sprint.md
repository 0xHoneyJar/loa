# Sprint Plan: Minimal Footprint by Default — Submodule-First Installation

> Cycle: cycle-035
> PRD: `grimoires/loa/prd.md`
> SDD: `grimoires/loa/sdd.md`
> Team: 1 AI developer
> Sprint duration: 1 sprint per session

---

## Sprint Overview

| Sprint | Global ID | Label | Goal |
|--------|-----------|-------|------|
| sprint-1 | sprint-44 | Foundation — Default Flip + Symlinks + Gitignore | Flip default to submodule mode, add missing symlinks, fix .gitignore collision |
| sprint-2 | sprint-45 | Migration + Polish | Migration command, stealth expansion, /loa status boundary report, /update-loa submodule support |
| sprint-3 | sprint-46 | Hardening + E2E Validation | Symlink verification tests, 15-script compatibility audit, loa-eject update, CI/CD documentation |
| sprint-4 | sprint-47 | Bridgebuilder Code Quality — DRY Manifest + Naming + Safety | Extract symlink manifest, rename .loa-cache → .loa-state, document --no-verify + lock scope, gitignore backup dirs |
| sprint-5 | sprint-48 | Installation Documentation Excellence | Pros/cons comparison across all install methods in README, INSTALLATION.md, and PROCESS.md |
| sprint-6 | sprint-49 | Portability + Security Hardening | Fix readlink -f macOS incompatibility, harden Agent Teams zone guard against symlink bypass, add migration feasibility validation |
| sprint-7 | sprint-50 | Construct Manifest Extension Point | Prototype construct-level manifest declarations for ecosystem extensibility |
| sprint-8 | sprint-51 | Excellence Hardening — Bridgebuilder Part 8 Findings | Fix all Part 8 findings: path traversal, schema-runtime gap, PID lock, jq perf, fork-friendly config |

**Sprints 1-5**: COMPLETED. Bridge review flatlined at 0.4 (3.0 → 0.4). All 131+ tests passing.

**Sprints 6-7**: COMPLETED. Bridge review flatlined at 0.5 (3.0 → 0.4 → 0.5). All 112 tests passing.

**Sprint 8**: Address Bridgebuilder Part 8 code review findings (all 7 findings regardless of severity). Aiming for excellence.

**Source**: Bridgebuilder Code Review Part 8 ([Issue #402](https://github.com/0xHoneyJar/loa/issues/402#issuecomment-3948715877)) — Findings F-001 through F-007

---

## Sprint 6: Portability + Security Hardening

**Goal**: Fix the HIGH-severity `readlink -f` macOS incompatibility in the eject path, harden Agent Teams zone guard against symlink-based System Zone bypass, and add migration dry-run feasibility validation. These three findings represent the final pre-merge quality bar.

**Global ID**: sprint-49
**Scope**: MEDIUM (5 tasks)
**Source**: Bridgebuilder findings high-1, medium-2, low-1

### Deliverables

- [ ] `loa-eject.sh` uses `get_canonical_path()` instead of raw `readlink -f` → **[high-1]**
- [ ] Agent Teams zone guard resolves symlinks before path checking → **[medium-2]**
- [ ] Migration dry-run validates feasibility (disk space, permissions, git state) → **[low-1]**
- [ ] Comprehensive tests for all three fixes
- [ ] Cross-platform compatibility documentation

### Acceptance Criteria

- [ ] `loa-eject.sh` eject flow works on macOS (BSD readlink) — all symlinks resolved via `get_canonical_path()` from `compat-lib.sh`
- [ ] No raw `readlink -f` calls remain in `loa-eject.sh` (verified by grep)
- [ ] `team-role-guard-write.sh` checks BOTH the raw path AND the resolved symlink target against System Zone patterns
- [ ] A teammate cannot write to `.loa/.claude/scripts/foo.sh` through the `.claude/scripts/foo.sh` symlink projection
- [ ] A teammate CAN still write to legitimate State Zone paths (grimoires/, .beads/) — no false positives
- [ ] `--migrate-to-submodule --dry-run` reports: disk space required, write permissions, git status clean check, submodule URL reachability
- [ ] Feasibility check runs BEFORE classification report (fail fast)
- [ ] All existing tests pass (zero regression)
- [ ] New tests cover: eject portability, zone guard symlink bypass, migration feasibility

### Technical Tasks

- [ ] **Task 6.1**: Fix `readlink -f` portability in `loa-eject.sh` → **[high-1]**
  - Source `compat-lib.sh` at top of eject function (it provides `get_canonical_path()`)
  - Replace line 451: `real_src=$(readlink -f "$link_path" 2>/dev/null || true)` → `real_src=$(get_canonical_path "$link_path" 2>/dev/null || true)`
  - Replace line 468: `real_src=$(readlink -f ".claude/settings.local.json" 2>/dev/null || true)` → `real_src=$(get_canonical_path ".claude/settings.local.json" 2>/dev/null || true)`
  - `compat-lib.sh` already provides the 3-tier fallback: readlink -f → realpath -m → cd+pwd -P
  - Verify `compat-lib.sh` is sourced once (check for existing source statement)
  - **FAANG parallel**: Node.js's `path.resolve()` uses the same cd+pwd fallback in their configure script. Platform detection at load time, portable API at call time.
  - File: `.claude/scripts/loa-eject.sh`

- [ ] **Task 6.2**: Harden Agent Teams zone guard for symlink resolution → **[medium-2]**
  - Current issue: `team-role-guard-write.sh:44` uses `realpath -m --relative-to=.` which resolves symlinks to their physical location. When Write targets `.claude/scripts/foo.sh` (a symlink to `.loa/.claude/scripts/foo.sh`), realpath resolves to `.loa/.claude/scripts/foo.sh` which does NOT match the `.claude/*` prefix check — bypassing the guard.
  - Fix: Check BOTH the original path AND the resolved path against protected patterns
  - Implementation approach:
    ```bash
    # Get both the raw path and resolved path
    raw_path="$file_path"  # from jq parse, before realpath
    resolved_path=$(realpath -m --relative-to=. "$file_path" 2>/dev/null) || true

    # Check both against System Zone prefix
    for check_path in "$raw_path" "$resolved_path"; do
      check_path="${check_path#./}"
      if [[ "$check_path" == .claude/* || "$check_path" == ".claude" ]]; then
        # BLOCKED
      fi
      # Also check resolved symlink targets within .loa/.claude/
      if [[ "$check_path" == .loa/.claude/* || "$check_path" == ".loa/.claude" ]]; then
        # BLOCKED — physical System Zone via submodule
      fi
    done
    ```
  - Add `.loa/.claude/*` as a protected prefix (the physical System Zone location in submodule mode)
  - Maintain fail-open semantics: if either path resolution fails, allow (don't block on errors)
  - File: `.claude/hooks/safety/team-role-guard-write.sh`
  - **FAANG parallel**: Linux kernel's path traversal security (CVE-2009-0029 class) — always resolve AND check both the logical and physical paths.

- [ ] **Task 6.3**: Add migration dry-run feasibility validation → **[low-1]**
  - Add `validate_migration_feasibility()` function to `mount-loa.sh`
  - Called BEFORE the discovery/classification phase in `--migrate-to-submodule --dry-run`
  - Checks:
    1. **Disk space**: Estimate space needed (submodule clone ~50MB), check available with `df`
    2. **Write permissions**: Test write to `.claude/`, `.gitignore`, project root
    3. **Git state**: Verify clean working tree (already exists, but surface in feasibility report)
    4. **Network**: Test `git ls-remote $LOA_REMOTE_URL` reachability (with 5s timeout)
    5. **Submodule conflicts**: Check if `.loa/` path already in use
  - Output format: Each check shows PASS/FAIL with details
  - If any FAIL: print summary with remediation instructions
  - **Terraform parallel**: `terraform plan` validates feasibility (provider auth, state lock, resource limits) before showing the execution plan. The dry-run should do the same.
  - File: `.claude/scripts/mount-loa.sh`

- [ ] **Task 6.4**: Tests for portability + security fixes
  - New test: `eject_uses_portable_readlink` — verify no raw `readlink -f` in loa-eject.sh
  - New test: `eject_resolves_symlinks` — verify eject correctly resolves symlinked paths on the current platform
  - New test: `zone_guard_blocks_symlink_bypass` — verify teammate Write to `.claude/scripts/foo.sh` (symlink) is blocked
  - New test: `zone_guard_blocks_submodule_direct` — verify teammate Write to `.loa/.claude/scripts/foo.sh` (physical) is blocked
  - New test: `zone_guard_allows_state_zone` — verify teammate Write to `grimoires/loa/foo.md` is allowed (no false positive)
  - New test: `migration_feasibility_clean_tree` — verify feasibility check passes on clean tree
  - New test: `migration_feasibility_dirty_tree` — verify feasibility check reports dirty tree
  - Files: `.claude/scripts/tests/test-eject-portability.bats`, `.claude/scripts/tests/test-zone-guard-symlinks.bats`

- [ ] **Task 6.5**: Cross-platform documentation update
  - Add "Cross-Platform Compatibility" section to INSTALLATION.md
  - Document: macOS requires no Homebrew packages (compat-lib handles all), Windows WSL recommended, Linux works out of the box
  - Update PROCESS.md helper scripts section to note compat-lib dependency
  - File: `INSTALLATION.md`, `PROCESS.md`

### Dependencies

- Sprint 5 (documentation complete, all prior sprints passing)
- `compat-lib.sh` already exists with `get_canonical_path()` — no new dependency

### Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Zone guard dual-check false positives | Test both allow AND block paths. Maintain fail-open on errors. |
| compat-lib sourcing adds startup latency to eject | `compat-lib.sh` uses one-time feature detection (~5ms). Negligible. |
| Feasibility check network timeout in CI | 5-second timeout on git ls-remote. Skip if CI detected and submodule already in .gitmodules. |

### Rollback

Task 6.1 can be reverted by restoring `readlink -f` calls (functionality unchanged on Linux). Task 6.2 is additive — removing the dual-check reverts to current behavior. Task 6.3 is a new function — removing it reverts to current dry-run behavior.

### Success Metrics

- `grep -r "readlink -f" .claude/scripts/loa-eject.sh` returns zero matches
- Zone guard test suite covers symlink bypass scenario
- Migration dry-run shows feasibility report before classification
- All 131+ existing tests pass + new tests pass
- No functional behavior changes for non-Agent-Teams users

---

## Sprint 7: Construct Manifest Extension Point

**Goal**: Prototype the construct-level manifest extension mechanism that allows construct packs to declare their own symlink requirements. This is the first step toward vision-008 (Manifest as Declarative Configuration) — the architectural precondition for Loa's ecosystem play.

**Global ID**: sprint-50
**Scope**: MEDIUM (5 tasks)
**Source**: Bridgebuilder finding medium-1, vision-008

### Deliverables

- [ ] Construct manifest schema (`construct-manifest.yaml`) → **[medium-1]**
- [ ] Manifest merger in `symlink-manifest.sh` that reads construct declarations → **[medium-1]**
- [ ] Validation for construct manifest entries (prevent escape, conflict detection) → **[security]**
- [ ] Example construct manifest in documentation → **[DX]**
- [ ] Tests for manifest extension, validation, and merge

### Acceptance Criteria

- [ ] Constructs can declare symlink requirements in a `.loa-construct-manifest.yaml` file within their pack directory
- [ ] `get_symlink_manifest()` discovers and merges construct manifests with core manifest
- [ ] Construct manifests cannot declare symlinks outside `.claude/` boundary (validated)
- [ ] Construct manifests cannot override core manifest entries (conflict detection → warning)
- [ ] Dependency ordering: construct `requires` are validated before symlink creation
- [ ] Example construct manifest provided in `PROCESS.md` or construct documentation
- [ ] `create_symlinks()` and `verify_and_reconcile_symlinks()` transparently handle merged manifest (no changes to consumers)
- [ ] All existing tests pass (zero regression)
- [ ] New tests cover: construct manifest discovery, merge, validation, conflict detection

### Technical Tasks

- [ ] **Task 7.1**: Define construct manifest schema
  - Create schema at `.claude/schemas/construct-manifest.schema.yaml`
  - Format:
    ```yaml
    # .loa-construct-manifest.yaml (inside a construct pack directory)
    name: my-construct
    version: "1.0.0"
    symlinks:
      directories:
        - link: ".claude/data/my-construct"
          target: "constructs/my-construct/data"
      files:
        - link: ".claude/loa/reference/my-construct-reference.md"
          target: "constructs/my-construct/reference.md"
    requires:
      - ".claude/scripts"   # must exist before my links
      - ".claude/data"      # parent directory must be linked
    ```
  - Validate with existing schema validation patterns from `.claude/schemas/`
  - File: `.claude/schemas/construct-manifest.schema.yaml`

- [ ] **Task 7.2**: Implement construct manifest discovery and merge
  - Extend `get_symlink_manifest()` in `lib/symlink-manifest.sh` to:
    1. After computing core manifest, scan for construct manifests
    2. Look in `${submodule}/.claude/constructs/*/` for `.loa-construct-manifest.yaml` files
    3. Also look in `.claude/constructs/*/` for user-installed constructs
    4. Parse YAML entries (using `yq` if available, grep fallback for simple cases)
    5. Append to new array: `MANIFEST_CONSTRUCT_SYMLINKS`
    6. Update `get_all_manifest_entries()` to include construct entries
  - Construct entries use the same `"link_path:target_path"` format as core entries
  - Target paths in construct manifests are relative to repo root (resolved from construct dir)
  - **Kubernetes CRD parallel**: Just as CRDs extend the Kubernetes API without modifying the core, construct manifests extend the symlink topology without modifying `symlink-manifest.sh`'s core arrays.
  - File: `.claude/scripts/lib/symlink-manifest.sh`

- [ ] **Task 7.3**: Implement construct manifest validation
  - Add `validate_construct_manifest()` function
  - Security checks:
    1. **Boundary enforcement**: All `link` paths must be under `.claude/` — reject paths that escape (e.g., `../../etc/passwd`)
    2. **Conflict detection**: No construct entry may override a core manifest entry — warn and skip
    3. **Dependency validation**: All `requires` entries must exist in the core manifest or as filesystem paths
    4. **Path sanitization**: Strip `..` traversals, normalize paths, reject absolute paths
  - Log warnings for skipped entries, don't fail the mount
  - **npm peerDependencies parallel**: Like npm's peer dependency validation, construct `requires` declare what must exist but don't install it themselves.
  - File: `.claude/scripts/lib/symlink-manifest.sh`

- [ ] **Task 7.4**: Documentation and example construct manifest
  - Add "Construct Manifest Protocol" section to PROCESS.md
  - Include example `.loa-construct-manifest.yaml` with all supported fields
  - Document validation rules and error messages
  - Reference vision-008 as the broader roadmap
  - Update BUTTERFREEZONE.md construct section if applicable
  - Files: `PROCESS.md`, potentially `INSTALLATION.md`

- [ ] **Task 7.5**: Tests for construct manifest extension
  - New test: `construct_manifest_discovery` — verify manifests found in construct dirs
  - New test: `construct_manifest_merge` — verify construct entries added to manifest
  - New test: `construct_manifest_boundary_escape` — verify path escape rejected
  - New test: `construct_manifest_conflict_detection` — verify core entry override warned
  - New test: `construct_manifest_requires_validation` — verify dependency check
  - New test: `construct_manifest_empty_graceful` — verify no constructs → manifest unchanged
  - New test: `construct_manifest_no_yq_fallback` — verify basic parsing without yq
  - File: `.claude/scripts/tests/test-construct-manifest.bats`

### Dependencies

- Sprint 6 (portability fixes ensure manifest works cross-platform)
- `lib/symlink-manifest.sh` (Sprint 4 extraction provides the extension point)

### Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| yq not available on all systems | grep/awk fallback for simple YAML parsing. Schema designed for minimal nesting. |
| Construct manifests introduce symlink conflicts | Conflict detection (Task 7.3) warns and skips — never overrides core. |
| Path traversal attacks in construct manifests | Boundary enforcement validates all links under `.claude/`. Path sanitization strips `..` |
| No existing constructs use manifests yet | Design is forward-compatible. No breaking changes. Example in docs enables adoption. |

### Rollback

Construct manifest support is fully additive. Removing the discovery/merge code in `get_symlink_manifest()` reverts to Sprint 4 behavior. No existing functionality is modified — only new code paths added.

### Success Metrics

- Construct packs can declare symlink requirements in `.loa-construct-manifest.yaml`
- Core manifest behavior unchanged when no construct manifests exist
- Path escape attempts blocked with clear error messages
- Conflict detection prevents construct manifests from overriding core entries
- All 131+ existing tests pass + 7 new tests pass

---

## Sprint 8: Excellence Hardening — Bridgebuilder Part 8 Findings

**Goal**: Address all 7 findings from the Bridgebuilder Part 8 code review regardless of severity. Zero tolerance for known imperfections. Aiming for excellence.

**Global ID**: sprint-51
**Scope**: MEDIUM (7 tasks)
**Source**: Bridgebuilder Code Review Part 8 ([Issue #402](https://github.com/0xHoneyJar/loa/issues/402#issuecomment-3948715877))

### Deliverables

- [ ] Path traversal validation catches trailing `..` → **[F-001]**
- [ ] Construct manifest schema enforces `.claude/` prefix at JSON Schema level → **[F-002]**
- [ ] Migration lock uses `flock` with PID fallback → **[F-003]**
- [ ] Dead logic removed from feasibility check → **[F-004]**
- [ ] Construct manifest jq invocations batched to O(1) → **[F-005]**
- [ ] Remote allowlist configurable via `.loa.config.yaml` → **[F-006]**
- [ ] Schema-runtime alignment test validates both reject the same inputs → **[F-007]**

### Acceptance Criteria

- [ ] Path `".claude/constructs/.."` is rejected by `_validate_and_add_construct_entry()` — test proves it
- [ ] JSON Schema for construct manifest has `"pattern": "^\\.claude/"` on link properties
- [ ] `relocate_memory_stack()` uses `flock` when available, falls back to PID+timestamp for stale detection
- [ ] Line 1684 of `mount-loa.sh` simplified — no redundant condition
- [ ] Construct manifest parsing uses a single `jq` call with `@tsv` output instead of per-entry forks
- [ ] `update-loa.sh` reads `update.allowed_remotes` from `.loa.config.yaml` with hardcoded default fallback
- [ ] A test verifies that the schema and runtime validation agree on boundary enforcement for at least 3 invalid inputs
- [ ] All 112 existing tests pass (zero regression)
- [ ] New tests cover all 7 findings

### Technical Tasks

- [ ] **Task 8.1**: Fix path traversal blind spot → **[F-001, LOW]**
  - File: `.claude/scripts/lib/symlink-manifest.sh:198`
  - Add trailing `..` check: `|| [[ "$link" == *.. ]]`
  - Also switch to allowlist pattern: add a positive-match regex `^\.claude/[a-zA-Z0-9_-]+(/[a-zA-Z0-9_.-]+)*$` as the primary validation, keeping the deny patterns as defense-in-depth
  - New test in `test-construct-manifest.bats`: verify `.claude/constructs/..` is rejected
  - **FAANG parallel**: CVE-2021-21300 in Git — path traversal through symlinks. Kubernetes admission controllers use allowlists, not deny-lists.

- [ ] **Task 8.2**: Add schema-level link prefix enforcement → **[F-002, LOW]**
  - File: `.claude/schemas/construct-manifest.schema.json`
  - Add `"pattern": "^\\.claude/"` to both `link` properties (directories and files)
  - Add `"not": {"pattern": "\\.\\."}` to reject `..` in link paths at schema level
  - Also add `"not": {"pattern": "^/"}` to reject absolute paths in target properties
  - This makes the schema a first line of defense matching the runtime validation
  - **FAANG parallel**: Google's Protocol Buffers and Stripe's OpenAPI specs enforce constraints at schema level. The schema is a contract, not just documentation.

- [ ] **Task 8.3**: Replace PID-based lock with flock → **[F-003, MEDIUM]**
  - File: `.claude/scripts/mount-submodule.sh` — `relocate_memory_stack()` function
  - Implementation:
    ```bash
    if command -v flock &>/dev/null; then
      exec 200>"$migration_lock"
      if ! flock -n 200; then
        err "Memory Stack migration already in progress."
      fi
    else
      # Fallback: PID + epoch timestamp for stale detection (>1 hour = stale)
      if [[ -f "$migration_lock" ]]; then
        local lock_info lock_pid lock_time
        lock_info=$(cat "$migration_lock" 2>/dev/null || echo "")
        lock_pid="${lock_info%%:*}"
        lock_time="${lock_info##*:}"
        local now; now=$(date +%s)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
          if [[ -n "$lock_time" ]] && (( now - lock_time < 3600 )); then
            err "Migration in progress (PID: $lock_pid, started $(( (now - lock_time) / 60 ))m ago)."
          fi
          warn "Stale lock (PID $lock_pid, >1h old). Removing."
        fi
        rm -f "$migration_lock"
      fi
      echo "$$:$(date +%s)" > "$migration_lock"
    fi
    ```
  - `flock` releases automatically on process death — no PID recycling risk
  - Fallback uses PID + timestamp — a 1-hour staleness threshold prevents false-positive blocks
  - **FAANG parallel**: Redis switched from PID files to `flock`. PostgreSQL's `postmaster.pid` uses PID + data directory + start time for the same reason.

- [ ] **Task 8.4**: Remove dead logic in feasibility check → **[F-004, LOW]**
  - File: `.claude/scripts/mount-loa.sh:1684`
  - Simplify from:
    ```bash
    if [[ "$feasibility_pass" == "true" ]] || [[ ${#feasibility_failures[@]} -eq 0 ]]; then
    ```
  - To:
    ```bash
    if [[ "$feasibility_pass" == "true" ]]; then
    ```
  - The two conditions are logically equivalent — `feasibility_pass` is only set to `"false"` when a failure is added to the array. Keeping both creates ambiguity for future maintainers.
  - **FAANG parallel**: Google's readability reviews. "Code is read far more often than it's written. Remove anything that makes the reader think harder than necessary."

- [ ] **Task 8.5**: Batch jq invocations for construct manifests → **[F-005, LOW]**
  - File: `.claude/scripts/lib/symlink-manifest.sh:151-170`
  - Replace the per-entry jq loop with a single batched call:
    ```bash
    # Parse all directory entries in one jq call
    jq -r '(.symlinks.directories // [])[] | [.link, .target] | @tsv' "$manifest_file" 2>/dev/null |
    while IFS=$'\t' read -r link target; do
      _validate_and_add_construct_entry "$link" "$target" "$pack_name" "$repo_root"
    done

    # Parse all file entries in one jq call
    jq -r '(.symlinks.files // [])[] | [.link, .target] | @tsv' "$manifest_file" 2>/dev/null |
    while IFS=$'\t' read -r link target; do
      _validate_and_add_construct_entry "$link" "$target" "$pack_name" "$repo_root"
    done
    ```
  - Reduces from `1 + 2N` jq invocations to exactly 2 (regardless of N)
  - **Note**: The `while read` loop runs in a subshell due to the pipe. Since `_validate_and_add_construct_entry` appends to `MANIFEST_CONSTRUCT_SYMLINKS` (a global array), we need to collect entries via process substitution or a temp file instead:
    ```bash
    while IFS=$'\t' read -r link target; do
      _validate_and_add_construct_entry "$link" "$target" "$pack_name" "$repo_root"
    done < <(jq -r '(.symlinks.directories // [])[] | [.link, .target] | @tsv' "$manifest_file" 2>/dev/null)
    ```
  - Process substitution `< <(...)` keeps the while loop in the current shell, preserving global array writes.
  - **FAANG parallel**: The "N+1 query problem" from every ORM. Netflix's build system: "every $() is a fork, every fork is ~5ms."

- [ ] **Task 8.6**: Make remote allowlist configurable → **[F-006, LOW]**
  - File: `.claude/scripts/update-loa.sh:44-48`
  - Read from `.loa.config.yaml` with hardcoded default:
    ```bash
    # Load custom allowed remotes from config, fall back to hardcoded defaults
    ALLOWED_REMOTES=()
    if command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
      local custom_remotes
      custom_remotes=$(yq_read "$CONFIG_FILE" '.update.allowed_remotes[]' '' 2>/dev/null) || true
      if [[ -n "$custom_remotes" ]]; then
        while IFS= read -r remote; do
          [[ -n "$remote" ]] && ALLOWED_REMOTES+=("$remote")
        done <<< "$custom_remotes"
      fi
    fi
    # Default if no config or empty
    if [[ ${#ALLOWED_REMOTES[@]} -eq 0 ]]; then
      ALLOWED_REMOTES=(
        "https://github.com/0xHoneyJar/loa.git"
        "https://github.com/0xHoneyJar/loa"
        "git@github.com:0xHoneyJar/loa.git"
      )
    fi
    ```
  - Add `.loa.config.yaml.example` entry:
    ```yaml
    # update:
    #   allowed_remotes:    # Override for forks/mirrors (default: 0xHoneyJar/loa)
    #     - "https://github.com/your-org/loa.git"
    #     - "git@github.com:your-org/loa.git"
    ```
  - **FAANG parallel**: Terraform's `.terraformrc` for registry overrides, Go's `GOPROXY` env var. Preserves default security posture while enabling fork-friendly configuration.

- [ ] **Task 8.7**: Schema-runtime alignment test → **[F-007, SPECULATION → TEST]**
  - File: `.claude/scripts/tests/test-construct-manifest.bats` (new tests)
  - Verify that schema and runtime validation agree on at least 3 invalid inputs:
    1. Link outside `.claude/` → both should reject
    2. Link with `..` traversal → both should reject
    3. Link with absolute path → both should reject
  - If `ajv` or `jsonschema` CLI is available, validate against schema; otherwise skip schema test with `[SKIP]` annotation
  - This ensures the two validation layers don't drift as the manifest evolves
  - **FAANG parallel**: loa-hounfour's TypeBox → JSON Schema generation + conformance vectors. The gold standard: types, schemas, and runtime share a single source of truth.

### Dependencies

- Sprint 7 complete (construct manifest exists to be improved)
- All 112 existing tests passing

### Risks & Mitigation

| Risk | Sprint | Severity | Mitigation |
|------|--------|----------|------------|
| `flock` unavailable on some systems | 8 | LOW | PID+timestamp fallback with 1-hour staleness threshold |
| Process substitution `< <(...)` not available in sh | 8 | LOW | All scripts use `#!/usr/bin/env bash` — bash4+ guaranteed |
| Schema pattern change breaks valid manifests | 8 | LOW | Pattern matches exactly what runtime allows — `.claude/` prefix. No valid manifest broken. |
| `yq` API differences (mikefarah vs jq-like) | 8 | LOW | `yq_read()` helper already handles both variants |

### Rollback

Every task is independently revertible. Tasks 8.1-8.2 are additive validations. Task 8.3 preserves fallback behavior. Task 8.4 is a simplification. Task 8.5 is a performance optimization that produces identical output. Task 8.6 preserves defaults when no config exists. Task 8.7 is test-only.

### Success Metrics

- All 7 Bridgebuilder Part 8 findings addressed
- Path `.claude/constructs/..` rejected in both schema and runtime
- Migration lock uses `flock` on Linux systems
- `jq` invocation count reduced from `1+2N` to `2` per manifest
- Fork users can configure remote allowlist without patching framework
- All 112+ existing tests pass + new tests pass
- Zero regression, zero new security vulnerabilities

---

## Risk Register (All Sprints)

| Risk | Sprint | Severity | Mitigation |
|------|--------|----------|------------|
| macOS eject fails silently | 6 | HIGH | Replace `readlink -f` with `get_canonical_path()` — 3-tier fallback chain |
| Agent Teams symlink bypass | 6 | MEDIUM | Dual-path checking + `.loa/.claude/` protection |
| PID recycling in migration lock | 8 | MEDIUM | `flock` with PID+timestamp fallback |
| Construct manifest path escape | 7 | MEDIUM | Boundary enforcement + sanitization |
| Schema-runtime validation drift | 8 | LOW | Alignment test validates both reject same inputs |
| yq unavailable on target system | 7 | LOW | grep/awk fallback for simple YAML |
| Migration dry-run network timeout | 6 | LOW | 5-second timeout, skip in CI |

## Appendix: Finding Traceability

| Finding ID | Severity | Finding | Sprint | Task |
|------------|----------|---------|--------|------|
| high-1 | **HIGH** | `readlink -f` in eject path fails silently on macOS | 6 | 6.1 |
| medium-1 | MEDIUM | Construct packs can't declare symlink requirements | 7 | 7.1-7.5 |
| medium-2 | MEDIUM | Agent Teams zone guard doesn't resolve symlinks | 6 | 6.2 |
| low-1 | LOW | Migration dry-run doesn't validate feasibility | 6 | 6.3 |
| F-001 | LOW | Path traversal misses trailing `..` | 8 | 8.1 |
| F-002 | LOW | Schema doesn't enforce `.claude/` prefix on link | 8 | 8.2 |
| F-003 | **MEDIUM** | PID-based lock susceptible to recycling | 8 | 8.3 |
| F-004 | LOW | Dead logic / redundant condition in feasibility | 8 | 8.4 |
| F-005 | LOW | O(n²) jq invocations per construct manifest | 8 | 8.5 |
| F-006 | LOW | Hardcoded remote allowlist blocks fork users | 8 | 8.6 |
| F-007 | SPECULATION | Schema-runtime validation gap | 8 | 8.7 |

## Definition of Done

- All acceptance criteria checked
- All new code has test coverage
- Existing 112+ test suite unbroken (zero regression)
- Sprint review + audit cycle passed
- No new security vulnerabilities introduced
- All Bridgebuilder findings (Parts 4-5: high-1, medium-1, medium-2, low-1; Part 8: F-001 through F-007) addressed
- Vision-008 advanced from Captured → Exploring
