# HANDOFF — agent-ergonomics pass 1 → pass 2

Pass 1 (2026-07-11, epic bd-m1o6) is complete: 13 recommendations applied
(R-001..R-013), 4 fresh-eyes fixes, ambition bar met (ambition_bar_check.md),
median uplift ≈ +330 on touched dimension-surface pairs, zero regressions.

## What pass 2 should pick up (ranked)

1. **session-limit-capture.sh --help** (help:false in the capabilities table —
   the only agent-facing script left without help). Small.
2. **path-lib LOA_SOUL_SOURCE/LOA_SOUL_OUTPUT unbound-variable stderr noise**
   when LOA_GRIMOIRE_DIR is env-overridden (path-lib.sh:393-394) — the same
   stderr-pollution class the qmd pass fixed; observed while building the
   R-004 tests.
3. **F7/F8/F9 remaining findings from the scorecard** (agent_surfaces.jsonl):
   hook-errors family beyond FR-2 (other BLOCK messages could name
   alternatives), installer family error pedagogy (mount-loa/mount-submodule
   were static-analysis only this pass — must-not-touch guardrail #6 applies).
4. **kf-write-lib duplicate-title guard** near-duplicate bypass
   (trailing-whitespace/synonym titles) — F3 scorer's top regression_resistance
   suspect.
5. **Exit-code dictionaries in --help for the remaining scripts** (grimoire-index,
   memory-query, construct-resolve document codes in comments only).
6. **`br` upstream issue for KF-022** (sync --status dirty-count vs --flush-only
   dirty_count=0 divergence + sticky counter) — file at steveyegge/beads_rust
   (or current upstream); reference the KF-022 evidence.
7. **golden_resolve_truename empty-stdout ambiguity** (F1 finding: legitimate
   no-op vs silent fallthrough are byte-identical; needs a distinct signal).
8. **loa-status --triage --economy interplay**: --economy short-circuits before
   triage; harmless but undocumented. One help-text line.

## How to re-open the loop

1. Read audit/manifest.json (pass 1 summary) + uplift_diff.md.
2. `re-score-only` against the post-pass tree to confirm scores held:
   re-run the Phase 2 scorer prompts over the changed surfaces.
3. The drift gates will tell you if the contract rotted:
   `bats tests/unit/agent-ergonomics-capabilities.bats`.
4. Beads: `br ready` under epic bd-m1o6's children (pass-2 items above).

## Phase 9 note

Fresh-agent simulation ran post-apply (agent_simulations/post_pass_1/);
pre-pass simulation was not captured as transcripts (the intent corpus +
its 40 executed probes in partial/intent_results.jsonl serve as the pre-pass
behavioral baseline instead — loa adaptation, documented).
