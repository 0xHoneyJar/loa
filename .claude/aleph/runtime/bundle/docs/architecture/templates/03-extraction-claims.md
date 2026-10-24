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
```

Column rules:

- `locator` uses the source's scheme from the corpus manifest (`L118-L131`,
  `M14:S2`). `span_hash` = sha256 of the exact span bytes at freeze.
- In `aleph-exact-evidence/v1`, use one packet per exact fragment. `quote` is
  a bounded display preview only and is never exact evidence. Run formats
  `1.1.0-provisional`, `1.2.0-provisional`, `1.3.0-provisional`, and
  `1.4.0-provisional`
  require this marker and the three versioned tables once S2 is reached. Historical
  `1.0.0-provisional` and pre-versioned packet ledgers without the marker
  retain their predecessor behavior and are not reinterpreted.
- `criterion`: the admission-criterion number from T2.2. A walked span that
  matched an exclusion class gets **no row** (that is the recorded
  two-level boundary); a span refused by a classifier gets a row with
  `criterion = refusal-blocked` so completeness accounting still balances.
- `status`: predecessor formats retain `active` |
  `superseded-by:PKT-xxxx` | `retracted:⟨reason⟩`. In run format 1.3 and later,
  durable PKT/CC rows use `active`; unit identity currentness is derived from
  T3.3a lineage instead of encoded in the status cell.
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

## T3.2 Source walk → `runs/<run-id>/ledgers/source-walk.md`

```markdown
# Source Walk Ledger — ⟨RUN-slug⟩

- source_walk_format: aleph-source-walk/v1
- source_position_format: zero-based-utf8-byte-half-open/v1

## Primary walk intervals
| walk_id | source_id | start_byte | end_byte | outcome | packet_ids | criterion_ref | producer_invocation_id | closure_state | reason | closure_note |
|---------|-----------|------------|----------|---------|------------|---------------|------------------------|---------------|--------|--------------|

## Extraction events
| event_id | source_id | start_byte | end_byte | shared_position_key | event_ordinal | packet_id | origin | producer_invocation_id | status |
|----------|-----------|------------|----------|---------------------|---------------|-----------|--------|------------------------|--------|

## Resume cursors
| cursor_id | source_id | byte_offset | shared_position_key | next_event_ordinal | predecessor_walk_id | predecessor_event_id | source_hash | reason |
|-----------|-----------|-------------|---------------------|--------------------|---------------------|----------------------|-------------|--------|

## Fresh gap reviews
| gap_review_id | source_id | producer_invocation_id | reviewer_invocation_id | review_basis_cursor_id | review_basis_digest | result | candidate_start_byte | candidate_end_byte | proposed_packet_id | reconciliation_event_id | status | note |
|---------------|-----------|------------------------|------------------------|------------------------|---------------------|--------|----------------------|--------------------|--------------------|-------------------------|--------|------|

## Per-source completion
| source_id | source_hash | source_length_bytes | final_cursor_id | gap_review_ids | completion_state | declared_by | note |
|-----------|-------------|---------------------|-----------------|----------------|------------------|-------------|------|
```

Column rules:

- Coordinates are zero-based absolute offsets into the exact frozen UTF-8
  bytes. Intervals are half-open `[start_byte, end_byte)`, may not split a
  UTF-8 code point, and partition each completed source from byte `0` through
  its exact byte length without holes or overlaps.
- Primary outcomes are `admitted`, `no-candidate-observed`, `excluded`,
  `deferred`, or `unsupported`. Admitted intervals use
  `admission:<criterion-number>` and packet IDs; excluded intervals use
  `exclusion:<class>`. Other outcomes use `none`.
- `deferred` is `open` or `resolved`; both require a reason, and `resolved`
  also requires a closure note. `unsupported` remains `open` in this format
  and blocks completion.
- Extraction events bind packets to exact source positions. Events at the
  same position share one `SP-<digits>` key and use unique contiguous
  ordinals. Primary intervals never overlap; only exact same-position event
  rows may share coordinates. Each event interval must be contained in exactly
  one mechanically mapped exact fragment for its packet; a packet with an
  unmappable locator cannot satisfy the 1.2 exact-position contract.
- A cursor is an actual checkpoint naming the **next unprocessed** source
  position or event. A pause after one same-position event stays at that byte
  position and names the next ordinal; uninterrupted siblings need no
  intermediate cursor. Source-end means no bytes remain structurally
  unwalked, not that semantic recall is perfect. `reason` is exactly
  `initial`, `progress`, `bounded-pause`, `resumed-shared-position`, or
  `source-complete`.
- Gap-review results are `no-gap-candidate-found`, `gap-candidate-found`, or
  `cannot-determine`. The reviewer invocation must differ from the primary
  producer. Every row binds the terminal primary source-end cursor and a
  recomputable digest of the frozen source, exact S1 criteria bytes, ordered
  primary walk/events, primary packet exact-evidence identities, and that
  cursor. A found candidate is `open` with both future canonical IDs set to
  `none`; after single-writer reconciliation it is `reconciled` with one
  committed event whose interval equals the candidate and is contained in the
  proposed packet's exact fragment. Same-position reconciliation uses the next
  contiguous event ordinal without rewriting primary walk/cursor history.
  `cannot-determine` blocks completion.
- `completion_state = complete` requires full interval coverage, a source-end
  cursor, no open interval or event, at least one distinct gap review, and no
  open or indeterminate gap result. A blocked row's final cursor must be the
  current frontier, not a stale historical checkpoint. This is procedural
  closure only.

## T3.3 Claim inventory → `runs/<run-id>/ledgers/claim-inventory.md`

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
  disposition`. Predecessor formats retain their active-row rule; 1.3 and later render
  lineage-current claims only.

<!-- example -->
| CC-104 | Token gating is associated with improved member retention/engagement | PKT-0007, PKT-0031, PKT-0064 | SRC-101, SRC-102, SRC-104 | factual | merged | canonical retention claim; absorbs CC-113, CC-114 | normalizer-judge | VER-0032 | active |

## T3.3a Unit lineage → `runs/<run-id>/ledgers/lineage.md`

```markdown
# Unit Lineage — ⟨RUN-slug⟩

- lineage_format: aleph-lineage/v1

| lineage_id | owner_stage | type | predecessors | successors | basis | established_by |
|------------|-------------|------|--------------|------------|-------|----------------|
```

Rules for run format 1.3 and later: `LIN-NNNN` is unique; owner stage is S2-S4; type
is exactly split/merge/replace/supersede/duplicate/reject/exclude/no-claim;
cardinality follows the artifact contract; `none` is used only when the event
has zero successors. Packet-to-claim ancestry remains claim provenance.
Lineage is append-only and predecessors are never rewritten or resurrected.

## T3.3b Typed relations → `runs/<run-id>/ledgers/relations.md`

```markdown
# Typed Relations — ⟨RUN-slug⟩

- relation_format: aleph-relations/v1

| relation_id | owner_stage | family | type | source_kind | source_id | target_kind | target_id | target_source_id | target_locator | target_span_hash | record_state | null_reason | basis_packet_ids | proposed_by | review_subject_digest | reviewed_by |
|-------------|-------------|--------|------|-------------|-----------|-------------|-----------|------------------|----------------|------------------|--------------|-------------|------------------|-------------|-----------------------|-------------|
```

Rules for run format 1.4:

- This exact 17-column table is the sole canonical relation table. IDs are
  unique `REL-NNNN`. Do not add scheme, append-time, status, authority,
  correction, replacement, supersession, version, support, or evidence-role
  fields.
- Families/types are closed: `claim-dependency /
  semantic-prerequisite`; `source-context / antecedent-context |
  qualifier-context | configuration-context`; `formal-reference /
  structural-anchor | notation-definition`; `discourse /
  continuation-context | parallel-contrast-context`.
- Sources are current `CC` or `PKT`. Asserted targets are current `CC`/`PKT`
  or an exact `source-locus`; other states use `target_kind = null` and
  `none` in every target-value field. A source locus derives its scheme from
  `target_source_id`'s frozen manifest row and must reopen/hash exactly.
- `record_state` is `asserted`, `unresolved-target`, `explicitly-absent`, or
  `indeterminate`. `not-applicable` remains a review-only outcome and creates
  no row. Concrete subtype, family-level, and taxonomy-level indeterminate
  scopes remain distinct.
- `basis_packet_ids` is a nonempty ordered comma list. `proposed_by` is
  `human:<actor-slug>` or `invocation:<producer-invocation-id>`.
- `review_subject_digest` hashes the fixed-order compact JSON
  `aleph-relation-review-subject/v1` subject containing all 14 pre-review
  fields from `owner_stage` through `proposed_by`, with packet IDs as an
  ordered array. `reviewed_by` names one existing `upheld` verdict targeted
  exactly to `relation-review-subject:<digest>`.
- Canonical rows are written only at S4 closure after lineage currentness is
  established. Before closure the artifact is absent or marker plus empty
  table; after closure/S5 it is read-only.
- A relation never asserts support or changes S6 evidence-role accounting.

## T3.4 Disposition ledger → `runs/<run-id>/ledgers/disposition-ledger.md`

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
rows always present even at count 0 — a zero row is information. Predecessor
formats retain active-row totals; in 1.3 and later total equals the lineage-current claim
count.

## T3.5 Merge map → `runs/<run-id>/ledgers/merge-map.md`

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

### 1.3+ merge-map rule

For run format 1.3 and later, `canonical` is a newly materialized successor CC and
`absorbs` lists its lineage predecessors. The same predecessor/successor set
must appear in one `merge` or `duplicate` lineage event. Absorbed historical
claims do not receive an S5 `merged` disposition merely because they were
terminalized structurally.

## T3.6 Representation use receipts — run format 1.6

