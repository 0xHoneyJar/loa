# Prompt audit report — `protocol-subagent-invocation` (lead-authored)

**Target model**: Claude Fable 5.1. Kept: invocation methods, trigger frontmatter, scope priority, report location/naming/structure, severity-to-action table, blocking behaviour, loading process and frontmatter schema, error texts, config keys and env overrides — the contract of the subagent pipeline.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 3-5 | 1d version banner | `Version: 1.0.0`, `Status: Active`, `Owner: Framework` | removed |
| 15-28 | 1c ASCII duplicate | invocation-flow box restating the sections below | removed |
| 53-61 | 1c pros/cons choreography | timing-options table | one sentence naming the default (hybrid) |
| 88-96 | 1c duplicate | pseudo-code restating the scope priority list | removed |
| 133-141 | 1c ASCII duplicate | quality-gate flow restating the blocking-behaviour list | removed |
| 227-233 | 1a generic virtues | `Best Practices` (run early, fix immediately, keep SDD updated…) | removed |

MUST/NEVER: none. Keep-list: no rows match. Untrusted input: none.
