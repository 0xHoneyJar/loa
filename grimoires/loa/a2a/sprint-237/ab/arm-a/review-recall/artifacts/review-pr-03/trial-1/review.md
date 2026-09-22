# Review: refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

## Overall Assessment

This PR is described as a simplification/refactor, but it removes load-bearing
correctness and security guards in two of the three touched files. The
`mount-submodule.sh` change silently defeats the MED-004 symlink-escape
protection for the exact call pattern used in this codebase, and the
`ledger-lib.sh` changes remove the only checks that prevented the ledger
(cycle/sprint state) from being silently wiped or corrupted on write failure.
Neither regression is covered by a new or existing test in this diff. This is
not a safe "trim ceremony" refactor — it removes functional safety nets.
Changes required.

## Critical Issues

### 1. Symlink escape validation is silently defeated (security regression)

`head/.claude/scripts/mount-submodule.sh:370-405` (`validate_symlink_target`)
dropped the `source` parameter that the base version used to resolve
relative targets:

```
base/.claude/scripts/mount-submodule.sh:373-378
  local resolve_base=""
  if [[ "$target" != /* ]]; then
    if [[ -n "$source" ]]; then
      resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
    fi
```

`ln -s TARGET LINK` resolves a relative `TARGET` relative to the directory
containing `LINK`, not relative to the caller's cwd. Every call site in this
file passes exactly such a target, e.g.
`head/.claude/scripts/mount-submodule.sh:493`:

```
safe_symlink ".claude/settings.local.json" "../$SUBMODULE_PATH/.claude/settings.local.json"
```

