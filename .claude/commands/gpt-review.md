---
name: gpt-review
description: DEPRECATED — superseded by /flatline-review. Do not invoke.
disable-model-invocation: true
---

# /gpt-review Command (DEPRECATED)

> [!WARNING]
> **DEPRECATED as of 2026-04-15**, stub-only as of cycle-119 (2026-07-07).
> `disable-model-invocation: true` prevents this command from running at all.

**Replacement**: use `/flatline-review` (Flatline Protocol — multi-model
adversarial review), or rely on the Flatline gates that already run inside
`/run sprint-plan`, `/run-bridge`, and `/audit-sprint`. See
`.claude/loa/reference/flatline-reference.md`.

**Full prior implementation** (execution steps, prompt-building examples,
verdict table, error codes) is preserved in git history — see
`git log -- .claude/commands/gpt-review.md` (pre-stub content at commit
`e25128ba` and earlier).

If you relied on `/gpt-review`, run `/feedback` or file an issue at
https://github.com/0xHoneyJar/loa/issues with the `deprecation` label.
