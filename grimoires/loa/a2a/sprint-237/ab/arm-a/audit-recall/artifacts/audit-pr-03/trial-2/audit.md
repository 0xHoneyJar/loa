# Security Audit Report — refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present)
**Scope**: `head.diff` — 3 files: `.claude/scripts/ledger-lib.sh`, `.claude/scripts/mount-submodule.sh`, `.claude/scripts/classify-pr-type.sh`
**Auditor**: auditing-security skill

## Executive Summary

This PR frames itself as a simplification ("trim write-guard checks, symlink resolution and PR classification") but it removes three independent, explicitly-labeled defensive controls (two tagged `SECURITY (HIGH-001)` / `SECURITY (MED-004 FIX)` in the source itself) without replacing their guarantees. The most severe change guts input/output validation in `_write_ledger()` — the sole write path for the framework's cycle/sprint state file — **and simultaneously removes every caller's error-propagation check**, so a single malformed write can silently truncate `ledger.json` to an empty/invalid file while every call site reports success. The second change alters `validate_symlink_target()`'s path-resolution base from the symlink's own directory to the process's current working directory, which is *not* how the OS resolves relative symlink targets — this can cause the "escapes repository bounds" boundary check introduced by MED-004 to validate against the wrong path, silently defeating its own purpose. The third change (release-merge PR misclassification) is a process/routing regression, not an exploitable vulnerability, and is reported for completeness.

**Overall Risk Level: HIGH**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## Findings

### [HIGH-1] `_write_ledger` content/JSON validation removed, and every caller now ignores its return code — silent corruption of ledger.json

**Component**: `head/.claude/scripts/ledger-lib.sh:146-194` (function), with error-propagation removed at call sites `head/.claude/scripts/ledger-lib.sh:379`, `:418`, `:451` (`allocate_sprint_number`), `:497` (approx., `add_sprint_to_cycle`), `:601`, `:820` (approx., `archive_cycle`)

**Description**: The base version guarded `_write_ledger()` with two checks that the diff deletes:

```bash
# removed, was at base .claude/scripts/ledger-lib.sh:152-156
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
    echo "ERROR: refusing to write empty or unparseable ledger content" >&2
    return $LEDGER_ERROR
fi
```

and, after the timestamp-stamping step:

```bash
# removed, was at base .claude/scripts/ledger-lib.sh:180-185
if [[ -z "$updated_content" ]]; then
    echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
    flock -u 9
    exec 9>&-
    return $LEDGER_ERROR
fi
```

In `head/.claude/scripts/ledger-lib.sh:146-194`, `_write_ledger()` no longer validates `$content` before writing and no longer checks whether the `jq --arg ts ... '.last_updated = $ts'` step (`head/.claude/scripts/ledger-lib.sh:168-169`) actually produced JSON. If the caller's `jq` pipeline upstream fails and yields an empty string — which happens whenever a `jq --argjson`/`--arg` filter receives malformed input, e.g. a non-numeric ID passed to `--argjson` (see HIGH-2 below for a concrete trigger) — `content` is `""`. `echo "" | jq --arg ts ... '.last_updated = $ts'` (`head/.claude/scripts/ledger-lib.sh:169`) then also fails and produces `""`. Nothing in the function detects this: `echo "$updated_content" > "$tmp_file"` (`head/.claude/scripts/ledger-lib.sh:173`) still succeeds (echoing an empty string to a file is a successful write), and `mv "$tmp_file" "$ledger_path"` (`head/.claude/scripts/ledger-lib.sh:182`) still succeeds. The function returns `0` (success) after having overwritten the entire ledger with an empty file.

Compounding this, the diff also strips `|| return $LEDGER_ERROR` from every call site that invokes `_write_ledger`, e.g.:

