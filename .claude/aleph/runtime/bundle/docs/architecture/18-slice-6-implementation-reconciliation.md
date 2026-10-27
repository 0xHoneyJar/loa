# Slice 6 Formal / Table / Layout Bindings — Implementation Reconciliation

Date: 2026-09-11

Status: PRODUCER-AUTHORED IMPLEMENTATION RECONCILIATION — FRESH INDEPENDENT AUDIT REQUIRED

This record reconciles the bounded implementation with the exact adopted Slice 6
proposal. It is not an independent design or implementation audit. All passing
results below establish only the named structural, checker, fixture, process,
byte-identity, or packaging proposition. No replay validation, semantic
validation, agent sanction, acceptance, production readiness, golden status,
or Aleph v1 is established.

## Exact authority and executable implementation

- Repository: `0xHoneyJar/loa-aleph`.
- Branch: `agent/slice-06-formal-layout-implementation-20260911`.
- Verified starting adoption commit: `e45a1d9b1cafc5ef3b6a1fb46a61a8a395d45770`.
- Starting adoption tree: `3f0ea796e1d8f1b7ad653e16fdf48f78eab50c29`.
- Proposal: `calibration/src-001/core-design-basis/PROPOSED-slice-6-formal-table-layout-bindings-and-degraded-formats-design-20260911.md`.
- Proposal commit: `330cab029687979937177220406868da901189c9`.
- Proposal tree: `0ca565b120a5569f029fbcccd7ecb310f497ab79`.
- Proposal Git blob: `9a09d9224840882cfc5752e68d24fe40464e6a98`.
- Adoption record: `calibration/src-001/core-design-basis/ADOPTED-slice-6-formal-table-layout-bindings-and-degraded-formats-design-20260911.md`.
- Implementation authorization: `calibration/src-001/core-design-basis/AUTHORIZED-slice-6-implementation-20260911.md`.
- Authorization commit: `1a8fcdecb4e554e116828166dc5e806851d9e499`; tree: `2a4a4cc014c9c9d9bce00936dbcc4c24a82f421e`.
- Final executable implementation commit: `31d5e0d66f5ae6c3667ec07e5102ceffeea573e5`.
- Final executable implementation tree: `2240aa6e11c55af913f8770270bcb076f84d1e01`.

The authorization commit is the direct child of the required adoption commit;
the executable implementation commit is its direct child. Repository identity,
branch, ancestry, clean starting tree, exact proposal/adoption, manifest
classification, and carried Slice 5 / OQ-01 authority were checked before
implementation. The authorization record was committed before code changed.
The human implementation declaration remains exactly:

```text
I authorize Slice 6 implementation based on the adopted Slice 6 design.
```

The proposal remains historically PROPOSED. The adoption and authorization
records establish their separate authority without rewriting historical bytes.
The subsequent reconciliation commit adds this record and its Core manifest
entry only. It cannot contain its own Git object identity. The final publication
head/tree and final-head package identities are reported after that commit;
the executable commit and reproduced identities below remain an exact,
reopenable implementation checkpoint, not an alias for the later publication.

## Implemented contract

| Adopted surface | Implementation |
| --- | --- |
| Capability and compatibility | Cumulative `1.6.0-provisional` / `formal-layout-bindings`; explicit registry activation, unknown/injected/downgraded refusal, predecessor behavior and retained pins preserved. |
| Canonical capture | Core T2.3 REP/AST/RPR/OBJ/BND/ASC schema, canonical serialization, strict byte/hash and file closure, supplied descriptor and deterministic ID-map correspondence. |
| Structure and availability | Closed coordinates, pages/regions, table axes/grid/spans/empty cells, ordered and cross-page fragments, states, supplied formal/image/chart material, and one Core availability predicate. |
| Use and review | T3.6 PKT/CC/REL/OBJ receipts, exact basis/subject digests, fidelity refusal, failed-candidate retention, fresh L2F transport and bounded review view, existing verifier spelling mapped to canonical CANNOT_DETERMINE. |
| Deterministic validation | Dedicated read-only K2.18, stable reason tokens, 1.6-only source-walk v2 basis, mechanically derived Précis section 17 limitation union. No semantic model, renderer, OCR, network, or subprocess in K2.18. |
| Host mechanics | Existing public start grammar imports explicit local input closure; S0 capture publication/recovery, opaque resume blocking, Core-planned single-writer transactions, exact preimages/idempotency, and C1 use seal. |
| Prompts and runtime | Verbatim common constraint block, adopted producer return deltas and L2F charter, canonical TypeScript source and generated ES2022 runtime. Hermes remains planned. |

