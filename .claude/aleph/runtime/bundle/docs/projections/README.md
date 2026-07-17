# Projection Authoring Packages

This tree contains the authoring contracts for Aleph's first two projection
types:

| Type | Tier | Package |
|------|------|---------|
| Product doctrine | Tier 1, universal | [`product-doctrine/`](product-doctrine/) |
| Software product requirements document (PRD) | Tier 2, domain-specific | [`prd/`](prd/) |

## Status

The templates, authoring instructions, type-specific trace/selection rules,
golden-derived renderings, and K6 structural evidence are implemented. The
golden run contains fixture-simulated audit and P3 records so the gate shapes
can be checked. Those records are not real authority evidence: the packages
remain local projection-type implementation candidates until independent review,
authority acceptance, publication, and the validation-ledger transition.

Using a package produces a projection candidate. It does not confer acceptance.

Worked examples:

- [`../fixtures/run-slice-2/projections/`](../fixtures/run-slice-2/projections/)
  renders both types from the exact golden Précis.
- [`../fixtures/projection-adversarial/`](../fixtures/projection-adversarial/)
  isolates K6 boundary and mutation cases.

## Shared prerequisites

A projection may begin only when all of the following are true:

1. The source run is `ACCEPTED`.
2. The authority has commissioned a named projection type, intended consumer,
   and any type parameters.
3. The commission defines a unique run-local `PRJ-NNN` and records its exact
   projection-trace path.
4. The commission records the current SHA-256 hash of `precis.md`.
5. The renderer has read the source Precis and ledgers without write access.

Use the canonical commission, selection-ledger, and trace shapes in
[`../architecture/templates/08-projection.md`](../architecture/templates/08-projection.md).
The architecture contract is
[`../architecture/07-projection-stage.md`](../architecture/07-projection-stage.md).

## Shared workflow

1. Create the commission record, assigning its `PRJ-NNN` exactly once. No
   commission means no projection.
2. Complete the selection ledger before writing prose.
3. Render into the selected type's template.
4. Trace every rendered paragraph as it is written.
5. Surface unresolved material and gaps; do not resolve or fill them.
6. Propagate external-referent taint into the first ten lines.
7. Verify the Precis hash is unchanged.
8. Run every available structural check and the projection-trace semantic lens.
9. Obtain independent audit and authority acceptance at P3.

## Shared statement rules

- `load-bearing`: backed by at least one active `carried` or `merged` claim.
- `boundary`: backed by at least one active negative-boundary (`NB-`) record
  and no claim ID; it constrains use but is not supporting evidence.
- `open-item`: backed by `deferred` or `unresolved` claims and written as open.
- `gap`: required by the template but absent from the Precis; backing is empty.
- `scaffolding`: headings, non-assertive transitions, or exact commission
  metadata framing; backing is empty and it asserts no corpus or product
  proposition.

Every rendered paragraph must have a trace row. A claim governed by a do-not-use
boundary may not support a projection. `backgrounded` material may provide
context but may not appear as load-bearing backing. Projection documents may
name `CC-` IDs, but must not expose packet IDs or reproduce the full claim and
disposition inventory.

## Packages

Each package contains:

- a status and usage `README.md`;
- a document template;
- authoring instructions; and
- type-specific selection and trace requirements.

The PRD package may consume the accepted Precis directly and may also use an
accepted product-doctrine projection. When it uses another projection, its
trace must still resolve transitively to the underlying `CC-` IDs.
