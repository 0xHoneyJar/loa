# Stress-Test Matrix — RUN-slice-2

## Stress-test matrix

| stm_id | adversarial pressure | source refs | candidate claim IDs | risk if handled badly | correct handling | resolved at |
|--------|----------------------|-------------|---------------------|-----------------------|------------------|-------------|
| STM-1 | Direct contradiction between a free open tier and a strict no-free-tier gate. | SRC-102, SRC-103 | CC-105, CC-106 | contradiction hidden by synthesis or lazily merged | keep both claims separate and unresolved | ledgers/claim-inventory.md; ledgers/unresolved-queue.md |
| STM-2 | Three near-duplicate retention assertions. | SRC-101, SRC-102, SRC-104 | CC-104, CC-113, CC-114 | duplicate conviction counted as independent proof | retain one canonical claim and every provenance edge without inflating certainty | ledgers/merge-map.md; ledgers/evidence-roles.md |
| STM-3 | Plausible token-price proposal outside access-model scope. | SRC-102 | CC-107 | scope creep or unsupported silent exclusion | exclude with a recorded scope reason and retain the inventory row | ledgers/claim-inventory.md; ledgers/negative-boundaries.md |
| STM-4 | Cosmetic dashboard preference that compression could silently drop. | SRC-104 | CC-109 | silent disappearance of admitted material | record a judged-non-load-bearing disposition and keep it in inventory | ledgers/claim-inventory.md; synthesis/cluster-synthesis.md |
| STM-5 | Referral-reward alternatives with no selection criterion. | SRC-103 | CC-112 | false certainty | preserve the alternatives as unresolved | ledgers/unresolved-queue.md |
| STM-6 | Token-architecture choice that depends on a later decision. | SRC-103 | CC-111 | projection leakage into an unsupported design commitment | defer and expose the required decision | ledgers/unresolved-queue.md; precis.md §15 |
| STM-7 | Proposal to publish identifiable wallet holdings. | SRC-104 | CC-110 | privacy harm, projection leakage, or silent deletion | exclude with reason and bind later use with a harm boundary | ledgers/negative-boundaries.md |

## Evidence-removal rows

| stm_id | claim_id | removed source | declared effect | attack outcome | consequence |
|--------|----------|----------------|-----------------|----------------|-------------|
| STM-8 | CC-101 | SRC-101 | survives-independent-support | effect-held | SRC-103 still supports the existence of the gate; free-tier stance remains unresolved. |
| STM-9 | CC-102 | SRC-101 | downgrades-to-unresolved | effect-held | No independent tier-model support remains under the hypothetical removal. |
| STM-10 | CC-105 | SRC-102 | downgrades-to-unresolved | effect-held | The free-tier position has no remaining direct support. |
| STM-11 | CC-106 | SRC-103 | downgrades-to-unresolved | effect-held | The strict-gate position has no remaining direct support. |
| STM-12 | CC-103 | SRC-101 | downgrades-to-unresolved | effect-held | The referral-loop claim has no remaining direct support. |
| STM-13 | CC-104 | SRC-104 | confidence-decreases | effect-held | SRC-101 and SRC-102 retain weaker association statements; REF-03 records that external generalization remains unresolved. |
| STM-14 | CC-113 | SRC-102 | downgrades-to-unresolved | effect-held | This absorbed restatement has no other direct provenance. |
| STM-15 | CC-114 | SRC-104 | downgrades-to-unresolved | effect-held | This absorbed restatement has no other direct provenance. |

Every load-bearing edge in RC-01 and RC-02 has one evidence-removal row. No
attack contradicted its declared effect, so no superseding evidence-role row was
required.
