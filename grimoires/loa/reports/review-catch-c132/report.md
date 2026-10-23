# cycle-132 — does the Loa review pipeline catch more real defects per dollar than a bare model, on PRs it has not seen?

**Cycle:** cycle-132 "the conclusive review-catch answer" · **Branch:** `feature/cycle-132-conclusive-review-catch` · **Pipeline under test:** Loa at commit `fbd36a0c` (every Phase 1 row's `source_commit`) · **Binding registration:** `REGISTRATION-15.json` (analysis addendum 16; PREREGISTRATION.md plus addenda 1–16; the pipeline pin unchanged; the full chain with hashes is in `PREREGISTRATION-sha256.txt`) · **Reads taken:** 2026-10-23, Sprint 271, by the lead (Fable 5.1) with `reads-c132.py --final` · **Every table below is copied byte for byte from a generated artefact** by `scripts/report-assemble.py`; `evals/tests/c132-report.bats` fails if a table row appears nowhere in those artefacts.

## ELI5

We asked one question and wrote down, before spending money, how we would answer it: on fourteen real pull requests the pipeline had never reviewed, does Loa's review pipeline (review gate, audit gate, a second model arguing against each) find more real bugs than plain model sessions given the same dollars?

Two blind annotators re-derived the bugs from the fix commits and later incidents, so the answer key was not the pipeline's own past output. Each PR was reviewed twice by the pipeline and twice by a bundle of plain model sessions costing the same money, with the plain sessions' findings pooled. A mechanical grader checked whether a finding pointed at a known bug; a blind judge audited a sample of its verdicts.

The result: the pipeline found about ten points more of the labelled bugs than the same-dollar bundle of plain sessions, and it did so while spending less. But the interval around that ten points runs from about minus nine to plus twenty-nine, so we cannot say the difference is real, and we cannot say it is absent. The pre-registered stopping rule did not fire; the final look reads "inconclusive". Under the older answer key seeded from the original reviews, the plain sessions even came out slightly ahead, so the sign itself depends on which key is used. The pipeline also lost over a quarter of its planned runs to a structural problem: on PRs that modify Loa's own files, the pinned pipeline reads its own already-fixed copies, and those runs were excluded.

Two things came out clearly. Review alone catches fewer bugs than review plus audit. And against plain sessions of the pipeline's own model at the same dollars, the pipeline wins by a wide margin. Nothing shipped by default changes on this cycle's strength.

## The answer

The pipeline (`a1_full`) caught a larger share of the labelled defects than the compute-matched bundle of bare Opus 5.5 sessions (`a0_bare_matched`) on the ten valid PRs, by about ten points of defect-weighted recall, with a 95 % cluster-t interval that includes zero and the registered minimum detectable effect:

| primary a1_full − a0_bare_matched | Δ 0.0971 | 95 % [-0.0936, 0.2879] | 90 % [-0.0575, 0.2517] | SE 0.0843 | PRs 10, pairs 16, defects 175 | diag 95 % percentile [-0.0682, 0.2647] |
| PR-weighted | Δ 0.0834 | 95 % [-0.0880, 0.2549] | 90 % [-0.0555, 0.2223] | | |

Repeated confidence interval at the stopping look 3: [-0.0936, 0.2879] (b = 2.2622); decision INCONCLUSIVE.

REML LMM: β 0.0614, 95 % [-0.0540, 0.1767], σu 0.1934, σe 0.1664.
PR-level permutation: p 0.3711 (exact, 1024).

**The stopping rule did not fire** at any of the three registered looks, and the final look (information fraction 1) reads **INCONCLUSIVE**: the YES statistic z_yes 1.15 is below the O'Brien–Fleming boundary 2.26 and the NO statistic z_no 0.03 is below its boundary, so neither "the pipeline catches more at the MDE" nor "it does not" is established. **The 25 % guard tripped on the full arm** (eleven of twenty-eight planned cells excluded), so by the registration the read is **inconclusive by degradation**. **The placebo on these rows failed its calibration band** (one in ten shuffled intervals excluded zero against the registered eight percent), so, as pre-specified in §8, the decision rests on the simulation-calibrated group-sequential boundary and the PR-level permutation test (p 0.37) rather than on the bootstrap interval alone. **The sign depends on the key:** under the registered review-derived sensitivity key (nine PRs, fifty-seven defects) the matched bundle reads above the pipeline, with an interval that again covers zero.

## Pre-registered reads (PREREGISTRATION §5)

### Secondary reads

Defects per USD: full 0.4117 [0.2677, 0.6292]; matched 0.2939 [0.1942, 0.4532].

The matched arm is **dominated**: on the valid pairs the full arm caught seventeen more defects while spending less (USD 276.92 against 330.07; on all spend 358.06 against 443.27), so the registered cost per extra defect has no positive increment to divide by. Since analysis addendum 16 the read carries the registration's own word, `dominated` (DEC-0805), with both increments printed. The session-1 contrasts are unavailable under the c132 validity rules (`no_session1`):

| cost per extra defect | value | extra defects | cost increment | status |
|---|---|---|---|---|
| matched_all_spend | — | 17.0000 | -85.2104 | dominated |
| matched_valid | — | 17.0000 | -53.1584 | dominated |
| session1_all_spend | — | — | — | no_session1 |
| session1_valid | — | — | — | no_session1 |

| contrast | read |
|---|---|
| review_only_vs_full | Δ -0.1185, 95 % [-0.1959, -0.0411], PRs 10 |
| pipeline_independent | Δ 0.2941, 95 % [-0.0437, 0.6320], PRs 7 |
| matched_fable | Δ 0.3333, 95 % [0.2122, 0.4545], PRs 11 |

Review alone catches fewer labelled defects than review plus audit (the one registered contrast whose interval excludes zero); the pipeline-independent read (defects with `review_driven = false` or sourced from an incident) has the same sign as the primary on too few PRs to decide; the same-model contrast against bare Fable 5.1 sessions at the same dollars favours the pipeline by a third of the key.

### Co-reads (PREREGISTRATION §5; descriptive, they never enter the decision)

| (a) pipeline-independent a1_full − a0_bare_matched | Δ 0.2941 | 95 % [-0.0437, 0.6320] | 90 % [0.0258, 0.5624] | SE 0.1381 | PRs 7, pairs 11, defects 34 | diag 95 % percentile [0.0000, 0.5333] |
| (c) cost-matched (exact-dollar trim, pairs within ±25 %) | Δ 0.0805 | 95 % [-0.0505, 0.2114] | 90 % [-0.0222, 0.1831] | SE 0.0510 | PRs 6, pairs 7, defects 87 | diag 95 % percentile [-0.0328, 0.1622] |

| stratum | a1_full caught / defects | recall | a0_bare_matched caught / defects | recall |
|---|---|---|---|---|
| label_source = fix-commit | 109 / 170 | 0.6412 | 95 / 170 | 0.5588 |
| label_source = fix-commit+incident | 3 / 3 | 1.0000 | 0 / 3 | 0.0000 |
| label_source = incident | 2 / 2 | 1.0000 | 2 / 2 | 1.0000 |
| review_driven = false | 23 / 33 | 0.6970 | 14 / 33 | 0.4242 |
| review_driven = true | 91 / 142 | 0.6408 | 83 / 142 | 0.5845 |

The pipeline-independent co-read keeps the primary's sign on the defects the production pipeline did not find first; the cost-matched read on the seven pairs within the dollar tolerance is smaller than the primary and its interval covers zero.

### Dollar matching

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

### Missingness (intention-to-run)

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

Bounds with every excluded matched session counted as caught-everything and as missed-everything:

| bound: excluded_sessions_caught_everything | Δ -0.1179 | 95 % [-0.3463, 0.1105] | 90 % [-0.3037, 0.0678] | SE 0.1025 | PRs 11, pairs 17, defects 195 | diag 95 % percentile [-0.3214, 0.0710] |
| bound: excluded_sessions_missed_everything | Δ 0.1026 | 95 % [-0.0639, 0.2690] | 90 % [-0.0328, 0.2380] | SE 0.0747 | PRs 11, pairs 17, defects 195 | diag 95 % percentile [-0.0443, 0.2532] |

## Stopping rule (PREREGISTRATION §6)

| look | PRs | defects | Δ | SE | t | z_yes | b_yes | z_no | b_no | CP yes | CP no | RCI | decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 78 | 0.2041 | 0.1022 | 0.0783 | 1.9966 | 1000.0000 | -1.0182 | 1000.0000 | 1.0000 | 0.0000 | [-102.0125, 102.4206] | CONTINUE (minimum information not reached (5 valid PRs < 6 or 78 labelled defects < 30)) |
| 2 | 8 | 108 | 0.1053 | 0.0960 | 0.0887 | 1.0963 | 158.5408 | -0.0548 | 158.5408 | 0.9643 | 0.0124 | [-15.1170, 15.3275] | CONTINUE |
| 3 | 10 | 122 | 0.0971 | 0.0843 | 1.0000 | 1.1518 | 2.2622 | 0.0339 | 2.2622 | 0.0000 | 0.0000 | [-0.0936, 0.2879] | INCONCLUSIVE |

Looks 1 and 2 read CONTINUE (look 1 below the minimum-information rule of six valid PRs; look 2 with both conditional powers above the futility floor); look 3 was the final look and reads INCONCLUSIVE by the registered table. No budget stop occurred.

## Sensitivities (PREREGISTRATION §10, registered order; they decide nothing)

| frozen_c131_labels (key dir `c131`) | status `too_few_prs` | PRs 3 |
| frozen_c131_labels: descriptive, valid pairs | a1_full 8 / 12 = 0.6667; a0_bare_matched 7 / 12 = 0.5833; PRs 3, pairs 3; cells re-graded 40, without a re-grade 100 |
| v1_labels (key dir `v1`) | status `too_few_prs` | PRs 3 |
| v1_labels: descriptive, valid pairs | a1_full 7 / 12 = 0.5833; a0_bare_matched 5 / 12 = 0.4167; PRs 3, pairs 3; cells re-graded 40, without a re-grade 100 |
| review_derived_labels (key dir `review`) | Δ -0.0877 | 95 % [-0.3033, 0.1279] | 90 % [-0.2616, 0.0862] | SE 0.0935 | PRs 9, pairs 14, defects 57 | diag 95 % percentile [-0.2336, 0.1064] |
| review_derived_labels: descriptive, valid pairs | a1_full 32 / 57 = 0.5614; a0_bare_matched 37 / 57 = 0.6491; PRs 9, pairs 14; cells re-graded 140, without a re-grade 0 |
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

Reading guide. The frozen cycle-131 and v1 keys exist for four of the fourteen fixtures, so after the re-grades (analysis addendum 16) their contrasts read the registered status `too_few_prs` (three PRs with valid pairs); descriptively both keep the primary's sign. **The seeded review-derived key reverses it:** on nine PRs and fifty-seven defects the matched bundle reads above the pipeline (Δ −0.09, interval covering zero). That key was seeded from the original human and pipeline review feedback and holds about a third as many defects as the re-derived v2 key on the same pairs; the primary's positive point estimate is therefore not robust to the choice of key, and the report says so rather than choosing between them after the fact. The judge-corrected sensitivity carries the registered Horvitz–Thompson estimator, which removes 1/m of a defect's credit per rejected citation and so penalises arms with many citations per defect (DEC-0800); it is not an arm comparison. Re-including the oracle-exposed cells (the structural limitation below) moves the estimate up and its interval off zero in the every-form row — that is the read the registration refused to make primary, because exposure is a property of the pinned pipeline on these PRs.

## Placebo (PREREGISTRATION §8)

On the Phase 1 rows, 200 seeded within-PR arm-label shuffles through the primary read:

| shuffles | resamples | share excluding 0 | mean Δ | Δ q05 / q50 / q95 | diag: mean abs Δ | diag: share (t) | diag: share (percentile) |
|---|---|---|---|---|---|---|---|
| 200 | 1000 | 0.1000 | -0.0005 | -0.0971 / 0.0057 / 0.0857 | 0.0501 | 0.1000 | 0.1000 |

| unshuffled | Δ 0.0971 | 95 % [-0.0936, 0.2879] | 90 % [-0.0575, 0.2517] | SE 0.0843 | PRs 10, pairs 16, defects 175 | diag 95 % percentile [-0.0682, 0.2647] |

Verdict **FAIL** on calibration (share excluding zero above the 0.08 band; bias passes), as the Phase 0 placebo on the 63 pre-existing rows also read:

| shuffles | resamples | share excluding 0 | mean Δ | Δ q05 / q50 / q95 | diag: mean abs Δ | diag: share (t) | diag: share (percentile) |
|---|---|---|---|---|---|---|---|
| 200 | 1000 | 0.0950 | -0.0090 | -0.1443 / -0.0050 / 0.1149 | 0.0622 | 0.0950 | 0.1700 |

The band is not loosened. The pre-specified fallback applies: the primary interval stands beside its placebo-estimated exclusion share, and the decision rests on the group-sequential boundary — whose size the power simulation put at P(YES | Δ = 0) = 0.034 for the complete procedure — and on the PR-level permutation test.

## Positive control (PREREGISTRATION §8, addendum 10)

Positive control (§8 (addendum 10); a1_full_openmount − a1_full, every group, saturated PRs exempt review-r11, review-r24, review-r25): pass; Δ 0.0417, 90 % [-0.0335, 0.1169], expected 0.0670; eligible pairs 11, exposed open runs 9. Pre-addendum-10 label (G1 only): inconclusive.

The open mount reads above the closed mount with oracle exposure in nine open runs, so the apparatus distinguishes the two in the expected direction and no read is void. The pre-addendum-10 label (G1 only) is printed beside it as registered.

## Ground truth (Phase 0, Sprint 269)

Two blind Opus 5.5 annotators labelled every fix hunk of `head..fix` and every post-merge incident of the fourteen fixtures; the lead adjudicated disagreements; the merged v2 key is the one every arm was graded against.

**Pooled (14 fixtures):** hunk-verdict κ 0.8776 (n 835); incident κ 0.8846 (n 120); items 955, adjudicated 344 (share 0.360); v2 defects 185 (incident-confirmed 5); defect-weighted review-driven share 0.827; blind-session spend USD 26.00 (rows in `evals/results/ablation-2.0/c132-phase0/rows.jsonl`).

| fixture | hunks | κ verdict | κ severity | localization | grouping Jaccard | items | adjudicated | share | v2 defects | incident-confirmed | review-driven share | review key confirmed | reruns | USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pr-27 | 28 | 1.000 | 1.000 | 1.000 | 0.973 | 31 | 6 | 0.194 | 13 | 1 | 0.769 | 5/7 | 0 | 0.880 |
| pr-28 | 9 | 1.000 | 1.000 | 1.000 | 1.000 | 11 | 1 | 0.091 | 3 | 0 | 1.000 | 2/2 | 0 | 0.320 |
| pr-23 | 66 | 0.938 | 0.861 | 1.000 | 0.792 | 77 | 27 | 0.351 | 13 | 1 | 0.615 | 1/1 | 1 | 2.880 |
| pr-14 | 95 | 0.970 | 0.620 | 1.000 | 0.922 | 121 | 13 | 0.107 | 17 | 0 | 1.000 | 2/2 | 0 | 3.740 |
| pr-15 | 227 | 0.930 | 0.762 | 0.971 | 0.525 | 239 | 99 | 0.414 | 45 | 0 | 0.867 | 3/3 | 0 | 6.340 |
| pr-25 | 29 | 0.838 | -0.200 | 1.000 | 0.372 | 39 | 12 | 0.308 | 4 | 0 | 1.000 | 0/1 | 0 | 0.990 |
| pr-16 | 18 | 0.880 | 1.000 | 1.000 | 0.300 | 26 | 11 | 0.423 | 6 | 0 | 0.667 | 3/4 | 0 | 0.590 |
| pr-26 | 54 | 0.551 | 0.630 | 1.000 | 0.846 | 56 | 23 | 0.411 | 9 | 0 | 0.778 | 0/0 | 0 | 1.510 |
| pr-21 | 105 | 0.843 | 1.000 | 0.941 | 0.606 | 108 | 70 | 0.648 | 16 | 0 | 0.938 | 1/2 | 0 | 2.410 |
| pr-19 | 20 | 1.000 | 0.231 | 0.933 | 1.000 | 30 | 7 | 0.233 | 15 | 0 | 0.867 | 9/11 | 0 | 1.100 |
| pr-24 | 31 | 0.784 | 0.210 | 1.000 | 0.963 | 39 | 11 | 0.282 | 9 | 1 | 0.778 | 4/4 | 0 | 1.250 |
| pr-20 | 56 | 0.629 | 1.000 | 1.000 | 1.000 | 57 | 13 | 0.228 | 10 | 0 | 0.300 | 1/4 | 0 | 1.020 |
| pr-22 | 79 | 0.886 | 0.576 | 1.000 | 0.614 | 88 | 44 | 0.500 | 20 | 2 | 0.900 | 9/11 | 0 | 2.230 |
| pr-11 | 18 | 0.780 | 0.000 | 1.000 | 1.000 | 33 | 7 | 0.212 | 5 | 0 | 1.000 | 4/5 | 0 | 0.720 |

Most defects were first found by the production pipeline (defect-weighted review-driven share 0.827), so the labels remain downstream of the thing being measured except for the pipeline-independent subset read above.

## Judge agreement (PREREGISTRATION §9, Sprint 270 Task 2.6)

- strict: agreement 0.6259 unweighted, 0.4646 weighted; kappa 0.1991 [0.1595, 0.2382]
- lenient: agreement 0.6921 unweighted, 0.5701 weighted; kappa 0.2735 [0.2295, 0.3180]

The grader's proximity rule credits a citation within three lines of a key anchor; the judge says about one in five such credits describes the labelled defect, in every arm alike. The registered corrected figures (strict, then lenient):

| arm | cells | PRs | recall (grader) | recall corrected | 95 % | precision (grader) | precision corrected | 95 % |
|---|---|---|---|---|---|---|---|---|
| a0_bare_fable_matched | 28 | 14 | 0.2757 | 0.0568 | [0.0209, 0.0932] | 0.2367 | 0.2926 | [0.2318, 0.3637] |
| a0_bare_matched | 25 | 13 | 0.4906 | 0.0520 | [-0.0213, 0.1547] | 0.2124 | 0.3051 | [0.2248, 0.3896] |
| a1_full | 17 | 11 | 0.6308 | 0.0150 | [-0.0956, 0.1202] | 0.2593 | 0.1788 | [0.1279, 0.2391] |
| a1_full_openmount | 23 | 12 | 0.6126 | 0.0572 | [0.0081, 0.1244] | 0.2692 | 0.2109 | [0.1621, 0.2737] |
| a1_review_only | 20 | 12 | 0.4714 | 0.0909 | [0.0199, 0.1835] | 0.2544 | 0.2456 | [0.1747, 0.3249] |

| arm | cells | PRs | recall (grader) | recall corrected | 95 % | precision (grader) | precision corrected | 95 % |
|---|---|---|---|---|---|---|---|---|
| a0_bare_fable_matched | 28 | 14 | 0.2757 | 0.1005 | [0.0398, 0.1599] | 0.2367 | 0.3206 | [0.2601, 0.3932] |
| a0_bare_matched | 25 | 13 | 0.4906 | 0.1153 | [0.0600, 0.2063] | 0.2124 | 0.3315 | [0.2533, 0.4110] |
| a1_full | 17 | 11 | 0.6308 | 0.0671 | [-0.0291, 0.1911] | 0.2593 | 0.2070 | [0.1569, 0.2650] |
| a1_full_openmount | 23 | 12 | 0.6126 | 0.1330 | [0.0793, 0.1870] | 0.2692 | 0.2582 | [0.1933, 0.3311] |
| a1_review_only | 20 | 12 | 0.4714 | 0.1634 | [0.0864, 0.2757] | 0.2544 | 0.2866 | [0.2195, 0.3588] |

An exploratory defect-level judge read (every credited citation of a seeded sample of credited cell–defect pairs per arm; declared before its data in DEC-0800, sized in DEC-0810) is reported in `judge-defects/result.md` when complete and is labelled post hoc there.

## Spend (PREREGISTRATION §7)

| item | USD |
|---|---|
| cap (PREREGISTRATION §7, binding) | 4200.00 |
| run rows since kickoff (arms, smokes, blind sessions; deduplicated by run_id) | 3272.72 |
| host cost ledger since kickoff (dissents, Flatline, judge-side calls) | 47.39 |
| cycle meter total | 3320.12 |
| headroom under the cap | 879.88 |
| reserves still held (reproduction rerun, dissents) | 250.00 |

No batch was stopped by the cap; the arm allowance and every reserve except the judge's were respected (the judge spent USD 43.1 against a reserve of 30; the contingency covered it).

## Honest caveats

1. **The structural limitation.** Nine of the fourteen PRs modify `.claude/`, and the pinned pipeline reads its own fixed copies of those files while reviewing; the registered oracle detector marks such runs exposed and the primary excludes them. Eight full-arm cells fell to it. The re-inclusion sensitivities show what the estimate would be if exposure were ignored; the registration refused to make that the primary, and so does this report.
2. **Degradation.** The full arm kept seventeen of twenty-eight planned cells; the 25 % guard trips and the read is inconclusive by degradation. The matched arm kept twenty-five.
3. **Contamination hand-reads.** Every invalid unit was read by hand (`batch-scans.md`); mechanisms by arm:

| arm | R | T | W | S | P | A | F | K | ? | total |
|---|---|---|---|---|---|---|---|---|---|---|
| a0_bare_fable_matched | 0 | 0 | 0 | 1 | 0 | 0 | 2 | 0 | 0 | 3 |
| a0_bare_matched | 9 | 13 | 0 | 7 | 2 | 0 | 3 | 1 | 0 | 35 |
| a1_full | 0 | 1 | 1 | 0 | 1 | 2 | 0 | 0 | 0 | 5 |
| a1_full_openmount | 0 | 0 | 0 | 3 | 0 | 0 | 1 | 0 | 0 | 4 |
| a1_review_only | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 |
| all | 9 | 14 | 1 | 12 | 3 | 2 | 6 | 1 | 0 | 48 |

| class | mechanism |
|---|---|
| R | reach for the upstream repository (clone, ls-remote, or a fetch of main) — the leak class 9 exists for |
| T | tool download or connectivity probe not naming the repository (jq 1.7.1 from github.com/jqlang; curl -I github.com) |
| W | a report written through a cat heredoc quoting PR text that carries the repository token (class 7, AG-53) |
| S | fictional paths or the repository token inside test inputs the reviewer fed to the PR's own guard or grader code |
| P | an environment probe for executable scratch space or mounts (/tmp is noexec, the root read-only) |
| A | a deliberately absent path in an errexit or fallback probe (/nonexistent/...) |
| F | GRADER FALSE POSITIVE: a sed/awk address or substitution regex (/re/d, /re/p, /re/g) tokenised as a two-component path |
| K | took-effect FAIL caused by PR code the agent executed (KF-053) |

4. **Labels downstream of the pipeline.** The v2 key was re-derived from fix commits and incidents, but most of those fixes were prompted by the pipeline's own past reviews (review-driven share 0.827). The pipeline-independent co-read is the honest check and is too small to decide.
5. **Key dependence.** The registered review-derived-key sensitivity reverses the primary's sign (nine PRs, fifty-seven defects, interval covering zero); the frozen c131 and v1 keys keep it on three PRs. Which key one believes decides the sign of the point estimate; no key makes the interval exclude zero in the pipeline's favour at matched dollars.
6. **Placebo calibration.** At ten clusters the cluster-t interval is anti-conservative by about two points; the registration anticipated this and bounded it by the simulated size of the whole procedure.
7. **Judge agreement is low** (κ about 0.2) and the registered correction is biased against arms with many citations per defect (DEC-0800). The grader stays primary as registered; the semantic question is open.
8. **Corpus ceiling.** N = 14 is every eligible fixture; the power simulation gave P(YES | MDE) 0.82 and P(NO | 0) 0.75 at that N, and a true null ends INCONCLUSIVE in about one study in seven. pr-11 (2026-09-25) is borderline for model exposure and is flagged; the pr-11-out sensitivity is above.
9. **Sixteen addenda** corrected defects exposed by smokes, looks, the judge pilot and the first final read, each registered before the data it governs was read; `PREREGISTRATION-sha256.txt` lists the chain. None changed the primary estimand, the arms, the rule or the cap; addendum 16 supplied the missing label-set and co-read branches of the analysis and the `dominated` label.
10. **Operations.** A host reboot killed the lead session at the start of Sprint 271 (recovered by `/run-resume`); two earlier reboots and one runner kill are recorded in `batches.md`. The Sprint 270 lead ran part of the sprint on Opus 5.5; arm and judge models are pinned in the registration and were unaffected.

## Proof

- **Reproduction** (FR-10): an Opus 5.5 reproducer, from a fresh clone of the record branch into an empty directory, re-grades every recorded run, re-rows, re-reads and re-runs the registered sample live; its report is `grimoires/loa/a2a/sprint-271/reproduction/report.md` (also under `reproduction/` beside this file on the record branch) and `REPRODUCE.md` beside this file carries the exact commands and expected hashes.
- **Controls:** the positive control and both placebos above (`placebo-phase1.md`, `placebo-existing/placebo-existing.md`).
- **Judge:** `judge/result.md`, `judge/result.json`, `judge/key-summary.json`; the exploratory defect-level read in `judge-defects/`.
- **Dissent records:** plan-stage Flatline reviews of the PRD, SDD, sprint plan and the pre-registration (`grimoires/loa/a2a/flatline/{prd,sdd,sprint,spec}-flatline-*-final_consensus.json`, `grimoires/loa/a2a/sprint-269/flatline-prereg.json`); the review and audit dissent envelopes of Sprints 269, 270 and 271 (`grimoires/loa/a2a/sprint-26{9,70}/adversarial-{review,audit}.json`, `sprint-270/` copied beside this file, `sprint-271/`); the Bridgebuilder round on the cycle PR.
- **Registration:** `PREREGISTRATION-sha256.txt` (every pre-registration and addendum hash and every REGISTRATION-N.json hash; binding at the final read: REGISTRATION-14).
- **Decisions:** DEC-0801 … DEC-0811 (the reads, the stopping-rule outcome, the placebo and positive-control verdicts, the sensitivity re-grades, the exploratory judge read, the record design), each with the alternatives rejected, in `grimoires/loa/decisions.yaml`.

## Files

| file | what |
|---|---|
| `reads.md`, `reads.json` | `reads-c132.py --final` at REGISTRATION-14 (byte-identical across runs; the JSON twin carries every figure) |
| `rows.jsonl` | the 140 Phase 1 rows (groups G1–G3, every registered arm) |
| `power.md` | the power simulation that set N = 14 and the cap |
| `PREREGISTRATION-sha256.txt` | the registration chain |
| `placebo-phase1.md`, `placebo-phase1.json` | the placebo on the Phase 1 rows |
| `judge/` | the blind judge (Task 2.6) |
| `ground-truth.md` | the annotation run (Task 1.6) |
| `spend.md`, `spend.json` | the cycle meter |
| `batches.md`, `batch-scans.md` | the batch record and the contamination hand-reads |
| `scripts/` | the lead's drivers (`batch-c132.sh`, `look.sh`, `final.sh`, `register*.sh`, `run-judge.sh`, `report-assemble.py`) |
| `sprint-270/` | the Sprint 270 gate artefacts (reviewer report, feedback, dissent envelopes) |
| `REPRODUCE.md`, `reproduction/` | the reproduction instructions and the reproducer's report |
| `judge-defects/` | the exploratory defect-level judge read |
