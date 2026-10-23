# Pre-registration addendum 18 — cycle-132

**Supersedes:** `REGISTRATION-16.json` sha256 `d360e0da896d543ad271ed28c3af1e54a3cbe1d874c696f40476396545f9902e` (pipeline pin `fbd36a0c9880b244af08133013f3b6959b085c94`). **Registered as:** `REGISTRATION-17.json`. **Governing text:** `PREREGISTRATION.md` is unchanged. **Scope:** `evals/analysis/c132/reproduce.sh` only — the live-rerun step. No read, row, grade, estimand, filter, boundary, seed or figure changes; no model is called by the change itself.

## What the first reproduction showed

From the fresh clone of the stage-1 record (`b15e546e`) every recorded grade, row and read reproduced byte for byte (433/433 session, 84/84 cell, 56/56 union grades; 140/140 rows; INPUTS.json and the four read files). The DEC-0812 live rerun was then refused by `run-ablation.sh` before any model call: its DEC-0435 hard gate requires the image self-check log, which the Sprint 270 batch driver passed explicitly as `--self-check-log grimoires/loa/reports/ablation-2.0/self-check-c132.txt` (tracked) while `reproduce.sh --live-sample` omitted the flag, so the runner looked for the cycle-130 default under the gitignored `a2a/sprint-259/`, which the record does not hold.

## What changed

`reproduce.sh --live-sample` passes `--self-check-log grimoires/loa/reports/ablation-2.0/self-check-c132.txt` and a `--pre-registration-ref` naming REGISTRATION-15 and the pin, exactly as the batch driver did, and raises the batch cap from USD 80 to 110 because the runner's conservative plan estimate for the three cells is USD 104 (the recorded cost was 50.27; the spend comes from the reproduction reserve and the contingency). The sample, arms, trial count, registration, pin and comparison rule of DEC-0812 are unchanged. Per the sprint's re-trigger rule, the record gains a stage-1b commit on top of stage 1 carrying this change, and the reproducer re-runs the whole reproduction and the live sample from a fresh clone of it.
