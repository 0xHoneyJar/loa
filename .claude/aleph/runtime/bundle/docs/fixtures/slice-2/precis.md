# v0 Research Précis — Slice 2 Adversarial Fixture

> **Synthetic adversarial v0 Research Précis.** Distilled from `corpus.md` (four
> synthetic source fragments, `SRC-101`–`SRC-104`). This is a **fixture artifact**
> proving the Précis doctrine *survives compression pressure*, not a real research
> deliverable. It is **projection-neutral**: it deliberately does not become a
> PRD, GTM plan, market landscape, or product spec.
>
> Format is Markdown prose + tables. **No schema is frozen** — per the wedge,
> packets are run first and the matrices name the structure second.

This artifact carries all 17 fields of the v0 acceptance envelope defined in
`../../precis-wedge.md` (sections 1–17 below, in envelope order). It **also**
instantiates the `stress-test matrix` step from the completeness trail
(`../../precis-wedge.md` §94–107) — the step Slice 1 did not exercise. The matrix
appears between §12 (do-not-use boundaries) and §13 (cluster synthesis), its
position in the trail.

> **Scope note (Aleph Slice 2, Choice A).** The stress-test matrix is demonstrated
> here at the *fixture level only*. This slice does **not** amend the accepted
> provisional v0 envelope in `../../precis-wedge.md`. Aleph's precedent is to run the
> packet first and let the matrix name the structure second; whether the envelope
> should later require a stress-test matrix is deferred to a future slice once this
> concrete matrix shape exists as evidence.

---

## 1. Corpus scope

A bounded synthetic corpus of four fragments (`SRC-101`–`SRC-104`) modeled after
Freeside / token-gating / business-research material, **seeded with adversarial
compression cases**: a direct contradiction, a three-way near-duplicate, a
plausible-but-out-of-scope claim, a tempting-to-drop cosmetic claim, an
ambiguous open question, an architecture-dependent deferral, and a do-not-use
claim that carries real harm. Scope is limited to claims about Freeside's
token-gated access model and its immediate community/growth mechanics. Anything
outside that frame is out of declared scope. Instance #2, not Aleph's boundary.

## 2. Source inventory

| source_id | kind (synthetic) | locus in corpus.md |
|-----------|------------------|--------------------|
| SRC-101 | deep-research snippet | "access model" |
| SRC-102 | conversation excerpt | "growth thread" |
| SRC-103 | working note | "gating rules" |
| SRC-104 | design / longitudinal note | "dashboard & profiles" |

All four sources are invented for this fixture. No real export content.

## 3. Extraction method / inclusion criteria

- A **candidate claim** = a declarative assertion about the Freeside token-gated
  access model or its community/growth mechanics that could plausibly bear on a
  downstream decision.
- **Excluded from candidacy at extraction** (recorded, not silently dropped):
  pure dialogue scaffolding ("Maybe", "Sure", "Honestly"), speaker labels, and
  formatting. These stay outside the candidate-claim inventory under this
  recorded rule.
- Once a sentence is recognized as a candidate claim it **must** receive a
  disposition; it may not vanish. "Non-load-bearing" and "do-not-use" are both
  resolved *by disposition inside the inventory*, never as a silent discard.
- Normalization: each claim is restated once in neutral form; near-duplicates
  across sources are merged with provenance retained; **contradictory claims are
  NOT merged** — they are kept as separate claims and the contradiction is
  recorded.

## 4. Candidate-claim inventory / packet index

Every candidate claim, with an individual ID, normalized statement, source
provenance, and exactly one recorded disposition. No claim's fate is asserted
without an entry here.

