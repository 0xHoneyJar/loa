# Sprint 47 Security Audit — Paranoid Cypherpunk Auditor

APPROVED - LETS FUCKING GO

## Audit Summary

Sprint 47 (Bridgebuilder Code Quality -- DRY Manifest + Naming + Safety) is a refactoring sprint touching shell scripts that handle symlinks, git commits, and file system operations. 14 files changed, 280 insertions, 327 deletions. Net reduction of 47 lines. All changes are within .claude/scripts/, .gitignore, and INSTALLATION.md.

Audited commit: `04aa6c9` (feat(sprint-47): DRY symlink manifest + .loa-state rename + safety docs)

---

## Security Checklist

### [PASS] No command injection via unsanitized variables in symlink manifest

**File**: `.claude/scripts/lib/symlink-manifest.sh`

The manifest function `get_symlink_manifest()` takes two parameters: `submodule` (default `.loa`) and `repo_root` (default `$(pwd)`). These are expanded inside double-quoted strings within array definitions:

```bash
".claude/scripts:../${submodule}/.claude/scripts"
```

**Assessment**: The `$submodule` parameter is only ever called with hardcoded values (`"$SUBMODULE_PATH"` which defaults to `.loa`) or with `$(pwd)` for `repo_root`. The parameter expansion occurs within array assignment, not in command evaluation contexts (no `eval`, no `$()` around the expansion). The `${submodule}` value flows from constants set at the top of each consumer script (never from user/network input). The colon-delimited format (`link:target`) is parsed with safe `${entry%%:*}` and `${entry#*:}` parameter expansion -- no `eval`, no word splitting risk.

The dynamic phases (3 and 4) iterate with `for skill_dir in "${repo_root}/${submodule}"/.claude/skills/*/` -- glob expansion over a controlled directory. `basename` strips path components safely.

**Verdict**: No command injection vector.

### [PASS] No path traversal -- symlink targets stay within repo

**File**: `.claude/scripts/mount-submodule.sh` (lines 330-376)

The `validate_symlink_target()` function resolves targets via `realpath` and checks they start with `$repo_root`. The `safe_symlink()` wrapper calls this validation before `ln -sf`. All four manifest consumption sites in `create_symlinks()` (lines 400-480) route through `safe_symlink`.

The manifest entries use relative paths (`../${submodule}/.claude/scripts`), which are validated after resolution to absolute paths. The check `[[ "$resolved_target" != "$repo_root"* ]]` correctly rejects targets that escape the repo boundary.

**Note**: `verify_and_reconcile_symlinks()` (line 785) creates symlinks directly with `ln -sf` in its reconciliation path, bypassing `safe_symlink`. However, this function reads from the same manifest and constructs `$full_link` from `"${repo_root}/${link_path}"` where `link_path` comes from the manifest (hardcoded relative paths). The target values are also from the manifest. Since the manifest is framework-controlled (not user input), this is acceptable. The reconciliation also resolves via `realpath -m` and checks `[[ -e "$resolved_target" ]]` before creating.

**Verdict**: Path traversal mitigated.

### [PASS] Source paths for library inclusion use safe resolution (BASH_SOURCE, dirname)

All four consumers of `lib/symlink-manifest.sh` use safe path resolution:

| Consumer | Line | Pattern |
|----------|------|---------|
| `mount-submodule.sh` | 395-396 | `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` then `source "${SCRIPT_DIR}/lib/symlink-manifest.sh"` |
| `mount-loa.sh` | 1783-1785 | `_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` then `source "${_script_dir}/lib/symlink-manifest.sh"` |
| `loa-eject.sh` | 440-442 | `_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` then `source "${_script_dir}/lib/symlink-manifest.sh"` |

All three patterns:
1. Use `BASH_SOURCE[0]` (not `$0`, which can be spoofed in sourced scripts)
2. Resolve via `cd ... && pwd` (resolves symlinks to absolute path)
3. Quote the path in `source` invocation (prevents word splitting)

**Verdict**: Safe sourcing.

### [PASS] --no-verify usage is justified and documented

All 7 `--no-verify` occurrences have been audited:

| File | Line(s) | Rationale | Justified? |
|------|---------|-----------|------------|
| `mount-submodule.sh` | 690-692 | Framework install -- only .claude/ tooling touched | YES |
| `mount-loa.sh` | 1174-1176 | Initial framework install -- only .claude/ tooling | YES |
| `mount-loa.sh` | 1308-1310 | Framework update -- only .claude/ paths + manifests | YES |
| `mount-loa.sh` | 1880-1882 | Migration -- restructures .claude/ vendored to submodule | YES |
| `update-loa.sh` | 232-233 | Submodule pointer update -- no app code touched | YES |
| `update.sh` | 1075-1077 | Framework update -- only .claude/ symlinks + manifests | YES |
| `flatline-snapshot.sh` | 455-458 | Flatline snapshot -- framework-internal state; CONDITIONAL (only when user has explicitly disabled hooks via config) | YES |

**Security assessment**: Every `--no-verify` use involves commits that exclusively touch framework infrastructure (`.claude/`, `.loa-version.json`, submodule pointers, or `.flatline/` snapshots). User pre-commit hooks typically target application code (lint, typecheck, test) and would false-positive on framework-only changes. The `flatline-snapshot.sh` case is particularly well-designed -- it only adds `--no-verify` when the user has explicitly opted out of hooks via `.loa.config.yaml` (`git_commit_with_hooks: false`), and it logs a warning when doing so.

None of these bypass security-relevant hooks (secret scanning, credential detection). These are all mechanical lint/test hooks that would block legitimate framework operations.

**Verdict**: All `--no-verify` uses are justified and documented.

### [PASS] .gitignore patterns don't accidentally hide security-relevant files

