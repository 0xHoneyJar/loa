# Prompt audit report — `protocol-implementation-compliance` (lead-authored)

**Target model**: Claude Fable 5.1. The registry-rendered checklist, error codes and decision tree are contract material — kept; the generated block is byte-identical.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 5 | 1d meta-narrative about who references the file | `This protocol is referenced by CLAUDE.loa.md, simstim-workflow, …` | dropped (routing lives in the callers) |
| 40-47 | 1c/3 restated layering as a numbered list | `enforced at 4 levels: 1. … 4. …` | one sentence |

No history tokens. MUST/NEVER/ALWAYS: none in prose (the table's ALWAYS cells are registry-rendered). Keep-list: no rows match. Untrusted input: none.
