# Security Audit Report — refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

**Audit date:** 2026-09-21
**Auditor:** Paranoid Cypherpunk Auditor (auditing-security skill)
**Scope:** `head.diff` touching `.claude/scripts/ledger-lib.sh`, `.claude/scripts/mount-submodule.sh`, `.claude/scripts/classify-pr-type.sh`

## Executive Summary

This PR bills itself as a simplification ("trim write-guard checks, symlink resolution and PR classification") but the diff removes a working repository-boundary security control in `mount-submodule.sh`, silently breaks the documented error-return contract of the ledger's atomic-write primitive in `ledger-lib.sh` (with corresponding loss of input validation), and drops a PR-classification rule with no replacement or explanation beyond the title.

The most serious problem is in `validate_symlink_target()` (`mount-submodule.sh`): the function used to resolve relative symlink targets against the directory that will contain the symlink (mirroring how the OS actually resolves a relative symlink target at dereference time). The refactor deletes that `source`-relative resolution and resolves relative targets against the process's current working directory instead. For the manifest-driven relative targets this script actually creates (e.g. `../.loa/.claude/scripts` from `.claude/scripts`), this either produces a wrong "cannot resolve" verdict that silently *allows* the symlink unchecked, or resolves to the wrong absolute path — in both cases the boundary check this function exists to perform (labeled `MED-004 FIX: Symlink Target Validation` in the same file) no longer reliably fires. This is a regression of a previously-fixed vulnerability class (symlink escape past `repo_root`).

The second serious problem is in `ledger-lib.sh`: six call sites that used to do `_write_ledger "$content" || return $LEDGER_ERROR` now call `_write_ledger "$content"` with no error check at all, even though `_write_ledger`'s own doc comment still promises "Returns: 0 on success, 1 on lock failure." Combined with the removal of the empty/unparseable-content guard inside `_write_ledger` itself, a failed ledger write (lock timeout, `mv` failure, malformed JSON) can now either be silently reported as success by the calling function or crash the whole (sourced, `set -euo pipefail`) process uncontrolled, depending on the caller's context — neither of which is the documented behavior.

## Overall Risk Level: **HIGH**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 1 |
| Medium | 2 |
| Low | 1 |

## Critical Issues

### C-1: Symlink boundary validation resolves relative targets against the wrong base directory, defeating the repo-escape check

- **Component:** `head/.claude/scripts/mount-submodule.sh:370-405` (`validate_symlink_target`), call site `head/.claude/scripts/mount-submodule.sh:414` (`safe_symlink`)
- **CWE:** CWE-59 (Improper Link Resolution Before File Access), CWE-668 (Exposure of Resource to Wrong Sphere)

**Before (base), `validate_symlink_target` took the symlink's own path as a second argument and used `dirname "$source"` as the base for resolving a relative `target`:**

```
local resolve_base=""
if [[ "$target" != /* ]]; then
    if [[ -n "$source" ]]; then
      resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
    fi
    ...
candidate="$resolve_base/$target"
```

This mirrors how the kernel actually resolves a relative symlink target: relative to the directory *containing* the symlink, never relative to whatever directory happened to be the shell's `$PWD` when the link was created.

**After (head), the `source` parameter is gone entirely** (`head/.claude/scripts/mount-submodule.sh:370-371`):

```
validate_symlink_target() {
  local target="$1"
  local repo_root
  repo_root=$(get_repo_root)

  # Resolve the target to an absolute path
  local resolved_target
  if [[ -e "$target" ]]; then
    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
  else
    local parent_dir
    parent_dir=$(dirname "$target")
    if [[ -d "$parent_dir" ]]; then
      resolved_target=$(cd "$parent_dir" && pwd)/$(basename "$target")
    else
      # Cannot resolve, allow but warn
      warn "Cannot resolve symlink target: $target"
      return 0
    fi
  fi
```

and the call site at `head/.claude/scripts/mount-submodule.sh:414` stopped passing it:

```
if ! validate_symlink_target "$target"; then
```

