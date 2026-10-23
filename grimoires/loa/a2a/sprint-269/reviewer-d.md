# s1-d report — Sprint 1 Task 1.8: the stdlib analysis module and the judge sampler

Model: global.anthropic.claude-opus-5-5. Worktree `loa-wt-s1d` at 346dbb87. Patch `~/.cache/loa/cycle-132/patches/s1-d.patch`.

## What was built
- `evals/analysis/c132/`: `stats.py` (bootstrap, REML, permutation, OBF recursion, RCI, CP, placebo, cost reads, kappa, Student-t), `common.py` (loading, keys, validity, pairing, INPUTS/registration validation), `reads.py` + `reads-c132.py` (`--look/--final/--placebo/--make-inputs`), `power.py` (§5.3 simulation), `judge_agree.py` (agreement, kappa, HT figures); `tests/` (4 test files, `synth.py`, `_path.py`, `fixtures/power-mini/`).
- `evals/harness/judge-sample.sh`; `evals/tests/analysis-c132.bats`, `evals/tests/judge-sample.bats`.

## How it was tested
```
python3 -m unittest discover -s evals/analysis/c132/tests        # 76 tests OK
~/.cache/loa/cycle-128/s2d/bin/bats evals/tests/analysis-c132.bats evals/tests/judge-sample.bats   # 5 + 8 ok
bash -n evals/harness/judge-sample.sh; tools/check-no-raw-sha256sum.sh, check-no-swallowed-jq.sh, check-no-raw-curl.sh: OK
~/.cache/loa/cycle-128/s2d/bin/bats evals/tests/                  # 1..554, 554 ok, exit 0
```
Per file: test_stats 32, test_reads 24, test_power 14, test_judge_agree 6 (76); analysis-c132.bats 5, judge-sample.bats 8. Read-only smoke on the 63 rows (outputs in /tmp): `--make-inputs` + `--placebo` on the 63 existing rows; `judge-sample.sh` on the 63 rows (3,620 units, 563 items, 0 grader-consistency mismatches); `power.py` defaults on the 63 rows in 69 s.

Reference values reproduced:
- OBF two-sided 0.05 at (1/3, 2/3, 1): 3.7103, 2.5114, 1.9930 (published 3.710, 2.511, 1.993); two looks (½, 1): 2.9626, 1.9686 (published 2.963, 1.969); one-sided 0.025 identical.
- REML: balanced 3-PR × 2-arm × 2-cell example; the reference is the ANOVA closed form computed in the test (REML = ANOVA for balanced data when positive): β = mean diff, σe² = SSE/(N−P−1), σu² = (MSB − MSE)/n, se(β) = √(MSE/(N/4)); all within 1e-6.
- kappa 2×2 [[20,5],[10,15]] = 0.40; permutation p = 2/8 on diffs 1, 2, 3; t₅,0.975 = 2.570582, t₁₁ = 2.200985.

## AC evidence
- FR-5 AC1 unit tests (bootstrap seed, REML 1e-6, permutation, OBF 0.01, placebo on nulls, validity): PASS (test_stats, ValidityTest).
- FR-5 AC2 placebo on the 63 rows committed: lead Task 1.10; smoke FAILS the band (findings 1–2).
- FR-5 AC3 `--look`/`--final` byte-identical: PASS (OutputTest, AC-2). Degenerate statuses and input refusals: PASS.
- FR-6 AC1 seeded determinism, AC2 candidate order, AC3 chosen N from frozen inputs (mini fixture): PASS (TinyRunTest, AC-4, test_candidate_order).
- FR-4 sampler strata on synthetic grades, provenance-free packets: PASS (JS-1, JS-4, JS-5).

