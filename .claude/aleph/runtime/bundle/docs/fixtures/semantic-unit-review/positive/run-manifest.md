# Run Manifest — RUN-semantic-unit-review

## Identity

- run_id: RUN-semantic-unit-review
- predecessor_run: none
- mode: manual
- created: 2026-08-13
- core_id: aleph-core
- core_version: 0.1.0-provisional
- core_digest: sha256:7120ceb600c01d27f60aa90873491eb4174943230cb79f2b60f9461ac0565afc
- adapter_id: core-manual
- adapter_version: 1.0.0-provisional
- adapter_digest: sha256:2222222222222222222222222222222222222222222222222222222222222222
- bundle_id: aleph-fixture-manual
- bundle_digest: sha256:04eefc0f7fb1c33096b043f1a78968bace128db0462c3b78ac67b2debd2e6ad5
- bundle_lock_ref: control/runtime/bundle/bundle.lock.json
- checker_digest: sha256:b2ea36dafaa9e285c0865d167985e89641ab92197a2962c7cab817f6f47dc86f
- adapter_protocol_version: 1.0.0-provisional
- run_format_version: 1.7.0-provisional
- host_identity: human-operator
- runtime_snapshot_ref: control/runtime/snapshot.json
- runtime_snapshot_digest: sha256:6666666666666666666666666666666666666666666666666666666666666666
- doctrine_sha: 07cf2a5a843f68e09628a7055e72c304af87f3d0

## Corpus binding

- representation_inventory_hash: sha256:fc8e9a6a0d4836fc140683b1ba4663ceeabe021fce84fab71d854d0cfddf0125

- corpus_ref: corpus/manifest.md
- corpus_hash: sha256:e14a3684de15463f43261a695ef56fc08e8d57b80a9e963a4eee91c2b3fee76b
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
