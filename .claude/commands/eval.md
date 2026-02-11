# Eval Command

## Purpose

Run evaluation suites to benchmark Loa skill quality and detect regressions.

## Invocation

```
/eval                                    # Run default suites (framework + regression)
/eval --suite framework                  # Run framework correctness suite
/eval --suite regression                 # Run regression suite
/eval --task constraint-proc-001         # Run single task
/eval --skill implementing-tasks         # Run all tasks for a skill
/eval --update-baseline --reason "..."   # Update baselines
```

## Agent

Launches `eval-running` from `skills/eval-running/`.

See: `skills/eval-running/SKILL.md` for full workflow details.

## Arguments

| Argument | Description | Required | Default |
|----------|-------------|----------|---------|
| `suite` | Named suite: `framework`, `regression`, `skill-quality` | No | `framework` |
| `task` | Single task ID | No | - |
| `skill` | Filter tasks by skill name | No | - |
| `update_baseline` | Update baselines from results | No | false |
| `reason` | Reason for baseline update | With update_baseline | - |
| `compare` | Run ID to compare against | No | - |

## Outputs

| Path | Description |
|------|-------------|
| `evals/results/run-*/results.jsonl` | Per-trial results |
| `evals/results/eval-ledger.jsonl` | Append-only result ledger |
| CLI report | Terminal-formatted summary |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All pass, no regressions |
| 1 | Regressions detected |
| 2 | Infrastructure error |
| 3 | Configuration error |

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| "Missing required tools" | jq, yq, etc. not installed | Install missing tools |
| "Local execution requires --trusted" | Running without sandbox | Add --trusted flag |
| "Suite not found" | Invalid suite name | Check evals/suites/ |
| "No valid tasks" | All tasks failed validation | Fix task YAML files |
