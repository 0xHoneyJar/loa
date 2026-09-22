# Prompt audit report — `protocol-git-safety` (lead-authored)

**Target model**: Claude Fable 5.1. Kept: the four detection snippets, the warning message and its placeholders, the `AskUserQuestion` call and the remediation guide — user-facing text and mechanism.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 13-58 | 1c numeric choreography | `(Fastest, < 100ms)`, `(Local, < 1s)`, `(Network, < 3s)` and four `When to use` lines restating the layer order | timings dropped; the two non-obvious "when" notes folded into the headings |
| 62-92 | 1c ASCII duplicate | detection-procedure box restating the confirmation flow and response table | four numbered steps |
| 139-145 | 1c duplicate | response table restating the option descriptions | removed (kept in step 4) |
| 173-192 | 1c overlapping lists | Edge Cases, Exceptions and Error Handling repeat each other | one merged list |

**Residual**: the file stays above its 70 % target because the warning text, the remediation guide and the four detection snippets are exact user-facing/mechanical content (keep-list class), not prose to cut. MUST/NEVER lines (`NEVER auto-proceed`) stay with their mechanism (`AskUserQuestion`). Keep-list: no rows match. Untrusted input: none.
