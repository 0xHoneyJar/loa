# 03 — Artifact Contracts

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md).
> Field lists below are **provisional shapes**, offered in the same spirit as
> the v0 acceptance envelope: enough structure to build fixtures against, no
> schema freeze.
> Format remains Markdown prose + tables (the portability contract); nothing
> here requires JSON, YAML, or a database — though agent mode may additionally
> emit machine-twin copies of any ledger (see §20).

Each artifact entry states: purpose, producer → consumer, provisional fields,
and hard invariants (the ones a future conformance slice would enforce).
Artifacts 1–14 belong to the distillation engine, 15–17 to verification,
18–19 to the projection engine, 20 to agent mode.

---

## 1. Run manifest (`run-manifest.md`)

- **Purpose:** the run's identity card — everything needed to interpret,
  reproduce, or audit the run.
- **Producer → consumer:** S0 → everyone; appended at every state transition.
- **Fields (provisional):** run id; mode (agent/manual/hybrid); corpus
  reference + content hash; declared corpus scope (prose); Core ID/version/tree
  digest; adapter ID/version/tree digest (`core-manual` for manual mode);
  bundle ID/digest and lock reference; checker digest; adapter-protocol and
  run-format versions; exact host identity; exact model identifiers and the
  realized profile mapping (or `human`); immutable runtime-snapshot path and
  digest; source provenance such as a commit SHA; budgets granted and spent;
  state-transition log (state, timestamp, actor); authority sign-offs with
  dates; known deviations from the runbook, with reasons.
- **Invariants:** exists before any other run artifact; the state-transition
  log is append-only and every transition follows an edge of the
  [`02-system-architecture.md`](02-system-architecture.md) §3 state machine —
  forward states appear in machine order without gaps, while `BLOCKED` may
  appear any number of times, each occurrence followed by re-entry into the
  state it interrupted (or by run end); all execution pins are exact, never
  aliases such as "latest"; the original bundle and runtime snapshot govern
  every resumption. Historical fixtures retain their recorded predecessor
  format rather than being silently repinned to current bytes. Forward-format
  Core checking validates the manifest's declared identity structure; a host
  adapter separately binds those declarations to retained execution authority
  and must reject version removal, downgrade, or pin disagreement before
  invoking the run's pinned checker.

## 2. Corpus manifest and source inventory (`corpus/manifest.md`)

- **Purpose:** the declared, frozen, bounded input — the thing "completeness"
  is defined against.
- **Producer → consumer:** S0/S1 → every later stage; the Précis §1–§2 are
  rendered from it.
- **Fields per source (provisional):** `SRC-NNN`; kind (conversation export,
  deep-research output, design note, spec, external-research intake, …);
  locus (file path within `corpus/sources/`); span-addressing scheme used;
  content hash; date or date-range if known; **trust class** (first-party
  note / model-generated / third-party / unverifiable); **sensitivity flags**
  (PII, confidential, licensing constraints); admission note (why this source
  is in scope).
- **Invariants:** every file under `corpus/sources/` has exactly one inventory
  row and vice versa; hashes verify; the corpus is a *blind* input — no
  candidate-claim IDs, disposition vocabulary, or other answer-key material
  (the existing corpus-boundary checks, generalized); post-freeze edits are
  forbidden — a changed hash fails the run.
- **Notes:** trust class and sensitivity flags are *recording*, not judgment:
  they feed the evidence-role pass (a claim confirmed only by an unverifiable
  source cannot be carried as confirmed) and the projection stage (sensitive
  spans need handling rules), without pretending the pipeline verifies truth.

## 3. Extraction-criteria record (`ledgers/extraction-criteria.md`)

