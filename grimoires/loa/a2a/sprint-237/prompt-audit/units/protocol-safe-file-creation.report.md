# Prompt audit report — `protocol-safe-file-creation` (lead-authored)

**Target model**: Claude Fable 5.1. Kept: the method table, the high-risk extension table, the corrupting example with its actual output, the pre-write checklist — the parts an implementer cannot infer.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 3-5 | 1d version banner + history token in rule text | `Protocol Version: 1.0.0`, `Last Updated`, `Issue Reference: #197` | moved to a `## Provenance` footer |
| 17-42 | 1c ASCII duplicate | decision-tree box restating the method table | three-sentence tree (shell-conventions.md points here for it) |
| 79-104 | 1c example over-indexing | two SAFE examples that the table already states | removed; the DANGEROUS example with its corrupted output stays |
| 138-164 | 1c/1d narrative | `Why This Matters` three subsections | one sentence with the reason (silent, unattended, costly) |
| 168-176 | 1c meta | `Integration Points` describing who references the file | removed |
| 180-184 | 1d history tokens | `#197`, `PR #199` in Related | Provenance footer |

MUST/NEVER: none. Keep-list: no rows match. Untrusted input: none.
