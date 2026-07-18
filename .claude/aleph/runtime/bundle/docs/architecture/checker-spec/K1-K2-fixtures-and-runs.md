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

- K2.1 (`layout`): required paths exist: `run-manifest.md`, `run-log.md`,
  `corpus/manifest.md`, `ledgers/extraction-criteria.md`,
  `ledgers/packet-index.md`, `ledgers/claim-inventory.md`,
  `ledgers/disposition-ledger.md`. Others (merge-map, evidence-roles,
  clusters/, arms/, precis.md, verification/) are required **iff** the
  manifest's state log shows the run reached the state that produces them
  (state→artifact table hardcoded from doc 04's "Emits" column).
- K2.2 (`manifest`, legacy predecessor format): manifest carries mode, doctrine_sha (40-hex), corpus
  hash, exactly one `run_id` (`RUN-<slug>`), exactly one `predecessor_run`
  (`none` or a different `RUN-<slug>`), and ≥1 state-log row; every state-log
  transition follows an edge of the
  doc-02 §3 machine — forward states in machine order without gaps, `BLOCKED`
  allowed any number of times with each occurrence followed by re-entry into
  the state it interrupted (or by run end); timestamps never move backwards;
  S0 approval predates the first S2 packetization entry; and each
  `PROJECTION-ACCEPTED` cycle has a positive P3 sign-off row.
  Decision 0004's forward run format additionally requires exact
  Core/adapter/bundle/checker/protocol/run-format/host/model/runtime pins.
  The accepted `run-slice-2` golden predates that format and is not silently
  migrated; the first new-format run fixture must extend K2.2 in lockstep.
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
- K2.6 (`claim table shape`): claim-inventory rows have exactly 10 columns
  (template T3.2); exactly one disposition from the seven on `active` rows;
  `packets` non-empty; `sources` equals the union of the cited packets'
  sources (recomputed).
- K2.7 (`accounting`): disposition-ledger counts equal recomputed counts
  over `active` inventory rows; total row equals inventory `active` count;
  all seven disposition rows present.
- K2.8 (`merge provenance`): C8 semantics over the run's merge-map against
  the inventory (canonical source set ⊇ each absorbed set); absorbed claims
  carry disposition `merged`.
- K2.9 (`criteria precede packets`): the extraction-criteria `written`
  timestamp ≤ the earliest run-log S2 entry; any criteria supersession row
  has a matching re-extraction note (string presence, not semantics).
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
Clean golden run → exit 0.
