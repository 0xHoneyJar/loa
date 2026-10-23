# Pre-registration addendum 3 — cycle-132

**Supersedes:** `REGISTRATION-2.json` sha256 `857669e7c80edac886eb54ce00ae29dfe11be011dcbf34e80db70c73b20eb51c` (pin `5af8b80e5b2b6defdb896a74d777f01947e91cac`). **Registered as:** `REGISTRATION-3.json`. **Governing text:** `PREREGISTRATION.md` is unchanged; §7's meter definition is made true by this addendum.

## What the first real rows found

§7 defines the cycle meter as every ledger row since the kickoff plus every run row whose `started` is at or after it. The runner writes its rows to the results root's `runs.jsonl` (`evals/results/ablation-2.0/runs.jsonl`); `spend.sh` read only the tracked copy `grimoires/loa/reports/ablation-2.0/runs.jsonl` and the per-batch `evals/results/ablation-2.0/*/rows.jsonl` files. The first two real smoke rows (USD 17.30 at 2026-10-21T09:15Z) were therefore invisible to the spend gate that derives each batch's `--max-usd` from the cap.

## What changed

`spend.sh` reads the live results-root `runs.jsonl` among its defaults (deduplicated by `run_id` with the tracked copy, the larger cost kept). Nothing else: the cap, its scope statement, the reservation rule and the overshoot bound are as registered.

## Why this is a correction, not a design change

The meter now computes the quantity §7 already defines. No graded Phase 1 row exists (the smoke rows decide nothing; the first smoke batch is superseded). The pin moves to the commit holding the fix; every other bound input is unchanged.

## Reporting

The final report names addenda 1–3 beside the registration hashes and prints the meter at every batch launch from the batch manifests' `spend_gate` records.
