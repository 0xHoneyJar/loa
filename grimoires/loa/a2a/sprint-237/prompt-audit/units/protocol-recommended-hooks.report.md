# Prompt audit report — `protocol-recommended-hooks`

**Scope**: `.claude/protocols/recommended-hooks.md` only. **Target model**: Claude Fable 5.1. **Bytes**: 11628 → 11737 (**+109**; target ≤8139 not reached — see Residual).

## Summary

This file is Claude-Code-hooks reference documentation (hook types, JSON config examples, exit codes, dev guidelines), not model-behavior-shaping prompt text. Zero instances of `MUST|NEVER|ALWAYS|CRITICAL|IMPORTANT` shouting (grep-verified); no scaffolds, step choreography, prohibition clusters, or output-shaping cadences. Groups 1a/1b/1c/1e/1f essentially don't apply. Both findings below are Group 2 matches; neither reduces bytes — the mandatory Provenance footer plus a factual fix make the file slightly larger.

## Findings

| Line(s) | Pattern | Evidence | Why obsolete | Confidence | Keep-list |
|---|---|---|---|---|---|
| 309–311 | 1d Fossil / History rule | `### 4. Memory Injection Hook — REMOVED (cycle-121)` … `was deleted in cycle-121` | Past-tense + bare `cycle-121` in body text violates "current rules only" and the History rule (cycle tokens survive only in `## Provenance` or a backticked path). No keep-list row names this file — passed. | High | passed |
| 161–167 | 2 Volatile specifics | `"Loa Default Async Hooks"` shows `check-updates.sh` with `"async": true` only | Contradicts the sibling "Loa Default One-Time Hooks" example and the live `.claude/settings.json` `SessionStart` entry, both of which carry `"once": true` on the same script — the two examples disagree (keep-list item 8: dedup/correct only on disagreement). Verified by reading `settings.json`. | Medium | passed |

## Action taken

- **Rewrite** (309–311): heading drops `— REMOVED (cycle-121)`; body states only the current fact (Claude Code auto-memory owns cross-session recall), no history narrative.
- **Rewrite** (161–167): added `"once": true` to the `SessionStart`/`check-updates.sh` entry.
- **Added** `## Provenance` footer (193 bytes, under the 300-byte cap) carrying the removed `cycle-121` token.

No MUST/NEVER/ALWAYS lines removed — none exist in the file. The one near-miss, "**Never async context injection** — Hooks returning `additionalContext` must be synchronous" (line 498), already names its mechanism inline and isn't duplicated; kept as-is.

## Untrusted input

None found.

## Deliberately kept despite grep hits

Version gates `(v2.1.10+)` etc. (tool-contract facts); the `Full Configuration Example` block (re-concatenates three earlier snippets verbatim — checked, they agree, keep-list item 8); the duplicate hooks-docs link in `## Overview` vs `## References` (identical, non-disagreeing); `Patterns from Other Frameworks` and the ×2 "example only" disclaimers (author-only context/caveats, not padding); the 7-item `Hook Development Guidelines` list (each carries its own reason; parallel checklist, not STEP-choreography); the pre-existing duplicate `### 5.` heading (Sprint Completion / Test Auto-Run) — a numbering slip, not a named pattern, left untouched.

## Residual above target

11737 vs. the 8139-byte target — not reached, and in the wrong direction. Nearly all content here is protected under Step 3 ("tool contracts and mechanics") and keep-list item 4 ("tool contract detail stays"): the hook-type table, JSON configs, exit codes, and use-case tables are exactly the reference material the method keeps, not the behavioral-steering prose the patterns target. The two defensible edits net to roughly +109 bytes (History fix ≈ ‑84, factual fix + footer ≈ +193). Per the brief, this is the stop point: a further cut would mean deleting protected contract/example content on volume grounds alone, which the method forbids.
