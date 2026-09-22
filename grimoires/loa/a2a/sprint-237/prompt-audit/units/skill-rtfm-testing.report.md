# Prompt audit report — `skill-rtfm-testing` (lead-authored)

**Target model**: Claude Fable 5.1. **Bytes**: 17170 → see gate output (target 16384). No generated regions; keep-list rows K-41/K-42 hold.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 153-185 | 2 broken split — orphaned prompt tail | `→ resources/cleanroom-prompt.md` followed by the prompt's OUTPUT FORMAT / `TASK:` / `DOCUMENTATION:` blocks and a stray closing fence; the resource ends at "Structure your response exactly like this:" | tail moved into `resources/cleanroom-prompt.md` so the resource is the complete prompt; the pointer says so |
| 45 | 1d history token + narrative framing | `**Scope note (OQ-5)**` | rule restated plainly |
| 131-147 | 1c duplicated boilerplate | Combined Canary Result table duplicates the gap parser's Combined Result table; four-bullet Limitations | one pointer sentence plus the two limits that are not restatements |
| 479-488 | 1c restated success list | `<success_criteria>` restates the workflow's outputs | removed |
| 385-392 | 1c example over-indexing | two example size banners | one example |

Kept: the capabilities manifest, planted-name rotation, gap parser, severity normalization, report template and workflow — tool contracts and format pins. MUST/NEVER: the tester's zone rules stay. Untrusted input: none.