The following numbered contract defines 1.6 material use. Section 6–10
references resolve to T2.3 in `02-corpus-intake.md`. Existing packet, lineage,
relation, and ambiguity contracts retain their ownership.

## 11. Evidence, claims, relations, and use receipts (future T3.6)

### 11.1 Preserve Slice 1

Every packet still has exactly one exact evidence record and a mechanically
reopened `md-lines` fragment. Existing length-framed evidence hashing and join
policies are unchanged. Ordered discontiguous OBJ bindings never become an
unrecorded single string. Use separate-fragments in packet evidence where
applicable; any visible joining belongs in a rendered transformation.

For a used SRC binding, its byte interval must be covered by the packet basis
where that use asserts evidence, not merely by a nearby source ID. A complete
line packet can cover several cell substrings; an empty cell has a valid
zero-length position within that packet interval. AST bytes alone never
materialize an exact packet or satisfy CC packet provenance.

### 11.2 Canonical use table

```text
| use_id | owner_stage | subject_kind | subject_id | basis_packet_ids | requirements | use_state | fidelity_claim | limitation_refs | reason | established_by | review_subject_digest | reviewed_by |
```

- Subject kinds: `PKT`, `CC`, `REL`, or `OBJ`. Owner stage respectively S2,
  S3/S4, S4, or S2/S3/S4.
- Exactly one receipt per canonical PKT/CC/REL; append in the same transaction
  as its subject. OBJ receipts preserve failed candidates/limitations without
  manufacturing a packet, claim, or relation; multiple distinct OBJ receipts
  are permitted and remain historical.
- Basis is an ordered unique list of existing exact PKTs, nonempty except OBJ limitation
  receipts. PKT basis is exactly itself. CC basis exactly equals its packet
  provenance in its ledger order. REL basis exactly equals its existing
  `basis_packet_ids`, including order. This overrides default set sorting and
  preserves the adopted relation review subject.
- `requirements` is a nonempty ordered JSON array of objects with keys
  `object_id`, `feature`, `binding_ids` in that order. No duplicate tuple.
  Binding IDs are an ordered subset of that OBJ's bindings; empty is permitted
  for a missing feature or a coordinate/association-only requirement.
- Feature enum: `text-bytes`, `table-grid`, `header-association`,
  `caption-association`, `formal-structure`, `image`, `chart-values`,
  `spatial-region`.
- `use_state`: `usable` or literal `CANNOT_DETERMINE`.
- `fidelity_claim`: `none`, `exact-representation`, or `gold`. Gold is a
  recognized forbidden assertion, always rejected in this format; no golden
  adoption surface is created.
- Limitation refs: set of REP/OBJ/ASC IDs from the used sources; reason is none
  for usable, nonempty for CANNOT_DETERMINE, whose limitation refs are nonempty.
- Established-by retains existing human/producer-invocation reference syntax;
  it does not confer authority. No repair of A4-16 is implied.

Default-text receipts require text-bytes with the source's default text OBJ.
Its whole-file BND identifies the carrier; for PKT/CC/REL the usable bytes are
exactly its intersection with that receipt's packet-basis intervals, never the
whole file as additional evidence. This is the sole whole-file-binding
exception. For imported objects, selected SRC BND intervals must instead lie
within the exact packet-basis union. A requirement needing
the whole table/header/caption must obtain the necessary packets; no implicit
context imports.

Non-text structures can be inspected as bounded context using supplied
objects/ASTs from the same source. This does not turn their bytes into packet
evidence. Every requirement must belong to a basis source (OBJ-only missing
candidates use their subject's source). Structure evidence drawn from an AST
must be identified as rendering/export context, and cannot claim
exact-representation fidelity.

### 11.3 Mechanical availability predicate

One Core predicate evaluates requirements without reading claim meaning:

| Feature | Available only when |
|---|---|
| text-bytes | Selected nonempty BND list reopens textual bytes. It may be a degraded formal object's exact retained text. Empty text bytes are still a declared value. |
| table-grid | OBJ is table, grid_state available, and section 7 grid checks pass. |
| header-association | OBJ is cell, its ASC is available, and every named header has available bound bytes. |
| caption-association | OBJ is table/formal/figure, its ASC is available, and every caption has available bound bytes. |
| formal-structure | OBJ is formal, structure_state available, notation source-markup or renderer-export, and its bindings or structure IDs reopen supplied structure. Flattened-text can never satisfy it. |
| image | OBJ is available image with image bytes; this proves presence, not worker vision capability. |
| chart-values | OBJ is chart-values with textual machine-readable binding, or figure with available values_state and nonempty available values IDs. No image-only binding. |
| spatial-region | OBJ is region with valid non-null supplied page/space/box. |

A well-formed request for a feature absent from that object is **unavailable**,
not grounds to synthesize the feature. References to nonexistent IDs, wrong
binding owners, or malformed tuples are structural failures.
If any requirement is unavailable, use_state must be CANNOT_DETERMINE.
All available requirements permit usable but do not require it: semantic
insufficiency or worker modality limits may still produce CANNOT_DETERMINE.
Thus deterministic availability is not entailment or semantic PASS.

Exact-representation requires usable, available named objects and ancestors,
all named features available, SRC-only binding closure, original-capture
origin, and no relevant degraded/unsupported/indeterminate association.
Rendering/export contexts cannot meet it. Packet exactness remains separately
valid even when this stronger representation claim fails.

CANNOT_DETERMINE receipts remain non-affirmative OBJ candidates; canonical
CC/REL rows require usable receipts. This does not forbid a limited claim such
as “the capture contains this flattened text”: its declared requirement is
text-bytes only, its fidelity claim none, and fresh review tests that it does
not assert the missing equation. Existing unresolved/indeterminate REL rows
may likewise have usable receipts for recording a typed-null judgment; this
does not declare their target available.

Each CANNOT_DETERMINE blocks that proposed use, not unrelated work. It never
waives an existing stage DoD: an indeterminate S2 gap review still blocks S2,
and a packet with neither a valid claim nor permitted no-claim closure still
blocks S3 under lineage rules. A later narrower usable candidate does not
erase the failed interpretation or its limitation. No automatic
complete/resolved flag is generated for a missing feature.

### 11.4 Exact review and existing relations

Use review-subject digest is SHA-256 over UTF-8 compact fixed-order JSON:
`format = aleph-representation-use-subject/v1`,
`representation_inventory_hash`, followed by the use's fields from
`owner_stage` through `established_by` in table order (list/requirement cells
as JSON values), then `subject`, then `packet_evidence_hashes`.
The latter is the ordered array of each basis packet's full exact-evidence
hash, including repeated evidence hashes when packets share one evidence
record. `subject` is the following immutable projection in listed key order:

- PKT: `source_id`, `locator`, `span_hash`, `criterion`;
- CC: `normalized_claim`, `packets`, `sources`, `claim_type`;
- REL: the existing `aleph-relation-review-subject/v1` subject object;
- OBJ: `object_id`, `representation_inventory_hash`.

Packets/sources in the CC projection are ordered arrays in canonical ledger
order. No later disposition or preview belongs in this digest.
The writer reserves canonical subject IDs before review and verifies that the
written projection equals the reviewed one. Reservation alone is not a durable
claim or relation. Exclude USE ID and review fields.
`reviewed_by` is none or one existing VER with exact target
`representation-use-subject:<digest>`. Changing a subject requires new review,
never reusing a verdict over different bytes.

Before a canonical CC/REL use with any non-text feature or AST binding is written, require
one fresh L2F upheld verdict for that exact subject. Text-only uses retain the
existing stage's review coverage; no Slice 7 universal atomicity review is
introduced. PKT capture receipts and OBJ limitations may have reviewed_by none.
An L2F cannot-determine verdict cannot authorize an affirmative CC/REL write.

REL taxonomy, its 17 columns, review digest, endpoint kinds, and immutable C1
boundary remain unchanged. A table/header target still resolves through
existing exact PKT/CC/source-locus evidence, with the use receipt refining the
declared material consulted. For an asserted source-locus use, selected target
SRC bindings must lie inside its exact reopened target span; acquire packets
for any additional evidence basis. OBJ IDs are not new REL endpoints.
Unavailable targets retain the existing typed-null contract. A material
receipt never supplies support, relation meaning, disposition, or authority.

Slice 3 alone owns PKT/CC successors. New successor receipts are explicit;
old receipts remain historical and are not retargeted. Merge/duplicate packet
provenance union remains required. No automatic inheritance of requirements,
loss of predecessor limitations, or new lineage type is allowed.
S5 ambiguity and OQ-01 consume this material only as bounded source context;
they do not select missing headers, formal readings, or chart values. Their
canonical relation set and reviewed authority basis remain immutable.

Existing post-S0 T3.1 rendered previews and normalized transformations remain
separate worker outputs with their existing output hashes. They are not newly
admitted ingestion ASTs, cannot add structure to the frozen inventory, and
cannot satisfy an unavailable feature. This distinction prevents ordinary
normalization from becoming an illicit post-freeze rendering pipeline.

### 11.5 Downstream visibility without invented claims

The existing unresolved-queue table remains CC-only. Its rows for an actual
unresolved/deferred claim name applicable USE/OBJ/ASC limitations in the
existing blocking/evidence field. Never insert an OBJ as a claim or fabricate
an open-question claim merely to fit that queue.

For 1.6 at ASSEMBLED and later, add this exact table inside the existing
Précis section 17 (do not change the v0 section headings):

```text
| limitation_ref | source_id | representation_state | reason |
```

The rows are the union of every non-available REP/OBJ/ASC and every
CANNOT_DETERMINE USE, unique and ASCII-sorted by limitation_ref. Source ID is
the owning REP's SRC; a USE naming several source limitations gets one row per
source, sorted by source_id after limitation_ref. USE state is the literal
CANNOT_DETERMINE; other states use section 8. Copy the recorded reason
losslessly with existing Markdown escaping. The key is
`limitation_ref + source_id`. Empty population retains the empty table.
K2.18 compares the table to that declared union. This is structural accounting,
not a judgment about importance, resolution, or acceptance.

The compiler produces this summary from retained artifacts without modifying
the sealed uses ledger. It preserves object-only failed candidates as known
incompleteness even when no claim was materialized. Projection consumers retain
the Précis limitations under their existing acceptance/trace doctrine; Slice 6
does not redesign projection formats or deterministically infer propagation.

## T3.7 Semantic review (1.7)

The following operative contract retains adopted Slice 7 sections 5–15.
Numbered cross-references refer to that adopted contract. Activation requires
the cumulative semantic-unit-review capability; retained predecessor runs
keep their existing contracts. Structural checking never judges meaning.

```text
Treat exact source evidence, proposed semantic fields, and review judgments
as different records. Propose or challenge one bounded semantic subject.
Preserve source-supported scope, conditions, qualifiers, modality, attribution,
comparators, metrics, and content roles explicitly. Do not add facts, strengthen
or weaken source language, or hide a result and its interpretation in one
unexamined paraphrase. A packet or sentence is not automatically atomic.
Context must be named and source-bound; proximity does not create evidence.
Use only the declared material and legal context. When the frozen evidence
cannot settle the decision, preserve CANNOT_DETERMINE and name what is missing.
Relations are not support edges. You do not write ledgers, grant acceptance,
choose a human authority action, or certify your own semantic adequacy.
```

### 5. Exact grammar and semantic ownership

All new objects are closed: every listed key is required and unknown or
duplicate keys fail. No optional freeform extension map exists. Canonical JSON
is UTF-8, compact, listed key order, no BOM or terminal newline. JSON strings
preserve Unicode and whitespace exactly; no text normalization. Reject
unpaired surrogates and duplicate members using the existing strict Core
parser. Integers are safe nonnegative decimal integers without sign, exponent,
fraction, or negative zero. Positive ordinals start at one. Hashes use
`sha256:` plus 64 lowercase hex digits.

Run-local `SEM-NNNN` and `SMR-NNNN` IDs use the Slice 6 new-ID grammar:
uppercase prefix, hyphen, at least four decimal digits, at least one nonzero.
Existing PKT/CC/LIN/VER/USE/OBJ/etc. grammars are unchanged. Subject-local
`A1`, `U1`, `C1`, `F1` identifiers are contiguous positive decimal ordinals
without leading zeroes, in array order, and have no cross-subject meaning.
Use JSON null only where specified; absence is never an omitted key.

Every field below has two distinct owners: a producer proposes its semantic
content and L2S challenges it; Core owns only serialization, references, and
structural invariants. The orchestrator can allocate IDs, reopen bytes, and
serialize mechanically, but cannot fill missing semantic fields from prose.
Humans do not select correct semantic values through authority gates.

#### 5.1 Source anchors

An anchor is a precise selection within a mechanically reopenable frozen
source locus, not a new packet or locator scheme:

```text
Anchor = {
  anchor_id, source_id, source_hash, locator, span_hash,
  start_byte, end_byte, selection_hash, exact_bytes_base64, packet_ids
}
```

`locator` retains the source's existing Core scheme (currently exact
`md-lines`). `span_hash` hashes that whole locus. Absolute half-open UTF-8
byte offsets select within it; bytes and `selection_hash` must match the
source and may not split a code point. `packet_ids` is an ordered unique
subset of the subject's packet basis whose exact fragments cover that
selection; it is empty for inspection-only unpacketed context. At least one
packet must fully cover a proposition-bearing anchor used by a canonical
claim. Source/fragment/evidence hashes are independently reopened.

