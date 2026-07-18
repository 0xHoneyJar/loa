# Product-Doctrine Projection Package

- **Tier:** 1, universal
- **Projection type:** `product-doctrine`
- **Status:** Authoring contract, golden-derived rendering, and K6 evidence
  implemented; real independent audit and authority acceptance pending.

A product-doctrine projection turns the carried invariant, design-intent, and
constraint claims in an accepted Research Precis into a compact set of
principles and decision rules. It commits to a product purpose without changing
the source Precis and without inventing requirements that the research did not
establish.

## Inputs

- an `ACCEPTED` run's `precis.md` and read-only ledgers;
- a `product-doctrine` commission defining its `PRJ-NNN`, trace path, intended
  consumer, and parameters;
- the commission-time SHA-256 hash of `precis.md`; and
- the templates and rules in this package.

## Outputs

```text
runs/<run-id>/projections/
  commission-product-doctrine.md
  tier-1/product-doctrine.md
  traces/product-doctrine-selection.md
  traces/product-doctrine-trace.md
```

## Package contents

- [`template.md`](template.md): document skeleton.
- [`authoring-instructions.md`](authoring-instructions.md): rendering rules and
  section guidance.
- [`trace-and-selection.md`](trace-and-selection.md): type-specific selection,
  trace, and review contract.

The common projection workflow and status boundary are in
[`../README.md`](../README.md).

## Definition of Done for a rendered candidate

- [ ] The source run was `ACCEPTED` before commissioning.
- [ ] Commission, trace, and rendered metadata agree on the `PRJ-NNN` and
      trace path.
- [ ] The selection ledger was completed before prose.
- [ ] Every active carried/merged claim has exactly one selection row.
- [ ] Every deferred/unresolved claim in the selected clusters is surfaced as
      open or explicitly outside the commissioned scope.
- [ ] Every rendered paragraph has a statement-trace row.
- [ ] Every load-bearing statement resolves to active carried/merged claim IDs.
- [ ] No template placeholder or instructional comment remains.
- [ ] Negative boundaries and external-referent taint are honored.
- [ ] The commissioned Precis hash is unchanged after rendering.
- [ ] Structural checks and an independent rendering-quality review are
      attached.
- [ ] P3 authority acceptance is recorded.

A rendered real output remains a `product-doctrine projection candidate` until
all evidence items exist. Fixture-simulated records do not make it an accepted
projection.
