# 04 — Pipeline Stages and Definitions of Done

> Status: ACCEPTED FOR IMPLEMENTATION by
> [`Decision 0003`](../decisions/0003-architecture-build-kit-implementation.md);
> capability claims still require their named replay evidence.

This document turns the wedge's completeness trail and the routing doctrine
into an executable stage graph. It refines — never replaces — the accepted
order of operations:

```
source inventory → extraction pass → packet index → classification/disposition
→ duplicate/merge map → do-not-use boundaries → stress-test matrix
→ cluster synthesis → unresolved/deferred queue → projection-neutral Précis
```

Conventions used below:

- **Actor** — who does the work in agent mode (worker role names from
  [`05-orchestration-on-fable-5.md`](05-orchestration-on-fable-5.md)); in
  manual mode the human plays every role, at the fidelity the manual runbook
  allows.
- **Blind-context rule** — what this stage's actor must NOT see (tenet T9).
- **DoD** — the Definition of Done: the checklist that must be fully true
  before the run advances. DoD items marked ⚙ are mechanically checkable (T1,
  once the corresponding checker slice exists); items marked ⚖ are verified by
  the harness (T2); items marked 👤 are human-gated (T3).

The stage graph:

```
S0 intake ─ S1 inventory ─ S2 packets ─ S3 claims ─ S4 merges ─ S5 dispositions
                                                                     │
             S7 pre-clusters ◄──────────────── S6 evidence roles ◄───┘
                  │
             S8 route clusters + routing (iterative, propagating)
                  │                │
        S9a adversarial arm   S9b convergent arm     (per cluster, weighted;
                  │                │                  S9b gated on referents)
                  └──────┬─────────┘
                    S10 synthesis + unresolved queue
                         │
                    S11 Précis assembly
                         │
                    S12 verification gate (T1 kernel + T2 harness)
                         │
                    S13 acceptance checkpoint (PR, authority)   ══► ACCEPTED
                         │
        P1 Tier-1 projections ─ P2 Tier-2 renderings ─ P3 projection gate
```

Fan-out points (agent mode): S2 parallel per source; S3/S5/S6 parallel per
packet/claim batch; S9 parallel per cluster; verification parallel per target.
Barriers: S4 needs all of S3 (dedup is global); S8 needs all of S7; S11 needs
all ledgers final.

---

## S0 — Intake and corpus freeze

- **Purpose:** turn "here is everything I have" into a declared, bounded,
  frozen corpus with an approved scope.
- **Inputs:** raw material from the user; a stated research goal ("what is
  this corpus about, and roughly what might it feed?" — recorded as context,
  never as a projection commitment).
- **Outputs:** run directory skeleton; `run-manifest.md`; `corpus/sources/`
  populated; draft corpus scope.
- **Actor:** Intake Clerk + the user; **authority gate** on scope.
- **Blind-context rule:** none (nothing downstream exists yet) — but the
  intake conversation must not record dispositions or conclusions.
- **Work:** preserve source bytes losslessly (no summarizing, cleaning,
  newline conversion, or character substitution); assign provisional source groupings; surface
  sensitivity flags (PII, confidential) for the user to rule on; draft the
  scope statement (what is in, what is explicitly out); estimate size and
  propose budgets.
- **DoD:**
  - [ ] ⚙ every raw file is under `corpus/sources/`, content-hashed, and
        listed in the draft manifest
  - [ ] ⚙ run manifest exists with mode; Core, adapter, bundle, checker,
        protocol, and run-format pins; exact host/model identities (or
        `core-manual` + `human`); and an immutable runtime-snapshot digest
  - [ ] 👤 authority approved the corpus scope statement and sensitivity
        rulings; approval recorded in the manifest
  - [ ] ⚙ corpus frozen: hashes recorded; run state = `CORPUS-FROZEN`

## S1 — Source inventory and extraction criteria

- **Purpose:** the auditable boundary between noise and candidacy, fixed
  before anyone extracts.
