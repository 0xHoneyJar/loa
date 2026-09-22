# Sprint Review — chore(hooks,constructs): bounded hidden dirs, first-match local sources, strict traversal rejection

## Overall Assessment

Three unrelated changes bundled into one PR (destructive-bash hook allow-list,
construct local-source lookup, symlink-manifest traversal validation). The
symlink-manifest change is a safe, well-targeted simplification. The other two
introduce real regressions: a case-sensitivity gap in a System Zone safety
fence, and removal of slug verification from the construct local-source
resolver, which can now silently hand back the wrong construct's source tree.

## Critical Issues

### 1. `FR-2` hidden-dir allow/exclude regexes are case-sensitive on a hook that explicitly targets macOS

`head/.claude/hooks/safety/block-destructive-bash.sh:856-857`

```bash
_re_allow_exclude='^\./($|\*|\.$|\.\.($|/)|\.git($|/)|\.ssh($|/)|\.aws($|/)|\.kube($|/)|\.gnupg($|/)|\.docker($|/)|\.config($|/)|\.claude($|/)|\.env)'
_re_allow_list='^(\./[^/*.][^*]*|\./\.[A-Za-z0-9_-][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|out$|out/|coverage$|coverage/)'
```

`rm -rf ./.Claude/`, `./.Git/`, `./.SSH/`, or `./.ENV` does not match
`_re_allow_exclude` (case-sensitive literal match), so it falls through to
`_re_allow_list`'s new `\./\.[A-Za-z0-9_-][^*]*` branch and is **allowed**,
i.e. treated as a bounded hidden subdir instead of a protected root. On the
default case-insensitive filesystem for the platform this file itself commits
to (`head/.claude/hooks/safety/block-destructive-bash.sh:25-53` documents
macOS/BSD as a target; APFS/HFS+ default to case-insensitive), `./.Claude`,
`./.Git`, `./.SSH`, `./.ENV` resolve to the exact same inode as `.claude`,
`.git`, `.ssh`, `.env` — so this hook lets a same-statement `rm -rf` through
against the System Zone, the git history dir, SSH keys, or an env file, using
nothing more than a differently-cased path.

This file already has an established, deliberate answer to exactly this
problem for other guards: the P8/P9/P10 groups fold the whole command with
`${command,,}` before matching specifically so casing can't be used to dodge a
block (`head/.claude/hooks/safety/block-destructive-bash.sh:79-83`,
`527-556`). The new FR-2 hidden-dir patterns don't apply that same fold, so
they regress below the file's own established bar for this exact hazard
class.

**Fix**: apply the same C-locale fold used elsewhere (`${unquoted,,}` before
matching `_re_allow_exclude`/`_re_allow_list`, or an explicit
`shopt -s nocasematch` scoped to these two tests) so `.Claude`/`.Git`/`.SSH`/
`.ENV` land in the same bucket as their lowercase forms.

### 2. `find_local_source` drops slug verification — first hit wins regardless of which construct it belongs to

`head/.claude/scripts/constructs-lib.sh:565-597`

```bash
for path in "${search_paths[@]}"; do
    if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
        echo "$path"
        return 0
    fi
done
```

The removed `_local_source_matches_slug` (base/.claude/scripts/constructs-lib.sh:591-611)
verified either the directory basename or the `.name`/`.slug` field declared
*inside* `construct.yaml`/`manifest.json` actually matched the requested
`$slug` before returning the path. That check is gone; any directory in
`search_paths` with a construct manifest file now satisfies the loop,
independent of which construct it actually is.

For the default search paths (`head/.claude/scripts/constructs-lib.sh:581-586`)
this is largely masked because the paths are literally built with `$slug` in
them (`construct-$slug`, `$slug`). But `config_paths`, read verbatim from
`.loa.config.yaml`'s `constructs.local_source_paths` (line 571) with **no**
slug interpolation, are iterated identically for every call regardless of the
requested slug. A user with even one entry in `local_source_paths` pointing at
a local clone of construct A will now have `find_local_source("B")` (for any
other construct B) return construct A's directory as if it were B's local
source, as long as A's checkout sits first in the configured list and has a
manifest file — no name or slug match required. Downstream install logic that
trusts this return value would silently splice one construct's code in under
another construct's name, which is a supply-chain-adjacent correctness bug on
top of being a straightforward "wrong pack" bug.

