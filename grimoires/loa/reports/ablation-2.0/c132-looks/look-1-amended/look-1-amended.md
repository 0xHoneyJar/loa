# cycle-132 reads — mode `look`

Inputs: rows sha256 `6fdb2ee91876380f1e5caf38dbdb986be985dacb69424472720e45790309fa32`; grades sha256 `544ca47719369965ae3367794c0d8b84c0076f456a2be0ab8f502c7c74f294e8`; INPUTS.json sha256 `6954dbaf533cc6ed2d58ae9d5e59af3ec0ef95ee243a79151537134aa66012e0`; registration `13cbd850f82513e8788322e9ea60ac28bba044a14c83b42e11e311611a19401c`; seed 20261021; interval t; validity rules c132.

Rows by registration: 614bcea50b1f: 60.

Registration chain (current first): `13cbd850f825` → `ae0b1da61447` → `614bcea50b1f` → `a31e59421545` → `6205eaf5f1f0` → `6ad2e34e503a` → `f2c0e8f99083` → `573041811eae` → `857669e7c80e` → `277a6effd863` → `7d5200119966`.

## Looks

| look | PRs | defects | Δ | SE | t | z_yes | b_yes | z_no | b_no | CP yes | CP no | RCI | decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 78 | 0.2041 | 0.1022 | 0.0783 | 1.9966 | 1000.0000 | -1.0182 | 1000.0000 | 1.0000 | 0.0000 | [-102.0125, 102.4206] | CONTINUE (minimum information not reached (5 valid PRs < 6 or 78 labelled defects < 30)) |

Decision table (ordered, exhaustive; round 3). The YES boundary is two-sided: "z_yes crosses" means |z_yes| ≥ b_yes. 1. z_yes crosses and Δ̂ < 0 → NEGATIVE. 2. z_yes crosses and Δ̂ > 0 and z_no < b_no and RCI upper ≥ MDE → YES. 3. z_yes crosses and Δ̂ ≥ 0 and (z_no ≥ b_no or RCI upper < MDE) → SMALL. 4. z_yes does not cross and z_no ≥ b_no → NO. 5. neither crossed, final look → INCONCLUSIVE. 6. neither crossed, interim look: both conditional powers < 0.20 → FUTILE (non-binding), else CONTINUE.

Boundary constant 1.0000; MDE 0.1000; planned final SE 0.0286.

## Co-reads (§5, reported at every look)

Descriptive: they qualify the primary and never enter the decision.

| (a) pipeline-independent a1_full − a0_bare_matched | Δ 0.4500 | 95 % [-0.3056, 1.2056] | 90 % [-0.0628, 0.9628] | SE 0.1756 | PRs 3, pairs 4, defects 20 | diag 95 % percentile [0.0000, 0.7500] |
| (c) cost-matched (exact-dollar trim, pairs within ±25 %) | Δ 0.1224 | 95 % [-0.5716, 0.8165] | 90 % [-0.2224, 0.4673] | SE 0.0546 | PRs 2, pairs 2, defects 49 | diag 95 % percentile [0.0000, 0.1333] |

(b) Recall per arm by stratum (valid pairs):

| stratum | a1_full caught / defects | recall | a0_bare_matched caught / defects | recall |
|---|---|---|---|---|
| label_source = fix-commit | 65 / 95 | 0.6842 | 48 / 95 | 0.5053 |
| label_source = fix-commit+incident | 3 / 3 | 1.0000 | 0 / 3 | 0.0000 |
| review_driven = false | 12 / 19 | 0.6316 | 4 / 19 | 0.2105 |
| review_driven = true | 56 / 79 | 0.7089 | 44 / 79 | 0.5570 |

(c) Dollar matching: 2 of 8 pairs within ±25 % of the full cell's cost (pairs outside stay in the primary); trimmed pairs without per-session data 0.

| PR | trial | cost full | cost matched | ratio | within |
|---|---|---|---|---|---|
| review-r15 | 1 | 15.7941 | 16.7622 | 1.0613 | yes |
| review-r23 | 1 | 24.2681 | 13.8150 | 0.5693 | no |
| review-r23 | 2 | 19.2728 | 13.4275 | 0.6967 | no |
| review-r25 | 1 | 14.9955 | 16.2485 | 1.0836 | yes |
| review-r25 | 2 | 12.6170 | 17.0016 | 1.3475 | no |
| review-r27 | 2 | 18.3201 | 25.5508 | 1.3947 | no |
| review-r28 | 1 | 12.2064 | 16.9947 | 1.3923 | no |
| review-r28 | 2 | 11.4826 | 15.3613 | 1.3378 | no |