```
# head/.claude/scripts/ledger-lib.sh:379
_write_ledger "$ledger_content"
echo "$cycle_id"
return $LEDGER_OK
```
(previously `_write_ledger "$ledger_content" || return $LEDGER_ERROR`). This pattern repeats at `head/.claude/scripts/ledger-lib.sh:418`, `:451`, `head/.claude/scripts/ledger-lib.sh:601` (`update_sprint_status`), and the two remaining sites shown in the diff (archive/cycle completion path). Even in the cases where `_write_ledger` still legitimately fails (e.g. `flock` lock-timeout at `head/.claude/scripts/ledger-lib.sh:158-162`, or the temp-file write/move failures at `:173-179`/`:182-188`, which still `return 1` on their own), the caller no longer checks that return value and unconditionally returns `$LEDGER_OK`. This means lock contention, disk-full, or any other genuine write failure is now silently reported as success to every downstream consumer of this library.

**Impact**: The ledger (`ledger.json`) is the framework's authoritative cycle/sprint state file (per `.loa/CLAUDE.loa.md`'s Beads-First/state-zone model, this is core Loa state). A single malformed write — reachable today via `update_sprint_status` with a non-numeric ID (HIGH-2) — silently truncates it to an empty/invalid JSON document, corrupting the tracked history of all cycles and sprints, while the calling code path believes the operation succeeded (`return $LEDGER_OK`). A pre-write backup (`ensure_ledger_backup`, `head/.claude/scripts/ledger-lib.sh:165`) provides a recovery path, but nothing signals that recovery is needed — the corruption is invisible until a later `jq` read against the now-empty file fails, potentially far from the original cause.

**Remediation**: Restore both validation guards in `_write_ledger()` (empty/unparseable `$content` on entry, and empty `$updated_content` after the timestamp-stamp step), and restore `|| return $LEDGER_ERROR` (or equivalent explicit `if ! _write_ledger ...; then return $LEDGER_ERROR; fi`) at every call site. If the goal was genuinely to simplify, at minimum keep the guards — they are the only thing standing between a jq failure and silent state-file destruction.

**References**: CWE-20 (Improper Input Validation), CWE-252 (Unchecked Return Value), CWE-460 (Improper Cleanup on Thrown Exception class — error state discarded)

---

### [HIGH-2] `validate_symlink_target` now resolves relative targets against the wrong base directory, defeating the repo-boundary check it exists to enforce

**Component**: `head/.claude/scripts/mount-submodule.sh:370-405` (`validate_symlink_target`), caller `head/.claude/scripts/mount-submodule.sh:409-419` (`safe_symlink`)

**Description**: This function is explicitly labeled `# === MED-004 FIX: Symlink Target Validation ===` (`head/.claude/scripts/mount-submodule.sh:359`) — i.e. it is a previously-landed security fix. The base version accepted a second argument, `source` (the path of the symlink being created), and used it to compute `resolve_base` for relative targets:

```bash
# base .claude/scripts/mount-submodule.sh (validate_symlink_target)
local resolve_base=""
if [[ "$target" != /* ]]; then
  if [[ -n "$source" ]]; then
    resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
  fi
  ...
fi
local candidate
if [[ "$target" = /* ]]; then
  candidate="$target"
else
  candidate="$resolve_base/$target"
fi
```

This matches actual filesystem symlink semantics: when a relative symlink target is dereferenced by the OS, it is resolved **relative to the directory containing the symlink**, not relative to whatever directory the creating process happened to have as its CWD.

The new code (`head/.claude/scripts/mount-submodule.sh:370-390`) drops the `source` parameter entirely and resolves `$target` directly against the process's current working directory via `[[ -e "$target" ]]` / `cd "$(dirname "$target")" && pwd`:

```bash
validate_symlink_target() {
  local target="$1"
  ...
  if [[ -e "$target" ]]; then
    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
  else
    ...
  fi
```

