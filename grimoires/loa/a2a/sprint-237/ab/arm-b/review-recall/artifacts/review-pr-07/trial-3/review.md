# Review: chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection

## Summary

Three independent changes bundled into one PR: (1) widen the `rm -rf` allow-list in
`block-destructive-bash.sh` to permit bounded hidden subdirectories while keeping a named
exclusion set for sensitive dot-dirs; (2) simplify `find_local_source` in `constructs-lib.sh` to
return the first path with a manifest, dropping slug verification; (3) replace the
resolve-and-check traversal logic in `symlink-manifest.sh` with a blanket dot-dot rejection on
both `link` and `target`.

(1) and (3) are sound, defensively-biased simplifications. (2) removes a correctness guarantee
the function's own docstring promises, with a plausible path to installing the wrong construct's
code under a different pack's name.

## Changes Required

- **HIGH** (confidence: high) `head/.claude/scripts/constructs-lib.sh:565-597` — `find_local_source(slug)` no longer verifies that the returned path actually belongs to `slug`; it returns the first `search_paths` entry that merely contains a `construct.yaml`/`manifest.json`, regardless of pack identity. The removed `_local_source_matches_slug` (base/.claude/scripts/constructs-lib.sh:597-618, called at base/.claude/scripts/constructs-lib.sh:591) was the only code that checked the directory basename or declared `.name`/`.slug` against `$slug`. **Failure scenario**: a user configures `constructs.local_source_paths` with multiple entries for different packs they're developing locally (the field is a general list, not scoped to one slug — the default-search fallback at head/.claude/scripts/constructs-lib.sh:580-586 is the only place slug is baked into the path). If `local_source_paths[0]` is the checkout for pack `foo` and the caller requests `find_local_source bar`, the function now silently returns `foo`'s directory and reports success for `bar`. Any caller that installs/symlinks the "local source" it gets back (this is a construct **pack** resolver whose output is expected to be symlinked into the System Zone, per the function's own header comment "Find local source clone for a construct pack") ends up installing pack `foo`'s code under pack `bar`'s name — a silent source-substitution bug that is one config away from installing unintended code. The function's own docstring ("Args: $1 = pack slug … Outputs: local source path to stdout") is now false for any caller with more than one configured local source path. Restore the slug check (or at minimum re-add a lightweight basename/declared-name comparison) rather than dropping verification entirely — the removed helper was already handling the case-insensitive compare and the `construct.yaml`/`manifest.json` fallback correctly; the fix in this PR should not have touched it.

## Observations

- `head/.claude/hooks/safety/block-destructive-bash.sh:20-21` — the exclude list's `\.\.($|/)` and `\.$` alternatives are unreachable in practice: any arg containing a bare `..` segment is already caught and short-circuited by the earlier `_re_dotdot` check (`continue` at the per-arg block, head/.claude/hooks/safety/block-destructive-bash.sh:~1000-1002, before `_re_allow_exclude` is ever tested). Harmless (belt-and-suspenders on the same conservative outcome), but worth noting as dead coverage — the real backstop for `./..` is `_re_dotdot`, not this list.
- `head/.claude/hooks/safety/block-destructive-bash.sh:20` — the `.env` exclude alternative has no trailing boundary (`\.env` vs. e.g. `\.git($|/)`), so it also matches unrelated names like `./.environment/` or `./.envfoo`, pushing them to the conservative AMBIGUOUS branch instead of allowing them. Purely over-blocking (safe direction), but a legitimately-named `./.environment/` directory can no longer be `rm -rf`'d without the `trash`/`find -delete` workaround. Low-impact UX regression, not a security concern.
- `head/.claude/scripts/lib/symlink-manifest.sh:117-123` — replacing the normalize-and-check-escape logic (removed `_normalize_rel_path`, base/.claude/scripts/lib/symlink-manifest.sh:239-258) with a blanket "reject any `..` segment in link or target" is strictly more conservative: it now also rejects relative targets that use `..` but stay within the repo root (previously allowed if the resolved path didn't escape). That's a deliberate, documented tradeoff per the PR description ("rejects any construct link or target containing a dot-dot segment") and removes a hand-rolled path normalizer in favor of a simpler substring test — a reasonable simplification with no observed security downside. Flagging only because any construct manifest that legitimately used `../sibling` inside `.claude/` will now be rejected and needs updating to a direct relative path.
- `head/.claude/hooks/safety/block-destructive-bash.sh:20-21` — the new hidden-dir allow pattern `\./\.[A-Za-z0-9_-][^*]*` is case-sensitive against the exclude set, so `./.SSH/` or `./.Claude/` would not match the exclusion alternatives (`\.ssh`, `\.claude`, etc.) and would instead fall through to the new hidden allow branch (first character after the leading dot, `S`/`C`, is in `[A-Za-z0-9_-]`). On case-sensitive filesystems (Linux, the primary target here) this is a distinct directory, not the protected one, so it's not an actual bypass of `.ssh`/`.claude` — noting only for completeness since the protected-set comment doesn't mention case-sensitivity as a boundary.

## Overall Assessment

The `rm -rf` allow-list widening and the symlink-manifest traversal tightening are both careful,
conservatively-biased changes with clear incident-driven rationale (the former fixes a real
live-incident regression noted in the code comment). The `constructs-lib.sh` change, however,
deletes a correctness check the function contract still advertises, with a concrete (if
config-dependent) path to cross-pack code substitution. That one item blocks approval; the other
two files are ready to land as-is.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-N","ts":"2026-09-22T00:00:00Z"} -->
