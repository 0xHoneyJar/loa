APPROVED - LETS FUCKING GO

# Sprint-46 (Cycle-035 Sprint-3) Security Audit

> **Auditor**: Paranoid Cypherpunk Auditor (Opus 4.6)
> **Date**: 2026-02-24
> **Verdict**: APPROVED -- 0 CRITICAL, 0 HIGH, 3 LOW, 1 INFO

---

## Audit Scope

| File | Change | Risk |
|------|--------|------|
| `.claude/scripts/loa-eject.sh` | NEW: `eject_submodule()` function (~140 lines) | HIGH (destructive ops: `rm -rf`, `git rm -f`) |
| `.claude/scripts/mount-loa.sh` | Updated `verify_mount()` symlink health check | MEDIUM (validation logic) |
| `.claude/scripts/memory-setup.sh` | `.loa/` -> `.loa-cache/` path migration | LOW (config path change) |
| `.claude/scripts/memory-admin.sh` | `.loa/` -> `.loa-cache/` path migration | LOW (config path change) |
| `.claude/scripts/memory-sync.sh` | `.loa/` -> `.loa-cache/` path migration | LOW (config path change) |
| `.claude/scripts/butterfreezone-gen.sh` | `installation_mode` detection | LOW (read-only) |
| `.claude/scripts/tests/test-mount-symlinks.bats` | NEW: 19 tests | LOW (test code) |
| `INSTALLATION.md` | CI/CD examples | LOW (documentation) |

---

## Security Findings

### LOW-001: Execution Order -- `eject_submodule()` runs before `create_backup()`

**Location**: `loa-eject.sh`, `eject_files()` L571-581

In `eject_files()`, Phase 0 (`eject_submodule`) executes at L576 BEFORE Phase 1 (`create_backup`) at L581. If eject crashes mid-way through Phase 1 (symlink replacement), there is no backup to restore from.

**Mitigations (adequate)**:
- `set -euo pipefail` ensures clean exit on failure
- Phase 1 of eject only replaces symlinks with copies -- the original data in the submodule directory remains untouched until Phase 2 (`git rm`)
- Phase 2's `git rm -f` is recoverable via `git checkout`
- `--dry-run` mode lets users preview before committing
- The ordering is intentional: backup needs real files, not symlinks, so it must come after symlink-to-file conversion

**Severity**: LOW -- ordering is a design choice with acceptable rationale, not a bug

### LOW-002: No path sanitization on `submodule_path`

**Location**: `loa-eject.sh`, L424-426

```bash
submodule_path=$(jq -r '.submodule.path // ".loa"' "$VERSION_FILE" 2>/dev/null) || true
submodule_path="${submodule_path:-.loa}"
```

The `submodule_path` is read from `.loa-version.json` without explicit validation that it does not contain `..` or absolute path components. A malicious `.loa-version.json` with `"path": "../../"` could cause `rm -rf` on L544 to target an ancestor directory.

**Mitigations (adequate)**:
- `.loa-version.json` is a local, user-controlled file (not network-sourced)
- The function validates `"$submodule_path/.claude"` directory exists before proceeding (L428) -- path traversal targets unlikely to have `.claude/` subdirectory
- Full eject flow requires user to type "eject" at confirmation prompt (L730)
- Attacker with write access to `.loa-version.json` already has full working tree access
- `rm -rf "$submodule_path"` on L544 is preceded by `git rm -f "$submodule_path"` on L542, which would fail for non-submodule paths

**Severity**: LOW -- theoretical path traversal, but preconditions require existing filesystem compromise

### LOW-003: Engineer ADV-1 -- `.gitmodules` index tracking after eject

**Location**: `loa-eject.sh`, L542-548

As noted by the engineer reviewer (ADV-1): `git rm -f "$submodule_path"` on L542 typically handles `.gitmodules` via git internals, but if `.gitmodules` was already unstaged, the empty-file removal on L546-548 removes the filesystem copy without `git rm` from the index.

**Mitigations (adequate)**:
- Standard `git submodule deinit -f` + `git rm -f` sequence handles 99% of cases
- The remaining edge case (unstaged `.gitmodules`) would leave a benign empty tracked file
- Users would notice and clean up during the `git commit` step in post-eject instructions

