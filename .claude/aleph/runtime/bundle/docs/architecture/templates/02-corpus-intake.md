# Templates 02 — Corpus Intake

## T2.1 Corpus manifest → `runs/<run-id>/corpus/manifest.md`

```markdown
# Corpus Manifest — ⟨RUN-slug⟩

## Scope
⟨The approved scope statement, verbatim from the manifest sign-off.⟩

## Span-addressing schemes in use
| scheme id | applies to | locator format |
|-----------|------------|----------------|
| md-lines | UTF-8 line-addressable text files | `L⟨start⟩-L⟨end⟩`; one-based inclusive complete lines, including the following LF unless the span ends on the final line |
| chat-msg | conversation exports | `M⟨n⟩` (1-based message index) or `M⟨n⟩:S⟨k⟩` (sentence k within message n) |
| ⟨add per format; propose new schemes in the same PR that first needs them⟩ | | |

## Source inventory
| source_id | kind | locus | scheme | content_hash | date(s) | trust_class | sensitivity | admission note |
|-----------|------|-------|--------|--------------|---------|-------------|-------------|----------------|
```

Column rules:

- `kind`: `conversation-export` | `deep-research-output` | `design-note` |
  `spec` | `external-research-intake` | `authority-statement` (closed set;
  extend only via PR).
- `trust_class`: `first-party` | `model-generated` | `third-party` |
  `unverifiable` — records provenance character, judges nothing.
- `sensitivity`: `none` | `pii` | `confidential` | `licensing` (comma-join
  multiple). Any non-`none` value requires an S0 authority ruling row in the
  run manifest before extraction may start.
- `admission note`: one line — why this source is inside the declared scope.
- `external-research-intake` and `authority-statement` rows must cite the
  `REF-NN` they resolve (see T4.4).
- Every source row is admitted before S0 freeze. Research material received
  later belongs to a successor run whose manifest names this run; never append
  it to the frozen corpus. A post-freeze authority resolution belongs in the
  current run's manifest sign-off table, not in a new source row.
- `content_hash` is over the exact frozen file bytes. Intake must not replace
  newline bytes, punctuation characters, ligatures, or other characters while
  producing a source that later exact-evidence fragments address. If exact
  source bytes are unavailable, record the degradation and do not claim a
  byte-exact source.

<!-- example -->
| SRC-101 | deep-research-output | sources/access-model.md | md-lines | sha256:9f31… | 2026-06 | model-generated | none | core access-model research named by scope |

## T2.2 Extraction criteria → `runs/<run-id>/ledgers/extraction-criteria.md`

```markdown
# Extraction Criteria — ⟨RUN-slug⟩
<!-- The written timestamp must predate the first packet row. -->
- written: ⟨date/time⟩
- author: ⟨actor⟩

## Candidate-claim definition (this corpus)
⟨One paragraph instantiating the wedge definition for this scope: a
declarative assertion about ⟨scope subject⟩ that could plausibly bear on a
downstream decision.⟩

## Admission criteria  <!-- numbered; packets cite these numbers -->
| # | criterion | example span that qualifies |
|---|-----------|-----------------------------|
| 1 | ⟨…⟩ | ⟨…⟩ |

## Exclusion classes (outside candidacy, recorded here once)
| class | description | example |
|-------|-------------|---------|
| scaffolding | greetings, "agreed/right", speaker labels, formatting | "Sounds good — " |
| tool-noise | logs, stack traces quoted without assertion | ⟨…⟩ |
| refusal-blocked | span a safety classifier refused to process (agent mode); routed to manual handling | n/a |
| ⟨…⟩ | | |

## Packet granularity policy
⟨2–4 sentences: what a span is for each source kind; when to widen; the
over-extraction bias stated explicitly.⟩

## Normalization conventions (used at S3)
⟨Restated-once rules: tense, actor naming, hedging words preserved or
normalized how, units.⟩

## Supersessions  <!-- criteria changes; each forces re-extraction -->
| # | date | change | re-extraction completed over |
|---|------|--------|------------------------------|
```

## T2.3 Source representations — run format 1.6

The following numbered contract sections define the canonical 1.6 capture,
import, and availability model. Their section numbers retain the adopted
contract references. They apply only with `formal-layout-bindings`.

## 5. Common grammar and byte authority

### 5.1 Identifiers and serialization

