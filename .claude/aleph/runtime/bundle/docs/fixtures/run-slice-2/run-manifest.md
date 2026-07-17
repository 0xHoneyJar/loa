# Run Manifest — RUN-slice-2

## Identity

- run_id: RUN-slice-2
- predecessor_run: none
- mode: manual
- created: 2026-07-16
- doctrine_sha: 2dc3549a0c6f3fed660b10743198409945c70b64
- doctrine_basis: implementation commit derived from PR #19 and including
  Decision 0003 plus the fixture-backed runbook and contract clarifications
- doctrine_amendments: none outside doctrine_sha
- runbook: docs/architecture/09-runbook-manual-mode.md at doctrine_sha
- publication_pin_status: doctrine, runbook, checker scripts, and fixture
  contracts are pinned to committed implementations; the latest kernel report
  records the TypeScript checker SHA and reproducible content digest

## Corpus binding

- corpus_ref: corpus/manifest.md
- corpus_hash: sha256:ccf27103ab6e9855057688bd861df942feec1597fde0283932bbbcc4f2f606a1
- declared_scope: >
    A bounded synthetic corpus of four source fragments about a token-gated
    access model and its immediate community and growth mechanics. Token-price
    operations, real market conclusions, and downstream document generation
    are outside scope.

## Execution profile

| field | value |
|-------|-------|
| model_ids (per role, exact strings; or "human") | human |
| effort policy deviations | n/a for manual fixture |
| fan-out limits | n/a for manual fixture |
| budgets granted | n/a for manual fixture |
| budgets spent | n/a for manual fixture |

## State log

The timestamps below are synthetic, monotonic fixture chronology. They are not
wall-clock execution, publication, review, or authority evidence.

| # | state | entered | actor | note |
|---|-------|---------|-------|------|
| 1 | DRAFT | 2026-07-16 08:00 UTC | manual-fixture-coordinator | run directory created |
| 2 | CORPUS-FROZEN | 2026-07-16 08:20 UTC | fixture-simulated authority | scope and sensitivity ruling recorded; four source hashes frozen |
| 3 | DISTILLING | 2026-07-16 08:30 UTC | manual-runner | S1 through S10 began |
| 4 | BLOCKED | 2026-07-16 10:10 UTC | manual-runner | awaiting the REF-02 authority scope ruling |
| 5 | DISTILLING | 2026-07-16 10:20 UTC | fixture-simulated authority | re-entered the interrupted state after REF-02 sign-off |
| 6 | ASSEMBLED | 2026-07-16 11:30 UTC | manual-assembler | 17-field projection-neutral Précis assembled |
| 7 | VERIFIED | 2026-07-16 12:00 UTC | fixture-verification-recorder | fixture kernel and harness evidence attached |
| 8 | ACCEPTED | 2026-07-16 12:30 UTC | fixture-simulated authority | structural exemplar accepted for checker development |
| 9 | PROJECTING | 2026-07-16 13:00 UTC | manual-projection-renderer | fixture-simulated product-doctrine cycle began from the accepted Precis hash |
| 10 | PROJECTION-ACCEPTED | 2026-07-16 13:30 UTC | fixture-simulated authority | product-doctrine artifact shape accepted for checker development only |
| 11 | PROJECTING | 2026-07-16 14:00 UTC | manual-projection-renderer | fixture-simulated software-PRD cycle began from the unchanged accepted Precis hash |
| 12 | PROJECTION-ACCEPTED | 2026-07-16 14:30 UTC | fixture-simulated authority | software-PRD artifact shape accepted for checker development only |

## Authority sign-offs

| gate | decision | by | date | reference |
|------|----------|----|------|-----------|
| S0 corpus scope + sensitivity | fixture-simulated approved; no sensitive personal data present | fixture-simulated authority | 2026-07-16 | run-log.md S0 gate entry |
| S8 REF-02 handling | fixture-simulated supplied; financial mandate absent, so CC-107 remains excluded | fixture-simulated authority | 2026-07-16 | run-log.md S8 gate entry and ledgers/external-referents.md REF-02 |
| S9a REF-03 unresolved need | fixture-simulated acknowledged; proceed with explicit taint and no generalization claim | fixture-simulated authority | 2026-07-16 | run-log.md S9a exit entry and ledgers/external-referents.md REF-03 |
| S9b unvalidated machinery | fixture-simulated acknowledged | fixture-simulated authority | 2026-07-16 | run-log.md S9b exit entry |
| S13 Précis acceptance | fixture-simulated accepted as a golden structural exemplar | fixture-simulated authority | 2026-07-16 | verification/audit/independent-audit.md |
| P3 product-doctrine acceptance | fixture-simulated accepted as a projection artifact-shape exemplar | fixture-simulated authority | 2026-07-16 | verification/harness/P3-product-doctrine/VER-0012.md and verification/audit/independent-projection-audit.md |
| P3 software-PRD acceptance | fixture-simulated accepted as a projection artifact-shape exemplar | fixture-simulated authority | 2026-07-16 | verification/harness/P3-prd/VER-0013.md and verification/audit/independent-projection-audit.md |

## Unvalidated-machinery notices

| what ran | why noted | date |
|----------|-----------|------|
| S9b reconciliation shape over REF-02 | No accepted convergent-heavy replay exists; the one-row artifact exercises structure only. | 2026-07-16 |
| Product-doctrine and software-PRD fixture renderings | Their deterministic checks, verifier records, audit, and sign-offs freeze shapes only; they do not prove real output quality or real authority acceptance. | 2026-07-16 |

## Deviations from runbook

| # | what | why | approved-by |
|---|------|-----|-------------|
| 1 | State acceptance and authority rows are marked fixture-simulated. | A golden fixture demonstrates the record shape but cannot create real authority or replay evidence. | Decision 0003 boundary |
| 2 | Fourteen claim-bearing packets are used rather than the handoff's rough sixty-to-ninety estimate. | The bounded corpus contains fourteen claim-bearing paragraphs; overlapping packets would manufacture volume without new re-entry value. | fixture-simulated authority |
| 3 | A routing log is materialized in this manual fixture. | The golden exemplar makes propagation and the REF-02 re-route inspectable; ordinary manual runs may rely on card histories. | fixture-simulated authority |
| 4 | Harness verdicts are fixture-simulated manual records. | They freeze portable evidence shapes; they do not prove an agent verifier capability. | Decision 0003 boundary |
| 5 | Both projection cycles use fixture-simulated verifier, audit, and P3 acceptance records. | The golden exemplar freezes package and gate shapes without claiming real rendering quality or authority acceptance. | Decision 0003 boundary |