An anchor is not a declaration that its content supports a proposition.
An empty `packet_ids` never imports the surrounding text as evidence.
Load-bearing source context for a claim must first obtain exact packets.
AST/rendering bytes are not admitted through this text-anchor type: they are
addressed exclusively by existing `material_use` requirement indexes and
the Slice 6 bounded view.

The raw producer type is exactly
`AnchorInput={anchor_id,source_id,locator,start_byte,end_byte,exact_bytes_base64}`.
The orchestrator computes the remaining hashes and packet bindings from the
frozen source and reserved/materialized exact evidence. It cannot change
the selection or source bytes. Sealed subjects contain all ten keys in
Anchor order above.

#### 5.2 Repeated semantic field envelope

Each semantic facet below uses this exact envelope:

```text
Facet<T> = { state, items, basis_anchor_ids }
state = present | not-expressed | CANNOT_DETERMINE
```

`basis_anchor_ids` is nonempty, unique, and in anchor order. For `present`,
`items` is nonempty and every item's anchors are included in the basis.
For `not-expressed`, `items=[]`; the producer claims only that the bounded
unit/context expresses no such facet. This is not a world-level absence
claim. For `CANNOT_DETERMINE`, `items=[]` and an unresolved finding must name
the exact facet path. Source-silent scope does not require invented population,
date, or geography. Partial uncertainty is preserved by a finding naming the
unknown dimension; known items may be retained in a `present` facet only when
the finding explicitly identifies the remaining unknown dimension.

Each item uses `{kind, source_text, anchor_ids}` unless an exact extension is
specified below. `source_text` is the UTF-8 decoding of exactly one named
anchor; that anchor is first in `anchor_ids`. Additional anchors provide
necessary context without silently concatenating text. Interpretation of
`kind` is semantic. Code checks exact source-text equality and legal enums,
not whether that label is correct. Item order is source-anchor order, then
kind in ASCII order for the same anchor; exact duplicate items fail.

#### 5.3 Atomic units and closed facet vocabularies

```text
AtomicUnit = {
  unit_id, proposition, proposition_anchor_ids,
  claim_roles, scope, conditions, qualifiers, modality, attribution,
  comparator, metric
}
```

`proposition` is nonempty proposed normalized text, never exact source text
by declaration. `proposition_anchor_ids` is nonempty, unique, in anchor
order. Every facet key is present even if its state is `not-expressed` or
`CANNOT_DETERMINE`. This requires explicit review slots, not fabricated
semantic values.

| Facet | Exact item `kind` enum | Meaning / boundary |
| --- | --- | --- |
| `claim_roles` | `result-observation`, `method-procedure`, `interpretation-inference`, `background-context`, `definition`, `recommendation`, `attribution-report`, `limitation-uncertainty` | Roles of the proposed assertion/content, not claim–source support weights |
| `scope` | `population`, `temporal`, `geographic`, `experiment-task`, `document-universe`, `quantified`, `exclusion-restriction` | Only source-expressed restrictions; missing dimensions remain unspecified |
| `conditions` | `condition`, `precondition` | Explicit conditions under which this unit holds; never inferred operating assumptions |
| `qualifiers` | `degree`, `frequency`, `approximation`, `limitation`, `comparative`, `exception`, `confidence-uncertainty` | Preserve source force; no hedge deletion or added confidence |
| `modality` | `observed-descriptive`, `possible`, `capable`, `normative-should`, `obligatory-must`, `intended-designed`, `predicted-expected`, `hypothetical`, `counterfactual`, `recommended` | No possibility-to-actuality or recommendation-to-fact conversion; spelling is not a lexical classifier |
| `attribution` | `source-author`, `quoted-entity`, `cited-external-in-corpus`, `reported-belief-opinion`, `system-model-interpretation` | Speaker/provenance of the assertion, not external truth |
| `comparator` | `comparison-basis` | Preserve what is compared, to what, and on which dimension |
| `metric` | `measured-quantity` | Preserve measured result together with its metric and stated unit |

`claim_roles.state=not-expressed` is illegal for an affirmative unit: a
producer must propose a role or acknowledge indeterminacy. Multiple roles are
permitted when inseparable; no automatic one-role-per-claim rule exists.

Attribution items add `attributed_to` after `source_text` and before
`anchor_ids`. It is nonempty source-supported speaker/entity text, or
literal `unspecified-in-source`. For `system-model-interpretation` it is
literal `producer-model`; the anchor identifies the source basis, not a claim
that the source uttered the interpretation. Such a unit cannot be committed
as an S3 source-entailed affirmative claim. Retain it as a rejected/indeterminate
candidate unless a new source-supported proposition receives its own review.
There is no external lookup field or implicit dereference of a cited work.

Comparator items add `subject_anchor_ids`, `baseline_anchor_ids`, and
`dimension_anchor_ids` before `anchor_ids`; metric items add
`quantity_anchor_ids`, `value_anchor_ids`, and `unit_anchor_ids`.
Each array is ordered/unique and included in `anchor_ids`. The first two
arrays in each item are nonempty. The third may be empty when the source does
not express a dimension/unit; an unresolved finding is required if that
absence prevents safe interpretation. No numeric calculation, unit conversion,
or comparator completion is performed by the checker.

These fields distinguish a metric from its result and a comparison from its
baseline without requiring them to become separate assertions. A source
metric definition that is independently asserted may instead be another
unit, with a context/coupling record.

#### 5.4 Context records

```text
Context = {
  context_id, kind, applies_to_unit_ids, anchor_ids,
  material_requirement_indexes, use
}
kind = necessary-local | attribution | definition-terms | condition-scope
     | representation-layout | discourse
use = required-for-interpretation | inspection-only | non-evidentiary
```

`applies_to_unit_ids` is nonempty and unit-ordered. At least one of
`anchor_ids` or `material_requirement_indexes` is nonempty; both lists are
ordered and unique. Requirement indexes are zero-based indexes in the
candidate's existing `material_use.requirements`, not a second material
schema. Only `representation-layout` can use those indexes. A discourse
record defaults to no evidential effect; the producer must explicitly
declare and defend any required interpretive use.

