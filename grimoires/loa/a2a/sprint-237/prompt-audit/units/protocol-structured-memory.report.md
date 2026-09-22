# Prompt audit report — `protocol-structured-memory` (lead-authored)

**Target model**: Claude Fable 5.1. Where-knowledge-goes table, template contract and write-discipline table are author-only knowledge — kept.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 3-4 | 1d history narrative + migration-relative phrasing | `v0.16.0 lineage…`, `cycle-121 (v2.0): shrunk… the old MUST-section tables… Claude-5-class models synthesize without a scripted ritual` | replaced by the one sentence that states the contract; lineage moved to a `## Provenance` footer |
| 17 | history tokens outside a KF-pointer line | `KF-002/KF-003 attempts tables` | rewritten as a `known-failures.md` pointer (the instruction, not a story) |
| 17 | 1d narrative tail | `(tracked as a discovered issue; alignment is template-owner work, not per-session)` | dropped; the WARN behaviour stays |

MUST/NEVER/ALWAYS: none. Keep-list: no rows match. Untrusted input: none.
