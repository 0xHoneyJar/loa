# Run Manifest — RUN-exact-evidence-fragments

## Identity

- run_id: RUN-exact-evidence-fragments
- predecessor_run: none
- mode: manual
- created: 2026-08-13
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
- run_format_version: 1.1.0-provisional
- host_identity: human-operator
- runtime_snapshot_ref: control/runtime/snapshot.json
- runtime_snapshot_digest: sha256:6666666666666666666666666666666666666666666666666666666666666666
- doctrine_sha: 07cf2a5a843f68e09628a7055e72c304af87f3d0

## Corpus binding

- corpus_ref: corpus/manifest.md
- corpus_hash: sha256:fe1adbbd209a4da841cb58c476ef07448d0987bec4be32d7a2182436bc3e6b6f
- declared_scope: synthetic exact-evidence structure only

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
| 1 | DRAFT | 2026-08-13 09:00 UTC | manual-fixture-coordinator | run directory created |
| 2 | CORPUS-FROZEN | 2026-08-13 09:10 UTC | fixture-simulated authority | one synthetic source frozen |
| 3 | DISTILLING | 2026-08-13 09:20 UTC | manual-fixture-runner | exact-evidence packetization began |

## Authority sign-offs

| gate | decision | by | date | reference |
|------|----------|----|------|-----------|
| S0 corpus scope + sensitivity | fixture-simulated approved; synthetic source only | fixture-simulated authority | 2026-08-13 09:10 UTC | run-log.md S0 exit |