- **Inputs:** frozen corpus; scope statement.
- **Outputs:** `corpus/manifest.md` finalized (source inventory with kinds,
  trust classes, admission notes); `ledgers/extraction-criteria.md`.
- **Actor:** Intake Clerk (inventory) + Coordinator-role review of criteria.
- **Blind-context rule:** criteria are written from the scope + a *skim* of
  the corpus, not from a full read that starts forming conclusions.
- **DoD:**
  - [ ] ⚙ inventory ↔ files one-to-one; hashes verify
  - [ ] ⚙ every source has kind, trust class, admission note
  - [ ] ⚙ extraction-criteria record exists and predates any packet (ledger
        timestamps)
  - [ ] ⚖ criteria are specific enough that two independent extractors would
        agree on candidacy for a sampled handful of spans (harness spot-check)

## S2 — Extraction pass (packetization)

- **Purpose:** elevate every span that meets the criteria into a packet with
  re-entry coordinates while recording a complete structural source walk and
  then testing primary recall with a separate fresh gap review.
- **Inputs:** frozen corpus; extraction criteria. Nothing else.
- **Outputs:** `ledgers/packet-index.md`; `ledgers/source-walk.md`; retained
  packet-level relation proposals when a separately bounded relation task is
  legal from the same one-source context (never canonical REL rows).
- **Actor:** Extractors (fan out per source), fresh gap reviewers, and the
  orchestrator as the only canonical ledger writer.
- **Blind-context rule (hard):** extractors see corpus + criteria only — no
  scope-of-run chatter, no prior packets from other sources (prevents
  cross-source anchoring), no disposition vocabulary.
- **Relation boundary:** S2 may propose context, formal-reference, or discourse
  relations only from its legal one-source packet context. It cannot inspect
  another source, propose a cross-source relation, or create claim dependency
  before claims exist.
- **Work:** walk each source in source order. Append contiguous half-open UTF-8
  byte intervals for admitted, non-candidate-observed, excluded, deferred, or
  unsupported regions. Record packet-producing events separately, including
  shared-position keys and contiguous event ordinals when more than one event
  occurs at one position. When bounded work stops with work remaining, record
  a next-work cursor bound to the frozen source hash; a pause between
  shared-position siblings stays at the same byte position and names the next
  ordinal. Siblings committed uninterrupted need no intermediate cursor. For
  each admitted span,
  record one or more ordered exact fragments with source + locator + hash +
  exact base64 bytes, plus a separate display preview and the criterion that
  admitted it. Use one packet per fragment. Declare `single-fragment`,
  `adjacent-fragments`, or `separate-fragments`; never hide inserted text
  between fragments. If exact bytes cannot be obtained, record a source-bound
  `degraded-non-exact` rendering with its source locator, reason, and no packet
  rather than reconstructing evidence. After the primary walk, dispatch a
  distinct fresh-context coverage reviewer over the frozen source, criteria,
  walk accounting, and admitted exact evidence. The reviewer returns no gap
  candidate, a located gap candidate, or cannot-determine; it never writes the
  canonical ledgers. Before recording the result, the orchestrator binds it to
  the terminal primary cursor and the Core review-basis digest. The
  orchestrator validates any candidate under Slice-1 exact-evidence rules and
  appends the packet/event or leaves the finding open with no future canonical
  IDs. A same-position reconciliation appends the next contiguous event
  ordinal without rewriting primary walk or cursor history.
  Over-extraction is the safe direction: a useless packet costs a
  `judged-non-load-bearing` disposition later; a missed span costs
  completeness silently.
