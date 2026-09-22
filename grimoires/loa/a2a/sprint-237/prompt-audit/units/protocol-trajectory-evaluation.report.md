# Prompt audit report — `protocol-trajectory-evaluation`

**Target**: Claude Fable 5.1. **Scope**: `.claude/protocols/trajectory-evaluation.md` only. No keep-list row matches this path (all scoped to `CLAUDE.loa.md`, 4 verdict-gate skills, 13 routed SKILL.md files, or flatline personas); no registry-rendered markers exist here. No text in the file read as an instruction to the auditor.

**Bytes**: 18,853 → 13,314 (29.4% cut; target ≤13,197). **Residual**: 117 bytes, explained at bottom.

## Findings (highest confidence first)

| Loc | Pattern | Evidence | Why obsolete | Conf. | Action |
|---|---|---|---|---|---|
| 3-5 | 1d fossil | Version/Status/Last-Updated header | Demand-loaded whole file; nothing reads a version tag | High | remove |
| 42-54 | 1b/2 dup | `### XML Format for Agent Reasoning` | Duplicates the later `"phase":"intent"` JSONL entry | High | remove, pointer instead |
| 56-65 | 1c dup prohibition | `### HALT Conditions` (❌ list) | Negates the "Three Required Elements" already stated positively | High | merge |
| 194-227 | 1c/dup | `## Agent Responsibilities` | Restates the phase table; superseded by numeric Self-Audit Checkpoint | High | remove |
| 489-504 | 1c/2 dup | `## Why This Matters` | Restates Purpose's "This catches" from the other direction | High | remove |
| 508/552/581 | 2 pinned tag | `(v0.9.0)` on 3 headings | One version of each schema exists; no disambiguating function | High | remove |
| 398 | 1d history | `(Task 3.8)` | Sprint ID on a script name; not needed to use the script | High | remove |
| 613-625 | 1d/2 fossil | `## Version History` + trailing Status/Next | Version-history + forward-looking TODO | High | remove |
| 20 | 1d history | `Source: PRD FR-5.1, SDD §4.2` | No behavior function; not a cycle/#/KF token | Medium | remove |
| 76-79 | 2 over-index | 3 near-identical path examples | Pattern above already shows the substitution | Medium | remove 2 of 3 |
| 163-169 | 2 dup | "Required pivot fields" bullets | Fields already visible in the JSON example above | Medium | remove |
| 233-239 | 2 over-index | Full EDD test-scenario block | 3 category names are the content, not a format contract | Medium | fold into prose |
| 219-227 | 1c bullet wall | "Trajectory Audit: PR #42" example | Fits one sentence; fake heading adds nothing | Medium | fold into prose |
| 316-326 | 1d unenforced | `## Model Selection Rationale` | No other phase/checkpoint/config references it, unlike every other phase | Medium | remove |
| 250-256 | 1c decorative | ASCII lineage tree | Prose + grep line already state the fact | Medium | remove |
| 407-429 | 1c bullet wall | ✅/❌ Communication Guidelines | Real rule, over-illustrated (3 ex./side) | Medium | 1 example/side |
| throughout | 1a pressure | "MUST articulate", "ANY search" | No mechanism named; unscoped emphasis flattens signal | Medium | plain statement |

## MUST/NEVER/ALWAYS

"MUST articulate" (intent-first search) names no enforcing script → rewritten plainly. `grounding_check`'s "strict mode blocks `/clear` if fail" **does** name its mechanism (strict/warn/disabled toggle) → kept. EDD's "3 test scenarios" matches the live `edd.min_test_scenarios: 3` config default and the `test_scenarios` field → kept, not a dated cap. No other MUST/NEVER/ALWAYS was removed on volume alone.

## Kept though a grep would flag it

All-caps `MANDATORY`/`STOP`/`FLAG` inside **Prevention Rules table cells** — structured reference data, original and unedited. The Grounding Types / Session Handoff / Delta Sync / Grounding Check "Required Fields" tables stayed beside their JSON examples — the `Type` column isn't derivable from raw values. The `mismatch`/`zero_results` JSONL examples — only place those shapes appear. `> Protocol: See ...` pointers to `session-continuity.md`/`grounding-enforcement.md`.

## Residual (117 bytes over target)

Every dated-pattern, duplicate, and unenforced candidate found was removed or rewritten. What remains is JSONL/YAML schema, config keys, and enforcement rules — contract text the method says never to cut. Closing the last 117 bytes would mean shortening table-cell prose for length alone, which the method disallows. Stopping here per the brief's escape clause.
