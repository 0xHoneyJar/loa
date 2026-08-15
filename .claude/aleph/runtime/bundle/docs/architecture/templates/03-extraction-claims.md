# Templates 03 — Extraction and Claims

## T3.1 Packet index → `runs/<run-id>/ledgers/packet-index.md`

```markdown
# Packet Index — ⟨RUN-slug⟩

- exact_evidence_format: aleph-exact-evidence/v1

## Packets
| packet_id | source_id | locator | span_hash | quote | criterion | status |
|-----------|-----------|---------|-----------|-------|-----------|--------|

## Exact evidence records
| evidence_key | packet_ids | evidence_state | fragment_count | join_policy | exact_evidence_hash | degraded_source_id | degraded_source_locator | degradation_reason |
|--------------|------------|----------------|----------------|-------------|---------------------|--------------------|-------------------------|--------------------|

## Ordered fragments
| fragment_key | evidence_key | packet_id | fragment_order | source_id | locator | source_relation | byte_role | fragment_hash | exact_bytes_base64 |
|--------------|--------------|-----------|----------------|-----------|---------|-----------------|-----------|---------------|--------------------|

## Evidence transformations
| transform_key | evidence_key | output_role | predecessor_exact_evidence_hash | effective_exact_evidence_hash | output_text | output_text_hash |
|---------------|--------------|-------------|---------------------------------|-------------------------------|-------------|------------------|

## Per-source completion  <!-- one row per source; S2 DoD needs every row -->
| source_id | walked | packets | declared complete by | note |
|-----------|--------|---------|----------------------|------|
```

Column rules:

- `locator` uses the source's scheme from the corpus manifest (`L118-L131`,
  `M14:S2`). `span_hash` = sha256 of the exact span bytes at freeze.
- In `aleph-exact-evidence/v1`, use one packet per exact fragment. `quote` is
  a bounded display preview only and is never exact evidence. Run format
  `1.1.0-provisional` requires this marker and the three versioned tables once
  S2 is reached. Historical `1.0.0-provisional` and pre-versioned packet
  ledgers without the marker retain their predecessor behavior and are not
  reinterpreted.
- `criterion`: the admission-criterion number from T2.2. A walked span that
  matched an exclusion class gets **no row** (that is the recorded
  two-level boundary); a span refused by a classifier gets a row with
  `criterion = refusal-blocked` so completeness accounting still balances.
- `status`: `active` | `superseded-by:PKT-xxxx` | `retracted:⟨reason⟩`.
- `evidence_state`: `exact` | `degraded-non-exact`. Every packet appears in
  exactly one `exact` evidence record. A degraded record uses `packet_ids =
  none`, `fragment_count = 0`, `join_policy = not-applicable`,
  `exact_evidence_hash = none`, an existing `degraded_source_id`, a locator
  under that source's declared scheme, and a nonempty reason. Exact records
  use `none` for both degraded provenance fields.
- `join_policy`: `single-fragment` (exactly one);
  `adjacent-fragments` (two or more consecutive `md-lines` fragments in one
  source); `separate-fragments` (two or more ordered fragments kept visibly
  separate). No policy inserts hidden bytes.
- Every fragment has a positive explicit order, a source and packet binding,
  `source_relation = frozen-source`, `byte_role = exact-source-bytes`, the
  fragment SHA-256, and canonical base64 of the exact located bytes. Version
  1 supports exact reopening only for `md-lines`; unsupported locator schemes
  use `degraded-non-exact` until a separately reviewed verifier exists.
- `exact_evidence_hash` is SHA-256 over UTF-8
  `aleph-exact-evidence/v1` plus NUL followed, in declared order, by each
  fragment encoded as an unsigned 64-bit big-endian byte length plus its exact
  bytes. Length framing preserves boundaries without silently joining source
  text.
- A transformation's `output_role` is `rendered` or `normalized`; its output
  text has its own UTF-8 SHA-256. For exact evidence, both predecessor and
  effective exact-evidence hashes equal the evidence record hash. A
  transformation records mechanical identity, not semantic adequacy.
