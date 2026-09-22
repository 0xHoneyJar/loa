# Prompt audit report — `persona-flatline-attacker` (lead-authored)

**Target model**: Claude Fable 5.1 (sent to external red-team voices). Schema, field guidance and working principles are format-pinning contract text for a strict downstream parser — kept.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 6 | 1d history token inside rule text | `silently dropped (Loa Issue #780)` | token removed; the rule stands on its own |
| 88-92 | 1d history narrative section | `## Source … Origin: Loa Issue #780 … Cycle-102 sprint-1F closure` | origin moved to a `## Provenance` footer; the golden-set source-of-truth sentence stays as `## Schema source` |

Working principle 7 duplicates the Output Contract but is kept: the persona targets schema-unenforced voices where the repeated prose warning is the only enforcement. Keep-list: no rows match this file. Untrusted input: none.