The review view includes the selected objects and structural dependencies,
origin/rendering provenance, packet bytes and selected outputs. Unselected
raw structure exports remain hash-identified without leaking unrelated
object declarations. Capture, declared availability and interpretation remain
separate. Neither an image nor a flattened formal string creates missing
structure. Structural PASS is compatible with the coherent wrong-header
semantic adversary.

## Verification evidence

| Validation | Result |
| --- | --- |
| `git diff --check` / staged check | PASS; final committed tree clean |
| `npm run typecheck` | PASS |
| `npm run runtime:build` / `runtime:check` | PASS; 38 canonical generated files, no drift |
| `npm test` at the executable commit above | PASS, exit 0; no tracked source drift |
| Runtime suite | 6/6 PASS |
| Core boundary | CB1–CB10 PASS; 605 classified paths at the executable checkpoint |
| Worker-return contracts | 14/14 PASS |
| Loa host / adapter / installer | 24/24, 34/34, 17/17 PASS |
| Discovered fixtures | 256/256 checks PASS across 11 declared fixtures |
| Isolated evidence / projection / complete-run validators | All PASS |
| Slice 5 Core contracts / deterministic cases / process | 12/12, 123/123 (106 mutations), 76/76 PASS |
| Slice 6 representation suite | 71/71 PASS, with source/runtime checker parity |
| Slice 6 material process suite | 20/20 PASS; fixture-simulated only |
| Conformance mutations and clean baselines | 117/117 and 11/11 PASS |
| Lineage / typed relation cases | 34/34 and 74/74 PASS |
| Core-boundary / bundle cases | 12/12 and 31/31 PASS |
| Release-package suite | 23/23 PASS |
| Canonical clean assembly / verification / release reproduction | Two assemblies and two releases PASS, byte-identical |
| Installed Node 20.19.5 | Install, verify-install, status PASS; positive and forbidden-gold checker reports equal to TypeScript |

The 71-case material suite includes FX01–FX17, the required mutation families,
source/generated-runtime report comparisons for every checker CLI invocation,
and non-vacuous must-pass pairs. Empty versus unavailable cells, alternate
formal strings/captions/cell and chart values, coherent wrong-header use, and
overlapping regions remain structural positives. Negatives assert the real
checker exit, K2.18 and intended token; the stale source-walk review asserts
K2.14. No deterministic semantic answer key is embedded.

The 20-case process suite uses real retained files, sealed requests, the
existing fixture-simulated worker-return path, and fresh subprocess recovery.
It covers reservation/refusal, exact review, duplicate writes, each material
subject/use/chain/state interruption, partial S0 asset publication and missing
freeze acknowledgement, C1 marker/seal recovery, post-C1 refusal, explicit
input closure, frozen-byte tampering, and repeated opaque-input resume. These
are bounded process results, not canonical production reachability proof.

All 221 pre-existing fixture files match the before-implementation SHA-256
inventory. All 219 prior per-fixture result records are identical. Only the
discovery summary changes from 10 to 11 fixtures; the full discovery now has
256 passing checks. A genuine 1.5 run created by the exact adoption-state code
resumed under both current TypeScript and generated runtime, with all 385
retained runtime files and its identity pins unchanged. A second genuine 1.5
run containing Slice 6 marker strings as source data passed both checkers
without activating K2.18. Missing L2F in a retained 1.5 profile is permitted;
new 1.6 profiles require its adopted mapping.

No historical SRC-001 headers, values, equation reconstruction, expected claim
IDs, or recall quotas entered generic Core code or prompts. Existing references
to withholding calibration answers remain withholding instructions only.
The exact common material constraint block was compared with the proposal.

## Reproduced executable-checkpoint packaging

