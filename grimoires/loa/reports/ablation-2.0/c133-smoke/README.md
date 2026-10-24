# cycle-133 Sprint 274 Task 3.5 — the home-scope smoke

`suite.yaml` is `evals/suites/ablation-2.0.yaml` with exactly one change: the `a1_full` arm gains `mount_mode: home-scope`
(sdd.md C-10; sprint.md Task 3.5 "set `mount_mode: home-scope` on the smoke batch's suite copy"). It is produced with
`yq '(.arms[] | select(.id == "a1_full")).mount_mode = "home-scope"'` and is JSON-equal to the suite file otherwise
(comments dropped). The smoke task is `grimoires/loa/evals/ablation-2.0/smoke/smoke-review-c133/` (pr-20, label set v2).
The smoke batch is launched by the lead's driver (`~/.cache/loa/cycle-133/scripts/smoke-3.5.sh <pin>`): egress block up,
pin self-check (recorded as `../self-check-c133-s274.txt`), one `a1_full` trial under the egress guard, egress block down.
Smoke rows decide nothing (DEC-0428); the batch lives under `evals/results/ablation-2.0/` (gitignored) and the evidence
that matters (self-check, took-effect clauses (a)–(g), grade under grader 1.5, spend, denials) is copied here.