`safe_symlink()` at `head/.claude/scripts/mount-submodule.sh:409-419` still creates the symlink as `ln -sf "$target" "$source"` where `$source` is typically a nested path under `.claude/` (e.g. `.claude/skills`) and `$target` is a relative path such as `../.loa/skills`, designed to resolve correctly *once the symlink is dereferenced from inside `.claude/`*. Validating that same relative target against the CWD (repo root, one directory level shallower than the symlink's real location) computes a materially different `resolved_target` than the one the OS will actually use at dereference time. Concretely, for `source=".claude/skills"`, `target="../.loa/skills"`:

- **Correct resolution** (relative to `dirname(source)` = `.claude`): `repo_root/.claude/../.loa/skills` → `repo_root/.loa/skills` (inside the repo — the intended, safe result).
- **New code's resolution** (relative to CWD = `repo_root`): `repo_root/../.loa/skills` → parent-of-repo-root — i.e. the check now validates a path that does not correspond to what will actually be dereferenced.

Because the check now validates the wrong candidate path, it can diverge from the real filesystem behavior in either direction depending on how many `..` segments a target uses and how deep the actual symlink source sits: a target that legitimately stays inside the repo when resolved from its true (deeper) location can be miscomputed as escaping (functional breakage), and — the security-relevant direction — a target crafted with a traversal depth calibrated to escape from a deep `source` path can be miscomputed as staying inside the repo when checked against the shallower CWD base, because fewer `..` segments are needed to leave a shallower root. Either way, the repo-boundary check at `head/.claude/scripts/mount-submodule.sh:397-402` is no longer validating the path that will actually be created.

**Impact**: This is a regression of a previously-fixed symlink path-traversal control (MED-004). The check can no longer be trusted to certify that a relative symlink target stays within repository bounds, because it resolves against a base directory that does not match how the OS resolves the symlink it is validating.

**Remediation**: Restore the `source` parameter and `resolve_base` logic so relative targets are resolved against `dirname(source)`, matching real symlink semantics, before the repo-boundary comparison.

**References**: CWE-22 (Path Traversal), CWE-706 (Use of Incorrect Resolution)

---

### [MEDIUM-1] Release-merge PR classification removed — cycle pipeline no longer triggered for release-merge PRs

**Component**: `head/.claude/scripts/classify-pr-type.sh:42-72` (`classify_pr_type`)

**Description**: The base version special-cased release-merge PR titles ahead of the generic fallback:

```bash
# removed, base .claude/scripts/classify-pr-type.sh (before line 66's "^fix" check)
if echo "$title" | grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"; then
    echo "cycle"
    return 0
fi
```

With this removed, a PR titled e.g. `Release: merge from origin/release/2.0` or `merge from origin/release/2.0` no longer matches any of the remaining rules in `head/.claude/scripts/classify-pr-type.sh:46-71` (label check, `\bcycle-[0-9]+\b`, `^(Run Mode|Sprint Plan|feat\(sprint|feat\(cycle)`, `^fix`) and falls through to `echo "other"` at `head/.claude/scripts/classify-pr-type.sh:71`.

**Impact**: Per the file's own docstring (`head/.claude/scripts/classify-pr-type.sh:26`), `cycle` classification is what drives the full post-merge pipeline (CHANGELOG, GT, RTFM, Release run). Release-merge PRs downgraded to `other` will skip that pipeline. This is a process/automation-correctness regression rather than a directly exploitable vulnerability, but it silently weakens the post-merge automation's coverage guarantee documented at the top of this same file.

**Remediation**: Restore the release-merge title pattern as a `cycle`-classifying rule, or confirm via the PR author/tests that release-merge PRs are intentionally meant to route through the `other`/bugfix path now (in which case, update the file's docstring, which still claims `cycle` drives "Release run").

**References**: CWE-696 (Incorrect Behavior Order) — advisory, not a direct exploit path.

## Security Checklist Status

- [ ] Input validation at all internal trust boundaries — **FAILED** (HIGH-1: `_write_ledger` content validation removed)
- [ ] Error handling does not silently discard failure state — **FAILED** (HIGH-1: callers ignore `_write_ledger` return code)
- [ ] Path/traversal validation resolves against the correct reference point — **FAILED** (HIGH-2: `validate_symlink_target` uses CWD instead of symlink source directory)
- [ ] Automation routing logic covers previously-handled cases — **FAILED** (MEDIUM-1: release-merge classification dropped)
- [x] No secrets or credentials introduced
- [x] Atomic write pattern (temp file + `mv`) and `flock`-based locking in `_write_ledger` itself remain intact

## Verdict

**CHANGES_REQUIRED**

Two HIGH findings — silent ledger corruption with swallowed errors, and a regressed path-traversal validation control — must be fixed before this PR merges. The MEDIUM finding (PR classification) should be resolved or explicitly justified.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"ad-hoc-pr-audit","ts":"2026-09-21T00:00:00Z"} -->
