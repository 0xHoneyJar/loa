# Sprint 269 Review Feedback — round 1

**Reviewer:** Fable 5.1 lead (reviewing-code contract; dissent via `adversarial-review.sh --type review` run 1: gpt-5.5-pro primary + claude-headless companion, both voices succeeded, envelope `adversarial-review.json`, 0 rejected payloads)
**Date:** 2026-10-21
**Scope:** `346dbb87..2ab4ca72` — the code of Sprint 269 (harness, graders, analysis, suites, tests, CHANGELOG, READMEs, pre-registration; fixtures, reports and planning documents excluded from the dissent diff), as reported in `reviewer.md`.
**Verdict:** CHANGES_REQUIRED — two high findings (a false-contamination path in grader class 9; the cap meter undercounting real spend), four medium, two low. None touches the pre-registered design; all are code corrections in files the sprint changed, so the registration is rebuilt after the fixes land (before any Phase 1 row).

## Findings

| # | Sev | Where | Finding | Fix owner |
|---|---|---|---|---|
| F1 | HIGH | `evals/harness/ablation-grade.sh` class 9 (`network_egress`), python clause ~1986 (DISS-001, DISS-C-001) | The python egress test runs on the raw Bash value, heredoc bodies included, across the whole value rather than per logical line, with class 9 evaluated before the class-7 exemption. A reviewer writing prose through `cat > review.md <<'EOF' … EOF` that mentions python, requests and github.com is marked contaminated and the cell is excluded; three unrelated commands on separate lines combine into one hit. Confirmed by reading the code. | C round 3 |
| F2 | HIGH | `evals/harness/spend.sh` (DISS-002, DISS-C-002) | The cap meter sums `cost_usd`; row 1.5's `cost_usd` on a matched cell holds only the valid sessions and an ordinary row's earlier attempts live only in `all_spend_usd`. Real spend is missing from the binding cap. Confirmed (`ablation-row.sh` `cost_valid` vs `all_spend`). | C round 3 |
| F3 | MEDIUM | `evals/harness/run-ablation.sh` took-effect plumbing (DISS-003) | An empty took-effect JSON passes the jq step with no output; the empty temp file replaces took.json and the row's `took_effect` reads null, which the analysis treats as "not recorded" (passes). The fail-closed rule of round 1 does not cover the empty case. | C round 3 |
| F4 | MEDIUM | `evals/harness/annotation-packets.sh` review_driven detector ~293 (DISS-C-004) | The citation regex caps the extension at 6 characters (the same cap grader 1.3.3 removed), so feedback citing `.loa.config.yaml.example` or `Dockerfile.ablation` never tags its hunks review_driven. The v2 key's `review_driven` field feeds the pre-registered pipeline-independent read; affected fixtures are re-merged after the fix. | A round 1; lead re-merge |
| F5 | MEDIUM | `evals/harness/ablation-grade.sh` `key_set_root()` and `recall-vs-defects.sh` set_root (DISS-C-005) | Only `manifests/c131/` keys are re-rooted; grading against the v1 key (a pre-registered sensitivity) mis-resolves the corpus sums, the v1 snapshot and the fixture head. | B round 3 |
| F6 | MEDIUM | `evals/harness/ablation-row.sh` sessions_valid (DISS-C-007) | The row counts a session valid only when cell.json marks it valid and its pipeline.json parses with a BARE phase; the grader's union trusts cell.json alone. A valid session with an unreadable pipeline.json is graded into the union but dropped from the row, which can read `infrastructure_error` while carrying a recall. | C round 3 |
| F7 | LOW | grader and runner headers (DISS-C-006) | The cell.json contract comment omits `attempts` / `attempt_costs`, which the runner writes and the grader reads. Documentation mismatch only. | C round 3 |
| F8 | LOW | `evals/harness/ablation-grade.sh` EGRESS_TOOL / EGRESS_GIT (DISS-C-003) | curl/wget/git/fetch match anywhere on a line rather than in command position, so `grep -rn curl … \| grep github.com` reads as egress. Folded into F1's per-logical-line, command-position rule. | C round 3 |

Lead observations, not sprint defects: `tests/unit/` 6,946 ok / 36 not ok — the 36 are the 10 pre-existing alias-resolution and reprice cases (reproduced on origin/main; bead bd-tgn04) and the 26 `post-merge-publication.bats` cases that fail in setup on this host (`git tag v1.0.0: fatal: no tag message?`, KF-034 recurrence recorded). Nothing under `.claude/` changed in this sprint.

## What is sound

- The blind-annotation chain (packets → sessions → κ → adjudication → merge → freeze) is deterministic and leak-checked; the v2 key is internally consistent (every anchor in range; the reference self-check passes 42/42 on grader 1.3.3).
- The matched-cell runner, union grader, row 1.5 and report 1.4 are covered by the RAB/union/row bats cases; the registration gates (pin, image, resume, spend) work end to end in the dry runs.
- The analysis module's textbook checks (OBF boundaries, REML, κ, permutation) and byte-identical outputs hold through three rounds; the power run re-derived identically after the memo change.
- The placebo FAIL, the N decision and the Flatline integration are recorded as taken, not hidden.

## Required before approval

F1–F8 fixed with the tests named in the round messages; grader bumped to 1.3.4; the affected fixtures' `hunks.meta.json` rebuilt and re-merged (F4) with the corpus refrozen; the image self-check re-run (42/42); the registration rebuilt at the new pin with a NOTES heading; `evals/tests/` green on the touched files.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":2},"excluded":0,"sprint_id":"sprint-269","ts":"2026-10-21T07:05:00Z"} -->