`$target` here is a relative string such as `../.loa/.claude/scripts` (the manifest expresses targets relative to the symlink's own directory, e.g. for link `.claude/scripts`). `create_symlinks()` runs with `$PWD` at the repository root, so:

- `[[ -e "$target" ]]` tests `repo_root/../.loa/.claude/scripts` — one directory level too high — which does not exist.
- The fallback then tests `parent_dir="../.loa/.claude"` for `-d`, again relative to `repo_root` instead of relative to `.claude/`, which also does not exist.
- The function hits the `else` branch and returns `0` ("Cannot resolve … allow but warn") — **the exact call sites the check exists to protect now pass through unchecked**, because the base directory used to resolve `..`-relative targets no longer matches the directory the symlink will actually live in.

**Impact / PoC:** Any manifest entry or attacker-influenced entry (e.g. a poisoned `symlink-manifest.sh`, or future code path that lets a target come from less-trusted input) whose relative target is crafted to escape `repo_root` (e.g. `../../../../etc/cron.d/evil`) is no longer reliably rejected — the resolution logic computes the wrong candidate path relative to `$PWD` rather than the symlink's real location, so the boundary comparison at `head/.claude/scripts/mount-submodule.sh:397` (`if [[ "$resolved_target" != "$repo_root"* ]]`) is compared against a path that does not reflect where the symlink will actually resolve at dereference time. Depending on nesting depth this can both false-negative (unsafely allow an escaping target) and false-positive (block a legitimate in-repo target), but the security-relevant failure mode is the false negative: the check silently degrades to "cannot resolve, allow" for the common case, which is worse than doing no normalization at all because it looks like validation is still happening.

**Remediation:** Restore the `source` parameter to `validate_symlink_target` and pass it through from `safe_symlink` (`head/.claude/scripts/mount-submodule.sh:409-419`), and resolve relative targets against `dirname "$source"`, not `$PWD`/`dirname "$target"`. Add a regression test that calls `safe_symlink` for a nested link path (e.g. `.claude/skills/foo/SKILL.md`) with a `../../.loa/...` target from a `$PWD` that is *not* the link's parent directory, asserting the function still resolves correctly and still rejects `../../../etc/passwd`-style escapes.

## High Issues

### H-1: Removing `|| return $LEDGER_ERROR` at six `_write_ledger` call sites breaks the function's documented error contract, allowing failed writes to be silently reported as success or to crash the process uncontrolled

- **Component:** `head/.claude/scripts/ledger-lib.sh:379` (`create_cycle`), `:418` (`update_cycle_field`), `:459` (`allocate_sprint_number`), `:511` (`add_sprint`), `:601` (`update_sprint_status`), `:822` (`archive_cycle`)
- **CWE:** CWE-252 (Unchecked Return Value), CWE-703 (Improper Check or Handling of Exceptional Conditions)

`_write_ledger`'s own doc comment (unchanged by this PR) still states the contract plainly:

```
144: # Write ledger JSON with exclusive locking (internal use)
145: # Args: $1 - JSON content
146: # Returns: 0 on success, 1 on lock failure
```

and `_write_ledger` still returns `1` on lock-acquire timeout (`head/.claude/scripts/ledger-lib.sh:158-162`) and on `mv` failure (`head/.claude/scripts/ledger-lib.sh:182-188`). Every one of its six callers used to check that return value:

```
-    _write_ledger "$ledger_content" || return $LEDGER_ERROR
+    _write_ledger "$ledger_content"
```

repeated identically at lines 379, 418, 459, 511, 601 and 822 in the head file. None of these call sites now check `_write_ledger`'s exit status at all — there is no replacement guard, `if`, or `$?` check.

**Impact:** The file is sourced (not executed as a subshell) under `set -euo pipefail` (`head/.claude/scripts/ledger-lib.sh:14`). Whether a failing `_write_ledger` now aborts the whole calling process via `errexit`, or is silently swallowed, depends entirely on the calling context (e.g. whether the function is itself invoked inside `$(...)`, an `if`, or an `&&`/`||` chain elsewhere in the codebase) — both outcomes are worse than the removed code:
- In an errexit-suspended calling context (e.g. `if create_cycle "$label"; then …` or `sprint_id=$(add_sprint "$label")`), a lock timeout or failed `mv` no longer returns `$LEDGER_ERROR` to the caller — execution falls through to `echo "$cycle_id"` / `return $LEDGER_OK` regardless, so a caller that checks the function's own return code for success/failure is told the write succeeded when it did not. For `archive_cycle` (`:822`) specifically, this means a cycle can be marked `archived` in the caller's mental model (and files already copied to the archive directory at `:794-811`) while the ledger update that was supposed to record that fact never actually landed.
- In a normal (errexit-active) context, the process now dies mid-function with no chance for any caller-side cleanup/rollback that used to run after `return $LEDGER_ERROR` — the previous code gave callers a controlled failure signal; the new code gives them either nothing or a crash.

Either way, the function's own documented contract ("Returns: 0 on success, 1 on lock failure") is now false for all six public entry points that wrap it.

**Remediation:** Restore `|| return $LEDGER_ERROR` (or equivalent explicit `if ! _write_ledger ...; then return $LEDGER_ERROR; fi`) at all six call sites. If the goal was to simplify, do it by having `_write_ledger` itself distinguish real failures from the removed validation, not by deleting the caller-side check entirely.

## Medium Issues

### M-1: `_write_ledger` no longer validates that `content` is non-empty, parseable JSON before writing

- **Component:** `head/.claude/scripts/ledger-lib.sh:146-194` (`_write_ledger`)
- **CWE:** CWE-20 (Improper Input Validation)

The base version guarded the top of `_write_ledger` with:

```
if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
    echo "ERROR: refusing to write empty or unparseable ledger content" >&2
    return $LEDGER_ERROR
fi
```

and guarded the post-timestamp step with:

```
if [[ -z "$updated_content" ]]; then
    echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
    flock -u 9
    exec 9>&-
    return $LEDGER_ERROR
fi
```

Both are gone from `head/.claude/scripts/ledger-lib.sh:146-194`. The function now proceeds straight from acquiring the flock (`:157-162`) and taking a backup (`:165`) into `updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')` (`:169`) with no check that `$content` is even JSON. In practice `jq`'s own failure plus `pipefail`/`errexit` will usually abort the process if `$content` is truly unparseable, but that is now an *incidental* side effect of shell option flags rather than an intentional, documented guard — and it happens **after** the lock has been taken and the backup copy already made, instead of failing fast before touching either. The clear, actionable `ERROR: refusing to write empty or unparseable ledger content` diagnostic is also gone, replaced by whatever raw `jq: error (at <stdin>:0): ...` text reaches stderr.

**Remediation:** Restore both guards. They cost nothing at the call sites that already produce valid content, and they are the only thing standing between a caller bug (e.g. a `jq` filter upstream that silently produces `null`/empty output) and either a corrupted `ledger.json` or an unhelpful crash deep inside the locking section.

### M-2: `update_sprint_status` no longer validates that `global_id` is numeric before using it in `jq --argjson`

- **Component:** `head/.claude/scripts/ledger-lib.sh:576-603` (`update_sprint_status`)
- **CWE:** CWE-20 (Improper Input Validation)

The base version rejected non-numeric input up front:

```
if [[ ! "$global_id" =~ ^[0-9]+$ ]]; then
    echo "ERROR: update_sprint_status requires a numeric global sprint id (got '$global_id')" >&2
    return $LEDGER_SPRINT_NOT_FOUND
fi
```

This check is absent from the head function (`head/.claude/scripts/ledger-lib.sh:576-603`). `global_id` now flows unchecked into `jq --argjson id "$global_id" ...` at `:592` and `:596`. `--argjson` requires its argument to be a JSON value; a non-numeric `global_id` (e.g. an empty string, or a caller passing a `sprint-N` label instead of the resolved global id) makes `jq` itself fail with an opaque `Invalid JSON text passed to --argjson` instead of the previous clear `ERROR: update_sprint_status requires a numeric global sprint id`, and — per H-1 — that failure is no longer guaranteed to propagate a `$LEDGER_ERROR`-style code back to the caller either, since the surrounding `|| { ...; return $LEDGER_ERROR; }` wrappers around the two `jq` calls (`:592-595`, `:596-599` in head) were also deleted (base had them at the equivalent lines).

**Remediation:** Restore the numeric-id guard at function entry, and restore explicit error handling around the two `jq` assignments.

## Low Issues

### L-1: Removing the release-merge classification rule silently changes post-merge pipeline routing with no replacement

- **Component:** `head/.claude/scripts/classify-pr-type.sh:42-72` (`classify_pr_type`)
- **CWE:** N/A (functional regression, not a security defect)

The base version classified release-merge titles as `cycle` (triggering the full post-merge pipeline: CHANGELOG, GT, RTFM, Release run):

```
if echo "$title" | grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"; then
    echo "cycle"
    return 0
fi
```

This block sat between the `cycle-NNN`/prefix checks (head `:56-64`) and the `^fix` bugfix check (head `:66-69`), and is now gone entirely from `head/.claude/scripts/classify-pr-type.sh`. A PR titled e.g. `Merge from origin/release/1.2 into main` or `Release: v1.2.0`, which used to classify as `cycle`, now falls through every remaining rule and classifies as `other` (`head/.claude/scripts/classify-pr-type.sh:71`) — the same bucket as an unrelated one-off PR. The file's own header comment (`:5-11`, `:30-36`) documents this classifier as "the single source of truth" for post-merge routing precisely because drift here previously caused silent pipeline misrouting (Issue #550); this change reintroduces exactly that class of drift for the release-merge case, with nothing in the PR description explaining why release-merge PRs should no longer be treated as `cycle`.

**Remediation:** Either restore the removed rule, or if release-merge PRs are meant to be routed differently now, say so explicitly in the PR description and add/update the file's rule-precedence comment (`:30-36`) and a corresponding test case, so the next reader doesn't have to diff against `base/` to discover the behavior changed.

## Security Checklist Status

- [ ] Path/symlink boundary checks resolve against the correct base directory — **FAILED (C-1)**
- [ ] Internal write primitives honor their documented return-value contract — **FAILED (H-1)**
- [ ] Input validation present at all documented trust-boundary guards — **FAILED (M-1, M-2)**
- [ ] Behavioral changes to shared classifiers are justified/tested — **FAILED (L-1)**
- [x] No secrets, credentials, or hardcoded keys introduced
- [x] No new injection sinks (`eval`, unsanitized `jq` filter strings, unsanitized SQL) introduced
- [x] `umask`/temp-file handling in `mount-submodule.sh` unchanged and still sane

## Threat Model Summary

The realistic attacker model for `mount-submodule.sh` is a malicious or compromised `symlink-manifest.sh` / `.loa-version.json` / submodule content (supply-chain on the Loa framework submodule itself, or a crafted PR to a fork) attempting to have `create_symlinks()` place a symlink that points outside the consuming repository (e.g. into `/etc`, a CI secrets mount, or a sibling project). `validate_symlink_target` is the only control standing between that input and `ln -sf`; C-1 shows it no longer reliably enforces the boundary for the relative-target case that is the script's normal operating mode. The ledger issues (H-1, M-1, M-2) are lower-exposure (no external attacker input crosses this boundary in the diff as reviewed) but represent real availability/integrity regressions in the framework's own state-tracking primitive.

## Recommendations

- **Immediate (24h):** Fix C-1 (restore source-relative resolution in `validate_symlink_target`) before this PR merges — it silently reintroduces a previously-fixed vulnerability class.
- **Short-term (1wk):** Restore the six `|| return $LEDGER_ERROR` checks (H-1) and the two `_write_ledger` content guards (M-1); add the numeric `global_id` guard back to `update_sprint_status` (M-2). Add regression tests asserting `_write_ledger`'s callers actually return `$LEDGER_ERROR` on a forced lock-timeout/mv-failure.
- **Long-term (1mo):** Add a bats test for `validate_symlink_target`/`safe_symlink` covering nested link paths invoked from a `$PWD` other than the repo root, so this class of regression is caught mechanically rather than by manual audit. Decide and document the intended classification for release-merge PRs (L-1) and add a corresponding fixture to whatever test suite covers `classify_pr_type`.

## Verdict

**CHANGES_REQUIRED**

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":2,"low":1},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
