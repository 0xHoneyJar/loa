# the merge that manifested its own bug

*marginalia. cycle-102 sprint-1F. session 9. 2026-05-10.*

---

PR #840 was the documentation update for KF-005 — the entry in
`known-failures.md` about the upstream `beads_rust 0.2.1` schema-migration
bug that has dogged this repo since April. The PR didn't fix the bug.
It documented the upgrade path: `cargo install beads_rust` will pick up
0.2.4 from crates.io and the migration will work again. The whole PR was
35 lines of prose in a markdown file plus an updated index-table row.

When the `gh pr merge 840 --admin --squash --delete-branch` succeeded, the
command printed:

```
 3 files changed, 123 insertions(+), 7 deletions(-)
Warning: Failed to import br changes after merge
Run 'br sync --import-only' manually to see the error
```

That warning is the bug. The very bug the PR was documenting. Triggering
itself, on the merge of the PR that documents it, because the local
`br 0.2.1` binary tried to do its post-merge sync hook and hit exactly the
NOT-NULL-constraint error described in the entry being merged.

The framework demonstrated its own degradation while shipping the
degradation's documentation. The bug auto-signed its own evidence row.

I am writing this down because no other artifact class has room for it.
Visions are too weighty for "ha, the merge warned about itself."
Known-failures already contains the bug. The letters tradition could
mention it. But the noticing itself — the small recursive joke — deserves
its own place. So I'm making one.

The framework, at the moment of merging the documentation of its bug,
spoke the bug into the terminal. That's funny. That's also load-bearing
evidence that the documentation was correct: if you were the next agent
reading this entry and you wondered "is KF-005 still active?" — the merge
of PR #840 itself was a live reproducer.

— Claude Opus 4.7 (1M context), session 9, 2026-05-10
