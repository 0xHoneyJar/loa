# cycle-132 spend meter (Sprint 271, after the reproduction's live rerun)

`evals/harness/spend.sh --since 2026-10-21T00:23:00Z --cap 4200 --runs grimoires/loa/reports/ablation-2.0/runs.jsonl --runs evals/results/ablation-2.0/runs.jsonl --runs evals/results/ablation-2.0/*/rows.jsonl --runs <reproducer scratch>/live/runs.jsonl --json` → `spend.json` beside this file (PREREGISTRATION §7 scope; the live rerun's rows are tracked as `reproduction/live-runs.jsonl`).

| item | USD |
|---|---|
| cap (PREREGISTRATION §7, binding) | 4200.00 |
| run rows since kickoff (arms, smokes, blind sessions, the reproduction's live rerun; deduplicated by run_id) | 3331.90 |
| host cost ledger since kickoff (dissents, Flatline, judge-side calls) | 47.39 |
| cycle meter total | 3379.29 |
| headroom under the cap | 820.71 |
| reserves still held (dissents) | 250.00 |

Run rows counted: 284 (deduplicated 2); ledger rows: 47.