New run-local ID families: `REP`, `AST`, `RPR`, `OBJ`, `BND`, `ASC`, `USE`.
Each is exactly its uppercase prefix, `-`, and at least four decimal digits,
with at least one nonzero digit. IDs are unique per family, case-sensitive,
and whitespace-free. They are opaque names: never infer order or meaning from
their numbers. Existing ID and evidence-key grammars remain unchanged.

Require exactly one of each canonical table below, exact headers, no duplicate
definitions, and no additional columns. Scalar absence is literal `none`;
empty lists are `[]`. Lists are compact JSON arrays without duplicate members.
Set-valued ID lists sort by ASCII byte order; explicitly ordered lists preserve
their sequence. Canonical JSON cells have the listed key order, UTF-8 encoding,
no insignificant whitespace, and no duplicate/unknown keys. Compare to the
Core serializer; do not silently normalize noncanonical cells.

Integers use `0` or a nonzero leading digit followed by digits, are safe
integers, and reject signs, fractions, exponents, whitespace, and negative zero.
Positive fields reject zero. JSON numeric fields have the same lexical rule.
Hashes are `sha256:` plus 64 lowercase hex digits. Base64 is standard padded
canonical base64, checked by decode/re-encode. Exact text never comes from a
Markdown preview cell.

### 5.2 Three different claims

1. **Capture identity:** frozen SRC/AST bytes equal the admitted capture.
2. **Representation availability:** that capture supplies the declared text,
   grid, formal structure, or image.
3. **Semantic adequacy:** supplied material supports a particular reading.

None implies the next. Text export can be byte-exact to its frozen SRC but
degraded relative to its upstream document. Its exact packet is not an exact
equation rendering. SRC bytes remain authoritative for Slice 1 fragments.
Different rendered/extracted output has separate AST bytes, hash, and
provenance; it never overwrites SRC or packet exact fields.

An extracted text file may itself be admitted as SRC at S0. Its bytes are then
packet authority for that extracted capture only; its origin declaration must
remain visible. No Unicode/newline/glyph/whitespace normalization, CSV
unquoting, entity decoding, or equation repair is implicit. For example,
literal source `&amp;` and rendered `&` have separate byte identities.

## 6. Frozen representation inventory (future T2.3)

These six tables belong in `corpus/representations.md`. During implementation,
specify them in `templates/02-corpus-intake.md`; no second authoritative schema
lives in the adapter.

### 6.1 Representations

```text
| representation_id | source_id | origin_kind | extraction_surface | state | reason | provenance_id |
```

Exactly one REP per admitted SRC, each referencing one capture RPR.

- `origin_kind`: `original-capture`, `supplied-extraction`, `unknown-origin`.
  A filename does not prove original origin. Unannotated text defaults to
  unknown-origin without losing byte equality to its capture.
- `extraction_surface`: `utf8-text` or `opaque`.
- `utf8-text` requires strict UTF-8 and existing manifest scheme `md-lines`.
- `opaque` means bytes exist but the shipped textual walk cannot consume them.
  Its manifest scheme is `opaque-bytes`, an inventory scheme only, never an
  exact-packet or asserted REL endpoint scheme.
- `state` and `reason` follow section 8. A degraded REP can contain available
  exact text: its state describes the overall representation.

Every REP has one root OBJ, kind source, binding its complete SRC. Empty
captures have a zero-length root binding. Material not declared by ingestion
is not invented by an extractor.

### 6.2 Assets

```text
| asset_id | representation_id | role | locus | media_type | encoding | byte_length | content_hash |
```

Roles: `upstream-capture`, `structure-export`, `rendered-text`,
`rendered-image`, `render-log`. Locus is exactly
`corpus/representation-assets/<asset_id>.<ext>`; extension is 1–12 lowercase
ASCII alphanumerics, default `bin`. Paths are run-relative regular files,
without symlinks, traversal, backslashes, external URLs, or special files.
Assets are inventoried one-to-one with files, owned by one REP, with verified
length and whole-file hash. `media_type` is a nonempty retained declaration,
not proof of a supported decoder. Encoding is `utf8` or `opaque`.
Structure-export, rendered-text, and render-log require strict UTF-8; rendered
images require opaque. Upstream captures declare either. No encoding is guessed
from media type or filename.

Upstream binary assets associated with an admitted text capture are retained
provenance, not additional SRC rows or independent evidence. They cannot be
counted as walked merely because the text was walked. Section 10 governs an
opaque SRC that is itself in extraction scope.

### 6.3 Provenance

```text
| provenance_id | representation_id | type | actor | tool | tool_version | input_refs | output_refs | parameters_asset_id | declaration_asset_id |
```

