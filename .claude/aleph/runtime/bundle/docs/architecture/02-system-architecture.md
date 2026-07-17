# 02 — System Architecture

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md),
> with the Core/adapter boundary fixed by
> [`Decision 0004`](../decisions/0004-core-adapter-and-bundle-boundary.md);
> run files remain canonical and artifact shapes remain provisional.

This document defines the layered architecture of the Aleph Method: the planes
the system is made of, the run directory that carries all state, the identifier
scheme that makes every artifact traceable to source, and the state machine a
run moves through. Stage-level detail lives in
[`04-pipeline-stages-and-dod.md`](04-pipeline-stages-and-dod.md); artifact
field detail in [`03-artifact-contracts.md`](03-artifact-contracts.md).

## 1. The six layers

```
┌──────────────────────────────────────────────────────────────────────┐
│ L6  GOVERNANCE                                                       │
│     roles (authority / coordinator / implementer / auditor),         │
│     PR checkpoints, authority gates, validation ledger               │
├──────────────────────────────────────────────────────────────────────┤
│ L5  RUNNERS                                                          │
│     agent mode (protocol-conforming host adapter)                     │
│     manual mode (human + worksheets + sparse cards)                  │
│     repo-consumption mode (downstream repos ingest artifacts)        │
├──────────────────────────────────────────────────────────────────────┤
│ L4  VERIFICATION STACK                                               │
│     T1 conformance kernel (deterministic, fail-closed)               │
│     T2 verification harness (adversarial model judges)               │
│     T3 human authority review                                        │
├──────────────────────────────────────────────────────────────────────┤
│ L3  PROCESS ENGINES                                                  │
│     distillation engine (stages S0–S13: corpus → Précis)             │
│     projection engine (stages P1–P3: Précis → documents)             │
├──────────────────────────────────────────────────────────────────────┤
│ L2  ARTIFACT SUBSTRATE                                               │
│     run directory, ledgers, cards, IDs, re-entry coordinates,        │
│     run manifest, run log                                            │
├──────────────────────────────────────────────────────────────────────┤
│ L1  DOCTRINE & CONTRACTS                                             │
│     accepted docs (wedge, responsibility map, routing doctrine,      │
│     ADRs), artifact contracts, stage contracts, prompt doctrine      │
└──────────────────────────────────────────────────────────────────────┘
```

Dependencies point downward only. A runner (L5) executes engine stages (L3)
that read and write artifacts (L2) under doctrine (L1), and everything it
produces passes through verification (L4) before governance (L6) accepts it.
No layer reaches around another: an agent never writes to `main` without the
verification stack and a PR checkpoint; the checker never encodes doctrine that
L1 has not accepted; a projection never reads anything but a finished Précis
and its ledgers.

### L1 — Doctrine & contracts

Already largely in place: `docs/precis-wedge.md` (completeness contract, seven
dispositions, v0 envelope), `docs/responsibility-map.md` (ownership),
`docs/routing-and-clustering.md` + ADR 0002 (clusters, arms, derivation trail),
ADR 0001 (projection separation), the fixtures, and the checker doc. This plan
adds three contract families to L1, each pending its own slice:

- **Artifact contracts** ([`03-artifact-contracts.md`](03-artifact-contracts.md))
  — provisional field shapes for every artifact the engines exchange.
- **Stage contracts** ([`04-pipeline-stages-and-dod.md`](04-pipeline-stages-and-dod.md))
  — per-stage inputs, outputs, blind-context rules, and Definitions of Done.
- **Prompt doctrine** (part of
  [`05-orchestration-on-fable-5.md`](05-orchestration-on-fable-5.md)) — the
  rules stage prompts must obey (goal-and-constraints over step enumeration,
  blind context, no invented external facts, refute-first verification).

### L2 — Artifact substrate: the run directory

Every execution of the method — agent or manual — is a **run**. A run is a
directory. Everything the run knows is in that directory; nothing the run
produced is real if it is not in that directory. This is the single most
important structural decision in the plan, because it is what makes runs
resumable, auditable, diffable, checkpointable by PR, and identical in shape
across modes on the canonical Core surface.

Proposed layout (names provisional; frozen only by the slice that first ships
a run fixture):

