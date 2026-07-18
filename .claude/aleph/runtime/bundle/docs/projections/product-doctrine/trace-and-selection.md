# Product-Doctrine Selection and Trace Contract

Use the canonical table shapes in
[`../../architecture/templates/08-projection.md`](../../architecture/templates/08-projection.md).
This file adds type-specific rules; it does not replace the shared projection
contract.

The commission's `projection_id` row is the sole definition of this output's
`PRJ-NNN`. Repeat that ID in the rendered metadata and trace header as a
citation, together with the commission's exact trace path.

## Selection policy

The selection ledger covers every active `carried` and `merged` claim exactly
once.

Mark a claim:

- `used` when it directly supports product intent, a governing principle, a
  decision rule, a boundary, or a known limit;
- `not-used` only with one allowed reason:
  `out-of-projection-scope`, `superseded-by:CC-...`, or
  `deferred-to:<other-type>`; or
- `surfaced-as-open` when an in-scope deferred/unresolved claim affects a used
  claim or selected cluster.

Selection priority:

1. invariant-bearing carried claims that survived applicable stress tests;
2. carried design-intent and constraint claims;
3. merged claims, using the canonical claim while retaining all source
   provenance;
4. applicable negative boundaries (carried through `NB-`-backed boundary trace
   rows, not treated as supporting claims) and known-incompleteness records; and
5. deferred/unresolved claims in the provenance cone of the above.

Selection never depends on citation count or prose prominence. A load-bearing
claim with an unresolved-source dependency remains usable only with its taint
made explicit.

## Type-specific open handling

Use these destination values in the selection ledger's open-handling field:

- `§6 Open Questions and Tensions`;
- `§7 Evidence Gaps`; or
- `§8 Known Limits and Change Conditions`.

An open item may appear in more than one paragraph, but it has one selection
row and every rendered occurrence has a trace row.

## Statement trace

Trace anchors use `§<section> ¶<paragraph-number>`. Recompute anchors after any
edit that adds, removes, joins, or splits paragraphs.

Classify:

- principles, implications, and decision rules as `load-bearing`;
- asserted negative boundaries as `boundary`, backed by active `NB-` IDs;
- deferred/unresolved questions and tensions as `open-item`;
- missing information as `gap`; and
- headings, non-assertive transitions, and exact commission metadata framing as
  `scaffolding`.

Every `load-bearing` row has one or more active carried/merged `CC-` IDs.
Every `boundary` row has one or more active `NB-` IDs and no claim backing.
Every `open-item` row has one or more deferred/unresolved `CC-` IDs. `gap` and
`scaffolding` rows have empty backing.

Commission parameters such as intended consumer are not corpus findings.
Phrase them as parameters, classify the paragraph as `scaffolding`, and cite
the exact commission field in the trace note. Do not use this rule for an
asserted negative boundary; that requires a `boundary` row.

## Taint and boundary checks

- If a used claim is within an unresolved external-referent cone, place the
  exact marker `external-referent unresolved` in the first ten rendered lines
  and list the relevant `REF-` IDs.
- Never back a statement with a do-not-use claim.
- Never use a `backgrounded` claim as load-bearing support.
- Never expose `PKT-` IDs in the rendered doctrine.
- Re-verify the source Precis hash after rendering.

## Independent semantic review

The reviewer receives the candidate, its selection ledger and trace, and the
source Precis, but not the renderer's working notes. The review attempts to
find:

- a rule not licensed by its backing claims;
- a hedge, condition, or actor lost in projection;
- unresolved material written as settled doctrine;
- a contradiction smoothed into one principle;
- a selected claim silently omitted;
- an unsupported implication or invented gap answer;
- a negative-boundary violation; or
- an external-referent taint hidden from the reader.

Any refutation is corrected and retraced before P3. The renderer does not grant
acceptance.
