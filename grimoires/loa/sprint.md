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

**MVP**: Sprint 1 delivers the default flip — after Sprint 1, new `/mount` installations use submodule mode. Sprints 2-3 are migration tooling and hardening.

**Risk**: Sprint 1 is lowest-risk (single-line default change + missing symlinks). Sprint 2 carries migration complexity. Sprint 3 is verification-heavy.

**Key Discovery**: `mount-submodule.sh` (619 lines) already implements full submodule installation. This is a **default flip**, not a greenfield build. "From sdd.md §1: The infrastructure already exists...The work is: (1) flip the default...and (4) add migration tooling."

---

## Sprint 1: Foundation — Default Flip + Symlinks + Gitignore

**Goal**: Make submodule mode the default for `/mount`, add missing symlinks to `mount-submodule.sh`, resolve `.loa/` path collision in `.gitignore`, and add graceful degradation preflight.

**Global ID**: sprint-44
**Scope**: MEDIUM (7 tasks)

### Deliverables

- [ ] `SUBMODULE_MODE=true` as default in `mount-loa.sh` → **[G1]**
- [ ] `--vendored` flag for backward compatibility → **[G5]**
- [ ] Missing symlinks added (hooks, data, reference, feedback-ontology, learnings) → **[G2]**
- [ ] `.gitignore` collision resolved (`.loa/` → `.loa-cache/`) → **[G3]**
- [ ] Graceful degradation preflight (auto-fallback to vendored) → **[G1, G5]**
- [ ] Post-clone auto-init for uninitialized submodules → **[G1]**
- [ ] Unit tests for default behavior, flags, and mode conflicts

### Acceptance Criteria

- [ ] Running `/mount` with no flags routes to `mount-submodule.sh` (submodule mode)
- [ ] Running `/mount --vendored` routes to standard mode (800+ file copy)
- [ ] Running `/mount --submodule` is a no-op (already default) with deprecation log
- [ ] `.claude/hooks/`, `.claude/data/`, `.claude/loa/reference/`, `.claude/loa/feedback-ontology.yaml`, `.claude/loa/learnings/` are all symlinked after submodule mount
- [ ] `.loa/` is NOT in `.gitignore` (submodule must be tracked)
- [ ] `.loa-cache/` IS in `.gitignore` (Memory Stack new home)
- [ ] Symlink entries (`.claude/scripts`, `.claude/protocols`, etc.) in `.gitignore`
- [ ] `@.claude/loa/CLAUDE.loa.md` import resolves correctly through symlink chain
- [ ] When git is unavailable, `/mount` falls back to vendored mode with warning
- [ ] When symlinks are not supported, `/mount` falls back to vendored mode with warning
- [ ] Fallback reason always recorded in `.loa-version.json` `fallback_reason` field (Flatline SKP-001)
- [ ] Prominent summary printed: "Installation: submodule" or "Installation: vendored (fallback: <reason>)"
- [ ] When `.loa/` exists as non-submodule (Memory Stack data), it auto-relocates to `.loa-cache/`
- [ ] Memory Stack relocation uses copy-then-verify-then-switch with lock file (Flatline IMP-002)
- [ ] Concurrent `/mount` operations prevented by lock file at `.claude/.mount-lock` (Flatline IMP-006)
- [ ] All new tests pass; existing mount tests unbroken

### Technical Tasks

- [ ] **Task 1.1**: Flip `SUBMODULE_MODE` default in `mount-loa.sh:183` from `false` to `true` → **[G1]**
  - Single line change: `SUBMODULE_MODE=true`
  - File: `.claude/scripts/mount-loa.sh`
  - Ref: SDD §3.1.1

- [ ] **Task 1.2**: Add `--vendored` flag + deprecate `--submodule` → **[G5]**
  - Add `--vendored)` case that sets `SUBMODULE_MODE=false`
  - Change `--submodule)` to no-op with deprecation log
  - Update help text to show submodule as default, vendored as opt-in
  - File: `.claude/scripts/mount-loa.sh` (lines 212-234)
  - Ref: SDD §3.1.2, §3.1.3

