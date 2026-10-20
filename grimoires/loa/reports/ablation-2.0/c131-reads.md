# cycle-131 Sprint 265 reads — formal run 2026-10-20T09:36:42Z

Pin `798d88cf`; rows `grimoires/loa/reports/ablation-2.0/c131-rows.jsonl` (27); pre-registration DEC-0648 (NOTES 2026-10-20T04:02:26Z, sha256 2ed2bfee…); decision statistic `defect_catch_rate_pm3` (DEC-0638); DEC-0650 (min_valid_cells 4 vs 3 planned trials → trial-level sensitivity beside the main read); S3 declared NOTES 2026-10-20T05:41:08Z. Script `reads-c131.py` (seed 20261015; 10,000 defect-level paired bootstrap resamples; 90 %; cluster bootstrap by PR descriptive).

# cycle-131 reads — pin `798d88cfc920a95ce896a527145b21ca72d0ab18` — 27 c131 rows — statistic `defect_catch_rate_pm3` (DEC-0638; pre-registration DEC-0648)


## Main read (min_valid_cells 4 as pre-registered)

| read | contrast | PRs | defects | cells A/B (Σ) | rate A | rate B | Δ | 90 % defect CI | cluster CI (PR) | USD/run A | USD/run B | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | a1_full_openmount − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.75 | 0.6833 | 0.0667 | [-0.0167, 0.15] | [0.0667, 0.0667] | 19.21 | 21.5 | insufficient |
| R5a | a0_bare_fable − a1_full | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.6845 | -0.4583 | [-0.6012, -0.3155] | [-0.5625, -0.4167] | 4.28 | 19.94 | outside ±0.05 |
| R5b | a0_bare_fable − a0_bare | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.3929 | -0.1667 | [-0.3095, -0.0179] | [-0.25, -0.1333] | 4.28 | 1.4 | outside ±0.05 |
| R3 | a1_review_only − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.65 | 0.6833 | -0.0333 | [-0.1333, 0.0667] | [-0.0333, -0.0333] | 11.42 | 21.5 | insufficient |
| R4 | a1_no_dissent − a1_full | pr-17 | 20 | r17:2/3 (Σ2) | 0.75 | 0.6833 | 0.0667 | [-0.05, 0.1917] | [0.0667, 0.0667] | 15.79 | 21.5 | insufficient |

R5 outcome: **between (both intervals reported)** (R5a bare-Fable vs full: outside ±0.05; R5b bare-Fable vs bare: outside ±0.05).

## Sensitivity: trial level (min 3 valid trials per side, the planned count; DEC-0650)

| read | contrast | PRs | defects | cells A/B (Σ) | rate A | rate B | Δ | 90 % defect CI | cluster CI (PR) | USD/run A | USD/run B | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | a1_full_openmount − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.75 | 0.6833 | 0.0667 | [-0.0167, 0.15] | [0.0667, 0.0667] | 19.21 | 21.5 | investigate |
| R5a | a0_bare_fable − a1_full | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.6845 | -0.4583 | [-0.6012, -0.3155] | [-0.5625, -0.4167] | 4.28 | 19.94 | outside ±0.05 |
| R5b | a0_bare_fable − a0_bare | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.3929 | -0.1667 | [-0.3095, -0.0179] | [-0.25, -0.1333] | 4.28 | 1.4 | outside ±0.05 |
| R3 | a1_review_only − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.65 | 0.6833 | -0.0333 | [-0.1333, 0.0667] | [-0.0333, -0.0333] | 11.42 | 21.5 | inconclusive |
| R4 | a1_no_dissent − a1_full | pr-17 | 20 | r17:2/3 (Σ2) | 0.75 | 0.6833 | 0.0667 | [-0.05, 0.1917] | [0.0667, 0.0667] | 15.79 | 21.5 | insufficient |

## Sensitivity: oracle exclusion by the diff form only

| read | contrast | PRs | defects | cells A/B (Σ) | rate A | rate B | Δ | 90 % defect CI | cluster CI (PR) | USD/run A | USD/run B | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | a1_full_openmount − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.75 | 0.6833 | 0.0667 | [-0.0167, 0.15] | [0.0667, 0.0667] | 19.21 | 21.5 | insufficient |
| R5a | a0_bare_fable − a1_full | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.6845 | -0.4583 | [-0.6012, -0.3155] | [-0.5625, -0.4167] | 4.28 | 19.94 | outside ±0.05 |
| R5b | a0_bare_fable − a0_bare | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.3929 | -0.1667 | [-0.3095, -0.0179] | [-0.25, -0.1333] | 4.28 | 1.4 | outside ±0.05 |
| R3 | a1_review_only − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.65 | 0.6833 | -0.0333 | [-0.1333, 0.0667] | [-0.0333, -0.0333] | 11.42 | 21.5 | insufficient |
| R4 | a1_no_dissent − a1_full | pr-17 | 20 | r17:2/3 (Σ2) | 0.75 | 0.6833 | 0.0667 | [-0.05, 0.1917] | [0.0667, 0.0667] | 15.79 | 21.5 | insufficient |

