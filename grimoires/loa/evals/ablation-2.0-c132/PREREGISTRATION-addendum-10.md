# Pre-registration addendum 10 — cycle-132

**Supersedes:** `REGISTRATION-8.json` sha256 `614bcea50b1fa77a9486dcc5d30a73af474ae4734b0e380235dfd844d04feffa` (pin `fbd36a0c9880b244af08133013f3b6959b085c94`). **Registered as:** `REGISTRATION-9.json`. **Governing text:** `PREREGISTRATION.md` is unchanged. **Scope:** the analysis module only (`evals/analysis/c132`); the pipeline and harness pin stays `fbd36a0c…` for every batch — every Phase 1 row before and after this addendum carries the same `source_commit`.

## What look 1 showed

Look 1 (2026-10-22T06:35Z, G1 complete: 60 rows, 5 valid PRs, 8 valid pairs, 78 defects) read **CONTINUE** by the registered minimum-information rule and nothing else was decided. Reading its output against the registered text found two places where the analysis module still implements the pre-Flatline draft of the design rather than the hashed text:

1. **Positive control (§8).** `positive_control()` used only the first group's pairs (registered: every group's pairs), called a pass on exposure in one open run (registered: ≥ 2), labelled any negative point estimate `void` (registered: void only when the 90 % cluster-t interval lies entirely below 0; a point estimate ≤ 0 whose interval covers 0 is "not demonstrated", and so is exposure in exactly one run), had no "not demonstrated" label (it printed "inconclusive"), and no "fewer than 3 eligible pairs → not exercised" rule. At look 1 the labels coincide in substance (Δ̂ = 0.0000, interval [−0.116, 0.116], exposure in 2 runs: module "inconclusive" = registered "not demonstrated"); at the final read the old code could have voided every read on a negative point estimate whose interval covers 0, which the registered text forbids.
2. **Co-reads at looks (§5).** The look mode printed the look table alone; §5 says the pipeline-independent Δ, the recall per arm stratified by `label_source` and `review_driven`, and the cost-matched Δ (exact-dollar trim plus the dollar-matching table) are "reported beside the primary at every look and at the final".

## What changed

`reads.py`: `positive_control()` implements the §8 table verbatim over every registered group (saturation exemption kept; fields `rule`, `n_exposed_open_runs`, `eligible_pairs`, `consequence`, and `outcome_pre_addendum_10` = the label the superseded code would print, so both reads stand side by side); the look mode adds a `co_reads` block (pipeline-independent, stratified, cost-matched) rendered under its own heading. Tests cover every outcome row, the inclusion of later groups, the superseded label, and an unchanged look decision with the co-reads present. `decide`, `look_table`, `stats.py`, `common.py`, the guard, the sensitivities, the grader and the runner are untouched.

## Both reads

Look 1's original outputs stay at `reports/ablation-2.0/c132-looks/look-1/`; the same 60 rows re-read with the amended module land at `c132-looks/look-1-amended/` and the two are reported together (identical decision, guard and primary figures by construction; the positive-control label and the co-reads are the difference).

## Why this is a correction, not a design change

The hashed text is the commitment; the module is its implementation. Nothing about estimands, arms, k, groups, looks, boundaries, cap or seed moves, and the change was taken at a look that could not decide anything (5 valid PRs < 6) and whose positive-control labels agree under both readings.
