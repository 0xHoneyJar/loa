# Evidence-Role Ledger — RUN-slice-2

## Claim-source edges

| claim_id | source_id | role | verification | removal_effect | note | status |
|----------|-----------|------|--------------|----------------|------|--------|
| CC-101 | SRC-101 | load-bearing | unverifiable | survives-independent-support | Direct access-primitive statement; SRC-103 independently states the gate requirement. | active |
| CC-101 | SRC-103 | corroborative | unverifiable | | Independently states that the gate is the product while differing on the free-tier question. | active |
| CC-102 | SRC-101 | load-bearing | unverifiable | downgrades-to-unresolved | Only source for the three-level holder model. | active |
| CC-103 | SRC-101 | load-bearing | unverifiable | downgrades-to-unresolved | Only source for the gated-perks referral loop. | active |
| CC-104 | SRC-101 | corroborative | unverifiable | | First of three source fragments associating gating and retention. | active |
| CC-104 | SRC-102 | corroborative | unverifiable | | Second source fragment restates the retention association. | active |
| CC-104 | SRC-104 | load-bearing | unverifiable | confidence-decreases | Most specific longitudinal observation; removal leaves weaker independent statements. | active |
| CC-105 | SRC-102 | load-bearing | unverifiable | downgrades-to-unresolved | Direct source for the free-tier growth position. | active |
| CC-105 | SRC-103 | contradictory | unverifiable | | Strict-gate statement directly conflicts with the free-tier position. | active |
| CC-106 | SRC-103 | load-bearing | unverifiable | downgrades-to-unresolved | Direct source for the strict no-free-tier position. | active |
| CC-106 | SRC-102 | contradictory | unverifiable | | Free-tier statement directly conflicts with the strict-gate position. | active |
| CC-107 | SRC-102 | contextual | unverifiable | | Records the proposal so its scope exclusion remains inspectable. | active |
| CC-108 | SRC-102 | unresolved-source | unverifiable | | Single conversational prevalence assertion with no supplied market referent. | active |
| CC-109 | SRC-104 | decorative | unverifiable | | Supports a cosmetic preference that bears no load in the synthesis. | active |
| CC-110 | SRC-104 | contextual | unverifiable | | Records the harmful proposal so the negative boundary remains inspectable. | active |
| CC-111 | SRC-103 | contextual | unverifiable | | Records an architecture-dependent choice without resolving it. | active |
| CC-112 | SRC-103 | contextual | unverifiable | | Records two referral-reward alternatives without choosing between them. | active |
| CC-113 | SRC-102 | load-bearing | unverifiable | downgrades-to-unresolved | Sole provenance for this absorbed retention restatement. | active |
| CC-114 | SRC-104 | load-bearing | unverifiable | downgrades-to-unresolved | Sole provenance for this absorbed retention restatement. | active |

## Synthesis/inference markers

| claim_id | inference basis (claim/packet ids) | uncertainty note |
|----------|-------------------------------------|------------------|

No carried or merged claim relies solely on synthesis or inference.

## Coverage accounting

- carried+merged claims: 6
- with ≥1 load-bearing or corroborative edge: 6
- explicitly marked synthesis/inference: 0
- NEITHER (must be 0 to pass): 0

All verification statuses are `unverifiable` because the fixture sources are
synthetic. That status records source character; it does not turn the run into
an external-truth claim.