- **DoD:**
  - [ ] ⚙ every packet resolves (locator + hash) to its source span
  - [ ] ⚙ every exact fragment's bytes and hash reopen against the frozen
        source; fragment order, packet binding, join policy, and exact-evidence
        digest verify
  - [ ] ⚙ rendered/normalized transformations remain separate and preserve
        predecessor/effective exact-evidence identity
  - [ ] ⚙ degraded renderings retain source/locator provenance while claiming
        no packet, fragment, or exact hash
  - [ ] ⚙ primary walk intervals begin at source byte zero, are ordered,
        contain no hole or undeclared overlap, and reach the exact source end
        before that source is marked complete
  - [ ] ⚙ every packet has one committed extraction event; same-position
        events have one shared key with unique contiguous ordinals; each event
        lies within exactly one exact fragment for its packet
  - [ ] ⚙ every recorded next-work cursor is source/hash bound, monotonic, in
        bounds, uses a Core cursor reason, and cannot skip an open interval or
        same-position sibling; equal-byte shared cursors cannot regress
        ordinal, while uninterrupted siblings require no intermediate cursor
  - [ ] ⚙ exclusions reference frozen S1 exclusion classes; deferred and
        unsupported regions remain reasoned and visibly open or validly closed
  - [ ] ⚙ every source has a distinct gap-review record; found candidates are
        bound to the terminal primary review basis and reconciled through exact
        evidence, while true open findings with no packet/event IDs and
        cannot-determine results block completion
  - [ ] ⚙ no packet carries stance/disposition/cluster vocabulary
  - [ ] ⚖ fresh gap review attacks primary recall from sealed inputs; a
        no-gap result is recorded model judgment, not deterministic proof
  - [ ] ⚙ per-source completion is recorded in the source-walk ledger; S2
        cannot exit while any source is blocked, and a blocked final cursor
        cannot sit behind already committed primary work

**Boundary:** checker-clean structural walk closure means every frozen byte has
a declared traversal state and the independent gap-review procedure is
recorded. It does not mean the extractor or reviewer achieved perfect semantic
recall.

## S3 — Candidate-claim normalization

- **Purpose:** turn packets into individually stated candidate claims —
  restated once, neutrally, with provenance.
- **Inputs:** packet index, including exact-evidence fragment and
  transformation records (+ read-only corpus access for context windows
  around a packet).
- **Outputs:** `ledgers/claim-inventory.md` (claims + provenance + claim type;
  dispositions still blank); in run format 1.3 and later, S3 structural
  identity outcomes append to `ledgers/lineage.md`; retained claim-level
  relation proposals may be returned but are not canonical REL rows.
- **Actor:** Normalizers (fan out per packet batch).
- **Blind-context rule:** normalizers do not assign dispositions and do not
  see other batches' outputs mid-pass (dedup is S4's job, done globally).
- **Relation boundary:** S3 may propose any legally typed claim relation
  available from the current packet/claim batch and its legal source context.
  It may not inspect another batch merely to discover relations. Global,
  cross-batch, or cross-source relation judgment belongs to S4.
- **Work:** one packet may yield zero, one, or several claims; several packets
  may support one claim (recorded, not merged yet). The neutral restatement
  must be entailed by the packet spans — adding outside knowledge here is the
  fabrication failure mode. Normalization writes only normalized claim text;
  it never edits, replaces, or relabels source fragments, display text, or
  exact-evidence hashes.
- **DoD:**
  - [ ] ⚙ every claim has ≥1 packet; every packet either yielded claims or has
        an explicit structural lineage closure; a true zero-claim packet uses
        the `no-claim` lineage event
  - [ ] ⚖ entailment spot-check: sampled claims re-derived from their packets
        alone by fresh verifiers; non-entailed restatements fail the batch
  - [ ] ⚙ claim IDs unique, hash-stable

## S4 — Duplicate/merge mapping

- **Purpose:** compact by normalization; kill duplicate conviction.
- **Inputs:** full claim inventory.
- **Outputs:** `ledgers/merge-map.md`; for run format 1.3 and later, each merge or
  duplicate also appends one lineage event and materializes a new canonical
  successor claim while every predecessor row remains immutable history. In
  run format 1.4, S4 also emits the one canonical
  `ledgers/relations.md` table at closure. Run format 1.5 replaces the single
  exit instant with the cumulative C1/C2/C3 composite barrier and emits
  `ledgers/internal-ambiguities.md` during C2.
