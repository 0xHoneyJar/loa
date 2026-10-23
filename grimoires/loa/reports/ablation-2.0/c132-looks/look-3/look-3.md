# cycle-132 reads — mode `look`

Inputs: rows sha256 `522e1980a1cca46bd3132c83abba8512b7b847acb951d8d98e9e7f7b3f7e41ad`; grades sha256 `57eea383b6c1a4bef8b13e4b80bdcc00b4912e6ef0c3df47d61af6b9e5e69c1c`; INPUTS.json sha256 `17725093540e47b7c14f362a14536c84eec523b41df4b497af11c9170e7abb62`; registration `2f6909d23efcadc0c65e34c5f49811e80b4b4c927c2a37eaed49f4fe040d521b`; seed 20261021; interval t; validity rules c132.

Rows by registration: 13cbd850f825: 72, 614bcea50b1f: 68.

Registration chain (current first): `2f6909d23efc` → `13cbd850f825` → `ae0b1da61447` → `614bcea50b1f` → `a31e59421545` → `6205eaf5f1f0` → `6ad2e34e503a` → `f2c0e8f99083` → `573041811eae` → `857669e7c80e` → `277a6effd863` → `7d5200119966`.

## Looks

| look | PRs | defects | Δ | SE | t | z_yes | b_yes | z_no | b_no | CP yes | CP no | RCI | decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 78 | 0.2041 | 0.1022 | 0.0783 | 1.9966 | 1000.0000 | -1.0182 | 1000.0000 | 1.0000 | 0.0000 | [-102.0125, 102.4206] | CONTINUE (minimum information not reached (5 valid PRs < 6 or 78 labelled defects < 30)) |
| 2 | 8 | 108 | 0.1053 | 0.0960 | 0.0887 | 1.0963 | 158.5408 | -0.0548 | 158.5408 | 0.9643 | 0.0124 | [-15.1170, 15.3275] | CONTINUE |
| 3 | 10 | 122 | 0.0971 | 0.0843 | 1.0000 | 1.1518 | 2.2622 | 0.0339 | 2.2622 | 0.0000 | 0.0000 | [-0.0936, 0.2879] | INCONCLUSIVE |

Decision table (ordered, exhaustive; round 3). The YES boundary is two-sided: "z_yes crosses" means |z_yes| ≥ b_yes. 1. z_yes crosses and Δ̂ < 0 → NEGATIVE. 2. z_yes crosses and Δ̂ > 0 and z_no < b_no and RCI upper ≥ MDE → YES. 3. z_yes crosses and Δ̂ ≥ 0 and (z_no ≥ b_no or RCI upper < MDE) → SMALL. 4. z_yes does not cross and z_no ≥ b_no → NO. 5. neither crossed, final look → INCONCLUSIVE. 6. neither crossed, interim look: both conditional powers < 0.20 → FUTILE (non-binding), else CONTINUE.

Boundary constant 1.0000; MDE 0.1000; planned final SE 0.0286.

## Co-reads (§5, reported at every look)

Descriptive: they qualify the primary and never enter the decision.

| (a) pipeline-independent a1_full − a0_bare_matched | Δ 0.2941 | 95 % [-0.0437, 0.6320] | 90 % [0.0258, 0.5624] | SE 0.1381 | PRs 7, pairs 11, defects 34 | diag 95 % percentile [0.0000, 0.5333] |
| (c) cost-matched (exact-dollar trim, pairs within ±25 %) | Δ 0.0805 | 95 % [-0.0505, 0.2114] | 90 % [-0.0222, 0.1831] | SE 0.0510 | PRs 6, pairs 7, defects 87 | diag 95 % percentile [-0.0328, 0.1622] |

(b) Recall per arm by stratum (valid pairs):

| stratum | a1_full caught / defects | recall | a0_bare_matched caught / defects | recall |
|---|---|---|---|---|
| label_source = fix-commit | 109 / 170 | 0.6412 | 95 / 170 | 0.5588 |
| label_source = fix-commit+incident | 3 / 3 | 1.0000 | 0 / 3 | 0.0000 |
| label_source = incident | 2 / 2 | 1.0000 | 2 / 2 | 1.0000 |
| review_driven = false | 23 / 33 | 0.6970 | 14 / 33 | 0.4242 |
| review_driven = true | 91 / 142 | 0.6408 | 83 / 142 | 0.5845 |

(c) Dollar matching: 7 of 16 pairs within ±25 % of the full cell's cost (pairs outside stay in the primary); trimmed pairs without per-session data 0.

| PR | trial | cost full | cost matched | ratio | within |
|---|---|---|---|---|---|
| review-r11 | 1 | 17.6831 | 19.2849 | 1.0906 | yes |
| review-r15 | 1 | 15.7941 | 16.7622 | 1.0613 | yes |
| review-r16 | 1 | 19.8120 | 21.8986 | 1.1053 | yes |
| review-r19 | 1 | 19.9983 | 32.3929 | 1.6198 | no |
| review-r19 | 2 | 19.7025 | 47.6722 | 2.4196 | no |
| review-r23 | 1 | 24.2681 | 13.8150 | 0.5693 | no |
| review-r23 | 2 | 19.2728 | 13.4275 | 0.6967 | no |
| review-r24 | 1 | 21.8296 | 21.7416 | 0.9960 | yes |
| review-r24 | 2 | 20.7753 | 18.7008 | 0.9001 | yes |
| review-r25 | 1 | 14.9955 | 16.2485 | 1.0836 | yes |
| review-r25 | 2 | 12.6170 | 17.0016 | 1.3475 | no |
| review-r26 | 1 | 13.1307 | 16.8035 | 1.2797 | no |
| review-r26 | 2 | 15.0276 | 16.4182 | 1.0925 | yes |
| review-r27 | 2 | 18.3201 | 25.5508 | 1.3947 | no |
| review-r28 | 1 | 12.2064 | 16.9947 | 1.3923 | no |
| review-r28 | 2 | 11.4826 | 15.3613 | 1.3378 | no |

