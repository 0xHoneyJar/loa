# Enhancements — post-council (2026-07-02)

The original kit (README, ARCHITECTURE, `loa_harness.py`, MANIFEST) was co-designed by Codex + the operator.
This file records enhancements made after a construct-council design pass (ROSENZU · GECKO · EULER · SAATY)
on the memory/recall substrate, plus one fix for a bug reproduced live. All changes are in `bin/loa_harness.py`
and `tests/test_harness.py`; **8/8 unit tests + smoke + `verify` green.** No new dependencies (stdlib only).

## What changed

- **World/zone awareness (Move 1).** Events now carry derived `zone` (system/state/app, from `policy.zones`)
  and `world` (repo basename) columns — additive SQLite migration, chain-safe. `context_message()` was
  rewritten to fill the continuity seam with the *world* instead of the FSM skeleton: it now injects
  `world`, the zone legend, and the **concrete next-gate** (e.g. "to reach SPRINTING, produce sdd.md ≥500
  bytes containing Architecture|Design|SDD") — the pre-computed answer to "what must be legible to move," so
  a weak model reads its position instead of deriving it. Design rationale: *the worldline state IS the
  attention-allocation function.*

- **Atomic append (concurrency fix).** `append_event` now allocates `seq`, reads the head hash, writes the
  jsonl line, and mirrors to SQLite all under one `BEGIN IMMEDIATE` reserved lock (+ busy_timeout). This fixes
  a real seq-collision race — reproduced live: concurrent hooks corrupted a ledger with a duplicate seq. A
  concurrency regression test fires N parallel hooks and asserts unique contiguous seqs. (Marked
  `loa:shortcut`: the lock covers concurrency, not a crash mid-write.)

- **Evidence floor (policy-pin).** `validate_transition_request` now **unions** request-supplied evidence with
  the `policy.default_transition_evidence` floor — the default is always enforced; a request may ADD stricter
  evidence but can never weaken or replace it. Closes the self-attestation hole where an agent authored its
  own trivial passing gate. The substrate holds the gate, not the model's self-authored request.

- **Denial-recall (Move 2).** `recent_denials()` folds the worldline's recent block reasons into the
  continuity ("the wall remembers — do not resubmit these"), so a weak model stops bouncing off a denial it
  can't otherwise see.

## Deferred (by design)

- **scar-recall** — would read a Loa-specific `known-failures.md`; kept out of the portable kit to avoid
  coupling it to Loa. Add when the kit runs inside a Loa project.
- **chDB / OLAP mirror** — the council (SAATY AHP, CR=0.017) ranked it below do-nothing for the model-agnostic
  goal: OLAP is retrospective/operator-facing and a heavy dependency degrades portability. SQLite is correct
  at current volumes; keep a thin query seam and defer the engine to an operator-facing observatory tier.

## Relationship to the review + RFC (both are point-in-time)

`trust-root-review.md` (Ken-Thompson lens) and `rfc.md` reviewed/described the **pre-enhancement** kit; their
`loa_harness.py` line references point at the original file and have shifted.

- **F8** (Stop-transition evidence was a substring in an agent-authored file) — now mitigated in-kit by the
  evidence floor above (default always enforced). The RFC's stronger provenance-bound-evidence direction still
  stands as the upstream plan.
- **Concurrency race** (flagged by the Flatline/BB reviews) — now fixed in-kit (atomic append).
- **F7** (the kit's own event chain is unsigned; a wholesale rewrite re-verifies clean) — **unchanged**. The
  fix remains upstream: emit through Loa's signed `audit-envelope.sh` rather than the kit's own chain, per the
  RFC. The kit's chain stays the portable fallback.

Full design + decisions: the operator's `grimoires/loa/context/harness-memory-council-synthesis.md`.
