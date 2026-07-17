# PRD Selection and Trace Contract

Use the canonical table shapes in
[`../../architecture/templates/08-projection.md`](../../architecture/templates/08-projection.md).
This file adds PRD-specific rules; it does not replace the shared projection
contract.

The commission's `projection_id` row is the sole definition of this output's
`PRJ-NNN`. Repeat that ID in the rendered metadata and trace header as a
citation, together with the commission's exact trace path.

## Selection policy

The selection ledger covers every active `carried` and `merged` claim exactly
once.

Mark a claim:

- `used` when it supports the problem/opportunity, an actor need, outcome,
  scope boundary, functional or non-functional requirement, workflow,
  dependency, delivery boundary, or acceptance condition;
- `not-used` only with one allowed reason:
  `out-of-projection-scope`, `superseded-by:CC-...`, or
  `deferred-to:<other-type>`; or
- `surfaced-as-open` when an in-scope deferred/unresolved claim affects a used
  claim, selected cluster, or required PRD section.

Selection priority:

1. carried/merged claims within the commissioned PRD boundary;
2. constraints and negative boundaries that limit requirements (negative
   boundaries terminate at active `NB-` IDs in boundary trace rows);
3. product intent and design-intent claims that license observable behavior;
4. accepted Tier-1 statements, flattened to their backing claim IDs;
5. relevant evidence gaps and known-incompleteness records; and
6. deferred/unresolved claims in the provenance cone of the above.

Do not select a claim merely to populate every PRD section. An empty section
becomes a documented gap.

## Type-specific open handling

Use these destination values in the selection ledger's open-handling field:

- `§4 Product Outcomes and Success Measures`;
- `§6 Functional Requirements`;
- `§7 User and System Workflows`;
- `§8 Constraints and Non-Functional Requirements`;
- `§9 Dependencies and Integrations`;
- `§10 Delivery Boundary`;
- `§11 Verification and Acceptance`;
- `§12 Risks, Open Questions, and Decisions Required`; or
- `§13 Gaps and Known Limits`.

Use `surfaced-as-open` for claim-backed uncertainty. Use a trace `gap` with no
backing when the template requires content the Precis does not contain.

## Statement trace

Trace anchors use `§<section> ¶<paragraph-number>`. Recompute anchors after any
edit that adds, removes, joins, or splits paragraphs.

Classify:

- problem statements, actor assertions, outcomes, requirements, workflows,
  constraints, dependencies, delivery claims, and acceptance conditions as
  `load-bearing`;
- asserted negative boundaries as `boundary`, backed by active `NB-` IDs;
- deferred/unresolved questions and decisions as `open-item`;
- missing users, measures, targets, behavior, dependencies, delivery decisions,
  or acceptance conditions as `gap`; and
- headings, labels, and non-assertive commission framing as `scaffolding`.

Every `load-bearing` row has one or more active carried/merged `CC-` IDs.
Every `boundary` row has one or more active `NB-` IDs and no claim backing.
Every `open-item` row has one or more deferred/unresolved `CC-` IDs. `gap` and
`scaffolding` rows have empty backing.

The software-product assumption, intended consumer, and commissioned PRD scope
are authority parameters rather than corpus findings. Phrase them as parameters,
classify the framing as `scaffolding`, and cite the commission field in the
trace note. An asserted negative boundary is not commission framing; trace it
as `boundary`.

## Tier-1 trace composition

When the PRD uses a product-doctrine statement:

1. locate its Tier-1 trace row;
2. verify every backing claim is still active;
3. put the underlying `CC-` IDs, not the Tier-1 paragraph alone, in the PRD
   trace backing column; and
4. cite the Tier-1 anchor in the PRD trace note.

A trace may pass through another projection for reader convenience, but it
never terminates there.

## Taint and boundary checks

- If a used claim is within an unresolved external-referent cone, place the
  exact marker `external-referent unresolved` in the first ten rendered lines
  and list the relevant `REF-` IDs.
- Never back a requirement with a do-not-use claim.
- Never use a `backgrounded` claim as load-bearing support.
- Never expose `PKT-` IDs in the rendered PRD.
- Re-verify the source Precis hash after rendering.

## Independent semantic review

The reviewer receives the PRD candidate, selection ledger, trace, source
Precis, and any accepted Tier-1 input, but not the renderer's working notes.
The review attempts to find:

- a requirement not licensed by its backing claims;
- unsupported MUST/SHOULD/MAY strength;
- an invented user, metric, threshold, workflow step, dependency, or schedule;
- unresolved material written as a settled requirement;
- a conflicting requirement smoothed away;
- a template gap filled from convention or model knowledge;
- a selected claim silently omitted;
- a negative-boundary violation; or
- hidden external-referent taint.

Any refutation is corrected and retraced before P3. The renderer does not grant
acceptance.
