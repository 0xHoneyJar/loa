# Templates 03 — Extraction and Claims

## T3.1 Packet index → `runs/<run-id>/ledgers/packet-index.md`

```markdown
# Packet Index — ⟨RUN-slug⟩

## Packets
| packet_id | source_id | locator | span_hash | quote | criterion | status |
|-----------|-----------|---------|-----------|-------|-----------|--------|

## Per-source completion  <!-- one row per source; S2 DoD needs every row -->
| source_id | walked | packets | declared complete by | note |
|-----------|--------|---------|----------------------|------|
```

Column rules:

- `locator` uses the source's scheme from the corpus manifest (`L118-L131`,
  `M14:S2`). `span_hash` = sha256 of the exact span bytes at freeze.
- `quote`: tight verbatim quote, ≤ ~60 words; longer spans quote the
  load-bearing sentence(s) and rely on the locator for the rest.
- `criterion`: the admission-criterion number from T2.2. A walked span that
  matched an exclusion class gets **no row** (that is the recorded
  two-level boundary); a span refused by a classifier gets a row with
  `criterion = refusal-blocked` so completeness accounting still balances.
- `status`: `active` | `superseded-by:PKT-xxxx` | `retracted:⟨reason⟩`.

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
