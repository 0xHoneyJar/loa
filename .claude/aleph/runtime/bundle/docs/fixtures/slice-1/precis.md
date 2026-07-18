# v0 Research Précis — Slice 1 Fixture

> **Synthetic v0 Research Précis.** Distilled from `corpus.md` (three synthetic
> source fragments). This is a **fixture artifact** proving the Précis *shape*,
> not a real research deliverable. It is **projection-neutral**: it deliberately
> does not become a PRD, GTM plan, market landscape, or product spec.
>
> Format is Markdown prose + tables. **No schema is frozen** — per the wedge,
> packets are run first and the matrices name the structure second.

This artifact carries all 17 fields of the v0 acceptance envelope defined in
`../../precis-wedge.md`. Each field is a section below, in envelope order.

---

## 1. Corpus scope

A bounded synthetic corpus of three fragments (`SRC-001`, `SRC-002`,
`SRC-003`) modeled after Freeside / token-gating / business-research material.
Scope is limited to claims about Freeside's **token-gated access model** and its
immediate community/growth mechanics. Anything outside that frame is out of
declared scope for this corpus. Instance #1, not Aleph's boundary.

## 2. Source inventory

| source_id | kind (synthetic)          | locus in corpus.md     |
|-----------|---------------------------|------------------------|
| SRC-001   | deep-research snippet     | "access model" section |
| SRC-002   | conversation excerpt      | "tiers & context"      |
| SRC-003   | design / working note     | "portal & growth"      |

All three sources are invented for this fixture. No real export content.

## 3. Extraction method / inclusion criteria

- A **candidate claim** = a declarative assertion about the Freeside token-gated
  access model or its community/growth mechanics that could plausibly bear on a
  downstream decision.
- **Excluded from candidacy at extraction** (recorded, not silently dropped):
  pure dialogue scaffolding ("Agreed", "Right"), speaker labels, and formatting.
  These stay outside the candidate-claim inventory under this recorded rule.
- Once a sentence is recognized as a candidate claim it **must** receive a
  disposition; it may not vanish. "Non-load-bearing" is resolved *by disposition
  inside the inventory*, never as a pre-extraction silent discard.
- Normalization: each claim is restated once in neutral form; duplicates across
  sources are merged with provenance retained.

## 4. Candidate-claim inventory / packet index

Every candidate claim, with an individual ID, normalized statement, source
provenance, and exactly one recorded disposition. This is the packet index: no
claim's fate is asserted without an entry here.

| claim_id | normalized claim | source(s) | disposition |
|----------|------------------|-----------|-------------|
| CC-001 | Token-gated membership (threshold token holding unlocks gated channels) is Freeside's core access primitive | SRC-001 | carried |
| CC-002 | Token gating increases member retention / engagement over time | SRC-001, SRC-003 | merged |
| CC-003 | The gating token may be a single fungible token or a multi-token per-tier arrangement | SRC-001 | deferred |
| CC-004 | Membership should support tiered holder levels (holder / contributor / core) rather than all-or-nothing | SRC-002 | carried |
| CC-005 | Token-gated communities are common across the market | SRC-002 | backgrounded |
| CC-006 | Gated perks drive referrals (the intended growth loop) | SRC-002 | carried |
| CC-007 | Token gating improves retention (keep the gate) | SRC-003 | merged |
| CC-008 | Freeside should launch its own L2 chain to host the system end-to-end | SRC-003 | excluded-with-reason |
| CC-009 | The gated portal accent color should be teal | SRC-003 | judged-non-load-bearing |
| CC-010 | Referral rewards may be paid in the token or in non-token points | SRC-003 | unresolved |

Inventory is complete: 10 candidate claims, 10 dispositions, zero unrecorded.

## 5. Classification / disposition ledger summary

Coverage of all seven dispositions (including `judged-non-load-bearing`):

| disposition | count | claim_ids |
|-------------|-------|-----------|
| carried | 3 | CC-001, CC-004, CC-006 |
| merged | 2 | CC-002, CC-007 |
| deferred | 1 | CC-003 |
| excluded-with-reason | 1 | CC-008 |
| backgrounded | 1 | CC-005 |
| judged-non-load-bearing | 1 | CC-009 |
| unresolved | 1 | CC-010 |
| **total** | **10** | all candidate claims accounted for |

## 6. Carried claims

- **CC-001** — Token-gated membership is the core access primitive. Load-bearing;
  everything else hangs off it.
- **CC-004** — Tiered holder levels (not all-or-nothing membership).
- **CC-006** — Gated perks drive referrals (the growth loop).