| claim_id | normalized claim | source(s) | disposition |
|----------|------------------|-----------|-------------|
| CC-101 | Token-gated membership (threshold holding unlocks gated channels) is Freeside's core access primitive | SRC-101, SRC-103 | carried |
| CC-102 | Membership should support tiered holder levels (holder / contributor / core), not all-or-nothing | SRC-101 | carried |
| CC-103 | Gated perks drive referrals (the intended growth loop) | SRC-101 | carried |
| CC-104 | Token gating is associated with improved member retention/engagement (canonical retention claim) | SRC-101, SRC-102, SRC-104 | merged |
| CC-105 | A free, open membership tier maximises sign-ups / top-of-funnel growth | SRC-102 | unresolved |
| CC-106 | Membership must be strictly token-gated with no free tier; a free side door collapses the access model | SRC-103 | unresolved |
| CC-107 | Run a token buyback / treasury program to support the token price | SRC-102 | excluded-with-reason |
| CC-108 | Token-gated communities are common across the market | SRC-102 | backgrounded |
| CC-109 | The member dashboard should default to dark mode with a teal accent | SRC-104 | judged-non-load-bearing |
| CC-110 | Display well-known members' wallet holdings on their public profiles to boost status | SRC-104 | excluded-with-reason |
| CC-111 | The gating token may be a single fungible token or a multi-token per-tier arrangement | SRC-103 | deferred |
| CC-112 | Referral rewards may be paid in the project token or in non-token points | SRC-103 | unresolved |
| CC-113 | Gating keeps members engaged / active longer (retention restatement) | SRC-102 | merged |
| CC-114 | Retention is consistently higher in gated periods than open periods (retention restatement) | SRC-104 | merged |

Inventory is complete: 14 candidate claims, 14 dispositions, zero unrecorded.

## 5. Classification / disposition ledger summary

Coverage of all seven dispositions:

| disposition | count | claim_ids |
|-------------|-------|-----------|
| carried | 3 | CC-101, CC-102, CC-103 |
| merged | 3 | CC-104, CC-113, CC-114 |
| deferred | 1 | CC-111 |
| excluded-with-reason | 2 | CC-107, CC-110 |
| backgrounded | 1 | CC-108 |
| judged-non-load-bearing | 1 | CC-109 |
| unresolved | 3 | CC-105, CC-106, CC-112 |
| **total** | **14** | all candidate claims accounted for |

Ledger total (14) equals inventory count (14).

## 6. Carried claims

- **CC-101** — Token-gated membership is the core access primitive. Load-bearing
  and multiply sourced (SRC-101 and SRC-103 agree on the gate itself).
- **CC-102** — Tiered holder levels rather than a single binary gate.
- **CC-103** — Gated perks are the referral/growth loop.

Note: CC-101 carries only the *existence* of the gate as the access primitive,
on which SRC-101 and SRC-103 agree. The contested question of whether a free
tier should *also* exist is a separate matter held unresolved (CC-105/CC-106,
§14); carrying CC-101 does not silently resolve that contradiction.

## 7. Merged claims

- **CC-104** (canonical) ← merges **CC-113** and **CC-114**. Three near-duplicate
  retention claims appear across three different sources: "gating appears to
  improve retention" (SRC-101), "gating keeps people engaged / active longer"
  (SRC-102), "retention is consistently higher when gated" (SRC-104). They are
  normalized into one retention claim. **All three source provenances are
  retained** (see merge map, §11). This is a three-way merge, not the pairwise
  merge of Slice 1: repeating the same conviction across three sources is **not**
  allowed to masquerade as three independent pieces of evidence (the
  duplicate-conviction risk).

## 8. Deferred claims

- **CC-111** — Single fungible token vs multi-token per-tier. Deferred: depends
  on a later architecture decision not resolvable from this corpus. Remains
  visible in the queue, not dropped, and explicitly **not** projected into a
  token-design spec.

## 9. Excluded-with-reason claims

- **CC-107** — "Run a token buyback / treasury program to support token price."
  **Reason:** out of declared corpus scope (the scope is the token-gated *access
  model*, not token-price / treasury financial operations); contrary to the
  read-only PoC posture; single conversational source with no supporting
  evidence. Plausible-sounding, but excluded with the reason recorded — not
  silently dropped, and not excluded on vibes.
- **CC-110** — "Display well-known members' wallet holdings on public profiles."
  **Reason:** a do-not-use claim (see §12) — it exposes member financial data,
  creates a doxxing / privacy-harm vector, and is outside the access-model scope.
  Excluded with the reason recorded; also carried into the negative-boundary
  list so it cannot be silently revived downstream.

