# Sprint 1 Review Feedback — round 1 (cycle-126, global sprint 247)

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead, unattended `/run sprint-plan`) with cross-model dissent (`adversarial-review.sh --type review`, dissenter `gpt-5.5-pro` → `codex-headless`, run per focused chunk so every changed source file fits the voice's 24K input budget)
**Date:** 2026-09-25
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 1
**Implementation Report:** grimoires/loa/a2a/sprint-247/reviewer.md

---

## Overall Assessment

The sprint delivers what the plan asked for, test-first, with the deviations named in the report and NOTES (per-call knob kept as the override; reasoning flag as a provider-aware union; the count consulted throughout the unverified zone; I1 only for ceiling-bearing entries; input-only provider shape not retried). The report's AC Verification walks every Sprint 1 criterion verbatim (`validate-ac-verification.sh --sprint-id sprint-1` exit 0). Three HIGH defects stand — a chain-walk contract violation, a lost-write race in the observed-bound store, and an under-billing arithmetic order in the premium tier — and must be fixed before approval. Each was surfaced by the chunked cross-model dissent (one also by the reviewer's own read) and reproduced by a failing test before the fix.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — chain fallback contract

- **HIGH** (confidence: high) `.claude/adapters/cheval.py:cmd_invoke` — the unverified-zone flag is computed once for the head entry and reused for every hop, so an ordinary 429 on a fallback hop ends the chain as `RATE_LIMIT_UNVERIFIED` instead of walking.
**File:** `.claude/adapters/cheval.py` (`_ceiling_unverified` read in the `RateLimitError` and `ProviderContextLimitError` arms)
**Issue:** `_ceiling_unverified` is set from the head's pre-flight outcome. After the head fails for a walkable reason, a fallback hop whose own bound is calibrated (or simply larger) runs the same payload verified, yet its 429 is classed `RATE_LIMIT_UNVERIFIED`, is not walked, and a calibration record is written for it. Dissent DISS-001 (BLOCKING, anchor `cheval.py:cmd_invoke`, `anchor_status: valid`) states the same scenario: `[anthropic-large-unverified, provider-B, provider-C]` returns `RATE_LIMITED` on B's ordinary 429 and never tries C. Confirmed independently by the reviewer's own read of the diff before the dissent returned.
**Why This Matters:** the operator's declared chain shape is the contract; a rate-limited fallback must walk. The mis-classification also writes a `RATE_LIMIT_UNVERIFIED` observation for a hop that was never above its bound (harmless to the bound — that class never lowers it — but wrong in the calibration record).
**Required Fix:** compute the flag per hop from THAT hop's entry and fitted budget (`input_bound(hop_entry, max_tokens=hop_budget, …)`: uncalibrated, `estimate > probed`) and use the hop-local flag in both arms; keep the head's flag only for the envelope's `ceiling_unverified`. Add the failing case to `test_ceiling_e2e.py`: head unverified fails walkably → calibrated fallback's 429 walks (`PROVIDER_OUTAGE`, no calibration record); the calibrated fallback's provider verdict is `PROVIDER_CONTEXT_LIMIT`.

### 2. Data integrity — the observed-bound store

- **HIGH** (confidence: high) `.claude/adapters/loa_cheval/routing/ceiling.py:record_observed` — the read → append → `os.replace` cycle takes no interprocess lock, so two concurrent chevals that hit a provider limit can each load the same old store and the later replace discards the earlier row.
**File:** `.claude/adapters/loa_cheval/routing/ceiling.py` (`record_observed`)
**Issue:** temp-file + `os.replace` makes each write atomic for readers but does not serialise writers. Dissent chunk a DISS-001 (BLOCKING, anchor valid); reproduced by the reviewer with 4 processes × 25 appends → 36 of 100 rows survived.
**Why This Matters:** a lost bound-lowering observation lets later calls keep routing over the provider's real limit — the self-correction silently fails.
**Required Fix:** hold `flock(LOCK_EX)` on a sibling lock file from `load_observed` through `os.replace` (the ledger writer's pattern); add the concurrent-writer test.

### 3. Correctness — long-context premium arithmetic

- **HIGH** (confidence: high) `.claude/adapters/loa_cheval/metering/pricing.py:calculate_total_cost` — the premium multiplies already-floored per-category micro-USD costs, discarding each category's remainder before the multiply and truncating again after it.
**File:** `.claude/adapters/loa_cheval/metering/pricing.py` (premium block)
**Issue:** dissent chunk c DISS-001 (BLOCKING, anchor valid): `output_per_mtok=1_250_000`, `output_tokens=3`, `output_multiplier=1.5` → correct `floor(3 × 1.25 × 1.5) = 5`, computed `floor(floor(3.75) × 1.5) = 4`. Underbills every premium row with a non-zero remainder.
**Why This Matters:** the ledger is the cost-of-record for the budget enforcer; a systematic under-count on the most expensive rows is the wrong direction to be wrong in.
**Required Fix:** compute each premium category as `floor(tokens × rate × multiplier / 1e6)` with the multiplier as an exact decimal (`Fraction(str(m))`), keep the remainder and the overflow guard; add the 3-token case as a test.

---

## Observations

### 1. Envelope precision
- **LOW** (confidence: high) `.claude/adapters/cheval.py` (pre-flight preempt branch) — on an I1 preempt (no bound) `PreflightDecision.effective_input_ceiling` is `0`, so the `[preflight] preempt … ceiling=0` line reads oddly; the envelope's `input_ceiling: null` and the reason text are correct. Cosmetic; leave or print `-`.
### 2. Static check residue
- **LOW** (confidence: high) `.claude/adapters/cheval.py:2425`, `loa_cheval/providers/retry.py:341,345` — pyflakes: `_final_entry`, `max_switches`, `provider_switches` assigned and unused. Pre-existing on `main`; not this sprint's.
### 3. Dissent coverage
- **MEDIUM** (confidence: high) process — the first whole-diff dissent saw 24K of 77K tokens and skipped `routing/ceiling.py` (`status_note: not an approval of unreviewed surface`); the review re-ran the dissent per chunk (`adversarial-review-<chunk>.json` kept beside the merged envelope). The Sprint 2 companion voice and the 160K Anthropic budget are the structural fix.

---

## Previous Feedback Status
None (first round).

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":1,"low":2},"excluded":0,"sprint_id":"sprint-247","ts":"2026-09-25T04:40:00Z"} -->
