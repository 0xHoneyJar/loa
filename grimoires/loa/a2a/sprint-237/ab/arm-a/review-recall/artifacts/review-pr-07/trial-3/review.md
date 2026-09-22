# Review: chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection

## Overall Assessment

Three independent hardening/refactor changes bundled into one PR. Two of the three (the `block-destructive-bash.sh` hidden-dir allowlist and the `symlink-manifest.sh` traversal rejection) are well-reasoned, conservative, and verified safe by tracing the regex/glob logic by hand. The third (`constructs-lib.sh` `find_local_source`) removes the only check that ties the returned path back to the requested slug, and I believe this is a real correctness/integrity bug, not just a simplification — see Critical Issues.

## Critical Issues

### 1. `find_local_source` no longer verifies the returned path matches the requested slug

`head/.claude/scripts/constructs-lib.sh:565-597`

```
find_local_source() {
    local slug="$1"
    ...
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}
```

The removed `_local_source_matches_slug` helper (base/.claude/scripts/constructs-lib.sh:591-614) was the *only* thing that connected the `$slug` argument to the returned path — it checked the directory basename (`construct-$slug` / `$slug`) or the declared name inside `construct.yaml`/`manifest.json` against `$slug`. After this change the function's contract ("Find local source clone for a construct pack" / "Args: $1 = pack slug", `head/.claude/scripts/constructs-lib.sh:561-563`) is no longer honored: it returns the *first* directory in `search_paths` that merely looks like *some* construct (has a `construct.yaml` or `manifest.json`), regardless of whether it is the construct identified by `$slug`.

This is most dangerous for the configured path (`head/.claude/scripts/constructs-lib.sh:571`, `.constructs.local_source_paths[]` from `.loa.config.yaml`), which is documented/implemented as a flat list of candidate checkout directories, not one path per slug. Any developer who has more than one local construct checkout configured (a normal multi-pack dev setup) will now get whichever checkout happens to sort first in that list for *every* slug they resolve locally, silently. That means:

- A `find_local_source foo` call can return the local source tree for an entirely different construct `bar`.
- Whatever caller consumes this path (install/sync/dev-link tooling) will read/copy/link files from the wrong pack while believing it is operating on `foo` — a correctness bug at minimum, and a supply-chain-adjacent integrity problem if the wrong pack's code silently ends up wired in under `foo`'s slug.

Even the default search paths (`head/.claude/scripts/constructs-lib.sh:580-586`) only *reduce* the risk (they interpolate `$slug` into the path) but don't eliminate it — a stale or manually-created directory at `$HOME/Documents/GitHub/construct-$slug` with someone else's `construct.yaml` inside would previously have been rejected by the name-vs-declared-name check and is now accepted unconditionally.

**Fix**: restore a slug-matching check before returning `$path` (it doesn't need to be the exact old implementation, but *some* verification that the directory's declared/inferred identity matches `$slug` is required to satisfy the function's own contract).

## Non-Critical Improvements

### 2. Hidden-dir allowlist permits near-miss names of protected dirs (by design, worth a code comment)

`head/.claude/hooks/safety/block-destructive-bash.sh:856-857`

I traced the new `_re_allow_exclude` / `_re_allow_list` pair by hand against `rm -rf` arguments like `./.git-backup`, `./.sshfoo`, `./.config-old`: because the exclusion alternatives are exact-match (`\.git($|/)`, `\.ssh($|/)`, etc.), a hidden directory whose name merely starts with a protected prefix but isn't an exact match (e.g. `./.git-backup`) falls through to the new permissive branch and is allowed. That's correct given the stated design (named exclusion list, not prefix blocking), and I don't think it's exploitable as a bypass of an *actual* `.git`/`.ssh`/etc. directory — but it's worth a one-line comment noting the match is exact-name-only, since a future reader might assume `.git*` is covered the way the old (buggy) blanket-`\.` rule accidentally did.

### 3. `_path_has_traversal` on `target` is stricter than the removed normalization, not weaker (verified, no action needed)

`head/.claude/scripts/lib/symlink-manifest.sh:255-260` replaces the `dirname(link)+target` normalization/escape check with a flat "does `target` contain a `..` segment anywhere" check. I confirmed this is at least as conservative: any relative `target` that resolves outside the repo root necessarily contains a literal `..` path segment somewhere, so the new check can't be bypassed by a target that the old normalization would have caught. It can, in theory, now reject a handful of legitimate nested symlinks whose `..` segments would have canceled out under full normalization (e.g. `link=.claude/skills/foo/nested/x`, `target=../shared`) — a usability regression at worst, not a security one. No change requested; flagging for awareness only.

## Adversarial Analysis

### Concerns Identified
1. `find_local_source` slug-match removal (Critical Issue #1) — silent cross-construct source resolution.
2. `_re_allow_exclude`/`_re_allow_list` in `block-destructive-bash.sh:856-857` rely on exact-name matching with no defense-in-depth prefix check, so any newly-added sensitive dot-dir in the future must remember to be added to the exclusion list explicitly — there's no fallback protection.
3. The PR description ("returns the first existing local source path") undersells what changed — it reads like a minor behavioral tweak but is actually the removal of the function's only correctness guarantee. A reviewer skimming the description alone would not catch Critical Issue #1.

### Assumptions Challenged
- **Assumption**: the engineer assumed slug validation was pure friction (blocking legitimate hidden-dir/local-dev cases) worth deleting outright, mirroring the legitimate friction fixed in the `block-destructive-bash.sh` hunk in the same PR.
- **Risk if wrong**: as shown above, `local_source_paths` is a general list, not a per-slug list, so removing validation trades a false-negative failure mode (correct but sometimes couldn't find a match) for a false-positive one (always finds *a* match, possibly the wrong construct) — the worse failure mode for something that feeds local installs.
- **Recommendation**: reinstate validation; if the goal was to relax an overly strict match (e.g. case sensitivity or the `construct-` prefix requirement), narrow the fix instead of deleting the check.

### Alternatives Not Considered
- **Alternative**: keep `_local_source_matches_slug` but relax it (e.g. drop the prefix requirement, keep the declared-name comparison) instead of deleting it wholesale.
- **Tradeoff**: slightly more code, but preserves the slug↔path invariant the function's own docstring promises.
- **Verdict**: should reconsider — the all-or-nothing deletion is what makes this a bug rather than a simplification.

## Next Steps

1. Restore slug verification in `find_local_source` (Critical Issue #1) before merge.
2. Optional: add a one-line comment on `_re_allow_exclude` noting exact-name-only matching (Non-Critical #2).
3. No action required on the `symlink-manifest.sh` change; verified safe.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":0,"low":2},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
