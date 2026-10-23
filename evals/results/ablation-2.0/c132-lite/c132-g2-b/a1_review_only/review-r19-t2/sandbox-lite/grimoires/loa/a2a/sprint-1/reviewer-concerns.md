# Reviewer concerns — sprint-1 (PR: sprint-255, guard register / control arms / task kinds / path-scoped rules)

Context for the dissenting voice. The diff is `pr/head.diff`; cite `head/<path>:<line>` from `pr/head/`.

## What I verified by running the PR's own bats suites in scratch trees

- guard-yield.bats 11/11, guard-origins.bats 15/15 (GO-9 after generating guards.md), loa-status-guards 3/3
- validate-artifact-sprint-kinds 11/11, sprint-seams 11/12 (SEAMS-9 needs a fixture outside the diff)
- arms-report 7/7, eval-recall-grader RG-28, recall-baseline-freshness BF-10..13, execute-agent EA-11/12, arm-toggles 11/11, seed-corpus 6/6 (no-secrets.sh stubbed)
- Not run: run-arms.bats (needs sandbox.sh/grade.sh/fixtures), floor-snapshot (needs origin/main), rule-paths, prompt-budget PB-10, cycle-ratio (ran: 6/6 pass)

## Concerns I want challenged or confirmed

1. `guard-yield.sh` sources `.claude/scripts/lib/heredoc-classifier.sh` inline (`source "$HEREDOC_LIB" 2>/dev/null`). If the sourced file, or what it sources (the fence in lib-only mode), calls `exit`, guard-yield.sh ends with status 0 and writes nothing. Reproduced with a classifier that sources a fence lacking `BDB_LIB_ONLY` handling. Is a subshell probe warranted?
2. `execute-agent.sh` karpathy toggle: `jq '(.constraints // []) |= map(...)'` errors ("Invalid path expression") when `.constraints` is absent; the failure is swallowed inside `apply_toggles || exit 2` and leaves `constraints.json.tmp` in the sandbox.
3. Tasks review-pr-11..18 / audit-pr-11..18 and README reference record fixtures, labels, manifests, record-pairs.tsv and an updated SHA256SUMS that are not in this change set; the review-recall suite globs `tasks/review-recall/**/*.yaml`.
4. `run-arms.sh`: transport retry gated on `ex_rc -eq 1`; `aggregate_status` lock dir not cleaned on crash (gives up silently after ~5 s); `cleanup` kills only direct job subshells; `$(find …)` unquoted.
5. `seed-corpus-from-record.sh` REDACTED counter counts the same secret in head.diff, base/ and head/ copies.
6. `implementing-tasks/SKILL.md` app zone permission read → read-write with no mention in the PR.
7. `check-prompt-budget.yml` and prompt-budget.bats comments changed to 160,000 / 114,688 B while the tool is not in the diff.
8. `review-kind-01.yml` relies on the `.yml` extension to stay out of the `*.yaml` suite glob.
9. Anything in the yield heuristics (burst ≥10/min, cwd under TMPDIR, prose classes) that would misclassify real catches or let a session hide its own blocks (LOA_AUDIT_REPLAY is an unauthenticated env flag).
10. validate_sprint_kinds: any regression for existing dated plans/tests; J-heuristic false positives.