## Findings the lead must weigh before hashing
1. **The placebo band fails on true nulls at this N.** The 95 % percentile PR-cluster interval undercovers. On synthetic nulls the share excluding 0 is 13.5 % at 6 PRs, 10.7 % at 8, 9.0 % at 12 and 5.9 % at 20. Mean |Δ| is 0.037 and 0.033 at 6 and 8. The t-interval Δ ± t_{P−1}·SE·√(P/(P−1)) gives 4.6 / 5.8 / 5.3 / 3.4 %, and it is printed beside as a diagnostic.
2. **On the 63 existing rows the placebo cannot pass.** The within-PR shuffle of arms with a real effect spreads Δ: share 0.160, mean |Δ| 0.075, t-diagnostic 0.080. Under the c132 validity filter, oracle exposure removes every a1_full cell of review-04, so only 5 PRs pair and the unshuffled read is `too_few_prs`.
3. **Clipping flags every N on the existing profiles.** The clipped share is 0.32 at Δ = 0 and 0.43 at the MDE, against a 0.10 flag. k is 11–19, so matched recall and full recall both sit near the ceiling. Power profiles: 5, not 6.
4. With the placeholder candidate table, calibration inflated the constant above 1 (1.02–1.11). That is the same undercoverage.

## DECISIONS (round 0)
The 23 round-0 DECISION bullets are verbatim in the round-0 final message to the lead (the source of the DEC rows).

## CHANGELOG entry text (### Added)
- Added `evals/analysis/c132/` (stdlib): `stats.py`, `common.py`, `reads.py` with the `reads-c132.py` CLI (`--look`, `--final`, `--placebo`, `--make-inputs`; input-manifest and registration validation; byte-identical output), `power.py` (simulation of the complete pre-registered procedure with calibration, cap and affordable-N) and `judge_agree.py` (agreement, kappa, Horvitz–Thompson corrected figures), with unit tests and `evals/tests/analysis-c132.bats`.
- Added `evals/harness/judge-sample.sh`: the stratified blind-judge sample of grader decisions with recorded inclusion probabilities and provenance-free packets, with `evals/tests/judge-sample.bats`.

## What the lead must do
- Registration fields `reads.py` reads: `seed`, `boundary_constant`, `groups`, `mde` (default 0.10), `planned_final_se` or `power_json` (power.json writes `planned_final_se`), and optionally `sensitivities`. Implementer C's `registration.py` should emit them.
- Build INPUTS.json with `reads-c132.py --make-inputs --pin … --label-set … --planned <keys> --suite-root …`, review it, then freeze it.
- Row field `took_effect` is read if present. When absent it is treated as "not recorded" and passes. Row writer 1.5 does not write it, so the took-effect filter is unenforced unless C adds it.
- `labels_meta[]` entries should carry `id`, or else be in d1…dN order (implementer B). `per_session[]` uses `{session, detected, cost_usd, status}` (implementer C).
- Task 1.10: run `--placebo --arm-b a0_bare --name placebo-existing` and decide findings 1–2 before Task 1.11.
- Task 1.9: run power with A's real candidate table; at defaults it takes about 70 s.
- The a2a copy is gitignored (not in the patch).

## Round 1 (lead review: findings 1–4 accepted)
Delta `~/.cache/loa/cycle-132/patches/s1-d-r1.patch` (8 files, +381/−137). Unit tests 83 OK (stats 36, reads 26, power 15, judge_agree 6); bats 13/13.
- **Interval:** `--interval t|percentile` (default t) in reads.py and power.py. The primary interval is Δ̂ ± t_{P−1}·SE_boot (90 %: t_{0.95}); the percentile interval is printed beside. Look boundaries move to the t scale with the same upper-tail mass and df = valid PRs − 1. This applies to the crossing rule, the RCI and power's procedure.
- **Coverage, independent nulls** (400 datasets per size, 300 resamples, seed 1000+s):

| PRs | t: share excluding 0 | percentile |
|---|---|---|
| 6 | 0.065 | 0.128 |
| 8 | 0.058 | 0.108 |
| 12 | 0.048 | 0.075 |

  The test pins t inside [0.03, 0.08] at 6, 8 and 12 PRs, and percentile above 0.08 at 6 and 8.
