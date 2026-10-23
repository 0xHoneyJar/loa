# Pre-registration addendum 4 — cycle-132

**Supersedes:** `REGISTRATION-3.json` sha256 `573041811eae6c47bb4d485f2c456637ee0af0a6b094f3734485142031d42f97` (pin `51a55a98d97c2fe56c69a0e5da4bac93abe23c7e`). **Registered as:** `REGISTRATION-4.json`. **Governing text:** `PREREGISTRATION.md` is unchanged; §4's contamination classes are read as scoped by task type for the `hidden` class.

## What the superseded smoke found

The superseded smoke's `a1_full` run on review-r23 (pr-23, the sprint-259 pull request whose own code implements the grader's hidden-test contamination check) graded recall 0.846 with the dissent present on both gates and was marked `contaminated {pattern: hidden}` on a heredoc in which the reviewer quoted the PR's code about the word "hidden". The grader's `hidden` class exists for build, bug-fix and refactor tasks, whose sandbox carries `hidden/` tests; a review-catch sandbox carries none, so for the registered corpus — five of whose fourteen PRs are about the evaluation harness itself — the class can only produce false exclusions of the pipeline arms.

## What changed

Grader 1.3.6: the `hidden` contamination class is applied only to task types whose sandbox holds hidden tests; review-catch grades record the skipped class. Every other contamination class (outside path, git history, repository name with its PR-content exemption, network egress, …) is unchanged. The smoke rows graded before this addendum are re-rowed with the new grader (`run-ablation.sh --rerow`); their transcripts are untouched.

## Why this is a correction, not a design change

The class never had an object in review-catch sandboxes; applying it there excluded valid cells of the arm under test on exactly the PRs that mention hidden tests. The estimands, arms, k, groups, looks, boundaries, cap and seed are untouched; no graded Phase 1 row exists (the smoke decides nothing).

## Reporting

The final report names addenda 1–4 beside the registration hashes and prints the contamination classes applied per task type.
