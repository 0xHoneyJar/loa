# Spec K1 + K2 — Discovered Fixtures and Run-Directory Mode

## K1 — Discovered-fixtures mode (slice 12; `validate-precis-fixtures.ts`)

**Goal:** generalize from the hardcoded `SLICES` constant to any directory
under `docs/fixtures/` that declares its expectations, with **zero behavior
change** for slice-1/slice-2.

**Mechanism:** a fixture opts in via a fenced declaration block in its
`README.md`:

````markdown
```aleph-fixture
kind: precis            # precis | run | evidence-role | routed | projection
src_ids: SRC-101..SRC-104
cc_ids: CC-101..CC-114
ledger_total: 14
stm_rows: STM-1..STM-7   # omit if no matrix
```
````

Rules:

- K1.1 (`declaration`): every directory directly under `docs/fixtures/`
  either is one of the two legacy slices (validated exactly as today,
  hardcoded) or contains a parseable `aleph-fixture` block —
  `FAIL <dir> K1.1 (declaration): no aleph-fixture block in README.md`.
- K1.2 (`kind dispatch`): `kind: precis` runs the full existing check set
  with expectations taken from the block instead of constants (ID ranges,
  totals, matrix presence). Other kinds dispatch to their group's checks
  (K2/K3/K4/K6) once those exist; an unknown kind fails
  (`K1.2 (unknown kind)`).
- K1.3 (`range syntax`): `A-NNN..A-MMM` expands inclusively; malformed
  ranges fail with `K1.3 (range)`. Single ids and comma lists allowed.
- Legacy behavior lock: with no new fixture directories present, output for
  slice-1/slice-2 is byte-identical to pre-K1 output except an added
  `PASS discovery` line.

**Battery:** (1) new fixture dir with no declaration → K1.1; (2) declared
`cc_ids` range that disagrees with the actual inventory → the existing
inventory check fires with the declared set (proves expectations flow
through); (3) unknown `kind` → K1.2; (4) malformed range → K1.3; (5) legacy
slices untouched → green, byte-identical modulo the discovery line.

## K2 — Run-directory mode (slice 9; new `validate-run.ts`)

**Target tree:** a run directory per doc 02 §2 layout (the golden fixture
lives at `docs/fixtures/run-slice-2/` and carries `kind: run`).

The top-level `control/` subtree is reserved for host-adapter runtime snapshots
and durable resume/dispatch mechanics. It is retained with the run but excluded
from canonical Core artifact discovery and K2-K6 content/identifier scans; it
cannot define or satisfy a Core artifact. Only the top-level subtree has this
status, so a directory named `control` below any canonical surface remains in
scope.

**Checks (scope = run id):**

- K2.1 (`layout`): `run-manifest.md`, `run-log.md`, and
  `corpus/manifest.md` are always required. Once the manifest state log reaches
  `DISTILLING`, or mechanically observable S2 evidence establishes that floor
  for a current-format run, the S1-S5 base artifacts are also required:
  `ledgers/extraction-criteria.md`, `ledgers/packet-index.md`,
  `ledgers/claim-inventory.md`, and `ledgers/disposition-ledger.md`. Others
  (merge-map, evidence-roles, clusters/, arms/, precis.md, verification/) are
  required **iff** the manifest's state log shows the run reached the state
  that produces them (state→artifact table hardcoded from doc 04's "Emits"
  column). Run format `1.2.0-provisional` additionally requires
  `ledgers/source-walk.md` whenever S2 applies.