- **Actor:** Normalizer-Judge, relation producers, fresh relation reviewers,
  ambiguity producers, fresh ambiguity reviewers, material-impact producers,
  fresh material-impact reviewers, human procedural authority where required,
  and the orchestrator as sole canonical writer (global pass — this stage is a
  barrier). Human procedure never determines source meaning.
- **Work:** near-duplicates merge with all provenance retained; genuinely
  contradictory claims are *never* merged (they stay separate, flagged for
  S5/S9); the corroboration note distinguishes independent support from
  restatement.
- **Relation closure:** challenge accumulated S2/S3 proposals against the
  lineage-current inventory. S4 owns any of the eight relation types when the
  judgment requires global, cross-batch, cross-source, or otherwise
  unavailable legal context. Producers propose only; fresh reviewers never
  write the ledger; the orchestrator recomputes each exact review-subject
  digest, requires the exact `upheld` VER target, resolves structural
  conflicts, and serializes canonical REL rows only at the closure barrier.
  In 1.5, C1 serializes and validates the complete relation ledger and makes it
  immediately read-only. C2 detects/reviews internal ambiguity, binds any
  material impact, and obtains human procedural authority only when the
  reviewed Class C scope requires it. C3 exits only after C2 is durable. S4
  does not acquire disposition, evidence-role, routing, duplicate/overlap
  relation, candidate-selection, or source-meaning authority.
- **DoD:**
  - [ ] ⚙ C8 provenance superset holds for every merge row; in 1.3 every
        merge/duplicate map row matches one typed lineage event whose new
        successor conserves predecessor packet provenance
  - [ ] ⚖ merge-precision spot-check: sampled merges defended to a refuter
        ("argue these are different claims"); refuted merges are unwound
  - [ ] ⚖ contradiction sweep: harness searches the inventory for
        incompatible pairs the mapper missed; found pairs get flagged rows
  - [ ] ⚙ every canonical REL row has the exact 17 fields, legal taxonomy,
        typed state/endpoint/provenance, lineage-current durable endpoints,
        recomputed review-subject digest, and one exact upheld VER target
  - [ ] ⚙ prohibited relation subgraphs are acyclic, self-edges and
        duplicate/conflicting scopes fail, and qualifier/configuration mixed
        cycles do not trigger a false global-DAG rule
  - [ ] ⚖ fresh relation review attacks missing/over-broad/wrong
        type/target, context-as-support, qualifier loss, wrong semantic locus,
        outside-corpus invention, explicit absence from incomplete context,
        and unjustified permitted cycles
  - [ ] ⚙ canonical relation bytes are absent/empty before closure, written
        only at C1, and refused unchanged after C1; retained K2 state does not
        claim historical intra-S4 timing
  - [ ] ⚙ 1.5 closure phases are exactly C1 → C2 → C3; C1-only state requires
        a complete K2.16-valid relation artifact and permits only C2 work
  - [ ] ⚙ every T5.1/T5.2 row satisfies exact expression reopening, search
        basis, candidate grammar/currentness, relation eligibility, legal state
        matrix, single-headed history, and exact upheld review binding
  - [ ] ⚖ fresh ambiguity review judges detection, candidate adequacy, and
        affected-relation completeness without human response/observation or
        desired-conclusion context
  - [ ] ⚙ every material-impact subject binds the exact T5.2/C1 basis and
        pinned Core requirement refs; Class B has empty scope and no request,
        while Class C has complete nonempty operative scope
  - [ ] ⚙ Core recomputes the legal action set and complete non-operative human
        presentation; a retained human response is applied once, never inferred
        or fabricated, and every T5.3 row selects no candidate
  - [ ] ⚙ C2 is terminal only for legal reviewed state; nonterminal actions,
        material revisions, replacement presentations, and actual resumes use
        contiguous single-headed M/Q sequences
  - [ ] ⚙ C3 exists only after C2 DoD and is the sole 1.5 permission to enter S5

## S5 — Disposition pass

- **Purpose:** resolve every candidate claim into exactly one of the seven
  dispositions, with reasons where the doctrine demands them.
