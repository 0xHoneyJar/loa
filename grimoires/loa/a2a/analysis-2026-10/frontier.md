# Deliverable 4 — cost-effectiveness frontier (suite v2, valid cells)

Catch rate = task-mean of the per-PR rate (the report's statistic); USD = mean per PR (per run, or the summed runs for a union). Unions take the defects any of the trials caught. 'Reconstructed' re-applies the grader's rule to a subset of the sources; 'hypothetical' changes only the cost. Script: `scripts/frontier.py` on `data/runs.json`.

## Task-mean frontier

| configuration | catch rate | USD per PR | minutes per PR | USD per 0.01 catch over bare x1 |
|---|---|---|---|---|
| bare x1 | 0.668 | 0.70 | 2.8 | — |
| bare x2 (union) | 0.744 | 1.41 | 5.5 | 0.09 |
| bare x3 (union) | 0.744 | 2.11 | 8.3 | 0.19 |
| full | 0.854 | 11.64 | 28.8 | 0.59 |
| full without AUDIT gate (reconstructed) | 0.799 | 5.93 | 15.3 | 0.40 |
| full, dissent cost removed (hypothetical) | 0.854 | 9.65 | 28.8 | 0.48 |
| review gate only, dissent cost removed (hypothetical) | 0.799 | 4.94 | 15.3 | 0.32 |
| full x2 (union, from the 3 trials) | 0.925 | 23.28 | 57.6 | 0.88 |

## Per PR

### review-01 (pr-05, 3 defects)

| configuration | catch rate | USD | min |
|---|---|---|---|
| bare x1 | 1.000 | 0.21 | 1.0 |
| bare x2 (union) | 1.000 | 0.43 | 2.1 |
| bare x3 (union) | 1.000 | 0.64 | 3.1 |
| full | 1.000 | 9.08 | 23.6 |
| full without AUDIT gate (reconstructed) | 1.000 | 4.23 | 11.3 |
| full, dissent cost removed (hypothetical) | 1.000 | 7.22 | 23.6 |
| review gate only, dissent cost removed (hypothetical) | 1.000 | 3.36 | 11.3 |
| full x2 (union, from the 3 trials) | 1.000 | 18.16 | 47.3 |

### review-02 (pr-08, 3 defects)

| configuration | catch rate | USD | min |
|---|---|---|---|
| bare x1 | 0.889 | 0.23 | 1.1 |
| bare x2 (union) | 1.000 | 0.46 | 2.2 |
| bare x3 (union) | 1.000 | 0.69 | 3.3 |
| full | 1.000 | 8.63 | 20.5 |
| full without AUDIT gate (reconstructed) | 0.889 | 3.86 | 9.8 |
| full, dissent cost removed (hypothetical) | 1.000 | 6.69 | 20.5 |
| review gate only, dissent cost removed (hypothetical) | 0.889 | 2.93 | 9.8 |
| full x2 (union, from the 3 trials) | 1.000 | 17.25 | 40.9 |

### review-03 (pr-12, 8 defects)

| configuration | catch rate | USD | min |
|---|---|---|---|
| bare x1 | 0.250 | 1.26 | 4.9 |
| bare x2 (union) | 0.375 | 2.53 | 9.8 |
| bare x3 (union) | 0.375 | 3.79 | 14.7 |
| full | 0.750 | 17.05 | 40.9 |
| full without AUDIT gate (reconstructed) | 0.708 | 8.92 | 23.6 |
| full, dissent cost removed (hypothetical) | 0.750 | 12.88 | 40.9 |
| review gate only, dissent cost removed (hypothetical) | 0.708 | 6.74 | 23.6 |
| full x2 (union, from the 3 trials) | 0.833 | 34.09 | 81.7 |

### review-04 (pr-13, 5 defects)

| configuration | catch rate | USD | min |
|---|---|---|---|
| bare x1 | 0.533 | 1.11 | 4.0 |
| bare x2 (union) | 0.600 | 2.21 | 8.0 |
| bare x3 (union) | 0.600 | 3.32 | 12.0 |
| full | 0.667 | 11.80 | 30.3 |
| full without AUDIT gate (reconstructed) | 0.600 | 6.73 | 16.6 |
| full, dissent cost removed (hypothetical) | 0.667 | 11.80 | 30.3 |
| review gate only, dissent cost removed (hypothetical) | 0.600 | 6.73 | 16.6 |
| full x2 (union, from the 3 trials) | 0.867 | 23.61 | 60.6 |

## ASCII chart (task-mean; x = USD per PR, y = catch rate)
```text
 0.92 |                                                                   8    
 0.90 |                                                                        
 0.88 |                                                                        
 0.86 |                            6    7                                      
 0.83 |                                                                        
 0.81 |              4  5                                                      
 0.79 |                                                                        
 0.77 |                                                                        
 0.75 |    2 3                                                                 
 0.73 |                                                                        
 0.71 |                                                                        
 0.69 |  1                                                                     
 0.66 |                                                                        
 0.64 |                                                                        
 0.62 |                                                                        
 0.60 |                                                                        
      +------------------------------------------------------------------------
       0                              USD per PR                          24
  1: bare x1  (0.668, USD 0.70)
  2: bare x2 (union)  (0.744, USD 1.41)
  3: bare x3 (union)  (0.744, USD 2.11)
  4: review gate only, dissent cost removed (hypothetical)  (0.799, USD 4.94)
  5: full without AUDIT gate (reconstructed)  (0.799, USD 5.93)
  6: full, dissent cost removed (hypothetical)  (0.854, USD 9.65)
  7: full  (0.854, USD 11.64)
  8: full x2 (union, from the 3 trials)  (0.925, USD 23.28)
```

## Cheapest configuration reaching each catch-rate level (task-mean)

| level | cheapest configuration | USD per PR | measured (not hypothetical) alternative |
|---|---|---|---|
| ≥ 0.65 | bare x1 | 0.70 | bare x1 (USD 0.70) |
| ≥ 0.70 | bare x2 (union) | 1.41 | bare x2 (union) (USD 1.41) |
| ≥ 0.75 | review gate only, dissent cost removed (hypothetical) | 4.94 | full without AUDIT gate (reconstructed) (USD 5.93) |
| ≥ 0.80 | full, dissent cost removed (hypothetical) | 9.65 | full (USD 11.64) |
| ≥ 0.85 | full, dissent cost removed (hypothetical) | 9.65 | full (USD 11.64) |
| ≥ 0.90 | full x2 (union, from the 3 trials) | 23.28 | full x2 (union, from the 3 trials) (USD 23.28) |

Reading: three bare passes (USD 2.11) reach 0.744; the full pipeline (USD 11.64) reaches 0.854 and nothing cheaper reaches 0.80 in this data. The reconstructed review gate alone keeps most of full's catch for about 55 % of its cost; the dissent's own cost is a quarter of a full run and buys no grader-credited citation (deliverable 2). On the two small PRs every configuration saturates, so the frontier is really drawn by pr-12 and pr-13.

