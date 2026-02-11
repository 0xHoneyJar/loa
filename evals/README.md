# Loa Eval Sandbox

Benchmarking and regression framework for the Loa agent development system. Ensures framework changes don't degrade agent behavior through deterministic, code-based evaluation.

## Quick Start

```bash
# Run framework correctness suite (local, trusted mode)
./evals/harness/run-eval.sh --suite framework --trusted

# Run via /eval command
/eval --suite framework

# Run a single task
./evals/harness/run-eval.sh --task constraint-proc-001-enforced --trusted

# JSON output for CI
./evals/harness/run-eval.sh --suite framework --json --trusted
```

## Requirements

- **Platform**: Linux (tested on Debian/Ubuntu)
- **Bash**: >= 4.0
- **Required tools**: jq, yq (mikefarah/yq), git, timeout, mktemp, sha256sum

### Tool Installation

```bash
# Debian/Ubuntu
apt install jq coreutils git
pip install yq  # or: brew install yq

# macOS (via Homebrew)
brew install jq yq coreutils git
```

## The `--trusted` Flag

Local execution requires the `--trusted` flag to acknowledge that eval code runs in your local environment without container isolation. In CI, container sandboxing provides isolation automatically.

```bash
# Local (requires --trusted)
./evals/harness/run-eval.sh --suite framework --trusted

# CI (uses container sandbox)
./evals/harness/run-eval.sh --suite framework --sandbox-mode container
```

## How to Write Tasks

Tasks are YAML files in `evals/tasks/<category>/`:

```yaml
id: my-new-task
schema_version: 1
skill: implementing-tasks
category: framework          # framework | regression | skill-quality | e2e
fixture: loa-skill-dir       # Directory in evals/fixtures/
description: "What this task checks"
trials: 1
timeout:
  per_trial: 60
  per_grader: 30
graders:
  - type: code
    script: file-exists.sh   # Script in evals/graders/
    args: ["path/to/check"]
    weight: 1.0
difficulty: basic
tags: ["framework"]
```

**Rules**:
- `id` must match filename (without `.yaml`)
- `fixture` must exist in `evals/fixtures/`
- `graders[].script` must exist in `evals/graders/` and be executable
- For `skill-quality` and `e2e` tasks, `prompt` field is required

## How to Write Graders

Graders are bash scripts in `evals/graders/`:

```bash
#!/usr/bin/env bash
# my-grader.sh
# Args: $1=workspace, $2..N=task-specific args
# Exit: 0=pass, 1=fail, 2=error
set -euo pipefail

workspace="$1"
# ... check something ...

echo '{"pass":true,"score":100,"details":"Check passed","grader_version":"1.0.0"}'
exit 0
```

**Contract**:

| Aspect | Requirement |
|--------|-------------|
| Input | `$1` = workspace path, `$2..N` = args from task YAML |
| Output | JSON: `{"pass": bool, "score": 0-100, "details": "string", "grader_version": "1.0.0"}` |
| Exit 0 | Pass |
| Exit 1 | Fail |
| Exit 2 | Error (grader broken) |
| Determinism | No network, no LLM, no time-dependent logic |

**Standard graders**:

| Grader | Purpose | Args |
|--------|---------|------|
| `file-exists.sh` | Check files exist | `<path> [path...]` |
| `tests-pass.sh` | Run test suite | `<test-command>` |
| `function-exported.sh` | Check named export | `<name> <file>` |
| `pattern-match.sh` | Grep pattern | `<pattern> <glob>` |
| `diff-compare.sh` | Diff against expected | `<expected-dir>` |
| `quality-gate.sh` | Loa quality gates | `[gate-name]` |
| `no-secrets.sh` | Secret scanning | (none) |
| `constraint-enforced.sh` | Verify constraint | `<constraint-id>` |
| `skill-index-validator.sh` | Validate skill index | `<check-type>` |

## How to Run Locally

```bash
# Full framework suite
./evals/harness/run-eval.sh --suite framework --trusted

# With verbose output
./evals/harness/run-eval.sh --suite framework --trusted --verbose

# Single task for debugging
./evals/harness/run-eval.sh --task golden-path-config-exists --trusted --verbose
```

## How to Update Baselines

Baselines are committed YAML files in `evals/baselines/`. Updates require a reason:

```bash
# Update from current results
./evals/harness/run-eval.sh --suite framework --update-baseline --reason "Initial baseline" --trusted

# Review the diff
git diff evals/baselines/

# Commit as PR for CODEOWNERS review
git add evals/baselines/
git commit -m "chore(eval): update framework baseline — initial baseline"
```

## Exit Codes

| Code | Meaning | CI Behavior |
|------|---------|-------------|
| 0 | All pass, no regressions | Check passes |
| 1 | Regressions detected | Check fails (blocks merge) |
| 2 | Infrastructure error | Check neutral |
| 3 | Configuration error | Check fails |

## Directory Structure

```
evals/
├── README.md              # This file
├── harness/               # Eval infrastructure
│   ├── run-eval.sh        # Main orchestrator
│   ├── validate-task.sh   # Task YAML validator
│   ├── sandbox.sh         # Sandbox provisioning
│   ├── grade.sh           # Grader orchestrator
│   ├── compare.sh         # Baseline comparison
│   ├── report.sh          # CLI report
│   └── tests/             # Harness tests
├── graders/               # Code-based graders
│   ├── file-exists.sh
│   ├── tests-pass.sh
│   ├── ...
│   └── allowlist.txt      # Permitted grader commands
├── fixtures/              # Test environments
│   └── loa-skill-dir/     # Framework testing fixture
├── tasks/                 # Eval task definitions
│   ├── framework/         # Framework correctness tasks
│   └── regression/        # Regression tasks (Sprint 2)
├── suites/                # Suite definitions
│   └── framework.yaml
├── baselines/             # Committed baselines
│   └── framework.baseline.yaml
└── results/               # Run results (gitignored)
    └── eval-ledger.jsonl
```
