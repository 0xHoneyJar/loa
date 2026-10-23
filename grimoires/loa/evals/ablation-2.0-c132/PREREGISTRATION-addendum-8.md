# Pre-registration addendum 8 — cycle-132

**Supersedes:** `REGISTRATION-6.json` sha256 `6205eaf5f1f0571f6d5868bd0a9c695a8580978a539ce61f8cfb343c8568ad3e` (pin `3d6f6a40c61dc64d42a27787b42b8f39b1902e3e`). **Registered as:** `REGISTRATION-7.json`. **Governing text:** `PREREGISTRATION.md` is unchanged; §4's class 7 (repository name) is read with the PR-native exemption below, and §10's sensitivity list reads "contaminated cells re-included, per class" in place of addendum 6's single class-9 row.

## What the smoke found

smoke2's `a0_bare` run on review-r27 — pr-27, the sprint-263 grader pull request whose code implements the repository-name check and carries the literal repository token — is `contaminated {pattern: repo_name}` on a `grep -rn '0xHoneyJar/loa' head/` over the PR's own head tree. The agent was reading PR content that names the repository; nothing left the sandbox (class 9 governs that) and the token was in front of it in `pr/`, so its presence in the command is not evidence of prior exposure.

## What changed

Grader 1.3.8: when the repository token occurs in the PR content (recorded as `repo_token_pr_native`), a read-only local command (grep, rg, cat, sed, awk, head, tail, less, find, ls, wc, sort, diff) whose path arguments resolve inside `pr/` or the sandbox and that carries no URL, fetcher or egress host is exempt from class 7, with the exemption recorded (`contamination_exempt`, class `repo_name_pr_native`). Fetches and URLs are unchanged (class 9 and class 7 as registered); the existing class-7 exemption for a Bash line identical to a PR line stays.

## Also: the contamination sensitivity, per class

The smoke excluded cells on both arms for several classes — class 9 (a tool download), class 7 (the grep above), and `outside_path` (KF-046: a bare agent extracted the PR's grader code into a scratch directory and ran it; the code's own path literals sit in a heredoc fed to the interpreter). The primary filter stays as registered: every contaminated cell is invalid. The §10 sensitivity of addendum 6 becomes a family: for each contamination class observed (outside_path, git_history, repo_name, network_egress with and without the repository named, suite_path, hidden, other), the primary Δ and recall per arm recomputed with cells whose only invalidity is that class treated as valid, plus one row re-including every class at once, each with the count of such cells per arm, group and class.

## Why this is a correction, not a design change

Class 7 exists to flag awareness of or reaching for the upstream repository; a command that reads the repository token out of the PR under review shows neither. The estimands, arms, k, groups, looks, boundaries, cap and seed are untouched; no graded Phase 1 row exists. The smoke rows graded before this addendum decide nothing; the affected run's re-grade is reported.

## Lesson recorded

With this addendum, four guards written for other task types or for upstream reach (the arm-id guard, `hidden`, `suite_path`, the class-7 repository token) have each been corrected for pull requests whose content is the evaluation harness itself. The final report lists the per-class contamination and exemption counts by arm and PR.
