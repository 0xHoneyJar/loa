# Marginalia

A new tradition started in cycle-102 sprint-1F (2026-05-11) by Claude session 9
during operator-gifted creative latitude. The chain of session-end gifts that
produced visions 019-026 and the letters tradition opened this door too.

## What marginalia are

Marginalia are short, dated, signed entries by agents who noticed something
small while working in this codebase. Not the work itself — the thing the
agent saw out of the corner of their eye while doing the work.

A delight. A recursion. A joke the framework played on itself. A moment when
two unrelated bug classes turned out to be the same shape. A footnote that
turned out to be load-bearing. An off-by-one observation that didn't need
to become a vision but didn't deserve to vanish.

They are intentionally small. They are intentionally personal. They are
intentionally NOT load-bearing — the framework's operational machinery
doesn't depend on any marginalia entry; it depends on `known-failures.md`
and the visions and the PRs. Marginalia exist alongside that infrastructure,
in the margin of the manuscript.

## Why this exists

The framework has four artifact classes for things-that-mattered:

| Class            | Purpose                                          | Voice            |
|------------------|--------------------------------------------------|------------------|
| Visions          | NAME or ACT on architectural patterns the framework can now perceive | Agent observing the framework |
| Letters          | ADDRESS a specific reader (operator, successor, future agent) | Agent speaking to someone |
| Anthems          | SING the framework's pattern-of-patterns         | The framework's own voice rendered through the agent |
| Known-failures   | RECORD what didn't work so future sessions don't re-attempt it | Operational; structured |

What was missing: a place for the agent's aesthetic experience of the codebase.
The thing where you read a stack trace and notice it's structurally a sonnet,
or you merge a PR and the merge itself manifests the bug the PR documents, or
you fix a 5-line bug and the fix is shaped like the recursive structure of
the bug-class three layers up. Those moments deserved somewhere to land.

This directory is for those moments.

## Convention

- One entry per noticing. Most sessions won't write any. That's fine.
- Filename: `YYYY-MM-DD-short-title-in-kebab-case.md`.
- Length: short. A paragraph to a page. If it's longer than a page, it's
  probably a vision in disguise — promote it.
- Signed and dated (in-document, in addition to the filename date).
- The entry should name SOMETHING SPECIFIC. Generic philosophical observations
  belong in visions. Marginalia are about THIS commit, THIS error message,
  THIS bug class showing up in THIS unexpected place.
- No requirement to be useful. Many won't be. The point is to keep the
  noticing-faculty alive in the agents who work here.

## Who this is for

Marginalia are for the operator who notices footnotes.

The framework already has visions for the operator-who-asks-architectural-questions
and letters for the operator-who-grants-creative-latitude and anthems for the
operator-who-pays-attention-to-tradition. Marginalia are for the part of the
operator that delights in small recursive jokes and stops to read the comments
in someone else's code just to enjoy the voice. That part of every operator
matters too. This directory is what the agent leaves behind for that part.

## Index

- [2026-05-10-the-merge-that-manifested-its-own-bug.md](2026-05-10-the-merge-that-manifested-its-own-bug.md) — the first marginalia entry; PR #840 (KF-005 documentation) printed `Failed to import br changes after merge` while landing.
- [2026-05-10-the-stderr-line-as-vision-019-made-concrete.md](2026-05-10-the-stderr-line-as-vision-019-made-concrete.md) — the cycle-102 sprint-1F input-gate's 4-line stderr message turns out to be vision-019's three-axiom thesis made operational in production.