## Sensitivity: degraded and dissent-absent rows excluded

| read | contrast | PRs | defects | cells A/B (Σ) | rate A | rate B | Δ | 90 % defect CI | cluster CI (PR) | USD/run A | USD/run B | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | a1_full_openmount − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.75 | 0.6833 | 0.0667 | [-0.0167, 0.15] | [0.0667, 0.0667] | 19.21 | 21.5 | insufficient |
| R5a | a0_bare_fable − a1_full | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.6845 | -0.4583 | [-0.6012, -0.3155] | [-0.5625, -0.4167] | 4.28 | 19.94 | outside ±0.05 |
| R5b | a0_bare_fable − a0_bare | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.3929 | -0.1667 | [-0.3095, -0.0179] | [-0.25, -0.1333] | 4.28 | 1.4 | outside ±0.05 |
| R3 | a1_review_only − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.65 | 0.6833 | -0.0333 | [-0.1333, 0.0667] | [-0.0333, -0.0333] | 11.42 | 21.5 | insufficient |
| R4 | a1_no_dissent − a1_full | pr-17 | 0 | r17:0/3 (Σ0) | - | - | - | - | - | None | 21.5 | insufficient |

## Sensitivity S3: scratch-directory outside_path contaminations re-included (NOTES 2026-10-20T05:41:08Z; min 3 trials)

| read | contrast | PRs | defects | cells A/B (Σ) | rate A | rate B | Δ | 90 % defect CI | cluster CI (PR) | USD/run A | USD/run B | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 | a1_full_openmount − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.75 | 0.6833 | 0.0667 | [-0.0167, 0.15] | [0.0667, 0.0667] | 19.21 | 21.5 | investigate |
| R5a | a0_bare_fable − a1_full | pr-17, pr-18 | 28 | r17:3/3 r18:3/3 (Σ6) | 0.2262 | 0.6786 | -0.4524 | [-0.5952, -0.3095] | [-0.5417, -0.4167] | 4.28 | 19.69 | outside ±0.05 |
| R5b | a0_bare_fable − a0_bare | pr-17, pr-18 | 28 | r17:3/3 r18:3/2 (Σ5) | 0.2262 | 0.3929 | -0.1667 | [-0.3095, -0.0179] | [-0.25, -0.1333] | 4.28 | 1.4 | outside ±0.05 |
| R3 | a1_review_only − a1_full | pr-17 | 20 | r17:3/3 (Σ3) | 0.65 | 0.6833 | -0.0333 | [-0.1333, 0.0667] | [-0.0333, -0.0333] | 11.42 | 21.5 | inconclusive |
| R4 | a1_no_dissent − a1_full | pr-17 | 20 | r17:2/3 (Σ2) | 0.75 | 0.6833 | 0.0667 | [-0.05, 0.1917] | [0.0667, 0.0667] | 15.79 | 21.5 | insufficient |

## Row inventory

| arm | task | rows | completed | main-valid | S3-eligible | degraded | fallback | oracle-exposed | USD |
|---|---|---|---|---|---|---|---|---|---|
| a0_bare | review-r17 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 4.64 |
| a0_bare | review-r18 | 3 | 2 | 2 | 0 | 0 | 0 | 0 | 3.59 |
| a0_bare_fable | review-r17 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 14.52 |
| a0_bare_fable | review-r18 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 11.16 |
| a1_full | review-r17 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 64.5 |
| a1_full | review-r18 | 3 | 2 | 2 | 1 | 0 | 0 | 0 | 53.62 |
| a1_full_openmount | review-r17 | 3 | 3 | 3 | 0 | 0 | 0 | 3 | 57.62 |
| a1_no_dissent | review-r17 | 3 | 2 | 2 | 0 | 0 | 0 | 0 | 48.63 |
| a1_review_only | review-r17 | 3 | 3 | 3 | 0 | 0 | 0 | 0 | 34.25 |