Types and requirements:

| Type | Contract |
|---|---|
| `capture` | Actor nonempty; copying tool/version nonempty (`manual-copy` / `1` permitted); input refs empty; outputs its SRC plus any retained upstream-capture ASTs; parameters/declaration assets `none` except the imported ID-map rule in section 10. |
| `supplied-structure` | Input includes SRC; output includes a structure-export AST; declaration asset is that AST; parameters asset `none`. Tool/version describe the supplied export producer, or both literal `unknown`. |
| `supplied-rendering` | Inputs include SRC and retained upstream ASTs actually named by the receipt; output names rendered ASTs and retained metadata ASTs. Parameters and declaration each reference a render-log AST; they may be the same asset. Tool/version nonempty and exact, or both `unknown`. |

Input/output arrays are sets of same-REP SRC/AST IDs. Every AST is output by
exactly one RPR. No output is its own input; asset derivation is acyclic.
Capture alone has no input. Metadata describing rendering is retained output,
not a claim that Aleph ran the renderer.

Rendered bytes may exist with explicitly unknown renderer identity/settings,
but original-layout fidelity then remains indeterminate/degraded. A retained
receipt saying “unknown” differs from an absent receipt, which fails structure.
Hashes establish provenance-record identity, not producer honesty or publisher
authenticity. No model may manufacture missing provenance.

### 6.4 Exact byte bindings

```text
| binding_id | representation_id | carrier_id | start_byte | end_byte | page_id | region_id | byte_role | fragment_hash | exact_bytes_base64 |
```

Carrier is the REP's SRC or AST. Offsets are zero-based, half-open:
`0 <= start <= end <= carrier length`. Strict UTF-8 text carriers cannot be
split inside a code point. Opaque carriers use byte bounds without text
decoding. Whole-carrier hash, sliced bytes, fragment hash, and base64 must agree.
`byte_role` is `frozen-source-bytes` for SRC and `retained-asset-bytes` for AST.
SRC encoding follows extraction_surface; AST encoding is explicit.
Page/region IDs are supplied same-REP objects of the corresponding kind or
literal none. They locate this fragment, including fragments of a table spanning
several pages. Where both exist, the region's declared page must agree.

Known empty cells can bind zero bytes with SHA-256 of empty bytes and literal
`""` (empty JSON string) in the base64 cell. This is the only empty-base64
spelling; other base64 cells contain their raw token. Unknown cells have no
binding and non-available state; they never become known empty values.

BND does not replace Slice 1 FRG. It can name an exact substring inside a
complete-line packet, including individual cells sharing one line. No new
positive packet locator scheme is introduced.

### 6.5 Objects

```text
| object_id | representation_id | kind | parent_id | state | reason | provenance_id | binding_ids | content_hash | coordinates |
```

Binding IDs are ordered same-REP BNDs. If nonempty, content hash is SHA-256 over
UTF-8 `aleph-material-fragments/v1` plus NUL, then each binding's bytes in
declared order, prefixed by its unsigned 64-bit big-endian length. This mirrors
Slice 1 boundary preservation with a distinct domain. Empty list means hash
`none`. No spatial sorting, implicit concatenation, or inserted bytes.

Closed kinds and coordinate cells (all keys required, fixed order):

| Kind | Coordinate shape | Legal parent |
|---|---|---|
| `source` | `{}` | none; one per REP |
| `page` | `{"index":1,"label":null,"space":null}` | source |
| `region` | `{"page_id":null,"box":null}` | source or page |
| `text` | `{}` | source, page, region, cell, header, caption, formal, figure |
| `table` | `{"row_ids":[],"column_ids":[],"grid_state":"indeterminate"}` | source, page, region |
| `row` | `{"index":1}` | table |
| `column` | `{"index":1}` | table |
| `cell` | `{"row_ids":[],"column_ids":[]}` | table |
| `header` | `{"cell_ids":[]}` | table |
| `caption` | `{}` | source, page, region |
| `formal` | `{"notation":"unknown","structure_ids":[],"structure_state":"indeterminate"}` | source, page, region, cell, caption |
| `figure` | `{"figure_kind":"unknown","image_ids":[],"values_ids":[],"values_state":"indeterminate"}` | source, page, region, cell, caption |
| `image` | `{}` | source, page, region, figure |
| `chart-values` | `{}` | figure |

