# Run Manifest — RUN-internal-ambiguity-lifecycle

## Identity

- run_id: RUN-internal-ambiguity-lifecycle
- predecessor_run: none
- mode: manual
- created: 2026-08-14
- core_id: aleph-core
- core_version: 0.1.0-provisional
- core_digest: sha256:6d784ae2e3d3278bff03be6ca9fe831b37ec6b1cd62c541ad100da5591e04cec
- adapter_id: core-manual
- adapter_version: 1.0.0-provisional
- adapter_digest: sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
- bundle_id: aleph-fixture-manual
- bundle_digest: sha256:a5d4be73d77e051c929fc5119c0f9d4c833faa6375d23d113cceb00279e912f9
- bundle_lock_ref: control/pinned-core/bundle.lock.json
- checker_digest: sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
- adapter_protocol_version: 1.0.0-provisional
- run_format_version: 1.5.0-provisional
- host_identity: human-operator
- runtime_snapshot_ref: control/runtime/snapshot.json
- runtime_snapshot_digest: sha256:6666666666666666666666666666666666666666666666666666666666666666
- doctrine_sha: 98d0b970601534276a58add14128d740407d8909

## Corpus binding

- corpus_ref: corpus/manifest.md
- corpus_hash: sha256:15c980b0d84d5cb034d9fb449ae3f05b7672b2a413ad31c6e849e5acd0c3c984
- declared_scope: synthetic cumulative internal-ambiguity structural accounting only

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
| 4 | ASSEMBLED | 2026-08-14 09:20 UTC | manual-fixture-assembler | structural lineage-current relation fixture assembled after the S4 closure barrier |

## Authority sign-offs

| gate | decision | by | date | reference |
|------|----------|----|------|-----------|
| S0 corpus scope + sensitivity | fixture-simulated approved; synthetic source only | fixture-simulated authority | 2026-08-14 08:05 UTC | run-log.md S0 exit |
