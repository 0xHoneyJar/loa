# dissent-rejected — the real rejected payloads (cycle-126 Sprint 2, PRD FR-2.2, SDD D-2.2 / D-2.4)

Three findings a cross-model dissenter actually produced and `adversarial-review.sh`
silently dropped for a trivial schema mismatch (`missing-or-empty-failure_mode`,
KF-004 class), copied verbatim from the sprint-237 and sprint-247 rejected sidecars
with a `_fixture` header added. Two were later judged real defects by a lead.

They drive two tests:
- `tests/unit/adversarial-review-normalise.bats` — the normaliser derives
  `failure_mode` from the first sentence of `description` (`failure_mode_derived: true`)
  and every one becomes a finding without a repair round-trip.
- the repair-loop case in the same file — with the normaliser bypassed and a stubbed
  repair model, the repair path still recovers them.

`payload` is exactly what the model returned (after the case-fold normaliser). Add a
new fixture only from a real sidecar row, never a hand-written one.
