# Deliverable 1 — per-defect contingency, bare vs full (suite v2, valid cells)

Source: the 24 valid run directories (12 a0_bare, 12 a1_full) re-graded with the grader's own citation rule (`scripts/extract.py`; cross-check against every grade.json: identical). 19 planted defects × 3 paired trials = 57 defect-trials. Script: `scripts/contingency.py` (seed 20261015, 10000 resamples, 90 % intervals).

## Pooled paired table (defect-trials)

| | full caught | full missed | total |
|---|---|---|---|
| **bare caught** | 31 | 0 | 31 |
| **bare missed** | 15 | 11 | 26 |
| **total** | 46 | 11 | 57 |

- bare catch rate 31/57 = 0.544; full 46/57 = 0.807; difference (pooled) +0.263
- discordant pairs: full-only 15, bare-only 0; **exact McNemar (two-sided binomial on the discordant pairs) p = 0.0001**
- caveat: the 57 defect-trials are not independent (three trials of one defect share the defect; defects share a PR); the McNemar p treats them as independent pairs and is therefore optimistic. The intervals below are the honest view.

## Per PR

| task | PR | diff lines | files | defects | bare caught /9 or /24 or /15 | full | both | full-only | bare-only | neither | exact McNemar p |
|---|---|---|---|---|---|---|---|---|---|---|---|
| review-01 | pr-05 | 127 | 3 | 3 | 9/9 | 9/9 | 9 | 0 | 0 | 0 | 1.000 |
| review-02 | pr-08 | 138 | 3 | 3 | 8/9 | 9/9 | 8 | 1 | 0 | 0 | 1.000 |
| review-03 | pr-12 | 1077 | 15 | 8 | 6/24 | 18/24 | 6 | 12 | 0 | 6 | 0.000 |
| review-04 | pr-13 | 5880 | 54 | 5 | 8/15 | 10/15 | 8 | 2 | 0 | 5 | 0.500 |

## Per defect (over 3 trials)

| task | defect | id | sev | category | bare | full | both | full-only | bare-only | neither |
|---|---|---|---|---|---|---|---|---|---|---|
| review-01 | d1 | `D13-find-exec-multi-root` | critical | authz | 3 | 3 | 3 | 0 | 0 | 0 |
| review-01 | d2 | `D14-billing-400-terminal` | high | error-handling | 3 | 3 | 3 | 0 | 0 | 0 |
| review-01 | d3 | `D15-completed-sprints-unscoped` | medium | logic | 3 | 3 | 3 | 0 | 0 | 0 |
| review-02 | d1 | `D22-ledger-shape-unpinned` | high | input-validation | 3 | 3 | 3 | 0 | 0 | 0 |
| review-02 | d2 | `D23-heredoc-body-fail-open` | medium | logic | 3 | 3 | 3 | 0 | 0 | 0 |
| review-02 | d3 | `D24-embedded-nul-valueerror` | medium | error-handling | 2 | 3 | 2 | 1 | 0 | 0 |
| review-03 | d1 | `L01-the-check-only-proves-the-head` | high | logic | 0 | 3 | 0 | 3 | 0 | 0 |
| review-03 | d2 | `L02-is-unguarded` | high | error-handling | 2 | 3 | 2 | 1 | 0 | 0 |
| review-03 | d3 | `L03-when-the-primary-ends-and-the-` | high | logic | 0 | 2 | 0 | 2 | 0 | 1 |
| review-03 | d4 | `L04-the-companion-is-forked-before` | medium | logic | 2 | 3 | 2 | 1 | 0 | 0 |
| review-03 | d5 | `L05-the-cli-hop-is-always-planned-` | medium | logic | 0 | 3 | 0 | 3 | 0 | 0 |
| review-03 | d6 | `L06-the-companion-runs` | medium | logic | 2 | 3 | 2 | 1 | 0 | 0 |
| review-03 | d7 | `L07-the-pipeline-materialises-the-` | low | security | 0 | 1 | 0 | 1 | 0 | 2 |
| review-03 | d8 | `L08-the-stub-spoke-the-review-voca` | low | logic | 0 | 0 | 0 | 0 | 0 | 3 |
| review-04 | d1 | `L01-is-discarded-silently` | low | logic | 2 | 2 | 2 | 0 | 0 | 1 |
| review-04 | d2 | `L02-the-model-id-shape-this-host-s` | medium | logic | 3 | 3 | 3 | 0 | 0 | 0 |
| review-04 | d3 | `L03-the-alias-target-is-interpolat` | low | security | 3 | 3 | 3 | 0 | 0 | 0 |
| review-04 | d4 | `L04-the-protocol-s-never-load-a-1-` | low | logic | 0 | 1 | 0 | 1 | 0 | 2 |
| review-04 | d5 | `L05-the-parallelism-sentence-cites` | low | concurrency | 0 | 1 | 0 | 1 | 0 | 2 |