Proposition-bearing bytes belong in `proposition_anchor_ids`; context
records label other needed or considered material. The same bytes can play
both roles only when explicitly referenced in both places and reviewed.
Required textual context for canonical CC content must be packet-covered.
Inspection-only context can provoke a widening request or challenge, but
cannot justify extra content in the claim. Nearby unrelated text should be
omitted; if shown as a distractor it must remain `inspection-only` or
`non-evidentiary`. Proximity is not an evidentiary role.

#### 5.5 Atomicity and source-composition couplings

```text
Semantics = {
  atomicity, units, contexts, couplings, relation_proposals,
  unresolved_findings
}
atomicity = single-assertion | multiple-separable | inseparable-context
          | CANNOT_DETERMINE | no-claim
Coupling = { kind, unit_ids, anchor_ids, treatment }
kind = result-interpretation | attribution-content | comparison-comparator
     | metric-result | condition-claim | required-context
treatment = keep-distinguishable | keep-together | CANNOT_DETERMINE
```

Units and contexts use their exact schemas above. Coupling arrays preserve
source order; duplicate tuples fail. `unit_ids` is a nonempty ordered subset
of the units, and `anchor_ids` is nonempty. `keep-distinguishable` names at
least two units; `keep-together` names exactly one. An indeterminate treatment
requires a finding and cannot authorize an affirmative normalization.

`single-assertion` or `inseparable-context` has exactly one unit.
`multiple-separable` has at least two. `CANNOT_DETERMINE` may retain any
number of tentative units; none is authorized as an affirmative claim.
`no-claim` has no units, contexts, or couplings and still requires exact
basis anchors plus a fresh no-claim review. It is not a way to discharge
uncertainty by relabeling it absence.

A source may grammatically combine an observation and its interpretation.
The producer can represent two units and their `result-interpretation`
coupling, or one explicitly multi-role unit if inseparable. L2S must attack
the decision. A coupling records how this source passage composes assertions;
it does not mean one claim proves another, confer corroboration, or create a
new Slice 4 relation family.

#### 5.6 Structured unresolved findings

```text
Finding = {
  finding_id, field_path, code, anchor_ids, material_requirement_indexes,
  unknown_dimension, missing, requested_context
}
code = atomicity-indeterminate | context-insufficient | scope-indeterminate
     | condition-indeterminate | qualifier-indeterminate | modality-indeterminate
     | attribution-indeterminate | role-indeterminate | referent-unresolved
     | comparator-indeterminate | metric-indeterminate | material-unavailable
     | relation-deferred | interpretation-unsupported
```

`field_path` is exactly one of section 9's enumerated coverage paths for
this subject, including `/material_use` when appropriate. No arbitrary
pointer or implementation-chosen nested field matcher is allowed.
`unknown_dimension` is `none`, a scope-kind enum, or `comparison-dimension`
or `measurement-unit`. `missing` is nonempty explanatory text; it cannot
select an answer or authorize a write. `anchor_ids` and requirement indexes
obey the same rules as context; their union is nonempty.
`requested_context` is an ordered array of exact
`{source_id, locator, purpose}` objects; purpose is `local-context`,
`same-source-referent-search`, or `material-inspection`. Requests may be
empty when frozen evidence cannot supply the missing material.

These are requests, not admitted context. They may name only already frozen
sources legal for the role. No URL, new source, answer-key locator, wildcard,
or outside-corpus candidate is accepted. A whole-source referent request
routes to the existing Slice 5 bounded search procedure, not automatic
expansion of an L2S bundle. The source and its result receive new exact
subjects if subsequently supplied.

#### 5.7 Per-field implementation obligations

The mutation IDs refer to section 18. Every field family has an explicit
review task and structural test; no truth test is implied.

| Field family | Semantic owner and reviewer attack | Evidence / absence | Structural rule and mutations |
| --- | --- | --- | --- |
| Atomicity / units | Extractor or normalizer; L2S attacks independent adjudicability and material conflation | Packet/source anchors; indeterminate and no-claim are distinct | Cardinalities and references only; M01, M02, M05, M15 |
| Proposition | Normalizer; L2S attacks additions and strengthening | Exact packet anchors; absent only in no-claim/zero-unit indeterminate | CC text equals sealed sole proposition; M04, M05 |
| Context | Producer; L2S attacks missing necessary and spurious nearby context | Anchors or existing material requirements; empty contexts legal | Legal source boundary, packet coverage, index resolution; M03, M04, M09 |
| Scope | Producer; L2S attacks widened population/time/task/universe | Facet's source basis; absent/unknown explicit | Closed kinds, no forced unspecified dimensions; M01, M02, M05 |
| Conditions | Producer; L2S attacks conditional-to-unconditional changes | Exact source condition anchors | Required key/envelope; M11, M05 |
| Qualifiers | Producer; L2S attacks strengthened/weakened force | Exact qualifier anchors | Required key/envelope; M10, M05 |
| Modality | Producer; L2S attacks actuality/normative/intention leakage | Exact source basis | Closed enum and state, not lexical inference; M13, M05 |
| Attribution | Producer; L2S attacks speaker substitution and imported authority | Frozen attributed words or explicit producer-model label | Speaker field and source binding; M12, M05 |
| Claim roles | Producer; L2S attacks result/interpretation and role conflation | Frozen basis; unknown visible | Closed content-role enum; S6 edge labels forbidden here; M14 |
| Comparator / metric | Producer; L2S attacks lost baseline, unit, or measured quantity | Named role-specific anchor subsets | Reference/cardinality rules, no arithmetic; M03, M05 |
| Couplings | Producer; L2S attacks material distinction or inseparability | Source anchors; unknown finding | Treatment/cardinality; no support semantics; M02, M15 |
| Relation proposals | Existing local relation producer; L2S challenges use in the unit; L3R owns canonical relation review | Existing Slice 4 subject and Slice 6 use | Existing stage/type/endpoint matrix; M03, M16 |
| Unresolved findings | Producer and reviewer independently; no human semantic selection | Exact subject field and missing source/material basis | State/closure consistency, legal requests; M15, M17 |
| Material use | Existing producer/L2F; L2S attacks whether declared needs omit meaning-bearing material | Existing `material_use`, USE and bounded view | Delegate availability, hashes and receipts to Slice 6; M04, M18 |
| Subject/provenance/prompt/profile | Core constructs, host transports; reviewer cannot rewrite | Exact immutable inputs | Recompute digest, match records and pins; M05–M09 |

### 6. Evidence-role reconciliation

The adopted S6 edge roles remain exactly `load-bearing`, `corroborative`,
`contradictory`, `contextual`, `decorative`, `unresolved-source`, with their
existing removal effects and verification vocabulary. The existing
`claim_type` remains `factual`, `design-intent`, `constraint`, `preference`,
`open-question`. Neither enum is renamed or expanded.

`claim_roles` is explicitly a content-function annotation, needed by
SL-01/04. It never writes `ledgers/evidence-roles.md`, predicts an edge's
weight, changes `claim_type`, or mechanically assigns an S5 disposition.
For example a source-author interpretation may be packet-entailed as a
report of that interpretation; it is not thereby a direct observation or
independent support for its conclusion.

S6 receives the reviewed claim facets as read-only preservation/challenge
context alongside its existing legal inputs. It independently judges the
CC×SRC edges and removal effects. No map from `result-observation` to
`load-bearing`, from `background-context` to `contextual`, or from relation
count to corroboration is allowed in Core or an adapter.

### 7. Exact producer-return integration

Keep the current Extractor/Normalizer return members, including all Slice 6
`material_use` objects. The 1.7 return adds exactly one root member:

```text
semantic_units: [{
  output_kind, output_index, review_mode, origin_unit_refs, anchors, semantics
}]
output_kind = packet-candidate | claim-candidate | no-claim-candidate
            | material-candidate
```

`output_index` is a zero-based index into the same return's `packets`,
`claims`, `no_claim_packets`, or `material_findings`, respectively.
The extractor permits packet/material candidates; the normalizer permits
claim/no-claim/material candidates. Exactly one semantic entry must exist
for each item of each applicable array, including degraded candidates;
duplicate selectors, unaccounted outputs, or entries for another role fail.
Selectors and entries are sorted by that listed kind order then index.

`review_mode` is `proposal` or `unresolved-record`, chosen explicitly by the
producer; the latter follows section 9.1. `origin_unit_refs` uses section
15.1's exact grammar, with `[]` for S2 and material-only candidates. The
normalizer supplies the mapping, and Core checks references/coverage without
inventing a semantic mapping.

`anchors` uses AnchorInput from section 5.1. Core completes it mechanically
against the output reservation; no semantic field is filled by Core. The
saved raw return is immutable and distinct from the completed subject.

For an exact packet candidate, one semantic entry describes its ordered
fragment group. Canonicalization still produces one PKT per fragment.
Existing PKT/USE materialization rules apply to each packet: if a returned
requirement is not valid for that packet's basis, refuse it; do not infer a
per-fragment requirement split. A producer can return separate candidates
with explicit valid declarations. This does not change source-walk
positions, shared-position ordinals, or gap accounting.

For a claim candidate, the normalizer's `normalized_claim` must exactly equal
the sole unit proposition for affirmative use, and `packets` equals the
sealed packet basis. A proposed multi-assertion claim is retained for review
but cannot become one canonical affirmative CC; the producer must return
separate candidates after the challenge. This cardinality rule enforces the
producer's own declaration; code does not decide whether an undeclared
compound assertion is actually compound.

A no-claim candidate binds the existing packet/no-claim proposal and has
`atomicity=no-claim`. It must undergo L2S before its existing LIN no-claim
event can close packet accounting. A degraded/material candidate uses
`atomicity=CANNOT_DETERMINE` and preserves its existing OBJ/USE limitation;
it does not obtain a fictitious PKT or CC.

