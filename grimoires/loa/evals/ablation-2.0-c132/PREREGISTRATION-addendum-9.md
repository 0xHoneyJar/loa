# Pre-registration addendum 9 — cycle-132

**Supersedes:** `REGISTRATION-7.json` sha256 `a31e594215454ec796ed2cde3d420f95050dd39cd1ea168b7599c48e981edcd7` (pin `9544948b6413fe838783a2f8daf4d7236efde800`). **Registered as:** `REGISTRATION-8.json`. **Governing text:** `PREREGISTRATION.md` is unchanged; §2's runtime-leakage statement and §4's validity rules are read with the two points below, and §10's sensitivity family gains the oracle rows.

## What smoke3 found

With the adapters pinned (addendum 5), smoke3's `a1_full` run on review-r14 — pr-14, the sprint-250 model-catalog and registry pull request — passed the mount probe, ran 32 minutes, and ended with no dissent voice on either gate: both envelopes `api_failure`, `voices_planned: 1` (the primary voice was never planned) and the companion `ProviderUnavailable exit 126`. The overlay had written the PR's `.claude/defaults/` model catalog and `.claude/scripts/` at the PR's head, so the pinned pipeline planned its dissent from a 2026-10-06 catalog and ran a PR-era wrapper. KF-050 is not about the adapters alone: the pipeline under test must run its own pinned runtime — adapters, defaults, scripts, hooks, skills, rules — in full.

## What changed

1. **Overlay:** every path under `.claude/` is left pinned (recorded as `overlay_excluded`); everything outside `.claude/` keeps the head-mode overlay; the PR's `.claude/` changes remain fully visible under `pr/head/`, `pr/base/` and `pr/head.diff`; `oracle_closed` judges the non-`.claude/` paths against the recorded exclusion.
2. **Sensitivity family (§10):** "oracle-exposed cells re-included" in three rows — form `read` only, form `diff`, and all oracle-exposed cells — each recomputing the primary Δ and recall per arm with those cells treated as valid (graded as graded), with counts per arm, group, PR and form.

## What this costs, stated plainly

For the registered PRs whose defects live in `.claude/` files (pr-11, 14, 15, 16, 19, 20, 21, 22, 27 touch `.claude/`; pr-20's ten defects all sit there), the sandbox copy of each such file is the pinned, fixed version. The grader's oracle detector marks a cell exposed when the agent diffs a PR path against the workspace copy or reads the workspace copy at lines present only in the fixed version near a defect's anchors; such a cell is invalid under §4 as registered. A pipeline arm that reads its own fixed skill file on a PR that fixed that skill file will register a `read` exposure every time: on those PRs the pinned pipeline cannot be measured without the detector excluding it, and the bare arm — which does not read `.claude/` — is not affected the same way. The primary therefore stands as registered and may lose those cells (reported in the 25 % guard, the missingness bounds and the per-PR exposure table); the new sensitivity rows show what the read would be with them. The alternative — running the PR-era framework so that the sandbox copy equals the PR's file — would measure a different, possibly broken pipeline on exactly those PRs (smoke2 and smoke3 showed both failure modes), which is the arm substitution the registration forbids.

## Why this is a correction, not a design change

The arm under test is the pinned pipeline, as registered; the estimands, k, groups, looks, boundaries, cap and seed are untouched; no graded Phase 1 row exists. The smoke rows decide nothing.

## Lesson recorded

A pull request that modifies the review pipeline's own runtime cannot be reviewed by that pipeline under a fully closed mount: either the pipeline runs the PR's broken version of itself or it runs the pinned version and can see the fix. The registered corpus holds nine such PRs because the unseen record fixtures are Loa's own recent sprints. The final report states this as the central limitation of the measurement on this corpus and reports every read with and without the affected cells.
