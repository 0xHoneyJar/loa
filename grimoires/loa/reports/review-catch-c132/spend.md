# cycle-132 spend meter (Sprint 271)

`evals/harness/spend.sh --since 2026-10-21T00:23:00Z --cap 4200 --runs grimoires/loa/reports/ablation-2.0/runs.jsonl --runs evals/results/ablation-2.0/runs.jsonl --runs evals/results/ablation-2.0/*/rows.jsonl --json` → `spend.json` beside this file (PREREGISTRATION §7 scope).

| item | USD |
|---|---|
| cap (PREREGISTRATION §7, binding) | 4200.00 |
| run rows since kickoff (arms, smokes, blind sessions; deduplicated by run_id) | 3272.72 |
| host cost ledger since kickoff (dissents, Flatline, judge-side calls) | 47.39 |
| cycle meter total | 3320.12 |
| headroom under the cap | 879.88 |
| reserves still held (reproduction rerun, dissents) | 250.00 |

Run rows counted: 271 (deduplicated 2); ledger rows: 47.
