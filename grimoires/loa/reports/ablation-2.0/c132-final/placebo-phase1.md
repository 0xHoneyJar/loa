# cycle-132 reads — mode `placebo`

Inputs: rows sha256 `522e1980a1cca46bd3132c83abba8512b7b847acb951d8d98e9e7f7b3f7e41ad`; grades sha256 `57eea383b6c1a4bef8b13e4b80bdcc00b4912e6ef0c3df47d61af6b9e5e69c1c`; INPUTS.json sha256 `17725093540e47b7c14f362a14536c84eec523b41df4b497af11c9170e7abb62`; registration `c9d98acb2668dabb4e7a9e3942bc6f1d880997cfe1e3e8c5cbc25cf42906eeb9`; seed 20261021; interval t; validity rules c132.

Rows by registration: 13cbd850f825: 72, 614bcea50b1f: 68.

Registration chain (current first): `c9d98acb2668` → `380f7a3656d3` → `05fa23fe8c69` → `9a0dda4bcedc` → `2f6909d23efc` → `13cbd850f825` → `ae0b1da61447` → `614bcea50b1f` → `a31e59421545` → `6205eaf5f1f0` → `6ad2e34e503a` → `f2c0e8f99083` → `573041811eae` → `857669e7c80e` → `277a6effd863` → `7d5200119966`.

Contrast `a1_full` − `a0_bare_matched`; FAIL.

Pass rule: |mean Δ| < 0.03 (bias) and ≤ 0.08 of the 95 % t intervals exclude 0 (calibration).

| shuffles | resamples | share excluding 0 | mean Δ | Δ q05 / q50 / q95 | diag: mean abs Δ | diag: share (t) | diag: share (percentile) |
|---|---|---|---|---|---|---|---|
| 200 | 1000 | 0.1000 | -0.0005 | -0.0971 / 0.0057 / 0.0857 | 0.0501 | 0.1000 | 0.1000 |

Primary read on the unshuffled pairs (descriptive):

| unshuffled | Δ 0.0971 | 95 % [-0.0936, 0.2879] | 90 % [-0.0575, 0.2517] | SE 0.0843 | PRs 10, pairs 16, defects 175 | diag 95 % percentile [-0.0682, 0.2647] |
