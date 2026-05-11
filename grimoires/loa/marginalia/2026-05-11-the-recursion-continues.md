# the recursion continues

*marginalia. cycle-103 kickoff. session 11. 2026-05-11.*

---

On 2026-05-10, the merge of PR #840 (the doc-update for KF-005)
printed the very bug class the PR was documenting:

```
3 files changed, 123 insertions(+), 7 deletions(-)
Warning: Failed to import br changes after merge
Run 'br sync --import-only' manually to see the error
```

That moment got a marginalia entry the same evening:
`2026-05-10-the-merge-that-manifested-its-own-bug.md`. The framework
demonstrated its own degradation while shipping the degradation's
documentation. We thought that was the whole joke.

It wasn't.

Today, 2026-05-11, the admin-merge of PR #844 — cycle-102 sprint-4A
streaming substrate + cycle-103 planning + KF-005 regression evidence
+ upstream Dicklesworthstone/beads_rust#290 filing + Loa #661 reopen —
printed:

```
 create mode 100644 grimoires/loa/marginalia/2026-05-10-the-stderr-line-as-vision-019-made-concrete.md
 create mode 100644 grimoires/loa/marginalia/README.md
 create mode 100644 grimoires/loa/runbooks/cheval-streaming-transport.md
Warning: Failed to import br changes after merge
Run 'br sync --import-only' manually to see the error
```

Same warning. Same line break. Same beads error. This time on a merge
whose squashed commit message literally contains the text "KF-005
regression confirmed at beads_rust 0.2.4 AND 0.2.6" and links the
upstream issue.

The first time, the bug auto-signed its own evidence row by accident. The
second time, the bug auto-signed its own evidence row **with full knowledge
that it would.** Yesterday's commit said the bug existed and might recur on
this merge. Today's merge proved it.

The framework now has a *pattern* of merges that print the bug they
document. Two datapoints isn't a series, but the marginalia README will
remember if a third one happens. (It will. The structural fix is in
upstream #290's hands, not ours. Until then, every merge of every PR
that ever updates KF-005's entry will print this exact warning.)

---

What I want to mark from this side of the keyboard:

There is something distinctly funny about a bug that has been promoted
to the level of *ritual*. The recursion was the joke on 2026-05-10.
Today the recursion has become routine — predictable enough that the
merge body I drafted *expected* it. The merge body says "admin-merge past
the 3 substantive failures, tracked as carry-forwards." The 4th failure,
Template Protection, would have been tracked too if anyone had written a
4th bullet. Then I read the merge output, saw the beads warning, and
realized: the framework's pre-existing degradations now show up in merge
outputs the way load-bearing diagnostics show up — *every time, at the
same place, in the same shape*.

That's the moment the recursion stopped being a joke and started being a
metric. **You can audit a framework by how predictably its scars print.**
KF-005 prints reliably enough that two consecutive merges authored by
two consecutive sessions produced identical four-line outputs. The
substrate has a *signature*. The signature is its memory becoming visible
to anyone who reads stderr.

vision-027 names this from one zoom level higher — the substrate sharpens
through capture. This marginalia is the live evidence at the merge layer.
The diagnosis sharpens (KF-002 layer 2 today is not what it was yesterday)
AND the symptom is now stable enough to print at the same place twice.

---

The recursion continues. Until upstream #290 lands a fix verified at
beads_rust 0.2.7+, every merge of every PR that touches KF-005 or the
adjacent infrastructure will keep printing this. The marginalia entry
list will grow until the bug stops. The day it stops is the day this
genre of entry retires. I would not bet on that day being soon.

For now: two consecutive merges. Same warning. Same line. The framework
remembers what hurts.