`relation_proposals` contains exactly
`{subject,review_subject_digest,material_use}` for each proposal. `subject`
is the existing complete fixed-order `aleph-relation-review-subject/v1`
object, including all 14 pre-review fields; its digest and existing
MaterialUseInput are unchanged. This is a projection of the existing Local
Relation Producer contract. Rationale/flags remain in the retained raw
relation-producer return and are never embedded in semantics or L2S context.
Core validates this projection through Slice 4/6 contracts. No new relation
enum, REL ID, or authority field is returned by these workers.
An empty array means no local proposal was made, not that no relation exists.
Explicit absence remains a separately typed and reviewed Slice 4 proposal.

A reserved CC is not a materialized Slice 4 endpoint. A new claim return can
therefore have no claim-level relation proposals yet, while still declaring
all necessary context/facets. Later local relation proposals over admitted
claims remain separately retained under Slice 4; they are not inserted into
an old SEM. If the claim's meaning-bearing fields must change, produce a new
bounded successor and semantic subject. Reservation never relaxes the
existing relation endpoint-existence or stage rules.

Raw producer rationale, notes, flags, or display prose cannot substitute for
any field in the structured semantic contract.

### 8. Immutable review subject and invalidation

Core constructs, serializes, and hashes this exact object in listed order:

```text
SemanticSubject = {
  format, semantic_id, owner_stage, subject_kind, review_mode,
  predecessor_semantic_id, producer_binding_hash, run_binding,
  prompt_parts, reviewer_profile, output_binding, origin_unit_refs,
  origin_context, packet_basis,
  anchors, semantics, material_use, material_views,
  lineage_context, relation_context, ambiguity_context, context_manifest
}
format = aleph-semantic-subject/v1
owner_stage = S2 | S3 | S4
subject_kind = packet-group | claim | no-claim | material-only
review_mode = proposal | unresolved-record
```

`semantic_id` is reserved before review. `predecessor_semantic_id` is `none`
for a first candidate or one retained SEM in the same run; chains are acyclic,
single-parent, and do not supersede PKT/CC identities. Alternative revisions
can reference one predecessor, but only one can discharge the same proposed
output reservation. Others remain visibly non-admitted.
This predecessor links proposal revisions only. Multiple claim predecessors
belong to `lineage_context`/`origin_unit_refs`, not a fabricated SEM merge.

`producer_binding_hash` hashes the retained producer identity tuple in this
order: `{call_id, context_id, raw_return_hash, output_kind, output_index}`.
The tuple is retained with process evidence, not exposed to L2S as a producer
rationale or identity hint. In manual records the call/context values are
distinct recorded pass identifiers, explicitly labeled as manual evidence.
The checker verifies the declared binding; it cannot authenticate a human's
or model's cognitive separation.

`run_binding` has exactly `{run_id, run_format_version, core_digest,
checker_digest, bundle_digest, runtime_snapshot_digest}` from the retained
execution identity. `prompt_parts` is the ordered list of
`{path, selector, digest}` for the exact common preamble, L2S frame, L2S
charter, bounded stage excerpt, semantic contract, and Slice 6 material
constraint block. Selectors use the existing Core-part grammar; bytes must
resolve under the pinned lock. No producer prompt history is included.

`reviewer_profile` is `{profile_id, profile_digest, role, model_identity}`.
Role is `verifier-l2s`; `model_identity` is the existing exact pinned model
identity object, including its declared effort/context information. The
profile and effort floor must agree with the run's existing role-mapping
contract. Changing role/model/profile or any prompt bytes requires a new
subject; no fallback model can inherit a verdict.

`output_binding` is one closed variant:

| Kind | Exact fields, in order |
| --- | --- |
| packet-group | `{kind, evidence_keys, packet_ids}`; ordered group produced by this candidate |
| claim | `{kind, reserved_claim_id, normalized_claim, packet_ids, source_ids, claim_type}` |
| no-claim | `{kind, packet_id, basis}`; `basis` is the existing no-claim proposal text, treated as proposed content to challenge |
| material-only | `{kind, object_id}`; source-bound existing OBJ, no future CC/PKT identifier |

The writer reserves a new CC identity before reviewing its proposed bytes.
Reservation is not admission, acceptance, or a future answer key. L2S may
receive that candidate identity because exact write comparison requires it.
It receives no downstream accepted-ID mapping or unrelated final inventory.

`origin_unit_refs` is the exact producer-supplied list from section 7.
`origin_context` contains direct projections
`{semantic_id,subject_digest,owner_stage,output_binding,anchors,semantics,
material_use,material_views}` from the prior subjects named by those
references, unique in first-reference order. Exclude their own origin
contexts, reviewer results, resolutions and hidden rationale. Include only
groups actually used by this output. Their exact selected context is part
of this new seal; no unrelated origin group may be added. Prior proposal
fields are challenge context, not inherited certification. Core checks
each projection against the retained complete subject/hash and rejects
reference cycles without recursively attaching ancestor histories.

`packet_basis` is an ordered array of
`{packet_id, packet, evidence_record, fragments, transformations}`.
`packet` contains exactly the T3.1 fields in template order;
`evidence_record`, fragments, and transformations contain their existing
exact T3.1 column names/values in column order, without Markdown escaping.
Every group member's complete evidence record is present; fragment order
and framed evidence hash remain unchanged. Transformations are separately
labeled display/normalized outputs. Never substitute them for exact bytes.
Canonical JSON array cells are decoded as JSON; other table cells stay
strings. The binding also includes packet previews, so changing displayed
candidate context cannot silently reuse a review.
For a CC, this array equals its output packet provenance in order. Additional
relation-target packet context goes in `relation_context`, never this basis.

`material_use` is the exact existing producer `MaterialUseInput` belonging to
the selected output. For no-claim it is JSON null, with its packet's existing
use retained in `material_views`. `material_views` contains ordered
`{use_subject, use_subject_digest, view}` entries for applicable reserved or
committed PKT/CC/OBJ uses. `use_subject` and `view` are the existing Core
Slice 6 subject and bounded review-view objects, losslessly serialized;
their bytes/digests must recompute from the frozen inventory. An entry for a
reserved use omits only its future VER receipt, exactly as Slice 6 already
does. No S7-specific coordinate, availability, rendering, or limitation
taxonomy is created.

For a packet group, its candidate material declaration is reviewed over the
group's packet union, while each canonical PKT receipt must independently
meet the existing per-PKT contract. The group review grants no extra packet
capture capability. Additional context requiring unavailable material
produces a finding; it cannot expand or rewrite a committed PKT receipt.

`lineage_context` is an ordered array of
`{lineage_id,row_digest,event,unit_definitions}`: only the direct
predecessor event/definitions needed for this proposed successor.
`event={owner_stage,type,predecessors,successors}` uses existing enums and
ordered ID arrays; `row_digest` binds the complete existing row. Do not
show its freeform basis or actor metadata. Each unit definition is
`{kind,id,projection}`, where PKT projection is the Slice 6 PKT subject
projection and CC projection is its CC projection. No disposition,
judgment rationale or downstream field is included. No ancestor graph
walk. New claim provenance from packets is not a lineage event. Empty is
normal for first S2/S3 candidates.
A not-yet-committed lineage event must be the exact reserved event supplied
by the already authorized producer/judgment step, with existing current
predecessors and explicitly reserved successors. Hash its complete proposed
row and commit it with the corresponding admissible successor transaction.
Do not pretend that a reserved LIN row is already canonical or invent a
lineage event solely to populate review context.

`relation_context` contains ordered
`{proposal_index,target_units,target_anchors,target_packet_context}` entries derived from
`semantics.relation_proposals`. Target units use the exact direct
`{kind,id,projection}` shape above; target anchors use Anchor. Include
only the explicitly proposed concrete endpoints. `target_packet_context`
uses the packet_basis entry shape but is inspection context, not additional
claim provenance. Target anchors outside the output packet basis have
`packet_ids=[]`. Never perform an automatic relation graph walk. Null
targets have empty target lists. Every entry must satisfy the earlier
stage's source/batch bounds. This supplies reopenable context for testing
the proposed target, not a second editable relation list.

`ambiguity_context` is an ordered array of
`{kind,reference,digest,projection}`. Kind is `semantic-finding` or
`slice5-working-subject`; projection is respectively an exact Finding
from an identified retained SEM/VER or the existing
`aleph-internal-ambiguity-review-subject/v1` working subject. Reference is
the exact canonical run-relative file plus JSON Pointer and byte digest;
the digest hashes the canonical selected object. Include its source
anchors/search basis as explicit legal context. Do not include T5.3,
authority responses/observations, producer rationale or material-impact
decisions. References must concern a subject unit or anchor. Canonical
T5.2 does not yet exist at S2/S3 or S4 pre-C1. This field allows working
findings only, not early canonical ambiguity writes or post-C2 revisions.

`context_manifest` lists `{path, selector, digest, purpose}` for each exact
run-data component supplied in this subject. Purpose is `packet-evidence`,
`inspection-context`, `material-context`, `lineage-context`,
`relation-context`, or `ambiguity-context`. It is generated from the above
components, cannot add an attachment, and excludes the subject file itself
to avoid recursive hashing. Source-locus selectors include exact offsets.
Asset selectors identify the existing Slice 6 asset/hash. Entries sort by
path then selector using UTF-8 byte order; duplicates fail.
The run-data selector grammar is exactly `bytes:<start>:<end>` for raw
source/asset selections, `json:<JSON-Pointer>` for a selected immutable
JSON object, or `row:<table-key>:<zero-based-row-index>` for a canonical
Markdown row. Table key is the literal artifact table heading; its unique
presence is required. Digests hash the selected raw bytes, canonical JSON
value, or canonical JSON cell array respectively. No globs, implicit
neighbor rows, or dynamically inferred selectors are legal. These selectors
describe the context manifest; they do not add a source locator scheme.