| Identity | Reproduced value |
| --- | --- |
| Core content | `sha256:87676aa4623ed765514127aa5bb5f9f8a8d343a3bcbe466fd826049ca7bda0cc` |
| Checker content | `sha256:628eaf6e09ebde4690e1d389b40a214f4c097f487ecdd578c0ae61ef780180d3` |
| Loa adapter content | `sha256:f7db89525517e08fa23078d8a2377e14e522b0bff9caedd77a1aa425cf542bed` |
| Loa payload | `sha256:60da8b9ccd59b8234e3720bcd08b8bd21c0eedf75d9b6011bf3845cd94f88df3` |
| Dependency-closure provenance commit | `31d5e0d66f5ae6c3667ec07e5102ceffeea573e5` |
| Dependency-closure provenance tree | `2240aa6e11c55af913f8770270bcb076f84d1e01` |
| Provenance digest | `sha256:947176322dfb4e36459c050c191d49f666d0c1b7c1d060ae2613e88a2f7e91bb` |
| Lock digest | `sha256:e5f0e3286abc2ba815439e36c32ab2c1db473d7ec18b9d86e33bf0d3042f0916` |
| Bundle digest | `sha256:75498d0e397f7810c36ebe1e4c68035d08decd3757997f434a4a7196248167c9` |
| Release archive digest | `sha256:aa853d5974ba253d4523176445613da1c6d72ffa46fe497d5b75babb1d6faabb` |

Version: `0.1.0-provisional`. Both assemblies and both releases pass;
all emitted bytes match across reproductions. The source worktree was clean.
The retained machine-readable report is `/tmp/slice6-code-reproduced-provenance.json`.


Content identity, provenance, lock, final bundle and release archive identity
are distinct. The two clean assemblies and two release packages above were
byte-identical, and each was independently verified by the repository tooling.
The release remains a local structural prerelease, not a published release or
semantic/replay qualification. Adding this Core reconciliation changes the
Core payload; those checkpoint hashes are not claimed for the later final
publication head. Final-head artifacts must be reproduced again after its
commit and identified separately in the publication report.

## Attempt history and limits

Earlier invocation failures were retained rather than relabeled successful.
Restricted subprocess execution returned EPERM; permitted-context reruns were
used. Earlier full runs found fixture scaffolding/permissions errors, then
runtime projection drift while source work was still changing. A later run
found a test assertion incorrectly expecting raw unselected export bytes; the
assertion was corrected. The added cross-page positive initially omitted the
required page byte binding; its fixture was corrected. The staged diff check also found one trailing blank line in the new test
helper; it was removed before commit. The full suite was then rerun on the
clean executable implementation commit, with no source drift. A local packaging attempt used a release version different from the declared
bundle version and was refused. The next verification mistakenly targeted the
parent output directory and was refused; subsequent verification used the
exact emitted release path. Both failed invocations remain retained. No
failure is an independent audit finding or semantic result.

Retained local evidence (SHA-256 over exact log/report bytes):

| Path | Result / role | SHA-256 |
| --- | --- | --- |
| `/tmp/slice6-full-code-head.log` | PASS; full gate at the clean executable commit | `98295fed1486b6a994f4f54307355a3f4e0c98c93920342ff89f862260890412` |
| `/tmp/slice6-code-reproduced-provenance.json` | PASS; exact clean package identities and reproduction | `fb269dda803b54cf66d8e5bc61eb5376a5a67d1ac5dc3c0584bd776d2b69d3c4` |
| `/tmp/slice6-code-node20-report.json` | PASS; exact checkpoint bundle on Node 20 | `c2c80bfd8b322978301c6d6d28ee7664523c03ea8292b585ec967959026209b5` |
| `/tmp/slice6-legacy-comparison-code.json` | PASS; before/after fixture comparison | `3917a125467ffd817abccacc45769c872277706da3d81874966093e8479d49a2` |
| `/tmp/slice6-source-markers-final.log` | PASS; genuine predecessor source-marker compatibility | `e7f6cc99d5b450cd8a6b7db22c60dd795a41fa189f42399691f5b172b8800abe` |
| `/tmp/slice6-full-01.log` | FAILED earlier fixture scaffolding attempt | `24465835a762a410a8ca9e920d522283648b192f4361dc43c8132cfe1ea742ba` |
| `/tmp/slice6-full-02.log` | FAILED earlier fixture scaffolding attempt | `06775669fe545e4d2a3838fc775740c3b81575ae295e7a227c7fb4a1e6f8104e` |
| `/tmp/slice6-full-03.log` | FAILED runtime projection drift during changing source | `d12ecb202dc26f5d72317f620ef599758194978e3880a0a4e354839da8a32d28` |
| `/tmp/slice6-full-stable.log` | FAILED new test assertion about withheld export bytes | `462b00a4c7a6248ccb2f4325f0f464354a716cd4f27dc6ee933eb0a47b79d34a` |
| `/tmp/slice6-representations-expanded.log` | FAILED added cross-page fixture missing its required binding | `6b1b45b02b60238f5c36f1f9c78e3c44b7cf19719cb395ba8eba5e9af72f6d5b` |
| `/tmp/slice6-code-package-1.stdout` | FAILED local release-version mismatch | `6f6cc98e69fbdc9e10255619e2813e0c248e65f1641d151dc45d0fd5693a468b` |
| `/tmp/slice6-code-clean-release-verify-1.stdout` | FAILED verification pointed at parent output directory | `b39d6ec94b6aa7a7b2a18aab48506a670cd9eaa85977eb8f5e7c610a8c1fd7a9` |