- **Inputs:** claim inventory + merge map + read-only relation ledger +
  read-only reviewed ambiguity/restriction state + scope statement +
  negative-boundary drafts. **Not** the routing/cluster layers (which do not exist yet — the
  four-layer model keeps disposition upstream of stance).
- **Outputs:** completed inventory; `ledgers/disposition-ledger.md`;
  `ledgers/negative-boundaries.md`; first entries of
  `ledgers/unresolved-queue.md`.
- **Actor:** Disposition Judges (fan out per claim batch) + harness review.
- **Blind-context rule:** judges see the claim, its packets, the scope, and
  the criteria — not other judges' calls on unrelated batches.
- **Relation boundary:** relations may supply challenge context but never
  mechanically select or change a disposition. S5 never rewrites REL rows.
- **Ambiguity boundary:** reviewed ambiguity and a restriction overlay may
  constrain legal downstream operations, but never mechanically select a
  disposition. Human observation/comment bytes are withheld from S5 judgment.
- **DoD:**
  - [ ] ⚙ every current research claim exactly one disposition; in 1.3 this
        population is the lineage-current claim set, while historical
        predecessors require no fabricated new disposition; accounting balances
  - [ ] ⚙ every `excluded-with-reason` has a reason; every exclusion citing
        scope maps to a negative boundary
  - [ ] ⚙ contradiction pairs from S4 are not silently resolved (each side
        `unresolved` or explicitly reasoned otherwise)
  - [ ] ⚖ adversarial review: for a sample stratified across dispositions —
        plus *every* `excluded-with-reason` and every contradiction — a
        refuter argues the opposite disposition; refutations that stand force
        `unresolved` and a run-log entry

## S6 — Evidence-role pass

