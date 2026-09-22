# Prompt audit report — `.claude/protocols/grounding-enforcement.md`

**Scope**: this file only (protocol, no `resources/`). **Target**: Claude Fable 5.1. **Bytes**: 12309 → 7246 (41% cut; target ≤8616).

No `prompt-keeplist.txt` row matches this path. No `@constraint-generated`/`@skill-include` markers, no `cycle-NNN`/`#NNNN`/`KF-NNN` tokens — no Provenance footer needed. No text read as an instruction to the auditor.

**Top findings**: "Verification Process" reimplemented `grounding-check.sh`'s ratio math inline using a buggier idiom than the real script — the script's own comment names this exact bug class as one it had to fix. Three facts (zero-claim pass, strict/warn/disabled behavior, citation-format validity) each appear 2-3 times in different ASCII/bullet dress, and `## Configuration` is split into two fragments that both open the same top-level `grounding:` key as if they were separate mappings.

## Findings

| Line(s) | Pattern | Evidence | Why obsolete | Conf. |
|---|---|---|---|---|
| 91–126 | 1b: arithmetic the model computes → code | `grep -c '"phase":"cite"' ... \|\| echo "0"` | Duplicates `grounding-check.sh`, which switched to `awk` *because* this idiom double-counts on no-match (its comment names the bug + 2 CI incidents). Verified against the script. | High |
| 128–143, 159–174 | 1c: duplicated rules, "say it once" | "ZERO-CLAIM HANDLING" block; per-level "Configuration Levels" bullets | Restate the Threshold table + `zero_claim_passes` key; facts folded into the table instead of a 3rd/4th copy | Med |
| 145–157 + 319–329 | 1c + schema defect | two `## Configuration` blocks, each opening `grounding:` | Two fragments of one YAML mapping shown as independent blocks; merged (keep-list §8 exempts redundancy only when copies don't disagree with reality) | High |
| 197–207 | 1c: near-duplicate | "Missing Path Prefix" repeats "INVALID (relative path)" verbatim | Same example already under Citation Format | High |
| 391–410 (1–3) | 1c: near-duplicate | Anti-Patterns "Paraphrased/Missing Line/Relative Paths" | Same 3 shapes as Citation Format's "Incorrect Citations"; items 4-5 (assumption flagging, ratio-gaming) are unique, kept | High |
| 303–317 | 1c: example over-indexing | "Decision Log" markdown mockup | Restates High-Ambiguity action + JSONL schema; grepped `*.sh`/`*.bats` for the literal string — no consumer | Med |
| 332–350 | 1c: choreography → prose | `IF unverified_ghosts > 0: BLOCK /clear` pseudocode | Folded into one clause in the Negative Grounding paragraph | Med |
| 444–450 | 1c: generic virtues | "Cite as you go / Use JIT retrieval / Flag assumptions early / Configure appropriately / Review trajectory" | Each restates content stated once elsewhere; "Use JIT retrieval" also names a protocol file that doesn't exist (below) | Med |
| 354–366 | 1c: heavy formatting for behavior | ASCII call-tree | Same call order in one sentence; checked against `synthesis-checkpoint.md`'s step list first | Med |
| 3–4, 464–466 | Grp 2: dates rot / pinned version | `**Version**: 1.0`, `**Last Updated**: 2025-12-27` | Nothing re-verifies it; duplicated across 4 sibling protocol files, actionless here | Med |
| 438 | Grp 2: verify claims against current code | `ck --hybrid ... --top-k 5` | `--top-k` errors on installed `ck` 0.7.0 (`tip: --topk`); this file's own Negative Grounding section already says "`--limit` (not `--top-k`)". Rewrote the flag, kept the example. | High (rewrite) |

No `MUST`/`NEVER`/`ALWAYS` removed — the file has exactly one (`MUST follow this format`, line 40), naming no separate mechanism; it's the Citation Format contract itself, kept as-is.

## Kept despite a plausible grep hit

- **Citation Format (38–71)**, kept whole: `citations.md` covers similar ground but *disagrees* — this file requires a literal `${PROJECT_ROOT}` prefix, `citations.md`'s own example uses a resolved path with no `${PROJECT_ROOT}` token. Keep-list §8 dedupes only when copies agree; flagged for out-of-band resolution, not touched.
- **All `ck`/`grep` command blocks**: real, version-verified tool contract; no `resources/` exists to move detail into (protocol, not a skill).
- **`[JIT Retrieval](jit-retrieval.md)` link**: left untouched. The file doesn't exist anywhere in the repo (only a `CHANGELOG.md` mention). A dangling reference isn't a Groups 1-4 pattern, so no deletion is cited; flagged for the lead to route separately.

## Residual

None — 7246 bytes is under target with headroom; no further cuts made once the target was met.
