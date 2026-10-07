All good

Sprint 1 has been reviewed and approved. Observations documented and non-blocking. See Observations below.

# Sprint 1 Review Feedback (cycle-126, global sprint 247) — round 3, approval

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead, unattended `/run sprint-plan`) with cross-model dissent (`adversarial-review.sh --type review`, dissenter `gpt-5.5-pro` → `codex-headless`) run per focused chunk; round 1 against `7246ae55`, round 2 against `58a0c2fc`, round 3 against `62aab641` / `0df687c8`
**Date:** 2026-09-25
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 1
**Implementation Report:** grimoires/loa/a2a/sprint-247/reviewer.md

---

## Overall Assessment

The sprint delivers every Sprint 1 task and walks every acceptance criterion verbatim with evidence (`validate-ac-verification.sh --sprint-id sprint-1` exit 0). The code was read, not just the report: the ceiling module's basis ordering (calibrated → probed/derived → observed → I1 → guard), the per-hop budget fit and walk gate, the non-walkable provider verdict, the retry layer's single shrink, the adapter defaults / beta-header allowlist / count endpoint / health probe, the catalog additions, the Bridgebuilder generator and reasoning union, the Flatline per-voice budget and the multipass estimator all match the SDD's D-1.1 … D-1.9 as amended by the Flatline dissent, with the deviations named in the report and NOTES (per-call knob kept as the override; provider-aware reasoning union; count consulted throughout the unverified zone; I1 only for ceiling-bearing entries; input-only provider shape not retried).

Four HIGH defects were found across three review rounds — three by the chunked cross-model dissent (one of them also by the reviewer's own read), one by the dissent on the round-1 fix — and every one was reproduced by a failing test before its fix and re-reviewed clean afterwards: the per-hop unverified flag (`91838f70`), the observed-store write race and the premium rounding order (`58a0c2fc`), the non-finite multiplier crash (`62aab641`). A hardening the auditor would have asked for landed as well (`0df687c8`, lock file opened `O_NOFOLLOW`). Whole adapters suite 2413 passed; bats 353/353 on the touched suites and the fence corpus; Bridgebuilder 754/755 with the one failure pre-existing on `main` (KF-036).

Zero critical / high open. The medium below is a process observation on dissent coverage, recorded because it changed how this review was run and because Sprint 2 is where its structural fix lands.

**Verdict:** APPROVED

---

## Observations

### 1. Dissent coverage (process)
- **MEDIUM** (confidence: high) `.claude/scripts/adversarial-review.sh` — the whole-diff dissent saw 24K of 77K estimated tokens, skipped `routing/ceiling.py` by its file-size cap and returned `clean` with `status_note: not an approval of unreviewed surface`. The review re-ran the voice per focused chunk (six chunks, each under the budget); those runs produced the four real findings. `adversarial-review.json` in this directory is the merged envelope (union of each chunk's latest run, `metadata.merged_from_chunks`), the per-chunk envelopes and every rejected-payload sidecar (all empty — hand-checked) sit beside it. KF-011 recurrence and attempt row recorded; Sprint 2's companion voice and the 160K Anthropic budget are the structural fix.

### 2. Envelope precision
- **LOW** (confidence: high) `.claude/adapters/cheval.py` (pre-flight preempt branch) — on an I1 preempt there is no bound, so the `[preflight] preempt … ceiling=0` stderr line reads oddly; the envelope's `input_ceiling: null` and the reason text are correct. Cosmetic.

### 3. Static-check residue (pre-existing)
- **LOW** (confidence: high) `.claude/adapters/cheval.py:2425`, `loa_cheval/providers/retry.py:341,345` — pyflakes: `_final_entry`, `max_switches`, `provider_switches` assigned and unused on `main` before this sprint. Not this sprint's.

---

## Previous Feedback Status

- Round 1 #1 (HIGH, `_ceiling_unverified` inherited by every hop) — **Resolved** in `91838f70`: `_hop_unverified` computed per hop from that hop's entry and fitted budget; both arms consult it; `test_ceiling_e2e.py::test_unverified_status_is_per_hop_not_inherited_from_the_head`; dissent chunk b round 2 clean.
- Round 1 #2 (HIGH, observed-store read/append/replace race) — **Resolved** in `58a0c2fc` (+ `0df687c8` O_NOFOLLOW): `flock(LOCK_EX)` on `<store>.lock` held from load through replace; `test_record_observed_is_serialised_across_processes` (4 × 25 → 100 rows) and `test_record_observed_never_follows_a_planted_symlink_at_the_lock_path`; dissent chunk a round 2 clean.
- Round 1 #3 (HIGH, premium multiplied floored costs) — **Resolved** in `58a0c2fc`: `_premium_cost_micro` floors once after the exact multiply, remainder and overflow guard kept; `test_premium_is_applied_before_flooring_not_to_rounded_categories`.
- Round 2 #1 (HIGH, non-finite multiplier crashes the cost path) — **Resolved** in `62aab641`: `_mult` requires finite and positive; `test_non_finite_or_absurd_multipliers_are_ignored_not_fatal`; dissent chunk c round 3 clean.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-247","ts":"2026-09-25T05:20:00Z"} -->
