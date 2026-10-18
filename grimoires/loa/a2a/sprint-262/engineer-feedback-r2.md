# Sprint 262 review — round 2 (cycle-130 Sprint 5) — CHANGES_REQUIRED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-18 (2026-10-18T11:31:36Z)
**Implementation:** the round-1 fix `caf55440` (report 1.2.1, implementer R4, `reviewer-r4.md`) on top of `82c5cd7d`; round 1 archived as `engineer-feedback-r1.md`.
**Dissent:** `adversarial-review.json` (run 2 of ≤ 3, `--type review`, the fix diff `82c5cd7d..caf55440`, 716 lines; run 1 archived as `adversarial-review-r1.json`): two voices (`gpt-5.5-pro`, `claude-headless`; 2 of 2), five findings — 1 BLOCKING + 4 ADVISORY; four defects (DISS-001 and DISS-C-001 are one), all accepted; none rejected. None touches a shipped number: the real rows all carry integer `suite_version`s and agree with their manifests' `arm_map`, and the report regenerated under 1.2.1 is identical on every decision key (R4's proof, repeated by the lead on commit).
**Local checks:** `ablation-report.bats` 39/39; `evals/tests/` 435 cases on `caf55440` (the run completes at the close); the shipped `report.json` identical on `h1`, `a4`, `decisions`, `sensitivity`, `arms`, `exclusions`, `cap_failures`, `cuts`, `by_suite_version` before and after 1.2.1; the batch-record tallies now read 132 / 24 / 9 directories with the inline grader versions the blind re-grade confirmed.

## Round 1 items
- **MEDIUM-1 closed** (type-stable tally key; never-fatal wrapper around the STATUS part, the tally and the rendering — with one gap below). **MEDIUM-2 closed** (one run directory per row by `run_id`, the highest `-r<k>` sibling when rerun; `priority-p1` 132, missing 0). **MEDIUM-3 closed** (`version_key()` keys every real number; `--suite-version` normalised; AR-38). **LOW-1 closed** (version-less rows that would be listed go to the primary version's never-decided list with the reason; a version-less scored row still exits 2; AR-39).

## Round 2 findings (on the fix)

### MEDIUM-1 — version-less listed rows bypass the manifest `arm_map` provenance check (DISS-001 + DISS-C-001; CONFIRMED)
`partition()` accepts a version-less row through `list_reason()`, which omits the `arm_map` check `_classify` runs before listing; a row whose manifest names another arm is now listed instead of exiting 2 as a provenance conflict (DEC-0407). Latent for the shipped rows (every row agrees with its manifest). **Required:** the same check before partitioning (or inside `list_reason()` for both call sites); a case with a conflicting version-less row → exit 2.

### LOW-1 — version-key types differ across JSON emitters (DISS-C-002)
Only `primary_suite_version` goes through `version_value()`; `by_suite_version[N].suite_version`, `h1.suite_version`, `a4.suite_version` and `batches[].suite_version` would emit a string for `2.1`; AR-38 does not pin the type. **Required:** one emitter for every version key; type assertions in AR-38.

### LOW-2 — the batch record is still fatal in one call (DISS-C-003)
`recs = batch_record(mans, rows)` sits outside the `try` that guards the rendering, so an exception in the grouping or manifest lookup aborts the report the header calls never fatal. **Required:** the whole computation degrades to "Not rendered (…)" with a note; a case with a broken manifest shape → exit 0 with the decision sections present.

### LOW-3 — run-directory attribution edges (DISS-C-004)
`run_dir_of()` compares the formatted `<task>-t<trial>` string (a zero-padded `rc-01-t01` no longer matches where 1.2.0 compared the trial numerically) and, when rerun directories exist without the row's `run_id` or a grade and the base directory is absent, counts the row as missing although directories exist. **Required:** numeric trial comparison; the highest rerun directory as the last fallback (`n/a` without `run_dirs_missing`); `run_dirs_missing` documented as rows with no attributable directory; cases for both edges.

## What was verified as sound in round 2
The 1.2.1 rules as stated in `reviewer-r4.md`, read against the code: the version-key canonicalisation (`2`, `2.0`, `"2"` → `"2"`; `2.1` → `"2.1"`; booleans and blanks absent), the stable order, the per-row directory resolution (run_id match → highest graded rerun → base), the type-stable tally key, the listing of version-less rows only when `list_reason()` would list them; AR-36 … AR-39 fail on 1.2.0 (R4 swapped scripts to prove it); the shipped report's decisions unchanged.

## Verdict

CHANGES_REQUIRED — fix MEDIUM-1 and LOW-1 … LOW-3 as report 1.2.2 with tests that fail before and pass after and the shipped report identical on every decision key; dissent run 3 is the audit, so round 3 is verified by the lead directly and by the audit dissent.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":1,"low":3},"excluded":0,"sprint_id":"sprint-262","ts":"2026-10-18T11:31:36Z"} -->
