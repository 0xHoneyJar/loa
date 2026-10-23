# Pre-registration addendum 1 — cycle-132

**Supersedes:** `REGISTRATION.json` sha256 `7d520011996628de0d4be270b0648bcfaa1b3a0fc922092f385ebaa9525d02ad` (pin `622d0043d34af6359ea44cd4f71aab00ae7a5e34`). **Registered as:** `REGISTRATION-1.json` (its `supersedes` field names the predecessor). **Governing text:** `PREREGISTRATION.md` is unchanged; this addendum records one runner correction under §12.

## What changed

`evals/harness/pipeline-run.sh`, the sandbox-wide arm-id leak guard. The guard refused any sandbox in which the arm id string occurred anywhere. Seven of the fourteen registered fixtures are the cycle-130/131 pull requests that built the ablation arms (pr-22, 23, 24, 25, 26, 27, 28), so their own diffs and PR descriptions name `a1_full`, `a0_bare` and `a1_review_only`, and the closed mount's generated review brief repeats that PR text. The first smoke batch (2026-10-21T08:14Z) therefore ended `infrastructure_error` within seconds on those fixtures. The correction: arm ids that occur in the PR's own content (`pr/PR.md`, `pr/head.diff`, `pr/base`, `pr/head`) are recorded as PR-native (`arm_ids_pr_native` in the arm evidence) and a hit on such an id inside PR-derived files (anything under `pr/` and the mount-generated files built from PR text) no longer refuses; every other hit refuses as before, and the strict leak scan of the task brief and every phase prompt is unchanged. A PR whose text names every arm tells the agent nothing about which arm it runs as.

## Why this is a correction, not a design change

No graded row exists: the aborted smoke batch produced only `infrastructure_error` rows with no cost (kept at `evals/results/ablation-2.0/c132-smoke-aborted-20261021T0814Z/` for the record). The estimands, arms, k, groups, looks, boundaries, cap and seed are untouched; the pin moves to the commit holding the runner fix, and the analysis tree, corpus sums and suite manifest hashes are re-bound unchanged except for the pin.

## Reporting

The final report names this addendum beside the registration hashes. Because no original output exists, there is no original-versus-amended read to show; the aborted batch directory is the only artefact of the superseded registration.