## 7. Merged claims

- **CC-002** (canonical) ← merges **CC-007**. Two near-duplicate retention
  claims ("gated access keeps members engaged", SRC-001; "token gating improves
  retention", SRC-003) are normalized into one retention claim. Both source
  provenances are retained (see merge map, §11). Duplicate conviction is not
  allowed to masquerade as new evidence.

## 8. Deferred claims

- **CC-003** — Fungible single token vs multi-token per-tier. Deferred: depends
  on a later architecture decision not resolvable from this corpus. Remains
  visible in the queue, not dropped.

## 9. Excluded-with-reason claims

- **CC-008** — "Launch its own L2 chain." **Reason:** out of declared corpus
  scope (the corpus scope is the token-gated access model, not chain
  infrastructure), and contrary to the read-only PoC posture; no supporting
  evidence in-corpus. Excluded, with the reason recorded — not silently dropped.

## 10. Backgrounded claims

- **CC-005** — "Token-gated communities are common across the market." Kept as
  background market context. Not load-bearing to Freeside's specific access
  model and carries no in-corpus evidence, so it informs but does not drive.

## 11. Duplicate / merge map

| canonical | absorbs | basis | provenance retained |
|-----------|---------|-------|---------------------|
| CC-002 | CC-007 | same underlying retention claim, different wording/source | SRC-001 + SRC-003 |

No other duplicates detected in this corpus.

## 12. Do-not-use / negative boundaries

- **Out of scope:** chain/L2 infrastructure decisions (basis for excluding
  CC-008). This corpus does not authorize claims about Freeside operating its
  own chain.
- **Not evidence:** market-prevalence statements (CC-005) may not be cited as
  evidence *for* a Freeside-specific design choice; they are background only.
- **No fabricated competitors:** no real competitor or market figure is asserted
  anywhere in this fixture.

## 13. Cluster synthesis

Normalized, deduplicated synthesis of the load-bearing picture (presentation
compression only — every underlying claim still has its own inventory entry in
§4; grouping here never replaces the inventory):

- **Access model (carried):** Freeside's core is token-gated membership
  (CC-001), refined into tiered holder levels (CC-004).
- **Why it matters (carried + merged):** gating is associated with improved
  retention (CC-002, merged) and gated perks are the referral/growth loop
  (CC-006).
- **Open architecture (deferred/unresolved):** token structure
  (single-vs-multi, CC-003) and referral-reward denomination (CC-010) are not
  settled by this corpus.
- **Context only (backgrounded):** the category is common in the market (CC-005).

Non-load-bearing material (e.g. CC-009 portal color) is grouped out of the
synthesis narrative but remains individually recorded in §4 with its disposition.

## 14. Unresolved claims / questions

- **CC-010** — Should referral rewards be paid in the project token or in
  non-token points? Open; needs a decision before build. Kept visible as an
  unresolved claim, not buried as a vague "question."

## 15. Consumer-deferred projection notes

This is where a consumer (a downstream repo or substrate) *would* project this
Précis into something concrete — and where this fixture deliberately stops:

- A product repo *could* project CC-001/CC-004 into a PRD for tiered gating.
- A growth surface *could* project CC-006 into a referral-program spec.
- A future business/market-intelligence consumer *could*
  project CC-005 into market positioning.

**None of these projections are generated here.** The Précis is
projection-neutral; the renderings belong to the consuming repo, not to Aleph.

## 16. Verification summary

- Source inventory present (§2): 3 sources.
- Extraction criteria recorded (§3).
- Candidate-claim inventory present (§4): 10 claims, each with one disposition.
- All seven dispositions represented (§5).
- Duplicate merged with provenance retained (§7, §11).
- Excluded claim carries a reason (§9).
- Deferred and unresolved claims remain visible (§8, §14).
- No downstream projection generated (§15).
- Output is a single portable, projection-neutral file (this document).

See `README.md` for the criterion-by-criterion self-check table.

## 17. Known incompleteness / limits

- **Bounded corpus:** only three synthetic fragments. "Complete" here means
  *every candidate claim extracted from this declared scope has a recorded
  disposition* — it does **not** mean omniscient or total semantic capture.
- **Synthetic:** no real research; conclusions are illustrative of the artifact
  shape, not findings about Freeside.
- **No schema freeze:** field structure is provisional; a later slice may
  rename/restructure.
- **No live machinery:** the Précis was authored by hand for this fixture; no
  extractor/parser code exists or is implied.