The subject digest is SHA-256 over the exact canonical JSON bytes above.
Its target string is exactly `semantic-review-subject:sha256:<64 hex>`.
The on-disk file is `verification/harness/semantic-subjects/SEM-NNNN.json`.
No in-place rewrite is permitted. Revisions allocate a new SEM and complete
subject, even when only a qualifier, packet order, material requirement,
local context window, relation proposal, or limitation changes.

Changing load-bearing fields after review makes that review inapplicable.
Core detects the mismatch and refuses use; it does not persist a generic
STALE/INVALIDATED state, retarget reviews, repair fields, or propagate
invalidation through the graph. Later unrelated S5 disposition text is
excluded and therefore does not change a valid S3 subject.

### 9. L2S exact reviewer return and coverage

Add the pinned lens heading
`L2S — atomicity, context, and semantic preservation (S2/S3)` and dispatch
role `verifier-l2s`. Legal invocation is S2, S3, and the strictly bounded S4
successor case in section 13. It uses the existing `refuter` mechanism,
separate context, and effort floor. It has a dedicated Core output contract:

```text
SemanticResult = {
  format, subject_digest, verdict, field_reviews, unresolved_findings,
  attacks_tried, missing_for_determination, rationale, candidate_evidence
}
format = aleph-semantic-result/v1
verdict = upheld | refuted | cannot-determine
FieldReview = {
  field_path, verdict, issue, anchor_ids, material_requirement_indexes,
  explanation
}
issue = none | compound-assertion | lost-context | spurious-context
      | altered-scope | lost-condition | altered-qualifier | altered-modality
      | altered-attribution | conflated-role | result-interpretation-collapse
      | lost-comparator | lost-metric | unsupported-interpretation
      | unresolved-referent | missing-material | illegal-relation-use
      | insufficient-context
```

All fields are required; unknown/duplicate keys fail. `candidate_evidence`
is exactly `[]`, enforced by the **portable Core L2S validator** and native
schema, not a host regex. This new contract does not repair the carried L2F
A-05 surface.

`field_reviews` contains exactly one row for `/semantics/atomicity`,
`/semantics/contexts`, `/semantics/couplings`,
`/semantics/relation_proposals`, `/semantics/unresolved_findings`,
`/material_use`, and each unit's `/proposition`, `/claim_roles`, `/scope`,
`/conditions`, `/qualifiers`, `/modality`, `/attribution`, `/comparator`,
and `/metric`, prefixed by `/semantics/units/<zero-based-index>`.
Rows use this enumeration order. A no-claim review additionally includes
`/output_binding/basis`. This is an enumerated finite coverage rule, not
open-ended arbitrary JSON Pointer evaluation.

Each row uses existing anchors/requirement indexes and nonempty explanation.
At least one binding is required except when challenging an empty structural
collection; in that case the exact field path is the evidence binding.
An upheld row uses issue `none`; refuted/cannot-determine uses a concrete
issue. The reviewer must state an attempted counter-reading, not merely say
the value is plausible. Code checks nonempty shape, not quality of the attack.

`unresolved_findings` uses the exact Finding schema, with fresh reviewer-local
F ordinals. It cannot rewrite producer findings. `attacks_tried` is a
nonempty array of nonempty strings. `missing_for_determination` is null
unless the verdict is cannot-determine, when it is nonempty. `rationale`
follows the existing 1–3 complete-sentence return rule. None of these prose
fields supplies executable authority or bypasses field reviews.

Overall verdict consistency is structural: any refuted row requires
`verdict=refuted`; otherwise any cannot-determine row requires
`verdict=cannot-determine`; otherwise all rows must be upheld. This combines
declared reviewer findings only; it never evaluates source meaning.
Every cannot-determine row has a matching unresolved finding. A refuted
verdict is not silently relabeled cannot-determine or vice versa.
Conversely, each reviewer finding other than `relation-deferred` requires
a refuted/cannot-determine row for the named field. An unexplained finding
cannot accompany an all-upheld result. For unresolved-record review, the
producer's preserved unknowns can be upheld as honestly recorded; any new
reviewer uncertainty about that record still follows this rule.

#### 9.1 Exhaustive subject coverage and review consequence

Every candidate selector receives L2S, not a sample. This deliberately
replaces the S3 spot-check minimum for 1.7 only; earlier run formats retain
their own rules. L1 gap review remains separate, and L2F remains separately
required for the material uses it governs. A single L2S record does not
substitute for either lens.

One fresh reviewer is the minimum for each subject. Preserve the current
common cannot-determine escalation to a second fresh reviewer of the
identical sealed subject. All retained assigned reviews participate: any
refuted result prevents admission; otherwise any cannot-determine prevents
affirmative admission. A later upheld vote cannot erase an earlier
indeterminate result. Additional reviews cannot be solicited until a
preferred verdict wins. Budget exhaustion preserves a pending/blocked
review; it is not an implicit outcome.

An upheld semantic review licenses only the unchanged candidate for the
specified next step, subject to all other DoDs. It is not a declaration of
truth or acceptance. Refuted means retain the failure and request producer
revision or a valid existing lineage/no-claim outcome; the reviewer never
writes the correction. Cannot-determine preserves the candidate and missing
basis and blocks that affirmative use.

To record an unresolved state as a completed bookkeeping object, the producer
may propose a new `review_mode=unresolved-record` subject, linked to the
original SEM, with `atomicity=CANNOT_DETERMINE`, exact missing basis and no
affirmative canonical output. L2S can uphold the faithfulness of that
**unresolved record**. This does not turn the original cannot-determine
verdict into upheld, allow its tentative proposition into the inventory, or
waive source-walk/lineage/stage closure. The unresolved record and original
verdict both remain visible.

### 10. Exact context allowlists and withholds

No worker receives the run directory or general filesystem access. The
adapter transports only the Core-constructed view and pinned prompt parts.
The sealed subject is the unit of challenge; batch IDs never authorize a
broader read. These rules apply to attachments, task sentences, tool access,
cached context, and provider/session continuation.

| Role | Allowed run context | Explicitly withheld |
| --- | --- | --- |
| S2 extractor | One complete frozen source and its manifest row; exact S1 criteria; that source's existing Slice 6 inventory/view; source-local primary cursor/walk needed for continuation | Other sources, other extractors' packets, developing CC inventory, dispositions, authority discussions, expected answers |
| S3 normalizer | Assigned current packet group and exact evidence; S1 normalization conventions/criteria; exact source-local windows named in its task; relevant Slice 6 view; upheld S2 unit/context structure | Other batches, global inventory, S5/S6 results, routing/projection, producer hidden context, authority observations |
| S2 L2S | One complete sealed packet-group subject; its exact packet evidence and declared source-local inspection anchors; required material closure; S1 criteria | Full source by default, other packet candidates except explicitly named context, producer rationale/history, CC/final IDs, expected split/answers |
| S3 L2S | One sealed claim/no-claim subject; exact packet basis, explicit context anchors, relevant S2 unit proposal, direct lineage context if needed, material view | Other candidate claims except coupling/context subjects explicitly needed, other batches, global final inventory, prior reviewer verdicts/rationales |
| S4 successor producer/L2S | Exact already-proposed successor, direct predecessor semantic records and provenance union; only source context needed to preserve meaning | Global duplicate search, other merge groups, L3 rationale/verdict preference, relation closure outcomes, downstream narratives |
| Orchestrator | Full run state for scheduling, byte validation, persistence, gates | It may see but must not forward withheld content or author semantic judgments |

Universal withholds for every semantic producer/reviewer are calibration
answers, closed-reference inventories, expected dispositions/claim IDs,
recall quotas, human semantic observations or authority response prose,
downstream narratives, unrelated batches/sources, and hidden reasoning from
another worker. Existing source documents may themselves contain citations,
opinions, or instructions; they are frozen data, never worker instructions.

The L2S attachment allowlist contains exactly one generated subject file and
the exact assets referenced by its embedded Slice 6 view. Packet/source
bytes are embedded or copied as exact bounded selections with identical
hashes. No raw `ledgers/claim-inventory.md`, full relation ledger, control
directory, producer-return file, or full provenance export is attached.
Core checks this closure; adapters do not choose it with semantic regexes.

Identity metadata required by an existing material view remains that view's
documented bounded disclosure (A-06). It never licenses adding producer
reasoning. New producer context/identity tuples remain hash-bound outside
the semantic view.

The task sentence is fixed by Core:
`Challenge only the attached sealed semantic subject under L2S.`
It contains no expected verdict, rationale, or unsealed context.

If context is insufficient, the reviewer returns a structured request/finding.
The orchestrator may assemble a newly sealed subject only from legal frozen
context. It may not append a helpful paragraph to the existing conversation.
Freshness requires a new invocation with no producer or previous-review
conversation reuse. Dedicated full-same-source referent search follows
Slice 5; global/cross-batch relation investigation waits for S4.

The exact source-local window is the union of the named packet spans and
explicit inspection anchors, not an implementation-chosen N-line radius.
Neither producer nor reviewer may silently expand it. Tests verify actual
attachment bytes and task strings, not merely the allowlist's declared names.

For the exceptional full-same-source search, require a retained structured
`same-source-referent-search` request and the exact Slice 5 full-source
completion/search basis before supplying `0..source_length`. Use a new
dedicated invocation of the stage's existing producer role (extractor at
S2, normalizer at S3, bounded successor normalizer at S4), followed by fresh
L2S over the new sealed context. Its task is limited to that one expression,
one source and the existing Slice 5 search rules. It returns a revised
semantic proposal/finding, not canonical T5.1/T5.2/T5.3. This does not
dispatch the C2-only ambiguity role at an illegal earlier stage. If source
completion is not yet available, retain the request as pending; do not
invent a completion record or widen context informally.

### 11. S2 packetization and source-walk integration

1. The extractor returns existing exact fragments/walk/events plus structured
   semantics. Core reopens the fragments; the orchestrator commits valid raw
   PKT evidence, its USE receipts, walk/events and cursor under existing
   capture rules. Capturing evidence does not certify atomicity.