- **Purpose:** the recorded boundary between raw noise and candidate claims —
  what makes disposition-level completeness auditable (wedge: "the extraction
  method / inclusion criteria are recorded").
- **Producer → consumer:** S1 (written **before** extraction begins) → S2/S3
  workers; auditors.
- **Fields:** the candidate-claim definition for this corpus (what counts as
  "could plausibly bear on a downstream decision" here); the exclusion classes
  kept outside candidacy (greetings, scaffolding, tool noise, …) with
  examples; normalization rules (restated-once-in-neutral-form conventions);
  the segmentation policy (what granularity a packet is).
- **Invariants:** committed to the ledger before the first packet is written;
  any mid-run criteria change is recorded as a superseding entry **and**
  requires re-running extraction over already-processed sources (criteria
  changes are never applied only forward).

## 4. Packet index (`ledgers/packet-index.md`)

- **Purpose:** the stance-neutral inventory of source spans elevated during
  extraction — the re-entry coordinates everything else resolves to.
- **Producer → consumer:** S2 → S3 (claims), S7 (pre-clustering), routing
  cards, auditors ("why this cluster?" reopens packets).
- **Legacy fields per packet:** `PKT-NNNN`; `SRC-NNN`; span locator; span
  content hash; quote/display preview; extraction note (which criterion
  admitted it). Historical `1.0.0-provisional` and pre-versioned packet
  ledgers without an `exact_evidence_format` marker retain this predecessor
  interpretation and are never silently migrated.
- **Compatibility:** run format `1.1.0-provisional` makes the versioned
  exact-evidence extension mandatory whenever the run reaches S2. Existing
  runs remain governed by their original bundle/runtime pins; their packet
  bytes are not reinterpreted. Absence of the marker is permitted only for
  the predecessor run format (or pre-versioned historical artifacts), not as
  an optional capability switch in a new run.
- **Versioned exact-evidence extension:** a packet ledger that declares
  `exact_evidence_format: aleph-exact-evidence/v1` also contains:
  - evidence records with ordered packet IDs, `exact` or
    `degraded-non-exact` state, fragment count, join policy, exact-evidence
    hash, degraded source ID/locator, and degradation reason;
  - fragment records with ledger-local key, evidence key, packet ID, explicit
    order, source ID, locator, `frozen-source` relation,
    `exact-source-bytes` role, fragment hash, and canonical base64 bytes; and
  - transformation records with `rendered` or `normalized` role, predecessor
    and effective exact-evidence hashes, output text, and output-text hash.
- **Join-policy vocabulary:** `single-fragment` means exactly one fragment;
  `adjacent-fragments` means two or more consecutive `md-lines` fragments in
  one source; `separate-fragments` means two or more ordered fragments that
  remain visibly separate. `not-applicable` is reserved for
  `degraded-non-exact` records. No policy inserts hidden bytes.
- **Exact-evidence digest:** SHA-256 over the UTF-8 domain
  `aleph-exact-evidence/v1` plus NUL, followed by each fragment in declared
  order as unsigned 64-bit big-endian byte length plus the exact fragment
  bytes. This framing preserves fragment order and boundaries without
  pretending that discontiguous fragments form one source string.
- **Invariants:** every exact fragment resolves to a frozen source row and
  file; source, packet, locator, fragment hash, and canonical base64 bytes
  agree; every packet in the versioned form is covered exactly once; fragment
  order and join policy are valid; and rendered/normalized transformations
  preserve the predecessor/effective exact-evidence identity. A degraded
  record has no packet, fragment, join, or exact hash; it must retain a source
  ID, source-local locator, rendered transformation, and reason so the
  non-exact rendering remains durably tied to what was degraded.
  Packets carry **no** disposition, cluster verdict, or stance; packet IDs
  remain stable under re-runs.
- **Verification boundary:** deterministic PASS proves source-byte and
  structural fidelity only. It does not prove entailment, packetization
  quality, normalization quality, atomicity, extraction completeness, source
  trustworthiness, or correct interpretation.

## 4a. Source-walk ledger (`ledgers/source-walk.md`)

- **Purpose:** make primary traversal, interruption, resume, independent gap
  review, and final per-source accounting mechanically reconstructable without
  treating packet existence as proof of exhaustive recall.
- **Producer → consumer:** S2 extractors propose ordered walk records and
  cursors; the orchestrator validates and appends them as single writer; a
  distinct fresh-context gap reviewer records semantic gap results; K2 and
  auditors consume the final ledger.
- **Activation:** run format `1.2.0-provisional` requires
  `source_walk_format: aleph-source-walk/v1` and
  `source_position_format: zero-based-utf8-byte-half-open/v1` once S2 begins.
  The prior `1.1.0-provisional` exact-evidence fixture remains a 1.1 artifact
  and is not migrated.
- **Primary walk intervals:** ordered, non-overlapping half-open frozen-byte
  intervals with outcome `admitted`, `no-candidate-observed`, `excluded`,
  `deferred`, or `unsupported`; packet and frozen S1 criterion references
  where applicable; producer invocation; and explicit closure state/reason.
- **Extraction events:** packet-producing events have exact byte positions,
  origin `primary` or `gap-reconciliation`, invocation identity, and commit
  status. Events at one source position share a key and unique contiguous
  ordinals; this is the only allowed same-position multiplicity and does not
  permit arbitrary interval overlap. Core maps each exact `md-lines` fragment
  to absolute frozen-byte bounds and requires the event interval to be
  contained in exactly one fragment for its packet. An unmappable exact
  locator blocks the 1.2 exact-position contract.
- **Resume cursors:** are actual traversal/checkpoint records that identify the
  **next unprocessed** source byte/event and bind it to the source hash plus
  predecessor walk/event records. If work pauses between same-position
  siblings, the cursor stays at that position and advances only the event
  ordinal. Siblings committed without interruption need no fabricated
  intermediate cursor. Every recorded same-position cursor remains strict,
  and cursor history cannot regress in ordinal. Cursor reasons are the Core
  values `initial`, `progress`, `bounded-pause`,
  `resumed-shared-position`, and `source-complete`.
- **Fresh gap reviews:** record distinct producer/reviewer invocation
  identities and one result:
  `no-gap-candidate-found`, `gap-candidate-found`, or `cannot-determine`.
  Each row names a same-source terminal primary cursor and a Core-recomputed
  digest over the frozen source identity, exact S1 criteria bytes, ordered
  primary walk/events, associated primary packet exact-evidence identities,
  and that cursor. The digest excludes the review result and all gap
  reconciliation additions. A post-review reconciliation event may append at
  an existing exact shared position with the next contiguous ordinal; it does
  not backdate a primary cursor, move the primary frontier, or change the
  review basis. A found candidate stays `open` with
  `proposed_packet_id = none` and `reconciliation_event_id = none` until the
  orchestrator validates Slice-1 exact evidence and appends its one committed
  reconciliation event. The candidate and event intervals must be equal, and
  the event must be contained in the proposed packet's exact fragment.
  `cannot-determine` blocks source completion.
- **Completion:** one row per source binds exact source hash/length, final
  cursor, all gap-review records, and `complete` or `blocked`. `complete`
  requires contiguous coverage from byte zero through source end, no open
  deferred/unsupported interval or pending shared event, and no open or
  indeterminate gap finding. For `blocked`, the named final cursor is checked
  against committed primary walk/event state as the actual current frontier;
  historical checkpoints are not subjected to that final-frontier rule.
- **Verification boundary:** K2 proves structural walk closure and that an
  inspectable review-basis record exists. It cannot prove that the extractor
  found every qualifying assertion, that a reviewer returning no candidate
  was semantically correct, or that declared distinct contexts were actually
  isolated. Adapter dispatch receipts remain the process-isolation evidence.

## 5. Candidate-claim inventory (`ledgers/claim-inventory.md`)

- **Purpose:** the heart of the completeness contract — every candidate claim,
  individually, with exactly one disposition. Rendered into Précis §4.
- **Producer → consumer:** S3 (claims) + S5 (dispositions) → everything
  downstream.
- **Fields per claim:** `CC-NNN`; normalized statement (one neutral
  restatement); provenance set (≥1 `PKT-NNNN`; the `SRC` set is derivable);
  **claim type** (proposed, small fixed set — e.g. factual / design-intent /
  constraint / preference / open-question — recorded because routing's shape
  vector and the projection stage both want it); exactly one disposition from
  the seven; disposition rationale (one line); disposition provenance (who/what
  judged it: worker id or "human", plus verifier outcome reference).
- **Invariants:** all existing wedge/checker invariants (unique IDs; exactly
  one disposition; seven-disposition coverage per corpus where applicable;
  ledger accounting balances; C1–C8 cross-section consistency); additionally —
  every claim's provenance set is non-empty and resolves through packets to
  sources; normalized statements remain separate from exact evidence and
  contain no external facts absent from the provenance spans (spot-checked by
  T2, not mechanically).
- **Note on claim type:** this is a *proposed* extension to the §4 table. It
  must earn its place via a fixture; if it turns out to be prose-policing bait
  it gets dropped. It is deliberately **not** the disposition axis and not the
  shape vector — collapsing axes is the named historical mistake.

## 6. Disposition-ledger summary (`ledgers/disposition-ledger.md`)

Unchanged from the wedge (Précis §5): per-disposition counts and claim-id
lists; totals equal the inventory; every claim appears exactly once. Exists as
its own ledger so the accounting is checkable before the Précis is assembled.

## 7. Duplicate/merge map (`ledgers/merge-map.md`)

- **Purpose:** compact-by-normalization with provenance retained; duplicate
  conviction never masquerades as new evidence.
- **Fields per row:** canonical `CC`; absorbed `CC`s; basis (why these are the
  same claim); provenance check (canonical's source set ⊇ each absorbed source
  set — the existing C8); **corroboration note** (proposed): after merging,
  does the merged claim have genuinely independent sources, or one source
  restated? Feeds evidence roles.
- **Invariants:** C8 (no provenance dropped); contradictory claims are never
  merged (slice-2 discipline: contradictions stay separate and unresolved);
  merges are between claims, never between packets.

## 8. Evidence-role ledger (`ledgers/evidence-roles.md`) — NEW

- **Purpose:** close the citation-vs-influence gap (issue #18 / the ProvenAI
  finding): a source being present, being cited, and actually bearing load are
  different states and must not collapse into one "has provenance" checkbox.
- **Producer → consumer:** S6 → routing (shape vector inputs), the stress-test
  arm (what to attack), the Précis verification summary, projections (what may
  be asserted how strongly).
- **Fields per edge (claim × source):** `CC-NNN`; `SRC-NNN`; **role** from a
  bounded set: `load-bearing` / `corroborative` / `contradictory` /
  `contextual` / `decorative` / `unresolved-source`; verification status of
  the source *for this claim* (verified-primary / verified-secondary /
  unverifiable); **declared removal effect** for load-bearing edges only — what
  happens to the claim if this source is removed (downgrades-to-unresolved /
  confidence-decreases / survives-independent-support / must-be-excluded).
- **Invariants (the acceptance criteria of issue #18, restated):** every
  carried claim has ≥1 `load-bearing` or `corroborative` edge **or** is
  explicitly marked synthesis/inference with uncertainty; every edge references
  inventoried IDs; roles come only from the documented set; `decorative` edges
  never count toward support coverage; a claim whose only support is
  `unresolved-source` cannot be carried as confirmed; contradictory edges
  remain visible (never dropped at merge); merged claims retain per-source
  roles.
- **Boundary:** this is an honesty ledger, not causal attribution. It records
  the distiller's declared dependency structure so verifiers can attack it
  (leave-one-source-out, S9); it does not claim to measure model internals,
  and it must not grow into a graph product.

## 9. Do-not-use / negative boundaries (`ledgers/negative-boundaries.md`)

Unchanged in spirit from Précis §12: out-of-scope declarations, not-evidence
rules, harm-bearing do-not-use claims (each also excluded-with-reason in the
inventory). Invariant: every negative boundary cites the claim/source IDs it
governs, so projections can mechanically honor it. Each row defines one
run-local `NB-N` ID; later artifacts cite that row and never redefine the ID.

## 10. Pre-cluster tags (`clusters/pre-cluster-tags.md`)

Per routing doctrine §4: **tags, not documents.** One file listing `PC-N` tags
against packet/claim IDs, grouped on stance-free structural features only.
Invariants: no pre-cluster carries prose analysis, posture, or doctrine claims;
a pre-cluster never promoted to a route cluster leaves only its tag rows.

## 11. Route-cluster cards (`clusters/route-cards/RC-NN.md`)

The doctrine's sparse card (routing doctrine §11), unchanged in fields:

```
Route cluster ID:            RC-NN
Working name:
Routing posture:             adversarial-weighted | convergent-weighted |
                             hybrid | unrouted-pending-external-referent
Internal-shape vector:       (the seven signals, coarse values suffice)
Structural pre-cluster tags used:
Packet/source IDs:
Candidate claim IDs:
Key dispositions:
Unresolved external referents:   REF-NN refs, if any
Depends on:                  lateral RC deps (routing propagation)
Blocks/finalization impact:  what this cluster taints if unresolved
```

Invariants (the "smallest manual-mode invariant", now stated for both modes):
no card without ≥1 packet ID; no cited packet ID absent from the packet index;
posture from the closed set; every `unrouted-pending-external-referent`
posture has a matching `REF-NN` record. Tool mode may additionally materialize
the full edge graph (`routing-log.md` records every propagation step); manual
mode never has to.

## 12. External-referent records (`ledgers/external-referents.md`) — NEW

- **Purpose:** make the compositional finalization gate (routing doctrine §8)
  computable and auditable: the corpus can reveal a *need* for an external
  referent; only a recorded authority statement/sign-off can *supply* one
  within the frozen current run. Research material can supply one only through
  S0 intake in a successor run whose manifest names the prior run.
- **Fields per record:** `REF-NN`; the need (what external fact is required,
  phrased as a question); the clusters/claims that depend on it; status
  (`unresolved` / `supplied` / `declined`); when supplied — the supplier
  (authority or named intake), the intake reference (a new run containing the
  supplied material as `SRC`, or an authority sign-off recorded verbatim), and
  date.
- **Invariants:** an output is "externally complete" only if every load-bearing
  cluster in its provenance cone has no `unresolved` referent (the gate);
  referent *resolutions* are never authored by pipeline workers; a supplied
  referent that arrived as research material starts a successor run (the frozen
  corpus is never extended in place) and becomes a scoped intake with its own
  `SRC` rows, so its claims flow through extraction like everything else rather
  than bypassing the ledger.

## 13. Arm outputs

- **Stress-test matrix (`arms/stress-test-matrix.md`)** — as instantiated by
  slice-2: `STM-N` rows carrying adversarial pressure, source refs, claim IDs,
  risk if handled badly, correct handling, where resolved. Extended (proposed)
  with **evidence-removal rows**: for each load-bearing evidence edge, a row
  that verifies the declared removal effect holds when a verifier argues the
  source away.
- **Reconciliations (`arms/reconciliations/`)** — the convergent arm's
  per-cluster outputs: claim ↔ referent comparisons (agrees / conflicts /
  extends / out-of-scope), each citing `CC`/`SRC`/`REF` IDs. Shape is
  explicitly **unvalidated** (validation ledger) and will be named properly by
  the second golden corpus, not by this plan.

## 14. Cluster synthesis and unresolved queue

As in the wedge: `synthesis/cluster-synthesis.md` is presentation compression
only (every underlying claim keeps its inventory row); `ledgers/unresolved-queue.md`
keeps deferred/unresolved claims visible with what would resolve them.

## 15. Verifier verdicts (`verification/harness/…`)

- **Purpose:** the T2 audit trail — what was challenged, by whom, with what
  outcome.
- **Fields per verdict:** verdict id; target (artifact + ID(s)); verifier
  role/lens (refuter / independent re-derivation / evidence-removal / …);
  fresh-context attestation (what the verifier was and was not shown);
  verdict (`upheld` / `refuted` / `cannot-determine`) + one-paragraph
  rationale; disposition consequence (none / flagged / forced-unresolved),
  applied by the orchestrator as a superseding ledger entry.
- **Invariants:** verdicts never edit ledgers directly — they cause appends;
  quorum and disagreement rules are per-stage policy
  ([`06-verification-and-conformance.md`](06-verification-and-conformance.md) §4);
  `cannot-determine` is a first-class outcome that propagates to `unresolved`,
  never silently to "pass".

## 16. Kernel report (`verification/kernel-report.md`)

The T1 conformance run over this run directory: checker version (git SHA),
check groups run, PASS/FAIL lines, and the exact command. Invariant: a Précis
may not enter `VERIFIED` state without a green kernel report produced by the
real checker (never a hand-written claim of one).

## 17. The Research Précis (`precis.md`)

Unchanged in contract: the 17-field v0 acceptance envelope, projection-neutral,
complete by disposition coverage, compact by normalization. What this plan
adds is an **assembly rule** for tool mode:

> The Précis is *compiled from the ledgers*, not free-generated. Sections
> §1–§12, §14, §16 are deterministic renderings of ledger content (a human or
> agent may smooth prose, but every row and count comes from a ledger).
> Sections §13 (cluster synthesis) and §17 (known incompleteness) are authored
> prose — written by the synthesist, verified by the harness, and bound by the
> same cross-reference checks as everything else.

This keeps the artifact identical in shape to the accepted fixtures while
making tool-mode assembly reproducible and cheap to re-run. The evidence-role
summary and the routing/card summary would join the envelope **only** via a
future envelope-amendment slice with authority approval (open question #3 in
[`12-risks-open-questions-do-not-build.md`](12-risks-open-questions-do-not-build.md)).

## 18. Projection trace + selection ledger (`projections/traces/…`) — NEW

- **Purpose:** extend traceability across the neutrality boundary: a rendered
  document must be auditable back to claims exactly as claims are auditable
  back to source.
- **Projection identity:** P1 assigns one run-local `PRJ-NNN` in the
  commission's `projection_id` row. That defining commission also records the
  accepted Précis hash and exact projection-trace path. The trace and rendered
  document repeat the ID only as citations to that definition.
- **Selection ledger fields:** for the projection at hand — every carried /
  merged claim in the Précis, with `used` / `not-used` and a reason for
  `not-used` (out of this projection's scope / superseded by another claim /
  deferred). Unresolved and deferred claims relevant to the projection's scope
  must map to an explicit open-questions section in the rendered document.
- **Trace fields:** per load-bearing statement in the rendered document — the
  statement (or a stable anchor to it) and the claim IDs backing it; plus a
  `scaffolding` class for structural prose (headings, transitions) that
  asserts nothing.
- **Invariants:** no load-bearing statement without claim backing; no new
  claims minted at projection time (a projection that needs a missing fact
  records a gap, it does not invent); negative boundaries honored (a
  do-not-use claim can never resurface as an assertion); external-completeness
  taint propagates — a projection built on tainted clusters carries the
  `external-referent unresolved` marker prominently, not in a footnote.

## 19. Tier-1 / Tier-2 projection documents (`projections/tier-1/…`, `tier-2/…`)

Per ADR 0001: Tier-1 (product-doctrine, architecture/primitive-map,
responsibility/environment-verification map, mvp-wedge) is domain-agnostic;
Tier-2 (PRD, SSD, series-bible, GTM/ops manual, …) is domain-specific and
pluggable. Each projection **type** owns: a template, authoring instructions,
a fixture, and conformance checks — acquired in its own slice
([`07-projection-stage.md`](07-projection-stage.md)).

## 20. Machine-twin ledgers (agent mode, optional) — NEW

Agent mode may emit, next to any Markdown ledger, a structured twin (e.g.
`claim-inventory.json`) produced via schema-constrained output. Rules: the
Markdown ledger remains canonical and human-auditable; twins are derived,
never hand-edited; any divergence between twin and ledger is a T1 failure.
Twins exist so downstream tooling and the kernel can parse without fragile
table-parsing — but the portability contract stays Markdown-first, and manual
mode never has to produce them.

---

## Cross-cutting invariant table (the ones a conformance slice would target first)

| # | Invariant | Today | Under this plan |
|---|-----------|-------|-----------------|
| X1 | Every ID resolves to its fixed home; no phantoms, no duplicate definitions | C1–C7 for `CC`/`SRC`/`STM` in fixtures | generalized to `RUN`/`SRC`/`PKT`/`CC`/`NB`/`PC`/`RC`/`REF`/`STM`/`VER`/`PRJ` across a run directory |
| X2 | Accounting balances (inventory ↔ ledger ↔ sections) | enforced | unchanged, plus evidence-role coverage accounting |
| X3 | Corpus is blind; answer-key leakage fails | enforced | generalized: later-stage vocabulary may not leak into earlier-stage artifacts |
| X4 | Merges retain provenance | C8 | unchanged, plus per-source roles retained |
| X5 | Précis never projects | enforced | unchanged; plus the reverse — projections never mint claims |
| X6 | No card without packet IDs; every packet reopens source | doctrine only | checked once run fixtures exist |
| X7 | Externally-dependent outputs carry taint until referents resolve | doctrine only | computable over `REF` records + provenance cones |
| X8 | Verifier verdicts append, never edit | — | new |
| X9 | Kernel green before VERIFIED; authority before ACCEPTED | culture | recorded in manifest, checked |