Examples specify types, not parser-inserted defaults. `notation` is
`source-markup`, `renderer-export`, `flattened-text`, or `unknown`.
Structure IDs name same-REP text objects containing supplied markup/export,
not a mathematical AST constructed by Aleph. Image/value IDs name same-REP
image/chart-values objects. These lists are ordered. Figure kind is the supplied
classification `figure`, `chart`, or `unknown`; no classifier infers it.

Parentage is acyclic, typed, within one REP. Non-root objects require provenance
of their supplied declaration. Only root source and one text child spanning a
plain UTF-8 capture may be defaulted mechanically from a capture receipt.
Capture alone cannot justify tables, formal objects, figures, or associations.

Available text/cell/header/caption/formal/image/chart-values leaves require
at least one binding. Containers require a binding or bound descendants;
row/column identity can instead reopen through the supplying structure export.
Non-available objects can retain partial or no bindings: the declaration and
root source still reopen the limitation.

An available image binds opaque SRC or image AST bytes. Chart-values binds
textual machine-readable source/export bytes; image bytes alone are never a
values binding. Grid/structure/values states use section 8 independently of byte
presence. Non-available feature state forces non-available containing-object
state. Thus a degraded figure can contain an available image, and degraded
formal material can retain exact flattened text.

### 6.6 Associations

```text
| association_id | representation_id | kind | subject_id | target_ids | state | reason | provenance_id |
```

- `header-for`: subject cell; targets header objects in the same table.
- `caption-for`: subject table/formal/figure; targets captions in the same REP.
- `available`: nonempty declared targets of correct kind/scope.
- `degraded`: empty or partially supplied targets with reason.
- `unsupported`: empty targets and explicit unsupported-feature reason.
- `indeterminate`: empty targets or explicitly supplied candidate targets.
  Candidates do not become selected associations.

Each cell has exactly one header-for row; each table/formal/figure has one
caption-for row. Multiple headers/captions belong in its ordered target list.
Explicit source absence uses degraded state with reason
`source-declares-absent`; this records unavailability, not a source defect.
Provenance is mandatory, including for absence/candidate declarations.

## 7. Coordinates

Page OBJ index is the positive supplied page ordinal, unique per REP. Sparse
indices are legal for partial captures. Printed label is a supplied string or
null and never resolves identity. Do not fill missing pages.

Page space is null or exactly
`{"unit":"pixel","width":100,"height":100,"origin":"top-left"}`:
positive integer dimensions, actually supplied by the source/export.
Only integer pixel geometry is supported. Other units, rotated geometry, or
floating coordinate systems remain in raw export bytes; usable space is null
with a limitation. No coordinate conversion or inferred page size.

Region page ID is null or a page in the same REP; a page parent must match it.
Box is null or `{"x0":0,"y0":0,"x1":1,"y1":1}`, requiring a declared page
space and `0 <= x0 < x1 <= width`, `0 <= y0 < y1 <= height`.
Null means unavailable, never page zero or a whole-page fallback. Non-spatial
regions remain useful. Objects inherit location from parentage; a BND can add
an explicit fragment location where no ancestor fixes it. Reject a BND that
contradicts a fixed ancestor page/region. Effective page is explicit BND page,
otherwise its explicit region's page, otherwise the ancestor page, otherwise
unavailable. A cross-page table therefore has a source parent and individually
located fragment BNDs; do not fabricate one common page.
Overlapping boxes are not inherently invalid and do not determine semantics.

Table row/column lists contain every declared row/column child once, in
increasing index order. Available grids have positive contiguous dimensions;
degraded grids may have explicit gaps. Each positioned cell names nonempty
contiguous subsequences of both lists. Their Cartesian product is its span.
A 2×3 spanning cell is one value occupying six positions, not six copies.
Cells cannot overlap. An available grid covers every position exactly once,
including declared empty cells. Missing cells force degraded grid state.

An unpositioned cell has both coordinate lists empty and indeterminate or
unsupported state. One populated and one empty axis is rejected in v1; partial
raw declarations remain retained in the export. No guessed coordinate or `?`.

A header's cell list names same-table cells it occupies, or is empty for a
separately supplied header outside the grid. Where cells are declared, their
binding intervals must cover the header's bindings on the same carriers.
Multiple header levels are ordered header targets; Core invents no hierarchy.
Captions may be shared only through explicit supplied associations. Proximity
never creates an association.

A swapped cell inconsistent with its retained declaration, an out-of-range
coordinate, or a coordinate collision fails structure. A semantically shifted
cell with internally consistent declarations, hashes, and provenance may pass.
Fresh review owns that adversary.

## 8. States and transitions

