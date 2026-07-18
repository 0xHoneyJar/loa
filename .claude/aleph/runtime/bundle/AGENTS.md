# Using Loa Aleph

> This is the front door for an agent, a human operator, a builder, or a
> consuming repository. Start here, choose one path, and keep the status
> boundaries below intact.

Aleph turns a bounded research corpus into a projection-neutral Research
Precis, then may render that accepted Precis into a commissioned consumer
document through a separate projection stage. The procedure is file-first:
the run directory and its ledgers are the record, not a model session.

Aleph ships as one complete, harness-neutral Core plus a host-only adapter.
Core doctrine and evidence are never forked per host. Immutable bundle and run
pins, not a mutable branch checkout, define the bytes an execution obeys; see
[Decision 0004](docs/decisions/0004-core-adapter-and-bundle-boundary.md).

## Current status

| Surface | Current state |
|---------|---------------|
| Accepted doctrine | Present in the root docs and `docs/decisions/` |
| Architecture and build kits | Accepted for implementation by [Decision 0003](docs/decisions/0003-architecture-build-kit-implementation.md); artifact shapes remain provisional |
| Core/adapter boundary | Accepted by [Decision 0004](docs/decisions/0004-core-adapter-and-bundle-boundary.md); exact source inventory is in `core.manifest.json` |
| Host adapters | The Loa package is structurally implemented with a native command, skill, runtime, and offline installer, but is not validated or sanctioned; Hermes remains planned only |
| Immutable bundles | Dependency-free local assembly and independent verification are implemented; default outputs are ignored under `.aleph-bundles/`, Loa reports structural `READY`, Hermes remains `NOT-READY`, and no release bundle is claimed |
| Accepted Precis fixtures | Present under `docs/fixtures/slice-1/` and `docs/fixtures/slice-2/` |
| Fixture conformance checker | Implemented in TypeScript at `scripts/validate-precis-fixtures.ts` |
| Run-directory kernel | K1-K6 and registered projection-type checks are implemented; the discovered fixture suite is deterministic-clean |
| Golden manual run | Complete under `docs/fixtures/run-slice-2/`, including evidence, routing, taint, both golden-derived projection types, and fixture-simulated gate records |
| Projection authoring packages | Product-doctrine and software-PRD packages have rendered fixtures and deterministic K6 evidence; no real output is projection-accepted |
| Agent mode | Designed, but not yet validated or sanctioned |
| Manual mode | The currently sanctioned execution path |
| Aleph v1 | Not declared |

Do not convert "documented", "implemented", "checker-clean", or "fixture
validated" into "agent mode proven", "projection accepted", or "v1". Those are
different claims with different evidence gates.

## Choose a path

