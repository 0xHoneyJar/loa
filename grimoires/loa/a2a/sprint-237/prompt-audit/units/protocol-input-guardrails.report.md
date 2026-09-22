# Prompt audit report — `protocol-input-guardrails`

**Scope**: `.claude/protocols/input-guardrails.md` only. **Target model**: Claude Fable 5.1. **Kind**: protocol.
**Keep-list**: no row in `tools/prompt-keeplist.txt`/`keep-list.md` matches this path — no protected string in this file; no `@constraint-generated`/`@skill-include` markers present.
**Bytes**: 8075 → 7426 (−649, ~8.0%). **Target**: ≤5652 (70%). **Residual**: 1774 B — see "Why the residual."

## Findings

| Line(s) | Pattern | Evidence | Why obsolete | Confidence | Keep-list |
|---|---|---|---|---|---|
| 74 | Group 3 contract mismatch | `"status": "DETECTED"` | Not in schema enum (`PASS\|WARN\|FAIL\|SKIP`); contradicts this file's own rule "Score >= threshold → FAIL" at score 0.85≥0.7 — `rewrite` to `FAIL` | High | n/a |
| 3-4 | Group 2 volatile version pin | `**Version**: 1.0.0` / `**Status**: Active` | No code path reads either; sibling `danger-level.md` carries neither — `remove` | Medium | n/a |
| 330 | Group 2 + 1d version narrative | `*Protocol Version 1.0.0 \| ... v1.20.0*` | Orphaned, unrelated-subsystem version bolted onto footer, unreferenced — `remove` | Medium | n/a |
| 101-138 | Group 1c diagram/bullet duplication | 3 mode diagrams each re-stated by the bullet beneath it | Say it once; also dialed back "Check MUST complete" (1a) — `rewrite` to one prose line/mode | Medium | mode names, config keys, "Use for" lists kept |
| 143-173 | Group 1c step choreography | BLOCK/WARN/Tripwire each a 3-4 item numbered list, no branching | `rewrite` to one sentence/condition | Medium | BLOCK example box kept byte-for-byte (item 7) |
| 181-190 | Group 1c/1d padding | 8-item Load Order list, `─►` on only 2/8 items | Restates Overview diagram at finer grain, inconsistently decorated — `rewrite` to one arrow-chain sentence | Low-Med | every stage + both pointers kept |
| 302-318 | Group 1c step choreography | 2 simple 3-step lists (script failure / invalid config) | No branching to justify numbering — `rewrite` to prose | Low-Med | Fail-Open Rationale sentence kept verbatim |

## Kept though a grep would flag

- L287 "Original PII values are **NEVER** logged." — real data-handling/privacy constraint (1e), not a behavior prohibition.
- L291-298 latency/overhead table (`<50ms`,`<100ms`,`<10%`) — software SLAs for guardrail scripts, not model-output caps (1f is scoped to the latter).
- Both pattern tables, all 4 JSON examples, both YAML config blocks, the env-var block, and the BLOCK example box — tool contract / format-pinning examples (keep-list items 2, 4, 7).

## Untrusted input

The file's own Pattern Categories table contains literal example phrases ("ignore previous", "you are now", "act as") — inert data describing what `injection_detection` flags, not instructions to this auditor. Not followed.

## Why the residual

This is real, implemented-subsystem documentation, not dated model-prompting text — cross-checked against sibling protocol `danger-level.md` and `.claude/schemas/guardrail-result.schema.json` (fields/examples match). After removing every dated-pattern instance findable in Groups 1-4, what remains is tool-contract detail or format-pinning examples that keep-list items 2/4/7/8 forbid cutting absent evidence of obsolescence or disagreement — none exists. Reaching 5652 B would mean deleting real regex patterns or config keys a loader still reads, so I stopped at the honest floor (7426 B) instead of manufacturing a cut.
