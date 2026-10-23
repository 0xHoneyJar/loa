# cycle-132 reads — mode `look`

Inputs: rows sha256 `6fdb2ee91876380f1e5caf38dbdb986be985dacb69424472720e45790309fa32`; grades sha256 `544ca47719369965ae3367794c0d8b84c0076f456a2be0ab8f502c7c74f294e8`; INPUTS.json sha256 `6954dbaf533cc6ed2d58ae9d5e59af3ec0ef95ee243a79151537134aa66012e0`; registration `614bcea50b1fa77a9486dcc5d30a73af474ae4734b0e380235dfd844d04feffa`; seed 20261021; interval t; validity rules c132.

## Looks

| look | PRs | defects | Δ | SE | t | z_yes | b_yes | z_no | b_no | CP yes | CP no | RCI | decision |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 | 78 | 0.2041 | 0.1022 | 0.0783 | 1.9966 | 1000.0000 | -1.0182 | 1000.0000 | 1.0000 | 0.0000 | [-102.0125, 102.4206] | CONTINUE (minimum information not reached (5 valid PRs < 6 or 78 labelled defects < 30)) |

Decision table (ordered, exhaustive; round 3). The YES boundary is two-sided: "z_yes crosses" means |z_yes| ≥ b_yes. 1. z_yes crosses and Δ̂ < 0 → NEGATIVE. 2. z_yes crosses and Δ̂ > 0 and z_no < b_no and RCI upper ≥ MDE → YES. 3. z_yes crosses and Δ̂ ≥ 0 and (z_no ≥ b_no or RCI upper < MDE) → SMALL. 4. z_yes does not cross and z_no ≥ b_no → NO. 5. neither crossed, final look → INCONCLUSIVE. 6. neither crossed, interim look: both conditional powers < 0.20 → FUTILE (non-binding), else CONTINUE.

Boundary constant 1.0000; MDE 0.1000; planned final SE 0.0286.

