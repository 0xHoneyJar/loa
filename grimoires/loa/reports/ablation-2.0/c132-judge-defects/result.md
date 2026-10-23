# Defect-level judge read — EXPLORATORY / post hoc (DEC-0800, DEC-0810)

Not a registered analysis. Per arm a seeded sample of grader-credited (cell, defect) pairs; every credited citation of a sampled pair judged blind. A pair counts when at least one of its citations is judged `describes` (strict) or `describes`/`partially` (lenient). Corrected recall = grader recall × share. 593 items, 593 judged; 200 pairs, 0 incomplete; seed 20261021; 2000 PR-cluster bootstrap resamples, 95 % percentile intervals.

## Per arm (EXPLORATORY / post hoc)

| arm | cells | PRs | pairs judged | items | strict share | 95 % | lenient share | 95 % | grader recall | corrected strict | 95 % | corrected lenient | 95 % |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| a0_bare_fable_matched | 28 | 14 | 40 of 40 | 58 | 0.1250 | [0.0000, 0.2408] | 0.2250 | [0.0689, 0.4048] | 0.2757 | 0.0345 | [0.0000, 0.0659] | 0.0620 | [0.0164, 0.1136] |
| a0_bare_matched | 25 | 13 | 40 of 40 | 103 | 0.2250 | [0.1000, 0.3913] | 0.3500 | [0.2571, 0.4706] | 0.4906 | 0.1104 | [0.0439, 0.2259] | 0.1717 | [0.1134, 0.2789] |
| a1_full | 17 | 11 | 40 of 40 | 166 | 0.2750 | [0.1000, 0.4595] | 0.3250 | [0.1600, 0.4872] | 0.6308 | 0.1735 | [0.0546, 0.3572] | 0.2050 | [0.0933, 0.3645] |
| a1_full_openmount | 23 | 12 | 40 of 40 | 147 | 0.4000 | [0.3030, 0.5217] | 0.5250 | [0.4000, 0.6923] | 0.6126 | 0.2450 | [0.1700, 0.3581] | 0.3216 | [0.2279, 0.4611] |
| a1_review_only | 20 | 12 | 40 of 40 | 119 | 0.2500 | [0.1163, 0.4167] | 0.3500 | [0.2500, 0.4828] | 0.4714 | 0.1179 | [0.0478, 0.2315] | 0.1650 | [0.0973, 0.2846] |

## a1_full − a0_bare_matched (EXPLORATORY / post hoc; PRs resampled jointly, 14 PRs)

| figure | difference | 95 % |
|---|---|---|
| share strict | 0.0500 | [-0.1586, 0.2343] |
| share lenient | -0.0250 | [-0.2059, 0.1810] |
| recall corrected strict | 0.0631 | [-0.0731, 0.2172] |
| recall corrected lenient | 0.0333 | [-0.0792, 0.1840] |

## Per PR (EXPLORATORY / post hoc)

