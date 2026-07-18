# RUN-slice-2 — Golden Manual Run Fixture

```aleph-fixture
kind: run
src_ids: SRC-101..SRC-104
cc_ids: CC-101..CC-114
ledger_total: 14
stm_rows: STM-1..STM-9, STM-10..STM-15
```

This directory is the complete hand-authored run replay of the accepted slice-2
adversarial corpus. It freezes the Markdown artifact shapes that the run kernel
validates while preserving the original four-source, fourteen-claim substance.
It is a synthetic structural exemplar, not a real research result or a claim
that agent mode has been validated.

## Read order

1. `run-manifest.md` and `run-log.md`
2. `corpus/manifest.md`, then all files under `corpus/sources/`
3. `ledgers/extraction-criteria.md`, packet and claim ledgers, then the remaining
   evidence and boundary ledgers
4. `clusters/`, `arms/`, and `synthesis/`
5. `precis.md`
6. `projections/` commissions, selections, renderings, and traces
7. `verification/kernel-report.md`, `verification/sampling-record.md`, harness
   verdicts, and `verification/audit/independent-audit.md`

## Artifact completeness

| area | required evidence | present |
|------|-------------------|---------|
| run control | manifest, append-only state history, log, simulated sign-offs | yes |
| frozen corpus | manifest, four per-source files, source hashes, aggregate hash | yes |
| extraction | criteria predating S2, fourteen reopenable packet locators | yes |
| completeness | fourteen active claims, all seven dispositions, balanced ledger | yes |
| merge | CC-104 absorbs CC-113 and CC-114 with source union retained | yes |
| evidence | nineteen typed edges, six carried/merged claims covered, removal effects | yes |
| boundaries | scope, harm, not-evidence, and no-fabricated-referent rows | yes |
| routing | four tags, four cards, routing log, one supplied and two unresolved referents | yes |
| arms | seven risk rows, eight evidence-removal rows, one disclosed unvalidated reconciliation | yes |
| assembly | cluster synthesis, assembly map, seventeen-field neutral Précis | yes |
| verification | two kernel reports, thirteen verdict records, exhaustive fixture sampling, distillation/projection audit records | yes |
| projection | PRJ-001 product doctrine and PRJ-002 software PRD, exact selections/traces, type checks, simulated P3 records | yes |

## Locator self-check

The accepted `md-lines` rule hashes one-based inclusive complete lines joined
with LF and includes the following LF when the span does not end on the frozen
file's final line.

| source | reopened packet | locator | expected span hash |
|--------|-----------------|---------|--------------------|
| SRC-101 | PKT-0001 | L3-L5 | sha256:b9bd5bd103710c25fc0fa391a22c6bb4ab1348ede0aa30f77b00f4c85552c142 |
| SRC-101 | PKT-0004 | L14-L15 | sha256:f300c3fb6d5c8b983fc324260ae1a56f75294b78650fcd3e1b33c5d4071b1cf8 |
| SRC-102 | PKT-0005 | L3-L5 | sha256:a6db5f3254a320ca364e823a312ccb438d3de6ea5981dd8ef5f4d5d731c9a55d |
| SRC-102 | PKT-0008 | L14-L15 | sha256:3a0390938bfede675567955ff5937683eb75ef5c06dbb5a99c4491b1b2cd8da0 |
| SRC-103 | PKT-0009 | L3-L5 | sha256:a17f931419b31d2a5991a80b4ef865307d380326e82943782755905c20dcfde0 |
| SRC-103 | PKT-0011 | L11-L13 | sha256:312005a6c988b7772f55a32337d712f0307d045f4ecb7225c630de8261f34e5f |
| SRC-104 | PKT-0012 | L3-L5 | sha256:ed0c8a0224753d095dd203b0a42b0cd3253da37e47eb7fb17e2afd2979d1012e |
| SRC-104 | PKT-0014 | L10-L12 | sha256:e931e261f7396304ae240ab321e6eabaf810c9ee0bb179fd77c47a06b3e3b272 |

Two locators per source are shown; the kernel reopens all fourteen.