2. Core binds each candidate group to those exact packet/evidence identities,
   constructs SEM, and dispatches fresh L2S. Return-shape/reference failure
   before capture keeps the entire return quarantined; it cannot obtain a
   validated-return brand through a partial semantic bypass. A later
   semantic challenge leaves already validly captured raw PKTs retained,
   with semantic completion blocked until its proper outcome is recorded.
3. L2S challenges separation, necessary context, scope, qualifications,
   modality, attribution, content roles, and result/interpretation coupling.
   An upheld `multiple-separable` packet group is legal: a packet is a byte
   container, and its reviewed units guide subsequent S3 candidates.
4. S2 exit requires every emitted candidate selector accounted for, every
   exact packet covered by a reviewed group or a legal recorded lineage
   outcome, and all independent source-walk/gap DoDs satisfied.

Packet splitting/widening is a producer proposal and uses existing Slice 3
split/replace/supersede semantics, new exact PKTs where required, and preserved
predecessors. Preserve full provenance and source-walk accounting; a semantic
review cannot delete bytes, rewrite primary intervals, fabricate cursor
history, or declare a gap closed. Sub-line semantic anchors are selections
inside existing exact fragments, not new canonical `md-lines` packets.

For same-line independent assertions, retain the complete-line PKT and
represent two units. Both future claims may cite it, with distinct anchors.
For separate-fragment evidence, preserve fragment order and join policy.
Necessary context can be separately packetized and explicitly referenced;
it is not silently inserted into exact evidence or concatenated prose.

When new packets arise through the existing fresh L1 gap-review path, they
receive the same producer semantic proposal and L2S treatment. L1 does not
become an atomicity producer or lose its differently framed recall attack.
Unaccounted gaps remain in source-walk machinery. No packet is discarded
because it is awkward to normalize.

### 12. S3 normalization and unresolved behavior

The normalizer proposes one AtomicUnit per affirmative CC output, preserving
all source-supported facets. Several claims can share packet provenance;
several packets can support one claim. The ordered packet list and the exact
normalized text are sealed. Normalization cannot add facts, collapse
assertions for prose elegance, change the actor, turn a possibility into an
observation, or strip a condition/hedge.

The orchestrator maintains an exact coverage map within the semantic ledger
resolutions: every upheld S2 `SEM/U` is referenced by at least one reviewed
S3 claim candidate or an explicit reviewed no-claim proposal. The references
are provenance/accounting only; no fixed one-to-one mapping or semantic
equivalence check is imposed. Any changed decomposition is visible in the
new subject and freshly challenged. No-claim still needs the existing LIN
event for the actual packet if zero claims result.

Unpacketed context needed for an affirmative claim requires the existing
widen/add-packet procedure before sealing the admissible claim. Merely
showing surrounding text to the normalizer/reviewer does not make it evidence.
Every text anchor used to justify the proposition or a required semantic
facet must be covered by the claim's actual packet provenance.

An affirmative canonical CC requires:

- an exact upheld L2S proposal subject with one single/inseparable unit;
- no CANNOT_DETERMINE facet, indeterminate coupling, or unresolved finding
  affecting the meaning asserted;
- a usable Slice 6 receipt and independent upheld L2F where required;
- exact equality to the reserved text/type/packet/source projection; and
- valid existing provenance, lineage, and stage prerequisites.

The mechanical rule treats all finding codes except `relation-deferred` as
blocking an affirmative use. `relation-deferred` is allowed only for a
relation proposal whose target is unavailable in the legal S2/S3 context;
it cannot excuse a missing condition, referent, or other meaning-bearing
facet. Such a deferred relation must be reconciled at S4 under Slice 4.
This rule avoids an implementation-chosen “material enough” threshold.

A statement faithfully reporting uncertainty can be an affirmative claim
about that reported uncertainty, with source-expressed limitation/attribution
and a separately upheld subject. It cannot assert the indeterminate
underlying interpretation. No open-question claim is fabricated merely to
fit an unresolved queue.

Semantic-only unresolved findings remain in the semantic ledger even when
there is no CC. Material-only findings also use Slice 6 OBJ/USE records.
The existing CC-only unresolved queue is not given new endpoint kinds.
Actual unresolved/deferred claims can cite SEM/USE references in their
existing blocking/evidence fields. If an unnormalized PKT has no valid claim
or independently valid no-claim lineage outcome, S3 remains blocked.
Human procedural carry cannot waive that DoD.

At ASSEMBLED and later, Précis section 17 additionally carries this exact
table without changing the accepted envelope headings:

```text
| semantic_id | finding_id | source_ids | state | subject_digest |
```

Rows include every retained producer/reviewer unresolved finding, including
earlier indeterminate candidates later followed by a narrower usable claim.
`finding_id` is `producer:F<n>` or `VER-NNNN:F<n>`, `source_ids` is the
ASCII-sorted unique source union of the finding's anchors/material
requirements, and state is literal `CANNOT_DETERMINE`. The row binds its own
subject digest; it does not label a later different claim indeterminate.
Sort by semantic ID then finding ID. Keep an empty table for an empty
population. The checker compares only this declared union. Findings are not
erased or semantically “resolved” by a newer row.

### 13. Relations, lineage successors, and S4 closure

S2 relation proposals remain one-source and packet-level: no claim target,
semantic-prerequisite, cross-source relation, or canonical REL write.
S3 proposals remain confined to the current batch and its legal context.
The four families/eight types, null states, exact 14-field relation subject,
and 17-column canonical ledger remain unchanged.

L2S challenges whether the proposed unit abuses context or omits a required
local relation. It does not replace L3R or confer relation write authority.
Only the existing S4 relation procedure reconciles deferred/cross-batch
proposals, reviews the complete exact relation subject, and writes canonical
REL rows at S4-C1. OBJ IDs do not become relation endpoints.

After existing S4 judgment proposes a new lineage successor, the normalizer
may perform a bounded preservation task at S4: express that already-named
successor with the same structured fields, exact predecessor/provenance
union, and explicit material requirements. L2S reviews it before admission.
Neither task may decide duplicate-versus-overlap, change membership of the
proposed merge group, or inspect unrelated inventory. If it finds that the
proposed successor cannot faithfully express the content, it returns
refuted/cannot-determine and blocks that successor; it does not repair L3.

Each new PKT/CC needs its own semantic record and, where applicable, USE and
L2F review. Old semantic subjects, receipts, and findings remain historical.
They are not auto-copied, reclassified as fresh, or retargeted to successors.
Direct current packet provenance is checked through Slice 3. Broader
descendant invalidation and post-S5 correction remain outside this slice.

At C1, after all current-unit semantic obligations and canonical relation
obligations close, seal the semantic ledger together with the existing
representation-use closure. Add `semantic_review_closure_hash: sha256:<hex>`
to the same retained C1 event. It hashes exact semantic-ledger bytes; referenced
subject/result hashes bind its immutable closure. This is a seal of this new
ledger, not a relation-set version, C1 replay mechanism, or new human gate.

After C1, refuse semantic subject admission/revision, resolution writes, and
PKT/CC semantic replacement before changing bytes. C2 consumes the closed
material and relations under Slice 5; C3 still gates S5. A discovered defect
requiring pre-C1 changes blocks under existing correction doctrine. Do not
rewrite C1, re-run it silently, retarget a relation, or amend a human response.

### 14. Slice 6 material-use integration

Reuse `validateMaterialUseInput`, `materialFeatureAvailable`,
`representationUseNeedsReview`, the exact use-subject serializer, and the
existing bounded material-view constructor. New semantic code must import
these Core contracts; it may not replicate them in a host mapping.

The candidate's `material_use` is the single authoritative requirements list.
Facet/context/finding records refer to indexes into it. They do not restate
features, bindings, coordinates, availability, or limitation states. The
subject binds the exact current inventory digest, actual material-use
subject, and all displayed objects/assets. L2S must challenge undeclared
semantic dependence on material, even if declared availability passes.

Preserve the Slice 6 common constraint block verbatim. In particular:

- exact captured bytes, supplied rendering, and interpretation stay distinct;
- missing headers, formal structure, chart values, or spatial relationships
  cannot be inferred from flattened text or pixels;
- `gold` remains a recognized forbidden fidelity assertion;
- all available features permit, but never require, a usable semantic result;
- a transport unable to consume a supplied modality returns cannot-determine;
- required non-text/AST CC/REL use still needs separate L2F upheld evidence.

Run L2F and L2S against the same reserved final CC projection before canonical
commit. A revision after either review requires new subjects for every review
whose included inputs changed. Because the Slice 6 CC subject binds
text/type/provenance but not new facets, a facet-only edit invalidates L2S;
L2F reuse is allowed only when its entire existing subject and displayed
material view are byte-identical. This is exact-subject equality within the
same pending reservation, not cross-run caching or semantic inference.
If the reservation's CC identity or actual use changes, re-reserve and review.

Do not replace L2F with L2S, reinterpret an OBJ failure as a CC, or modify
1.6 receipts. The new L2S empty-candidate-evidence rule is portable Core
validation for its own new contract only; A-05 remains carried.

### 15. Durable artifacts, transitions, and resume

#### 15.1 Canonical semantic ledger

Add `ledgers/semantic-review.md` with exactly one marker and four tables:

```text
- semantic_review_format: aleph-semantic-review/v1

| semantic_id | owner_stage | subject_kind | subject_path | subject_digest | predecessor_semantic_id | producer_receipt_ref |

| review_id | semantic_id | assignment_path | assignment_digest |

| review_id | semantic_id | result_path | result_digest | execution_kind | execution_evidence_ref |

| resolution_id | semantic_id | outcome | review_ids | canonical_refs | origin_unit_refs | followup_semantic_ids |
```

