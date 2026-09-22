# Prompt audit report — `protocol-change-validation` (lead-authored)

**Target model**: Claude Fable 5.1. Kept: when to apply, the four-part checklist, the exit-code tables (warnings 1 / blockers 2) and the script pointers — the contract of `validate-change-plan.sh`.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 7-15 | 1c restatement | `## Purpose` list restates the title and checklist | removed |
| 66-92 | 1c numeric choreography without a mechanism | three "Levels" with `Run time: ~5 seconds / ~30 seconds / ~2 minutes` — the script has no level flag | removed |
| 96-108 | 1c duplicate | Mermaid flowchart restates the exit-code tables | removed; the preflight YAML stays |
| 155-207 | 1c example over-indexing | three markdown evidence templates | one paragraph stating what evidence a plan records |
| 211-240 | 1c/3 generic integration recipes | pre-commit and CI snippets that only wrap the script | one sentence: hook or CI step, fail on exit 2 |
| 244-252 | 1c example | sample Decision Log table | one sentence |

MUST/NEVER/ALWAYS: none. Keep-list: no rows match. Untrusted input: none.
