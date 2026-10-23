# cycle-132 reads — mode `final`

Inputs: rows sha256 `522e1980a1cca46bd3132c83abba8512b7b847acb951d8d98e9e7f7b3f7e41ad`; grades sha256 `57eea383b6c1a4bef8b13e4b80bdcc00b4912e6ef0c3df47d61af6b9e5e69c1c`; INPUTS.json sha256 `17725093540e47b7c14f362a14536c84eec523b41df4b497af11c9170e7abb62`; registration `380f7a3656d3c9dfbd93ce73ab8732ec6a777ccf89f8e49e892ed27c5b595090`; seed 20261021; interval t; validity rules c132.

Rows by registration: 13cbd850f825: 72, 614bcea50b1f: 68.

Registration chain (current first): `380f7a3656d3` → `05fa23fe8c69` → `9a0dda4bcedc` → `2f6909d23efc` → `13cbd850f825` → `ae0b1da61447` → `614bcea50b1f` → `a31e59421545` → `6205eaf5f1f0` → `6ad2e34e503a` → `f2c0e8f99083` → `573041811eae` → `857669e7c80e` → `277a6effd863` → `7d5200119966`.

## Looks

| look | PRs | defects | Δ | SE | t | z_yes | b_yes | z_no | b_no | CP yes | CP no | RCI | decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 78 | 0.2041 | 0.1022 | 0.0783 | 1.9966 | 1000.0000 | -1.0182 | 1000.0000 | 1.0000 | 0.0000 | [-102.0125, 102.4206] | CONTINUE (minimum information not reached (5 valid PRs < 6 or 78 labelled defects < 30)) |
| 2 | 8 | 108 | 0.1053 | 0.0960 | 0.0887 | 1.0963 | 158.5408 | -0.0548 | 158.5408 | 0.9643 | 0.0124 | [-15.1170, 15.3275] | CONTINUE |
| 3 | 10 | 122 | 0.0971 | 0.0843 | 1.0000 | 1.1518 | 2.2622 | 0.0339 | 2.2622 | 0.0000 | 0.0000 | [-0.0936, 0.2879] | INCONCLUSIVE |

Decision table (ordered, exhaustive; round 3). The YES boundary is two-sided: "z_yes crosses" means |z_yes| ≥ b_yes. 1. z_yes crosses and Δ̂ < 0 → NEGATIVE. 2. z_yes crosses and Δ̂ > 0 and z_no < b_no and RCI upper ≥ MDE → YES. 3. z_yes crosses and Δ̂ ≥ 0 and (z_no ≥ b_no or RCI upper < MDE) → SMALL. 4. z_yes does not cross and z_no ≥ b_no → NO. 5. neither crossed, final look → INCONCLUSIVE. 6. neither crossed, interim look: both conditional powers < 0.20 → FUTILE (non-binding), else CONTINUE.

Boundary constant 1.0000; MDE 0.1000; planned final SE 0.0286.

## Pre-registered reads

| primary a1_full − a0_bare_matched | Δ 0.0971 | 95 % [-0.0936, 0.2879] | 90 % [-0.0575, 0.2517] | SE 0.0843 | PRs 10, pairs 16, defects 175 | diag 95 % percentile [-0.0682, 0.2647] |
| PR-weighted | Δ 0.0834 | 95 % [-0.0880, 0.2549] | 90 % [-0.0555, 0.2223] | | |

Repeated confidence interval at the stopping look 3: [-0.0936, 0.2879] (b = 2.2622); decision INCONCLUSIVE.

REML LMM: β 0.0614, 95 % [-0.0540, 0.1767], σu 0.1934, σe 0.1664.
PR-level permutation: p 0.3711 (exact, 1024).

Defects per USD: full 0.4117 [0.2677, 0.6292]; matched 0.2939 [0.1942, 0.4532].

| cost per extra defect | value | extra defects | status |
|---|---|---|---|
| matched_all_spend | -5.0124 | 17.0000 | ok |
| matched_valid | -3.1270 | 17.0000 | ok |
| session1_all_spend | — | — | no_session1 |
| session1_valid | — | — | no_session1 |

| contrast | read |
|---|---|
| review_only_vs_full | Δ -0.1185, 95 % [-0.1959, -0.0411], PRs 10 |
| pipeline_independent | Δ 0.2941, 95 % [-0.0437, 0.6320], PRs 7 |
| matched_fable | Δ 0.3333, 95 % [0.2122, 0.4545], PRs 11 |

Positive control (§8 (addendum 10); a1_full_openmount − a1_full, every group, saturated PRs exempt review-r11, review-r24, review-r25): pass; Δ 0.0417, 90 % [-0.0335, 0.1169], expected 0.0670; eligible pairs 11, exposed open runs 9. Pre-addendum-10 label (G1 only): inconclusive.

Dollar matching: 7 of 16 pairs within ±25 % of the full cell's cost.

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

25 % guard: INCONCLUSIVE BY DEGRADATION.

## Missingness

