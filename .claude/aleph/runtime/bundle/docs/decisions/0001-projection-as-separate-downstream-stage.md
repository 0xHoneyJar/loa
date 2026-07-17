# Decision 0001 — Projection becomes a separate downstream stage Aleph owns

- **Status:** Accepted
- **Date:** 2026-06-26
- **Authority:** Eileen (product / architecture authority), explicit approval
- **Supersedes:** the original "Aleph stops at the neutral Précis; it generates no
  downstream projection" constraint as stated in `README.md`,
  `docs/responsibility-map.md`, and `docs/precis-wedge.md` (Phase 0/1 framing).
- **Implemented by:** [Decision 0003](0003-architecture-build-kit-implementation.md)
  for the initial `product-doctrine` and `prd` packages; real projection
  acceptance remains separately gated.

## Context

Aleph was founded on a hard boundary: it produces a single **projection-neutral
Research Précis** and nothing else. Producing finished consumer documents — PRDs,
system/architecture specs, product-doctrine, etc. — was explicitly **out of
scope** and assigned to *consuming* repos or substrates. This boundary was
written into three places and (for the Précis layer) enforced by the conformance
checker.

That boundary made the Précis reusable: by refusing to commit to any single
output, one Précis could be cast into many different documents. The neutrality
was the source of the reuse.

But the product goal is now explicit: a person should be able to download
loa-aleph, drop in their own research, and **get a finished document out** — a
PRD, an SSD, a product-doctrine, an MVP-wedge selection, etc. — in either of two
modes:

- **agent mode:** an agent syncs `main`, follows the repo's instructions, and
  produces the document;
- **manual mode:** a person follows the same instructions by hand, with no agent,
  and reaches the same result.

A repo that only ever emits a neutral intermediate cannot deliver that outcome.
The founding boundary and the product goal are in direct conflict.

## Decision

**Neutrality is preserved as a property of the Précis, not of the repo.**

1. The **Research Précis remains strictly projection-neutral.** The Précis itself
   must never decide what it becomes, never generate a PRD/SSD/doctrine, never
   commit to a single downstream form. This is unchanged and remains enforced by
   the conformance checker on the Précis layer (`docs/fixtures/*/precis.md`).

2. **Aleph additionally owns a separate, explicitly-bounded projection stage.**
   This downstream stage *consumes a finished, neutral Précis* and *renders* it
   into a specific consumer document. It is a distinct step with its own inputs
   (a completed Précis), its own outputs (a named document type), and its own
   conformance checks. It does not run inside, or mutate, the Précis.

3. The pipeline is therefore two clearly separated stages:

   ```
   messy corpus
     → [Stage 1: distillation]  → projection-neutral Research Précis   (neutral)
       → [Stage 2: projection]  → finished consumer document           (committed)
   ```

   Stage 1's neutrality is sacred. Stage 2 is allowed to commit to a purpose
   precisely because it is downstream of, and never alters, the neutral artifact.

## Projection tiers

Stage 2 projections are organized in two tiers, learned from the Loa-Straylight
manual precedent (which produced doctrine / primitive-map / responsibility-map /
mvp-wedge by hand from the same distilled research):

- **Tier 1 — universal projections** (domain-agnostic; apply to any novel
  subject, software or not): product-doctrine, architecture / primitive-map,
  responsibility / environment-verification map, mvp-wedge selection.
- **Tier 2 — terminal renderings** (domain-specific; only some domains have
  them): e.g. PRD and SSD for software; a series-bible or world-doctrine for
  creative work; a GTM or ops manual for a business. Tier 2 renders *from* a
  Tier-1 projection and/or the Précis. The set is pluggable, not fixed.

Aleph stays domain-neutral down through Tier 1 and commits to a domain only at
Tier 2.

## What does NOT change

- The Précis completeness contract, disposition ledger, normalization, and
  provenance rules are untouched.
- The Précis-layer neutrality guard in the checker stays exactly as strict: a
  `precis.md` that tries to generate a projection still fails closed.
- Business / market intelligence remains a separate, deferred downstream
  concern. Adding a projection stage to Aleph does not pull that downstream
  scope into Aleph.

## Consequences

- `README.md`, `docs/responsibility-map.md`, and `docs/precis-wedge.md` are
  amended to state the two-stage model and to point at this decision. In
  `README.md` this spans the "What a Research Précis is" prose, the "Where Aleph
  sits in the stack" diagram, and the Status note; the blunt "no downstream
  projection generation" lines elsewhere are replaced with the precise rule:
  *the Précis never generates a projection; a separate projection stage does.*
- At this decision's acceptance date, a `projections/` concern was still to be
  added with per-tier templates and per-projection conformance checks. Decision
  0003 later authorized the initial product-doctrine and PRD packages, fixtures,
  and K6 implementation.
- This decision itself required **no checker change**: the then-current checker
  scanned only the accepted Précis fixtures and continued enforcing neutrality
  there. The later K6 slice extends discovery deliberately and in lockstep with
  projection fixtures; it does not weaken the Précis neutrality boundary.
