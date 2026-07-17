# Spec K4 + K5 — Route Cards and the Finalization Gate (slice 11)

**Target:** `clusters/` + `ledgers/external-referents.md` in a run directory
or routed fixture (`kind: routed`). Enforces the card invariants and makes
the compositional finalization gate computable. Posture *reasonableness*
stays in the harness (L7); the kernel checks structure and taint arithmetic
only.

**Closed vocabularies:** postures `adversarial-weighted`,
`convergent-weighted`, `hybrid`, `unrouted-pending-external-referent`;
shape-vector values `low`, `med`, `high`; referent statuses `unresolved`,
`supplied`, `declined`.

## K4 — Card checks

- K4.1 (`card shape`): every `clusters/route-cards/RC-*.md` carries the
  9 fixed fields and the 7-signal shape vector table, values from the
  closed sets. Filename id equals in-card id.
- K4.2 (`smallest invariant`): every card lists ≥1 `PKT-` id; every cited
  `PKT-`/`CC-`/`PC-`/`RC-`/`REF-` id resolves to its home ledger. This is
  the doctrine's "no card without a packet ID; no cited packet absent from
  the index", finally enforced —
  `FAIL … K4.2 (smallest invariant): RC-03 lists no packet ids`.
- K4.3 (`pending posture ⇒ REF`): posture
  `unrouted-pending-external-referent` requires ≥1 id in the card's
  referents relation, each with status `unresolved` in the referent ledger.
  The relation is the union of card fields and the ledger's `depends` RC/CC
  ids; all statuses use the closed vocabulary. Conversely an unresolved REF
  requires the pending posture, while supplied/declined requires history
  showing pending followed by the current rerouted posture.
- K4.4 (`tags are tags`): `pre-cluster-tags.md` rows have exactly 3 columns;
  no file matching `PC-*.md` exists anywhere under `clusters/` (pre-clusters
  must not become documents).
- K4.5 (`dependency sanity`): `Depends on` ids resolve; the dependency graph
  over cards contains no cycle unless every edge of the cycle carries the
  literal annotation `mutual` in the card field.
- K4.6 (`posture history`): every card has ≥1 posture-history entry; the
  last history entry's posture equals the posture field.

## K5 — Taint gate checks

Definition (mechanical): the **provenance cone** of an artifact = the set of
route clusters reachable by following, transitively: the clusters whose
`claim_ids`/`packet_ids` the artifact cites, plus each cluster's
`Depends on` edges. A cluster is **tainted** iff its referents field or its
transitive dependencies include a REF with status `unresolved`.

- K5.1 (`taint declaration`): every tainted card's `Blocks/finalization
  impact` field is non-empty; every `unresolved` REF row's `taint note` is
  non-empty.
- K5.2 (`no externally-complete claim under taint`): the literal marker
  string `externally complete` may not appear in any run artifact that
  cites a tainted cluster (or its claims) without the accompanying marker
  `external-referent unresolved` in the same file —
  `FAIL … K5.2 (gate): synthesis/cluster-synthesis.md claims externally
  complete over tainted RC-03`.
- K5.3 (`Précis taint honesty`): if any load-bearing (carried/merged) claim
  belongs to a tainted cluster, `precis.md` §17 must contain the marker
  `external-referent unresolved` and name every unresolved `REF-` id in the
  transitive card cone; every declined referent in that cone is also named.
- K5.4 (`resolution hygiene`): every `supplied` REF row cites either
  `external-research-intake`/`authority-statement` source rows (which must
  exist in the corpus manifest) or an explicitly cited positive manifest
  sign-off whose authority matches `supplied_by`; `supplied_by` is non-empty.
  Source rows must have been admitted at S0. Research material received after
  freeze is admissible only in a successor run whose manifest names the prior
  run; within the frozen current run, only an already-admitted authority
  statement or a manifest sign-off may resolve the REF. K5.4 verifies manifest
  membership and sign-off linkage, not wall-clock receipt; run audit owns that
  chronology judgment.
  A REF flipped to `supplied` with neither is the
  worker-resolved-a-referent defect —
  `FAIL … K5.4 (resolution hygiene): REF-02 supplied without intake or sign-off`.

**False-positive guards:** the *phrase* "external-referent unresolved"
appearing in doctrine quotes inside `run-log.md` is fine (K5.2/K5.3 scan
only synthesis, precis, projections, and cards — the finalization surfaces);
`declined` referents lift taint (the authority chose to proceed without —
the decline row itself is the record) but K5.3 still requires the decline to
be named in §17.

**Battery (minimum 9):** card with zero packets → K4.2; card citing
`PKT-9999` → K4.2; pending posture without REF → K4.3; REF resolved but
posture never re-routed (no history entry) → K4.3; a `PC-2.md` file →
K4.4; circular `Depends on` without `mutual` → K4.5; "externally complete"
in synthesis over a tainted cluster → K5.2; tainted load-bearing claim with
a §17 missing the marker → K5.3; REF flipped to supplied by nobody → K5.4.
Clean routed fixture (with one deliberately tainted cluster properly
marked, and one resolved REF properly re-routed) → exit 0.
