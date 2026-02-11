# Sprint Plan: Eval Sandbox — Benchmarking & Regression Framework

**PRD**: grimoires/loa/prd.md (v1.1.0)
**SDD**: grimoires/loa/sdd.md (v1.1.0)
**Issue**: [loa #277](https://github.com/0xHoneyJar/loa/issues/277)
**Version**: 1.1.0 (revised per Flatline Protocol review)
**Date**: 2026-02-11

---

## Sprint 1: Eval Harness, Graders & Framework Correctness

### Sprint Goal

Build the eval harness infrastructure: task loading, validation, sandbox provisioning, grader framework, result storage, baseline comparison, and CLI reporting. Deliver the framework correctness eval suite with ≥20 deterministic tasks that validate Loa's infrastructure contracts without any agent execution.

### Deliverables

- [ ] Eval harness pipeline (load → validate → sandbox → execute → grade → compare → report)
- [ ] 8 standard graders with exit code contracts
- [ ] Framework correctness fixture (`loa-skill-dir`)
- [ ] ≥20 framework correctness eval tasks
- [ ] Suite YAML schema and loader
- [ ] Baseline comparison with CLI report
- [ ] `/eval` skill registration and command routing
- [ ] Harness test suite

### Technical Tasks

#### Task 1.1: Eval Harness Core — `run-eval.sh` **[G1, G2, SDD §3.1]**

Create the main orchestrator script `evals/harness/run-eval.sh` that implements the pipeline: PREFLIGHT → INIT → LOAD_SUITE → VALIDATE_TASKS → EXECUTE_TRIALS → GRADE → FINALIZE → COMPARE → REPORT → DONE.

**Acceptance Criteria**:
- [ ] Preflight check: validates required tools (bash ≥4, jq, git, timeout, mktemp, sha256sum) and exits code 3 with actionable install guidance if missing (SKP-001)
- [ ] Accepts `--suite`, `--task`, `--skill`, `--update-baseline`, `--compare`, `--json`, `--trusted`, `--sandbox-mode` flags
- [ ] `--trusted` flag required for local execution (SKP-003). Without it, refuses to run with message explaining container mode or `--trusted` flag.
- [ ] Loads suite YAML and resolves task glob patterns
- [ ] Parallel task execution with configurable concurrency (default: 4). Each task writes per-task result file, then single-threaded FINALIZE step merges into JSONL ledger (SKP-002)
- [ ] Error propagation in parallel: infrastructure errors logged and skipped, eval failures collected. Partial results always recorded. (IMP-002)
- [ ] Exit codes: 0 (pass), 1 (regression), 2 (infrastructure error), 3 (config error)
- [ ] Run directory created per invocation: `evals/results/run-{timestamp}-{hash}/`
- [ ] Run metadata written to `run-meta.json` with JSONL schema version field (IMP-004)
- [ ] Trial runner interface defined: `run_trial(task_yaml, sandbox_path, trial_num) → result.json` (IMP-005). Framework tasks use shell-exec runner; agent tasks use agent-exec runner (Sprint 2+).

#### Task 1.2: Task Validator — `validate-task.sh` **[FR1.7, FR1.8, SDD §3.2]**

Create task YAML validator that checks all required fields, schema version, fixture existence, grader existence, and grader command allowlist.

**Acceptance Criteria**:
- [ ] Validates all required fields from Schema Version 1
- [ ] Rejects unknown `schema_version` with actionable error
- [ ] Verifies `skill` exists in `.claude/skills/`
- [ ] Verifies `fixture` directory exists in `evals/fixtures/`
- [ ] Verifies all `graders[].script` files exist and are executable
- [ ] Validates grader args against `evals/graders/allowlist.txt`
- [ ] JSON output: `{"valid": bool, "task_id": string, "warnings": [], "errors": []}`

#### Task 1.3: Sandbox Manager — `sandbox.sh` **[FR2.3, SDD §3.3]**

Create sandbox provisioning script for local mode (temp directory with controlled environment and minimal isolation).

**Acceptance Criteria**:
- [ ] `sandbox.sh create` copies fixture to temp dir, initializes git, sets controlled env vars (`TZ=UTC`, `LC_ALL=C`, `HOME=<sandbox>/home`)
- [ ] Minimal isolation (SKP-003): restrictive umask (077), clean PATH (only essential dirs), clear sensitive env vars (`AWS_*`, `ANTHROPIC_*`, `GITHUB_TOKEN`, `GH_TOKEN`, `OPENAI_*`)
- [ ] `sandbox.sh destroy` removes temp dir with trap-based cleanup
- [ ] `sandbox.sh destroy-all` removes all sandboxes for a run
- [ ] Handles dependency strategies: `prebaked` (copy), `offline-cache` (install from cache with `--ignore-scripts`), `none` (skip)
- [ ] Records environment fingerprint to `env-fingerprint.json`
- [ ] PATH_SAFETY: rejects `..` in fixture paths, validates within `evals/fixtures/`, rejects symlinks pointing outside fixture (SKP-010)

#### Task 1.4: Grader Framework — `grade.sh` + 8 Standard Graders **[FR3, SDD §3.4]**

Create grader orchestrator and 8 standard graders following the exit code contract.

**Acceptance Criteria**:
- [ ] `grade.sh` runs all graders for a task with per-grader timeout via `timeout(1)`
- [ ] Supports composite strategies: `all_must_pass`, `weighted_average`, `any_pass`
- [ ] Each grader outputs JSON: `{"pass": bool, "score": 0-100, "details": string, "grader_version": "1.0.0"}`
- [ ] Grader exit codes: 0 = pass, 1 = fail, 2 = error
- [ ] Timeout → exit code 2 (error, not fail)
- [ ] 8 graders implemented: `file-exists.sh`, `tests-pass.sh` (explicit command, no auto-detect), `function-exported.sh`, `pattern-match.sh`, `diff-compare.sh`, `quality-gate.sh`, `no-secrets.sh`, `constraint-enforced.sh`
- [ ] Strict grader execution model (SKP-004): no `eval`, no `sh -c`, no unquoted expansions. Commands resolved to absolute paths via controlled PATH. Args validated structurally per grader (not string allowlist).
- [ ] Grader security test that attempts common bypasses (arg injection, path traversal, command chaining)

#### Task 1.5: Result Storage & Baseline Comparison — `compare.sh` **[FR4, SDD §3.5-3.6]**

Create JSONL result storage and baseline comparison engine.

**Acceptance Criteria**:
- [ ] Results written as JSONL (one entry per trial) to `evals/results/run-*/results.jsonl`
- [ ] Results appended to `evals/results/eval-ledger.jsonl` with `flock` for atomic writes
- [ ] `compare.sh` reads baseline YAML and current results, classifies each task: pass, regression, degraded, new, missing
- [ ] Regression threshold configurable (default: 10%)
- [ ] `--update-baseline` generates updated YAML from current results, requires `--reason "justification"` (SKP-005). Reason is recorded in baseline file.
- [ ] Baseline YAML includes: `version`, `suite`, `model_version`, `recorded_at`, `update_reason`, per-task `pass_rate`, `trials`, `mean_score`, `status`
- [ ] Result JSONL entries include `schema_version: 1` field for forward compatibility (IMP-004)

#### Task 1.6: CLI Report — `report.sh` **[FR5.7, SDD §3.7]**

Create terminal-formatted eval results report.

**Acceptance Criteria**:
- [ ] Displays run ID, duration, model, git SHA
- [ ] Summary counts: pass, fail, regression, new, quarantined
- [ ] Regression details: task name, baseline → current, delta
- [ ] Improvement details: task name, baseline → current, delta
- [ ] Color-coded output (green/red/yellow) with NC fallback

#### Task 1.7: Framework Correctness Fixture + Tasks **[FR7, SDD §4-5]**

Create the `loa-skill-dir` fixture and ≥20 framework correctness eval tasks.

**Acceptance Criteria**:
- [ ] `evals/fixtures/loa-skill-dir/` contains minimal Loa project structure (skills, protocols, constraints, config, ledger)
- [ ] `evals/fixtures/loa-skill-dir/fixture.yaml` with metadata
- [ ] `evals/suites/framework.yaml` suite definition
- [ ] ≥20 tasks in `evals/tasks/framework/` covering: constraint validation (5+), golden path routing (5+), skill index integrity (3+), config schema (3+), quality gate validation (4+)
- [ ] All tasks use code-based graders (zero LLM cost)
- [ ] `evals/baselines/framework.baseline.yaml` with initial baselines (all 100% for deterministic tasks)

#### Task 1.8: `/eval` Skill Registration & Command **[SDD §3.8]**

Create the eval-running skill and /eval command routing.

**Acceptance Criteria**:
- [ ] `.claude/skills/eval-running/index.yaml` with triggers, inputs, outputs
- [ ] `.claude/skills/eval-running/SKILL.md` that routes to `evals/harness/run-eval.sh`
- [ ] `.claude/commands/eval.md` routing `/eval` to eval-running skill
- [ ] Skill registered in `.claude/skills/` directory

#### Task 1.9: README & Documentation **[IMP-001]**

Create getting-started documentation for the eval system.

**Acceptance Criteria**:
- [ ] `evals/README.md` with: overview, quick start, how to write tasks, how to write graders, how to run locally, how to update baselines
- [ ] Documents `--trusted` flag requirement for local execution
- [ ] Documents Linux-only requirement and supported tool versions
- [ ] Documents grader contract (input/output/exit codes)

#### Task 1.10: Harness Test Suite **[SDD §9]**

Create tests for the harness infrastructure.

**Acceptance Criteria**:
- [ ] `evals/harness/tests/test-validate-task.sh` — validates task YAML validation catches all error types
- [ ] `evals/harness/tests/test-sandbox.sh` — validates sandbox creation, isolation, cleanup
- [ ] `evals/harness/tests/test-graders.sh` — validates each grader with known pass/fail fixtures
- [ ] `evals/harness/tests/test-compare.sh` — validates comparison logic (regression, improvement, new, missing)
- [ ] Grader test fixtures in `evals/graders/tests/` with pass/fail directories per grader
- [ ] All tests pass with exit code 0

---

## Sprint 2: Regression Suite, CI Pipeline & PR Comments -- REVIEWED, APPROVED

### Sprint Goal

Build the regression eval suite with fixture repositories, GitHub Actions CI pipeline with container sandboxing, PR comment reporting, and statistical baseline comparison. Complete the MVP by delivering automated regression detection on every PR that modifies Loa framework files.

### Deliverables

- [ ] 4 fixture repositories (TypeScript, Python, shell, buggy-auth)
- [ ] ≥10 regression eval tasks
- [ ] Container sandbox (Dockerfile.sandbox)
- [ ] GitHub Actions workflow with base-branch security
- [ ] PR comment formatter
- [ ] Statistical comparison (Wilson intervals)
- [ ] Eval config in .loa.config.yaml
- [ ] Constraint amendments

### Technical Tasks

#### Task 2.1: Fixture Repositories **[FR2, SDD §5]**

Create 4 fixture repos with fixture.yaml metadata, explicit test commands, and pinned runtime versions.

**Acceptance Criteria**:
- [ ] `evals/fixtures/hello-world-ts/` — simple TypeScript project with `fixture.yaml` (`test_command: "npx jest --ci"`, `runtime_version: "20.11.0"`, `dependency_strategy: prebaked`)
- [ ] `evals/fixtures/buggy-auth-ts/` — TypeScript with known auth bugs (race condition, missing validation, exposed secret)
- [ ] `evals/fixtures/simple-python/` — Python stdlib project (`dependency_strategy: none`, `test_command: "python3 -m pytest"`)
- [ ] `evals/fixtures/shell-scripts/` — Bash script project (`dependency_strategy: none`, `test_command: "bash tests/run.sh"`)
- [ ] Each fixture has `fixture.yaml` with all required fields
- [ ] No auto-detect in any fixture — all test commands explicit

#### Task 2.2: Regression Eval Tasks **[FR1, SDD §3.2]**

Create ≥10 regression tasks targeting core Loa skills.

**Acceptance Criteria**:
- [ ] `evals/tasks/regression/` with ≥10 task YAML files
- [ ] Tasks cover at least 3 different skills (implementing-tasks, reviewing-code, bug-triaging)
- [ ] Each task has `prompt` field (explicit agent instruction)
- [ ] Each task has ≥2 graders
- [ ] `evals/suites/regression.yaml` with `min_trials: 3`, `gate_type: blocking`
- [ ] `evals/baselines/regression.baseline.yaml` with initial baselines from first eval run

#### Task 2.3: Container Sandbox — `Dockerfile.sandbox` **[SKP-001, SDD §3.3]**

Create container image for secure CI eval execution.

**Acceptance Criteria**:
- [ ] `evals/harness/Dockerfile.sandbox` with pinned base image, exact Node.js and Python versions
- [ ] npm lifecycle scripts disabled (`--ignore-scripts`)
- [ ] Minimal tools: bash, git, jq, node, python3, grep, diff
- [ ] Non-root user
- [ ] `sandbox.sh` updated with `--sandbox-mode container` flag
- [ ] Container runs with `--network none`, `--memory 2g`, `--cpus 2`, `--read-only` (except workspace and tmp)

#### Task 2.4: CI Pipeline — `eval.yml` **[FR6, SDD §3.9]**

Create GitHub Actions workflow for automated eval on PRs.

**Acceptance Criteria**:
- [ ] `.github/workflows/eval.yml` triggers on PRs modifying `.claude/skills/`, `.claude/protocols/`, `.claude/data/`, `.loa.config.yaml`, `evals/`
- [ ] Checks out base branch for trusted graders/harness + PR branch for code
- [ ] Downloads previous eval ledger artifact (if exists)
- [ ] Builds sandbox container
- [ ] Runs framework + regression suites in containers
- [ ] Uploads eval ledger as artifact (90-day retention)
- [ ] Supports `eval-skip` label to bypass
- [ ] Fork PRs blocked (does not trigger)
- [ ] Minimal permissions: `contents: read`, `pull-requests: write`
- [ ] Validate downloaded ledger artifact: check JSONL integrity, reject if invalid (SKP-010)
- [ ] Symlink validation: reject PR workspace symlinks pointing outside workspace (SKP-010)
- [ ] PR workspace mounted read-only where possible

#### Task 2.5: PR Comment Formatter — `pr-comment.sh` **[FR6.3, SDD §3.7]**

Create structured PR comment posting.

**Acceptance Criteria**:
- [ ] Generates markdown comment matching PRD FR6.3 format (summary table, regressions, improvements, new tasks, full details in collapsible)
- [ ] Posts via `gh pr comment`
- [ ] Handles partial results (marks incomplete runs)
- [ ] Shows model version skew warnings if applicable
- [ ] Includes run ID and duration

#### Task 2.6: Statistical Comparison — Wilson Intervals **[SKP-003, SDD §3.6]**

Enhance `compare.sh` with statistical comparison for agent evals.

**Acceptance Criteria**:
- [ ] Framework evals (1 trial, deterministic): exact match comparison
- [ ] Agent evals (≥3 trials): Wilson confidence interval at 95% confidence
- [ ] Regression classified only when lower bound of current CI < upper bound of baseline CI minus threshold
- [ ] Agent evals with 1 trial: advisory only (warning posted, no merge block)
- [ ] Model version skew detection: different model → advisory only, recommend baseline update

#### Task 2.7: Configuration & Constraints **[SDD §7-8]**

Add eval configuration to `.loa.config.yaml` and amend constraints.

**Acceptance Criteria**:
- [ ] `eval:` section added to `.loa.config.yaml` with all fields from SDD §7
- [ ] C-EVAL-001 added to `constraints.json`: ALWAYS submit baseline updates as PRs with rationale
- [ ] C-EVAL-002 added to `constraints.json`: ALWAYS ensure code-based graders are deterministic
- [ ] CLAUDE.loa.md updated with eval constraints
- [ ] `evals/` directory added to gitignore for results (except baselines)
- [ ] CODEOWNERS entry for `evals/baselines/`

---

## Sprint 3: Bridgebuilder Refinements — Hardening, Observability & Decision Trail

### Sprint Goal

Address all findings from the Bridgebuilder PR review (#282) and prior audit advisories. Harden grader security (ReDoS, source-injection, command execution), add sequential testing optimization for multi-trial evals, resolve the Dockerfile digest placeholder, and document architectural decisions with forward-looking Hounfour routing hooks.

### Deliverables

- [x] Grader hardening: ReDoS guard, direct execution, source-injection CI check
- [x] Wilson CI sequential testing optimization (early stopping)
- [x] Real Dockerfile SHA256 digest (not placeholder)
- [x] ADR decision trail (JSONL vs SQLite, yq variant)
- [x] Multi-model routing documentation and `model_version` hooks
- [x] Updated harness tests covering new hardening
- [x] Framework eval suite stays green (22/22)

### Technical Tasks

#### Task 3.1: ReDoS Guard in `pattern-match.sh` **[Audit Advisory, Bridgebuilder F1]**

Add a regex complexity guard to prevent ReDoS patterns from being passed as grader args. The current implementation passes task YAML `args` directly into `grep -qlE` without complexity validation.

**Acceptance Criteria**:
- [ ] Reject regex patterns with nested quantifiers (e.g., `(a+)+`, `(a*)*`, `(a{2,}){2,}`)
- [ ] Reject patterns exceeding 200 characters (configurable via `MAX_REGEX_LEN`)
- [ ] Return exit code 2 (grader error) with descriptive JSON on rejection
- [ ] Add test case in `evals/harness/tests/` verifying ReDoS rejection
- [ ] Existing pattern-match eval tasks still pass

#### Task 3.2: Safer Command Execution in `tests-pass.sh` **[Audit Advisory, Bridgebuilder F2]**

Replace `bash -c "$test_command"` with direct argument-array execution. The current approach concatenates the command string through a subshell, which is less secure than splitting and executing directly.

**Acceptance Criteria**:
- [ ] Replace `bash -c "$test_command"` at line 40 with array-based execution: split command into array, execute `"${cmd_array[@]}"` directly
- [ ] Preserve allowlist validation (must still check first token)
- [ ] Handle multi-word commands correctly (e.g., `npx jest --verbose`)
- [ ] Return exit code 2 with JSON error on empty/malformed commands
- [ ] Existing tests-pass eval tasks still pass
- [ ] Add test case verifying argument injection is blocked (e.g., `; rm -rf /` in args)

#### Task 3.3: Grader Source-Injection Guard in CI **[Bridgebuilder F3, Medium]**

Add a CI step that validates no grader scripts contain `source`, `.`, or `eval` directives that reference paths outside the trusted grader tree. Prevents a PR from injecting code into trusted graders via sourced files.

**Acceptance Criteria**:
- [ ] New CI step (after "Copy trusted eval infrastructure", before "Run framework suite") in `eval.yml`
- [ ] Scans all `.sh` files in `pr/evals/graders/` and `pr/evals/harness/` for `source`/`.`/`eval` directives
- [ ] Fails CI if any `source`/`.` targets resolve outside `pr/evals/` or contain variable expansion (`$`, backticks)
- [ ] Static analysis only — no execution of grader code
- [ ] Does not block legitimate `source` of sibling scripts within the eval tree
- [ ] Add comment in CI workflow explaining the trust boundary rationale

#### Task 3.4: Sequential Testing Optimization **[Bridgebuilder F4, Medium]**

Add early stopping for multi-trial agent evals. When a task accumulates enough failures that its Wilson CI lower bound can never exceed the regression threshold, stop remaining trials early. Saves CI time proportional to trial count.

**Acceptance Criteria**:
- [ ] New function `can_early_stop(passes, failures, remaining, threshold)` in `compare.sh` or a shared util
- [ ] Returns true when the best-case Wilson CI lower bound (all remaining trials pass) still indicates regression
- [ ] `run-eval.sh` trial loop calls `can_early_stop()` after each trial for multi-trial tasks (trials > 1)
- [ ] Single-trial framework evals are unaffected (no early stopping check)
- [ ] Early-stopped tasks are marked with `"early_stopped": true` in result JSON
- [ ] Add test case verifying early stopping triggers correctly (e.g., 0/3 passes with threshold 0.5)
- [ ] Log message when early stopping: `"Task {id}: early stopped at trial {n}/{total} — regression inevitable"`

#### Task 3.5: Dockerfile Real SHA256 Digest **[Audit Advisory, Bridgebuilder F5]**

Replace the placeholder SHA256 digest in `Dockerfile.sandbox` with the real digest for `node:20.11.0-bookworm-slim` from Docker Hub.

**Acceptance Criteria**:
- [ ] SHA256 digest on FROM line matches actual `node:20.11.0-bookworm-slim` manifest digest from Docker Hub
- [ ] Digest verified by running `docker manifest inspect node:20.11.0-bookworm-slim` (or equivalent registry API)
- [ ] Comment added noting the date the digest was pinned and how to refresh it
- [ ] Dockerfile health check still passes (all tools verified)

#### Task 3.6: ADR Decision Trail **[Bridgebuilder F6, Low]**

Document the key architectural decisions made during eval sandbox design as lightweight ADR entries in the README. Addresses the "decision trail gaps" finding.

**Acceptance Criteria**:
- [ ] New `## Architecture Decisions` section in `evals/README.md`
- [ ] ADR-001: JSONL vs SQLite — why append-only JSONL was chosen over SQLite for result storage (simplicity, no binary dependency, git-friendly audit trail, flock atomicity)
- [ ] ADR-002: yq variant — explicitly states mikefarah/yq (Go binary) was chosen over kislyuk/yq (Python wrapper), with rationale (no Python runtime dependency, single binary, consistent behavior)
- [ ] ADR-003: Shell-based harness — why bash over Node.js/Python for the harness (zero additional runtime, universal CI availability, exit code contract simplicity)
- [ ] Each ADR has: Context, Decision, Consequences (1-3 sentences each)

#### Task 3.7: Multi-Model Eval Routing Documentation **[Bridgebuilder F7, Low]**

Document the `model_version` field's forward-looking connection to multi-model routing (Hounfour / permission-scape). The field already exists in results but its strategic purpose for model comparison and routing is undocumented.

**Acceptance Criteria**:
- [ ] New `## Multi-Model Evaluation` section in `evals/README.md`
- [ ] Documents `model_version` field in result schema and its purpose for cross-model comparison
- [ ] Explains model version skew detection in `compare.sh` (advisory mode when model versions differ)
- [ ] Forward reference to Hounfour multi-model routing: eval data provides empirical evidence for routing decisions (which model performs best on which task categories)
- [ ] Notes that `model_version` in baselines enables per-model baseline tracking when multi-model support lands
- [ ] Does NOT implement routing — documentation only, connecting the existing `model_version` field to the vision

---

## Sprint Summary

| Sprint | Goal | Tasks | Est. Components |
|--------|------|-------|-----------------|
| Sprint 1 | Eval Harness + Framework Correctness | 10 | 28 new files, 0 modified |
| Sprint 2 | Regression Suite + CI Pipeline | 7 | 20 new files, 4 modified |
| Sprint 3 | Bridgebuilder Refinements | 7 | 0 new files, 8 modified |
| **Total** | **Exceptional PR** | **24** | **48 new, 12 modified** |

### Risk Mitigation in Sprint Plan

| Risk | Sprint | Mitigation |
|------|--------|------------|
| Harness complexity | 1 | Task 1.1 is self-contained pipeline; can be tested without graders |
| Grader quality | 1 | Task 1.9 harness tests catch grader regressions |
| Container complexity | 2 | Task 2.3 isolated from other work; falls back to local mode |
| CI integration issues | 2 | Task 2.4 can be tested on a branch before merge |
| ReDoS guard false positives | 3 | Permissive length limit (200 chars); only rejects nested quantifiers |
| Early stopping edge cases | 3 | Only activates for multi-trial; single-trial evals unchanged |
| Dockerfile digest staleness | 3 | Comment documents refresh procedure |

### Dependencies

```
Task 1.1 (harness) ← Task 1.2 (validator) ← Task 1.7 (tasks)
Task 1.1 (harness) ← Task 1.3 (sandbox)
Task 1.1 (harness) ← Task 1.4 (graders) ← Task 1.10 (tests)
Task 1.1 (harness) ← Task 1.5 (compare)
Task 1.5 (compare) ← Task 1.6 (report)
Task 1.7 (fixture + tasks) ← Task 1.8 (skill registration)
Task 1.8 (skill registration) ← Task 1.9 (README)

Task 1.3 (sandbox) ← Task 2.3 (container)
Task 1.4 (graders) ← Task 2.1 (fixtures)
Task 1.5 (compare) ← Task 2.6 (Wilson intervals)
Task 1.6 (report) ← Task 2.5 (PR comment)
Task 2.1 (fixtures) ← Task 2.2 (regression tasks)
Task 2.3 (container) ← Task 2.4 (CI pipeline)

Sprint 3 (all tasks independent — no inter-task dependencies):
Task 3.1 (ReDoS guard) ← Task 1.4 (graders)
Task 3.2 (tests-pass fix) ← Task 1.4 (graders)
Task 3.3 (CI injection guard) ← Task 2.4 (CI pipeline)
Task 3.4 (early stopping) ← Task 2.6 (Wilson intervals)
Task 3.5 (Dockerfile digest) ← Task 2.3 (container)
Task 3.6 (ADR trail) ← Task 1.9 (README)
Task 3.7 (routing docs) ← Task 1.9 (README)
```

### Flatline Protocol Integration Log

| Finding | Category | Action | Integration |
|---------|----------|--------|-------------|
| IMP-001 | HIGH_CONSENSUS | Auto-integrated | Task 1.9 (README) added |
| IMP-002 | HIGH_CONSENSUS | Auto-integrated | Error propagation rules in Task 1.1 |
| IMP-004 | HIGH_CONSENSUS | Auto-integrated | JSONL schema versioning in Task 1.5 |
| IMP-005 | HIGH_CONSENSUS | Auto-integrated | Trial runner interface in Task 1.1 |
| IMP-010 | DISPUTED | Skipped | Project management hygiene out of scope |
| SKP-001 | BLOCKER (CRITICAL) | Accepted | Preflight tool check in Task 1.1, Linux-only documented in Task 1.9 |
| SKP-002 | BLOCKER (HIGH) | Accepted | Per-task result files + single-threaded merge in Task 1.1 |
| SKP-003 | BLOCKER (CRITICAL) | Accepted | --trusted flag + minimal isolation in Tasks 1.1, 1.3 |
| SKP-004 | BLOCKER (CRITICAL) | Accepted | Strict grader execution model in Task 1.4 |
| SKP-005 | BLOCKER (HIGH) | Accepted | Baseline --reason requirement in Task 1.5 |
| SKP-010 | BLOCKER (HIGH) | Accepted | Ledger validation + symlink checks in Task 2.4 |

### Bridgebuilder Review Integration Log (Sprint 3)

| Finding | Severity | Source | Integration |
|---------|----------|--------|-------------|
| BRG-001 | Advisory | Audit + Bridgebuilder | Task 3.1 — ReDoS guard in pattern-match.sh |
| BRG-002 | Advisory | Audit + Bridgebuilder | Task 3.2 — Safer execution in tests-pass.sh |
| BRG-003 | Medium | Bridgebuilder | Task 3.3 — Grader source-injection CI guard |
| BRG-004 | Medium | Bridgebuilder | Task 3.4 — Sequential testing optimization |
| BRG-005 | Advisory | Audit + Bridgebuilder | Task 3.5 — Real Dockerfile SHA256 digest |
| BRG-006 | Low | Bridgebuilder | Task 3.6 — ADR decision trail |
| BRG-007 | Low | Bridgebuilder | Task 3.7 — Multi-model routing documentation |