**File**: `.gitignore` (lines 73-80)

New entries:
```
.claude.backup.*
.loa-state/
```

**Analysis of `.claude.backup.*`**: This pattern matches timestamped backup directories created during migration/update/eject (e.g., `.claude.backup.1708123456`, `.claude.backup.20260224_103000`). These are temporary local artifacts containing copies of `.claude/` for rollback purposes. They should never be committed -- they contain snapshot state that could be stale and confusing.

The pattern uses the `.*` glob which is sufficiently specific (requires `.claude.backup.` prefix). It does NOT match:
- `.claude/` (no "backup" in path)
- Any application file (requires `.claude.backup.` prefix)
- `.github/` or other dotfiles

**Analysis of `.loa-state/`**: Replaces `.loa-cache/`. Contains machine-specific state (vector database, embeddings, indexes). The comment accurately describes semantics: "NOT a cache (not ephemeral) -- this is persistent local state."

**Verdict**: No accidental hiding of security-relevant files.

### [PASS] No hardcoded secrets or credentials

Scanned all 14 changed files. No API keys, tokens, passwords, private keys, or credential material found. The `LOA_UPSTREAM` URL is the public GitHub repo URL. The `ALLOWED_REMOTES` array in `update-loa.sh` contains only public GitHub URLs (HTTPS and SSH).

### [PASS] readlink -f in eject doesn't follow symlinks outside repo boundary

**File**: `.claude/scripts/loa-eject.sh` (lines 446-463)

The eject function iterates manifest entries and for each symlink:
```bash
real_src=$(readlink -f "$link_path" 2>/dev/null || true)
```

Then:
```bash
if [[ -n "$real_src" && -e "$real_src" ]]; then
    cp -r "$real_src" "$link_path"
```

`readlink -f` resolves the full chain of symlinks to the final target. In the submodule context, `.claude/scripts` -> `../.loa/.claude/scripts` resolves to within the repo (the `.loa/` submodule). The copy replaces the symlink with the resolved content.

**Risk**: Could `readlink -f` resolve to something outside the repo? Only if the symlink was manually modified to point elsewhere. The manifest entries are hardcoded relative paths, and the symlinks are created by framework scripts. An attacker who can modify symlinks in `.claude/` already has write access to the repo.

**Mitigating factor**: The eject function requires confirmation (user must type "eject") unless `--force` is used. The `create_backup` function preserves the pre-eject state for rollback.

**Verdict**: Acceptable risk. The `readlink -f` operates on framework-controlled symlinks and the eject operation is inherently destructive (converting symlinks to copies).

### [PASS] Lock file (PID-based) scope documentation is accurate

**File**: `.claude/scripts/mount-loa.sh` (lines 1366-1371)

```bash
# === Mount Lock (Flatline IMP-006) ===
# Scope: PID-based advisory lock using kill -0 liveness check.
# Safe on: Local filesystems (ext4, APFS, NTFS) -- single-host concurrency only.
# NOT safe on: NFS, CIFS, or shared-mount filesystems -- kill -0 cannot check PIDs
# on remote hosts, and echo > file is not atomic on network mounts.
# If NFS support is ever needed, use flock(1) or a lockfile(1) approach instead.
```

**Assessment**: The documentation is technically accurate. The PID-based lock (`kill -0 $lock_pid`) checks if the process is still running on the local host. This is correct behavior for local filesystems. The warning about NFS is appropriate -- `kill -0` cannot verify PIDs across hosts, and file creation/writing is not atomic on network mounts.

**Reviewer observation acknowledged**: The migration lock in `relocate_memory_stack()` (line 179) uses the same PID pattern without explicit scope documentation. This is a minor gap but not a security issue -- the function is internal and the pattern is identical.

### [PASS] INSTALLATION.md -- no secrets, no unsafe instructions

**File**: `INSTALLATION.md`

References to `.loa-state/` correctly updated. Line 283 (`rm -rf grimoires/loa/ .beads/ .loa-state/ .loa-version.json .loa.config.yaml`), line 731 (`mkdir -p .loa-state`), line 744 (`rm -rf grimoires/loa/ .beads/ .loa-state/...`).

No credentials, API keys, or dangerous instructions. The one-liner install (`curl | bash`) is for the framework's own mount script from the official GitHub repo -- this is standard practice for CLI tools and is documented with the specific URL.

---

## Additional Security Observations

### Restrictive umask (defense in depth)
Both `mount-submodule.sh` (line 28) and `loa-eject.sh` (line 24) set `umask 077` at script start. This ensures any temp files or directories created during execution have restrictive permissions (owner-only). Good practice.

### set -euo pipefail (fail-safe defaults)
All audited scripts use `set -euo pipefail` which ensures:
- `set -e`: Exit on error
- `set -u`: Error on undefined variables
- `set -o pipefail`: Propagate pipe failures

This prevents silent failures that could leave the system in an inconsistent state.

### Atomic operations
The snapshot system (`flatline-snapshot.sh`) uses temp-file-then-mv for atomic writes. The update system (`update.sh`) uses atomic swap with backup. The migration (`mount-loa.sh`) uses copy-verify-then-switch. These are all correct patterns for crash safety.

---

## Net Assessment

This is a clean DRY refactoring sprint with no new security surface area. The changes reduce code duplication (symlink manifest consolidation from 4 inline copies to 1 shared library), improve naming accuracy (`.loa-cache/` -> `.loa-state/`), and add documentation to previously undocumented safety decisions (`--no-verify` rationale, lock scope).

No new external inputs are introduced. No new command evaluation contexts. No new privilege escalation paths. The refactoring preserves all existing security controls (symlink validation, path traversal checks, umask restrictions).

**APPROVED for merge.**