## Intervals

- **Pre-registered read (reproduced):** defect-level paired bootstrap over the 19 defects (each defect's mean over its 3 trials), 90 %: **+0.263 [+0.140, +0.386]** (the shipped report: +0.263 [+0.158, +0.386]; same statistic, independent implementation; the bootstrap distribution over 19 units is discrete and the 5 % point sits on a jump between 8/57 = +0.140 and 9/57 = +0.158 — one defect-trial — so the two lower bounds are the same number read on either side of the jump; upper bound identical).
- **Cluster bootstrap by PR (4 clusters, resampled with replacement, defect-pooled statistic):** +0.263 [+0.056, +0.437]; task-mean statistic +0.186 [+0.056, +0.375]. With four clusters the resampling distribution has only 33 distinct values (support +0.000 … +0.500); the interval's lower end is where resamples drop pr-12 — **this is the honest uncertainty with four PRs: the effect is positive in every resample that keeps pr-12 and ≈ 0 in those that do not.**
- Leave-one-PR-out (pooled): without review-01 (pr-05) +0.312, without review-02 (pr-08) +0.292, without review-03 (pr-12) +0.091, without review-04 (pr-13) +0.310.
- Task means: review-01 +0.000, review-02 +0.111, review-03 +0.500, review-04 +0.133.

## Diff-size covariate

| task | PR | diff lines | files | defects | bare rate | full rate | lift |
|---|---|---|---|---|---|---|---|
| review-01 | pr-05 | 127 | 3 | 3 | 1.000 | 1.000 | +0.000 |
| review-02 | pr-08 | 138 | 3 | 3 | 0.889 | 1.000 | +0.111 |
| review-03 | pr-12 | 1077 | 15 | 8 | 0.250 | 0.750 | +0.500 |
| review-04 | pr-13 | 5880 | 54 | 5 | 0.533 | 0.667 | +0.133 |

Reading: the lift is not monotone in diff size — zero on the two ~130-line PRs where bare is already at or near 1.0 (ceiling), largest on the 1,077-line PR, and small on the 5,880-line PR where both arms are low and the dissent never ran (budget gate). Bare's catch rate falls with diff size (1.00, 0.89, 0.25, 0.53); full's falls less (1.00, 1.00, 0.75, 0.67). Four points cannot separate 'size' from 'this PR'.

## By severity and category (defect-trials caught)

| severity | defects | bare | full |
|---|---|---|---|
| critical | 1 | 3/3 | 3/3 |
| high | 5 | 8/15 | 14/15 |
| low | 6 | 5/18 | 8/18 |
| medium | 7 | 15/21 | 21/21 |

| category | defects | bare | full |
|---|---|---|---|
| authz | 1 | 3/3 | 3/3 |
| concurrency | 1 | 0/3 | 1/3 |
| error-handling | 3 | 7/9 | 9/9 |
| input-validation | 1 | 3/3 | 3/3 |
| logic | 11 | 15/33 | 26/33 |
| security | 2 | 3/6 | 4/6 |
