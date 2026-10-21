# Pre-registration addendum 7 — cycle-132

**Supersedes:** `REGISTRATION-5.json` sha256 `6ad2e34e503aa10c425c9ec95f6477aa8b5e4099029128645dca83b0625b9557` (pin `426c6c3d15f69a3b927356709dfbdd87bc3d9e22`). **Registered as:** `REGISTRATION-6.json`. **Governing text:** `PREREGISTRATION.md` is unchanged; §4's contamination classes are read as scoped by task type for the `suite_path` class, as addendum 4 already reads them for `hidden`.

## What the smoke found

smoke2's `a1_full` run on review-r23 — pr-23, the pull request that created the frozen suite root `grimoires/loa/evals/ablation-2.0/tasks/` — is `contaminated {pattern: suite_path}` on an audit-phase command that extracted the grader's python body from the PR's own file and named the suite path the PR's code names. The `suite_path` class catches a build-task agent reading the frozen suite's expectations from its sandbox; a review-catch sandbox holds no suite root, so the class has no object there, and five registered PRs name that path in their content.

## What changed

Grader 1.3.7: the `suite_path` class, like `hidden` (addendum 4), is applied only to task types whose sandbox holds the thing it protects (build, bug-fix, refactor); review-catch grades record both skipped classes. Every other class is unchanged. Smoke rows graded before this addendum decide nothing and are not re-rowed; the affected run's re-grade is reported.

## Why this is a correction, not a design change

The class never had an object in review-catch sandboxes; the estimands, arms, k, groups, looks, boundaries, cap and seed are untouched; no graded Phase 1 row exists.

## Lesson recorded

Three contamination and leak guards written for build tasks (the arm-id guard, `hidden`, `suite_path`) fired on review-catch content because the registered corpus contains the pull requests that built the evaluation harness itself. The smoke exists to find exactly this before a graded row; the final report lists the addenda and the per-class contamination counts by task type.
