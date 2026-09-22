# Review: refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

## Overall Assessment

This PR removes three independent chunks of defensive logic under a "simplification" banner: input/error guards in `_write_ledger`/`update_sprint_status`, the symlink-target resolution base in `mount-submodule.sh`, and a title-classification rule in `classify-pr-type.sh`. The ledger and classifier changes are debatable simplifications with real (if narrow) behavioral regressions. The `mount-submodule.sh` change is not a simplification — it changes *which path is validated*, and demonstrably breaks the symlink-escape check (a documented security fix, "MED-004") for at least one concrete, real call site in the same file. That alone blocks approval.

## Critical / High Issues

### 1. Symlink-escape validation now resolves relative targets against the wrong base directory — HIGH

`head/.claude/scripts/mount-submodule.sh:376-390`

```bash
validate_symlink_target() {
  local target="$1"
  ...
  if [[ -e "$target" ]]; then
    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
  else
    local parent_dir
    parent_dir=$(dirname "$target")
    if [[ -d "$parent_dir" ]]; then
      resolved_target=$(cd "$parent_dir" && pwd)/$(basename "$target")
    else
      warn "Cannot resolve symlink target: $target"
      return 0
    fi
  fi
```

The dropped `source` parameter (`head/.claude/scripts/mount-submodule.sh:414`, compare `base/.claude/scripts/mount-submodule.sh:369-395`) was doing real work: a symlink's *relative* target is resolved by the OS relative to the directory containing the symlink itself, not relative to the process's current working directory. The old code modeled that correctly — it built `resolve_base` from `dirname "$source"` and resolved `target` against it before testing existence/bounds. The new code tests `-e "$target"` / `dirname "$target"` as-is, which bash evaluates relative to the script's cwd (repo root) regardless of where the symlink actually lives.

This isn't hypothetical — the very next call site proves it:

`head/.claude/scripts/mount-submodule.sh:492-494`
```bash
if [[ -f "$SUBMODULE_PATH/.claude/settings.local.json" ]]; then
    safe_symlink ".claude/settings.local.json" "../$SUBMODULE_PATH/.claude/settings.local.json"
```

Here `target = "../$SUBMODULE_PATH/.claude/settings.local.json"`. Resolved correctly (relative to `.claude/`, the symlink's own directory — matching how `ln -s` will actually be interpreted at runtime), this lands inside the repo at `$SUBMODULE_PATH/.claude/settings.local.json`. Resolved against cwd (repo root, per the new code), `-e "../$SUBMODULE_PATH/..."` and `dirname` both point *above* the repo root — a path that will not exist — so the function falls into the `else` branch, `[[ -d "$parent_dir" ]]` also fails, and the function hits `warn "Cannot resolve symlink target..."; return 0`. The bounds check is skipped entirely (treated as "allow but warn") for a real, legitimate symlink created by this same script. The security check this function exists to perform (see its own docstring, "Returns: 0 if safe, 1 if escapes bounds", and the "MED-004 FIX" comment at line 358/453) is now bypassed rather than enforced for exactly the case it should be validating.

Confirming this isn't a one-off: the file's *other*, untouched symlink-resolution logic (`head/.claude/scripts/mount-submodule.sh:869-871`) still does `cd "$(dirname "$full_link")" && resolve_path_portable "$target"` — i.e. resolves relative to the link's own directory, the same thing the removed `source` parameter used to do. The new `validate_symlink_target` is now inconsistent with the rest of the file's own model of symlink semantics.

**Fix**: restore the `source` parameter and resolve relative targets against `dirname "$source"`, not cwd.

## Medium Issues

### 2. `update_sprint_status` lost its input validation, and `_write_ledger` lost its content guards — MEDIUM

`head/.claude/scripts/ledger-lib.sh:576-603` (compare `base/.claude/scripts/ledger-lib.sh:585-612`)

The numeric-ID guard was removed outright, not just its error-handling wrapper:
```bash
-    if [[ ! "$global_id" =~ ^[0-9]+$ ]]; then
-        echo "ERROR: update_sprint_status requires a numeric global sprint id (got '$global_id')" >&2
-        return $LEDGER_SPRINT_NOT_FOUND
-    fi
```
If a caller ever passes a non-numeric `global_id`, `jq --argjson id "$global_id"` (`head/.claude/scripts/ledger-lib.sh:592,596`) now fails with jq's own generic error instead of the specific, actionable `LEDGER_SPRINT_NOT_FOUND` message. Combined with the removal of `_write_ledger`'s guards (`head/.claude/scripts/ledger-lib.sh:149-155`, `head/.claude/scripts/ledger-lib.sh:167-172` in the base version) — "refusing to write empty or unparseable ledger content" and "timestamp stamping produced empty content" — the only thing standing between malformed input and a corrupted/aborted write is implicit `set -euo pipefail` propagation through a chain of plain command-substitution assignments (`ledger_content=$(jq ...)`, `updated_content=$(echo "$content" | jq ...)`).

That's a fragile substitute for explicit checks: `set -e` is silently suspended the moment any of these functions are invoked inside a condition (`if create_cycle ...; then`), inside `&&`/`||`, or as part of a command substitution one level further out (`id=$(create_cycle ...)` — a pattern every one of these functions uses via `echo "$cycle_id"` at the end). Every call site of `_write_ledger`'s callers lost its explicit `|| return $LEDGER_ERROR` (`head/.claude/scripts/ledger-lib.sh:379,418,459,511,601,822`), so the distinction between "wrote successfully," "lock timeout," and "malformed content" collapses into "the whole process died somewhere, with whatever bash/jq happened to print."

This file is explicitly flagged as security-relevant in its own comments ("SECURITY (HIGH-001): Atomic write via temp file + mv", `head/.claude/scripts/ledger-lib.sh:167`). Removing the input-shape guards here isn't unreasonable if the goal is trusting `set -e` end-to-end, but that needs to be a deliberate, verified decision (e.g. a test that a non-numeric `global_id` still aborts loudly and doesn't leave the ledger in a partial state), not an implicit side effect of deleting the explicit checks.

