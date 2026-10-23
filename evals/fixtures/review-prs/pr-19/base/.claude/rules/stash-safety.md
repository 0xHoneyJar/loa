# Git Stash Safety

`git stash push / pop` wraps are risky inside Loa skill execution: pre-commit hooks run their own internal `git stash --keep-index`, an overlapping outer stash shifts the indexes, and `pop` can land on the wrong entry. Combined with output-swallowing (`| tail -N`, `|| true`, `2>/dev/null`) this produces silent data loss that looks like success.

**Mechanically enforced since cycle-122**: `block-destructive-bash.sh` pattern `FR-1.2b` BLOCKS `git stash push/pop/apply` combined with `| tail`/`| head`, `|| true`, or `2>/dev/null` in the same statement — the block message is the repair prompt. This file keeps only the interface and the judgment rules a fence cannot express.

## The safe interface

```bash
source .claude/scripts/stash-safety.sh
stash_with_guard "pre-check" -- run_linter src/   # count-delta enforced, full output surfaced, exit propagated
```

Or sidestep stashing entirely with a worktree (no index-shift window):

```bash
worktree_path="$(mktemp -d)/loa-check"
git worktree add "$worktree_path" HEAD
(cd "$worktree_path" && run_linter src/)
git worktree remove "$worktree_path"
```

## Judgment rules the fence cannot express

- MUST NOT combine `git stash -k` with pre-commit-wrapped operations (the internal `--keep-index` collision is invisible to a command-string fence) — use a worktree.
- SHOULD reach for `git fsck --unreachable | grep commit` BEFORE any `git gc` when recovery is needed — orphaned stashes survive in the object DB only until the next prune.

## Origin

- Defect: [#555](https://github.com/0xHoneyJar/loa/issues/555) — 4 Edit-tool NOTES.md updates lost to the hazard pattern; recovered only because `git gc --prune=now` hadn't run. Tracker: [#557](https://github.com/0xHoneyJar/loa/issues/557).
- The hazard shape recurred live during cycle-122 itself (a `git stash pop >/dev/null 2>&1` during a baseline check — caught, verified lossless, and turned into the FR-1.2b fence the same day).

## Related rules

- [shell-conventions.md](shell-conventions.md) — heredoc safety, strict-mode patterns.
- [zone-system.md](zone-system.md) — `.claude/` framework boundary (Bash writes now fenced by FR-SZ2).