| Finding / boundary | Carried status |
| --- | --- |
| F-03 | OPEN: canonical accepted-worker-return → LedgerWriter/orchestrator production reachability remains unproven. |
| F-04 | OPEN: path/case/platform portability remains unresolved. |
| F-05 | OPEN and bounded by F-03: late-correction/lineage production-path reachability remains unproven. |
| S5A4-02 | DEFERRED; broader K2.6/K2.7 activation is not repaired. |
| S5A4-03 | DEFERRED; the pre-existing ad-hoc S3 recognizer is not repaired. |
| S5A2-03 / S5-A-03 | DEFERRED; material-only resume prerequisites do not close generic resume or review-subject invariants. |
| Slice 5 / OQ-01 | MP01–MP08, procedural authority without semantic authorship, immutable Core requirements, non-operative observations, relation/ambiguity boundaries and C1/C2/C3 ordering preserved. |
| Execution | Manual mode remains the only sanctioned mode; all worker/authority test activity was fixture-simulated. Real model calls: none. |
| Exclusions | No general PDF/OCR/vision/renderer or provider/launcher refactor; no Slice 7 or Slice 8 work; no merge. |

No finding is independently closed here. No merged Slice 5 history or preserved
adapter stash/workstream was modified. A fresh independent audit must inspect
the complete final publication range from the starting adoption commit through
the reported final head/tree, including this reconciliation, before merge.

## Changed files at the executable checkpoint

### Core contracts, registry, inventory and build metadata (9)

- `.gitattributes`
- `adapter-protocol/adapter.schema.json`
- `core.manifest.json`
- `package.json`
- `scripts/compatibility-fixture-source.ts`
- `scripts/lib/check-helpers.ts`
- `scripts/lib/run-model.ts`
- `scripts/lib/source-representation.ts`
- `scripts/lib/worker-return-contract.ts`

### Checker and validation (4)

- `scripts/lib/checks-k2-representations.ts`
- `scripts/lib/checks-k2.ts`
- `scripts/test-representation-mutations.ts`
- `scripts/validate-precis-fixtures.ts`

### Prompts (5)

- `docs/architecture/prompts/README.md`
- `docs/architecture/prompts/orchestrator.md`
- `docs/architecture/prompts/verifier-lenses.md`
- `docs/architecture/prompts/workers-intake-extraction.md`
- `docs/architecture/prompts/workers-internal-ambiguity.md`

### Fixtures (44)