## 10. Backgrounded claims

- **CC-108** — "Token-gated communities are common across the market." Kept as
  background market context. Not load-bearing to Freeside's specific access
  model and carries no in-corpus evidence, so it informs but does not drive, and
  may not be cited as evidence *for* a design choice (§12).

## 11. Duplicate / merge map

| canonical | absorbs | basis | provenance retained |
|-----------|---------|-------|---------------------|
| CC-104 | CC-113, CC-114 | same underlying retention claim, three wordings/sources | SRC-101 + SRC-102 + SRC-104 |

This is a **three-way** merge. No other duplicates detected. The contradiction
pair CC-105 / CC-106 is **deliberately not in this map** — contradictory claims
are never merged (§3, §14, stress-test matrix STM-1).

## 12. Do-not-use / negative boundaries

- **Out of scope:** token-price / treasury financial operations (basis for
  excluding CC-107). This corpus does not authorize claims about managing the
  token's price.
- **Do-not-use (harm):** publishing members' wallet holdings on public profiles
  (CC-110). This must not be used in any synthesis or projection; it is a
  privacy / doxxing harm. Recorded here so the claim is visibly refused, not
  silently absent.
- **Not evidence:** market-prevalence statements (CC-108) may not be cited as
  evidence *for* a Freeside-specific design choice; background only.
- **No fabricated competitors:** no real competitor or market figure is asserted
  anywhere in this fixture.

## Stress-test matrix

> The completeness trail (`../../precis-wedge.md` §94–107) places a **stress-test
> matrix** between the do-not-use boundaries and cluster synthesis. Slice 1 did
> not instantiate it. Slice 2 does, here. Each row maps an adversarial pressure to
> the claim(s) it threatens, the risk if mishandled, the correct Aleph handling,
> and where in this Précis it is resolved. This section is the proof that the
> Précis does not merely *list* claims — it *survives* compression pressure.

| case_id | adversarial pressure | source refs | candidate claim IDs | risk if handled badly | correct Aleph handling | resolved at |
|---------|----------------------|-------------|---------------------|-----------------------|------------------------|-------------|
| STM-1 | Direct contradiction (free open tier vs strictly no free tier) | SRC-102, SRC-103 | CC-105, CC-106 | contradiction hidden by synthesis; lazy merge into a false consensus | keep both claims separate, record the contradiction, merge neither, hold both unresolved pending a consumer decision | §14, §4 (both rows), this matrix |
| STM-2 | Three-way near-duplicate retention claim | SRC-101, SRC-102, SRC-104 | CC-104, CC-113, CC-114 | duplicate conviction: one belief counted as three independent evidences | merge into one canonical claim, retain all three provenances, do not inflate confidence | §7, §11 |
| STM-3 | Plausible-sounding but out-of-scope proposal (token buyback) | SRC-102 | CC-107 | scope creep; or unsupported exclusion (dropping it with no recorded reason) | exclude-with-reason, reason recorded, claim still visible in inventory | §9, §4 |
| STM-4 | Tempting silent discard (cosmetic dashboard color) | SRC-104 | CC-109 | silent disappearance of a real candidate claim | admit to inventory, then disposition judged-non-load-bearing (recorded, not dropped) | §4, §13 (grouped out of narrative, still inventoried) |
| STM-5 | Ambiguous open question (referral reward denomination) | SRC-103 | CC-112 | false certainty: forcing a carry/exclude the corpus does not support | hold unresolved, keep visible, do not invent a resolution | §14 |
| STM-6 | Architecture-dependent choice (single vs multi token) | SRC-103 | CC-111 | projection leakage: projecting a deferred choice into a product/token spec | defer, keep visible, generate no projection | §8, §15 |
| STM-7 | Do-not-use harm claim (publish member wallet holdings) | SRC-104 | CC-110 | projection leakage / real privacy harm; or silent disappearance | exclude-with-reason AND list in do-not-use negative boundaries; refuse, do not vanish | §9, §12 |