- A degraded transformation is rendered and explicitly non-exact. Its source
  binding does not prove the rendering matches inaccessible bytes, OCR,
  layout, or source meaning, and it cannot support a packet as exact evidence.

<!-- example -->
| PKT-0007 | SRC-101 | L5-L8 | sha256:aa10… | "Gating appears to improve member retention: members who must hold to stay in tend to stick around longer…" | 1 | active |

## T3.2 Claim inventory → `runs/<run-id>/ledgers/claim-inventory.md`

```markdown
# Candidate-Claim Inventory — ⟨RUN-slug⟩
| claim_id | normalized claim | packets | sources | claim_type | disposition | rationale | judged_by | verified | status |
|----------|------------------|---------|---------|-----------|-------------|-----------|-----------|----------|--------|
```

Column rules:

- `packets`: comma-joined `PKT-…` (≥1). `sources`: derived union of those
  packets' `SRC-…` — kept denormalized because Précis §4 renders from it.
- `normalized claim` is semantic restatement, never an exact-evidence field.
  Normalization must leave every cited packet's exact fragment records and
  predecessor/effective exact-evidence hashes unchanged.
- `claim_type` (provisional set, Q5): `factual` | `design-intent` |
  `constraint` | `preference` | `open-question`.
- `disposition`: exactly one of the seven (`carried`, `merged`, `deferred`,
  `excluded-with-reason`, `backgrounded`, `judged-non-load-bearing`,
  `unresolved`); blank only between S3 and S5.
- `rationale`: one line, mandatory for every disposition except plainly
  `carried`; for `excluded-with-reason` it IS the reason and must also map to
  a negative boundary when scope-based.
- `judged_by`: worker/actor id. `verified`: blank | `VER-…` refs.
- **Précis §4 rendering:** exactly `claim_id | normalized claim | source(s) |
  disposition`, `active` rows only.

<!-- example -->
| CC-104 | Token gating is associated with improved member retention/engagement | PKT-0007, PKT-0031, PKT-0064 | SRC-101, SRC-102, SRC-104 | factual | merged | canonical retention claim; absorbs CC-113, CC-114 | normalizer-judge | VER-0032 | active |

## T3.3 Disposition ledger → `runs/<run-id>/ledgers/disposition-ledger.md`

```markdown
# Disposition Ledger — ⟨RUN-slug⟩
| disposition | count | claim_ids |
|-------------|-------|-----------|
| carried | ⟨n⟩ | ⟨…⟩ |
| merged | ⟨n⟩ | ⟨…⟩ |
| deferred | ⟨n⟩ | ⟨…⟩ |
| excluded-with-reason | ⟨n⟩ | ⟨…⟩ |
| backgrounded | ⟨n⟩ | ⟨…⟩ |
| judged-non-load-bearing | ⟨n⟩ | ⟨…⟩ |
| unresolved | ⟨n⟩ | ⟨…⟩ |
| **total** | **⟨n⟩** | all candidate claims accounted for |
```

Rules: recomputed (never hand-edited) after any inventory change; all seven
rows always present even at count 0 — a zero row is information; total equals
the inventory's `active` row count.

## T3.4 Merge map → `runs/<run-id>/ledgers/merge-map.md`

```markdown
# Duplicate / Merge Map — ⟨RUN-slug⟩
| canonical | absorbs | basis | provenance retained | corroboration | status |
|-----------|---------|-------|--------------------|--------------| -------|
```

Rules: `provenance retained` lists the union source set and must be a
superset of every absorbed claim's sources (the C8 invariant); `corroboration`
= `independent` (distinct origins genuinely agree) | `restatement` (same
origin echoed) — feeds evidence roles; contradictory claims never appear
here — a contradiction discovered during merging is recorded in the run log
and both claims go/stay `unresolved`.

<!-- example -->
| CC-104 | CC-113, CC-114 | same underlying retention claim, three wordings | SRC-101 + SRC-102 + SRC-104 | independent | active |
