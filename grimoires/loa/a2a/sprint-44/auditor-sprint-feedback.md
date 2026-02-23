APPROVED - LETS FUCKING GO

# Sprint 44 (sprint-1) Security Audit Report

> Auditor: Paranoid Cypherpunk Auditor (Claude Opus 4.6)
> Date: 2026-02-24
> Cycle: cycle-035 -- Minimal Footprint by Default -- Submodule-First Installation
> Sprint: Foundation -- Default Flip + Symlinks + Gitignore
> Verdict: **APPROVED**

---

## Files Audited

| File | Lines Read | Focus Areas |
|------|-----------|-------------|
| `.claude/scripts/mount-loa.sh` | 183, 212-264, 1310-1450, 1557-1620 | Default flip, flags, mode conflicts, lock, preflight, fallback, main routing |
| `.claude/scripts/mount-submodule.sh` | 1-788 (full file) | Relocation, auto-init, preflight, symlinks, gitignore, manifest, commit |
| `.gitignore` | 1-223 (full file) | `.loa/` -> `.loa-cache/` change |
| `.claude/scripts/tests/test-mount-submodule-default.bats` | 1-221 (full file) | 30 test cases |

---

## Security Checklist

### Command Injection -- PASS

- All variables in command positions are properly double-quoted
- `jq` invocations at `mount-loa.sh:1318` and `mount-loa.sh:1427` use `--arg` for safe variable interpolation
- `jq` invocation at `mount-submodule.sh:227` reads from file with no user-controlled filter
- `exec` at `mount-loa.sh:1445` passes properly quoted array `"${args[@]}"`
- `git checkout "$ref"` at `mount-submodule.sh:280` is quoted
- `git submodule add` at `mount-submodule.sh:275` passes all args quoted
- No `eval` usage in new code

### Path Traversal -- PASS

- All 5 new symlinks use `safe_symlink()` with `validate_symlink_target()` validation
- Symlink targets: `.claude/hooks`, `.claude/data`, `.claude/loa/reference`, `.claude/loa/learnings`, `.claude/loa/feedback-ontology.yaml`
- Relative paths are standard pattern: `../$SUBMODULE_PATH/.claude/X` or `../../$SUBMODULE_PATH/.claude/loa/X`
- `validate_symlink_target()` resolves absolute paths via `realpath` and verifies target starts with `repo_root`
- No new symlinks bypass the `safe_symlink()` guard

### Race Conditions -- PASS

- Mount lock at `.claude/.mount-lock`: PID-based detection via `kill -0`
- Migration lock at `.loa-cache/.migration-lock`: Same PID pattern
- Both have stale lock cleanup (check if PID still running, remove if not)
- TOCTOU window between check and write is acknowledged but impact is limited to "two concurrent mounts could race" -- not a privilege escalation
- `trap 'release_mount_lock; _exit_handler' EXIT` at `mount-loa.sh:1563` ensures cleanup on all exit paths (RF-2 fix verified)

### Information Disclosure -- PASS

- Fallback reasons are generic enum strings: `git_not_available`, `not_git_repo`, `git_version_too_old`, `symlinks_not_supported`
- No sensitive paths, usernames, tokens, or system architecture details exposed
- CI guard message at `mount-loa.sh:1408-1414` prints only the fix command (safe)
- Error messages in mode conflicts mention only public directory names (`.claude/`, `.loa/`)

### Denial of Service -- PASS

- `find` at `mount-submodule.sh:165` scoped to `$source` (hardcoded `.loa`)
- `find` at `mount-submodule.sh:181` scoped to `$target` (hardcoded `.loa-cache`)
- No unbounded loops or recursive operations on user-controlled paths
- Symlink loop for skills/commands iterates over glob of existing directories (bounded by filesystem)

### File System Safety -- PASS

- `rm -rf "$source"` at line 169: `source=".loa"` (hardcoded local, only after non-submodule verification)
- `rm -rf "$target"` at lines 177, 186: `target=".loa-cache"` (hardcoded local, rollback path)
- `rm -rf "$source"` at line 191: removal after copy-verify completes successfully
- `rm -rf ".git/modules/$SUBMODULE_PATH"` at line 267: `SUBMODULE_PATH=".loa"` (hardcoded)
- `rm -rf "$SUBMODULE_PATH"` at line 268: same constrained path
- Copy-then-verify-then-switch pattern at lines 163-194 ensures no data loss during relocation
- Empty directory guard at lines 167-173 prevents fragile 0==0 verification false positive (ADV-2 fix verified)
- Dotfile copy fix at line 175: `cp -r "$source"/. "$target"/` (RF-1 fix verified)

### Supply Chain -- PASS

- `LOA_UPSTREAM` environment variable allows custom fork URLs (pre-existing, by design)
- `git submodule add` uses HTTPS URL with safe default `https://github.com/0xHoneyJar/loa.git`
- No downloads outside of git submodule mechanism
- No `curl | bash` patterns in new code

---

## Review Fix Verification

| Finding | Severity | Status | Verification |
|---------|----------|--------|--------------|
| RF-1: Dotfile loss in relocation | HIGH | FIXED | `mount-submodule.sh:175` uses `cp -r "$source"/. "$target"/` |
| RF-2: EXIT trap override | MEDIUM | FIXED | `mount-loa.sh:1563` combines `release_mount_lock; _exit_handler` |
| ADV-2: Empty directory edge case | Advisory | ADDRESSED | `mount-submodule.sh:167-173` early return guard |

---

## Advisories (Non-Blocking)

### ADV-A1: Unquoted heredoc in create_manifest (LOW)

**File**: `mount-submodule.sh:592`

The version manifest heredoc uses unquoted `<< EOF` which enables shell expansion. All interpolated variables (`$framework_version`, `$SUBMODULE_PATH`, `$ref`, `$submodule_commit`) are derived from git commands and hardcoded values, not user input. The `$(date ...)` is intentional. No current injection vector, but a quoted heredoc with `jq` construction would be more defensive.

### ADV-A2: Operator precedence in add_submodule conditional (LOW)

**File**: `mount-submodule.sh:262`

`[[ -d "$SUBMODULE_PATH" ]] || [[ -f ".gitmodules" ]] && grep -q "$SUBMODULE_PATH"` relies on bash's `&&` binding tighter than `||`. Behavior is correct for the intent, but explicit grouping with `{ }` would improve readability. Pre-existing code, not introduced by this sprint.

### ADV-A3: grep -q without -F for literal string match (LOW)

**File**: `mount-submodule.sh:142,199,262` and `mount-loa.sh:1406`

Patterns like `grep -q "$SUBMODULE_PATH" .gitmodules` and `grep -q ".loa" .gitmodules` use regex mode for what should be literal string matches. The `.` in `.loa` matches any character. No practical impact since `.loa` is unlikely to cause false positives in `.gitmodules`, but `grep -qF` would be more correct. Pre-existing pattern carried through.

---

## Test Coverage Assessment

30 tests pass. All tests are grep-based code structure verification (not integration tests). This is appropriate for sprint-1 scope. Integration tests that execute actual mount flows should be added in sprint-2 or sprint-3 as noted by the reviewer.

---

## Conclusion

No CRITICAL or HIGH security issues found. All three review findings (RF-1, RF-2, ADV-2) have been correctly addressed. The implementation follows established security patterns (`safe_symlink`, `validate_symlink_target`, `umask 077`, `set -euo pipefail`, `--arg` for jq). The three advisories are all LOW severity and can be addressed opportunistically.

Sprint-44 is approved for completion.