- **Placebo pass rule:** |mean Δ| < 0.03 and t-interval share ≤ 0.08. Mean |Δ| and the t / percentile shares are kept as diagnostics. On the 63 rows with `--validity c131` (6 PRs): mean Δ −0.009 passes the bias rule; share 0.095 fails the calibration rule (percentile 0.170, mean |Δ| 0.062); the unshuffled Δ is 0.2836 with t 95 % [0.140, 0.427].
- **Power:** the per-N table adds P(NO | 0), P(SMALL | 0), the clipped share and the expected matched and full recall. Selection needs both P(YES | MDE) and P(NO | 0) ≥ 0.80; if no N qualifies, `chosen_n` is null, `decision_required` is true and the figures are given at the ceiling. With the placeholder candidates no N qualifies; at N = 10, P(YES) 0.636, P(NO) 0.603, constant 1.00. Expected matched recall is 0.749.
- **π0:** the literal estimate is printed beside as a diagnostic: bare 0.028 literal vs 0.237 fixed point. Correction to the round-1 note: the literal form shrinks a true 0.20 to 0.023; the fixed point recovers it.
- `--validity c131` (no oracle_exposed clause) is added to reads.py and power.py; the default stays c132. Under c131, power has 6 profiles instead of 5.

DECISIONS (round 1):
- DECISION: the t interval uses SE_boot without the √(P/(P−1)) inflation of my round-0 diagnostic (the lead's formula; coverage above).
- DECISION: under t, the boundaries convert by equal upper-tail mass, b_t = t_sf⁻¹(1 − Φ(b), df = valid PRs − 1), in reads and power alike; conditional power stays on the normal Brownian model.
- DECISION: the placebo exclusion share uses the primary interval; percentile, t and mean |Δ| are diagnostics.
- DECISION: "exploratory" now flags when either power is below 0.50; the affordable-N rule applies only when an N meets both powers.
- DECISION: `--validity c131` drops only the oracle_exposed clause, and power.py gets the same flag.

## Round 2 (lead integration findings)
Delta `~/.cache/loa/cycle-132/patches/s1-d-r2.patch` (7 files, +187/−76). Unit tests 88 OK locally (stats 37, reads 30, power 15, judge_agree 6; +5). The AC-1 pin goes 112 → 117 for the branch. bats 13/13 locally (pin set to 88 for the local check).
- **labels_meta:** the `defect` key (grader 1.3.2) is accepted beside `id`. Keyed entries win; the positional fallback fills only unnamed ids.
- **per_session:** `detected_pm3` is preferred over `detected` (`common.session_detected`) in BARE-1 and in the exact-dollar trim. Tested with both keys present and differing.
- **took_effect:** confirmed, with no change: null or absent → not_recorded (passes); {rule: bool} needs every value true. Note that an empty {} currently reads as fail.
- **Timing.** cProfile of a 200-study N = 12 run shows `_gs_cached`, the boundary recursion per distinct 0.01-rounded fraction tuple, at 91 % of the time. Breakdown: about 70 % in the bisection's `cross`, the rest in density propagation. Study simulation is about 7 %, which covers the k ≤ 30 session draws (≈ 4 %). The Δ solve is 3 % and `t_boundary` 2 %.
- **Cause of the slowdown:** calibration never re-simulates; it re-evaluates stored studies. But the 4,096-entry LRU on boundaries evicts once 3-look designs (N ≥ 12) produce thousands of (t1, t2) tuples. Each calibration step, the summarise pass and every sensitivity then recompute them.
- **Fix with identical output:** unbounded memo, shared prefix states ((t1) → (t1, t2) → (t1, t2, 1)), `phi_sf`/`phi_cdf` inlined with the same expressions, and a stderr progress line (`--quiet` silences it).
- **Byte-identical checks:**

| Case | Old | New |
|---|---|---|
| Mini fixture, N 6–14, 60 studies, sensitivities | 20.6 s | 13.1 s |
| 63 rows, c131, N = 12, 200 studies | 25 s | 15 s |
| 63 rows, c131, N = 12 and 14, 2,000 studies | 366 s | 162 s |

  All under load average 6 of 8 cores. The reads look and final outputs on the synthetic batch are also identical.
- **Estimate for the lead's job** (grid 6–14, 2,000 studies, eight sensitivities at a 3-look N): about 35–45 min on the old code and about 15–20 min on the new code, output identical. Further speed would need parallel precomputation of the fraction tuples (stdlib multiprocessing; still identical). It is not done.

DECISIONS (round 2):
- DECISION: keyed labels_meta entries (`defect`, then `id`) take precedence; the positional fallback never overwrites a keyed entry.
- DECISION: the exact-dollar trim reads `detected_pm3` like BARE-1, so both sides of every pair use the decision statistic.
- DECISION: boundary caches are unbounded (pure functions; tens of MB at the largest grid) and the recursion keeps its arithmetic and its order, so every output is byte-identical.

## Round 3 (Flatline SKP-003/SKP-006: NEGATIVE and the ordered table)
Delta `~/.cache/loa/cycle-132/patches/s1-d-r3.patch` (5 files, +111/−35). Unit tests 94 OK locally (stats 37, reads 35, power 16, judge_agree 6; +6). The AC-1 pin goes 117 → 123 for the branch. bats 13/13 locally (pin set to 94 for the local check).
- `reads.decide(delta, …)` now implements the lead's ordered table, with "z_yes crosses" read as |z_yes| ≥ b_yes (the YES boundary is two-sided; a literal z_yes ≥ b_yes can never hold when Δ̂ < 0). `PARTITION_LEGEND` is quoted in reads.md and power.md. `OUTCOMES` lists the seven decisions.
- **Correction of the premise:** round 2 never labelled a negative crossing SMALL. Its `z_yes ≥ b_yes` test was one-signed, so a significantly negative Δ̂ (z_no large) was labelled **NO**. The fix moves those cases from NO to NEGATIVE.
- **What changes, mini fixture** (seed 20261021, 60 studies, N 6/8/12/14, with sensitivities): only P(NO | Δ = 0) drops, by exactly the new P(NEGATIVE | 0).

| N | P(NO · 0) before | after | P(NEGATIVE · 0) |
|---|---|---|---|
| 6 | 0.3333 | 0.3167 | 0.0167 |
| 8 | 0.55 | 0.50 | 0.05 |
| 12 | 0.85 | 0.7667 | 0.0833 |
| 14 | — | — | 0 |

  Also changed: `power_no_at_reference` and every sensitivity's `power_no_at_null`; NEGATIVE columns were added. P(NEGATIVE | MDE) was 0 on this fixture. YES, SMALL, FUTILE, INCONCLUSIVE, type I, the calibrated constants, the planned SE, the clipped shares and the chosen/reference N are byte-for-byte unchanged. On this fixture N = 12 falls below the P(NO | 0) ≥ 0.80 threshold.
- **reads:** look.json and final.json on the synthetic batch are identical (no negative crossing in it); look.md and final.md gain the legend line. A real read changes only where a look's Δ̂ crosses negatively: NO becomes NEGATIVE.

DECISIONS (round 3):
- DECISION: "z_yes crosses" = |z_yes| ≥ b_yes for rules 1–4.
- DECISION: P(NO | 0) excludes NEGATIVE in the N-selection rule, as the table says. P(NO or NEGATIVE | 0), the round-2 figure, can be read beside it as no + negative.
- DECISION: rule 3 catches every remaining crossing with Δ̂ ≥ 0, so the table stays exhaustive at Δ̂ = 0.
