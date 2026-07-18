# TypeScript Migration Kernel Report — RUN-slice-2

- checker_version: 027b07908010380f726a1a8c16c3eaa1e19ac0f6
- checker_base_sha: 082d9bae0fb04ecdccee6e2ba5cf98f958204936
- checker_content_sha256: sha256:682afdcab98b1da544e924926c3e133f59cf9b89bfd0a335abdb3fb5ddc98c68
- record_role: publication-ready TypeScript checker capture
- publication_pin_status: checker scripts are committed at checker_version and the content digest matches that commit
- command: `node scripts/validate-run.ts --root . --run docs/fixtures/run-slice-2`
- date: 2026-07-16 15:25 UTC
- result: PASS

## Output (verbatim, complete)

```text
Aleph Run Conformance Kernel
(run: /home/eileenspectremoon/loa-dev/loa-aleph/docs/fixtures/run-slice-2, kind: run)

PASSED CHECKS:
PASS RUN-slice-2 K2.1 (layout): required base and reached-state artifacts are present
PASS RUN-slice-2 K2.2 (manifest): mode, hashes, ordered states, BLOCKED re-entry, and sign-offs are valid
PASS RUN-slice-2 K2.3 (forbidden tokens): fixture run contains zero absolute-forbidden tokens
PASS RUN-slice-2 K2.4 (packet resolution): all packet locators reopen source spans and hashes match
PASS RUN-slice-2 K2.5 (id integrity): every structured ID token resolves to one home definition, except the manifest predecessor field
PASS RUN-slice-2 K2.6 (claim table shape): 10-column claims, claim types, dispositions, packets, and source unions are valid
PASS RUN-slice-2 K2.7 (accounting): all seven rows and total balance over 14 active claims
PASS RUN-slice-2 K2.8 (merge provenance): canonical source sets retain absorbed provenance and absorbed claims are merged
PASS RUN-slice-2 K2.9 (criteria precede packets): criteria timestamp precedes S2 and supersessions have re-extraction records
PASS RUN-slice-2 K2.10 (status discipline): all append-ledger status cells and supersession chains are valid
PASS RUN-slice-2 K2.11 (precis consistency): envelope, neutrality, exact §4 projection, and C1-C8 are consistent
PASS RUN-slice-2 K2.12 (kernel honesty): 3 kernel report(s) have valid results and the latest names the TypeScript checker
PASS RUN-slice-2 K3.1 (edge shape): edge rows have exactly 7 columns and closed vocabulary values
PASS RUN-slice-2 K3.2 (edge resolution): every edge resolves to an active claim and corpus source
PASS RUN-slice-2 K3.3 (removal effect presence): removal effects are present exactly on load-bearing edges
PASS RUN-slice-2 K3.4 (coverage): carried/merged support and inference coverage recomputes with NEITHER=0
PASS RUN-slice-2 K3.5 (decorative counted): decorative and contextual edges do not contribute to support coverage
PASS RUN-slice-2 K3.6 (unverifiable support): no carried claim is confirmed solely by unresolved or non-supporting edges
PASS RUN-slice-2 K3.7 (contradiction preservation): canonical merged claims preserve every absorbed contradictory edge
PASS RUN-slice-2 K3.8 (inference markers resolve): all inference markers target active claims with resolving bases and uncertainty
PASS RUN-slice-2 K4.1 (card shape): every route card has matching IDs, 9 fields, and a 7-signal vector
PASS RUN-slice-2 K4.2 (smallest invariant): every card lists a packet and every card ID resolves
PASS RUN-slice-2 K4.3 (pending posture => REF): pending and resolved referents agree with card posture histories
PASS RUN-slice-2 K4.4 (tags are tags): pre-clusters are exact 3-column tags and never documents
PASS RUN-slice-2 K4.5 (dependency sanity): dependencies resolve and every cyclic edge is explicitly mutual
PASS RUN-slice-2 K4.6 (posture history): every card has history ending at its current posture
PASS RUN-slice-2 K5.1 (taint declaration): every tainted card and unresolved referent declares its impact
PASS RUN-slice-2 K5.2 (gate): no finalization surface claims external completeness without its taint marker
PASS RUN-slice-2 K5.3 (Precis taint honesty): Précis §17 names every load-bearing taint and declined referent
PASS RUN-slice-2 K5.4 (resolution hygiene): every supplied referent names a supplier and authorized intake/sign-off
PASS RUN-slice-2 K6.1 (commission): every commission defines one projection ID and binds its trace and accepted Précis
PASS RUN-slice-2 K6.2 (selection coverage): selection ledgers cover carried/merged and touched-cluster open claims
PASS RUN-slice-2 K6.3 (trace resolution): claim and negative-boundary backing resolve for every statement kind
PASS RUN-slice-2 K6.4 (trace coverage): every rendered paragraph and trace anchor resolve bidirectionally
PASS RUN-slice-2 K6.5 (new claim): every load-bearing projection statement has claim backing
PASS RUN-slice-2 K6.6 (boundary honor): projection traces honor do-not-use and background-only boundaries
PASS RUN-slice-2 K6.7 (open voice): surfaced-open selections and trace anchors name the same sections
PASS RUN-slice-2 K6.8 (taint propagation): tainted projections carry a prominent first-ten-line marker
PASS RUN-slice-2 K6.9 (neutrality both ways): rendered projections leak neither packet IDs nor Précis disposition tables
PASS RUN-slice-2 K6.10 (type contract): registered projection metadata and required section sets are complete

RESULT: PASS
```

This committed checker capture proves that the TypeScript implementation
preserves the golden fixture's deterministic K2-K6 result. The reproducible
checker pin does not prove semantic rendering quality, real independent review,
real authority acceptance, agent mode, or system v1.