**Ask**: either restore the `update_sprint_status` numeric-ID guard and the two `_write_ledger` content guards, or show (via test) that every call site correctly surfaces and handles the resulting hard-exit.

### 3. Release-branch PRs silently drop out of "cycle" classification, with no stated reason — MEDIUM

`head/.claude/scripts/classify-pr-type.sh:63` (removed hunk, was `base/.claude/scripts/classify-pr-type.sh:66-70`)

```bash
-    if echo "$title" | grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"; then
-        echo "cycle"
-        return 0
-    fi
```

Per the file's own docstring, `cycle` classification drives "CHANGELOG, GT, RTFM, Release run" — the full post-merge pipeline (`head/.claude/scripts/classify-pr-type.sh:26`). Titles like `Merge branch 'release/1.4.0' into main` or `Release(v1.4.0): ...` will now fall through to `bugfix`/`other` and get routed to the lighter "tag only" path instead. The PR description states this was removed but gives no rationale (obsolete pattern? no longer produced by the release tooling? false-positive source?), and no test file is included in the diff to show the removal is safe. Unlike the `feat:` bare-prefix exclusion (which has an explicit NOTE justifying it at `head/.claude/scripts/classify-pr-type.sh:37-40`), this removal has no equivalent explanation.

**Ask**: state why release-branch merges no longer need "cycle" routing, or restore the rule.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/scripts/mount-submodule.sh:376-390` — symlink-escape check now validates the wrong path and demonstrably self-bypasses for a real call site (`:492-494`). See Critical Issue 1.
2. `head/.claude/scripts/ledger-lib.sh:576-603` — loss of explicit input validation shifts correctness onto implicit `set -e` propagation, which several of this file's own call patterns (command substitution, `echo` of a return value) can silently defeat. See Medium Issue 2.
3. `head/.claude/scripts/classify-pr-type.sh:63` — undocumented removal of a routing rule with a stated purpose ("cycle" = full release pipeline), no replacement rationale, no test evidence. See Medium Issue 3.
4. None of the three changes touch or add tests in this diff — for a PR that removes three separate safety/validation code paths, there's no evidence any of the removed behavior was actually exercised by tests before deletion (i.e. we can't tell if this was "dead code cleanup" or "regression").

### Assumptions Challenged
- **Assumption**: the engineer appears to have assumed `dirname "$target"`/`[[ -e "$target" ]]` in `validate_symlink_target` behave the same whether or not `target` is prefixed with a resolution base — i.e. that dropping the `source`-relative prefix is a pure simplification.
- **Risk if wrong**: as shown, it isn't — the function validates a different filesystem location than the one the symlink will actually resolve to at runtime, defeating the security check for any relative target where cwd ≠ the symlink's own directory (true for every nested symlink under `.claude/skills/*`, `.claude/commands/*`, etc., and for the explicit `settings.local.json` case).
- **Recommendation**: restore `source`-relative resolution; add a regression test that calls `validate_symlink_target` with a relative target from a non-repo-root cwd and asserts it still resolves/bounds-checks correctly.

### Alternatives Not Considered
- **Alternative**: if the goal was genuinely to simplify `_write_ledger`'s error handling, a cleaner path would have been keeping the guards but collapsing the *return-code plumbing* at call sites (e.g. a shared `_write_ledger_or_die` wrapper), rather than deleting both the guards and the explicit propagation and leaning on `set -e` alone.
- **Tradeoff**: the chosen approach saves ~20 lines total across three files but trades away explicit, testable failure modes for implicit ones that depend on invocation context (conditionals, command substitution) the reader can't see at the call site.
- **Verdict**: for the ledger file, this is a judgment call and non-blocking if deliberate; for the symlink validator, the "simplification" isn't equivalent behavior at all and should be reverted rather than reconsidered.

## Next Steps

1. Restore `source`-relative resolution in `validate_symlink_target` (Critical Issue 1) — blocking.
2. Either restore the removed guards in `ledger-lib.sh` or add tests demonstrating the `set -e`-only behavior is safe across all call sites (Medium Issue 2).
3. State the rationale for dropping the release-merge classification rule, or restore it (Medium Issue 3).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
