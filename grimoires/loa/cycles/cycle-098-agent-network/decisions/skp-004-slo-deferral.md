# Decision: SKP-004 SLO Deferral — operator-signed waiver

**Status**: APPROVED — operator-signed (deep-name / jani@0xhoneyjar.xyz)
**Date approved**: 2026-05-03
**Source**: Sprint 1 PR #693 bridgebuilder kaironic finding F1 (HIGH consensus); SDD pass-#1 SKP-004 SLO target

## Decision

**Sprint 1 ships with audit-envelope write-path SLO miss documented and explicitly waived.** Sprint 2 (ajv path) and Sprint 6 (long-lived JCS daemon) are the technical fixes. This document is the formal operator-signed exception that satisfies bridgebuilder F1's "operator-signed waiver in cycle decisions/" requirement.

## SLO target vs measured

| Quantile | Target (SDD §6 SKP-004) | Measured (Linux, Sprint 1) | Delta |
|----------|------------------------|----------------------------|-------|
| p50 | <30ms | ~280ms | +9× |
| p95 | <50ms | ~309-340ms | +6-7× |
| p99 | <200ms | (per benchmark) | (within order of magnitude) |

**Notable signal**: 1MB payload faster than 100KB payload — variance dominated by `python3` cold-start, not cryptographic work. This is the classic AWS Lambda cold-start curve (Lambda 2019 postmortem). Fix pattern is well-trodden: warm pool / persistent helper.

Benchmark artifact: `tests/perf/audit-envelope-write-bench-results.md`.

## Why ship with this

1. **Operator-tooling, not real-time hot path.** Loa is dev-machine + CI orchestration. L1 panel decisions fire per autonomous-decision (rare), not per-token. Audit envelope correctness is unaffected.

2. **L1 panel decision rate**: estimated 10-100/day at peak operator usage. 300ms × 100 = 30 seconds/day total audit-write overhead. Operationally acceptable.

3. **Correctness > performance for trust-bearing surfaces.** F1 strip-attack was the BLOCKER worth catching. Throughput is a refinement.

4. **The fix is staged, not deferred indefinitely.** Sprint 2 + Sprint 6 each ship a layer of the fix. The SLO target IS reached in cycle-098 — just not in Sprint 1.

## Mitigation plan (the staged fix)

| Sprint | Action | Expected p95 |
|--------|--------|--------------|
| Sprint 1 (this PR) | Ship with documented waiver | ~309-340ms |
| Sprint 2 (#654 L2) | Adopt `ajv` path for schema validation; bypass `python3 -c` for the schema-only validation hot path | ~50-100ms (estimated) |
| Sprint 6 (#658 L6) | Long-lived JCS daemon — startup amortization | <20ms (target) |

## Threat model: what does NOT change

- Audit-envelope correctness (signing, verification, hash-chain, strip-attack defense): unaffected
- Trust-store root-of-trust: unaffected
- L1 protected-class routing: unaffected
- Concurrent write safety (F3 flock): unaffected

The SLO miss is a **performance** concern, not a **correctness** or **security** concern.

## Acceptance criteria for closing this waiver

- [ ] Sprint 2 ships ajv path; benchmark re-runs show p95 <100ms
- [ ] Sprint 6 ships JCS daemon; benchmark re-runs show p95 <20ms
- [ ] If neither lands by cycle-098 close, escalate to cycle-099 P0

## Operator sign-off

By committing this file to the cycle-098-sprint-1 PR, the maintainer (deep-name / jani@0xhoneyjar.xyz) explicitly accepts the documented SLO deviation for Sprint 1 ship and commits to the staged-fix plan above.

This satisfies bridgebuilder F1's "Deliberative Council pattern requires that exceptions enter the audit chain, not the README" — by entering the audit chain via this signed decision document.

## References

- Bridgebuilder F1 finding: PR #693 bridgebuilder iter-1 review comment
- SDD §6 Sprint 1 ACs: SKP-004 SLO target (p95 <50ms)
- SDD §1.4.1 + §3.2: audit-envelope.sh / audit_envelope.py implementation
- Benchmark: `tests/perf/audit-envelope-write-bench-results.md`
- Sprint 1 audit feedback: `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md` (audit accepted SKP-004 disposition; bridgebuilder F1 elevated to "operator-signed waiver" requirement)
