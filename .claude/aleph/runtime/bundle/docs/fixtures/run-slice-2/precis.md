# v0 Research Précis — RUN-slice-2 Golden Run Fixture

> **Synthetic manual-run fixture.** Distilled from four frozen source fragments,
> SRC-101 through SRC-104. This file demonstrates the accepted Précis envelope
> inside a complete run directory. It is projection-neutral and generates no
> downstream document.
>
> Markdown tables remain provisional implementation shapes. No schema is frozen.

## 1. Corpus scope

A bounded synthetic corpus of four source fragments about a token-gated
membership product. Candidate claims include the access primitive, tiering,
retention, referrals, open implementation choices, conflicting free-tier
positions, and proposals that require an explicit non-load-bearing or negative
disposition. The declared scope is the token-gated access model and its immediate
community and growth mechanics. Token-price operations, real market conclusions,
and downstream document generation are outside scope.

## 2. Source inventory

| source_id | kind | locus |
|-----------|------|-------|
| SRC-101 | deep-research-output | corpus/sources/SRC-101-access-model.md |
| SRC-102 | conversation-export | corpus/sources/SRC-102-growth-thread.md |
| SRC-103 | design-note | corpus/sources/SRC-103-gating-rules.md |
| SRC-104 | design-note | corpus/sources/SRC-104-dashboard-profiles.md |

All four sources are synthetic and frozen by the corpus manifest. They do not
establish facts outside this bounded fixture.

## 3. Extraction method / inclusion criteria

- A candidate claim is a declarative assertion about the token-gated access
  model or its immediate community and growth mechanics that could plausibly
  bear on a downstream decision.
- Access, retention, growth, implementation-choice, scope, and harm-bearing
  assertions are admitted. Apparent irrelevance, conflict, deferral, or harm is
  handled by disposition rather than pre-extraction deletion.
- Speaker labels, conversational fillers, formatting, container headings, and
  non-assertive tool noise remain outside candidacy under recorded classes.
- Each claim-bearing paragraph becomes one packet unless independent claims
  require distinct re-entry coordinates. Every source was walked completely.
- Claims are restated once in neutral language. Near-duplicates remain separate
  until the global merge pass; incompatible claims remain separate.

## 4. Candidate-claim inventory / packet index

| claim_id | normalized claim | source(s) | disposition |
|----------|------------------|-----------|-------------|
| CC-101 | Token-gated membership, where threshold holding unlocks gated channels, is the core access primitive. | SRC-101, SRC-103 | carried |
| CC-102 | Membership should support holder, contributor, and core levels rather than an all-or-nothing gate. | SRC-101 | carried |
| CC-103 | Gated perks drive referrals as an intended growth loop. | SRC-101 | carried |
| CC-104 | Token gating is associated with improved member retention and engagement. | SRC-101, SRC-102, SRC-104 | merged |
| CC-105 | A free open membership tier maximizes sign-ups and top-of-funnel growth. | SRC-102 | unresolved |
| CC-106 | Membership must be strictly token-gated with no free tier because a free side door collapses the access model. | SRC-103 | unresolved |
| CC-107 | A token buyback and treasury program should support token price and perceived membership value. | SRC-102 | excluded-with-reason |
| CC-108 | Token-gated communities are common across the market. | SRC-102 | backgrounded |
| CC-109 | The member dashboard should default to dark mode with a teal accent. | SRC-104 | judged-non-load-bearing |
| CC-110 | Well-known members' wallet holdings should appear on public profiles to boost status. | SRC-104 | excluded-with-reason |
| CC-111 | The gating design may use one fungible token or a different token per holder tier. | SRC-103 | deferred |
| CC-112 | Referral rewards may use the project token or non-token points. | SRC-103 | unresolved |
| CC-113 | Gating keeps members engaged and active longer. | SRC-102 | merged |
| CC-114 | Retention is consistently higher in gated periods than in open periods. | SRC-104 | merged |

Inventory is complete against the recorded extraction criteria: fourteen active
candidate claims and fourteen dispositions.

## 5. Classification / disposition ledger summary

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

## 6. Carried claims

- **CC-101:** Token-gated membership is the core access primitive. SRC-101 and
  SRC-103 support the existence of the gate without settling the free-tier
  contradiction.
- **CC-102:** Holder, contributor, and core levels provide the stated membership
  shape.
- **CC-103:** Gated perks provide the stated referral loop.

## 7. Merged claims

- **CC-104** is the canonical retention association and absorbs **CC-113** and
  **CC-114**. The merge retains SRC-101, SRC-102, and SRC-104. Repetition across
  those fragments is not counted as three independent proofs, and the language
  remains associative rather than causal.

## 8. Deferred claims

- **CC-111:** One fungible token versus separate per-tier tokens depends on a
  later architecture decision. It remains visible and generates no token-design
  commitment here.

## 9. Excluded-with-reason claims

- **CC-107:** Excluded because token-price and treasury operations are outside
  the declared access-model scope. REF-02 records the fixture-simulated authority
  ruling that no scoped financial mandate was supplied.
- **CC-110:** Excluded because publishing identifiable wallet holdings creates
  privacy and doxxing harm and is outside the access-model scope.

## 10. Backgrounded claims

- **CC-108:** The market-prevalence assertion remains background only. The
  bounded corpus supplies no external support for it, so it cannot bear on an
  access-model decision.

## 11. Duplicate / merge map

| canonical | absorbs | basis | provenance retained |
|-----------|---------|-------|---------------------|
| CC-104 | CC-113, CC-114 | same underlying retention association stated in three source fragments | SRC-101, SRC-102, SRC-104 |

CC-105 and CC-106 do not appear in the merge map because they are incompatible.

## 12. Do-not-use / negative boundaries

