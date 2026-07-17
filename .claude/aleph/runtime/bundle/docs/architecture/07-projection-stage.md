# 07 — The Projection Stage

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md).
> ADR 0001 declared the projection stage and its two tiers. The initial
> product-doctrine and software-PRD packages, fixtures, and deterministic checks
> now exist; real outputs still require independent audit and authority
> acceptance.

## 1. Position and prime directive

```
ACCEPTED Précis (+ ledgers, read-only)
        │
        ▼
  P1  Tier-1 universal projections          product-doctrine
      (domain-agnostic)                     architecture / primitive-map
        │                                   responsibility / environment-
        │                                     verification map
        ▼                                   mvp-wedge selection
  P2  Tier-2 terminal renderings            PRD, SSD (software)
      (domain-specific, pluggable)          series-bible (creative)
        │                                   GTM / ops manual (business)
        ▼
  P3  projection gate (trace checks + audit + acceptance)
```

Prime directive (ADR 0001, operationalized): **the projection engine consumes
a finished, accepted Précis and never mutates it.** Mechanically: the engine
runs only against `ACCEPTED` runs; it holds read-only references; the Précis
hash is recorded before P1 and re-verified at P3; any mismatch fails the
projection outright.

The second directive is this plan's extension: **neutrality ends at the
Précis, but traceability never ends.** A projection commits to a purpose; it
does not get to commit to facts the Précis doesn't carry. Every load-bearing
statement in a rendered document traces to claim IDs (artifact 18), exactly as
every claim traces to packets.

## 2. What a projection type is

A projection **type** (e.g. `product-doctrine`, `prd`) is a pluggable package
of five things, acquired in its own slice:

1. **Template** — the document skeleton: sections, the question each section
   answers, and which claim classes feed it.
2. **Authoring instructions** — how a renderer (agent or human) fills the
   template: selection rules, tone, length calibration, what to do with
   unresolved/deferred claims (surface them; never resolve them), how to
   handle taints.
3. **Selection-ledger and trace requirements** — instantiating artifact 18
   for this type.
4. **Conformance checks** — the `PT-*` kernel group instantiated for the
   template (required sections present; trace resolves; no new claims;
   boundaries honored).
5. **Fixture** — a golden example: an accepted Précis (a fixture one) rendered
   into this type, hand-audited.

A projection type without all five is a sketch, not a type. The **Definition
of Done for adding a projection type**:

- [ ] template + authoring instructions reviewed and merged
- [ ] fixture rendered from an accepted Précis fixture, with full trace and
      selection ledger
- [ ] kernel checks for the type added in lockstep, negative battery extended
- [ ] independent audit of the fixture against the trace contract
- [ ] authority acceptance; validation-ledger entry ("projection type X:
      fixture-validated")

## 3. The commissioning step

Projections do not happen because a run finished; they happen because the
authority **commissions** one: a short record (in the run's
`projections/` area) defining its unique `PRJ-NNN`, naming the type, intended
consumer, exact trace path, and any type-specific parameters (e.g. PRD scope).
That `projection_id` row is the ID's sole defining location; the rendering and
trace cite it. Commissioning is where purpose enters the system — after the
neutral artifact is sealed, never before. The runbooks make this a hard gate.

## 4. Rendering rules (both tiers)

1. **Selection before prose.** The renderer first completes the selection
   ledger — every carried/merged claim marked used / not-used-with-reason —
   then writes. This ordering makes "what did the projection ignore?"
   answerable by diff instead of by re-reading.
2. **Unresolved material surfaces.** Deferred/unresolved claims within the
   projection's scope map to an explicit open-questions/risks section.
   A projection that reads as settled while the Précis says unresolved is a
   defect the trace checks catch (a statement tracing to an unresolved claim
   must be marked as open, not asserted).
3. **Taint is loud.** If any load-bearing cluster feeding the projection
   carries `external-referent unresolved`, the rendered document opens with
   that marker and lists the pending referents. "Externally complete" language
   is forbidden while taint exists (K5 gate, extended through P-stages).
4. **Negative boundaries bind renderers.** Do-not-use claims cannot resurface;
   not-evidence material cannot be cited as support. The trace makes this
   checkable.
5. **Gaps stay gaps.** Where the template demands something the Précis lacks
   (e.g. a PRD wants latency targets and no claim speaks to latency), the
   renderer writes an explicit gap entry. Minting facts at render time is the
   projection-stage equivalent of fabrication — the no-new-claims trace check
   exists for exactly this.
6. **Tier-2 renders from Tier-1 and/or the Précis** (ADR 0001). When a Tier-2
   document builds on a Tier-1 projection, its trace may cite Tier-1 sections,
   but those must themselves trace onward to claims — traces compose; they
   never terminate in another projection's prose.

## 5. Tier-1 specifics

The four universal types map to claim classes roughly as:

| Tier-1 type | Primarily consumes | Watch out for |
|---|---|---|
| product-doctrine | carried invariant-bearing claims; survived stress-tests | doctrine written from claims that never faced the adversarial arm |
| architecture / primitive-map | carried design-intent + constraint claims; cluster structure | premature primitives from unresolved contradictions |
| responsibility / environment-verification map | constraint claims; negative boundaries; external-referent records | scope creep past declared corpus scope |
| mvp-wedge selection | the cluster dependency graph; unresolved queue (what a wedge must *not* depend on) | wedges resting on tainted clusters |

The Straylight manual precedent (doctrine / primitive-map / responsibility-map
/ mvp-wedge produced by hand from distilled research) is the golden shape for
these; the first Tier-1 fixtures should consciously imitate it.

## 6. Tier-2 specifics

Tier-2 is a plugin registry, deliberately open-ended. The first plugin should
be the **PRD** (it matches the product goal's headline promise and the
Freeside-adjacent corpus most likely to be run first). Plugin-specific DoD
adds to §2: the plugin declares its domain assumptions explicitly (a PRD
plugin assumes a software product context — that assumption is recorded in the
rendered doc, since the Précis itself never carried it).

## 7. Anti-goals

- No projection-on-demand service. Projections are runs of a procedure with
  gates, not an endpoint.
- No "regenerate until it sounds right" loops that bypass the trace. Every
  regeneration re-passes the checks.
- No back-propagation: a projection discovering a Précis defect files it as a
  finding against the run (which may spawn a corrective distillation slice);
  it never patches the Précis in place.
- No business/market-intelligence scope absorption: those projection types
  remain outside Aleph unless separately authorized under an accepted contract
  for that external consumer; the plugin registry does not quietly become a BI
  product.