| arm | planned | rowed | valid | not rowed | excluded by reason |
|---|---|---|---|---|---|
| a0_bare_fable_matched | 28 | 28 | 28 | 0 | — |
| a0_bare_matched | 28 | 28 | 25 | 0 | sessions_valid<ceil(k/2) 3 |
| a1_full | 28 | 28 | 17 | 0 | contaminated 5, oracle_exposed 8, refusal_fallbacks 1, status:contaminated 5 |
| a1_review_only | 28 | 28 | 20 | 0 | contaminated 1, oracle_exposed 7, status:contaminated 1 |

| arm / k | cells | sessions planned | valid | excluded |
|---|---|---|---|---|
| a0_bare_fable_matched/k=3 | 20 | 60 | 57 | 3 |
| a0_bare_fable_matched/k=4 | 8 | 32 | 32 | 0 |
| a0_bare_matched/k=10 | 6 | 60 | 46 | 14 |
| a0_bare_matched/k=11 | 4 | 44 | 40 | 4 |
| a0_bare_matched/k=12 | 8 | 96 | 92 | 4 |
| a0_bare_matched/k=13 | 2 | 26 | 25 | 1 |
| a0_bare_matched/k=15 | 2 | 30 | 30 | 0 |
| a0_bare_matched/k=16 | 2 | 32 | 32 | 0 |
| a0_bare_matched/k=18 | 2 | 36 | 36 | 0 |
| a0_bare_matched/k=9 | 2 | 18 | 6 | 12 |

| bound: excluded_sessions_caught_everything | Δ -0.1179 | 95 % [-0.3463, 0.1105] | 90 % [-0.3037, 0.0678] | SE 0.1025 | PRs 11, pairs 17, defects 195 | diag 95 % percentile [-0.3214, 0.0710] |
| bound: excluded_sessions_missed_everything | Δ 0.1026 | 95 % [-0.0639, 0.2690] | 90 % [-0.0328, 0.2380] | SE 0.0747 | PRs 11, pairs 17, defects 195 | diag 95 % percentile [-0.0443, 0.2532] |

## Sensitivities (registered order; decide nothing)