- K2.2 (`manifest`): every format carries mode, doctrine_sha (40-hex), corpus
  hash, exactly one `run_id` (`RUN-<slug>`), exactly one `predecessor_run`
  (`none` or a different `RUN-<slug>`), and ≥1 state-log row; every state-log
  transition follows an edge of the
  doc-02 §3 machine — forward states in machine order without gaps, `BLOCKED`
  allowed any number of times with each occurrence followed by re-entry into
  the state it interrupted (or by run end); timestamps never move backwards;
  S0 approval predates the first S2 packetization entry; and each
  `PROJECTION-ACCEPTED` cycle has a positive P3 sign-off row.
  In a current-format run, mechanically observable S2 evidence — including a
  packet index or packet rows, an S2 run-log entry, the exact-evidence marker,
  or exact-evidence tables — cannot coexist with a state log that stops before
  `DISTILLING`.
  Decision 0004's forward run formats (`1.1.0-provisional` and
  `1.2.0-provisional`) additionally require
  exactly one structurally valid Core ID/version/digest; adapter
  ID/version/digest; bundle ID/digest/lock reference; checker digest;
  adapter-protocol and run-format version; host identity; model identities and
  realized mapping; adapter-profile ID/digest; and runtime-snapshot
  reference/digest. These are mechanical identity and shape checks only.
  The accepted `run-slice-2` golden predates that format and is not silently
  migrated; `exact-evidence-fragments` is the first complete 1.1
  forward-format fixture, and `source-walk-accounting` is the first 1.2
  fixture.

  A host-neutral checker cannot authenticate a removed or downgraded mutable
  manifest version against historical provenance that is absent from the run's
  Core bytes. A live adapter must therefore compare the Core-parsed manifest to
  its retained run state, original bundle lock, and immutable runtime identity
  before invoking the pinned checker. Existing 1.0 runs remain governed by
  their original immutable bundle/runtime/checker; this current-repository
  legacy fixture exercise is not permission for a new 1.1 or 1.2 run to
  self-select an earlier validation contract.
- K2.3 (`forbidden tokens`, fixture runs only): the fixture-layer
  absolute-forbidden token scan (same zero-tolerance semantics, same token
  list as the existing checker) applied to every canonical Core file of a run directory
  that lives under `docs/fixtures/` — the tokens exist to catch answer-key
  leakage in *generated* fixtures. Real run directories are exempt: an
  arbitrary user corpus may legitimately contain those words, and S0
  preserves source content losslessly, so this check never runs outside
  `docs/fixtures/`.
- K2.4 (`packet resolution`): every packet row's `source_id` exists in the
  corpus manifest; its locator parses under that source's declared scheme
  (`L⟨a⟩-L⟨b⟩` with a≤b within file line count; `M⟨n⟩`/`M⟨n⟩:S⟨k⟩` positive
  ints); its `span_hash` equals sha256 of the located span bytes
  (`node:crypto` is a built-in — allowed).
- K2.5 (`id integrity`): every `RUN-`/`SRC-`/`PKT-`/`CC-`/`NB-`/`PC-`/`RC-`
  /`REF-`/`STM-`/`VER-`/`PRJ-` token anywhere on the canonical Core run surface resolves
  to exactly one definition (generalizes C1/C4/C7). Fixed homes are:
  `run-manifest.md`'s `run_id`, corpus manifest, packet index, claim inventory,
  negative-boundary ledger, pre-cluster tags, route-card files, external-
  referent ledger, stress-test matrix, verifier files, and the projection
  commission's `projection_id` row, respectively. A rendered projection or
  trace cites its `PRJ-*`; neither is a second definition. The sole exception
  to local-home resolution is the manifest's typed `predecessor_run`: it names
  an external prior run whose directory/hash verification is outside this
  run-local checker.
- K2.6 (`claim table shape`): once `DISTILLING` is reached, or whenever a claim
  inventory already exists, claim-inventory rows have exactly 10 columns
  (template T3.3); exactly one disposition from the seven on `active` rows;
  `packets` non-empty; `sources` equals the union of the cited packets'
  sources (recomputed). Before `DISTILLING`, an absent claim inventory is not
  yet applicable.
- K2.7 (`accounting`): disposition-ledger counts equal recomputed counts
  over `active` inventory rows; total row equals inventory `active` count;
  all seven disposition rows present.
