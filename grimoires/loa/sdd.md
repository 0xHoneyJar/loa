# SDD: Eval Sandbox — Benchmarking & Regression Framework for Loa

**Version**: 1.1.0
**Status**: Draft (revised per Flatline Protocol review)
**Author**: Architecture Phase (architect)
**PRD**: grimoires/loa/prd.md (v1.1.0)
**Issue**: [loa #277](https://github.com/0xHoneyJar/loa/issues/277)
**Date**: 2026-02-11

---

## 1. Executive Summary

The Eval Sandbox is an evaluation and benchmarking framework for Loa that measures whether changes to skills, protocols, and configurations improve or degrade agent behavior. It introduces a YAML-based task definition system, fixture repositories for reproducible test environments, a deterministic code-based grader framework, JSONL result storage with baseline comparison, a `/eval` CLI command, and GitHub Actions CI integration with structured PR comments.

The architecture follows loa-finn's ground-truth verification patterns: deterministic graders with exit code contracts, property-based testing with pass/fail fixtures, and JSON-first output for programmatic analysis. The system is built in four phases: framework correctness → regression protection → skill quality → e2e workflows, with Phases 1-2 as MVP.

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    ENTRY POINTS                                 │
│  /eval CLI skill  ·  GitHub Actions workflow  ·  /run --eval    │
├────────────────────────────────────────────────────────────────┤
│                    EVAL HARNESS (run-eval.sh)                   │
│  Suite loader → Task validator → Trial scheduler → Reporter     │
│  ↕ Orchestrates the full eval pipeline                          │
├──────────┬─────────────┬──────────────┬───────────────────────┤
│  TASK    │  SANDBOX    │   GRADER     │    RESULT             │
│  LAYER   │  LAYER      │   LAYER      │    LAYER              │
│          │             │              │                        │
│  YAML    │  Fixture    │  Code-based  │  JSONL ledger          │
│  loader  │  cloner     │  graders     │  Baseline YAML         │
│  Schema  │  Dep setup  │  Composite   │  Comparison engine     │
│  valid.  │  Isolation  │  Timeouts    │  Flake detector        │
├──────────┴─────────────┴──────────────┴───────────────────────┤
│                    REPORTING LAYER                               │
│  CLI report  ·  PR comment (gh)  ·  JSONL metrics               │
└────────────────────────────────────────────────────────────────┘
```

### 2.2 Component Inventory

| Component | Type | Action | Path |
|-----------|------|--------|------|
| eval-running skill | New | Create | `.claude/skills/eval-running/` |
| eval command | New | Create | `.claude/commands/eval.md` |
| run-eval.sh | New | Create | `evals/harness/run-eval.sh` |
| sandbox.sh | New | Create | `evals/harness/sandbox.sh` |
| grade.sh | New | Create | `evals/harness/grade.sh` |
| report.sh | New | Create | `evals/harness/report.sh` |
| compare.sh | New | Create | `evals/harness/compare.sh` |
| pr-comment.sh | New | Create | `evals/harness/pr-comment.sh` |
| validate-task.sh | New | Create | `evals/harness/validate-task.sh` |
| 8 standard graders | New | Create | `evals/graders/*.sh` |
| 5 fixture repos | New | Create | `evals/fixtures/*/` |
| Suite definitions | New | Create | `evals/suites/*.yaml` |
| Task definitions | New | Create | `evals/tasks/**/*.yaml` |
| Baseline files | New | Create | `evals/baselines/*.baseline.yaml` |
| CI workflow | New | Create | `.github/workflows/eval.yml` |
| constraints.json | Existing | Amend | `.claude/data/constraints.json` |
| CLAUDE.loa.md | Existing | Amend | `.claude/loa/CLAUDE.loa.md` |
| golden-path.sh | Existing | Extend | `.claude/scripts/golden-path.sh` |
| .loa.config.yaml | Existing | Extend | `.loa.config.yaml` |

### 2.3 Data Flow

```
Developer modifies skill
        │
        ▼
   /eval (CLI)  ─── or ─── GitHub Actions (CI)
        │                        │
        ▼                        ▼
   Load suite YAML          Load suite YAML
        │                        │
        ▼                        ▼
   For each task:            For each task:
   ┌──────────────┐         ┌──────────────┐
   │ Validate YAML │         │ Validate YAML │
   │ Clone fixture │         │ Clone fixture │
   │ Setup deps    │         │ Setup deps    │
   │ Run N trials  │         │ Run 1 trial   │
   │ Grade each    │         │ Grade each    │
   │ Store JSONL   │         │ Store JSONL   │
   └──────────────┘         └──────────────┘
        │                        │
        ▼                        ▼
   Compare baselines         Compare baselines
        │                        │
        ▼                        ▼
   CLI report               PR comment + check status
```

---

## 3. Component Design

### 3.1 Eval Harness (`evals/harness/run-eval.sh`)

The main orchestrator. Follows loa-finn's `quality-gates.sh` pattern: composable scripts with exit code contracts and JSON output.

**Interface**:
```bash
# Run all default suites
./evals/harness/run-eval.sh

# Run specific suite
./evals/harness/run-eval.sh --suite regression

# Run single task
./evals/harness/run-eval.sh --task implement-simple-function

# Run tasks for a specific skill
./evals/harness/run-eval.sh --skill implementing-tasks

# Update baselines
./evals/harness/run-eval.sh --update-baseline

# Compare runs
./evals/harness/run-eval.sh --compare <run-id-1> <run-id-2>

# JSON output for CI
./evals/harness/run-eval.sh --suite regression --json
```

**Exit codes** (follows loa-finn pattern):
| Code | Meaning | CI Behavior |
|------|---------|-------------|
| 0 | All tasks pass, no regressions | Check passes |
| 1 | Regressions detected | Check fails (blocks merge) |
| 2 | Infrastructure error (sandbox/grader failure) | Check neutral (does not block) |
| 3 | Configuration error (harness broken) | Check fails |

**Pipeline**:
```
INIT → LOAD_SUITE → VALIDATE_TASKS → EXECUTE_TRIALS → GRADE → COMPARE → REPORT → DONE
```

Each step writes to a run directory: `evals/results/run-{timestamp}-{hash}/`

### 3.2 Task Schema & Validation (`evals/harness/validate-task.sh`)

**Schema Version 1**:
```yaml
# Required fields
id: string              # Unique task identifier (kebab-case)
schema_version: 1       # Schema version for compatibility
skill: string           # Target skill name (must exist in .claude/skills/)
category: enum          # framework | regression | skill-quality | e2e
fixture: string         # Path relative to evals/fixtures/
description: string     # Human-readable description

# Execution
trials: integer         # Number of trials (default: from suite config)
timeout:
  per_trial: integer    # Seconds (default: 120)
  per_grader: integer   # Seconds (default: 30)

# Agent invocation (required for skill-quality and e2e categories)
prompt: string          # Explicit prompt/instruction for the agent
                        # (replaces implicit 'input' for agent tasks)
input: object           # Skill-specific structured input parameters

# Grading
graders:                # At least one required
  - type: code          # code (future: model)
    script: string      # Path relative to evals/graders/
    args: [string]      # Optional arguments (from ALLOWLIST only)
    weight: float       # For composite scoring (default: 1.0)

# Optional
difficulty: enum        # basic | intermediate | advanced
tags: [string]          # Arbitrary tags for filtering
model:
  pin: boolean          # Record model version in results
baseline:
  pass_rate: float      # Expected pass rate (0.0-1.0)
  model_version: string # Model version used for baseline
  recorded_at: string   # ISO date
```

**Agent Invocation Contract** (IMP-002):

For `skill-quality` and `e2e` category tasks, the harness executes the agent:

1. **Prompt Assembly**: Combine `task.prompt` + `task.input` + fixture context into agent input
2. **Workspace Handoff**: Agent receives sandbox path as working directory
3. **Output Capture**: All tool calls, outputs, and timing captured to JSONL transcript
4. **Timeout**: Per-trial timeout enforced. Agent process killed on timeout.
5. **Retry**: Infrastructure errors retry once. Agent failures do not retry.

```
Harness → Clone fixture → Set working dir → Assemble prompt
       → Invoke agent (claude --prompt <assembled> --cwd <sandbox>)
       → Capture transcript → Run graders → Record result
```

**Validation rules** (checked before any execution):
1. `id` matches filename (without `.yaml`)
2. `schema_version` is supported (currently: 1)
3. `skill` exists in `.claude/skills/`
4. `fixture` directory exists in `evals/fixtures/`
5. All `graders[].script` files exist and are executable
6. `trials` > 0 if specified
7. `timeout.per_trial` and `timeout.per_grader` > 0 if specified

**Validation output** (JSON):
```json
{
  "valid": true,
  "task_id": "implement-simple-function",
  "warnings": [],
  "errors": []
}
```

### 3.2.1 Suite YAML Schema (IMP-001)

Suites define which tasks run together, with default settings.

```yaml
# evals/suites/regression.yaml
name: regression
description: "Regression protection — catch breakage before merge"
version: 1

# Task inclusion
tasks:
  include:
    - "tasks/regression/**/*.yaml"    # Glob patterns
  exclude:
    - "tasks/regression/experimental-*"

# Execution defaults (overridable per task)
defaults:
  trials: 3
  timeout:
    per_trial: 120
    per_grader: 30
  composite_strategy: all_must_pass

# CI behavior
ci:
  gate_type: blocking         # blocking | async | scheduled
  min_trials: 3               # Minimum trials for regression classification
  regression_threshold: 0.10  # 10% drop triggers regression

# Ordering (optional)
execution_order: parallel     # parallel | sequential
concurrency: 4                # Max parallel tasks
```

**Required fields**: `name`, `version`, `tasks.include`
**Validation**: Suite YAML validated at load time. Unknown fields rejected.

### 3.3 Sandbox Manager (`evals/harness/sandbox.sh`)

Provides isolated environments for eval task execution.

**Interface**:
```bash
# Create sandbox from fixture
sandbox.sh create --fixture fixtures/hello-world-ts --trial-id run-abc-trial-1
# Returns: /tmp/loa-eval-run-abc-trial-1/

# Destroy sandbox
sandbox.sh destroy --trial-id run-abc-trial-1

# Destroy all sandboxes for a run
sandbox.sh destroy-all --run-id run-abc
```

**Local mode** (developer machine):
1. Create temp directory: `mktemp -d /tmp/loa-eval-XXXXXX`
2. Copy fixture contents (not symlink — isolation)
3. Initialize git repo in sandbox (for skills that use git)
4. Set controlled environment: `TZ=UTC`, `LC_ALL=C`, `HOME=/tmp/loa-eval-home`
5. Install dependencies per fixture strategy (prebaked: copy, offline-cache: install from cache, none: skip)
6. Record environment fingerprint: runtime versions (node, python, bash), OS, architecture → `env-fingerprint.json`
7. Return sandbox path

**CI mode** (GitHub Actions — container-based from MVP):
> Flatline SKP-001 integration: Container sandboxing moved from Phase 3 to Phase 2 (MVP) for CI security.

1. Build container image from `evals/harness/Dockerfile.sandbox` (pinned base image with exact runtime versions)
2. Mount fixture as read-write volume at `/workspace`
3. No network namespace (`--network none`)
4. Resource limits: `--memory 2g --cpus 2 --pids-limit 256`
5. Read-only root filesystem except `/workspace` and `/tmp`
6. No secrets in environment
7. Controlled toolchain: exact Node.js, Python, Bash versions pinned in Dockerfile
8. npm lifecycle scripts disabled: `--ignore-scripts` enforced
9. Run grader inside container
10. Record environment fingerprint for reproducibility

**Cleanup**: Always destroy sandbox after trial completes (success or failure). Use trap for signal handling.

**Grader command allowlist** (SKP-001):

Only the following commands may be invoked by graders. `validate-task.sh` rejects tasks with grader args containing commands outside this list:

```
node, npx, python3, pytest, bash, sh, grep, diff, jq, git, test, [, [[
```

Custom commands must be registered in `evals/graders/allowlist.txt`.

**Dependency strategies**:
```yaml
# fixture.yaml
name: hello-world-ts
language: typescript
runtime: node-20
runtime_version: "20.11.0"     # Exact version (SKP-002: pin toolchains)
dependency_strategy: prebaked   # prebaked | offline-cache | none
test_command: "npx jest --ci"   # Explicit test command (SKP-002: no auto-detect)
```

| Strategy | Description | When |
|----------|-------------|------|
| `prebaked` | `node_modules/` or `venv/` committed in fixture | Default. Fastest. Deterministic. |
| `offline-cache` | `package-lock.json` + cached tarballs, `npm ci --offline --ignore-scripts` | When `node_modules` is too large |
| `none` | No dependency installation | Shell-only fixtures, Loa skill fixtures |

### 3.4 Grader Framework (`evals/harness/grade.sh` + `evals/graders/`)

**Grader orchestrator** (`grade.sh`):
```bash
# Run all graders for a task in a sandbox
grade.sh --task-yaml <path> --workspace <sandbox-path> --timeout 30

# Output: JSON array of grader results
```

**Grader contract** (every grader must follow):

| Aspect | Contract |
|--------|----------|
| Input | `$1` = workspace path, `$2..N` = args from task YAML |
| Output | JSON to stdout: `{"pass": bool, "score": 0-100, "details": "string", "grader_version": "1.0.0"}` |
| Exit code | 0 = pass, 1 = fail, 2 = error (grader itself broken) |
| Timeout | Enforced by `grade.sh` via `timeout(1)`. Timeout → exit code 2. |
| Determinism | No network, no LLM, no time-dependent logic, no randomness |
| Side effects | Read-only access to workspace. No writes outside workspace. |

**Standard grader library**:

| Grader | Purpose | Args | Score Logic |
|--------|---------|------|-------------|
| `file-exists.sh` | Check file(s) exist | `<path> [path...]` | 100 if all exist, 0 if any missing |
| `tests-pass.sh` | Run test suite | `<test-command>` | 100 × (passed / total). Explicit command required (no auto-detect). |
| `function-exported.sh` | Check named export | `<name> <file>` | 100 if exported, 0 if not |
| `pattern-match.sh` | Grep pattern in file(s) | `<pattern> <glob>` | 100 if found, 0 if not |
| `diff-compare.sh` | Diff against expected | `<expected-dir>` | 100 × (1 - lines_changed / total_lines) |
| `quality-gate.sh` | Run Loa quality gates | `[gate-name]` | Pass/fail per gate |
| `no-secrets.sh` | Scan for leaked secrets | (none) | 100 if clean, 0 if secrets found |
| `constraint-enforced.sh` | Verify constraint | `<constraint-id>` | 100 if enforced, 0 if not |

**Composite grading** (in `grade.sh`):

When a task has multiple graders, aggregate using the task's composite strategy:

| Strategy | Logic | Use Case |
|----------|-------|----------|
| `all_must_pass` (default) | All graders must exit 0. Score = min(scores). | Regression tests — strict. |
| `weighted_average` | Score = Σ(weight × score) / Σ(weight). Pass if score ≥ threshold. | Quality scoring — nuanced. |
| `any_pass` | At least one grader passes. Score = max(scores). | Exploratory — lenient. |

### 3.5 Result Storage (`evals/results/`)

**Run directory structure**:
```
evals/results/
├── .gitkeep
├── eval-ledger.jsonl            # Append-only result ledger
└── run-20260211-143000-a1b2/    # Per-run directory
    ├── run-meta.json            # Run metadata
    ├── results.jsonl            # Per-trial results
    └── transcripts/             # Agent transcripts (Phase 3+)
        └── trial-001.jsonl
```

**JSONL result entry** (one per trial):
```json
{
  "run_id": "run-20260211-143000-a1b2",
  "task_id": "implement-simple-function",
  "trial": 1,
  "timestamp": "2026-02-11T14:30:15Z",
  "duration_ms": 45200,
  "model_version": "claude-opus-4-6",
  "status": "completed",
  "graders": [
    {"name": "file-exists.sh", "pass": true, "score": 100, "exit_code": 0, "duration_ms": 50},
    {"name": "tests-pass.sh", "pass": true, "score": 100, "exit_code": 0, "duration_ms": 3200},
    {"name": "function-exported.sh", "pass": true, "score": 100, "exit_code": 0, "duration_ms": 30}
  ],
  "composite": {
    "strategy": "all_must_pass",
    "pass": true,
    "score": 100
  },
  "error": null,
  "transcript_hash": "sha256:abc123..."
}
```

**Run metadata** (`run-meta.json`):
```json
{
  "run_id": "run-20260211-143000-a1b2",
  "suite": "regression",
  "started_at": "2026-02-11T14:30:00Z",
  "completed_at": "2026-02-11T14:35:42Z",
  "duration_ms": 342000,
  "tasks_total": 10,
  "tasks_passed": 9,
  "tasks_failed": 1,
  "tasks_error": 0,
  "model_version": "claude-opus-4-6",
  "git_sha": "abc123",
  "git_branch": "feature/eval-sandbox-277",
  "harness_version": "1.0.0",
  "cost_usd": 0.00,
  "environment": "local"
}
```

**Gitignore**: `evals/results/` is gitignored except `evals/results/.gitkeep`. Baselines are in `evals/baselines/` (tracked).

### 3.6 Baseline Manager (`evals/harness/compare.sh`)

**Baseline file format** (`evals/baselines/regression.baseline.yaml`):
```yaml
version: 1
suite: regression
model_version: "claude-opus-4-6"
recorded_at: "2026-02-11"
recorded_from_run: "run-20260211-143000-a1b2"
tasks:
  implement-simple-function:
    pass_rate: 0.67
    trials: 3
    mean_score: 89
    status: active    # active | quarantined
  review-catches-bug:
    pass_rate: 1.0
    trials: 3
    mean_score: 100
    status: active
```

**Comparison logic**:

For each task in current run vs baseline:

| Condition | Classification | Detail |
|-----------|---------------|--------|
| Current pass_rate ≥ baseline pass_rate | **Pass** | Task is at or above baseline |
| Current pass_rate < baseline - threshold | **Regression** | Score dropped below threshold (default: 10%) |
| Current pass_rate < baseline but within threshold | **Degraded** | Minor drop, warning only |
| Task not in baseline | **New** | No comparison available |
| Task in baseline but not in run | **Missing** | Task may have been removed |
| Task status = quarantined | **Quarantined** | Excluded from regression scoring |

**Statistical comparison** (SKP-003):

With low trial counts, raw pass_rate deltas are unreliable. The comparison engine uses:

| CI Trial Count | Comparison Method | Gate Behavior |
|----------------|-------------------|---------------|
| 1 (framework — deterministic) | Exact match | Pass=pass, fail=regression |
| ≥3 (agent evals) | Wilson confidence interval (95%) | Regression only if lower bound of current interval < upper bound of baseline interval minus threshold |
| 1 (agent eval — emergency) | Advisory only | Warning posted, does not block merge |

For MVP, flake detection is deferred. The system records per-run variance but does not auto-quarantine until ledger history exists (Phase 3).

**Ledger persistence in CI** (SKP-004):

The eval ledger is persisted as a GitHub Actions artifact with 90-day retention:

```yaml
# In eval.yml
- name: Upload eval ledger
  uses: actions/upload-artifact@v4
  with:
    name: eval-ledger-${{ github.sha }}
    path: pr/evals/results/eval-ledger.jsonl
    retention-days: 90

- name: Download previous ledger (if exists)
  uses: actions/download-artifact@v4
  continue-on-error: true
  with:
    name: eval-ledger-latest
    path: pr/evals/results/
```

**Model version skew handling** (IMP-006):

When the current run's model version differs from the baseline's pinned version:

| Scenario | Action |
|----------|--------|
| Framework eval (no model) | No check needed |
| Agent eval, same model version | Normal comparison |
| Agent eval, different model version | Mark results as `model_skew: true`. Post warning. Results are advisory only — do not block merge. Recommend baseline update. |
| Baseline has no model_version | Warn about missing pin. Compare normally. |

**Cost tracking** (IMP-004):

For agent-invoking trials, cost is tracked per-trial:

1. **Measurement**: Record tokens_in, tokens_out, model from API response
2. **Calculation**: Apply pricing from `.loa.config.yaml` or default rates
3. **Enforcement**: Sum running cost per suite. If `budget_per_run` exceeded, abort remaining tasks, publish partial results with `budget_exceeded` error.
4. **Reporting**: Total cost in run-meta.json and CLI report

**Baseline update workflow**:
```bash
# Generate updated baseline from current run
./evals/harness/compare.sh --update-baseline --run-id run-abc --suite regression

# Output: evals/baselines/regression.baseline.yaml (modified)
# Developer reviews diff, commits with rationale
```

### 3.7 Reporter (`evals/harness/report.sh` + `evals/harness/pr-comment.sh`)

**CLI report** (`report.sh`):
```
═══════════════════════════════════════════════════════════
  EVAL RESULTS — regression
═══════════════════════════════════════════════════════════

  Run ID:    run-20260211-143000-a1b2
  Duration:  5m 42s
  Model:     claude-opus-4-6
  Git SHA:   abc123 (feature/eval-sandbox-277)

  Summary:
    ✅ Pass:        9
    ❌ Fail:        1
    ⚠️  Regression:  1
    🆕 New:         0
    ⏭️  Quarantined: 1

  Regressions:
    implement-error-handling  100% → 33%  (-67%) ⛔

  Improvements:
    review-catches-xss       67% → 100%  (+33%) ✅

═══════════════════════════════════════════════════════════
```

**PR comment** (`pr-comment.sh`):
Uses `gh pr comment` to post structured markdown (format defined in PRD FR6.3).

```bash
# Post comment to PR
pr-comment.sh --run-id run-abc --pr 42

# Uses: gh pr comment 42 --body "$(cat formatted-comment.md)"
```

### 3.7.1 Parallelism Model (IMP-003)

**Unit of parallelism**: Task (not trial). Each task runs its trials sequentially, but multiple tasks run in parallel.

```
Suite: regression (10 tasks, concurrency=4)
├── Slot 1: task-A (trial 1 → trial 2 → trial 3) → grade → record
├── Slot 2: task-B (trial 1 → trial 2 → trial 3) → grade → record
├── Slot 3: task-C (trial 1 → trial 2 → trial 3) → grade → record
└── Slot 4: task-D (trial 1 → trial 2 → trial 3) → grade → record
     ↓ (slot freed)
     Slot 4: task-E ...
```

**Isolation**: Each task gets its own sandbox directory. No shared state between parallel tasks.

**Write semantics**: JSONL ledger uses `flock(1)` for atomic appends. Each task writes its own result block, then appends to the shared ledger under lock.

**Aggregation**: After all tasks complete, `compare.sh` reads the full results JSONL and produces the comparison report.

### 3.8 Skill Definition (`eval-running`)

**`evals/skills/eval-running/index.yaml`** (placed in evals/ not .claude/skills/ since this is an eval-specific skill):

Wait — actually, `/eval` should be a proper Loa skill for the golden path. Let me place it in `.claude/skills/`.

**`.claude/skills/eval-running/index.yaml`**:
```yaml
name: "eval-running"
version: "1.0.0"
model: "native"
color: "cyan"

effort_hint: medium
danger_level: safe
categories:
  - quality
  - testing

description: |
  Run evaluation suites to benchmark Loa skill quality and detect regressions.
  Use this skill to validate that framework changes don't degrade agent behavior.
  Supports framework correctness, regression, and skill quality eval suites.

triggers:
  - "/eval"
  - "run evals"
  - "benchmark skills"
  - "check for regressions"

negative_triggers:
  - "unit test"
  - "integration test"

inputs:
  - name: "suite"
    type: "string"
    description: "Named eval suite to run (framework, regression, skill-quality)"
    required: false
  - name: "task"
    type: "string"
    description: "Single task ID to run"
    required: false
  - name: "skill"
    type: "string"
    description: "Run all tasks targeting this skill"
    required: false
  - name: "update_baseline"
    type: "boolean"
    description: "Update baselines from current results"
    required: false
  - name: "compare"
    type: "string"
    description: "Run ID to compare against"
    required: false

outputs:
  - path: "evals/results/run-*/results.jsonl"
    description: "Per-trial evaluation results"
    format: detailed
  - path: "evals/results/eval-ledger.jsonl"
    description: "Append-only result ledger"
    format: raw

protocols:
  required: []
  recommended: []

input_guardrails:
  pii_filter:
    enabled: false
  injection_detection:
    enabled: false
  relevance_check:
    enabled: true
    reject_irrelevant: false
```

**`.claude/skills/eval-running/SKILL.md`** — routes to `evals/harness/run-eval.sh` with appropriate flags. The skill is a thin wrapper that translates `/eval` arguments to harness CLI arguments.

**`.claude/commands/eval.md`** — command file routing `/eval` to the `eval-running` skill.

### 3.9 CI Pipeline (`.github/workflows/eval.yml`)

```yaml
name: Eval Gate

permissions:
  contents: read
  pull-requests: write  # For PR comments

on:
  pull_request:
    branches: [main]
    paths:
      - '.claude/skills/**'
      - '.claude/protocols/**'
      - '.claude/data/**'
      - '.loa.config.yaml'
      - 'evals/**'

jobs:
  eval-gate:
    name: Eval — Framework + Regression
    runs-on: ubuntu-latest
    if: "!contains(github.event.pull_request.labels.*.name, 'eval-skip')"

    steps:
      - name: Checkout base branch (for trusted graders/harness)
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.base.sha }}
          path: base

      - name: Checkout PR branch (for task definitions + framework code)
        uses: actions/checkout@v4
        with:
          path: pr

      - name: Setup eval environment
        run: |
          # Use graders and harness from BASE branch (trusted — SKP-001)
          cp -r base/evals/harness/ pr/evals/harness/
          cp -r base/evals/graders/ pr/evals/graders/

      - name: Download previous eval ledger
        uses: actions/download-artifact@v4
        continue-on-error: true
        with:
          name: eval-ledger-latest
          path: pr/evals/results/

      - name: Build sandbox container
        working-directory: pr
        run: docker build -t loa-eval-sandbox -f evals/harness/Dockerfile.sandbox .

      - name: Run framework eval suite (in container)
        working-directory: pr
        run: |
          ./evals/harness/run-eval.sh --suite framework --json \
            --sandbox-mode container > framework-results.json
        timeout-minutes: 5

      - name: Run regression eval suite (in container)
        working-directory: pr
        run: |
          ./evals/harness/run-eval.sh --suite regression --json \
            --sandbox-mode container --min-trials 3 > regression-results.json
        timeout-minutes: 15

      - name: Post PR comment
        if: always()
        working-directory: pr
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          ./evals/harness/pr-comment.sh \
            --pr ${{ github.event.pull_request.number }} \
            --framework-results framework-results.json \
            --regression-results regression-results.json

      - name: Upload eval ledger
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: eval-ledger-latest
          path: pr/evals/results/eval-ledger.jsonl
          retention-days: 90

      - name: Check for regressions
        working-directory: pr
        run: |
          # Exit 1 if regressions detected (blocks merge)
          ./evals/harness/compare.sh --results regression-results.json --strict
```

**Security measures** (per PRD SKP-002):
- Graders and harness sourced from base branch, not PR
- `permissions: contents: read` (minimal)
- No secrets exposed to eval scripts (GITHUB_TOKEN only for PR comments)
- Fork PRs: workflow does not trigger (controlled by `pull_request` event type)

---

## 4. Framework Correctness Eval Tasks

These are the P0 tasks that run without agent execution — pure deterministic checks.

### 4.1 Constraint Validation Tasks

For each constraint category in `constraints.json`, verify enforcement:

| Task ID | What It Checks |
|---------|---------------|
| `constraint-never-code-outside-implement` | C-PROC-001: verify SKILL.md references the constraint |
| `constraint-always-review-audit-cycle` | C-PROC-005: verify run-mode enforces cycle |
| `constraint-beads-tracking` | C-BEADS-*: verify beads integration points |
| `constraint-bug-eligibility` | C-PROC-015/016: verify bug skill checks eligibility |

**Grader**: `constraint-enforced.sh` — parses constraints.json, finds the skill/protocol that should enforce it, greps for enforcement markers.

### 4.2 Golden Path Routing Tasks

| Task ID | What It Checks |
|---------|---------------|
| `golden-path-loa-resolves` | `/loa` command exists and routes correctly |
| `golden-path-plan-resolves` | `/plan` routes to plan-and-analyze |
| `golden-path-build-resolves` | `/build` routes to implementing-tasks |
| `golden-path-review-resolves` | `/review` routes to review-sprint + audit-sprint |
| `golden-path-ship-resolves` | `/ship` routes to deploy-production + archive-cycle |

**Grader**: `pattern-match.sh` — verifies routing scripts contain expected targets.

### 4.3 Skill Index Integrity Tasks

| Task ID | What It Checks |
|---------|---------------|
| `skill-index-all-valid` | All skills have index.yaml with required fields |
| `skill-index-triggers-unique` | No trigger collisions between skills |
| `skill-index-danger-levels` | All skills have danger_level matching expectations |

**Grader**: custom `skill-index-validator.sh` — reads all `index.yaml` files, validates schema.

---

## 5. Fixture Repository Design

### 5.1 MVP Fixtures

| Fixture | Language | Purpose | Dependency Strategy |
|---------|----------|---------|-------------------|
| `hello-world-ts` | TypeScript | Simple implementation tasks | prebaked |
| `buggy-auth-ts` | TypeScript | Bug-fixing tasks (known auth bugs) | prebaked |
| `simple-python` | Python | Cross-language testing | none (stdlib only) |
| `shell-scripts` | Bash | Script-based tasks | none |
| `loa-skill-dir` | YAML/MD | Framework correctness testing | none |

### 5.2 Fixture Structure

```
evals/fixtures/hello-world-ts/
├── fixture.yaml           # Metadata
├── package.json           # Project definition
├── package-lock.json      # Locked dependencies
├── node_modules/          # Prebaked (for prebaked strategy)
├── tsconfig.json          # TypeScript config
├── src/
│   └── index.ts           # Starter code
├── tests/
│   └── index.test.ts      # Existing tests (if applicable)
└── README.md              # Scenario description
```

**`fixture.yaml`**:
```yaml
name: hello-world-ts
version: "1.0.0"
language: typescript
runtime: node-20
dependency_strategy: prebaked
description: "Simple TypeScript project for implementation eval tasks"
difficulty: basic
domain: general
deprecated: false
```

### 5.3 Fixture for Loa Framework Testing

```
evals/fixtures/loa-skill-dir/
├── fixture.yaml
├── .claude/
│   ├── skills/
│   │   └── test-skill/
│   │       ├── index.yaml
│   │       └── SKILL.md
│   ├── data/
│   │   └── constraints.json
│   └── protocols/
│       └── test-protocol.md
├── .loa.config.yaml
└── grimoires/
    └── loa/
        └── ledger.json
```

This fixture provides a minimal Loa project structure for framework correctness evals.

---

## 6. Error Handling

### 6.1 Error Taxonomy

| Error Type | Exit Code | Retry | CI Behavior |
|------------|-----------|-------|-------------|
| `infrastructure_error` | 2 | Once | Neutral (does not block) |
| `eval_failure` | 1 | No | Blocks (regression detected) |
| `timeout` | 2 | No | Neutral |
| `budget_exceeded` | 2 | No | Neutral (partial results published) |
| `config_error` | 3 | No | Blocks (harness broken) |
| `validation_error` | 3 | No | Blocks (task definition invalid) |

### 6.2 Partial Failure Behavior

When a task fails with `infrastructure_error`:
1. Log the error with full context
2. Record result as `{"status": "error", "error": {"type": "infrastructure_error", "message": "..."}}`
3. Continue to next task
4. Final report marks which tasks errored vs which failed grading
5. Infrastructure errors do not count toward regression scoring

### 6.3 Timeout Handling

```bash
# Per-trial timeout via timeout(1)
timeout --signal=TERM --kill-after=10 "${per_trial_timeout}" run_trial "$@"
exit_code=$?

if [[ $exit_code -eq 124 ]]; then
  # Timed out
  record_result --status timeout --error "Trial exceeded ${per_trial_timeout}s"
fi
```

---

## 7. Configuration Integration

**New config section in `.loa.config.yaml`**:

```yaml
eval:
  enabled: true
  suites:
    default: ["framework", "regression"]
    ci: ["framework", "regression"]
    ci_async: ["skill-quality"]
    full: ["framework", "regression", "skill-quality"]
  trials:
    default: 3
    ci: 1
  timeout:
    per_trial: 120
    per_grader: 30
    per_suite_multiplier: 2
  concurrency: 4
  regression:
    threshold: 0.10
    block_merge: true
    flake_quarantine:
      enabled: true
      consecutive_flaky_runs: 3
  results:
    retention: 100
    ledger_path: "evals/results/eval-ledger.jsonl"
  ci:
    post_pr_comment: true
    required_check: true
    skip_label: "eval-skip"
    fork_pr_policy: "block"
    sandbox:
      container: true   # Container sandboxing from MVP (SKP-001)
      network: "none"
      ignore_scripts: true
  cost:
    budget_per_run: 5.00
    track_usage: true
  baseline:
    require_rationale: true
    pin_model_version: true
```

---

## 8. Constraint Amendments

### New Constraints

| ID | Name | Type | Text |
|----|------|------|------|
| C-EVAL-001 | `eval_baselines_require_review` | ALWAYS | ALWAYS submit baseline updates as PRs with rationale for CODEOWNERS review |
| C-EVAL-002 | `eval_graders_deterministic` | ALWAYS | ALWAYS ensure code-based graders are deterministic — no network, no LLM, no time-dependent logic |

### Process Compliance Amendments

The `/eval` command does NOT require the implement→review→audit cycle because it is a read-only quality measurement tool, not an implementation skill. It sits alongside `/validate` and `/audit` as a quality gate command.

---

## 9. Testing Strategy

### 9.1 Harness Tests

| Test | Type | What It Validates |
|------|------|-------------------|
| `test-validate-task.sh` | Unit | Task YAML validation catches all error types |
| `test-sandbox.sh` | Unit | Sandbox creation, isolation, cleanup |
| `test-graders.sh` | Unit | Each grader returns correct pass/fail for known inputs |
| `test-compare.sh` | Unit | Baseline comparison logic (regression, improvement, new, missing) |
| `test-report.sh` | Unit | CLI report formatting |
| `test-run-eval.sh` | Integration | Full pipeline: load → validate → execute → grade → compare → report |
| `test-pr-comment.sh` | Integration | PR comment formatting (mock gh) |

### 9.2 Grader Tests

Each grader has a paired test with known-pass and known-fail fixtures:

```
evals/graders/tests/
├── file-exists/
│   ├── pass/              # Fixture where file exists
│   │   └── src/math.ts
│   └── fail/              # Fixture where file doesn't exist
│       └── src/           # (empty)
├── tests-pass/
│   ├── pass/              # Fixture where tests pass
│   └── fail/              # Fixture where tests fail
└── ...
```

### 9.3 Self-Testing Property

The eval system must be able to evaluate itself: run the `framework` suite against the Loa repo to validate that framework correctness tasks pass. This serves as a bootstrap test.

---

## 10. Implementation Phases

### Phase 1: Framework Correctness (Sprint 1)

**Deliverables**:
1. `evals/harness/run-eval.sh` — main orchestrator
2. `evals/harness/validate-task.sh` — task YAML validation
3. `evals/harness/sandbox.sh` — temp-dir sandbox (local mode only)
4. `evals/harness/grade.sh` — grader orchestrator with timeouts
5. `evals/harness/report.sh` — CLI report
6. `evals/harness/compare.sh` — baseline comparison
7. `evals/graders/` — 8 standard graders
8. `evals/fixtures/loa-skill-dir/` — framework testing fixture
9. `evals/tasks/framework/` — ≥20 framework correctness tasks
10. `evals/suites/framework.yaml` — suite definition
11. `evals/baselines/framework.baseline.yaml` — initial baseline
12. `.claude/skills/eval-running/` — skill registration
13. `.claude/commands/eval.md` — command routing
14. Harness test suite

### Phase 2: Regression Protection (Sprint 2)

**Deliverables**:
1. `evals/fixtures/hello-world-ts/` — TypeScript fixture (with `fixture.yaml`, explicit `test_command`, pinned `runtime_version`)
2. `evals/fixtures/buggy-auth-ts/` — bug-fixing fixture
3. `evals/fixtures/simple-python/` — Python fixture
4. `evals/fixtures/shell-scripts/` — shell fixture
5. `evals/tasks/regression/` — ≥10 regression tasks
6. `evals/suites/regression.yaml` — suite definition (with suite YAML schema)
7. `evals/baselines/regression.baseline.yaml` — initial baseline
8. `evals/harness/pr-comment.sh` — PR comment formatter
9. `evals/harness/Dockerfile.sandbox` — container sandbox image (pinned runtimes)
10. `evals/graders/allowlist.txt` — permitted grader commands
11. `.github/workflows/eval.yml` — CI pipeline (with container sandboxing + ledger persistence)
12. Error taxonomy implementation in `run-eval.sh`
13. Wilson confidence interval comparison in `compare.sh`
14. `.loa.config.yaml` eval section
15. Environment fingerprint recording in `sandbox.sh`

### Phase 3: Skill Quality (Future Sprint)

- Agent execution sandbox with transcript capture
- `evals/tasks/skill-quality/` tasks
- Container-based CI sandboxing
- Cost tracking and budget enforcement
- Statistical determinism with confidence intervals

### Phase 4: E2E Workflows (Future Sprint)

- Full plan→build→review→ship eval scenarios
- Model-based graders (LLM-as-judge)
- E2E fixture repositories

---

## 11. Security Considerations

| Concern | Mitigation |
|---------|-----------|
| Grader code injection via PR | Graders sourced from base branch in CI |
| Fixture dependency attacks | `--ignore-scripts` for npm, `--no-deps` for pip, prebaked strategy preferred |
| Secret leakage in eval results | No secrets in eval environment. Results contain no env vars. |
| Resource exhaustion | Per-trial timeouts, per-grader timeouts, concurrency limits, budget cap |
| Path traversal in graders | PATH_SAFETY checks in sandbox.sh (reject `..`, require within workspace) |
| Fork PR exploitation | Fork PRs blocked from eval CI |

---

## 12. Risk Mitigation

| Risk (from PRD) | Architectural Mitigation |
|-----------------|-------------------------|
| Expensive CI | Phase 1-2: zero LLM cost. Phase 3+: async non-blocking. Budget cap. |
| Non-deterministic agent output | Explicit determinism model. Pinned params per baseline. Flake quarantine. |
| Stale fixtures | `fixture.yaml` versioning. Staleness check on eval run. |
| CI latency | Tiered gating: framework (<2 min) + regression (<5 min) blocking. Skill quality async. |
| False regressions | Threshold-based comparison. Quarantine for flaky tasks. `eval-skip` label. |
| Baseline gaming | PR-based updates with rationale. CODEOWNERS review. Diff reporting. |

---

## 13. Flatline Protocol Integration Log

| Finding | Category | Action | Integration |
|---------|----------|--------|-------------|
| IMP-001 | HIGH_CONSENSUS | Auto-integrated | Suite YAML schema defined (Section 3.2.1) |
| IMP-002 | HIGH_CONSENSUS | Auto-integrated | Agent invocation contract added (Section 3.2) |
| IMP-003 | HIGH_CONSENSUS | Auto-integrated | Parallelism model defined (Section 3.7.1) |
| IMP-004 | HIGH_CONSENSUS | Auto-integrated | Cost measurement/enforcement points (Section 3.6) |
| IMP-006 | HIGH_CONSENSUS | Auto-integrated | Model version skew handling (Section 3.6) |
| IMP-007 | HIGH_CONSENSUS | Auto-integrated | Explicit prompt field in task schema (Section 3.2) |
| SKP-001 | BLOCKER (CRITICAL) | Accepted | Container sandboxing in MVP, grader command allowlist, strict validation (Sections 3.3, 3.4, 3.9) |
| SKP-002 | BLOCKER (CRITICAL) | Accepted | No auto-detect, explicit test commands in fixture.yaml, pinned runtimes, env fingerprint (Sections 3.3, 3.4, 3.5) |
| SKP-003 | BLOCKER (HIGH) | Accepted | Wilson confidence intervals, min_trials=3 for agent evals in CI (Section 3.6) |
| SKP-004 | BLOCKER (HIGH) | Accepted | Ledger persisted as CI artifact, flake detection deferred to Phase 3 (Section 3.6, 3.9) |

---

## Next Step

After SDD approval: `/sprint-plan` to create sprint plan with task breakdown for Phases 1-2.