- [ ] **Task 1.3**: Update mode conflict messages → **[G5]**
  - Update `check_mode_conflicts()` error messages for inverted default
  - Standard→submodule blocked with migration hint
  - Submodule→vendored blocked with manual instructions
  - File: `.claude/scripts/mount-loa.sh` (lines 1310-1333)
  - Ref: SDD §3.1.4

- [ ] **Task 1.4**: Add graceful degradation preflight + mount lock → **[G1, G5]**
  - Implement `preflight_submodule_environment()` function
  - Check: git present, inside git repo, git version ≥ 1.8, symlink support, CI submodule state
  - Auto-fallback to vendored with clear warning on any failure
  - Always record `fallback_reason` in `.loa-version.json` when falling back (Flatline SKP-001)
  - Print prominent installation mode summary after mount completes
  - Add mount lock file (`.claude/.mount-lock`) to prevent concurrent `/mount` (Flatline IMP-006)
  - CI guard: detect `CI=true` + uninitialized submodule → clear error with exact fix command (Flatline SKP-007)
  - Call before `route_to_submodule()`
  - File: `.claude/scripts/mount-loa.sh`
  - Ref: SDD §3.1.5 (Flatline IMP-001, SKP-001, SKP-002, SKP-007, IMP-006)

- [ ] **Task 1.5**: Add missing symlinks to `mount-submodule.sh` → **[G2]**
  - Add `.claude/hooks/` → `../.loa/.claude/hooks` symlink
  - Add `.claude/data/` → `../.loa/.claude/data` symlink
  - Add `.claude/loa/reference/` → `../../.loa/.claude/loa/reference` symlink
  - Add `.claude/loa/feedback-ontology.yaml` → file symlink
  - Add `.claude/loa/learnings/` → dir symlink
  - Fix preflight Memory Stack detection (`.loa/` auto-relocate to `.loa-cache/`)
  - Migration uses copy-then-verify-then-switch: `cp -r` → verify file count match → `rm -rf` source (Flatline IMP-002)
  - Lock file (`.loa-cache/.migration-lock`) prevents concurrent relocation (Flatline IMP-002)
  - Rollback on verification failure: remove partial `.loa-cache/`, log error (Flatline IMP-002)
  - Add `auto_init_submodule()` for post-clone recovery
  - File: `.claude/scripts/mount-submodule.sh` (after line 322)
  - Ref: SDD §3.2.1-3.2.5 (Flatline IMP-002, SKP-003)

- [ ] **Task 1.6**: Fix `.gitignore` collision + add symlink entries → **[G3]**
  - Remove `.loa/` entry (line 75) — replace with `.loa-cache/`
  - Add symlink gitignore entries: `.claude/scripts`, `.claude/protocols`, `.claude/hooks`, `.claude/data`, `.claude/schemas`, `.claude/loa/CLAUDE.loa.md`, `.claude/loa/reference`, `.claude/loa/feedback-ontology.yaml`, `.claude/loa/learnings`
  - File: `.gitignore`
  - Ref: SDD §3.3.1, §3.3.2

- [ ] **Task 1.7**: Unit tests for default flip, flags, preflight, symlinks → **[G1, G2]**
  - New test file: `.claude/scripts/tests/test-mount-submodule-default.bats`
  - Tests: `default_is_submodule`, `vendored_flag`, `submodule_flag_noop`, `mode_conflict_standard_to_sub`, `mode_conflict_sub_to_vendored`
  - Tests for preflight: `no_git_falls_back`, `no_symlinks_falls_back`
  - Tests for symlinks: verify all expected symlinks exist after mount
  - Test for Memory Stack relocation: `.loa/` non-submodule auto-migrates
  - ~80 lines
  - Ref: SDD §6.1, §6.2

### Dependencies

- None (Sprint 1 is the foundation)

### Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| @-import breaks after default flip | Design verified in SDD §2.3 — submodule at `.loa/`, symlink chain preserves `@.claude/loa/CLAUDE.loa.md`. Test in Task 1.7. |
| Existing `.loa/` Memory Stack blocks submodule add | Auto-relocate via atomic `mv` in preflight (Task 1.5). Test coverage for this path. |
| git unavailable in some environments | Graceful degradation preflight (Task 1.4) auto-falls back to vendored mode. |

### Rollback (Flatline IMP-001)

If Sprint 1 changes cause issues:
1. Revert `SUBMODULE_MODE=true` → `false` in `mount-loa.sh:183` (single line)
2. Revert `.gitignore` changes: restore `.loa/` entry, remove `.loa-cache/` and symlink entries
3. Remove added symlink creation code from `mount-submodule.sh` (the script still works, symlinks are additive)
4. Existing submodule installations continue working — the revert only affects new `/mount` calls

### Success Metrics

- `/mount` with no flags creates submodule at `.loa/` (not vendored)
- `git ls-files` shows ≤ 5 framework-related tracked files after fresh mount
- Fallback rate: 0% on systems with git + symlinks (tracked via `.loa-version.json`)
- All new tests pass
- Existing mount tests unbroken

---

## Sprint 2: Migration + Polish

**Goal**: Provide one-command migration for existing users, expand stealth mode coverage, add `/loa` boundary report, and add submodule support to `/update-loa`.

**Global ID**: sprint-45
**Scope**: LARGE (8 tasks)

### Deliverables

- [ ] `/mount --migrate-to-submodule` command → **[G4]**
- [ ] `apply_stealth()` expansion from 4 to 14 entries → **[G3]**
- [ ] Memory Stack relocation utility (`get_memory_stack_path()`) → **[G3]**
- [ ] `/loa` status boundary report showing installation mode → **[G2]**
- [ ] `/update-loa` submodule support with symlink reconciliation → **[G1]**
- [ ] `verify_and_reconcile_symlinks()` algorithm → **[G1]**
- [ ] Documentation updates (INSTALLATION.md, README.md, PROCESS.md) → **[G1]**
- [ ] Migration tests + stealth tests

### Acceptance Criteria

- [ ] `/mount --migrate-to-submodule` defaults to dry-run mode; requires `--apply` to execute (Flatline SKP-004)
- [ ] Migration preserves: `.loa.config.yaml`, `.claude/settings.json`, `.claude/commands/`, `.claude/overrides/`
- [ ] Migration creates timestamped backup at `.claude.backup.{timestamp}/`
- [ ] Migration with `--dry-run` (default) shows classification report without changes
- [ ] Migration requires clean working tree (dirty → error with `git stash` instruction)
- [ ] Migration classifies files: FRAMEWORK (remove), USER_MODIFIED (flag with explicit user choice), USER_OWNED (preserve)
- [ ] Single-command rollback documented: `git checkout <pre-migration-commit>` + restore backup (Flatline SKP-004)
- [ ] `apply_stealth()` adds 14 entries (4 core + 10 doc) — no duplicates on re-run
- [ ] `/loa` shows installation mode (submodule vs vendored), commit hash, file counts
- [ ] `/update-loa` in submodule mode: fetches, checks out, verifies symlinks
- [ ] `verify_and_reconcile_symlinks()` detects dangling symlinks, removes stale, recreates from manifest
- [ ] Supply chain integrity: allowlist expected remote URL, enforce HTTPS, record commit hash + repo identity in `.loa-version.json` (Flatline SKP-005)
- [ ] CI mode: `--require-submodule` + `--require-verified-origin` flags fail closed on mismatch
- [ ] INSTALLATION.md updated with submodule-first quickstart

### Technical Tasks

