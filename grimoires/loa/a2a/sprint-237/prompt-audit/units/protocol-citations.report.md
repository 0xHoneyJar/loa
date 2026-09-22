# Prompt audit report — `protocol-citations`

**Scope**: `.claude/protocols/citations.md` only. **Target model**: Claude Fable 5.1. **Bytes**: 13399 → 9309 (target ≤ 9379).

No row in `tools/prompt-keeplist.txt` / `keep-list.md` targets this path (K-01…K-46 scope CLAUDE.loa.md, review/audit/run-mode SKILL.md, personas, the keep-list bats itself) — every deletion below passes the keep-list check vacuously.

## Findings

| Line(s) | Pattern | Evidence | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| 66-102, one Path-Format variant, one Multi-Line-Citations block | Group 1c example over-indexing | "Configuration / Middleware / Function Signature Citation" — same ❌/✅ template restated | one pinned example generalizes; near-identical repeats cost tokens without new judgment | Medium | remove — consolidated to one JWT example + one ellipsis example |
| 214-252 | Group 1c example over-indexing | "Citation in Different Contexts": PRD/SDD, Implementation Reports, Code Reviews reprint the identical template | format is context-invariant; restating per document type is duplicated boilerplate | Medium | remove, replaced with one sentence noting context-invariance |
| 121-127 + 272-284 | Group 1c padding / Group 2 "info lives in one place" | ellipsis-truncation rule + example given in Code Quote Guidelines, a standalone block, and Edge Case 2 | same instruction and near-identical example stated three times | Medium | consolidate to one instance |
| 455-461 | Group 2 history narrative + brief History rule (`cycle-NNN`) | "1.1 \| 2026-07-29 \| cycle-121: merged unique content of negative-grounding.md…" | authority is the behavior a rule prescribes, not the incident that produced it; `cycle-121` may only live in a Provenance footer | High | remove table; token relocated to Provenance |
| 463-465 | Group 2 history narrative (roadmap pointer) | "**Next**: Integrate into agent skills (Sprint 4)" | stale forward-looking status marker, not an instruction | Medium | remove |
| 406, 422, 441 | Brief History rule (`cycle-NNN` in heading text) | "(merged from self-audit-checkpoint.md, cycle-121)" ×3 | tokens sit outside a Provenance footer / backticked path | High | drop parentheticals; body unchanged; tokens relocated to Provenance |
| 424 | Brief History rule (`KF-NNN`, not the naming-known-failures.md exception) | "(KF-019 class: confabulated absence)" | inline tag, not an instruction naming `known-failures.md`; the two-query rule stands without it | High | remove parenthetical; token relocated to Provenance |

## MUST/NEVER/ALWAYS audit

None deleted. "Every citation MUST include…" (Requirements) and "Do not complete the task if…" (Self-Audit Checkpoint) each name a findable enforcing mechanism stated nearby — the reviewing-code agent's rejection, the Validation grep checks, and the grounding-ratio gate (`>= 0.95`) — so the removal condition ("names no enforcing mechanism") isn't met; both kept verbatim in meaning.

## Untrusted input

None found.

## Deliberately kept though a grep might flag

- `**Source**: PRD FR-5.3` — not a `cycle-NNN`/`#NNNN`/`KF-NNN` token the History rule targets; the only pointer explaining why the protocol exists.
- `Version: 1.0 / Status: Active / Last Updated: 2025-12-27` frontmatter — dated-looking, but no method row cleanly matches static metadata; an untied finding isn't a finding.

## Non-pattern edit

Validation's third check was a non-functional stub (`# Compare citation code with actual line`, no comparison performed). Rewrote as one working instruction — a correctness fix, not cruft removal.

## Residual

None. Proposed file is 9309 bytes, under the 9379-byte target.
