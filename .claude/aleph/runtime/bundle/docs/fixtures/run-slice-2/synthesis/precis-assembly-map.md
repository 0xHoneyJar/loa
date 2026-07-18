# Précis Assembly Map — RUN-slice-2

| § | envelope field | assembled from | transform |
|---|----------------|----------------|-----------|
| 1 | Corpus scope | corpus/manifest.md Scope | verbatim scope plus fixture-instance note |
| 2 | Source inventory | corpus/manifest.md Source inventory | project source_id, kind, and locus |
| 3 | Extraction method / inclusion criteria | ledgers/extraction-criteria.md | summarize definition, exclusions, granularity, and normalization |
| 4 | Candidate-claim inventory | ledgers/claim-inventory.md | project active rows to claim_id, normalized claim, source(s), disposition |
| 5 | Disposition ledger summary | ledgers/disposition-ledger.md | copy all seven rows and total |
| 6 | Carried claims | ledgers/claim-inventory.md | render active carried rows |
| 7 | Merged claims | ledgers/merge-map.md | render canonical merge and provenance |
| 8 | Deferred claims | ledgers/unresolved-queue.md | render deferred rows |
| 9 | Excluded-with-reason | ledgers/claim-inventory.md | render excluded rows with rationale |
| 10 | Backgrounded | ledgers/claim-inventory.md | render backgrounded rows |
| 11 | Duplicate / merge map | ledgers/merge-map.md | project canonical, absorbs, basis, provenance retained |
| 12 | Do-not-use / negative boundaries | ledgers/negative-boundaries.md | render each active boundary |
| matrix | Stress-test matrix | arms/stress-test-matrix.md | copy STM-1 through STM-7 |
| 13 | Cluster synthesis | synthesis/cluster-synthesis.md | render cluster prose without changing dispositions |
| 14 | Unresolved claims / questions | ledgers/unresolved-queue.md | render unresolved rows |
| 15 | Consumer-deferred projection notes | clusters/route-cards and boundaries | name possible consumer work without generating it |
| 16 | Verification summary | verification/kernel-report.md, harness reports, sampling record | summarize exact fixture evidence and limitations |
| 17 | Known incompleteness / limits | manifest notices, referents, sampling record | carry every taint, simulated sign-off, and unvalidated artifact |

No envelope field required information absent from an upstream artifact.
