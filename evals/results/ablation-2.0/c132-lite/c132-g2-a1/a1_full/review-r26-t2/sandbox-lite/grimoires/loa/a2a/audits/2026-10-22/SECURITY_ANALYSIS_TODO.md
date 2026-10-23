# Security analysis working file — sprint-1 audit (PR: sprint-262 ablation-row.sh 1.2 / ablation-report.py 1.2.0)

Scope: pr/head.diff (5 files; evals/harness/ablation-report.py, evals/harness/ablation-row.sh, two bats suites, the fixture generator).
Trust model (assumption): runs.jsonl rows, MANIFEST.json and STATUS.json are harness-written (operator trust); grade.json
sits in the per-run directory beside the agent-under-test's workspace (semi-trusted); the suite file is operator-owned.

## Sources (untrusted → semi-trusted inputs)
| # | Source | file:line | Trust | Status |
|---|--------|-----------|-------|--------|
| S1 | runs.jsonl row fields `suite_version`, `arm`, `batch`, `task_id`, `trial` | head/evals/harness/ablation-report.py:328-368 | harness | CONFIRMED (suite_version, arm unvalidated beyond type) |
| S2 | STATUS.json beside MANIFEST.json | head/evals/harness/ablation-report.py:1007-1048 | harness | PARTIAL (trials_planned raw) |
| S3 | grade.json `grader_version` per run directory | head/evals/harness/ablation-report.py:1069-1079 | semi-trusted | CONFIRMED (sort crash) |
| S4 | `--suite-version` CLI arg | head/evals/harness/ablation-report.py:857 | operator | SAFE (Fail on no match) |
| S5 | grade.json `recall.missed`, `regressions.final_green` (row writer) | head/evals/harness/ablation-row.sh:410-414 | semi-trusted | SAFE (typed in jq, validated under --validate) |

## Sinks
| # | Sink | file:line | Status |
|---|------|-----------|--------|
| K1 | `sorted(gv.items(), key=…int(p)…)` | ablation-report.py:1081-1082 | CONFIRMED — TypeError/ValueError, uncaught, exit 1, no report |
| K2 | markdown headings/lines interpolating `v` (suite_version) | ablation-report.py:1441, 1533, 1539, 1541, 885 | CONFIRMED — forged bold H1 lines reproduced |
| K3 | `os.path.join(d, r["arm"])` + listdir/open | ablation-report.py:1054-1073 | CONFIRMED — read outside batch tree (listed rows still walked) |
| K4 | table cell `e['trials_planned']` raw | ablation-report.py:1157 | CONFIRMED — `|` splits the row |
| K5 | `version_order()` `int(k)` on `k.isdigit()` | ablation-report.py:839-840 | CONFIRMED — '²' → ValueError, uncaught |
| K6 | `write_out` of report.md/report.json | ablation-report.py:1640 | SAFE (operator paths) |
| K7 | jq row build in ablation-row.sh (new fields) | ablation-row.sh:410-414 | SAFE |

## Dismissed
- DISS-C-005 IndexError in the defect union: every vector of one task has length `task_defects[task]` (ablation-report.py:541, 545, 553) — not reachable.
- Rows whose batch has no manifest are listed and excluded from the batch record (trials_rowed counts manifest batches only) — by design.
- `--help` sed range (ablation-row.sh:123) stops one line before "Tested by" — pre-existing in base (2,84p had the same offset); not introduced.