- **Purpose:** type every claim×source edge; declare removal effects for
  load-bearing support (artifact 8; issue #18's ALEPH-EVIDENCE-ROLE-001).
- **Inputs:** inventory, merge map, read-only relation ledger, source trust classes.
- **Outputs:** `ledgers/evidence-roles.md`.
- **Actor:** Evidence-Role Judges.
- **Relation boundary:** no REL family or multiplicity becomes
  load-bearing/corroborative/contradictory support. S6 independently judges
  the `CC x SRC` evidence-role surface and never rewrites REL rows.
- **DoD:**
  - [ ] ⚙ role-coverage accounting: every carried claim has qualifying support
        or an explicit synthesis/inference marker with uncertainty
  - [ ] ⚙ no confirmed-carried claim supported only by `unresolved-source`
  - [ ] ⚙ decorative edges excluded from all support counts
  - [ ] ⚖ removal-effect declarations sanity-checked by refuters on a sample
        (full leave-one-source-out attack happens in S9a)

## S7 — Structural pre-clustering

- **Purpose:** provisional grouping on stance-free structural features only
  (contradiction density, reference density, claim-type distribution).
- **Outputs:** `clusters/pre-cluster-tags.md` — tags, never documents.
- **Actor:** Cluster Cartographer.
- **DoD:**
  - [ ] ⚙ every tag row references existing packet/claim IDs
  - [ ] ⚙ no pre-cluster artifact beyond tag rows exists
  - [ ] ⚖ feature honesty: tags justified by structural signals, not by
        doctrine-relative reasoning (spot-checked)

## S8 — Route-cluster formation and routing

- **Purpose:** form doctrine-relative route clusters as a spine emerges;
  assign provisional postures from the internal-shape vector; propagate
  routing as dependencies resolve; record external-referent needs.
- **Inputs:** everything S1–S7. This is the first stage allowed to be
  doctrine-relative — pretending otherwise was the named error.
- **Outputs:** `clusters/route-cards/RC-*.md`; `clusters/routing-log.md`
  (tool mode: every propagation step); `ledgers/external-referents.md`
  (needs recorded; **resolutions only via the gate**).
- **Actor:** Router; **authority gate** whenever a load-bearing cluster is
  `unrouted-pending-external-referent` — the run may proceed elsewhere
  (the gate is compositional, not total) but the affected cone is tainted
  until the authority supplies a recorded statement/sign-off or declines the
  referent. Research material received after S0 does not change this run; it
  starts a successor run whose manifest names this one.
- **DoD:**
  - [ ] ⚙ every card satisfies the card invariants (≥1 packet ID; IDs resolve;
        posture from the closed set; referrent-pending ⇒ `REF` record)
  - [ ] ⚙ dependency edges acyclic or explicitly annotated where mutual
  - [ ] ⚖ posture reasonableness: refuters argue the opposite arm-weighting
        for sampled clusters; upheld objections re-route
  - [ ] 👤 all referent needs surfaced to the authority in one batch, with the
        taint cone each implies

## S9a — Adversarial arm (stress-testing)

- **Purpose:** pressure-test invariants and expose contradictions on clusters
  weighted adversarial; instantiate the stress-test matrix; execute
  evidence-removal attacks against declared removal effects.
- **Outputs:** `arms/stress-test-matrix.md` (STM rows incl. evidence-removal
  rows); superseding ledger entries where attacks change dispositions.
- **Actor:** Adversarial Panel — fresh-context refuters with distinct lenses
  (contradiction, unsupported-exclusion, silent-disappearance, false-certainty,
  duplicate-conviction, projection-leakage, evidence-removal — the slice-2
  risk families, now as runtime roles).
- **DoD:**
  - [ ] ⚙ every named risk family has ≥1 matrix row (slice-2 discipline)
  - [ ] ⚙ every load-bearing evidence edge in adversarial-weighted clusters
        has an evidence-removal row whose outcome is consistent with the
        declared removal effect *or* a superseding correction
  - [ ] ⚖ every matrix row's "correct handling" actually points at where the
        run resolved it
  - [ ] ⚙ matrix rows reference only existing IDs (C5/C6/C7 generalized)

## S9b — Convergent arm (referent reconciliation) — UNVALIDATED

- **Purpose:** reconcile clusters weighted convergent against supplied
  referents (prior art, existing systems, constraints).
- **Gate (hard):** runs only over `supplied` referent material already present
  when this run's corpus froze at S0. No referent, no reconciliation — the arm
  idles rather than inventing. A post-freeze authority statement/sign-off may
  resolve the current run's gate but does not become research material;
  post-freeze research can be reconciled only in the successor run that admits
  it at S0.
- **Outputs:** `arms/reconciliations/…` per cluster.
- **Honesty note:** the convergent-heavy shape has **no replay case** yet
  (validation ledger). Until the second golden corpus exists, S9b runs are
  themselves experiments: expect the artifact shape to be renamed by evidence,
  and never present S9b output as validated machinery.
- **DoD:**
  - [ ] ⚙ every reconciliation row cites `CC` + `REF`/`SRC` IDs
  - [ ] ⚙ conflicts with referents recorded as claims-vs-referent rows, not
        silent claim edits
  - [ ] ⚖ refuter pass over "agrees" verdicts (agreement is the easy lie)
  - [ ] 👤 authority informed this arm ran unvalidated (manifest note)

## S10 — Cluster synthesis and unresolved queue

- **Purpose:** the presentation-compressed load-bearing picture; the visible
  queue of what is not settled.
- **Outputs:** `synthesis/cluster-synthesis.md`; finalized unresolved queue.
- **Actor:** Synthesist (sees everything; writes prose; changes no ledger).
- **DoD:**
  - [ ] ⚙ synthesis references only existing claim IDs (C1) and every
        non-grouped-out claim appears somewhere downstream (C2)
  - [ ] ⚙ grouping compressed presentation only — inventory untouched
  - [ ] ⚖ faithfulness: refuters check the synthesis asserts nothing the
        dispositions don't license (e.g. carried-claim language for an
        unresolved claim fails)

## S11 — Précis assembly

- **Purpose:** compile the 17-field, projection-neutral Précis from the
  ledgers (assembly rule, artifact 17).
