# cycle-132 power simulation

Seed 20261021; inputs sha256 `01740b2500c052172963242690c04a8ae1fafa613247aff7fc714f4562286667`; 2000 studies per N and Δ; MDE 0.1000; exclusion rate 0.0500; partial-group probability 0.1000; SE bootstrap (200 resamples).

Interval t. Selection: the smallest N with P(YES | MDE) ≥ 0.80 and P(NO | 0) ≥ 0.80 under its calibrated constant.

## Per N

| N | groups | constant | SE plan | Δ | YES | NO | SMALL | NEGATIVE | FUTILE | inconclusive | void | clipped | E recall matched | E recall full | cap USD |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 6 | 6 | 1.0000 | 0.0413 | 0 | 0.0335 | 0.2770 | 0.0015 | 0.0260 | 0.0000 | 0.6620 | 0.0000 | 0.1652 (unreliable) | 0.7528 | 0.7528 | 1950 |
| 6 | 6 | 1.0000 | 0.0413 | MDE | 0.3980 | 0.0175 | 0.0020 | 0.0000 | 0.0000 | 0.5825 | 0.0000 | 0.2597 (unreliable) | 0.7586 | 0.8586 | 1950 |
| 8 | 6+2 | 1.0000 | 0.0370 | 0 | 0.0265 | 0.4470 | 0.0040 | 0.0335 | 0.0520 | 0.4370 | 0.0000 | 0.1652 (unreliable) | 0.7528 | 0.7528 | 2400 |
| 8 | 6+2 | 1.0000 | 0.0370 | MDE | 0.5625 | 0.0220 | 0.0030 | 0.0005 | 0.0360 | 0.3760 | 0.0000 | 0.2597 (unreliable) | 0.7586 | 0.8586 | 2400 |
| 10 | 6+4 | 1.0000 | 0.0338 | 0 | 0.0300 | 0.5595 | 0.0060 | 0.0335 | 0.0225 | 0.3485 | 0.0000 | 0.1652 (unreliable) | 0.7528 | 0.7528 | 2850 |
| 10 | 6+4 | 1.0000 | 0.0338 | MDE | 0.6460 | 0.0280 | 0.0005 | 0.0005 | 0.0185 | 0.3065 | 0.0000 | 0.2597 (unreliable) | 0.7586 | 0.8586 | 2850 |
| 12 | 6+3+3 | 1.0000 | 0.0306 | 0 | 0.0325 | 0.6860 | 0.0045 | 0.0285 | 0.0525 | 0.1960 | 0.0000 | 0.1652 (unreliable) | 0.7528 | 0.7528 | 3350 |
| 12 | 6+3+3 | 1.0000 | 0.0306 | MDE | 0.7260 | 0.0415 | 0.0035 | 0.0010 | 0.0485 | 0.1795 | 0.0000 | 0.2597 (unreliable) | 0.7586 | 0.8586 | 3350 |
| 14 | 6+4+4 | 1.0000 | 0.0286 | 0 | 0.0340 | 0.7530 | 0.0060 | 0.0295 | 0.0270 | 0.1505 | 0.0000 | 0.1652 (unreliable) | 0.7528 | 0.7528 | 3800 |
| 14 | 6+4+4 | 1.0000 | 0.0286 | MDE | 0.8200 | 0.0340 | 0.0015 | 0.0000 | 0.0265 | 0.1180 | 0.0000 | 0.2597 (unreliable) | 0.7586 | 0.8586 | 3800 |

| N | P(YES · MDE) | P(NO · 0) | P(SMALL · 0) | P(NEGATIVE · 0) | P(NEGATIVE · MDE) | type I | both ≥ 0.80 |
|---|---|---|---|---|---|---|---|
| 6 | 0.3980 | 0.2770 | 0.0015 | 0.0260 | 0.0000 | 0.0335 | no |
| 8 | 0.5625 | 0.4470 | 0.0040 | 0.0335 | 0.0005 | 0.0265 | no |
| 10 | 0.6460 | 0.5595 | 0.0060 | 0.0335 | 0.0005 | 0.0300 | no |
| 12 | 0.7260 | 0.6860 | 0.0045 | 0.0285 | 0.0010 | 0.0325 | no |
| 14 | 0.8200 | 0.7530 | 0.0060 | 0.0295 | 0.0000 | 0.0340 | no |

Decision table (ordered, exhaustive; round 3). The YES boundary is two-sided: "z_yes crosses" means |z_yes| ≥ b_yes. 1. z_yes crosses and Δ̂ < 0 → NEGATIVE. 2. z_yes crosses and Δ̂ > 0 and z_no < b_no and RCI upper ≥ MDE → YES. 3. z_yes crosses and Δ̂ ≥ 0 and (z_no ≥ b_no or RCI upper < MDE) → SMALL. 4. z_yes does not cross and z_no ≥ b_no → NO. 5. neither crossed, final look → INCONCLUSIVE. 6. neither crossed, interim look: both conditional powers < 0.20 → FUTILE (non-binding), else CONTINUE.

**No N chosen — DECISION REQUIRED** (NO N satisfies P(YES | MDE) >= 0.80 and P(NO | 0) >= 0.80: nothing is chosen; the figures below are at the largest evaluated N (the ceiling) and the lead decides). At the reference N = 14: P(YES | MDE) 0.8200, P(NO | 0) 0.7530; groups [6, 4, 4], looks [6, 10, 14]; calibrated constant 1.0000; planned final SE 0.0286; cap USD 3800 (envelope USD 2500); corpus ceiling 14.

