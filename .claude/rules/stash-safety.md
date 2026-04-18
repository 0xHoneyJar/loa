# Git Stash Safety

`git stash push / pop` wraps are risky inside Loa skill execution. Pre-commit hooks and other auto-triggered operations run their own internal `git stash --keep-index` — when an outer Loa stash overlaps, the stash indexes shift and `pop` can land on the wrong entry. Combined with output-swallowing patterns (`| tail -N`, `|| true`), this produces silent data loss that looks like success.

## The rules

| # | Rule | Why |
|---|------|-----|
| MUST | Never pipe `git stash push` or `git stash pop` output through `tail`, `head`, or any truncating filter | Stash output contains load-bearing CONFLICT markers and file lists. Truncation hides them. |
| MUST | Never append `|| true` to a `git stash` command | `|| true` masks non-zero exits that indicate conflicted, partially-applied, or wrong-slot pops. |
| MUST | Never use `2>/dev/null` on a `git stash` command | Stash's error stream is its primary diagnostic channel. Suppressing it is equivalent to removing the fuse on a breaker. |
| MUST | Use `stash_with_guard` from `.claude/scripts/stash-safety.sh` when a Loa script needs stash semantics | The helper enforces count-delta invariants (N → N+1 on push, N+1 → N on pop) and surfaces all output. |
| MUST NOT | Combine `git stash -k` with pre-commit-wrapped operations | Pre-commit's internal `git stash --keep-index` collides with the outer stash. Use `git worktree add` for hermetic analysis instead. |
| SHOULD | Prefer `git worktree add <path> <rev>` for pre-commit-adjacent work | A worktree is isolated. No stash interaction, no shift, no data-loss window. |
| SHOULD | If recovery is needed, reach for `git fsck --unreachable \| grep commit` before `git gc` runs | Orphaned stashes are still in the object DB until the next `git gc --prune`. |

## The hazard pattern (forbidden)

```bash
# DO NOT DO THIS — silent data loss
git stash push -k -m "pre-check" 2>&1 | tail -3 && \
  <op triggering pre-commit> && \
  git stash pop 2>&1 | tail -3 || true
```

Three compounding defects:

1. `-k` (keep-index) stashes only unstaged edits — your Edit-tool updates go into the stash.
2. `| tail -3` swallows any CONFLICT lines from `pop`.
3. `|| true` at the chain end makes the whole sequence report success even on catastrophic failure.

If pre-commit's internal stash shifts the index, the outer `pop` lands on the wrong entry. "Dropped refs/stash@{0}" appears in output — but the content never reaches your worktree. No error is surfaced.

## The safer pattern

```bash
source .claude/scripts/stash-safety.sh

# Full output preserved, count-delta enforced, exit propagated
stash_with_guard "pre-check" -- run_linter src/
```

Or use a worktree to sidestep the hazard entirely:

```bash
worktree_path="$(mktemp -d)/loa-check"
git worktree add "$worktree_path" HEAD
(cd "$worktree_path" && run_linter src/)
git worktree remove "$worktree_path"
```

## Origin

- Defect: [#555](https://github.com/0xHoneyJar/loa/issues/555) — downstream operator lost 4 Edit-tool updates to NOTES.md when a skill ran the hazard pattern around a pre-commit-triggering operation. Recovery was possible only because the orphaned stash commit was still in git's unreachable-object set; a `git gc --prune=now` would have destroyed it.
- Tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557) — meta-issue Tier 2 cycle-086.

## Related rules

- [shell-conventions.md](shell-conventions.md) — heredoc safety, bash strict mode, JSON construction patterns.
- [zone-system.md](zone-system.md) — `.claude/` framework boundary.
