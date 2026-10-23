# Security analysis working file — sprint-1 (review-r26), 2026-10-22

Scope: `pr/head.diff` (5 files). Trust model: `runs.jsonl` rows, `MANIFEST.json`, `STATUS.json`, `grade.json` and the suite file are operator-supplied inputs read by an offline CLI; rows are produced by `ablation-row.sh` from agent-run output and can be hand-edited or come from older writers, so they are **semi-trusted**. The report writes only `--out` / `--json`.

## Sources (untrusted → semi-trusted)

| # | Source | Where | Trust | Status |
|---|--------|-------|-------|--------|
| S1 | row `suite_version` (number/string/null) | `head/evals/harness/ablation-report.py:825-861` | semi-trusted | CONFIRMED (HIGH-001, LOW-001, LOW-002) |
| S2 | row `arm` | `head/evals/harness/ablation-report.py:1054` | semi-trusted | CONFIRMED (MED-001) |
| S3 | `grade.json` `grader_version` | `head/evals/harness/ablation-report.py:1066-1082` | untrusted (any file on disk) | CONFIRMED (HIGH-002) |
| S4 | `STATUS.json` fields | `head/evals/harness/ablation-report.py:1013-1050` | untrusted | PARTIAL (shape-tolerant; LOW-003 rendering) |
| S5 | `--suite-version` argv | `head/evals/harness/ablation-report.py:857` | operator | CONFIRMED (LOW-002) |
| S6 | `grade.json` `recall.missed`, `regressions.final_green` (row writer) | `head/evals/harness/ablation-row.sh:410-414` | untrusted | SAFE (type-guarded in jq; validated at `:165-170`) |
| S7 | suite YAML via `yq` subprocess | `head/evals/harness/ablation-report.py:308` | operator path, argv list | SAFE (pre-existing; no shell) |

## Sinks

| # | Sink | Where | Status |
|---|------|-------|--------|
| K1 | `os.listdir` / `open` on a path built from S2 | `:1054-1070` | CONFIRMED (MED-001; CWE-22 read-only) |
| K2 | `sorted()` key over S3 | `:1081-1082` | CONFIRMED (HIGH-002; uncaught TypeError) |
| K3 | `int(k)` in `version_order` over S1 | `:840` | CONFIRMED (LOW-001; uncaught ValueError) |
| K4 | Markdown table cells from S4 / row `task_id` | `:1156`, `:1106`, `:1269` | CONFIRMED by reading (LOW-003) |
| K5 | `write_out` | `:1641-1647` | SAFE (symlink refused, only two paths) |
| K6 | `json.load` of STATUS/grade | `:1024`, `:1069` | SAFE (OSError/ValueError caught; non-dict tolerated) |

## Second-order flows

- S1 → `partition()` grouping → every decision/H1/A4 figure (HIGH-001: a `None` key pools rows across versions).
- S2 rows already listed as "not run by the suite" still reach K1 (the batch record iterates every row of the batch).

## Deferred / out of scope

- `evals/tests/ablation-row.bats` not executed: its fixture tree `evals/tests/fixtures/ablation-runs/` is not in the PR; the jq programs were reviewed by reading and by `--validate` over all eleven generated fixture sets (all valid, `present` included: 90 rows).
- The real suite `evals/suites/ablation-2.0.yaml` is outside the PR; a synthesized JSON suite with the same arm ids and rules keys was used (`/tmp/audit-r26/repo`).