```
runs/<run-id>/
  run-manifest.md            # who/what/when: corpus ref, mode, model ids,
                             # doctrine versions, budgets, authority sign-offs
  run-log.md                 # append-only narrative: stage entries/exits,
                             # decisions, anomalies, budget spend
  corpus/                    # the frozen bounded input (or a content-addressed
    manifest.md              #   pointer to it) + source inventory + trust classes
    sources/…                # the source files themselves, span-addressable
  ledgers/
    extraction-criteria.md   # inclusion rules recorded before extraction
    packet-index.md          # every packet with re-entry coordinates
    claim-inventory.md       # candidate claims + dispositions (the §4 table)
    disposition-ledger.md    # the §5 summary accounting
    merge-map.md             # duplicate/merge map with provenance
    evidence-roles.md        # claim×source role edges + removal effects
    negative-boundaries.md   # do-not-use boundaries
    unresolved-queue.md      # deferred + unresolved, visible
    external-referents.md    # referent needs, intakes, resolutions
  clusters/
    pre-cluster-tags.md      # tags on packet ids (tags, not documents)
    route-cards/RC-*.md      # one sparse card per route cluster
    routing-log.md           # posture assignments + propagation steps
  arms/
    stress-test-matrix.md    # adversarial arm output (STM rows)
    reconciliations/…        # convergent arm outputs, per cluster
  synthesis/
    cluster-synthesis.md     # presentation-compressed synthesis
  precis.md                  # the assembled projection-neutral Précis
  verification/
    kernel-report.md         # conformance kernel results for this run
    harness/…                # verifier verdicts, per stage, per claim
    audit/…                  # independent auditor findings
  projections/               # produced only by the projection engine,
    tier-1/…                 #   only from a finished, accepted precis.md
    tier-2/…
    traces/…                 # projection traces + selection ledgers
```

The tree above is the canonical Core artifact surface. A host adapter may also
retain a top-level `control/` subtree in the run directory for immutable runtime
snapshots, dispatch and authority journals, checker records, and other durable
resume mechanics. That optional subtree is adapter-owned bookkeeping, not a
Core artifact: it cannot define or satisfy one and is excluded from K2-K6
canonical discovery and content/identifier scans. Only the top-level subtree
has this status; a directory named `control` below a canonical surface remains
in Core-checker scope. Manual mode does not have to create adapter control
bookkeeping.

Rules:

- **Append-over-mutate.** Ledgers grow; corrections are recorded as
  superseding entries with reasons, not silent edits. (The Précis itself is
  assembled fresh each time from ledgers, so it may be regenerated.)
- **The corpus freezes at S0.** After intake, source files are immutable for
  the run. Material received after freeze starts a successor run with a new
  corpus and a manifest that names the prior run. Only an authority statement
  or sign-off may resolve a referent in the current run without changing its
  corpus. This keeps "bounded corpus" honest and packet re-entry coordinates
  stable.
- **Fixtures are miniature runs.** The existing `docs/fixtures/slice-*/`
  triples (corpus/precis/README) are the degenerate ancestor of this layout; a
  future fixture slice ships one full hand-authored run directory as the
  golden example, and the checker learns to validate a run directory the same
  way it validates fixtures today.

### L3 — Process engines

Two engines, cleanly separated per ADR 0001:

- **Distillation engine** — stages S0–S13, corpus → projection-neutral Précis.
  Owns everything up to and including the acceptance checkpoint of the Précis.
- **Projection engine** — stages P1–P3, finished Précis → Tier-1 projections →
  Tier-2 terminal renderings, each with a projection trace. It consumes
  `precis.md` and the ledgers read-only. Tier-2 may additionally consume a
  Tier-1 projection whose trace resolves transitively to that Précis. It never
  runs unless the Précis passed its gate.

Both engines are *procedures*, not processes: in manual mode a human is the
engine. Stage detail: [`04-pipeline-stages-and-dod.md`](04-pipeline-stages-and-dod.md).

### L4 — Verification stack

Three tiers with non-overlapping mandates
(full spec: [`06-verification-and-conformance.md`](06-verification-and-conformance.md)):

| Tier | What | Nature | May block | May never do |
|------|------|--------|-----------|--------------|
| T1 | Conformance kernel (grows out of `scripts/validate-precis-fixtures.ts`) | Deterministic, read-only, fail-closed | Any artifact with broken structure, accounting, references, or boundary violations | Judge semantic truth or research quality |
| T2 | Verification harness | Fresh-context adversarial model judges, quorum rules | Claims/merges/dispositions that fail refutation review → forced to `unresolved` or flagged | Approve acceptance; supply external facts; edit ledgers it audits |
| T3 | Human authority | Judgment | Everything, at the checkpoints | Be bypassed on stance, external referents, acceptance, or anything irreversible |