| State | Meaning | Reason |
|---|---|---|
| `available` | Named capture/declaration supplies the feature and required bindings. Available as that representation, not certified original meaning or gold. | `none` |
| `degraded` | Some material survives, but known loss/absence prevents claiming the complete feature. Exact retained text may still exist. | Nonempty, naming loss/absence |
| `unsupported` | Format/mechanism has no supported representation of this feature; no fabricated positive structure. | Nonempty, naming unsupported feature/format |
| `indeterminate` | Records cannot establish whether/how the feature exists, or supplied declarations conflict. | Nonempty, naming uncertainty |

No inferred default, gold state, or reconstructed-exact state exists. Honest
non-available records can pass structural validation while blocking a use.
Unsupported top-level extraction surface cannot claim REP available.

These states are immutable capture facts, not a general revision lifecycle:

| Operation on a captured identity | Legal? |
|---|---|
| Read/retry identical bytes, state, and hash | Yes, idempotently |
| Any state → different state | No |
| Degraded/unsupported/indeterminate → available, including renamed replacement in the same run | No |
| Newly discover a limitation in an available capture | Record blocking anomaly; do not rewrite historical state |

Before canonical capture, incomplete preparation may be replaced outside the
canonical inventory. Once captured, corrected exports/new renderings require a
successor run with new frozen identity. A second REP for the same SRC cannot
evade the rule. This bounded non-migration policy avoids general revision and
correction machinery.

The checker compares retained state and frozen digest. It cannot prove a
temporal history if an attacker replaces every seal along with the evidence;
retained execution identity, writer guards, and process tests own that boundary.

## 9. Formal and visual material

| Supplied material | Canonical treatment |
|---|---|
| Exact source markup for a formula | Bind source bytes; notation source-markup. Structure can be available as literal supplied markup, without mathematical parsing or equivalence claims. |
| Additional renderer structure | Separate ASTs/RPR; structure IDs name supplied export text. Available as renderer output, never substituted for source bytes. |
| Flattened equation text | Preserve exact captured text bindings; notation flattened-text; structure state degraded; no inferred fractions, superscripts, subscripts, operators, grouping, or reading order. |
| Unavailable formal structure | Preserve declaration/root provenance with indeterminate or degraded state and no invented structure IDs. |
| Unsupported formal format | Unsupported structure state, explicit format/reason, retained raw bytes if supplied. |
| Image-only chart | Available image binding if bytes exist; figure values state unsupported when no machine-readable values mechanism exists, otherwise degraded/indeterminate as actually declared. Empty values IDs. |
| Supplied chart values | Separate chart-values object binding literal textual source/export bytes. No interpolation, numerical parsing, axis inference, or reconciliation with pixels. |
| Figure with no chart semantics | Figure still records empty values IDs and unsupported values state with reason source-declares-absent. This does not assert the image is a chart. |

A flattened text claim can quote what that capture literally contains. It
cannot assert the recovered equation. If formal structure is necessary for
the proposed conclusion, the worker returns `CANNOT_DETERMINE` and names the
missing feature. C-029 is a calibration motivation, never a reconstruction
target or a generic prompt example.

An image can be reopened by identity without being semantically consumable by
the current worker path. Its presence never authorizes vision/OCR, invented
chart values, or a source interpretation unavailable from the supplied bytes.
No inference from ASCII positioning or visual alignment is implicit either.

## 10. Bounded ingestion and usable Loa path

### 10.1 Default text

Keep current raw UTF-8 input behavior and `md-lines` packets. A plain text
capture receives its capture RPR, one REP, root source OBJ, one text OBJ, and
one whole-file BND shared by those objects. State available means its text
capture is available; it does not assert that no table/formal material exists.
The same rule applies to currently accepted `.csv`, `.tsv`, `.json`, etc.
No new CSV/Markdown/JSON table extractor is inferred from file extension.

If a worker discovers apparently required but undeclared structure, it names
that missing feature on the source/text object and returns CANNOT_DETERMINE.
It cannot convert prose recognition into an ingestion declaration.

### 10.2 Supplied representation export

Add only one explicit interchange route, consumed by unchanged public
`/loa-aleph start <inputs...>`: a file with suffix
`.aleph-representation.json` and exact format
`aleph-supplied-representation/v1`. Ordinary JSON remains ordinary source text.
A reserved-suffix file with a missing/unknown format fails; no fallback.
The Core parser, not the adapter, owns this route's schema:

```text
{
  "format": "aleph-supplied-representation/v1",
  "source_path": "<relative path>",
  "origin_kind": "<section 6 enum>",
  "extraction_surface": "<section 6 enum>",
  "state": "<section 8 enum>",
  "reason": "<string or literal none>",
  "assets": [],
  "provenance": [],
  "bindings": [],
  "objects": [],
  "associations": []
}
```

Every array element has exactly the corresponding section 6 table keys in that
order, with these input-only differences:

- omit `representation_id` everywhere; the descriptor describes one REP;
- SRC references use reserved string `source`;
- assets replace `locus` with `input_path` at the same key position;
- list/coordinate values are JSON values, not Markdown-escaped strings;
- zero-length binding base64 is the empty JSON string;
- descriptor-local RPR/AST/BND/OBJ/ASC IDs obey the same grammars.

The importer adds the capture RPR and REP. The descriptor must supply one root
source OBJ; its provenance token is reserved `capture`, rewritten to that RPR.
Other objects/associations reference their declared RPRs. Capture RPR is not
in the input provenance array. RPR output refs may include reserved
`declaration`, meaning the raw descriptor file retained as a structure-export
AST. Exactly one supplied-structure RPR must output `declaration`; its
declaration asset ref is also `declaration`. This provides a reopenable origin
for declarations without requiring a self-hash inside the descriptor.

Stable input capture must verify every supplied source/asset hash and every
BND slice before canonical materialization. The raw descriptor is retained
unchanged. K2.18 re-parses it and compares all imported structural fields,
states, associations, and binding coordinates after applying the ID map;
rewriting an object coordinate and recomputing only the Markdown digest cannot
pass. The parser does not prove that the external export correctly interpreted
the original document.

ID allocation is deterministic bookkeeping: preserve existing source ordering;
for each assigned SRC, allocate one REP and capture RPR, then descriptor AST,
then each remaining family in ASCII order of descriptor-local ID, using the
next unused numeric ID in that family padded to at least four digits. Store
the exact mapping as a compact JSON object in the capture's retained render-log
asset only for an imported export. This asset is an additional capture output.
The capture row also outputs all upstream-capture ASTs, so those imported
assets must not be outputs of a supplied-structure/rendering RPR. Mapping keys,
in order, are `format`, `source_id`, `representation_id`, `capture_id`,
`declaration_asset_id`, `id_map`; format is `aleph-representation-id-map/v1`.
`id_map` contains local ID to canonical ID pairs sorted by local ID. K2.18
requires a bijection, proper families, and no unexplained imported rows.
Default text needs no mapping asset.

For an imported capture, name that map via capture
`declaration_asset_id`; its parameters asset remains none. The map is metadata,
not original source evidence. Its own AST ID is allocated immediately after
the descriptor AST and is not in the local ID map. The descriptor is already
retained independently, so the map does not assert a renderer run.

`source_path` and asset input paths are regular files beneath the descriptor's
directory, using normalized relative paths without symlinks/traversal.
They are the descriptor's explicit input closure; no network or ambient fetch.
Directory intake inventories descriptors first and consumes their members once,
then handles other ordinary inputs in existing order. Two descriptors claiming
one member, or a member separately selected as another source, fail as duplicate
selection; no silent deduplication or double evidence.

This imports existing supplied bytes/structure. It does not run a converter,
invent a renderer, or let a semantic worker author the descriptor. An operator
can supply an upstream export but must not label an interpretation they wrote
as source-provided structure. Fresh review challenges that distinction.

### 10.3 Unsupported inputs

Raw extensions outside current intake support still return an explicit
unsupported-input error identifying the input. Do not silently drop them or
auto-convert them. A supplied descriptor can retain such an input as an opaque
SRC, with `opaque-bytes` locator `B<start>-B<end>` for bounded inventory
reopening only. The root spans the whole file, including zero-length captures.

An opaque SRC can be canonically recorded in DRAFT/CORPUS-FROZEN with truthful
unsupported extraction state. It cannot enter DISTILLING/S2 in this slice.
K2.18 reports `UNSUPPORTED_EXTRACTION_SURFACE` on attempted progression;
the existing UTF-8 source-walk contract is not weakened or generalized.
Use an existing S0 authority exclusion before freeze if appropriate, preserving
the input/exclusion record, or start a successor run with a supplied text export.
Do not infer that the text is equivalent to the original.

This intentionally permits a structurally valid retained unsupported capture
while refusing an unsupported execution. It also permits a supported text SRC
with an upstream image/PDF AST for provenance. The latter is not a claim that
Aleph extracted all content from that binary asset.