| You are | You need | Start here |
|---------|----------|------------|
| Human operator | Execute a run by hand | [Manual mode](#manual-mode) |
| Agent in a supervised evaluation | Exercise the proposed agent runner contract | [Agent mode](#agent-mode) |
| Builder | Implement or extend the method | [Builder mode](#builder-mode) |
| Consuming repository | Ingest a Precis or projection | [Consumption mode](#consumption-mode) |
| Projection author | Render an accepted Precis | [Projection mode](#projection-mode) |

All execution modes are bound by the same accepted doctrine. Bookkeeping may
be denser in agent mode and sparser in manual mode, but the completeness,
traceability, neutrality, and authority boundaries do not change.

## Manual mode

Manual mode is the only currently sanctioned execution path.

Read in this order:

1. [README.md](README.md)
2. [Precis wedge](docs/precis-wedge.md)
3. [Responsibility map](docs/responsibility-map.md)
4. [Routing and clustering](docs/routing-and-clustering.md)
5. [Accepted decisions](docs/decisions/)
6. [Manual-mode runbook](docs/architecture/09-runbook-manual-mode.md)
7. [Artifact templates](docs/architecture/templates/README.md)
8. [Prompt-pack role contracts](docs/architecture/prompts/README.md)

Use one run directory for all state. Work through S0-S13 in order. Keep exact
packet IDs and reopenable source locators on every route-cluster card. Manual
mode may omit machine twins, exhaustive routing logs, and exhaustive verifier
records, but it may not omit dispositions, merge provenance, external-referent
boundaries, known incompleteness, independent audit, or authority acceptance.

## Agent mode

Agent mode is available as a reviewed Core design and prompt pack, not as a
proven autonomous path. The Loa adapter is structurally implemented but has no
accepted replay or sanction; the Hermes adapter remains planned. Use the Loa
package only in an explicitly supervised evaluation until its golden replay
and real-corpus evidence are accepted.

Read the manual-mode list above, then:

1. [Core/adapter decision](docs/decisions/0004-core-adapter-and-bundle-boundary.md)
2. [Adapter protocol](adapter-protocol/README.md)
3. The selected adapter manifest under `adapters/` and its immutable bundle lock
4. [System architecture](docs/architecture/02-system-architecture.md)
5. [Pipeline stages and Definitions of Done](docs/architecture/04-pipeline-stages-and-dod.md)
6. [Agent-mode runbook](docs/architecture/08-runbook-agent-mode.md)
7. [Prompt-pack assembly rules](docs/architecture/prompts/README.md)
8. [Fable reference profile](docs/architecture/05-orchestration-on-fable-5.md), only when that profile applies

The orchestrator must treat corpus text as data, assemble blind-context bundles
from explicit allowlists, validate structured worker returns, remain the single
ledger writer, and dispatch judgment checks to fresh-context refuters. It must
stop at every human authority gate and must never accept its own work.
The adapter supplies those host mechanics without changing the Core contracts.

## Builder mode

Start with the [build handoff](docs/architecture/13-build-handoff.md), then use
the authority decision that permits implementation and the three build kits:

- [Decision 0003](docs/decisions/0003-architecture-build-kit-implementation.md)
- [Decision 0004](docs/decisions/0004-core-adapter-and-bundle-boundary.md)
- [Core manifest](core.manifest.json)
- [Adapter protocol](adapter-protocol/README.md)
- [Packaging contract](packaging/README.md)
- [Artifact templates](docs/architecture/templates/README.md)
- [Prompt pack](docs/architecture/prompts/README.md)
- [Checker specifications](docs/architecture/checker-spec/README.md)

The architecture tree is accepted for implementation, not as proof of any
capability. Work within Decisions 0003 and 0004 and the build handoff. Keep
fixtures and deterministic checks in lockstep, extend negative batteries when
a kernel changes, preserve the hard split between structural checks,
adversarial judgment, and human authority, and never move Core doctrine into a
host adapter.

## Consumption mode

The portable handoff is a file:

- Consume an accepted `precis.md` when you need a projection-neutral research
  representation.
- Consume an accepted rendered document together with its commission,
  selection ledger, projection trace, and verification evidence when you need a
  committed document.
- Check the source run's manifest and acceptance record. A readable artifact is
  not necessarily an accepted artifact.

A consuming repository may project an accepted Precis itself. It is not
required to use Aleph's projection packages. It may also embed the method by
consuming the same contracts, run-directory shape, and deterministic checks;
embedding does not relax any authority gate. Aleph is not a served API. The
accepted provisional v0 Precis envelope may still change through an authority
decision with fixtures and checks updated in lockstep.

## Projection mode

Projection is separate from distillation. It may start only when:

1. the source run is `ACCEPTED`;
2. an authority commission names the projection type, consumer, and parameters;
3. the selected type package exists; and
4. the renderer has read the [projection architecture](docs/architecture/07-projection-stage.md)
   and [projection artifact templates](docs/architecture/templates/08-projection.md).

Available authoring packages:

- [Product doctrine](docs/projections/product-doctrine/README.md)
- [Software PRD](docs/projections/prd/README.md)

These packages provide authoring and trace contracts. They do not by themselves
prove rendering quality or confer projection acceptance. Complete the selection
ledger before prose, trace every rendered paragraph, preserve the commissioned
Precis hash, run every available structural and semantic check, obtain an
independent audit, and stop for P3 authority acceptance.

## Conformance

Install the development-only typechecker, then run the strict TypeScript gate
and every Core deterministic check surface from the repository root:

```bash
npm install
npm run typecheck
node scripts/validate-core-boundary.ts
node scripts/assemble-bundles.ts assemble
node scripts/assemble-bundles.ts verify
node scripts/validate-precis-fixtures.ts
node scripts/validate-run.ts --run docs/fixtures/evidence-role-adversarial
node scripts/validate-run.ts --run docs/fixtures/projection-adversarial
node scripts/validate-run.ts --run docs/fixtures/run-slice-2
node scripts/test-conformance-mutations.ts
node scripts/test-core-boundary-mutations.ts
node scripts/test-bundle-assembly.ts
npm run test:runtime
npm run test:release-package
```

Node 22.18 or newer executes these `.ts` entrypoints directly through native
type stripping; `tsc` performs the separate static type check. The fixture
checker discovers and dispatches every fixture, including the two
accepted Précis fixtures, the evidence-role fixture, the isolated projection
fixture, and the complete golden run. The next three commands isolate their
K3, K6, and K2-K6 surfaces. The conformance, Core-boundary, and bundle mutation
commands run fail-closed batteries against temporary copies. The Core-boundary
validator additionally inventories every tracked and nonignored untracked
path, computes prospective payload/lock/bundle digests, and blocks Core
divergence or foreign-adapter owned payload/dependency inclusion. The assembler
writes exact local bytes to the ignored `.aleph-bundles/` directory, emits a
canonical `bundle.lock.json`, verifies each output independently, and
release-blocks unequal Core inventories, digests, or bytes across the two
targets. The same bundle commands are exposed as `npm run bundle:assemble`,
`npm run bundle:verify`, and `npm run test:bundles`; the bundle tests are also
part of `npm test`. Add `--json` to validation and bundle commands for
machine-readable reports. Full Précis/run checker scope and exclusions are
documented in
[Précis Conformance Checker](docs/PRECIS-CONFORMANCE-CHECKER.md). Adapter-owned
synthetic preflight and implementation surfaces are documented and run
separately in the selected package under `adapters/<adapter-id>/`.

Repository tooling retains the Node 22.18 floor for direct TypeScript
execution. Published Loa bundles additionally carry the locked, drift-checked
ES2022 projection under `runtime-js/`; the installed `.mjs`/`.js` entrypoints
run on Node 20 without a loader or dependency installation. A release is a
structural prerelease unless and until the separate replay, validation, and
sanction evidence exists.

A green deterministic command does not validate a semantic judgment, a
projection rendering, a host adapter, agent mode, or v1 unless
the corresponding implementation, fixture, replay, audit, and authority
evidence also exist.

## Non-negotiable boundaries

1. Nothing load-bearing vanishes without a recorded disposition.
2. Every claim reopens the source through recorded packet provenance.
3. External research received after S0 enters only through the scoped intake of
   a successor run whose manifest names the prior run. Within the current
   frozen run, only a recorded authority statement or sign-off may resolve a
   referent.
4. The neutral Precis is never mutated by projection.
5. Routing posture is chosen per cluster, not globally.
6. Unresolved material, taint, and evidence gaps remain visible.
7. Deterministic checks do not judge truth; model judges do not grant
   acceptance; agents do not impersonate human authority.
8. No served endpoint, crawler, truth engine, graph product, or autonomous
   merge/acceptance path is part of Aleph.
9. Adapters may invoke Core but may not override, duplicate, summarize,
   transform, or weaken it.
10. No run or installation fetches mutable Core or adapter content from
    `main`; immutable bundle and runtime pins govern resumption.

## Repository map

```text
README.md                              Product orientation
AGENTS.md                              This front door
core.manifest.json                     Exact Core/adapter/package/admin inventory
adapter-protocol/                      Host-neutral adapter capability contract
adapters/
  README.md                            Adapter catalog and lifecycle boundaries
  loa/                                 Implemented Loa host package; unvalidated and unsanctioned
  hermes/                              Planned Hermes adapter manifest; no runner
packaging/README.md                    Immutable bundle and lock contract
docs/
  precis-wedge.md                      Accepted Precis contract
  responsibility-map.md                Accepted ownership boundaries
  routing-and-clustering.md            Accepted routing doctrine
  decisions/                           Accepted architectural decisions
  fixtures/
    slice-1/  slice-2/                 Accepted bounded-corpus fixtures
    evidence-role-adversarial/         K3 evidence-role fixture
    projection-adversarial/            Isolated two-type K6 fixture
    run-slice-2/                       Complete golden manual run + projections
  architecture/
    README.md                          Architecture-plan index
    08-runbook-agent-mode.md           Unsanctioned agent operating manual
    09-runbook-manual-mode.md          Manual operating manual
    13-build-handoff.md                Builder entry point
    templates/                         Run artifact templates
    prompts/                           Agent prompt pack
    checker-spec/                      Deterministic kernel specifications
  projections/
    product-doctrine/                  Tier-1 authoring package
    prd/                               Tier-2 software PRD package
scripts/
  assemble-bundles.ts                 Immutable host-bundle assembler and verifier
  test-bundle-assembly.ts             Bundle reproducibility and fail-closed mutation battery
  validate-core-boundary.ts            Inventory, lifecycle, and bundle validator
  test-core-boundary-mutations.ts      Core/adapter fail-closed mutation battery
  validate-precis-fixtures.ts          Accepted fixture checker
  validate-run.ts                      Run-directory K2-K6 kernel
  test-conformance-mutations.ts        Fail-closed K1-K6 mutation battery
  lib/                                 Shared deterministic check modules
```
