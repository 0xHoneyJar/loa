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

## Architecture Decisions

### ADR-001: JSONL for Result Storage

**Context**: Eval results need persistent storage for trend analysis, CI comparison, and audit trails. Options considered: SQLite, PostgreSQL, JSONL, CSV.

**Decision**: Append-only JSONL (JSON Lines) files with `flock`-based atomic writes.

**Consequences**: No binary dependencies beyond `jq`. Git-friendly audit trail (human-readable diffs). `flock` provides atomicity for parallel task execution. Trade-off: no indexed queries — acceptable since result sets are small (hundreds of rows, not millions) and `jq` handles filtering efficiently. If scale demands change, JSONL can be migrated to SQLite without schema changes since each line is self-describing JSON.

### ADR-002: mikefarah/yq (Go Binary)

**Context**: Task YAML parsing requires a `yq` implementation. Two major variants exist: mikefarah/yq (Go, single binary) and kislyuk/yq (Python, wraps jq).

**Decision**: mikefarah/yq v4.40.5 (Go binary, pinned version).

**Consequences**: Zero Python runtime dependency for the harness. Single static binary simplifies container images and CI setup. Consistent behavior across platforms (no Python version variance). Trade-off: Go binary is larger (~10MB) than the Python wrapper. The version is pinned in `Dockerfile.sandbox` and CI (`mikefarah/yq@v4.40.5`) to prevent breaking changes from upstream.

### ADR-003: Shell-Based Harness

**Context**: The eval harness orchestrates task loading, sandboxing, grading, and reporting. Could be implemented in Node.js (project runtime), Python (data tooling), or Bash (system scripting).

**Decision**: Pure Bash (4.0+) with `jq` for JSON processing.

**Consequences**: Zero additional runtime required — Bash and coreutils are universally available in CI environments and containers. Exit code contract (`0`=pass, `1`=fail, `2`=error) maps naturally to shell semantics. Graders are themselves shell scripts, so the harness speaks the same language. Trade-off: complex data transformations (Wilson intervals) shell out to `python3 -c` inline, and string handling requires more care than in higher-level languages.

## Multi-Model Evaluation

### The `model_version` Field

Every eval result includes a `model_version` field that records which AI model produced the output being graded. For framework evals (no agent execution), this is `"none"`. For agent evals, it captures the model identifier (e.g., `"claude-opus-4-6"`, `"claude-sonnet-4-5-20250929"`).

### Model Version Skew Detection

When comparing results against baselines, `compare.sh` detects **model version skew** — the baseline was recorded with one model version, but the current run uses a different one. When skew is detected, all comparison results are marked `"advisory": true`, meaning regressions are reported but do not block CI. This prevents false failures when model upgrades change behavior.

### Per-Model Baseline Tracking

The baseline YAML format includes a top-level `model_version` field. This enables future per-model baselines: `framework.claude-opus-4-6.baseline.yaml` vs `framework.claude-sonnet-4-5.baseline.yaml`. The current implementation uses a single baseline per suite, with skew detection as the safety valve.

### Forward Reference: Multi-Model Routing

The eval framework's `model_version` tracking provides empirical data for multi-model routing decisions. When multiple models are available (via Hounfour / permission-scape architecture), eval results answer: "Which model performs best on which task categories?"

For example, if regression evals show Model A scores 95% on code generation tasks but 70% on documentation tasks, while Model B shows the inverse, a routing layer can direct tasks to the optimal model. The eval sandbox provides the measurement infrastructure; the routing layer (future work) provides the decision engine.

### Early Stopping

Multi-trial agent evals support **early stopping** via raw pass rate projection. After each trial, the harness computes the best-case pass rate assuming all remaining trials pass. If this best case still indicates regression (pass rate < baseline - threshold), remaining trials are skipped. Early-stopped tasks are marked with `"early_stopped": true` in results. This optimization is transparent to graders and has no effect on single-trial framework evals. Raw pass rate (not Wilson CI) is used for the early stopping decision to avoid false positives from wide confidence intervals at small sample sizes; the full Wilson CI comparison is applied at final comparison time.
