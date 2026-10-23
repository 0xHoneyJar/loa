# Security analysis working file — sprint-1 audit (PR: sprint-262 ablation-row.sh 1.2 / ablation-report.py 1.2.0), 2026-10-22

Scope: pr/head.diff (5 files). `pr/head/evals/.run/audit.jsonl` is a hook artifact of the review session, not part of the PR — N/A.

## Sources (untrusted or semi-trusted input)
| # | Source | file:line | Trust | Status |
|---|--------|-----------|-------|--------|
| S1 | runs.jsonl rows (arm, task_id, trial, suite_version, defects_missed) | ablation-report.py:328-367 | harness output, partially validated | CONFIRMED (→ K1, K2, K3) |
| S2 | MANIFEST.json (suite_version, smoke, arm_map) | ablation-report.py:370-402 | harness output | SAFE (schema major + batch checks) |
| S3 | STATUS.json beside MANIFEST.json | ablation-report.py:1007-1049 | harness output, unvalidated shape | PARTIAL (→ K4) |
| S4 | grade.json under <batch>/<arm>/<task>-t<n> | ablation-report.py:1070-1079 | grader output | CONFIRMED (→ K1, K2) |
| S5 | grade.json recall.missed / regressions.final_green | ablation-row.sh:410-414 | grader output | SAFE (type-checked; id grammar unchecked, pre-existing reader) |
| S6 | CLI --suite-version | ablation-report.py:857 | operator | PARTIAL (string not normalised, HIGH-002) |

## Sinks
| # | Sink | file:line | Status |
|---|------|-----------|--------|
| K1 | os.listdir / json.load on a path built from row arm, task_id | ablation-report.py:1054-1075 | CONFIRMED — LOW-002 (CWE-22, read-only, grader_version only) |
| K2 | sorted() key int()/str mix on grader_version | ablation-report.py:1081-1082 | CONFIRMED — HIGH-001 (uncaught TypeError), LOW-001 (ValueError on Unicode digits) |
| K3 | version_order int(k) after isdigit; partition primary choice | ablation-report.py:835-861, 1611 | CONFIRMED — HIGH-002, HIGH-003, LOW-001, LOW-005 |
| K4 | markdown table cells | ablation-report.py:1156 | CONFIRMED — LOW-003 (trials_planned raw) |
| K5 | report.md / report.json write | ablation-report.py:1640-1647 | SAFE (symlink refused, pre-existing) |
| K6 | yq subprocess on suite path | ablation-report.py:308 | N/A (pre-existing, operator path, argv list) |
| K7 | jq programs in ablation-row.sh (--validate, row build) | ablation-row.sh:165-170, 410-414 | SAFE (data via --slurpfile/--argjson, no string interpolation) |

## Deferred
- none
