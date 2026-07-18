# Software PRD Projection Package

- **Tier:** 2, terminal rendering
- **Projection type:** `prd`
- **Domain:** Software product
- **Status:** Authoring contract, golden-derived rendering, and K6 evidence
  implemented; real independent audit and authority acceptance pending.

The PRD projection turns an accepted Research Precis, optionally accompanied by
an accepted Tier-1 product doctrine, into a software product requirements
document. It commits to the commissioned software-product purpose while keeping
all claims traceable and every missing requirement explicit as a gap.

## Inputs

- an `ACCEPTED` run's `precis.md` and read-only ledgers;
- a `prd` commission defining its `PRJ-NNN`, trace path, intended consumer,
  software-product domain assumption, and PRD scope;
- the commission-time SHA-256 hash of `precis.md`;
- optionally, an accepted product-doctrine projection with its trace; and
- the templates and rules in this package.

## Outputs

```text
runs/<run-id>/projections/
  commission-prd.md
  tier-2/prd.md
  traces/prd-selection.md
  traces/prd-trace.md
```

## Package contents

- [`template.md`](template.md): PRD skeleton.
- [`authoring-instructions.md`](authoring-instructions.md): rendering rules and
  section guidance.
- [`trace-and-selection.md`](trace-and-selection.md): type-specific selection,
  trace, and review contract.

The common projection workflow and status boundary are in
[`../README.md`](../README.md).

## Definition of Done for a rendered candidate

- [ ] The source run was `ACCEPTED` before commissioning.
- [ ] The authority commission records the `PRJ-NNN`, trace path, software-
      product assumption, intended consumer, PRD boundary, and Precis hash.
- [ ] Commission, trace, and rendered metadata agree on the `PRJ-NNN` and
      trace path.
- [ ] The selection ledger was completed before prose.
- [ ] Every active carried/merged claim has exactly one selection row.
- [ ] Every relevant deferred/unresolved claim is surfaced as open.
- [ ] Every template demand unsupported by the Precis is an explicit gap.
- [ ] Every rendered paragraph has a statement-trace row.
- [ ] No template placeholder or instructional comment remains.
- [ ] Any Tier-1 input trace resolves transitively to the underlying claim IDs.
- [ ] Negative boundaries and external-referent taint are honored.
- [ ] The commissioned Precis hash is unchanged after rendering.
- [ ] Structural checks and an independent rendering-quality review are
      attached.
- [ ] P3 authority acceptance is recorded.

A rendered real output remains a `PRD projection candidate` until all evidence
items exist. Fixture-simulated records do not make it an accepted projection or
accepted PRD.
