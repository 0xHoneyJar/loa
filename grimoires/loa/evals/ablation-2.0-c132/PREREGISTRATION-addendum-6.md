# Pre-registration addendum 6 — cycle-132

**Registered as:** `REGISTRATION-5.json`, together with addendum 5 at one pin (supersedes `REGISTRATION-4.json` sha256 `f2c0e8f99083a742318e9d3e2197d63d3ee8768fb20f2190325403b5a694e70c`). **Governing text:** `PREREGISTRATION.md` is unchanged; §10's sensitivity list gains one item, the class-9 grade gains telemetry, and the per-run cap of §3/§7 is USD 45.

## What the smoke found

smoke2's `a0_bare` run on review-r22 is `contaminated {pattern: network_egress}` for `curl … https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64` — a third-party tool download from a GitHub host. Under the registered class-9 rule (any GitHub egress by a fetcher) that is contamination and the cell is invalid; it is not answer-key retrieval. The rule applies to every arm alike, but a bare agent that installs tools from GitHub will lose cells this way more often than the pipeline arms, whose tooling the framework provides.

## What changed

1. **Telemetry:** class-9 grades record `contaminated.repo_named` (whether the flagged segment names the repository), `host` and `url`. The rule itself is unchanged: any GitHub egress still invalidates the cell in the primary.
2. **One more pre-registered sensitivity (§10, after "degraded and contaminated rows excluded vs the main filter"):** *class-9 non-repository egress re-included* — the primary Δ and recall per arm recomputed with cells whose only invalidity is a class-9 contamination with `repo_named = false` treated as valid (graded as the grader graded them), with the count of such cells per arm and group printed beside it.

3. **Per-run cap:** the batch driver's `--run-cap` rises from USD 30 to USD 45 for every arm. smoke2's `a1_full` run on review-r20 (5,810-line diff) ended `cap_failure` at USD 34.48 after 57 minutes with the dissent on both gates and the pipeline's fix rounds — the behaviour addendum 2 restored; the cycle-131 cap of 30 was set on 2,000–4,500-line PRs. The §7 overshoot bound becomes concurrency × run cap = 3 × 45 = USD 135; the cycle cap (USD 4,200) and the reservation rule are unchanged.

## Why this is a correction, not a design change

The primary estimand, its validity filter, the arms, k, groups, looks, boundaries, cap and seed are untouched; the addendum adds information the report must show so that an exclusion rule written against answer-key retrieval cannot silently decide the bare arm's recall through tool downloads. No graded Phase 1 row exists.
