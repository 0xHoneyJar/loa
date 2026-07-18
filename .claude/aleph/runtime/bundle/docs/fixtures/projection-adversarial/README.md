# Projection Adversarial Fixture

```aleph-fixture
kind: projection
cc_ids: CC-201..CC-209
```

This standalone fixture isolates K6 against two projections of the same
fixture-accepted synthetic Precis. The required WP7 examples that render the
exact golden-run Précis live under `../run-slice-2/projections/`; this fixture is
the smaller adversarial supplement:

- `PRJ-201`, rendered as a Tier-1 `product-doctrine`; and
- `PRJ-202`, rendered independently as a Tier-2 software `prd`.

The fixture treats `precis.md` as fixture-accepted input. Decision 0003 permits
a standalone projection fixture to omit a run manifest; that omission removes
only the run-state chronology check. Both commissions still bind the exact
current Precis hash, and neither commission is evidence of real authority
acceptance.

## Cases Frozen Here

- Every active carried or merged claim receives exactly one selection row in
  each projection.
- Each `PRJ-*` is defined once in its commission; its trace and rendering cite
  that definition and the exact trace path.
- Used claims touch `RC-201` and `RC-202`, so deferred and unresolved claims in
  those clusters are surfaced as open.
- `CC-208` is governed by the active `do-not-use-harm` boundary and is
  explicitly not selected.
- `REF-201` remains unresolved in the provenance cone of used `CC-203` and
  `CC-209`, so both rendered documents carry the exact
  `external-referent unresolved` marker in their first ten lines.
- Both traces cover every rendered paragraph, include non-assertive
  scaffolding, and preserve an honest gap with empty backing.
- Rendered documents contain no packet IDs or copied disposition-table rows.

## Validation

```text
node scripts/validate-run.ts --root . --run docs/fixtures/projection-adversarial
```

The clean fixture must exit zero with K6.1 through K6.10 passing. The mutation
battery is run against temporary copies and does not alter this fixture.