## Sensitivities at N = 14

| variant | P(YES · MDE) main c | P(NO · 0) main c | type I main c | recalibrated c | P(YES · MDE) | P(NO · 0) | type I |
|---|---|---|---|---|---|---|---|
| k_minus_3 | 0.7455 | 0.6975 | 0.0475 | 1.0000 | 0.7430 | 0.6870 | 0.0460 |
| k_plus_3 | 0.7560 | 0.7475 | 0.0355 | 1.0000 | 0.7565 | 0.7475 | 0.0355 |
| r_0 | 0.7945 | 0.7310 | 0.0510 | 1.0200 | 0.7850 | 0.7160 | 0.0480 |
| r_0.10 | 0.7625 | 0.6990 | 0.0480 | 1.0000 | 0.7585 | 0.6930 | 0.0490 |
| rho_0.3 | 0.7000 | 0.6175 | 0.0360 | 1.0000 | 0.6660 | 0.5790 | 0.0370 |
| rho_0.6 | 0.5865 | 0.5305 | 0.0440 | 1.0000 | 0.5305 | 0.4720 | 0.0440 |
| spread_x0.5 | 0.7810 | 0.7330 | 0.0460 | 1.0000 | 0.7780 | 0.7295 | 0.0465 |
| spread_x1.5 | 0.7690 | 0.7090 | 0.0510 | 1.0000 | 0.7650 | 0.7035 | 0.0500 |

## Model inputs

| profile | defects | bare runs | full runs | diff lines | k |
|---|---|---|---|---|---|
| review-01 | 3 | 3 | 3 | 70 | 19 |
| review-02 | 3 | 3 | 3 | 72 | 19 |
| review-03 | 8 | 3 | 3 | 822 | 16 |
| review-04 | 5 | 3 | 3 | 5079 | 10 |
| review-r17 | 20 | 6 | 6 | 3791 | 11 |
| review-r18 | 8 | 5 | 3 | 1818 | 14 |

| arm | α | β | mean | ρ | never caught | chance | π0 (fixed point) | diag: chance (one pass) | diag: π0 literal |
|---|---|---|---|---|---|---|---|---|---|
| bare | 1.6281 | 0.6557 | 0.7129 | 0.3045 | 0.2766 | 0.0593 | 0.2310 | 0.2502 | 0.0264 |
| full | 3.1738 | 0.5734 | 0.8470 | 0.2107 | 0.0638 | 0.0150 | 0.0496 | 0.0479 | 0.0159 |

| cost fit | intercept | slope per line | rows |
|---|---|---|---|
| a0_bare | 0.5967 | 0.000207 | 23 |
| a0_bare_fable | 2.6882 | 0.000568 | 6 |
| a1_full | 11.4522 | 0.001125 | 23 |

## Candidates (seeded order: post-cutoff first, pr-11 last and flagged)

| order | fixture | sprint | head date | defects | exposure (Fable 5.1) | diff lines | k Opus | k Fable | contamination note |
|---|---|---|---|---|---|---|---|---|---|
| 1 | pr-27 | 263 | 2026-10-19 | 10 | post-cutoff | 4588 | 11 | 3 | — |
| 2 | pr-28 | 264 | 2026-10-20 | 4 | post-cutoff | 347 | 18 | 4 | — |
| 3 | pr-23 | 259 | 2026-10-15 | 12 | post-cutoff | 3479 | 12 | 3 | — |
| 4 | pr-14 | 250 | 2026-10-06 | 28 | post-cutoff | 2324 | 13 | 4 | — |
| 5 | pr-15 | 251 | 2026-10-07 | 15 | post-cutoff | 3023 | 12 | 3 | — |
| 6 | pr-25 | 261 | 2026-10-18 | 11 | post-cutoff | 883 | 16 | 4 | — |
| 7 | pr-16 | 252 | 2026-10-13 | 12 | post-cutoff | 3574 | 12 | 3 | one cycle-131 smoke run (decided nothing) |
| 8 | pr-26 | 262 | 2026-10-18 | 2 | post-cutoff | 1424 | 15 | 4 | seeded with --allow-no-labels; annotation supplies the key |
| 9 | pr-21 | 257 | 2026-10-14 | 5 | post-cutoff | 6827 | 10 | 3 | — |
| 10 | pr-19 | 255 | 2026-10-14 | 21 | post-cutoff | 6794 | 10 | 3 | — |
| 11 | pr-24 | 260 | 2026-10-16 | 12 | post-cutoff | 4408 | 11 | 3 | — |
| 12 | pr-20 | 256 | 2026-10-14 | 5 | post-cutoff | 5810 | 10 | 3 | — |
| 13 | pr-22 | 258 | 2026-10-15 | 20 | post-cutoff | 7096 | 9 | 3 | — |
| 14 | pr-11 (flagged) | 247 | 2026-09-25 | 20 | post-cutoff | 3501 | 12 | 3 | synthetic-plus-record; flagged (pr-11 last) |

Selected (first N in order, reference N — not chosen): pr-27, pr-28, pr-23, pr-14, pr-15, pr-25, pr-16, pr-26, pr-21, pr-19, pr-24, pr-20, pr-22, pr-11.