- [ ] **Task 2.1**: Implement `--migrate-to-submodule` command → **[G4]**
  - Add to `mount-loa.sh` argument parser as new subcommand
  - Default mode is `--dry-run` (show classification report only). Requires `--apply` to execute. (Flatline SKP-004)
  - Workflow: detect mode → require clean tree → create migration branch → discovery phase → backup → classify files → `git rm --cached` framework files → `git submodule add` → create symlinks → restore user files → update `.loa-version.json` → update `.gitignore` → commit
  - Discovery phase classifies FRAMEWORK/USER_MODIFIED/USER_OWNED using `.loa-version.json` checksums
  - USER_MODIFIED files require explicit user confirmation (keep/remove/backup)
  - Rollback: `git checkout <pre-migration-commit>` + restore from `.claude.backup.{timestamp}/`
  - ~140 lines new function
  - File: `.claude/scripts/mount-loa.sh`
  - Ref: SDD §3.6 (Flatline SKP-004)

- [ ] **Task 2.2**: Expand `apply_stealth()` → **[G3]**
  - Replace current 4-entry implementation with 14-entry version
  - Core entries: `grimoires/loa/`, `.beads/`, `.loa-version.json`, `.loa.config.yaml`
  - Doc entries: `PROCESS.md`, `CHANGELOG.md`, `INSTALLATION.md`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE.md`, `BUTTERFREEZONE.md`, `.reviewignore`, `.trufflehog.yaml`, `.gitleaksignore`
  - Idempotent: `grep -qxF` before appending
  - File: `.claude/scripts/mount-loa.sh` (lines 985-1009)
  - Ref: SDD §3.4

- [ ] **Task 2.3**: Implement Memory Stack relocation utility → **[G3]**
  - Create `get_memory_stack_path()` utility function
  - Transactional migration: copy → verify file count → switch → cleanup (Flatline IMP-002, SKP-003)
  - Lock file prevents concurrent access during migration
  - Automatic rollback on verification failure: remove partial copy, log error
  - Cross-filesystem: rsync + count verification, never silent `rm`
  - Update any memory/embedding scripts referencing `.loa/` path
  - File: `.claude/scripts/mount-submodule.sh` or new utility
  - Ref: SDD §3.5 (Flatline SKP-003, IMP-002)

- [ ] **Task 2.4**: Implement `/loa` status boundary report → **[G2]**
  - Detect installation mode from `.loa-version.json`
  - Show: mode (submodule/vendored), commit hash, tracked file count, submodule file count, gitignored file count
  - List user-owned tracked files
  - File: `.claude/scripts/golden-path.sh` or loa skill
  - Ref: SDD §3.7

- [ ] **Task 2.5**: Implement `/update-loa` submodule support → **[G1]**
  - Detect mode from `.loa-version.json`
  - Submodule mode: `cd .loa && git fetch && git checkout <tag>` → verify symlinks
  - Update commit hash + repo identity (owner/name) in `.loa-version.json`
  - Run `verify_and_reconcile_symlinks()` after update
  - Supply chain: allowlist expected remote URL(s), enforce HTTPS, compare commit hash (Flatline SKP-005)
  - CI flags: `--require-submodule` fails if not submodule, `--require-verified-origin` fails on URL mismatch
  - Pin to tagged releases by default, not branch HEAD
  - File: update-loa skill / `.claude/scripts/update-loa.sh`
  - Ref: SDD §3.8, §5.2 (Flatline SKP-005)

- [ ] **Task 2.6**: Implement `verify_and_reconcile_symlinks()` + symlink health command → **[G1]**
  - Authoritative symlink manifest (directory symlinks + file symlinks + per-skill symlinks)
  - Use canonical path resolver (avoid CWD assumptions) (Flatline SKP-002)
  - Phase 1: Check directory symlinks (scripts, protocols, hooks, data, schemas)
  - Phase 2: Check file/nested symlinks (CLAUDE.loa.md, reference, feedback-ontology.yaml, learnings)
  - Phase 3: Check per-skill symlinks
  - Detect dangling → remove → recreate from manifest → report count
  - Add standalone `--check-symlinks` subcommand for mount health checks (Flatline SKP-002)
  - File: `.claude/scripts/mount-submodule.sh`
  - Ref: SDD §3.8.1 (Flatline IMP-004, SKP-002)

- [ ] **Task 2.7**: Update documentation → **[G1]**
  - INSTALLATION.md: Rewrite Method 1 as submodule (default), add Method 3 as vendored (legacy)
  - README.md: Update quickstart to show submodule install
  - PROCESS.md: Update "Getting Started" section
  - `.claude/skills/mounting-framework/SKILL.md`: Update default behavior docs
  - ~100 lines of documentation changes

- [ ] **Task 2.8**: Migration tests + stealth tests
  - Migration tests in `.claude/scripts/tests/test-migration.bats`: `migration_creates_backup`, `migration_preserves_settings`, `migration_preserves_commands`, `migration_preserves_overrides`, `migration_already_submodule`, `migration_dry_run`
  - Stealth tests in `.claude/scripts/tests/test-stealth-expansion.bats`: `stealth_core_entries`, `stealth_doc_entries`, `stealth_idempotent`, `standard_no_docs`
  - ~110 lines
  - Ref: SDD §6.3, §6.4

### Dependencies

- Sprint 1 (default flip and symlinks must be in place)

### Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Migration loses user files | Discovery phase classifies files before removal. Timestamped backup created first. `--dry-run` available. |
| Migration on dirty tree corrupts state | Require clean working tree (`git status --porcelain` empty). Error message with `git stash` instruction. |
| USER_MODIFIED framework files ambiguous | Flag for user review with choice: keep/remove/backup. Don't auto-decide. |
| Supply chain: submodule URL tampered | `verify_submodule_integrity()` compares URL against expected origin. Commit hash comparison on update. |

### Rollback (Flatline IMP-001)

If Sprint 2 changes cause issues:
1. Migration: `git checkout <pre-migration-commit>` restores exact pre-migration state. Backup at `.claude.backup.{timestamp}/` provides file-level recovery.
2. Stealth mode: revert `apply_stealth()` changes in `mount-loa.sh`. Remove added `.gitignore` entries manually.
3. `/update-loa` submodule: revert to `cd .loa && git checkout <previous-tag>`. Symlink reconciliation is idempotent.
4. Memory Stack: if `.loa-cache/` relocation failed, data remains at `.loa/` (fallback path in `get_memory_stack_path()`).

### Success Metrics

- `/mount --migrate-to-submodule --apply` converts a standard install with zero data loss
- `--dry-run` (default) shows accurate classification without side effects
- `/loa` shows clear boundary report with file counts
- `/update-loa` fetches and reconciles symlinks in submodule mode
- All stealth entries (14) present in `.gitignore` after stealth mode application

---

## Sprint 3: Hardening + E2E Validation

**Goal**: Comprehensive verification of symlink integrity, 15-script compatibility audit, loa-eject submodule support, CI/CD documentation, and end-to-end goal validation.

**Global ID**: sprint-46
**Scope**: MEDIUM (7 tasks)

### Deliverables

- [ ] Symlink verification test suite → **[G1, G2]**
- [ ] Memory Stack relocation test suite → **[G3]**
- [ ] Gitignore correctness test suite → **[G3]**
- [ ] 15-script compatibility audit with fixes → **[G1]**
- [ ] `loa-eject.sh` submodule mode support → **[G5]**
- [ ] CI/CD documentation and examples → **[G1]**
- [ ] End-to-end goal validation

### Acceptance Criteria

- [ ] 10 symlink tests pass (scripts, protocols, hooks, data, schemas, CLAUDE.loa.md, reference, @-import resolves, user files NOT symlinked, overrides NOT symlinked)
- [ ] 3 Memory Stack tests pass (new path used, auto-migrate from old path, submodule safe)
- [ ] 3 Gitignore tests pass (`.loa/` NOT gitignored, `.loa-cache/` gitignored, symlinks gitignored)
- [ ] All 15 scripts from SDD §3.9 audited; those needing changes updated
- [ ] `loa-eject.sh` handles submodule mode: deinit submodule, remove symlinks, copy files to `.claude/`
- [ ] INSTALLATION.md has GitHub Actions and GitLab CI examples for submodule clone
- [ ] All PRD goals (G1-G5) validated end-to-end

### Technical Tasks

- [ ] **Task 3.1**: Symlink verification test suite → **[G1, G2]**
  - New file: `.claude/scripts/tests/test-mount-symlinks.bats`
  - 10 tests: `scripts_symlink`, `protocols_symlink`, `hooks_symlink`, `data_symlink`, `schemas_symlink`, `claude_loa_md_symlink`, `reference_symlink`, `at_import_resolves`, `user_files_not_symlinked`, `overrides_not_symlinked`
  - Each test verifies symlink exists and target resolves
  - ~100 lines
  - Ref: SDD §6.2

- [ ] **Task 3.2**: Memory Stack relocation tests → **[G3]**
  - Tests: `memory_stack_new_path`, `memory_stack_auto_migrate`, `memory_stack_submodule_safe`
  - Verify `.loa-cache/` used for fresh installs
  - Verify auto-migration from non-submodule `.loa/`
  - Verify no migration when `.loa/` is submodule
  - ~40 lines
  - Ref: SDD §6.5

- [ ] **Task 3.3**: Gitignore correctness tests → **[G3]**
  - Tests: `loa_dir_not_gitignored`, `loa_cache_gitignored`, `symlinks_gitignored`
  - ~30 lines
  - Ref: SDD §6.6

- [ ] **Task 3.4**: 15-script compatibility audit → **[G1]**
  - Audit scripts from SDD §3.9 table:
    - `mount-loa.sh` (done in Sprint 1), `mount-submodule.sh` (done in Sprint 1)
    - `update-loa.sh` (done in Sprint 2), `golden-path.sh` (done in Sprint 2)
    - `loa-eject.sh` (Task 3.5), `verify-mount.sh` (add symlink verification)
    - `butterfreezone-gen.sh` (update installation mode label)
    - `memory-query.sh` (update to `.loa-cache/` path)
    - `beads-health.sh`, `ground-truth-gen.sh`, `run-mode-ice.sh`, `bridge-orchestrator.sh`, `flatline-orchestrator.sh`, `config-path-resolver.sh`, `check-permissions.sh` (verify via-symlink compatibility)
  - ~50 lines of changes across affected scripts
  - Ref: SDD §3.9

- [ ] **Task 3.5**: Update `loa-eject.sh` for submodule mode → **[G5]**
  - Detect installation mode from `.loa-version.json`
  - If submodule: deinit submodule → remove `.loa/` → remove symlinks → copy framework files to `.claude/` → update mode to `standard`
  - If standard: existing behavior unchanged
  - ~40 lines
  - File: `.claude/scripts/loa-eject.sh`

- [ ] **Task 3.6**: CI/CD documentation → **[G1]**
  - Add to INSTALLATION.md:
    - GitHub Actions example with `--recurse-submodules`
    - GitLab CI example with `GIT_SUBMODULE_STRATEGY: recursive`
    - Shallow clone compatibility (`--depth 1`)
  - ~20 lines
  - Ref: PRD US-5, SDD §7.1

- [ ] **Task 3.7**: End-to-End Goal Validation → **[G1, G2, G3, G4, G5]**
  - Validate each PRD goal:
    - **G1** (Submodule default): Fresh `/mount` uses submodule
    - **G2** (≤5 tracked files): Count tracked framework files after mount
    - **G3** (Comprehensive gitignore): Zero `.ck/`, `.run/`, state in `git status`
    - **G4** (Migration path): `--migrate-to-submodule` converts standard install
    - **G5** (Backward compat): `--vendored` produces standard install
  - Document verification results
  - Ref: PRD §3.1

### Dependencies

- Sprint 1 (symlinks, default flip)
- Sprint 2 (migration, stealth, /update-loa)

### Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Scripts break via symlink paths | SDD §3.9 key insight: most scripts access `.claude/scripts/` paths — symlinks resolve transparently. Audit verifies. |
| loa-eject creates incomplete state | Test coverage for eject flow. Eject copies ALL framework files before removing submodule. |
| CI examples wrong for specific providers | Test examples with GitHub Actions matrix. Include shallow clone + recurse-submodules combo. |

### Rollback (Flatline IMP-001)

Sprint 3 is verification-only — no rollback needed. Test files and documentation can be removed without affecting functionality. The `loa-eject.sh` update (Task 3.5) is additive and the existing eject flow is unchanged for standard mode.

### Success Metrics

- All symlink tests pass (10 tests)
- All Memory Stack tests pass (3 tests)
- All gitignore tests pass (3 tests)
- 15-script audit complete with zero compatibility regressions
- All PRD goals (G1-G5) validated end-to-end
- Zero regression in existing test suite

---

## Risk Register

| Risk | Sprint | Severity | Mitigation |
|------|--------|----------|------------|
| @-import chain breaks | 1 | CRITICAL | Design verified in SDD §2.3. Symlink at `.claude/loa/CLAUDE.loa.md` → `../../.loa/.claude/loa/CLAUDE.loa.md`. Task 1.7 tests this. |
| Memory Stack data loss during relocation | 1 | LOW | Atomic `mv` with verification. Cross-filesystem: rsync + count comparison. Error surfaced, not swallowed. (Flatline SKP-003) |
| Migration destroys user customizations | 2 | MEDIUM | Discovery phase classifies files. Backup created first. `--dry-run` available. USER_MODIFIED flagged for review. (Flatline SKP-004) |
| Submodule supply chain compromise | 2 | MEDIUM | URL verification + commit hash recording + optional signed tag check. (Flatline SKP-005) |
| Scripts fail through symlinks | 3 | LOW | Most scripts transparently resolve through symlinks. 15-script audit (§3.9) identifies exceptions. |
| CI without `--recurse-submodules` | 3 | HIGH | Document in INSTALLATION.md with provider-specific examples. Post-clone auto-init as safety net. |
| Users confused by git submodules | All | MEDIUM | `/loa` boundary report. Clear error messages. Documentation rewrite. |
| Windows symlink issues | 1 | LOW | `safe_symlink()` already handles this. Preflight tests symlink support. Vendored fallback. |

## Flatline SDD Review Integration

Flatline Protocol reviewed the SDD with 80% model agreement. Sprint plan incorporates all addressed blockers.

**HIGH_CONSENSUS integrated (3)**:
- IMP-001 (avg 900): Graceful degradation preflight → Task 1.4
- IMP-002 (avg 895): Post-clone auto-init → Task 1.5
- IMP-004 (avg 825): Symlink verify/reconcile algorithm → Task 2.6

**BLOCKERS addressed (5)**:
- SKP-001 (920): Submodule assumes git everywhere → Task 1.4 (graceful degradation)
- SKP-002 (880): Symlink fragility → Task 1.4 preflight + Task 2.6 reconcile
- SKP-003 (760): Memory Stack relocation risks data loss → Task 1.5 (atomic mv)
- SKP-004 (740): Migration destructive git ops → Task 2.1 (discovery phase + dry-run)
- SKP-005 (790): Submodule supply chain integrity → Task 2.5 (URL verify + commit hash)

**DISPUTED (pending user review)**:
- IMP-006: Migration dry-run output format (GPT 860 vs Opus 520) — implemented conservatively in Task 2.1
- IMP-008: Windows symlink detection (GPT 520 vs Opus 850) — covered by existing `safe_symlink()` + preflight

## Flatline Sprint Review Integration

Flatline Protocol reviewed the sprint plan with 100% model agreement.

**HIGH_CONSENSUS integrated (3)**:
- IMP-001 (avg 800): Per-sprint rollback instructions → Rollback sections added to all 3 sprints
- IMP-002 (avg 885): Memory Stack migration safety (copy-verify-switch, lock file, rollback on failure) → Task 1.5, Task 2.3
- IMP-006 (avg 785): Mount lock/idempotency guarantee → Task 1.4 (`.claude/.mount-lock`)

**BLOCKERS addressed (6)**:
- SKP-001 (900): Silent fallback undermines goal → Task 1.4 updated: record `fallback_reason` in `.loa-version.json`, prominent summary
- SKP-002 (870): Symlink fragility across platforms → Task 2.6 updated: canonical path resolver, `--check-symlinks` health command
- SKP-003 (840): Memory Stack data loss → Addressed by IMP-002 (copy-verify-switch + lock)
- SKP-004 (920): Migration complexity/irreversibility → Task 2.1 updated: default `--dry-run`, require `--apply`, explicit rollback command
- SKP-005 (760): Supply chain controls underspecified → Task 2.5 updated: allowlist URL, enforce HTTPS, repo identity, CI fail-closed flags
- SKP-007 (740): CI behavior inconsistent → Task 1.4 updated: CI guard with clear error + fix command

## Appendix A: File Change Summary

| Sprint | Files Changed | Files Created | Estimated Lines |
|--------|--------------|---------------|-----------------|
| 1 | 3 (mount-loa.sh, mount-submodule.sh, .gitignore) | 1 (test-mount-submodule-default.bats) | ~190 |
| 2 | 4 (mount-loa.sh, mount-submodule.sh, golden-path.sh, update-loa) | 2 (test-migration.bats, test-stealth-expansion.bats) | ~490 |
| 3 | 5 (loa-eject.sh, verify-mount.sh, butterfreezone-gen.sh, memory-query.sh, INSTALLATION.md) | 1 (test-mount-symlinks.bats) | ~305 |
| **Total** | **12** | **4** | **~985** |

## Appendix B: Key File References

| File | Purpose | Sprint |
|------|---------|--------|
| `.claude/scripts/mount-loa.sh` (1540 lines) | Default flip (L183), flag inversion (L212-214), mode conflicts (L1310-1333), stealth (L985-1009) | 1, 2 |
| `.claude/scripts/mount-submodule.sh` (619 lines) | Missing symlinks (L322+), preflight (L131-166), Memory Stack relocation | 1, 2 |
| `.gitignore` (222 lines) | `.loa/` → `.loa-cache/` collision fix (L75), symlink entries | 1 |
| `.claude/scripts/loa-eject.sh` | Submodule mode ejection | 3 |
| `.claude/scripts/golden-path.sh` | `/loa` status boundary report | 2 |

## Appendix C: Goal Traceability

| Goal ID | Goal | Contributing Tasks | Validated In |
|---------|------|--------------------|--------------|
| G1 | Submodule as default (100% new installs) | 1.1, 1.2, 1.4, 1.5, 2.5, 2.6, 2.7, 3.4, 3.6 | Task 3.7 |
| G2 | Minimal tracked files (≤5 files) | 1.5, 1.6, 2.4, 3.1 | Task 3.7 |
| G3 | Comprehensive gitignore (zero state in git status) | 1.6, 2.2, 2.3, 3.2, 3.3 | Task 3.7 |
| G4 | Migration path (one-command migration) | 2.1, 2.8 | Task 3.7 |
| G5 | Backward compatibility (--vendored flag) | 1.2, 1.3, 1.4, 3.5 | Task 3.7 |

All goals have contributing tasks. Task 3.7 (E2E Goal Validation) validates all 5 goals.

## Definition of Done

- All acceptance criteria checked
- All new code has test coverage
- Existing mount/symlink tests unbroken
- Sprint review + audit cycle passed
- No new security vulnerabilities introduced
- All 5 PRD goals (G1-G5) validated in Task 3.7