**Severity**: LOW -- cosmetic edge case, not a security or data loss issue

### INFO-001: `install_mode` output in BUTTERFREEZONE

**Location**: `butterfreezone-gen.sh`, L685-690, L906

The `installation_mode` value is emitted in the AGENT-CONTEXT YAML block. This reveals whether the installation is "submodule" or "standard".

**Assessment**: This is intentional -- the BUTTERFREEZONE is designed to be a project summary for agents. The installation mode is not sensitive information. No action needed.

---

## Verification: Memory Path Consistency

Confirmed all `.loa/` -> `.loa-cache/` migrations are complete and consistent:

| Script | `LOA_DIR` | Residual `.loa/` refs | Verdict |
|--------|-----------|----------------------|---------|
| `memory-setup.sh` | `${PROJECT_ROOT}/.loa-cache` (L18) | 0 | PASS |
| `memory-admin.sh` | `${PROJECT_ROOT}/.loa-cache` (L26) | 0 | PASS |
| `memory-sync.sh` | `${PROJECT_ROOT}/.loa-cache/sync_state.json` (L25) | 0 | PASS |

User-facing install instructions in `memory-setup.sh` L101 also correctly reference `.loa-cache/venv`.

---

## Verification: Symlink Health Check

`mount-loa.sh` `verify_mount()` (L1499-1521):

- Reads `installation_mode` from `.loa-version.json` with jq -- correct
- Only activates symlink check for `"submodule"` mode -- correct
- Checks both `-L` (is symlink) AND `-e` (resolves) -- correct (catches dangling symlinks)
- Falls back gracefully for real directories (`-d "$sl" && ! -L "$sl"`) -- correct
- Emits `"warn"` status, not `"fail"` -- appropriate (symlinks can be repaired)
- Repair instructions point to `mount-submodule.sh --reconcile` -- correct

No issues found.

---

## Verification: Test Quality

19 tests in `test-mount-symlinks.bats`:

| Category | Count | Verification Type |
|----------|-------|-------------------|
| Symlink existence + resolution (Task 3.1) | 10 | Behavioral: `-L`, `-d`, `-f`, content read |
| Manifest coverage (bonus) | 3 | Code-level: grep function/array existence |
| Memory stack relocation (Task 3.2) | 3 | Code-level: grep function behavior |
| Gitignore correctness (Task 3.3) | 3 | Behavioral: grep actual .gitignore + code-level |

**Assessment**: The 10 Task 3.1 tests are strong behavioral tests that actually create symlinks, verify they resolve, and check content accessibility. The `overrides_not_symlinked` test (L163-170) verifies writability, which is a genuine security property. The Task 3.2 tests are code-level (grep-based), which is an acceptable trade-off given the full behavioral tests for the same functions exist in the sprint-1 and sprint-2 suites (30 + 13 tests).

---

## Verification: Documentation (INSTALLATION.md)

CI/CD section (L639-699):
- GitHub Actions example uses correct `actions/checkout@v4` with `submodules: recursive`
- GitLab CI example uses correct `GIT_SUBMODULE_STRATEGY: recursive`
- Shallow clone example uses generic `your-org/your-repo` placeholder -- no org-specific paths leaked
- API key examples use placeholder `sk_your_api_key_here` -- no real secrets
- No internal paths, team names, or infrastructure details exposed

No information disclosure issues found.

---

## Decision

| Severity | Count | Details |
|----------|-------|---------|
| CRITICAL | 0 | -- |
| HIGH | 0 | -- |
| MEDIUM | 0 | -- |
| LOW | 3 | Execution order (mitigated), path sanitization (mitigated), gitmodules edge case (cosmetic) |
| INFO | 1 | Installation mode in BUTTERFREEZONE (intentional) |

**Verdict: APPROVED** -- No blocking issues. All LOW findings have adequate mitigations in place. The `eject_submodule()` function follows a sound 3-phase approach with proper dry-run support, confirmation prompts, and `set -euo pipefail` safety. Memory path migrations are consistent. Test coverage is comprehensive. Documentation is clean.

79/79 tests pass across 4 suites. Zero regressions. All 5 PRD goals (G1-G5) validated end-to-end.

Cycle-035 "Minimal Footprint by Default" is complete.