- K2.8 (`merge provenance`): C8 semantics over the run's merge-map against
  the inventory (canonical source set ⊇ each absorbed set); absorbed claims
  carry disposition `merged`.
- K2.9 (`criteria precede packets`): once `DISTILLING` is reached, or whenever
  extraction criteria already exist, the extraction-criteria `written`
  timestamp ≤ the earliest run-log S2 entry; any criteria supersession row
  has a matching re-extraction note (string presence, not semantics). Before
  `DISTILLING`, absent criteria are not yet applicable.
- K2.10 (`status discipline`): every non-`active` status cell matches
  `superseded-by:⟨existing row id⟩` or `retracted:⟨nonempty⟩`; a
  `superseded-by` target must exist and be `active` or itself superseded
  (no dangling chains).
- K2.11 (`precis consistency`, only when `precis.md` exists): run the
  existing fixture-layer Précis checks (envelope-17, neutrality boundary,
  C1–C8) against the run's `precis.md` with expectations derived from the
  run ledgers (ID sets, all seven counts, total, and exact §2 source
  inventory), plus: §4 rows equal the 4-column projection of `active`
  inventory rows exactly (same ids, same dispositions).
- K2.12 (`kernel honesty`, when `verification/kernel-report.md` exists):
  the latest report names a checker command containing `validate-run.ts`;
  every result field is PASS/FAIL; explicitly historical or superseded reports
  may retain their retired JavaScript command; a run whose manifest reached
  VERIFIED must have a PASS report from the TypeScript checker.
- K2.13 (`exact evidence and ordered fragments`): retained
  `1.0.0-provisional` and pre-versioned historical runs without
  `exact_evidence_format` preserve the legacy K2.4 interpretation and are not
  reinterpreted. In run formats `1.1.0-provisional` and
  `1.2.0-provisional`, the marker is mandatory once `DISTILLING` is reached
  and must equal
  `aleph-exact-evidence/v1`; its absence is a failure, not a legacy fallback.
  The packet index must contain exact-evidence, ordered-fragment, and
  transformation tables. Every packet is covered exactly once by an `exact`
  evidence record. Every fragment resolves through its source row and packet
  to a readable frozen `md-lines` span; the whole-source content hash, locator
  bounds, canonical base64 bytes, fragment hash, explicit table/order value,
  ordered packet list, and framed exact-evidence hash must agree.
  `single-fragment`, `adjacent-fragments`, and `separate-fragments` are the
  only exact join policies; they describe relationship/presentation and add no
  bytes. Rendered/normalized transformations have their own text hashes and
  must preserve equal predecessor/effective exact-evidence hashes. A
  `degraded-non-exact` record has no packet, fragment, join, or exact hash and
  requires an existing source ID whose frozen locus and whole-source hash
  resolve, a structurally valid source-local locator, a rendered
  transformation, and a reason. For `md-lines`, Core also verifies that the
  declared line range is within the frozen source. Schemes with known grammar
  but no Core reopener remain explicitly structurally checked but mechanically
  unverified. None of these checks compare degraded rendered text to exact
  bytes or claim that rendering is faithful.