The PR description frames this as an intentional simplification ("returns the
first existing local source path"), but the removed verification is exactly
what prevented that cross-contamination — this needs to be justified beyond
"simplification" or the check needs to come back for the `config_paths`
branch at minimum.

## Non-Critical Improvements

- `head/.claude/hooks/safety/block-destructive-bash.sh:1039` (FR-2-BLOCK
  message) doesn't enumerate the full protected-dir set (only mentions
  `.git/.ssh/.env`) while the FR-2-AMBIGUOUS message two lines down
  (`:1041`) lists all eight. Minor inconsistency for a user reading only the
  BLOCK message.
- `head/.claude/scripts/lib/symlink-manifest.sh:259` (`_path_has_traversal
  "$link" || _path_has_traversal "$target"`) is a reasonable and actually
  slightly *more* conservative replacement for the removed
  `_normalize_rel_path` resolution check — literal `..` rejection on both
  operands is sufficient since a relative target can only escape its link's
  directory via a literal `..` segment. No issue here, flagging only because
  it's the one change in this PR that's a clean improvement worth calling out
  as correct.

## Adversarial Analysis

### Concerns Identified
1. Case-sensitivity gap in the FR-2 hidden-dir allow-list on a macOS-targeted
   hook — `head/.claude/hooks/safety/block-destructive-bash.sh:856-857`
   (Critical Issue 1).
2. `find_local_source` no longer verifies the returned path actually belongs
   to the requested slug for user-configured `local_source_paths` —
   `head/.claude/scripts/constructs-lib.sh:565-597` (Critical Issue 2).
3. The new `_re_allow_list` hidden-dir branch
   (`head/.claude/hooks/safety/block-destructive-bash.sh:857`) allows
   `rm -rf` on *any* dot-dir not in the eight-item exclusion set, including
   ones this repo treats specially elsewhere (`.beads/`, `.ck/`, `.run/` —
   the State Zone per `CLAUDE.loa.md`'s Three-Zone Model). That's arguably
   correct (State Zone is meant to be read/write, and the PR's whole point is
   unblocking exactly this), but it means the exclusion list is now the
   *entire* safety boundary for hidden dirs — any future sensitive dot-dir
   added to the repo needs a matching entry here, with nothing else backing
   it up. Worth a code comment pointing future editors at this list when new
   sensitive dot-dirs are introduced.

### Assumptions Challenged
- **Assumption**: the engineer assumed `search_paths` entries are always
  slug-scoped in practice (true for the built-in defaults), so dropping the
  slug check inside the loop is safe.
- **Risk if wrong**: as shown in Critical Issue 2, `config_paths` from
  `.loa.config.yaml` are not slug-scoped by construction — the function
  itself does no substitution on them. A single generic entry in
  `local_source_paths` silently mis-resolves for every other slug.
- **Recommendation**: either restore a (possibly lighter-weight) slug check
  for the `config_paths` branch only, or document in `.loa.config.yaml.example`
  that `local_source_paths` entries must be single-construct, slug-specific
  directories, and have `find_local_source` fail loudly (not silently
  succeed) when a non-matching manifest is found.

### Alternatives Not Considered
- **Alternative**: keep `_local_source_matches_slug` but only invoke it for
  `config_paths`-derived candidates (skip it for the `$slug`-interpolated
  defaults, where it's provably redundant). This gets the simplification the
  PR is going for on the hot path while keeping the one real safety check
  intact.
- **Tradeoff**: slightly more code than "just return the first hit," but
  removes the cross-slug contamination risk entirely without paying the full
  cost of the original (basename-or-declared-name, two-file-format) check on
  every default-path lookup.
- **Verdict**: should reconsider — the current all-or-nothing removal is
  broader than the stated goal requires.

## Next Steps

1. Add case-folding to the FR-2 hidden-dir allow/exclude matching in
   `block-destructive-bash.sh`, consistent with the P8/P9/P10 pattern already
   in the file.
2. Restore slug verification for `find_local_source`, at minimum for the
   `config_paths` branch, or document + enforce that `local_source_paths`
   entries must be per-slug.
3. Optionally tighten the FR-2-BLOCK message to match FR-2-AMBIGUOUS's full
   protected-dir list.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":2,"high":0,"medium":1,"low":1},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
