# Run Manifest — RUN-lineage-accounting

## Identity

- run_id: RUN-lineage-accounting
- predecessor_run: none
- mode: manual
- created: 2026-08-14
- core_id: aleph-core
- core_version: 0.1.0-provisional
- core_digest: sha256:1111111111111111111111111111111111111111111111111111111111111111
- adapter_id: core-manual
- adapter_version: 1.0.0-provisional
- adapter_digest: sha256:2222222222222222222222222222222222222222222222222222222222222222
- bundle_id: aleph-fixture-manual
- bundle_digest: sha256:3333333333333333333333333333333333333333333333333333333333333333
- bundle_lock_ref: sha256:4444444444444444444444444444444444444444444444444444444444444444
- checker_digest: sha256:5555555555555555555555555555555555555555555555555555555555555555
- adapter_protocol_version: 1.0.0-provisional
- run_format_version: 1.3.0-provisional
- host_identity: human-operator
- runtime_snapshot_ref: control/runtime/snapshot.json
- runtime_snapshot_digest: sha256:6666666666666666666666666666666666666666666666666666666666666666
- doctrine_sha: 98d0b970601534276a58add14128d740407d8909

## Corpus binding

- corpus_ref: corpus/manifest.md
- corpus_hash: sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984
- declared_scope: synthetic source-walk accounting only

## Execution profile

| field | value |
|-------|-------|
| model_ids (per role, exact strings; or "human") | human |
| adapter profile ID + digest | n/a (core-manual) |
| model/context/effort mapping actually used | n/a (manual) |
| profile deviations | none |
| fan-out limits | n/a (manual) |
| budgets granted (per stage, tokens) | n/a (manual) |

## State log

| # | state | entered | actor | note |
|---|-------|---------|-------|------|
| 1 | DRAFT | 2026-08-14 08:00 UTC | manual-fixture-coordinator | run directory created |
| 2 | CORPUS-FROZEN | 2026-08-14 08:05 UTC | fixture-simulated authority | one synthetic source frozen |
| 3 | DISTILLING | 2026-08-14 08:20 UTC | manual-fixture-runner | source-walk accounting began |
| 4 | ASSEMBLED | 2026-08-14 09:20 UTC | manual-fixture-assembler | structural lineage-current Précis fixture assembled |

## Authority sign-offs

| gate | decision | by | date | reference |
|------|----------|----|------|-----------|
| S0 corpus scope + sensitivity | fixture-simulated approved; synthetic source only | fixture-simulated authority | 2026-08-14 08:05 UTC | run-log.md S0 exit |