- **NB-1:** CC-107 and its token-price or treasury proposal must not enter the
  access-model synthesis.
- **NB-2:** CC-110 must not be displayed or used as a design lever because it
  exposes identifiable financial holdings.
- **NB-3:** CC-108 must not support a product-specific design choice because the
  corpus supplies no market referent.
- **NB-4:** Missing external facts must remain unresolved rather than being
  invented from category language.

## Stress-test matrix

| stm_id | adversarial pressure | source refs | candidate claim IDs | risk if handled badly | correct handling | resolved at |
|--------|----------------------|-------------|---------------------|-----------------------|------------------|-------------|
| STM-1 | Direct contradiction between a free open tier and a strict no-free-tier gate. | SRC-102, SRC-103 | CC-105, CC-106 | contradiction hidden by synthesis or lazily merged | keep both claims separate and unresolved | §14 |
| STM-2 | Three near-duplicate retention assertions. | SRC-101, SRC-102, SRC-104 | CC-104, CC-113, CC-114 | duplicate conviction counted as independent proof | retain one canonical claim and every provenance edge without inflating certainty | §7, §11 |
| STM-3 | Plausible token-price proposal outside access-model scope. | SRC-102 | CC-107 | scope creep or unsupported silent exclusion | exclude with a recorded scope reason and retain the inventory row | §9, §12 |
| STM-4 | Cosmetic dashboard preference that compression could silently drop. | SRC-104 | CC-109 | silent disappearance of admitted material | record a judged-non-load-bearing disposition and keep it in inventory | §4, §13 |
| STM-5 | Referral-reward alternatives with no selection criterion. | SRC-103 | CC-112 | false certainty | preserve the alternatives as unresolved | §14 |
| STM-6 | Token-architecture choice that depends on a later decision. | SRC-103 | CC-111 | projection leakage into an unsupported design commitment | defer and expose the required decision | §8, §15 |
| STM-7 | Proposal to publish identifiable wallet holdings. | SRC-104 | CC-110 | privacy harm, projection leakage, or silent deletion | exclude with reason and bind later use with a harm boundary | §9, §12 |

## 13. Cluster synthesis

- **Access gate and membership shape (RC-01):** CC-101 and CC-102 form the
  carried access spine. CC-105 and CC-106 remain an explicit free-tier
  contradiction, and CC-111 remains deferred.
- **Retention and referral mechanics (RC-02):** CC-104 retains the provenance of
  CC-113 and CC-114 without multiplying certainty; CC-103 states the referral
  loop; CC-112 remains unresolved. REF-03 records that the bounded synthetic
  retention association cannot establish external generalization.
- **Refused and non-load-bearing proposals (RC-03):** CC-107 and CC-110 stay
  excluded under NB-1 and NB-2. CC-109 remains inventoried but outside the
  load-bearing narrative.
- **Unsupported category context (RC-04):** CC-108 remains background only while
  REF-01 remains unresolved.

Grouping compresses presentation only. Every claim retains its inventory row.

## 14. Unresolved claims / questions

- **CC-105 and CC-106:** The corpus contains incompatible free-tier and
  strict-gate positions. Neither is merged or silently selected.
- **CC-112:** Referral rewards may use the project token or non-token points;
  the corpus supplies no decision criterion.

## 15. Consumer-deferred projection notes

A commissioned consumer could use CC-101 and CC-102 in an access-requirements
document, CC-103 in referral design, or CC-104 in a retention rationale bounded
to this corpus. It would have to preserve CC-105, CC-106, CC-111, and CC-112 as
open items, honor NB-1 through NB-4, and carry the REF-03 taint wherever CC-104
is load-bearing.

No projection is generated here. A projection requires an accepted run and a
separate authority commission.

## 16. Verification summary

- Four frozen sources and fourteen packet locators were checked against SHA-256
  content and span hashes.
- Fourteen claims have non-empty packet provenance and exactly one disposition;
  all seven disposition classes are represented.
- The CC-104 merge retains the source union of CC-113 and CC-114.
- Nineteen evidence-role edges cover all six carried or merged claims; eight
  load-bearing edges in adversarial clusters have removal attacks.
- Four route cards contain packet IDs, closed-set postures, complete shape
  vectors, and acyclic dependencies.
- REF-01 and REF-03 remain unresolved. REF-02 resolves only through the manifest
  authority sign-off and does not add an external fact.
- VER-0001 through VER-0011 are fixture-simulated portable verdict records. The
  sampling record names each checked population.
- The kernel report records the exact structural-check command and its fixture
  status. This fixture does not turn simulated T2 or T3 records into capability
  evidence.

## 17. Known incompleteness / limits

- **Bounded and synthetic:** completeness means every claim admitted under the
  recorded criteria has a disposition. It does not establish external truth.
- **External-referent unresolved:** REF-01 leaves RC-04 market-prevalence context
  tainted. REF-03 leaves RC-02 and any use of CC-104 tainted against claims of
  external generalization.
- **Supplied authority ruling only:** REF-02 supplies a scope decision, not
  financial or market evidence.
- **Unvalidated arm:** the one-row reconciliation against REF-02 freezes a
  provisional artifact shape. It does not validate convergent-heavy execution.
- **Fixture-simulated governance:** acceptance, authority, audit, and harness
  rows demonstrate required record shapes; they do not substitute for real
  independent review or replay.
- **Manual extraction scale:** fourteen claim-bearing packets honestly represent
  this small corpus. The handoff's rough larger estimate was not treated as a
  quota.
- **No schema freeze:** claim type, reconciliation, and other Markdown shapes
  remain provisional under Decision 0003.
- **No live generation:** no extractor, autonomous research generator, service,
  or downstream rendering is claimed.