- **Outputs:** `precis.md`.
- **Actor:** Assembler.
- **DoD:**
  - [ ] ⚙ all 17 envelope fields present, in order, rendered from ledgers
  - [ ] ⚙ zero projection generation; provisional-schema wording present
  - [ ] ⚙ known-incompleteness section lists every taint, every unvalidated
        arm that ran, every deviation logged in the manifest

## S12 — Verification gate

- **Purpose:** the full T1 + T2 pass over the assembled run.
- **Outputs:** `verification/kernel-report.md`; harness reports; fixes as
  superseding entries + re-assembly if needed (loop S11↔S12 until green).
- **DoD:**
  - [ ] ⚙ kernel green (real checker, exact command recorded)
  - [ ] ⚖ harness report attached: all stage-level ⚖ items completed, verdict
        counts summarized, every `refuted`/`cannot-determine` traced to its
        ledger consequence
  - [ ] ⚙ run state = `VERIFIED`

## S13 — Acceptance checkpoint

- **Purpose:** the human decision that the Précis is done, at a PR checkpoint,
  after independent audit.
- **Work:** branch + PR containing the run directory; an independent
  auditor reviews against the contracts; authority accepts or returns
  with findings.
- **DoD:**
  - [ ] 👤 independent audit completed and attached
  - [ ] 👤 authority acceptance recorded in the manifest; PR merged
  - [ ] ⚙ run state = `ACCEPTED` — only now is the projection engine unlocked

---

## P1 — Tier-1 projections

- **Inputs:** the ACCEPTED `precis.md` + ledgers, read-only; a **projection
  commission** from the authority defining a unique `PRJ-NNN`, the type, and
  exact trace path.
- **Outputs:** the commissioned `PRJ-NNN` at
  `projections/tier-1/<type>.md` + trace + selection ledger.
- **DoD (per projection):**
  - [ ] ⚙ selection ledger covers every carried/merged claim
  - [ ] ⚙ commission, trace, and rendered metadata agree on `PRJ-NNN` and
        trace path
  - [ ] ⚙ trace: no load-bearing statement without claim backing; no new
        claims; negative boundaries honored; taint markers propagated
  - [ ] ⚖ rendering-quality review against the type's template rubric
  - [ ] ⚙ Précis untouched (hash identical before/after)

## P2 — Tier-2 terminal renderings

Same contract as P1, rendered from Tier-1 output and/or the Précis, using the
domain plugin's template (PRD, SSD, …). Additional DoD: the plugin's own
conformance checks pass; domain sections that need facts the Précis lacks
appear as explicit gaps, never as filled-in guesses.

## P3 — Projection acceptance

Audit + authority acceptance per projection, at a PR checkpoint, exactly as
S13. A projection is never "done" by the renderer's say-so.

---

## Stage-contract summary table

| Stage | Emits | Barrier? | Fan-out | Authority gate |
|-------|-------|----------|---------|----------------|
| S0 | manifest, frozen corpus | — | — | scope + sensitivity |
| S1 | inventory, criteria | yes (criteria before packets) | — | — |
| S2 | packet index; retained one-source relation proposals | — | per source | — |
| S3 | claim inventory (no dispositions); retained batch-local relation proposals | — | per packet batch | — |
| S4 | merge map; lineage closure; canonical relation ledger | yes (global) | relation production/review may fan out under bounded bundles | — |
| S5 | dispositions, boundaries, queue | — | per claim batch | — |
| S6 | evidence roles | — | per claim batch | — |
| S7 | pre-cluster tags | yes | — | — |
| S8 | route cards, routing log, referent records | yes | — | referents |
| S9a/b | matrix / reconciliations | — | per cluster | S9b unvalidated notice |
| S10 | synthesis, queue final | yes | — | — |
| S11 | precis.md | yes | — | — |
| S12 | kernel + harness reports | yes | per target | — |
| S13 | accepted PR | yes | — | acceptance |
| P1–P3 | projections + traces | per type | per type | commission + acceptance |