| arm | PR | pairs | items | judged pairs | strict | lenient |
|---|---|---|---|---|---|---|
| a0_bare_fable_matched | review-r11 | 1 | 1 | 1 | 0 | 0 |
| a0_bare_fable_matched | review-r14 | 5 | 8 | 5 | 0 | 0 |
| a0_bare_fable_matched | review-r15 | 12 | 19 | 12 | 2 | 3 |
| a0_bare_fable_matched | review-r16 | 1 | 1 | 1 | 0 | 0 |
| a0_bare_fable_matched | review-r19 | 1 | 1 | 1 | 0 | 0 |
| a0_bare_fable_matched | review-r20 | 1 | 2 | 1 | 0 | 0 |
| a0_bare_fable_matched | review-r21 | 2 | 2 | 2 | 0 | 0 |
| a0_bare_fable_matched | review-r22 | 3 | 4 | 3 | 0 | 0 |
| a0_bare_fable_matched | review-r23 | 2 | 2 | 2 | 0 | 0 |
| a0_bare_fable_matched | review-r24 | 5 | 8 | 5 | 0 | 1 |
| a0_bare_fable_matched | review-r25 | 1 | 1 | 1 | 0 | 0 |
| a0_bare_fable_matched | review-r26 | 2 | 5 | 2 | 1 | 2 |
| a0_bare_fable_matched | review-r27 | 4 | 4 | 4 | 2 | 3 |
| a0_bare_matched | review-r11 | 2 | 2 | 2 | 0 | 0 |
| a0_bare_matched | review-r14 | 4 | 10 | 4 | 1 | 2 |
| a0_bare_matched | review-r15 | 12 | 33 | 12 | 0 | 3 |
| a0_bare_matched | review-r16 | 2 | 5 | 2 | 1 | 1 |
| a0_bare_matched | review-r19 | 4 | 6 | 4 | 1 | 1 |
| a0_bare_matched | review-r21 | 2 | 4 | 2 | 1 | 1 |
| a0_bare_matched | review-r23 | 1 | 1 | 1 | 0 | 0 |
| a0_bare_matched | review-r24 | 3 | 7 | 3 | 1 | 2 |
| a0_bare_matched | review-r25 | 2 | 17 | 2 | 1 | 1 |
| a0_bare_matched | review-r26 | 1 | 3 | 1 | 1 | 1 |
| a0_bare_matched | review-r27 | 5 | 10 | 5 | 2 | 2 |
| a0_bare_matched | review-r28 | 2 | 5 | 2 | 0 | 0 |
| a1_full | review-r11 | 1 | 5 | 1 | 1 | 1 |
| a1_full | review-r15 | 8 | 25 | 8 | 0 | 0 |
| a1_full | review-r16 | 1 | 4 | 1 | 0 | 0 |
| a1_full | review-r19 | 3 | 5 | 3 | 0 | 1 |
| a1_full | review-r22 | 5 | 11 | 5 | 0 | 1 |
| a1_full | review-r23 | 8 | 41 | 8 | 4 | 4 |
| a1_full | review-r24 | 4 | 24 | 4 | 2 | 2 |
| a1_full | review-r25 | 2 | 26 | 2 | 1 | 1 |
| a1_full | review-r26 | 2 | 5 | 2 | 0 | 0 |
| a1_full | review-r27 | 5 | 13 | 5 | 2 | 2 |
| a1_full | review-r28 | 1 | 7 | 1 | 1 | 1 |
| a1_full_openmount | review-r11 | 2 | 6 | 2 | 1 | 1 |
| a1_full_openmount | review-r14 | 4 | 10 | 4 | 2 | 3 |
| a1_full_openmount | review-r15 | 11 | 27 | 11 | 3 | 4 |
| a1_full_openmount | review-r16 | 2 | 10 | 2 | 0 | 0 |
| a1_full_openmount | review-r19 | 1 | 2 | 1 | 1 | 1 |
| a1_full_openmount | review-r21 | 5 | 16 | 5 | 3 | 4 |
| a1_full_openmount | review-r23 | 4 | 26 | 4 | 2 | 2 |
| a1_full_openmount | review-r25 | 2 | 21 | 2 | 1 | 2 |
| a1_full_openmount | review-r26 | 5 | 22 | 5 | 2 | 2 |
| a1_full_openmount | review-r27 | 4 | 7 | 4 | 1 | 2 |
| a1_review_only | review-r11 | 3 | 10 | 3 | 1 | 1 |
| a1_review_only | review-r14 | 6 | 11 | 6 | 0 | 1 |
| a1_review_only | review-r19 | 1 | 1 | 1 | 1 | 1 |
| a1_review_only | review-r21 | 2 | 4 | 2 | 0 | 0 |
| a1_review_only | review-r22 | 3 | 5 | 3 | 1 | 1 |
| a1_review_only | review-r23 | 9 | 30 | 9 | 1 | 2 |
| a1_review_only | review-r24 | 4 | 22 | 4 | 2 | 2 |
| a1_review_only | review-r25 | 2 | 4 | 2 | 0 | 1 |
| a1_review_only | review-r26 | 3 | 13 | 3 | 1 | 1 |
| a1_review_only | review-r27 | 5 | 15 | 5 | 3 | 3 |
| a1_review_only | review-r28 | 2 | 4 | 2 | 0 | 1 |