### L5 — Runners

- **Agent mode** — a protocol-conforming host adapter executes byte-identical
  Core contracts, isolates workers and verifier panels, writes only through
  the run directory's single-writer boundary, invokes the real checker, and
  presents every human gate. The operating contract is
  [`08-runbook-agent-mode.md`](08-runbook-agent-mode.md); document 05 is one
  Fable-specific reference profile, not the universal runner.
- **Manual mode** — the same stages executed by hand at reconstructable
  fidelity: sparse cards instead of materialized graphs, sampled self-checks
  instead of exhaustive panels. Manual:
  [`09-runbook-manual-mode.md`](09-runbook-manual-mode.md).
- **Repo-consumption mode** — downstream repos either ingest a finished Précis
  and project it themselves, or embed the procedure. They depend only on L1
  contracts and L2 artifacts, never on the runners.

**Mode equivalence invariant (hard):** for the same corpus and the same
Core tree digest and run-format version, agent mode and manual mode must produce runs that are
*equivalent under the contracts* — same claim inventory completeness, same
disposition accounting, same traceability — even where they differ in
bookkeeping density (full graph vs sparse cards) and in throughput. Equivalence
is demonstrated on golden corpora, not assumed
(see [`06-verification-and-conformance.md`](06-verification-and-conformance.md) §5).

### L6 — Governance

Carried from the responsibility map and the Straylight precedent:

```
User (Eileen)  = product/architecture authority; approves stance, external
                 referents, acceptance; performs/approves commits and pushes
Coordinator    = interprets, sequences, writes prompts and docs
Claude in repo = repo-local implementation worker (and, in agent mode, the
                 run orchestrator)
Auditor        = independent reviewer (any capable agent/human not the
                 implementer); audit precedes PR
GitHub PRs     = source-of-truth checkpoints
```

**Authority gates** (T3) are fixed points where agent mode must stop and ask,
enumerated in the runbook. The three non-negotiable ones: corpus scope
approval at S0; external-referent supply/resolution whenever the compositional
gate demands it; and acceptance of the Précis (and of each projection) at the
checkpoints.

## 2. Identifier scheme and re-entry coordinates

Traceability is only as strong as the IDs. Proposed scheme (provisional):

| ID | Names | Assigned at | Points to |
|----|-------|-------------|-----------|
| `RUN-<slug>` | a run | S0 | the run directory |
| `SRC-NNN` | a source in the corpus | S1 | a file (or file section) in `corpus/sources/` |
| `PKT-NNNN` | a packet: a contiguous source span elevated during extraction | S2 | `SRC-NNN` + span locator + content hash |
| `CC-NNN` | a candidate claim | S3 | ≥1 `PKT-NNNN` |
| `NB-N` | a negative boundary | S5 | one row in `ledgers/negative-boundaries.md` |
| `PC-N` | a structural pre-cluster tag | S7 | a tag written against packet/claim ids — never a document |
| `RC-NN` | a route cluster | S8 | a sparse card listing exact `PKT`/`CC` ids |
| `STM-N` | a stress-test matrix row | S9 | `CC`/`SRC` refs under test |
| `REF-NN` | an external referent record | S8+ | need → intake → resolution |
| `VER-…` | a verifier verdict | any judged stage | the artifact judged |
| `PRJ-NNN` | a projection output | P1 commission | the commission row binding `precis.md` + one projection trace |