Coverage check: all seven required adversarial cases (contradiction, three-way
merge, plausible-but-excluded, near-miss silent discard, ambiguous unresolved,
deferred, do-not-use) appear as STM-1 … STM-7. Every named risk
(silent disappearance, lazy merge, false certainty, unsupported exclusion,
projection leakage, duplicate conviction, contradiction hidden by synthesis) is
represented in the "risk if handled badly" column.

## 13. Cluster synthesis

Normalized, deduplicated synthesis of the load-bearing picture (**presentation
compression only** — every underlying claim still has its own inventory entry in
§4; grouping here never replaces the inventory):

- **Access model (carried):** Freeside's core is token-gated membership
  (CC-101), refined into tiered holder levels (CC-102).
- **Why it matters (carried + merged):** gating is associated with improved
  retention (CC-104, a three-way merge) and gated perks are the referral/growth
  loop (CC-103).
- **Open / contested (unresolved):** whether a free open tier should also exist
  is a live contradiction (CC-105 vs CC-106), and referral-reward denomination
  (CC-112) is unsettled — none are resolved by this corpus.
- **Open architecture (deferred):** token structure single-vs-multi (CC-111).
- **Context only (backgrounded):** the category is common in the market
  (CC-108).
- **Refused (do-not-use / excluded):** treasury price-support (CC-107) and
  publishing member wallet holdings (CC-110) are out of scope / harmful and do
  not enter the synthesis.

Non-load-bearing material (e.g. CC-109 dashboard color) is grouped out of the
synthesis narrative but remains individually recorded in §4 with its
disposition. Grouping compressed presentation, not inventory.

## 14. Unresolved claims / questions

- **CC-105 ↔ CC-106 (contradiction).** The corpus contains both "a free open
  tier maximises sign-ups" (CC-105, SRC-102) and "membership must be strictly
  gated, no free tier" (CC-106, SRC-103). These are **incompatible** on the
  free-tier question. They are **not merged** and neither is silently adopted.
  Resolving the contradiction is a consumer / product-strategy decision Aleph
  does not make; both are held visible and unresolved, with the contradiction
  recorded (STM-1).
- **CC-112.** Should referral rewards be paid in the project token or in
  non-token points? Open; needs a decision before build. Kept visible as
  unresolved, not buried as a vague "question" and not forced to a false answer.

## 15. Consumer-deferred projection notes

This is where a consumer (a downstream repo or substrate) *would* project this
Précis into something concrete — and where this fixture deliberately stops:

- A product repo *could* project CC-101/CC-102 into a PRD for tiered gating.
- A growth surface *could* project CC-103 into a referral-program spec.
- A consumer that *resolved* the CC-105/CC-106 contradiction *could* project a
  funnel strategy — but that resolution is not Aleph's to make.

**None of these projections are generated here.** The Précis is
projection-neutral; the renderings belong to the consuming repo, not to Aleph.

## 16. Verification summary

- Source inventory present (§2): 4 sources.
- Extraction criteria recorded (§3), including the no-merge-on-contradiction rule.
- Candidate-claim inventory present (§4): 14 claims, each with one disposition.
- All seven dispositions represented (§5).
- Three-way duplicate merged with all provenance retained (§7, §11).
- Excluded claims carry reasons (§9); do-not-use boundaries recorded (§12).
- Deferred and unresolved claims remain visible (§8, §14).
- Stress-test matrix instantiated (between §12 and §13): seven adversarial cases,
  all named risks represented.
- No downstream projection generated (§15).
- Output is a single portable, projection-neutral file (this document).

See `README.md` for the case-by-case and disposition self-check tables.

## 17. Known incompleteness / limits

- **Bounded corpus:** only four synthetic fragments. "Complete" here means
  *every candidate claim extracted from this declared scope has a recorded
  disposition* — it does **not** mean omniscient or total semantic capture.
- **Synthetic:** no real research; conclusions are illustrative of the artifact
  shape under adversarial pressure, not findings about Freeside.
- **No schema freeze:** field structure is provisional. The stress-test matrix is
  demonstrated at fixture level and is **not** added to the accepted provisional
  v0 envelope by this slice (see scope note at top).
- **No live machinery:** the Précis was authored by hand for this fixture; no
  extractor / parser / matrix-generator code exists or is implied.
