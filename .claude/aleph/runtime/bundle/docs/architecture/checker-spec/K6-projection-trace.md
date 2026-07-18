# Spec K6 — Projection-Trace Checks (slice 16, then per projection type)

**Target:** `projections/` in a run directory or projection fixture
(`kind: projection` — accepted Précis + one rendered document + commission +
selection ledger + trace). Rendering *quality* is the L10 harness lens; the
kernel checks the trace arithmetic and the neutrality boundary in both
directions.

**Closed vocabularies:** selection `used`, `not-used`, `surfaced-as-open`;
statement kinds `load-bearing`, `boundary`, `open-item`, `gap`, `scaffolding`;
not-used reasons must start with one of `out-of-projection-scope`,
`superseded-by:CC-`, `deferred-to:`.

**Checks (scope = run id + projection type):**

- K6.1 (`commission`): a commission file exists for the type; it defines one
  unique `PRJ-NNN`, names the exact projection-trace path, and its
  `precis_hash` equals sha256 of `precis.md` **now** (P3 re-verification is
  this same check re-run). The trace cites the same projection ID. For a
  projection inside a run directory, the manifest state log must show ACCEPTED
  before the commission date. A
  standalone `kind: projection` fixture need not embed a run manifest; its
  README records the accepted-Précis provenance for audit, while K6.1 still
  enforces the hash binding.
- K6.2 (`selection coverage`): the selection ledger contains exactly one row
  for every `active` carried/merged claim in the inventory; `not-used` rows
  have a reason with a valid prefix; every `deferred`/`unresolved` claim
  whose cluster the projection's used-claims touch appears as
  `surfaced-as-open` —
  `FAIL … K6.2 (selection coverage): CC-108 has no selection row`.
- K6.3 (`trace resolution`): every trace row's `backing` ids exist, are
  `active`, and carry disposition carried or merged (for `load-bearing`
  rows) or deferred/unresolved (for `open-item` rows); `gap` and
  `scaffolding` rows have empty backing. A `boundary` row has one or more
  active `NB-` IDs and no claim backing; other statement kinds may not use
  boundary backing.
- K6.4 (`trace coverage`): every paragraph of the rendered document (split
  on blank lines; headings count as `scaffolding` automatically) has ≥1
  trace row whose anchor names it; no trace row anchors a nonexistent
  paragraph.
- K6.5 (`no new claims`): every `load-bearing` row has non-empty backing —
  a load-bearing statement with empty backing is the minted-fact defect —
  `FAIL … K6.5 (new claim): §3 ¶2 load-bearing with no backing`.
- K6.6 (`boundary honor`): no trace row's backing includes a claim governed
  by a `do-not-use-harm` negative boundary; no rendered paragraph cites a
  `backgrounded` claim as support (backing ids with disposition
  backgrounded fail on `load-bearing` rows).
- K6.7 (`open voice`): `open-item` rows must appear in the document section
  the selection ledger's `surfaced-as-open` handling names; mechanical
  check only — the anchor's section matches the declared section (voice/
  phrasing is L10's job).
- K6.8 (`taint propagation`): K5's cone computation over the projection's
  used claims: if tainted, the rendered document's **first 10 lines** must
  contain the marker `external-referent unresolved` (header prominence,
  mechanically approximated).
- K6.9 (`neutrality both ways`): `precis.md` byte-hash unchanged (K6.1) and
  the rendered document contains none of the answer-key/backwards-leak
  tokens: no `PKT-` ids, no disposition column tables copied wholesale (a
  rendered doc quoting the full §4 table is a leak of the neutral layer into
  a committed document — detected as any table row matching the §4 4-column
  shape with a disposition cell).
- K6.10 (`type contract`): the projection type is registered; its rendered
  metadata table carries every field required by that type; its `PRJ-NNN`,
  projection-trace path, commission path, and current Précis hash agree; no
  template placeholder/comment remains; and its required numbered top-level
  sections are present exactly once in order. The initial registry requires
  sections 1-8 for `product-doctrine` and 1-13 for `prd`.

**False-positive guards:** the document MAY name `CC-` ids inline (that is
traceability, not leakage); `gap` rows are healthy and expected — the
battery includes a gap-bearing golden that must stay green; scaffolding
paragraphs need no ids.

**Battery (minimum 8):** commission hash mismatch → K6.1; carried claim
missing from selection → K6.2; trace backing a retracted claim → K6.3;
untraced paragraph → K6.4; load-bearing row with empty backing → K6.5;
backing includes do-not-use claim → K6.6; open-item anchored outside its
declared section → K6.7; tainted projection without the header marker →
K6.8; missing registered type section → K6.10; dangling negative-boundary
backing → K6.3. Clean projection fixture
(including one honest `gap` row and one `surfaced-as-open` item) → exit 0.