| frozen_c131_labels | status `not_provided` | PRs — |
| v1_labels | status `not_provided` | PRs — |
| judge_corrected | Δ -0.0370 |
| judge_strays_as_defects | Δ 0.0160 | 95 % [-0.0916, 0.1236] | 90 % [-0.0712, 0.1032] | SE 0.0476 | PRs 10, pairs 16, defects 375 | diag 95 % percentile [-0.0771, 0.1066] |
| exact_dollar_trim | Δ 0.1257 | 95 % [-0.0317, 0.2831] | 90 % [-0.0018, 0.2532] | SE 0.0696 | PRs 10, pairs 16, defects 175 | diag 95 % percentile [0.0000, 0.2716] |
| pair_level_permutation | p 0.2173 |
| ci90 | [-0.0575, 0.2517] |
| leave out review-r11 | Δ 0.0882 | 95 % [-0.1118, 0.2882] | 90 % [-0.0730, 0.2495] | SE 0.0867 | PRs 9, pairs 15, defects 170 | diag 95 % percentile [-0.0826, 0.2582] |
| leave out review-r15 | Δ 0.0846 | 95 % [-0.1625, 0.3318] | 90 % [-0.1147, 0.2839] | SE 0.1072 | PRs 9, pairs 15, defects 130 | diag 95 % percentile [-0.1064, 0.2966] |
| leave out review-r16 | Δ 0.1006 | 95 % [-0.1019, 0.3031] | 90 % [-0.0627, 0.2639] | SE 0.0878 | PRs 9, pairs 15, defects 169 | diag 95 % percentile [-0.0709, 0.2741] |
| leave out review-r19 | Δ 0.1586 | 95 % [-0.0137, 0.3310] | 90 % [0.0197, 0.2976] | SE 0.0747 | PRs 9, pairs 14, defects 145 | diag 95 % percentile [0.0133, 0.3088] |
| leave out review-r23 | Δ 0.0268 | 95 % [-0.1156, 0.1693] | 90 % [-0.0880, 0.1417] | SE 0.0618 | PRs 9, pairs 14, defects 149 | diag 95 % percentile [-0.1040, 0.1312] |
| leave out review-r24 | Δ 0.1146 | 95 % [-0.0961, 0.3254] | 90 % [-0.0553, 0.2846] | SE 0.0914 | PRs 9, pairs 14, defects 157 | diag 95 % percentile [-0.0667, 0.2963] |
| leave out review-r25 | Δ 0.0958 | 95 % [-0.1066, 0.2982] | 90 % [-0.0674, 0.2590] | SE 0.0878 | PRs 9, pairs 14, defects 167 | diag 95 % percentile [-0.0784, 0.2692] |
| leave out review-r26 | Δ 0.0955 | 95 % [-0.1207, 0.3118] | 90 % [-0.0788, 0.2699] | SE 0.0938 | PRs 9, pairs 14, defects 157 | diag 95 % percentile [-0.0909, 0.2832] |
| leave out review-r27 | Δ 0.0926 | 95 % [-0.1170, 0.3022] | 90 % [-0.0764, 0.2616] | SE 0.0909 | PRs 9, pairs 15, defects 162 | diag 95 % percentile [-0.0878, 0.2738] |
| leave out review-r28 | Δ 0.1124 | 95 % [-0.0827, 0.3075] | 90 % [-0.0449, 0.2698] | SE 0.0846 | PRs 9, pairs 14, defects 169 | diag 95 % percentile [-0.0481, 0.2847] |
| pr-11 out | Δ 0.0882 | 95 % [-0.1118, 0.2882] | 90 % [-0.0730, 0.2495] | SE 0.0867 | PRs 9, pairs 15, defects 170 | diag 95 % percentile [-0.0826, 0.2582] |
| degraded_contaminated_excluded | Δ 0.0971 | 95 % [-0.0936, 0.2879] | 90 % [-0.0575, 0.2517] | SE 0.0843 | PRs 10, pairs 16, defects 175 | diag 95 % percentile [-0.0682, 0.2647] |
| re-included: oracle-exposed, read form only | Δ 0.1447 | 95 % [-0.0258, 0.3151] | 90 % [0.0060, 0.2833] | SE 0.0765 | PRs 11, pairs 19, defects 235 | diag 95 % percentile [-0.0391, 0.2692] |
| recall per arm (oracle-exposed, read form only) | a1_full 0.6511, a0_bare_matched 0.5064 |
| re-included: oracle-exposed, diff form | Δ 0.1339 | 95 % [-0.0181, 0.2860] | 90 % [0.0099, 0.2580] | SE 0.0691 | PRs 12, pairs 19, defects 224 | diag 95 % percentile [-0.0059, 0.2650] |
| recall per arm (oracle-exposed, diff form) | a1_full 0.6607, a0_bare_matched 0.5268 |
| re-included: oracle-exposed, every form | Δ 0.1655 | 95 % [0.0319, 0.2991] | 90 % [0.0562, 0.2748] | SE 0.0613 | PRs 13, pairs 22, defects 284 | diag 95 % percentile [0.0250, 0.2665] |
| recall per arm (oracle-exposed, every form) | a1_full 0.6585, a0_bare_matched 0.4930 |
| oracle-exposed cells (arm / group / PR: form n) | a1_full / G1 / review-r14: diff 1; a1_full / G1 / review-r15: read 1; a1_full / G2 / review-r21: diff 2; a1_full / G3 / review-r11: read 1; a1_full / G3 / review-r20: read 1; a1_review_only / G1 / review-r15: diff 1, read 1; a1_review_only / G2 / review-r16: diff 1; a1_review_only / G2 / review-r19: diff 1; a1_review_only / G2 / review-r21: read 1; a1_review_only / G3 / review-r20: read 2 |
| re-included: network_egress:nonrepo | Δ 0.0971 | 95 % [-0.0936, 0.2879] | 90 % [-0.0575, 0.2517] | SE 0.0843 | PRs 10, pairs 16, defects 175 | diag 95 % percentile [-0.0682, 0.2647] |
| re-included: outside_path | Δ 0.1042 | 95 % [-0.0672, 0.2755] | 90 % [-0.0352, 0.2436] | SE 0.0769 | PRs 11, pairs 17, defects 192 | diag 95 % percentile [-0.0467, 0.2573] |
| re-included: repo_name | Δ 0.0851 | 95 % [-0.0940, 0.2642] | 90 % [-0.0600, 0.2302] | SE 0.0792 | PRs 10, pairs 17, defects 188 | diag 95 % percentile [-0.0688, 0.2435] |
| re-included: every class | Δ 0.0927 | 95 % [-0.0694, 0.2547] | 90 % [-0.0391, 0.2245] | SE 0.0727 | PRs 11, pairs 18, defects 205 | diag 95 % percentile [-0.0491, 0.2405] |
| recall per arm (network_egress:nonrepo) | a1_full 0.6514, a0_bare_matched 0.5543 |
| recall per arm (outside_path) | a1_full 0.6354, a0_bare_matched 0.5312 |
| recall per arm (repo_name) | a1_full 0.6436, a0_bare_matched 0.5585 |
| recall per arm (every class) | a1_full 0.6293, a0_bare_matched 0.5366 |
| re-included cells (arm / group: class n) | a1_full / G1: outside_path 1, repo_name 1; a1_full / G3: network_egress:nonrepo 1; a1_full_openmount / G3: outside_path 3; a1_review_only / G1: repo_name 1 |
| pr_weighted | Δ 0.0834 [-0.0880, 0.2549] |
| matched_fable_contrast | Δ 0.3333 | 95 % [0.2122, 0.4545] | 90 % [0.2348, 0.4319] | SE 0.0544 | PRs 11, pairs 17, defects 195 | diag 95 % percentile [0.2408, 0.4521] |
