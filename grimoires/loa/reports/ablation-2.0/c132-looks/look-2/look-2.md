# cycle-132 reads — mode `look`

Inputs: rows sha256 `7160b3543c4cdae2071e0bf9bf538dff703003a6440acc8c7eb257c64b03d053`; grades sha256 `6064906c57cbb5fec16a1b661eb78d1a71396aece17f21016a0a378994e43504`; INPUTS.json sha256 `9bdc25d991d3a464114069bca124405617e14b05c9dc2bd6ad0fa4be3592e89f`; registration `13cbd850f82513e8788322e9ea60ac28bba044a14c83b42e11e311611a19401c`; seed 20261021; interval t; validity rules c132.

Rows by registration: 13cbd850f825: 32, 614bcea50b1f: 68.

Registration chain (current first): `13cbd850f825` → `ae0b1da61447` → `614bcea50b1f` → `a31e59421545` → `6205eaf5f1f0` → `6ad2e34e503a` → `f2c0e8f99083` → `573041811eae` → `857669e7c80e` → `277a6effd863` → `7d5200119966`.

## Looks

| look | PRs | defects | Δ | SE | t | z_yes | b_yes | z_no | b_no | CP yes | CP no | RCI | decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 78 | 0.2041 | 0.1022 | 0.0783 | 1.9966 | 1000.0000 | -1.0182 | 1000.0000 | 1.0000 | 0.0000 | [-102.0125, 102.4206] | CONTINUE (minimum information not reached (5 valid PRs < 6 or 78 labelled defects < 30)) |
| 2 | 8 | 108 | 0.1053 | 0.0960 | 0.0887 | 1.0963 | 158.5408 | -0.0548 | 158.5408 | 0.9643 | 0.0124 | [-15.1170, 15.3275] | CONTINUE |

Decision table (ordered, exhaustive; round 3). The YES boundary is two-sided: "z_yes crosses" means |z_yes| ≥ b_yes. 1. z_yes crosses and Δ̂ < 0 → NEGATIVE. 2. z_yes crosses and Δ̂ > 0 and z_no < b_no and RCI upper ≥ MDE → YES. 3. z_yes crosses and Δ̂ ≥ 0 and (z_no ≥ b_no or RCI upper < MDE) → SMALL. 4. z_yes does not cross and z_no ≥ b_no → NO. 5. neither crossed, final look → INCONCLUSIVE. 6. neither crossed, interim look: both conditional powers < 0.20 → FUTILE (non-binding), else CONTINUE.

Boundary constant 1.0000; MDE 0.1000; planned final SE 0.0286.

## Co-reads (§5, reported at every look)

Descriptive: they qualify the primary and never enter the decision.

| (a) pipeline-independent a1_full − a0_bare_matched | Δ 0.3667 | 95 % [0.0305, 0.7028] | 90 % [0.1032, 0.6302] | SE 0.1308 | PRs 6, pairs 9, defects 30 | diag 95 % percentile [0.0769, 0.5833] |
| (c) cost-matched (exact-dollar trim, pairs within ±25 %) | Δ 0.0938 | 95 % [-0.0641, 0.2516] | 90 % [-0.0229, 0.2104] | SE 0.0496 | PRs 4, pairs 4, defects 64 | diag 95 % percentile [0.0000, 0.1277] |

(b) Recall per arm by stratum (valid pairs):

| stratum | a1_full caught / defects | recall | a0_bare_matched caught / defects | recall |
|---|---|---|---|---|
| label_source = fix-commit | 89 / 149 | 0.5973 | 76 / 149 | 0.5101 |
| label_source = fix-commit+incident | 3 / 3 | 1.0000 | 0 / 3 | 0.0000 |
| review_driven = false | 20 / 29 | 0.6897 | 10 / 29 | 0.3448 |
| review_driven = true | 72 / 123 | 0.5854 | 66 / 123 | 0.5366 |

(c) Dollar matching: 4 of 13 pairs within ±25 % of the full cell's cost (pairs outside stay in the primary); trimmed pairs without per-session data 0.

| PR | trial | cost full | cost matched | ratio | within |
|---|---|---|---|---|---|
| review-r15 | 1 | 15.7941 | 16.7622 | 1.0613 | yes |
| review-r16 | 1 | 19.8120 | 21.8986 | 1.1053 | yes |
| review-r19 | 1 | 19.9983 | 32.3929 | 1.6198 | no |
| review-r19 | 2 | 19.7025 | 47.6722 | 2.4196 | no |
| review-r23 | 1 | 24.2681 | 13.8150 | 0.5693 | no |
| review-r23 | 2 | 19.2728 | 13.4275 | 0.6967 | no |
| review-r25 | 1 | 14.9955 | 16.2485 | 1.0836 | yes |
| review-r25 | 2 | 12.6170 | 17.0016 | 1.3475 | no |
| review-r26 | 1 | 13.1307 | 16.8035 | 1.2797 | no |
| review-r26 | 2 | 15.0276 | 16.4182 | 1.0925 | yes |
| review-r27 | 2 | 18.3201 | 25.5508 | 1.3947 | no |
| review-r28 | 1 | 12.2064 | 16.9947 | 1.3923 | no |
| review-r28 | 2 | 11.4826 | 15.3613 | 1.3378 | no |

