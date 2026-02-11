# Eval Running Skill

Run evaluation suites against the Loa framework to detect regressions and benchmark skill quality.

## Usage

```bash
# Run framework correctness suite
/eval --suite framework

# Run regression suite
/eval --suite regression

# Run a single task
/eval --task constraint-proc-001-enforced

# Run all tasks for a skill
/eval --skill implementing-tasks

# Update baselines
/eval --suite framework --update-baseline --reason "Post-refactor re-baseline"
```

## How It Works

1. Parses arguments from the `/eval` command
2. Delegates to `evals/harness/run-eval.sh` with appropriate flags
3. Reports results via CLI or JSON output

## Execution

When invoked, translate the user's request into `run-eval.sh` arguments:

```bash
# Default: run all default suites
./evals/harness/run-eval.sh --suite framework --trusted

# With suite specified
./evals/harness/run-eval.sh --suite <suite> --trusted

# With task specified
./evals/harness/run-eval.sh --task <task-id> --trusted

# With skill filter
./evals/harness/run-eval.sh --skill <skill-name> --trusted

# Update baseline
./evals/harness/run-eval.sh --suite <suite> --update-baseline --reason "<reason>" --trusted

# JSON output for programmatic use
./evals/harness/run-eval.sh --suite <suite> --json --trusted
```

**Note**: `--trusted` flag is always added for local execution. In CI, the container sandbox provides isolation.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All pass, no regressions |
| 1 | Regressions detected |
| 2 | Infrastructure error |
| 3 | Configuration error |

## Constraints

- C-EVAL-001: ALWAYS submit baseline updates as PRs with rationale
- C-EVAL-002: ALWAYS ensure code-based graders are deterministic
