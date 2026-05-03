# Vision: Test Fixture Realism — Match Production Threat Substrate

**ID**: vision-018
**Source**: Bridgebuilder PR #705 review (cycle-098 Sprint 2), iter-1 finding F8 + iter-2 finding F-006-direct-write — convergent across two iterations as the most architecturally interesting reframe.
**PR**: [#705](https://github.com/0xHoneyJar/loa/pull/705) (cycle-098 Sprint 2 — L2 cost-budget-enforcer)
**Date**: 2026-05-04T00:00:00Z
**Status**: Captured (original_severity: REFRAME)
**Tags**: [test-quality, fixture-realism, fail-closed, fidelity-gap, threat-modeling, sprint-2-bridgebuilder]

## Insight

A test fixture that breaks the chain to simulate an anomaly is testing a different threat than the one production faces. Production's nightmare is a **chain-valid log with semantically anomalous values** — a counter that drifted while signatures stayed correct, or a compromised signer producing valid envelopes with bad numbers. Sprint 2's BATS suite covers `counter_inconsistent` detection by injecting `prev_hash="GENESIS"` records with negative `actual_usd` — convenient, but the chain is broken at the injection point. The realistic attacker constructs entries with **correct** prev_hash chained from prior entries, so chain verification passes, and only the semantic check (negative value, decreasing post, backwards ts) catches the anomaly.

Sprint 1 had a related instance: every BATS suite runs with `LOA_AUDIT_VERIFY_SIGS=0`. The signed-mode happy path is unobserved. Production-default verify_sigs=1 paths can regress silently because no test exercises them. The bridgebuilder named this the "fidelity gap" between test substrate and production substrate — borrowed from Google SRE's framing and Netflix's chaos engineering doctrine ("inject failures at the layer where they actually occur, not at a convenient layer above").

## Potential

The general principle: **threat-model your fixtures.** For each adversarial test, ask:
- What does the actual failure / attacker produce in production?
- Does my fixture match that substrate?
- Or am I testing a more-broken state because it's easier to construct?

For Loa specifically, this surfaces three concrete remediations:

1. **Helper for chain-valid envelope injection.** `_inject_record_call_envelope <log> <payload>` that computes correct prev_hash from the existing tail and emits a properly-chained envelope with the requested anomalous payload. Used by every "anomaly detection" test. Sprint 2's `_l2_compute_counter` consistency check (negative / decreasing / backwards) deserves this treatment.

2. **At-least-one-strict-path rule.** Per safety-sensitive subsystem, at least one integration test runs with all production-default safety flags enabled (verify_sigs=1, signing_key_id set, trust-store populated). The test fixture sets up an ephemeral signing key in setup() and tears down in teardown(). #706 captures this for L2; the same applies to L1 panel-decisions, L4 trust-ledger, etc.

3. **Mutation testing as fidelity validator.** Run mutation testing against the lib and assert the test suite catches each mutation. Mutations that survive reveal where fixtures don't reach the production-realistic threat.

## Connection Points

- Bridgebuilder iter-1 F8 (REFRAME, confidence 0.6) + iter-2 F-006-direct-write (LOW, confidence 0.7) — same insight at two confidence levels
- Bridgebuilder iter-1 F-001 (MEDIUM, confidence 0.87) + iter-2 F-001 (MEDIUM, confidence 0.93) — the signed-mode coverage gap is the highest-confidence single instance
- Issue #706 — signed-mode happy-path coverage for L2 (the concrete first remediation step)
- Lore: `governance-isomorphism`, `deliberative-council`, `fail-closed-cost-gate` — fixtures must be as adversarial as the production threats those gates defend against
- Google Tricorder ISSTA 2018: production-parity test tier
- Netflix Chaos Engineering: inject failures at the actual layer
- Jepsen testing framework (Kyle Kingsbury): per-actor exit-status assertions
- Stripe / AWS KMS: at-least-one-happy-path-test-per-release-branch for security-sensitive modules
- Linux kernel `Fixes:` trailer convention: traceable test-to-finding lineage (Sprint 2 used this pattern via `F-001:`, `HIGH-1:`, etc. test labels)

## Open Questions

- Is the `_inject_chain_valid` helper a Loa-wide primitive or per-primitive helper? (Probably Loa-wide — mirrors the audit-envelope-shared infrastructure pattern.)
- Mutation testing has a runtime cost. Can it run only on PRs touching `.claude/scripts/lib/` or `.claude/scripts/audit-envelope.sh`? (Probably yes — scope to the safety-critical surface.)
- Should bridgebuilder be taught to flag fixture-realism gaps automatically? (Maybe — F8 + F-001 + F-006-direct-write are recurring patterns; bridgebuilder could add this to its lore queries when reviewing test files.)
- Does this vision graduate into a dedicated cycle-099 RFC, or fold into a hardening pass? (Probably hardening pass — the per-primitive remediation steps are well-scoped.)
- Where does this connect to existing rules in `.claude/rules/`? (None currently address fixture realism explicitly. Could become `.claude/rules/test-fixture-realism.md`.)
