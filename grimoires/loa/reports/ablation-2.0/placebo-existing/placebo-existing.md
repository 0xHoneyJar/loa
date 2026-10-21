# cycle-132 reads — mode `placebo`

Inputs: rows sha256 `4818a6dfbc7672a34396f16ad6205f140cbb100e26fce71a90aaf89fe755f5b0`; grades sha256 `0b8c8d8f84df9f96940893ad1bcbdab592a76805830206be19668aa1c3794c0f`; INPUTS.json sha256 `13bc8ba2b97679ba133d5eefc58546f2d525cd86019a70b5c500f0c70d72b00a`; registration `unregistered`; seed 20261021; interval t; validity rules c131.

Contrast `a1_full` − `a0_bare`; FAIL.

Pass rule: |mean Δ| < 0.03 (bias) and ≤ 0.08 of the 95 % t intervals exclude 0 (calibration).

| shuffles | resamples | share excluding 0 | mean Δ | Δ q05 / q50 / q95 | diag: mean abs Δ | diag: share (t) | diag: share (percentile) |
|---|---|---|---|---|---|---|---|
| 200 | 1000 | 0.0950 | -0.0090 | -0.1443 / -0.0050 / 0.1149 | 0.0622 | 0.0950 | 0.1700 |

Primary read on the unshuffled pairs (descriptive):

| unshuffled | Δ 0.2836 | 95 % [0.1402, 0.4269] | 90 % [0.1712, 0.3960] | SE 0.0558 | PRs 6, pairs 21, defects 201 | diag 95 % percentile [0.1149, 0.3429] |
