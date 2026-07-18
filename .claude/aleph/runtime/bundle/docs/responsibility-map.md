# Aleph Responsibility Map

This document fixes what Aleph owns, what it does not own, and where its
boundary sits relative to the rest of the Loa stack. It is a boundary contract,
not an implementation plan.

## Ownership statement

> Aleph owns the process substrate and the portable Research Précis artifact,
> **and a separate downstream projection stage** that renders a finished Précis
> into consumer documents. The Précis itself stays strictly projection-neutral —
> it never generates a finished document. Projection happens in a distinct stage
> that consumes the neutral artifact without mutating it. Aleph's first wedge
> proves only that a bounded corpus can become one projection-neutral Précis file
> with a complete candidate-claim disposition trail. The separately implemented,
> acceptance-gated projection stage does not alter that wedge. See
> `docs/decisions/0001-projection-as-separate-downstream-stage.md`.

## Aleph owns

- The **distillation process**: source inventory → extraction → packet index →
  classification / disposition → duplicate/merge map → do-not-use boundaries →
  stress-test → cluster synthesis → unresolved/deferred queue → Précis.
- The **Research Précis artifact**: its acceptance envelope, its completeness
  contract, its normalization rules, its provenance and disposition ledger.
- The **completeness guarantee** — that every candidate claim within the declared
  corpus scope has a recorded disposition, and that the extraction criteria
  separating raw noise from candidate claims are themselves recorded.
- The **portability contract**: the Précis is a file that can be checked in,
  handed off, diffed, versioned, audited, and ingested.

## Aleph owns (projection stage)

- The **projection stage**: a separate, explicitly-bounded downstream step that
  *consumes a finished, neutral Précis* and *renders* it into a named consumer
  document. It never runs inside the Précis and never mutates it. Organized in
  two tiers:
  - **Tier 1 — universal projections** (domain-agnostic): product-doctrine,
    architecture / primitive-map, responsibility / environment-verification map,
    mvp-wedge selection.
  - **Tier 2 — terminal renderings** (domain-specific, pluggable): e.g. PRD / SSD
    for software; series-bible / world-doctrine for creative work; GTM / ops
    manual for a business.
- Each projection type carries its own template, fixture, and registered
  conformance checks, added in lockstep.

## Aleph does not own

- **Generation of projections *by the Précis itself*.** The neutral artifact must
  never commit to a single output form; that neutrality is what makes one Précis
  reusable across many projections. Projection is allowed only in the separate
  downstream stage above, never folded into the Précis.
- **Business / market intelligence.** Competitor analysis, market landscape,
  protocol/product viability, GTM, positioning, revenue path — these do not
  belong to Aleph. A future adjacent stack-wide business/market-intelligence
  consumer may project Aleph Précis material into business, market, competitor,
  GTM, protocol/product-viability, and commercial-intelligence artifacts for
  Loa repos, but its own responsibility map, artifact contract, and wedge
  remain outside Aleph and deferred until Aleph's Précis contract is stable.
- **Product / platform surfaces.** Token gating, teams, growth loops,
  community/commercial utility — these belong to **Freeside** and peer product
  repos.
- **Served endpoints.** The Précis is file-first. Endpoint or integration
  surfaces, if they ever exist, project from the artifact and are out of scope
  for the current phase.

## Boundary with the rest of the stack

```
raw / fragmented research corpus
  ↓
Aleph                                       (this repo)
  │
  ├─ Stage 1: distillation
  │    ↓
  │  projection-neutral Research Précis file   (this repo's core artifact)
  │    ↓
  └─ Stage 2: projection stage                 (this repo, acceptance-gated)
       ↓
     finished consumer documents
     (Tier 1: doctrine / primitive-map / responsibility / mvp-wedge;
      Tier 2: PRD, SSD, … domain-specific)
       ↓
┌───────────────┬───────────────┬────────────────┐
↓               ↓               ↓
business/       Freeside        other Loa repos
market-intel    product/        future consumers
consumers       platform use
(may also project the neutral Précis themselves)
```

- **The neutral Précis is the hinge.** Aleph's own Stage-2 projection consumes it;
  so can any external consumer. A consumer is never *forced* through Aleph's
  projection stage — it may take the neutral Précis and project it itself. Aleph
  owning a projection stage adds a capability; it does not close the artifact off.
- **Aleph fans out, it does not serialize.** The Précis is an adjacent input to
  whichever consumers need it. An adjacent business/market-intelligence
  consumer or projection layer is optional, not a mandatory intermediary
  between Aleph and Freeside.
- **Aleph → any repo:** the same contract holds for any consumer. Aleph does not
  privilege a particular downstream. Freeside is the first corpus context only
  because the current research happens to be Freeside/token-gating related.

## Workflow roles (carried from the Loa-Straylight precedent)

```
User (Eileen) = product / architecture authority; approves and runs commits/PRs
Coordinator   = interprets, sequences, writes prompts and docs
Claude in repo = repo-local implementation worker
Codex in ~/loa-dev = independent repo auditor
GitHub PRs    = source-of-truth checkpoints
```

Repo work proceeds in phases. Implementation drafts and patches happen locally;
independent audit precedes PR; PRs are the source-of-truth checkpoints. The
architecture authority makes final architectural decisions and performs or
approves commits and pushes.

## What is explicitly out of scope right now

- No endpoint.
- No extractor, generator, served application, or autonomous acceptance path.
- The **Précis never generates a projection**; projection lives only in the
  separate downstream stage.
- No final schema freeze beyond the v0 acceptance envelope.
- No formalization of an adjacent business/market-intelligence consumer until
  the Aleph Précis contract is stable.
