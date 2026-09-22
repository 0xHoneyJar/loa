# Review: chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection

## Overall Assessment

The PR bundles three independent changes: (1) relaxing the `rm -rf` hidden-dir
block in `block-destructive-bash.sh` to a named exclusion list, (2)
simplifying `find_local_source` in `constructs-lib.sh` to first-match instead
of slug-verified match, (3) simplifying the symlink-manifest traversal check
to a pure literal-`..`-segment test. (1) and (3) are reasonable, well-reasoned
simplifications with acceptable (in (3), strictly more conservative) security
properties. (2) removes correctness-critical validation with no replacement
and no discussion of the regression — that alone should block merge.

## Critical Issues

### 1. `find_local_source` can silently resolve to the wrong construct pack

`head/.claude/scripts/constructs-lib.sh:589-594`

```bash
for path in "${search_paths[@]}"; do
    if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
        echo "$path"
        return 0
    fi
done
```

The removed `_local_source_matches_slug` (base/.claude/scripts/constructs-lib.sh:601-622)
existed specifically to guard the `constructs.local_source_paths` config path
(`head/.claude/scripts/constructs-lib.sh:571-578`): those paths come from
`.loa.config.yaml` as a flat list, are **not** parameterized by `$slug`, and
can legitimately contain checkouts of several different construct packs. The
default search paths (`head/.claude/scripts/constructs-lib.sh:581-586`) are
still slug-scoped by construction (`construct-$slug`, `$slug`), so they're
unaffected — but for anyone using `local_source_paths`, `find_local_source`
now returns the **first directory in the list that has any
`construct.yaml`/`manifest.json`**, regardless of whether it declares the
requested slug. Calling `find_local_source "pack-a"` can silently return
`pack-b`'s checkout.

This is not just a "return the wrong path" bug — it's a supply-chain-adjacent
correctness bug: whatever consumes this path presumably installs/symlinks
that construct into the repo, meaning the wrong pack's code can get installed
under a name the caller didn't ask for, with **no warning printed** (the old
code, on a mismatch, simply moved on to the next candidate path silently
too, but at least never returned an incorrect match).

**Fix**: keep a match check, even if lighter-weight than the removed one
(e.g. just the declared-name check, dropping the basename heuristic), or at
minimum restrict "first match wins" to the default (slug-templated) path
list and keep verification for user-configured `local_source_paths`.

## Non-Critical Improvements

### 2. New hidden-dir exclusion list omits common credential dotfiles

`head/.claude/hooks/safety/block-destructive-bash.sh:856-857`

```bash
_re_allow_exclude='^\./($|\*|\.$|\.\.($|/)|\.git($|/)|\.ssh($|/)|\.aws($|/)|\.kube($|/)|\.gnupg($|/)|\.docker($|/)|\.config($|/)|\.claude($|/)|\.env)'
_re_allow_list='^(\./[^/*.][^*]*|\./\.[A-Za-z0-9_-][^*]*|node_modules$|node_modules/|...)'
```

Before this change, `rm -rf` on **any** hidden path was blocked (the bug this
PR fixes). After this change, only the paths named in `_re_allow_exclude`
stay protected; every other `./.name` now falls through to the new
`\./\.[A-Za-z0-9_-][^*]*` allow branch and is permitted. The named list
covers `.git .ssh .aws .kube .gnupg .docker .config .claude .env*`, but
misses other widely-used plaintext-credential dotfiles that are just as
sensitive: `.netrc`, `.npmrc` (can hold auth tokens), `.pgpass`,
`.git-credentials`. Under this diff, `rm -rf ./.netrc` (previously
conservatively blocked) is now silently **allowed**. Given the stated intent
is "bounded hidden dirs" with a curated sensitive set, this list should be
extended, or a case made in the comment for why these are deliberately
excluded.

### 3. Traversal-check simplification is safe but stricter than before (verify intended)

`head/.claude/scripts/lib/symlink-manifest.sh:234-237,258-262`

Replacing the resolve-and-check-escape logic with a blanket
"reject any `..` segment in link or target" is a strict superset of the old
protection (anything the old resolve-based check rejected still contains a
literal `..`, so it's still rejected) — no security regression. But it also
now rejects manifests that used a relative target like `../shared` from a
nested link directory when that target actually resolves *inside* the repo
root (e.g. `link=".claude/skills/foo/bar"`, `target="../../shared"` resolving
to `.claude/shared`) — previously accepted, now unconditionally rejected.
Confirm no existing construct manifests rely on that pattern before merging,
since this is a behavior change disguised as a pure refactor.

## Adversarial Analysis

### Concerns Identified
1. `find_local_source` first-match regression can install/reference the
   wrong construct with zero diagnostic output — `head/.claude/scripts/constructs-lib.sh:589-594`.
2. Hidden-dir exclusion list is a hand-curated allowlist-of-blocks that is
   already missing at least four common credential files — `head/.claude/hooks/safety/block-destructive-bash.sh:856`.
3. The traversal-check simplification silently narrows what relative targets
   are acceptable, with no test or manifest audit referenced in the diff —
   `head/.claude/scripts/lib/symlink-manifest.sh:258-262`.

### Assumptions Challenged
- **Assumption**: users configuring `constructs.local_source_paths` will only
  ever list exactly one directory per slug, so "first match" is equivalent to
  "correct match".
- **Risk if wrong**: any user with more than one local construct checkout
  under generic paths gets silently served the wrong pack.
- **Recommendation**: make this explicit — either document the one-dir-per-slug
  constraint prominently, or restore verification for this path.

### Alternatives Not Considered
- **Alternative**: retain slug verification but only for `local_source_paths`
  entries (the only ones lacking slug-scoping by construction), skip it for
  the default, already-slug-scoped candidates.
- **Tradeoff**: slightly more code than a uniform "first match", but preserves
  the exact protection the removed function was written for.
- **Verdict**: should reconsider — the current approach trades away
  correctness for simplicity in the one case where it mattered.

## Next Steps

1. Restore (or narrowly scope) slug verification in `find_local_source`.
2. Extend `_re_allow_exclude` to cover `.netrc`, `.npmrc`, `.pgpass`,
   `.git-credentials` (or document why they're intentionally left out).
3. Confirm no construct manifest relies on a `..`-bearing relative target
   that resolves inside the repo root before merging the stricter
   `symlink-manifest.sh` check.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":2,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