- K2.14 (`source walk, gap review, and resume accounting`): only run format
  `1.2.0-provisional` activates
  `source_walk_format: aleph-source-walk/v1` with
  `source_position_format: zero-based-utf8-byte-half-open/v1`. Once S2 is
  mechanically observable, the dedicated ledger and all five tables are
  mandatory. Earlier formats must not be reinterpreted as 1.2.

  For every source, Core reopens the frozen locus, verifies the whole-source
  SHA-256 and byte length, requires valid UTF-8, and rejects any coordinate
  outside the source or inside a multibyte code point. Primary walk intervals
  use canonical zero-based half-open byte coordinates and must form one
  ordered contiguous prefix from byte zero with no reversed interval, hole,
  or overlap. A source declared complete must reach its exact byte length.
  Outcomes are `admitted`, `no-candidate-observed`, `excluded`, `deferred`,
  and `unsupported`. Admitted/excluded rows resolve frozen S1 criterion
  references; deferred rows carry a reason and are open or resolved with a
  closure note; unsupported rows carry a reason and remain blocking.

  Packet-producing extraction events resolve to source-walk intervals,
  packets, and Slice-1 exact-evidence records. Primary events must be declared
  by their admitted interval. Gap-reconciliation events may attach only to a
  compatible primary region and must be linked by exactly one found gap
  record. Overlapping event coordinates are legal only when they are exactly
  equal and share one source-position key. Ordinals within that key are unique
  and contiguous from one. Core maps every bound `md-lines` exact fragment to
  absolute frozen-byte bounds and requires each event interval to be contained
  in exactly one fragment for its packet. A packet with a locator Core cannot
  map fails the 1.2 exact-position contract rather than receiving a false
  positional PASS. For reconciliation, candidate and event intervals are
  equal and the event remains subject to the same fragment-containment rule.

  Resume cursors are actual traversal/checkpoint records. Each identifies the
  **next unprocessed** byte/event, carries the frozen source hash, resolves
  predecessor walk/event records, remains monotonic and in bounds, and cannot
  move beyond open intervals or pending events. A pause after ordinal one
  stays at that same byte position and names ordinal two; siblings committed
  uninterrupted require no intermediate cursor. Every recorded shared cursor
  is validated against its position, pending ordinal, predecessor event/walk,
  and source hash. Equal-byte cursor history at one shared position may
  advance ordinal but may not regress. Cursor `reason` is one of `initial`,
  `progress`, `bounded-pause`, `resumed-shared-position`, or
  `source-complete`.

  Gap reviews record distinct primary-producer and reviewer invocation
  identities plus `no-gap-candidate-found`, `gap-candidate-found`, or
  `cannot-determine`. Core can verify only the distinct declared identities
  and ledger structure; live host isolation remains adapter evidence. Every
  review names a same-source terminal primary source-end cursor and a
  `review_basis_digest`. Core hashes the UTF-8 bytes of one compact JSON object
  in fixed field order with:

  - format `aleph-source-walk-review-basis/v1`;
  - source ID and reopened frozen-source SHA-256;
  - SHA-256 and byte length of the exact current
    `ledgers/extraction-criteria.md` bytes;
  - all primary walk rows for the source in ledger order, with every column;
  - all `origin = primary` event rows in ledger order, with every column;
  - unique primary packet IDs in first-event order, each packet's source,
    locator, span hash, exact-evidence record key/packet list/count/join/hash,
    and its fragment identities ordered by `fragment_order`; and
  - every field of the named terminal primary cursor.

  The review result, reconciliation event, and all gap-reconciliation
  packet/event additions are excluded. This binds review inputs only; it does
  not prove semantic correctness, fresh-context isolation, or worker
  independence. A post-review reconciliation event may use an existing exact
  shared-position key and the next contiguous ordinal without a retroactive
  primary cursor; it does not rewrite the completed primary walk or its review
  basis. A found candidate with `status = open` carries valid
  coordinates but uses `proposed_packet_id = none` and
  `reconciliation_event_id = none`. `status = reconciled` requires the valid
  exact packet, exactly one matching committed reconciliation event, and the
  positional bindings above. `cannot-determine` is blocking.

  One completion row per source binds hash, byte length, last cursor, all gap
  reviews, and `complete` or `blocked`. Completion requires full coverage, a
  source-end cursor, no open deferred/unsupported interval, no pending event,
  at least one gap review, and no open or indeterminate finding. An S2 exit or
  later manifest state requires all sources complete. For a blocked source,
  the named final cursor is also checked as the actual current frontier:
  committed primary intervals/events may not already exist beyond a
  non-shared cursor; at a shared cursor, ordinals before the named next ordinal
  are committed, that ordinal and later ones are not committed, and no later
  primary traversal/event is committed. This rule does not reinterpret
  historical cursor rows.

