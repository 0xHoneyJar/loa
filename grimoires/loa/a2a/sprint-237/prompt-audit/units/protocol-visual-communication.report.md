# Audit report — `.claude/protocols/visual-communication.md`

**Scope**: single file, as scoped by the brief. **Target model**: Claude Fable 5.1.
**Byte count**: 8276 → 5771 (target ≤5793 met; no residual).

No `MUST|NEVER|ALWAYS|CRITICAL|IMPORTANT` token exists anywhere in the original file (grep-confirmed), so there is no enforcing-mechanism citation to add. No `cycle-NNN`/`#NNNN`/`KF-NNN` token exists in the body (git history shows `#144`/`#68` only in commit messages, never in file text), so no Provenance footer was needed. No row in `tools/prompt-keeplist.txt` targets this path, so no keep-list check applies to any line — removals are judged against the method groups only. No text in the file reads as an instruction to the auditor; it is pure protocol documentation throughout.

## Findings

| Line(s) | Pattern (group/row) | Evidence | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| 3-5 | Group 2, "History narratives: past tense, incident IDs, PR numbers, pinned model names" | `**Version:** 2.0.0` / `**Status:** Active` / `**Date:** 2026-02-02` | Rots the moment the file is next edited without a matching bump; git history already records this | High | remove |
| 9 | Group 1d, "Migration-relative phrasing" | "Version 2.0 introduces a three-mode rendering strategy ... replacing the broken external service dependency" | Diffs against a prompt version the model never saw; rewritten as the current rule only | High | rewrite |
| 219-228 | Group 1c, "Example over-indexing ... judgment the model already owns" | `### Node Naming` Good/Avoid block | Restates General Rule 1 ("descriptive node labels") with a trivial example current models don't need | Medium | remove |
| 305-325 | Group 1d + Group 2, "Migration-relative phrasing" / "History narratives" | `## Migration from v1.x`, "Now outputs GitHub native ... not preview URLs" | Stale diff against a retired prompt version; its one live fact (`include_preview_urls: true`) is already in Configuration Reference | High | remove |
| 43-50 | Step 3 "could the model already know this?" | Diagram Type Selection "Use Case" column ("process flows, decision trees" etc.) | Restates generic, heavily-trained Mermaid knowledge; exact syntax-token column kept | Medium | remove |
| 155-163 | Step 3 / Group 1c padding | Theme table "Description" column ("Dark purple", "Arctic blue") | Restates what the theme ID already implies; "Best For" (non-obvious) kept | Low-Medium | remove |
| 58-110 | Group 1c, duplicated boilerplate / example over-indexing | Same 6-line mermaid block + heading repeated 3× (GitHub Native / Local Render / Preview URL) | Consolidated to one canonical block + a line on how each mode's wrapper differs; zero example content dropped | Medium | rewrite |
| 116-149 | Group 1c, duplicated boilerplate (heading restates the comment) | Four `### Generate ...` subheadings over four bash blocks | Merged into one block; every command/comment retained verbatim — format-only | Low | rewrite |
| 27-41 | Group 1c, heading-as-data | `### Required` / `### Optional` subheadings over two tables | Folded into one `Requirement` column; no agent/diagram mapping dropped | Low | rewrite |
| 193-207 | format-only, no named pattern | Two `npm install` / `npx` bash blocks | Condensed to one sentence, both commands kept; reclaims heading/fence overhead only | Low | rewrite |

## Deliberately kept despite a plausible grep hit

- **"(legacy)" labels** on the URL mode (table, subheading, YAML comment): describe the mode's *current* standing (still supported, discouraged default), not a past-vs-present diff — stay per "write current rules as the only rules that ever existed."
- **Full Script Usage commands and Configuration Reference YAML**: long, but exact tool contract (flags, schema keys) per keep-list item 4 ("tool contract detail stays"); nothing shortened for length alone.
- **`## Integration with Skills` snippet**: confirmed live, not aspirational — `designing-architecture`, `discovering-requirements`, `planning-sprints`, `reviewing-code`, `translating-for-executives` all reference this pattern today.

## Residual

None — proposed file is 5771 bytes, under the 5793-byte target.