Rules (extending the wedge's existing `SRC`/`CC`/`STM` practice):

1. **Every ID resolves.** A cited ID that does not exist in its fixed home is a
   T1 failure (the existing C1/C4/C7 checks generalize to all ID families).
   `RUN-*` is defined by the manifest `run_id`; `NB-*` by the negative-boundary
   ledger; and `PRJ-*` by exactly one commission `projection_id` row. Rendered
   projection metadata and traces cite, but do not redefine, that `PRJ-*`.
   A successor manifest may name one `predecessor_run`; this is an explicit
   cross-run reference, not a second local definition. The run-local kernel
   validates its shape but does not claim to locate or hash-verify the prior
   run directory.
2. **Packet IDs are re-entry coordinates, not citations** (routing doctrine
   §9). A packet record must carry enough to *reopen the exact source span*:
   source ID, a span locator appropriate to the source format, and a content
   hash of the span so drift is detectable. The concrete locator scheme per
   source format (markdown line ranges, chat-export message indices, PDF page
   +offset) is an open question to settle in the run-fixture slice — see
   [`12-risks-open-questions-do-not-build.md`](12-risks-open-questions-do-not-build.md).
3. **IDs are stable within a run.** Re-running a stage must not re-number
   surviving entities. Mechanism (proposed): IDs are assigned once, recorded
   in the ledger with the content hash of the underlying unit; a re-run
   matches by hash, reuses the ID, and appends rather than rewrites.
4. **IDs are never reused.** A retracted packet/claim keeps its ID with a
   superseding note; the ID never points at new content.

## 3. The run state machine

A run advances through states; the manifest records every transition with a
timestamp and the actor.

```
DRAFT ──► CORPUS-FROZEN ──► DISTILLING ──► ASSEMBLED ──► VERIFIED ──► ACCEPTED
                                 │              │            │           │
                                 │              │            │           └──► PROJECTING ──► PROJECTION-ACCEPTED
                                 │              │            │                         ▲             │
                                 │              │            │                         └─────────────┘
                                 │              │            │
                                 ▼              ▼            ▼
                              BLOCKED (external referent / authority gate / budget)
                                 │
                                 ▼
                              (resumes where it stopped — never restarts silently)
```

- `DRAFT` — run created, corpus intake in progress (S0).
- `CORPUS-FROZEN` — scope approved by authority; sources immutable (end S0).
- `DISTILLING` — S1–S10 in progress; may oscillate with `BLOCKED`.
- `ASSEMBLED` — `precis.md` assembled (S11).
- `VERIFIED` — T1 kernel green and T2 harness report attached (S12).
- `ACCEPTED` — authority accepted at the PR checkpoint (S13). Only now may the
  projection engine run.
- `PROJECTING` — one authority-commissioned projection is being rendered and
  verified. A run may re-enter this state from `PROJECTION-ACCEPTED` for a
  later commission.
- `PROJECTION-ACCEPTED` — the commissioned projection passed P3 audit and
  authority acceptance. The accepted Précis remains immutable and another
  projection may be commissioned.
- `BLOCKED` — waiting on a human: unresolved external referent on a
  load-bearing cluster, an authority gate, or an exhausted budget. Blocking is
  a normal state, not a failure; the run log records what is awaited.

**Resumability invariant:** any run can be resumed by any compatible runner
(the same agent, a different agent, or a human) from the run directory plus
its original immutable bundle lock and runtime snapshot. If resuming requires
unrecorded information or newer mutable bytes, that is a defect.

## 4. Where this runs (and where it deliberately does not)

- **Primary target: immutable host bundles.** `aleph-for-loa` and
  `aleph-for-hermes` each contain the same complete Core bytes plus only their
  selected adapter. A native host may provide checkpointing, workers, skills,
  or scheduling, but those are adapter/profile mechanics and may not alter
  Core.
- **Other hosts remain possible through the same protocol.** They must consume
  frozen Core bytes, produce the same run-directory contracts, pass full-mode
  preflight, and earn validation and sanction independently.
- **Never: mutable branch deployment.** A run does not sync or fetch `main`;
  it pins a bundle, checker, adapter, host/model identity, and runtime snapshot.
- **Never: a served endpoint.** Endpoint surfaces, if they ever exist, project
  from artifacts; they are out of scope for this plan entirely (responsibility
  map, and the do-not-build list in
  [`12-risks-open-questions-do-not-build.md`](12-risks-open-questions-do-not-build.md)).

## 5. Trust boundaries

Four boundaries the architecture treats as hard:

1. **Corpus ↔ pipeline.** Corpus content is untrusted input: it may contain
   instructions, injections, or synthetic sources. Stage workers treat corpus
   text as data, never as instructions; the source inventory records a trust
   class per source; nothing in the corpus can widen scope, alter doctrine, or
   trigger actions. (Grounding: agentic-workflow-injection literature via
   issue #18.)
2. **Generation ↔ verification.** Verifiers get fresh context and refute-first
   prompts; they never see "the answer is probably right" framing, and where
   the design calls for independent re-derivation they do not see the original
   worker's verdict at all.
3. **Distillation ↔ projection.** The projection engine has read-only access
   to a finished, accepted Précis. No back-edits, ever (T4).
4. **Aleph ↔ the rest of the stack.** Business/market intelligence stays out
   (the concern of a future adjacent consumer); product surfaces stay out
   (Freeside's). The method may *record* that a cluster needs a competitor
   referent; supplying competitive analysis is not its job.