K2.13 proves only frozen-source byte fidelity and declared structure. It does
not prove semantic entailment, good packetization, good normalization, correct
interpretation, atomicity, complete extraction, or source trustworthiness.

K2.14 proves structural traversal and procedural review accounting only. It
does not prove perfect recall, semantic candidacy, review correctness,
exclusion wisdom, or model quality.

**False-positive guards:** prose mentions like "no `CC-999` exists" are NOT
exempt — same context-free strictness as the existing forbidden-token scan;
therefore run artifacts must never name nonexistent ids even rhetorically
(template README warns). Locator schemes beyond the two named are ignored by
K2.4 with a `PASS (scheme ⟨x⟩ unverified)` note rather than a failure —
new schemes get verification when their fixture arrives.

**Battery (minimum 10):** missing `run-manifest.md` → K2.1; state log with
ASSEMBLED before CORPUS-FROZEN → K2.2; forbidden token in a fixture run's
`run-log.md` → K2.3, while the same token in a run directory outside
`docs/fixtures/` → no finding (exemption proven, not assumed);
arbitrary canonical-looking bytes under top-level `control/runtime/` → no
finding, followed by the same dangling identifier in canonical nested
`verification/control/` and `run-log.md` paths → K2.5;
tampered span (hash mismatch) → K2.4; dangling `PKT-*`, `RUN-*`, `NB-*`, or
`PRJ-*` citation, or duplicate `PRJ-*` commission definition → K2.5;
inventory row with two dispositions → K2.6; ledger total off by one
→ K2.7; absorbed claim missing a source in canonical set → K2.8; criteria
timestamp after first S2 log entry → K2.9; `superseded-by:PKT-0999`
(nonexistent) → K2.10; §4 in precis.md missing one active claim → K2.11.
The Slice-1 K2.13 battery additionally mutates curly quotation bytes, a
ligature, newline bytes, fragment row order, an undeclared join, a normalized
  byte role substituted for exact evidence, a missing frozen source file, a
  fragment hash, locator bounds, a normalization event's effective exact hash,
  new-format marker activation, forward-identity completeness, suppressed
  `DISTILLING` with retained S2 evidence, degraded locator bounds, a missing
  degraded frozen locus, and degraded exact-claim constraints. Each must fail
  its named K2 invariant. The pre-versioned
golden remains a positive legacy lock; the `1.1.0-provisional` exact-evidence
fixture remains the positive 1.1 lock.

The Slice-2 K2.14 battery retains its original 28 mutations of a skipped interior interval, uncovered
origin, uncovered terminal bytes, reversed and out-of-bounds intervals,
undeclared overlap, duplicate and missing shared-position ordinals, a resume
jump past a same-position sibling, backward and beyond-end cursors, missing
packet/exact-evidence links, invalid exclusion criteria, malformed deferred
and unsupported regions, false completion over uncovered/open work, missing
or non-distinct gap review, open and cannot-determine gap results, removed
format marker and ledger, understated manifest state, a UTF-8-splitting
coordinate, and changed frozen source bytes. The
`source-walk-accounting` fixture is the positive 1.2 lock. Added review
regressions cover a true open candidate, premature open IDs, same-source
wrong-span evidence, stale primary walk/criteria/exact-evidence review bases, a
nonterminal basis cursor, a stale blocked final cursor, shared ordinal
regression, a post-review same-position reconciliation ordinal gap, invalid
recorded shared cursors, and duplicate completion review IDs. Positive
baselines cover both interrupted and uninterrupted primary siblings plus
same-position post-review reconciliation without cursor backdating. Loa
separately tests retained 1.2 authority against manifest downgrade and version
removal, and rejects an extractor cursor return with no Core `reason`.