Here `target = "../.loa/.claude/settings.local.json"` is meant to be resolved
relative to `.claude/` (the symlink's directory) — that correctly lands on
`<repo_root>/.loa/.claude/settings.local.json`.

After this change, `validate_symlink_target` (`head/.claude/scripts/mount-submodule.sh:377-390`)
tests `[[ -e "$target" ]]` and `dirname "$target"` against the *script's cwd*
(repo root, since `create_symlinks` at `head/.claude/scripts/mount-submodule.sh:433-495`
runs with cwd = repo root). For the target above, that means checking
`../.loa/.claude/settings.local.json` and `../.loa/.claude` **one level above
the repo root** — a path that essentially never exists. That falls straight
into the `else` branch's `else` at `head/.claude/scripts/mount-submodule.sh:385-389`:

```
      warn "Cannot resolve symlink target: $target"
      return 0
```

i.e. the function returns "safe" (0) without ever computing `resolved_target`
or comparing it against `repo_root`. This happens for essentially every
legitimate symlink the script creates (all manifest targets are relative
`../…` paths meant to resolve from nested `.claude/...` directories), which
means the MED-004 boundary check is now a no-op in normal operation — the
exact regression it was written to close. A manifest entry (or future
one) with a malicious target that *does* resolve as a file relative to repo
root's parent would now also incorrectly pass, since the check compares
against the wrong base directory.

**Fix**: restore the `source` parameter and resolve_base logic from the base
version (`base/.claude/scripts/mount-submodule.sh:373-386`), and pass `$source`
from `safe_symlink` (`head/.claude/scripts/mount-submodule.sh:409-419`) as
before.

### 2. `_write_ledger` failures are now silently swallowed by every caller

`head/.claude/scripts/ledger-lib.sh:379,418,459,511,601,822` changed
`_write_ledger "$ledger_content" || return $LEDGER_ERROR` to
`_write_ledger "$ledger_content"` — the exit code is discarded. `_write_ledger`
(`head/.claude/scripts/ledger-lib.sh:145-190`) can still fail (lock timeout,
temp-file write failure, `mv` failure — see the `return 1` paths at
`head/.claude/scripts/ledger-lib.sh:158,175,182`), but callers such as
`update_sprint_status` now unconditionally `return $LEDGER_OK`
(`head/.claude/scripts/ledger-lib.sh:601-602`) even when the write failed.
Every caller of these functions (cycle creation, sprint status updates,
archival, `next_sprint_number` increments) will now believe a ledger mutation
succeeded when it may not have. This is a functional regression, independent
of the empty-content issue below — it removes error propagation entirely
from six write paths.

### 3. Removed guards allow the ledger to be overwritten with empty/corrupt content

Two guards were removed from `_write_ledger` itself
(`base/.claude/scripts/ledger-lib.sh:152-156` and `:172-177`, deleted in
`head/.claude/scripts/ledger-lib.sh:145-190`):

- The "refuse empty or unparseable content" check before writing.
- The "timestamp stamping produced empty content, aborting write" check after
  `updated_content=$(echo "$content" | jq --arg ts ... '.last_updated = $ts')`.

Combined with Issue #2, and with the additional removal of the `jq` failure
guards in `update_sprint_status`
(`base/.claude/scripts/ledger-lib.sh:602-610` — the
`|| { echo "ERROR..."; return $LEDGER_ERROR; }` blocks — deleted in
`head/.claude/scripts/ledger-lib.sh:589-599`), a `jq` failure anywhere in the
`ledger_content=$(jq ...)` pipeline now produces an empty `ledger_content`
that flows straight into `_write_ledger`, which will happily `echo "" >
tmp_file && mv tmp_file "$ledger_path"` — replacing the entire ledger file
with an (almost) empty file, and then reporting success.

This is concretely reachable: `update_sprint_status`
(`head/.claude/scripts/ledger-lib.sh:576-603`) also dropped its numeric-ID
guard (`base/.claude/scripts/ledger-lib.sh:586-590`:
`if [[ ! "$global_id" =~ ^[0-9]+$ ]]; then ... return $LEDGER_SPRINT_NOT_FOUND; fi`).
`jq --argjson id "$global_id"` (`head/.claude/scripts/ledger-lib.sh:592,596`)
requires `$global_id` to be valid JSON; a non-numeric caller argument (a bug
upstream, a bad CLI arg, an unset variable) makes `jq` error out, `jq`'s
stderr is discarded, `ledger_content` is empty, `_write_ledger` wipes the
ledger, and `update_sprint_status` returns `$LEDGER_OK`
(`head/.claude/scripts/ledger-lib.sh:601-602`) with no indication anything
went wrong.

Given the file being an atomically-managed state ledger for cycles/sprints,
silent truncation-on-error is a data-loss bug, not a style simplification.

**Fix**: restore all four guards (empty/unparseable-content refusal,
post-timestamp empty check, `jq` failure handling per branch, numeric-ID
validation) and restore `|| return $LEDGER_ERROR` on every `_write_ledger`
call site.

## Non-Critical Improvements

### 4. Undocumented behavior change in PR classification

`head/.claude/scripts/classify-pr-type.sh:63-68` removes the release-merge
rule (`from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:` → `cycle`) that existed in
`base/.claude/scripts/classify-pr-type.sh:66-69`. Release-titled PRs that
don't also carry a `cycle` label or match `\bcycle-[0-9]+\b` or the
`Run Mode|Sprint Plan|feat(sprint|feat(cycle` prefixes will now classify as
`other` (or `bugfix` if the title happens to start with `fix`) instead of
`cycle`, changing which post-merge pipeline steps run (CHANGELOG/GT/RTFM/
Release run per the docstring at `head/.claude/scripts/classify-pr-type.sh:26-28`).
Note the doc comment's "Rules" list (`head/.claude/scripts/classify-pr-type.sh:29-34`)
never listed this rule to begin with — it may have been intentionally
orphaned — but the PR description doesn't explain why this classification
should change, and there's no test asserting the new/old behavior either way.
Please confirm this is intentional (and not just "unreferenced in the
docstring therefore safe to delete") and add a regression test either way.

## Adversarial Analysis

### Concerns Identified

1. `validate_symlink_target`'s relative-path resolution now uses cwd instead
   of the symlink's directory, defeating MED-004 for the actual manifest
   entries in this script (`head/.claude/scripts/mount-submodule.sh:370-390`,
   `:493`).
2. `_write_ledger`'s return value is discarded at all six call sites, so
   write failures are invisible to callers (`head/.claude/scripts/ledger-lib.sh:379,418,459,511,601,822`).
3. Empty/unparseable ledger content can now be written to disk unchecked,
   overwriting the cycle/sprint state ledger (`head/.claude/scripts/ledger-lib.sh:145-190`).
4. `update_sprint_status` no longer validates that `global_id` is numeric
   before feeding it to `jq --argjson`, and no longer guards against the `jq`
   failure this can cause (`head/.claude/scripts/ledger-lib.sh:576-603`).
5. The release-merge PR classification rule was removed without an
   accompanying test or explanation for why the pipeline routing change is
   safe (`head/.claude/scripts/classify-pr-type.sh:63-68`).

### Assumptions Challenged

- **Assumption**: The engineer appears to have assumed these were dead or
  redundant checks ("write-guard checks" framed as pure cleanup in the PR
  title), safe to delete because they "never fire in practice."
- **Risk if wrong**: For `mount-submodule.sh`, the check *always* takes the
  degraded no-op path for normal manifest entries — it isn't a rare edge
  case, it's the common case, so the security control is effectively gone,
  not just untested. For `ledger-lib.sh`, the removed checks are exactly the
  belt-and-suspenders guards against `jq` producing empty/invalid output on
  a critical state file — the kind of check that "never fires" until a
  malformed argument or a transient `jq` hiccup causes state loss.
- **Recommendation**: Do not remove error-handling guards without tracing
  every call site's relative-path/resolution assumptions (mount-submodule.sh)
  and without keeping failure propagation intact (ledger-lib.sh). If the goal
  was genuinely to simplify, a shell test (bats) exercising a bad `jq`
  input or an out-of-bounds symlink target should have been run before and
  after to show behavior is preserved — none exists in this diff.

### Alternatives Not Considered

- **Alternative**: If the goal was to simplify `_write_ledger`'s call sites,
  the return-code check could have been kept while still shortening the
  function bodies elsewhere (e.g., a shared `_write_ledger_or_die` wrapper),
  rather than dropping `|| return $LEDGER_ERROR` at every site.
- **Tradeoff**: More code (a wrapper) vs. silently losing error propagation.
- **Verdict**: The current approach is not justified — propagating write
  failures is a correctness requirement for a lock-protected atomic-write
  function, not incidental verbosity.

## Next Steps

1. Restore the `source`-relative resolution in `validate_symlink_target` and
   re-thread `$source` through `safe_symlink` (mount-submodule.sh).
2. Restore `|| return $LEDGER_ERROR` on all six `_write_ledger` call sites.
3. Restore the empty/unparseable-content guard and post-timestamp empty guard
   inside `_write_ledger`.
4. Restore the numeric `global_id` guard and the `jq`-failure handling in
   `update_sprint_status`.
5. Either restore the release-merge classification rule or provide
   justification + a regression test for its removal.
6. Add bats coverage: a symlink-escape attempt that must still be rejected
   after this refactor, and a `_write_ledger` call with a `jq` failure that
   must still propagate an error and must not truncate the ledger file.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":3,"high":0,"medium":1,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