Table headers are exact and unique; no extra columns or duplicate rows.
List cells are compact JSON arrays, unique and ordered as specified below.
`producer_receipt_ref` and `execution_evidence_ref` are exact run-relative
paths plus SHA-256 (`path@sha256:<hex>`) to immutable records. They may
reference control evidence for a host run but that evidence is never a
reviewer attachment. Manual/static records use paths under
`verification/harness/semantic-process/`, with their actual evidence kind.
Paths use existing canonical relative-path and no-symlink rules. A missing
record is not equivalent to a static record.

Before dispatch, reserve VER and append its assignment row. Assignment path
is `verification/harness/semantic-assignments/VER-NNNN.json`, containing
exactly `{format,semantic_id,subject_digest,review_id,role,profile_digest,
invocation_id,producer_binding_hash,execution_kind}` in that order.
Format is `aleph-semantic-assignment/v1`; role is `verifier-l2s`.
Invocation ID is the reserved host call or manual/static pass ID, and
execution kind uses the enum below. This immutable assignment records
pending work; a result cannot exist without it. Enumerate all assignments
to determine the required result set, including the second invocation
after cannot-determine. An assignment cannot be erased to improve the
aggregate verdict. Assignment/result ID pairs are one-to-one.

`subject_path` is the canonical SEM path from section 8. `result_path` is
`verification/harness/semantic-results/VER-NNNN.json`; its bytes are the
canonical SemanticResult, not a Markdown paraphrase. Also retain a T7.1 VER
companion at `verification/harness/<S2|S3|S4>/VER-NNNN.md`, with exact
target, stage, lens `L2S`, and shown/withheld declaration. It must agree
with the JSON result. The existing VER is a display/inspection companion;
the structured result supplies new field coverage.

`execution_kind` is exactly `native-dispatch`, `fixture-simulated`,
`static-record`, or `manual-separate-pass`. The writer derives it from
actual dispatch/retention evidence, not the reviewer's return. A static
record is admissible as synthetic fixture evidence only. It cannot satisfy
agent/hybrid execution freshness. Fixture simulation must remain in the
existing fixture-simulated execution mode.

Resolution IDs are SMR. There is at most one resolution for each SEM;
absence means pending. Resolution outcome and fields follow this table:

| Outcome | Preconditions and exact references |
| --- | --- |
| `admitted` | All assigned reviews upheld; `review_mode=proposal`; atomicity single/inseparable or S2 multiple-separable; no blocking indeterminate fields/findings; output eligible under sections 11/12/13; `canonical_refs` is the ordered exact PKT group or sole CC; followups empty |
| `no-claim` | All reviews upheld; no-claim subject; canonical refs exactly the packet and its valid LIN no-claim event, in that order; no followup |
| `revision-required` | At least one refuted review, or a mechanically superseded pending reservation; no canonical refs; nonempty followups, each linked to this SEM |
| `unresolved-recorded` | All reviews upheld of `review_mode=unresolved-record`; no PKT/CC/LIN canonical refs; followups empty; original failed subject remains non-admitted |
| `not-admitted` | Refuted/cannot-determine candidate or withdrawn uncommitted reservation; canonical refs empty; any followups explicitly identify their SEM |

`review_ids` lists **all** assigned completed VER IDs in dispatch order.
Uncompleted assigned reviews block `admitted`, `no-claim`, and
`unresolved-recorded`. Withdrawal is procedural abandonment of a reservation,
never semantic rejection, packet disappearance, or source-walk closure.
A refuted proposal need not have a revision to remain durably not-admitted.

`origin_unit_refs` is an ordered array of strings `SEM-NNNN/U<n>`, naming
reviewed S2 units or units from a directly preceding reviewed semantic
proposal being accounted for. S2
resolutions use `[]`. S3/S4 outputs enumerate their declared source-unit
mapping; repeated origins across different CCs are legal. No-claim
resolutions enumerate every originating unit claimed to produce no CC.
Code verifies reference/coverage accounting, not equivalence between them.
If the packet group was indeterminate and had no units, its SEM identity is
instead covered through the packet-level outcome; inventing U1 is forbidden.
An S3 reviewer may uphold a producer's `multiple-separable` diagnosis while
that compound CC reservation remains ineligible for admission. Separate
child candidates then reference its distinct U IDs, preserving the source
coupling even when the split was discovered after S2. Such an origin is
reviewed proposal history, not an admitted CC or new lineage event.

Rows append only after all referenced immutable files exist. The ledger
never overwrites subject/review history. A new narrower candidate may be
admitted while its predecessor remains `not-admitted`; the unresolved
summary retains the predecessor finding. Revisions are not in-place patches.

#### 15.2 Mechanical transaction contract

Core produces a bounded semantic write plan with exactly
`{key, stage, semantic_id, subject_digest, writes, prerequisite_hashes}`.
Each write has the existing material-plan shape
`{path, before_hash, after_base64, after_hash}`; prerequisites are sorted
`{path, digest}` pairs. The key is
`semantic:<semantic_id>:<subject_digest>:<operation>:<record_id>`.
Operation and record ID are exactly: `reserve-subject`/SEM,
`assign-review`/VER, `record-review`/VER, `resolve`/SMR, `admit`/SMR,
or `seal`/`S2|S3|C1`. For a seal only, semantic ID is literal `none` and
subject_digest is the hash of the stage seal or complete C1 ledger bytes.
Stage remains S2/S3/S4 as applicable. Different assignments therefore cannot
collide with each other or with the subject reservation.

The plan enumerates exact permitted paths and byte preimages. It never
chooses a split, qualifier, role, relation, disposition, or interpretation.
Host code executes only the plan under the existing single-writer lock.
Compose semantic and material subject/receipt writes in one prepared
transaction; do not independently commit one and later assume the other.
PKT raw capture may precede semantic review as section 11 specifies;
affirmative CC admission may not.

The transaction must bind the authentic accepted producer return and review
receipts to this reservation. A fabricated boolean such as `reviewed=true`
or a static VER file cannot substitute for `ValidatedWorkerReturn`/the
actual host acceptance evidence in agent/hybrid operation.

Crash recovery verifies the prepared plan, immutable subject/result files,
ledger preimages/after-images, chain/state hashes, exact reservation and
run pins, then completes the same bytes idempotently. A different preimage,
forked resolution, lost review, changed subject, or post-C1 write is a
refusal before further writes. Never synthesize missing semantic fields
during recovery. Completed retries are byte-identical no-ops.

#### 15.3 Closure and resume grammar

Within the existing run-log event grammar, the 1.7 S2/S3 exit events add
exactly these field lines:

```text
semantic_stage: S2
semantic_review_seal_ref: verification/harness/semantic-stage-seals/S2.json@sha256:<64 lowercase hex>
```

The S3 event uses `semantic_stage: S3` and `S3.json`. Each immutable stage
seal contains exactly `{format,stage,subjects,assignments,results,resolutions}`.
Format is `aleph-semantic-stage-seal/v1`; stage is S2 or S3. Each table value
is an ordered array of its complete canonical row cell arrays at exit.
All cells are exact decoded strings; JSON-valued cells retain their
canonical compact JSON spelling. Serialize in listed order and hash those
bytes. Current table rows must begin with those exact sealed rows in order.
Later rows can be appended to each table, but a sealed row cannot change.

This deliberately seals table-record prefixes, not a byte prefix of the
whole Markdown file: adding a row to an earlier table changes later byte
offsets. The single writer permits only new rows at each table's end and
uses exact whole-file preimages for each transaction. At C1 all four tables
are complete, so the existing `semantic_review_closure_hash` binds the
entire final file. Exactly one successful exit event/seal per stage is
permitted; no generic run-state, rewind, or checkpoint-version mechanism
is added.

New K2.19 activation uses the shared `runLogEvents` parser plus canonical
semantic artifact presence and retained stage facts. It does not change
K2.6/K2.7 or the older S3 recognizer. A later stage/C1/ASSEMBLED signal with
missing S2/S3 semantic closure fails the new contract. As with previous
slices, a standalone checker cannot authenticate history after coordinated
erasure of every signal; retained host pins/stage records must prevent a
live downgrade.

Before 1.7 resume advances, run bounded semantic validation after pending
transaction recovery and retained identity verification. Check all referenced
subjects/results, current candidate-to-output equality, pending review
reservations, stage seals, C1 seal, and existing material prerequisites.
At a C1-closed run, resume may read but not repair the semantic ledger.
This is validation of the new semantic closure only, not generic full-run
resume validation or closure of S5A2-03/S5-A-03.

Manual execution follows the same file, stage, and identity contract under
existing manual procedures. Manual evidence records exactly
`{producer_actor,reviewer_actor,producer_pass_id,reviewer_pass_id,
subject_digest,shown_digest,withheld_declaration}`; strings are nonempty.
A same-person separate sitting may be retained as temporal-review evidence
but cannot satisfy the new independent producer/reviewer requirement.
Distinct manual actors/passes are required for 1.7 independent review.
They execute existing manual semantic roles; neither acts as human authority
selecting source meaning or granting a new gate. No manual evidence proves
native freshness. Originally pinned manual procedures remain sanctioned
and are not retroactively changed by this proposal.

### Manual reviewer profile clarification

For manual runs only, the four-key reviewer_profile is exactly
`{profile_id:"n/a (core-manual)",profile_digest:null,role:"verifier-l2s",model_identity:"human"}`
in that order. This is the sole exception to the generic model-object wording
in section 8 above. The retained run mode controls the variant. Existing
manual run identity remains core-manual / human-operator / human, with
profile n/a (core-manual) and execution mapping n/a (manual); do not invent
a model, profile digest, context or effort mapping. Agent/hybrid requirements
are unchanged. Manual identity is not evidence of distinct reviewers: the
exact section 15.3 actor/pass evidence controls independent manual review.
Same-person separate-sitting evidence is temporal only; manual evidence
never proves native dispatch or cognitive independence.
