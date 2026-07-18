# Decision 0002 — Routing is per-cluster, not a global stance

- **Status:** Accepted — provisional / known-limits recorded
- **Date:** 2026-06-29
- **Authority:** Eileen (product / architecture authority), explicit approval
- **Relates to:** `docs/precis-wedge.md` (refines the `cluster synthesis` step of the
  completeness trail), `docs/responsibility-map.md`, `docs/decisions/0001-projection-as-separate-downstream-stage.md`
- **Companion doctrine:** `docs/routing-and-clustering.md` (the full model this ADR ratifies)
- **Implementation update:** [Decision 0003](0003-architecture-build-kit-implementation.md)
  authorized the fixture-backed K4/K5 checks after this decision's prerequisite
  was met. This decision's routing doctrine remains in force.

## What "Accepted — provisional / known-limits recorded" means here

This status is deliberate and bounded. It means:

- **Accepted** as Aleph's *current* routing and manual-mode doctrine. Future doctrine
  slices may depend on this model.
- **NOT** accepted as proof that all routing arms are validated. The convergent-heavy arm
  remains explicitly unvalidated (see Known limits below and the validation ledger in the
  companion doc).
- **NOT**, at this decision's acceptance date, accepted as a
  checker-enforceable schema. No conformance check then enforced routing,
  clustering, or derivation cards, and none could be added until a fixture /
  replay case existed. The later fixture and K4/K5 implementation satisfy that
  prerequisite without converting semantic routing judgment into T1 code.
- **NOT** permission to build an extractor, generator, tooling, or any runtime. This ADR
  authorizes doctrine only.

The acceptance is real enough to build *doctrine* on, and bounded enough that it cannot be
mistaken for validated machinery.

## Context

The accepted Précis wedge (`docs/precis-wedge.md`) ships a completeness trail whose late
steps include a single step named **`cluster synthesis`**, treated as one undefined object.
Everything downstream of it — matrices, handoff packets, and the separate projection stage
(ADR 0001) — depends on *how clusters form and how they are routed*, yet the repo never
defined that.

Two failure modes had to be avoided:

1. **A single global stance.** Modelling a whole corpus as "novel" *or* "known-domain" *or*
   "hybrid" is too coarse. It forces the user to declare, up front, something Aleph is
   supposed to help surface — and it collapses the real per-region structure of a corpus
   into one label.
2. **Letting the agent invent external facts.** Whether prior art / competitors / reference
   architectures exist is not a property of the corpus. The corpus alone cannot prove
   novelty. An agent that decides stance by itself can confabulate novelty it never verified.

## Decision

1. **Aleph rejects a single global novel / known-domain / hybrid stance.**
2. **Aleph adopts per-cluster routing over layered cluster objects** (packet index →
   structural pre-cluster → route cluster → output cluster), with two always-available arms
   (adversarial / convergent) whose *weighting* — not whose existence — varies per cluster.
3. **Aleph accepts manual-mode reconstructability as sufficient for hand-authored use.** A
   human keeps sparse derivation cards, not an exhaustive edge-maintained graph.
4. **The full derivation graph belongs to tool mode**, not to the manual-mode promise. The
   invariant both modes share is *traceable reconstructability*, never exhaustive
   hand-maintained completeness.

The full model — four-layer clusters, two-arm routing, the vector internal-shape, routing
as a propagating dependency graph, the compositional finalization gate, the derivation-trail
invariant, the manual/tool split, the route-cluster card schema, and the validation ledger —
is specified in `docs/routing-and-clustering.md`.

## Consequences

- **Future doctrine slices may depend on this model.** It is the ratified refinement of the
  wedge's `cluster synthesis` step.
- **Future checker / tooling slices could not enforce it** until a fixture /
  replay case existed. That gate was subsequently satisfied; K4/K5 now enforce
  card, reference, taint, and gate structure, while routing judgment remains
  outside deterministic conformance.
- **Convergent-heavy routing remains explicitly unvalidated.** The only golden precedent
  (Loa-Straylight) exercised a heavy adversarial arm and only a *light* convergent
  constraint. Heavy convergent reconciliation and the known-category-plus-novel-delta hybrid
  have no replay case yet.
- **No generator, extractor, endpoint, or toolchain is authorized by this ADR.** It is
  doctrine-only.
- The Précis wedge, its acceptance criteria, the disposition ledger, ADR 0001's
  projection-stage separation, and the conformance checker are all **unchanged**.

## Known limits (hard)

```
validated:
  - heavy adversarial arm
  - light convergent constraint / stack-compatibility arm

not yet validated:
  - heavy convergent competitor/category reconciliation
  - known-category plus novel-delta hybrid
```

By Aleph's own Popperian discipline, the unvalidated arms have not earned "Accepted" as
*machinery*; this ADR accepts the *doctrine that names them*, including the honest record
that they are untested.
