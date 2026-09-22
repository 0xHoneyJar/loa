# Prompt audit — `.claude/protocols/ride-translation.md`

**Scope**: this file only. **Target model**: Claude Fable 5.1. **Bytes**: 8426 → 5893 (target ≤5898).

No keep-list row matches this path/glob; no `@constraint-generated`/`@skill-include` markers present. Nothing in the file reads as an instruction aimed at the auditor — it's a self-contained workflow spec.

## Findings

| Line(s) | Pattern | Evidence | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| 34–55 | 1c/row5 repetition-as-reinforcement | ASCII "Execution Sequence" diagram | Restates the Phase 0–8 sequence given in full immediately below, zero new info | High | remove |
| 9–17 | 1c/row5 padding/duplication | "Enterprise Standards" table (AWS Projen/Anthropic/Google ADK) | Every cell elaborated in full later (Phase 0/1/3/7, Truth Hierarchy); vendor attributions add no verifiable/operational content | Medium | remove |
| 19–32 | 1c/row4 heavy formatting for behavior | `+---+` box art, "CODE WINS ALL CONFLICTS. ALWAYS." | One-sentence invariant in ASCII art; rewritten as prose carrying the same rule at a fraction of the bytes | High | rewrite |
| 126–130 | 1c/row5 repetition-as-reinforcement | Weight table (50/30/20) vs identical code comments | Same three weights stated twice; merged the table's only unique content (source paths) into the code comments, dropped the table | High | rewrite (merge) |
| 221–233 | 1c/row5 + keep-list #10 boundary | 9-item "Verification Checklist" | Restates every one of the 8 phases' requirements with zero new fact — a full second copy of the protocol, not "a recap of the few key constraints" | Medium | remove |
| 179–186 | 1c/row5 repetition-as-reinforcement | "Quality Gates" table | 3 of 4 rows restate Phase 0 exit-1, Phase 7 G3, Phase 7 G5; kept the one non-duplicate fact (completeness threshold) as a sentence, dropped the table | Medium | rewrite |
| 1 | Group 2 volatile specifics | `v2.0` in title | Not Fable-5.1-specific; low-confidence idiom-dating, cut anyway (zero-risk, nothing in-file depends on it) | Low | remove |

## MUST/NEVER/ALWAYS audit

- `CODE WINS ALL CONFLICTS. ALWAYS.` — no named mechanism (judgment principle); rewritten plainly ("Code wins every conflict"), meaning unchanged.
- `**BLOCKING** if integrity_enforcement: strict` (Phase 0) — **kept verbatim**: mechanism is the `exit 1` in the same code block.
- `**MANDATORY** before completion.` (Phase 7) — no mechanism named; folded into a plain instruction sentence rather than deleted, since the underlying requirement (produce `translation-audit.md`) is real.
- `Every claim MUST use citation format` — **kept** ("Every claim must use one of these formats"): enforced in-file by Phase 7's G1/G2 checks.

## Kept despite a grep hit

All bash blocks kept byte-exact (fragile-operation rule). Audience Adaptation Matrix, Grounding Protocol table, Phase 2 table, Output Structure tree kept as format-pinning/tool-contract data. The "Reject audit" consequence (dropped from Quality Gates) was not restored elsewhere: redoing a miscalculated formula is an obvious corrective action a capable model takes unprompted (Step 3 test). Once the vendor-standards sentence was cut from `## Overview`, that section became a verbatim restatement of the blockquote above it, so the section itself was removed as self-inflicted duplication.

No residual above target.
