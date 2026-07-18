# Templates 08 — Projection Stage

## T8.1 Projection commission → `runs/<run-id>/projections/commission-⟨type⟩.md`

```markdown
# Projection Commission — ⟨type⟩ for ⟨RUN-slug⟩
| field | value |
|-------|-------|
| projection_id | ⟨PRJ-NNN; unique within this run⟩ |
| commissioned_by | ⟨authority⟩ |
| date | ⟨…⟩ |
| projection type | ⟨product-doctrine \| architecture-primitive-map \| responsibility-map \| mvp-wedge \| prd \| ssd \| …⟩ |
| projection trace | projections/traces/⟨type⟩-trace.md |
| intended consumer | ⟨repo / team / person⟩ |
| type parameters | ⟨e.g. PRD scope boundary; none⟩ |
| precis_hash at commissioning | ⟨sha256 of precis.md⟩ |
| run state verified | ACCEPTED (⟨manifest row ref⟩) |
```

Rules: no commission → no projection (a finished Précis is a complete run).
The `projection_id` row is the sole defining location for this `PRJ-NNN`; the
rendered document and trace cite it. The hash and trace path recorded here must
verify unchanged at P3.

## T8.2 Selection ledger → `runs/<run-id>/projections/traces/⟨type⟩-selection.md`

```markdown
# Selection Ledger — ⟨type⟩
<!-- Completed BEFORE rendering prose. Covers every carried and merged
     claim in the Précis; plus every deferred/unresolved claim in scope. -->
| claim_id | disposition | selection | reason if not-used / open-handling |
|----------|-------------|-----------|-------------------------------------|
```

`selection`: `used` | `not-used` | `surfaced-as-open`. Rules: carried/merged
claims are `used` or `not-used` with a reason from {out-of-projection-scope,
superseded-by:CC-x, deferred-to:⟨other type⟩}; deferred/unresolved claims in
scope must be `surfaced-as-open` with the section that will carry them; a
blank reason is a K6 failure.

## T8.3 Projection trace → `runs/<run-id>/projections/traces/⟨type⟩-trace.md`

```markdown
# Projection Trace — ⟨type⟩
- projection_id: ⟨PRJ-NNN from the commission; citation, not a new definition⟩
- renders: projections/tier-⟨1|2⟩/⟨type⟩.md
- precis_hash verified: ⟨sha256 — must equal commission value⟩
- taint status: ⟨none \| external-referent unresolved: REF-… (marker present in document header)⟩

## Statement trace
| anchor | statement kind | backing (CC/NB ids) | note |
|--------|----------------|------------------|------|
```

Column rules:

- `anchor`: a stable pointer into the rendered document — `§⟨section⟩ ¶⟨n⟩`
  (renderers keep paragraphs stable once traced; retrace after edits).
- `statement kind`: `load-bearing` (asserts something a reader could act on)
  | `boundary` (asserts an active negative boundary and terminates at one or
  more `NB-` IDs) | `open-item` (must trace to a deferred/unresolved claim and
  be phrased as open) | `gap` (template wanted it; Précis lacks it; phrased as
  explicit gap; `backing` empty by definition) | `scaffolding` (headings,
  transitions, or exact commission metadata framing; asserts no corpus or
  product proposition; `backing` empty).
- Rules (K6 enforces): every `load-bearing` row has ≥1 CC id, each resolving
  to carried/merged; every `boundary` row has ≥1 active NB id and no CC id; an
  `open-item` asserting language is a defect; no statement may rest on claims
  governed by a do-not-use boundary; every rendered document paragraph appears
  in some row (coverage).

<!-- example -->
| §2 ¶3 | load-bearing | CC-101, CC-102 | access primitive + tiering |
| §3 ¶1 | boundary | NB-2 | active privacy-harm boundary |
| §5 ¶1 | open-item | CC-105, CC-106 | free-tier contradiction held open |
| §4 ¶2 | gap | | template wants latency targets; no claim speaks to latency |