- `docs/fixtures/formal-layout-bindings/README.md`
- `docs/fixtures/formal-layout-bindings/inputs/material.txt`
- `docs/fixtures/formal-layout-bindings/inputs/opaque.bin`
- `docs/fixtures/formal-layout-bindings/inputs/table.aleph-representation.json`
- `docs/fixtures/formal-layout-bindings/positive/README.md`
- `docs/fixtures/formal-layout-bindings/positive/arms/stress-test-matrix.md`
- `docs/fixtures/formal-layout-bindings/positive/clusters/pre-cluster-tags.md`
- `docs/fixtures/formal-layout-bindings/positive/clusters/route-cards/README.md`
- `docs/fixtures/formal-layout-bindings/positive/corpus/manifest.md`
- `docs/fixtures/formal-layout-bindings/positive/corpus/representations.md`
- `docs/fixtures/formal-layout-bindings/positive/corpus/sources/SRC-401-source-walk.txt`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/claim-inventory.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/disposition-ledger.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/evidence-roles.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/external-referents.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/extraction-criteria.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/internal-ambiguities.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/lineage.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/merge-map.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/negative-boundaries.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/packet-index.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/relations.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/representation-uses.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/source-walk.md`
- `docs/fixtures/formal-layout-bindings/positive/ledgers/unresolved-queue.md`
- `docs/fixtures/formal-layout-bindings/positive/precis.md`
- `docs/fixtures/formal-layout-bindings/positive/run-log.md`
- `docs/fixtures/formal-layout-bindings/positive/run-manifest.md`
- `docs/fixtures/formal-layout-bindings/positive/synthesis/cluster-synthesis.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1401.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1402.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1403.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1404.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1405.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1406.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1407.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1408.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1409.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1410.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1411.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1412.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1413.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/harness/S4-relations/VER-1414.md`
- `docs/fixtures/formal-layout-bindings/positive/verification/semantic-review-cases.md`

### Loa and planned Hermes adapter metadata (16)

- `adapters/hermes/adapter.manifest.json`
- `adapters/loa/README.md`
- `adapters/loa/adapter.manifest.json`
- `adapters/loa/profiles/loa-default.json`
- `adapters/loa/skill/loa-aleph/SKILL.md`
- `adapters/loa/src/cli.ts`
- `adapters/loa/src/intake.ts`
- `adapters/loa/src/ledger-writer.ts`
- `adapters/loa/src/run-control.ts`
- `adapters/loa/src/runtime-snapshot.ts`
- `adapters/loa/src/types.ts`
- `adapters/loa/src/worker-bundle.ts`
- `adapters/loa/src/worker-return.ts`
- `adapters/loa/tests/test-loa-adapter.ts`
- `adapters/loa/tests/test-representation-process.ts`
- `adapters/loa/tests/test-slice5-process.ts`

### Generated runtime (14)

- `runtime-js/adapters/loa/src/cli.js`
- `runtime-js/adapters/loa/src/intake.js`
- `runtime-js/adapters/loa/src/ledger-writer.js`
- `runtime-js/adapters/loa/src/run-control.js`
- `runtime-js/adapters/loa/src/runtime-snapshot.js`
- `runtime-js/adapters/loa/src/types.js`
- `runtime-js/adapters/loa/src/worker-bundle.js`
- `runtime-js/adapters/loa/src/worker-return.js`
- `runtime-js/scripts/lib/check-helpers.js`
- `runtime-js/scripts/lib/checks-k2-representations.js`
- `runtime-js/scripts/lib/checks-k2.js`
- `runtime-js/scripts/lib/run-model.js`
- `runtime-js/scripts/lib/source-representation.js`
- `runtime-js/scripts/lib/worker-return-contract.js`

### Architecture, templates and checker documentation (12)

- `docs/PRECIS-CONFORMANCE-CHECKER.md`
- `docs/architecture/02-system-architecture.md`
- `docs/architecture/03-artifact-contracts.md`
- `docs/architecture/04-pipeline-stages-and-dod.md`
- `docs/architecture/08-runbook-agent-mode.md`
- `docs/architecture/09-runbook-manual-mode.md`
- `docs/architecture/checker-spec/K1-K2-fixtures-and-runs.md`
- `docs/architecture/checker-spec/README.md`
- `docs/architecture/templates/01-run-control.md`
- `docs/architecture/templates/02-corpus-intake.md`
- `docs/architecture/templates/03-extraction-claims.md`
- `docs/architecture/templates/07-verification.md`

This reconciliation and its single added `files.core` manifest entry are the
only subsequent changes. The authorization record is administrative; the
reconciliation follows the existing Slice 5 Core-document convention.

SLICE 6 IMPLEMENTED — FRESH INDEPENDENT AUDIT REQUIRED BEFORE MERGE
