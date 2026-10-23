# Reviewer concerns — sprint-1 (PR: sprint-263 closed review-catch mount, grader 1.3.0, dissent line anchors, budget_scale)

Phase 2 notes for the cross-model dissenter. Lines are pr/head/ line numbers.

1. evals/graders/recall-vs-defects.sh — BASH_HDR[0] (`^(\s*)(?:function\s+)?NAME\s*\(\)\s*\{?`) has an optional brace and no end anchor, so Python method calls inside bash heredocs (`flush()`, `out.pop()`, `ds.sort()`, `EXEMPT_BUF.clear()`) are read as bash function headers. Demonstrated: a defect at recall-vs-defects.sh:300 is credited by a citation at :480 (180 lines away), and ablation-grade.sh:2320 by :2540, under rule pm3_or_same_function. The corpus fixtures are Loa PRs full of Python-in-bash heredocs.
2. evals/harness/lib/sandbox-mount.sh cmd_check clause (d) — `rev-list --all == [base]` and `fsck --unreachable` empty: any agent-side `git add` / `git stash` / `git commit` in the sandbox fails took-effect oracle_closed, which run-ablation rows as infrastructure_error and pauses the arm. Conflates agent behaviour with mount integrity.
3. evals/harness/ablation-grade.sh repo_name_exempt — unit is the backtick span; a bare `` `0xHoneyJar/loa` `` is a substring of every fixture line holding the token, so it is always exempt once the fixture mentions the repo anywhere.
4. recall-vs-defects.sh MD_HDR matches `#` comment lines inside fenced code blocks in markdown; CLOSE_ONE one-liner detection fires on a header line that ends in `}` (e.g. `foo() { x=${y}`).
5. ablation-grade.sh corpus_sha256 — read_regular refuses symlinks, then a plain open() re-reads the path (TOCTOU / symlink follow on the second read).
6. ablation-grade.sh grade_recall positions(): v1-only ids map to v1 positions that may collide with current-manifest position labels.
7. sandbox-mount.sh clause (b) pre-launch: any non-answer file byte-equal to a pinned answer-path version (duplicate files in .claude/) refuses the trial.
8. adversarial-review.sh _adv_conf_budget_scale: a yq failure reading the tag sets CONF_BUDGET_SCALE_SET=true (envelope then names a scaling the config never wrote).
