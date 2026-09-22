# Prompt audit — `protocol-danger-level`

**File**: `.claude/protocols/danger-level.md` · **Target model**: Claude Fable 5.1 · **Scope**: this file only (no `resources/`).

**Assumptions**: scope is the single named file; target model per brief is Claude Fable 5.1. No `tools/prompt-keeplist.txt` / `keep-list.md` row matches this path — no byte-for-byte protected strings apply. No `@constraint-generated`/`@skill-include` markers present.

**Byte count**: 9985 → 5698 (43% cut; target was ≤6989, comfortably under).

## Findings

| Location | Pattern (group/row) | Evidence | Why obsolete for Fable 5.1 | Confidence | Keep-list check |
|---|---|---|---|---|---|
| L3-5 header | 1d "History narratives... pinned version numbers" | `**Version**: 1.0.0` / `**Status**: Active` | No enforcement or cross-reference reads these; "Active" has no documented alternate value in this file | Medium | No K-id matches this path — passed |
| L305 footer | 1d, same row | `*Protocol Version 1.0.0 \| Input Guardrails & Tool Risk Enforcement v1.20.0*` | Pure version-pin narrative at EOF; nothing consumes it | Medium | passed |
| L32 comment | History rule (dated provenance not in a Provenance footer) | `<!-- PROTO-002: Synchronized with index.yaml sources of truth (2026-02-06) -->` | Dated, ticket-style comment; the substantive claim (sync source) is preserved implicitly by the Skill Declaration section, the wrapper is not | Medium | passed; not a cycle-/#/KF-token so no footer entry warranted |
| L58-113 | 1c "Bullet walls and heavy formatting for behavioral guidance" + duplicated boilerplate | Two full tables (Interactive Mode, Autonomous Mode) plus two box-drawn UI mockups ("⚠️ High-Risk Skill Confirmation", "🛑 Skill Blocked") | Content is a strict subset of the Decision Matrix (L119-124 orig) already in the file; the mockups add only decorative formatting, not new contract | High | passed — replaced with one summary sentence, no information lost |
| L229-256 | 1c padding/kitchen-sink illustration | "Integration Points" 3 subsections each repeating a header line plus an ASCII/pseudo-code block | Each code block restates its own header sentence; no new mechanism named | Medium | passed — condensed to one prose sentence naming the same three integration points |
| L271-293 | 1c duplicated boilerplate + 1e unprovenanced permissive aside | "Troubleshooting" (3 FAQ items) incl. "pipe `yes` to confirmation (not recommended)" | Duplicates Override Mechanisms (`--allow-high`, critical no override) and Safety Invariant #4 (fail-closed default); the `yes`-piping aside has no provenance and undermines the confirmation gate it sits next to | Medium | passed — the one net-new fact (missing `danger_level` in `index.yaml` triggers fail-closed) folded into Safety Invariant #4 |
| decorative ✅/⚠️/🛑 glyphs in tables | byte-diet formatting, not a named pattern | markers throughout Mode-Specific/Decision Matrix tables | Not tied to a Group 1-4 row; dropped only for byte economy since the boxes carrying them were removed | Low (disclosed, not claimed as a finding) | n/a |

## MUST/NEVER/ALWAYS

- "These invariants MUST NOT be violated" (Safety Invariants, 4 items) — **kept verbatim in substance**. No script/hook is named in this file as the enforcing mechanism, so the removability test in the brief is met, but this list *is* the protocol's entire substantive contract (danger-level semantics), not a generic prohibition wall — kept per the rule against deleting a fence/invariant, unchanged except folding in the Troubleshooting fact under item 4.
- "`critical: always_block` cannot be changed. This is a safety invariant." — kept, tightened to one sentence, same meaning.

## Untrusted input

None found. The file is straight reference documentation; no text addresses the auditing agent or reads as an instruction.

## Kept despite matching a grep

The 17-row "Current Skill Assignments" table matches Group 2's "volatile specifics... nothing re-checks them by default" signal, but it is genuine structured reference data (the Group 1c fix explicitly favors "structure for reference data") and the audit scope excludes verifying it against each skill's `index.yaml`. Kept unchanged; only its dated sync-comment wrapper was removed.

## Residual

None — final size (5698 B) is under the 6989 B target with margin, so no residual to report.
