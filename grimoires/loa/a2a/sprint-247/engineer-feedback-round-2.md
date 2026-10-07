# Sprint 1 Review Feedback — round 2 (cycle-126, global sprint 247)

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead, unattended) with cross-model dissent re-run per chunk against `58a0c2fc` (chunks a, b, c)
**Date:** 2026-09-25
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 1
**Implementation Report:** grimoires/loa/a2a/sprint-247/reviewer.md

---

## Overall Assessment

The three round-1 findings are resolved in the code (verified below). The re-run dissent on the adapters/metering chunk found one more defect introduced by the round-1 premium fix: the exact-decimal arithmetic now raises on a non-finite multiplier the parser let through. One HIGH; fix before approval.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Robustness — catalog input to the cost path

- **HIGH** (confidence: high) `.claude/adapters/loa_cheval/metering/pricing.py:_long_context_fields` — a non-finite multiplier (`.inf`, `nan`, `1e309`) passes the `> 0` check and `Fraction(str(m))` then raises inside `calculate_total_cost` for every over-threshold request.
**File:** `.claude/adapters/loa_cheval/metering/pricing.py` (`_mult`)
**Issue:** dissent chunk c round 2 DISS-001 (BLOCKING, anchor valid). The parser's contract is "a malformed block means no premium"; a catalog typo must not crash accounting after dispatch.
**Why This Matters:** the ledger row is written after the billed call; an exception there loses the row (or the call's result path) for the most expensive requests.
**Required Fix:** `math.isfinite(m) and m > 0`, else `1.0`; test `inf`, `nan`, `1e309`, negative, zero, non-numeric, `None`.

---

## Observations

None new. Round-1 observations stand (cosmetic `ceiling=0` on an I1 preempt; pre-existing pyflakes residue; dissent coverage process — the chunked re-run is what found this).

---

## Previous Feedback Status

- Round 1 #1 (HIGH, per-hop unverified flag) — **Resolved** in `91838f70`: `_hop_unverified` computed per hop from the hop's entry and fitted budget; both arms consult it; `test_unverified_status_is_per_hop_not_inherited_from_the_head` green; dissent chunk b round 2 clean.
- Round 1 #2 (HIGH, observed-store race) — **Resolved** in `58a0c2fc`: `flock(LOCK_EX)` on `<store>.lock` around load → append → replace; `test_record_observed_is_serialised_across_processes` (4 × 25 → 100 rows) green; dissent chunk a round 2 clean.
- Round 1 #3 (HIGH, premium rounding order) — **Resolved** in `58a0c2fc`: `_premium_cost_micro` floors once after the exact multiply; `test_premium_is_applied_before_flooring_not_to_rounded_categories` green; the follow-on defect above is the only residue.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-247","ts":"2026-09-25T05:05:00Z"} -->