## Differences from the accepted slice-2 Précis

The accepted fixture at `../slice-2/precis.md` remains frozen. This worked run
preserves its fourteen claim IDs, source unions, merge, seven dispositions,
seven original stress cases, and projection-neutral outcome. The differences
below are deliberate consequences of materializing the full run:

| surface | difference | reason |
|---------|------------|--------|
| corpus inventory | one `corpus.md` became four content-preserving source files plus a hashed manifest; only the blank separators between source sections were omitted by the split | gives every packet a reopenable file and span hash while retaining each source heading and body |
| claim wording | punctuation and a few normalized phrases were regularized; IDs, meaning, source sets, and dispositions did not change | makes the run ledger and four-column Précis projection identical |
| verification summary | now names packet hashes, evidence edges, route cards, referents, sampling, and portable verdict records | the accepted fixture predates those run artifacts |
| stress testing | STM-1 through STM-7 are preserved; STM-8 through STM-15 add evidence-removal attacks | exercises removal effects without changing the original risks |
| synthesis | the accepted narrative is partitioned into four route clusters with explicit tags, dependencies, and postures | makes per-cluster routing and source reconstruction inspectable |
| external referents | REF-01 and REF-03 keep unsupported market/generalization claims tainted; REF-02 records a simulated scope ruling | prevents the worked run from implying external facts the corpus lacks |
| known limits | fixture-simulated governance and the unvalidated reconciliation shape are named explicitly | artifact shapes are evidence, not real audit, authority, or replay capability |

No accepted slice-2 file is modified or superseded by this fixture.

## Claim and disposition self-check

| disposition | claim IDs | count |
|-------------|-----------|-------|
| carried | CC-101, CC-102, CC-103 | 3 |
| merged | CC-104, CC-113, CC-114 | 3 |
| deferred | CC-111 | 1 |
| excluded-with-reason | CC-107, CC-110 | 2 |
| backgrounded | CC-108 | 1 |
| judged-non-load-bearing | CC-109 | 1 |
| unresolved | CC-105, CC-106, CC-112 | 3 |
| total | all active claims | 14 |

## Routing and taint self-check

| case | evidence | expected result |
|------|----------|-----------------|
| contradiction | RC-01 contains CC-105 and CC-106 | adversarial-weighted; claims remain unresolved |
| supplied ruling and re-route | REF-02 supplies the authority scope ruling for RC-03 and CC-107 | RC-03 history moves pending to adversarial-weighted |
| unresolved background referent | REF-01 governs RC-04 and CC-108 | background assertion remains external-referent unresolved |
| unresolved load-bearing referent | REF-03 governs RC-02 and CC-104 | Précis §17 names REF-03 and every downstream use must carry taint |
| tags stay tags | only `pre-cluster-tags.md` defines PC-1 through PC-4 | no pre-cluster document exists |

## Honesty boundaries

- Acceptance, authority, harness, and audit records are explicitly
  `fixture-simulated`; they demonstrate required shapes and do not create real
  governance evidence.
- State and run-log timestamps are synthetic ordinal fixture chronology, not
  wall-clock execution or publication evidence.
- REF-02 is an authority scope ruling, not a supplied financial or market fact.
- REF-01 and REF-03 remain unresolved and visible.
- The reconciliation shape remains unvalidated.
- Projection verifier, audit, and P3 records are also fixture-simulated. They
  validate package and record shapes, not real rendering quality or acceptance.
- PRJ-001 and PRJ-002 are run-local fixture identities defined only by their
  commission rows; they do not imply real publication or acceptance.
- Fourteen packets reflect the fourteen claim-bearing source paragraphs; the
  fixture does not manufacture overlapping packets to meet a rough estimate.
- No schema is frozen and no external truth is claimed. The two downstream
  fixture renderings are not presented as real or accepted outputs.

## Validation

```text
node scripts/validate-precis-fixtures.ts
node scripts/validate-run.ts --root . --run docs/fixtures/run-slice-2
```

The run checker must exit zero and print `RESULT: PASS`.
