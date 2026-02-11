# PRD: Eval Sandbox — Benchmarking & Regression Framework for Loa

**Version**: 1.1.0
**Status**: Draft (revised per Flatline Protocol review)
**Author**: Discovery Phase (plan-and-analyze)
**Issue**: [loa #277](https://github.com/0xHoneyJar/loa/issues/277)
**Date**: 2026-02-11

---

## 1. Problem Statement

Loa is a complex agent-driven development framework with 21 skills, 48 process compliance constraints, multiple quality gates, and a multi-phase workflow (plan → build → review → ship). Changes to any of these components — a SKILL.md rewrite, a protocol amendment, a config schema change, a new constraint — can have cascading effects on agent behavior across the entire system.

**There is currently no systematic way to know whether a change to Loa makes things better or worse.**

The real-world pattern:

1. Developer modifies a skill (e.g., improves `implementing-tasks` prompting)
2. Developer manually tests against one or two scenarios
3. Change gets merged through review + audit gates
4. Weeks later, a subtle regression surfaces — the skill now struggles with edge cases it previously handled
5. Nobody connects the regression to the earlier change because there's no baseline

**What's missing**:

- **No reproducible test scenarios**: Skills are tested ad-hoc against whatever project happens to be active. There are no fixture repositories with known outcomes.
- **No quality baselines**: There's no record of "this skill produced correct output for these 20 scenarios" that would catch a regression.
- **No deterministic graders**: Quality assessment is human judgment during review. Two reviewers might grade the same output differently.
- **No trial-level variance measurement**: Agent outputs are non-deterministic. A skill that passes once and fails twice has a 33% success rate, but we'd never know without multiple trials.
- **No CI integration**: Changes to `.claude/skills/` or `.claude/protocols/` can be merged without any automated quality check.

The existing test infrastructure (50+ TypeScript unit tests, shell script validators, skill benchmarks) tests *framework mechanics* — does the script run, does the config parse, does the quality gate trigger. It does **not** test *agent behavior* — does the skill produce good output when given a realistic task.

> Source: [Issue #277](https://github.com/0xHoneyJar/loa/issues/277), [Anthropic: Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

### Prior Art

The loa-finn ecosystem has established patterns that inform this design:

- **Ground Truth skill** ([PR #51](https://github.com/0xHoneyJar/loa-finn/pull/51), [PR #52](https://github.com/0xHoneyJar/loa-finn/pull/52)): 7-stage deterministic verification pipeline with no LLM in the verification path. Quality gates are shell scripts. Property-based testing with 100 generated test documents. This is the gold standard for the "code-based grader" pattern.
- **Bridgebuilder review** ([PR #54](https://github.com/0xHoneyJar/loa-finn/pull/54)): 547 tests across the test suite. Fixture-based testing with pass/fail examples and exit code contracts. Multi-layer testing (unit → integration → e2e).
- **Hounfour RFC** ([Issue #31](https://github.com/0xHoneyJar/loa-finn/issues/31)): Model adapter architecture with capability matrices and JSONL cost ledger — patterns for eval result storage and multi-model parameterization.
- **Bridgebuilder persona** ([Issue #24](https://github.com/0xHoneyJar/loa-finn/issues/24)): Structured review pipeline with severity levels and quality scoring — patterns for eval grading rubrics.

### Anthropic's Eval Framework

The [Anthropic engineering article](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) defines the canonical vocabulary:

| Concept | Definition | Loa Mapping |
|---------|-----------|-------------|
| **Task** | Individual test with defined inputs and success criteria | A skill invocation against a fixture repo with expected outcome |
| **Trial** | One attempt at a task (multiple needed for variance) | One execution of a skill against a fixture |
| **Grader** | Logic that scores performance | Shell scripts and TS assertions (code-based), LLM judges (model-based, future) |
| **Transcript** | Complete record of interactions, tool calls, reasoning | Agent session log capturing all tool calls and outputs |
| **Outcome** | Final environmental state demonstrating success | Files created, tests passing, quality gates satisfied |
| **Eval Harness** | Infrastructure managing end-to-end eval execution | The `/eval` skill + CI pipeline |

---

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurable Outcome |
|---|------|-------------------|
| G1 | Provide reproducible evaluation of Loa skill quality with explicit determinism boundaries | Framework evals: 100% deterministic (code-based graders). Agent evals: statistical determinism via pinned model params + multi-trial confidence intervals. |
| G2 | Catch regressions before merge | CI gate blocks PRs that degrade eval scores below baseline |
| G3 | Measure agent behavior, not just framework mechanics | Evals test skill output quality against realistic scenarios, not just "does the script parse" |
| G4 | Support iterative improvement with clear metrics | Developers see "this change improved /implement pass rate from 60% to 80%" before merging |
| G5 | Establish baselines for all core skills | Every skill with danger level ≥ moderate has at least 5 eval tasks with recorded baselines |
| G6 | Integrate with existing PR workflow | Eval results posted as structured PR comments alongside review/audit feedback |

### Determinism Model

> Flatline SKP-001 integration: Determinism means different things for different eval tiers.

| Eval Tier | Determinism Type | What's Pinned | Variance Handling |
|-----------|-----------------|---------------|-------------------|
| **Framework correctness** | Full determinism | Inputs + graders (no LLM) | Same input = same output. No trials needed. |
| **Regression (code-based graders)** | Grader determinism | Grader scripts. Agent output varies. | Multiple trials. Statistical pass rate. Grader itself is deterministic. |
| **Skill quality (agent execution)** | Statistical determinism | Model version, temperature, top_p, tool versions. Recorded per baseline. | ≥3 trials per task. Confidence intervals. Rerun-on-fail policy. Flake quarantine. |
| **E2E workflows** | Observational | Full environment snapshot | Advisory only — not used for merge gating |

**Flake handling**: If a task passes in <50% of trials across 3 consecutive eval runs, it enters quarantine (removed from regression suite, flagged for investigation). Quarantined tasks do not block merges.

### Success Metrics

| # | Metric | Current | Target |
|---|--------|---------|--------|
| M1 | Skills with automated eval coverage | 0/21 | ≥10/21 (all moderate+ skills) |
| M2 | Eval tasks per covered skill | 0 | ≥5 tasks per skill |
| M3 | Regression detection rate | 0% (manual only) | ≥90% (CI catches regressions before merge) |
| M4 | Time from PR to eval result | N/A | <5 minutes for framework evals (required check), <30 minutes for skill quality (async) |
| M5 | Eval result consistency | N/A | Code-based graders: 100% deterministic. Agent evals: <10% inter-run variance with pinned params. |
| M6 | False positive rate on regression alerts | N/A | <5% (evals don't block good changes) |

---

## 3. User & Stakeholder Context

### Primary Persona: Loa Framework Developer

The person modifying skills, protocols, constraints, or configurations within Loa. They need confidence that their changes don't break existing behavior and visibility into how their changes affect agent quality.

**Workflow**: Modify skill → run `/eval` locally → see results → iterate → push → CI eval gate passes → merge

### Secondary Persona: Loa Contributor / Reviewer

The person reviewing PRs to Loa. They need automated evidence that a change doesn't regress quality, beyond manual inspection of the diff.

**Workflow**: Open PR → see eval results in PR comment → understand impact → approve/request changes

### Tertiary Persona: Loa End User (Indirect)

Developers using Loa for their projects. They benefit from a framework that gets measurably better over time, with confidence that updates won't degrade their experience.

---

## 4. Functional Requirements

### FR1: Eval Harness — Task Definition & Execution

The eval harness is the core infrastructure that defines, executes, and grades evaluation tasks.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR1.1 | Define eval tasks as declarative YAML files with: task ID, schema version, skill target, fixture repo, input parameters, expected outcomes, grader(s), and metadata | P0 |
| FR1.2 | Execute eval tasks in isolated sandbox environments (container-based for CI, temp-dir for local dev) | P0 |
| FR1.3 | Support multiple trials per task (configurable, default: 3) to measure non-determinism | P0 |
| FR1.4 | Capture full transcripts of agent interactions during eval execution as structured JSONL: `{timestamp, tool_name, tool_input, tool_output, duration_ms, tokens_used}` | P1 |
| FR1.5 | Support task tagging for filtering: `category` (framework, skill, e2e), `skill` (implementing-tasks, reviewing-code, etc.), `difficulty` (basic, intermediate, advanced) | P1 |
| FR1.6 | Support eval suites — named collections of tasks that run together (e.g., "regression", "skill-quality", "framework-correctness") | P0 |
| FR1.7 | Task schema versioning: task YAML includes `schema_version` field. Harness validates schema compatibility and rejects unknown versions with actionable error. | P0 |
| FR1.8 | Task validation on load: verify required fields, fixture existence, grader script existence, and schema version before execution begins | P0 |

**Task Definition Example**:
```yaml
# evals/tasks/implement-simple-function.yaml
id: implement-simple-function
schema_version: 1
skill: implementing-tasks
category: skill-quality
difficulty: basic
fixture: fixtures/hello-world-ts
description: "Implement a simple TypeScript function from a clear specification"
input:
  sprint_task: "Implement isPrime(n) function in src/math.ts with full test coverage"
  acceptance_criteria:
    - "src/math.ts exports isPrime function"
    - "Handles edge cases: 0, 1, negative numbers, 2"
    - "Tests cover at least 5 cases"
trials: 3
timeout:
  per_trial: 120  # seconds
  per_grader: 30  # seconds
model:
  pin: true  # Record model version in results for baseline stability
graders:
  - type: code
    script: graders/file-exists.sh
    args: ["src/math.ts"]
  - type: code
    script: graders/tests-pass.sh
  - type: code
    script: graders/function-exported.sh
    args: ["isPrime", "src/math.ts"]
baseline:
  pass_rate: 0.67  # 2/3 trials expected to pass
  model_version: "claude-opus-4-6"
  recorded_at: "2026-02-11"
```

### FR2: Fixture Repositories — Sandbox Environments

Pre-built test repositories that provide deterministic, known-state inputs for eval tasks.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR2.1 | Store fixture repos as git bundles or template directories within the eval suite | P0 |
| FR2.2 | Each fixture defines: language/framework, directory structure, existing code, known bugs (for bug-fixing evals), missing features (for implementation evals), and a `fixture.yaml` metadata file | P0 |
| FR2.3 | Fixtures are cloned to isolated sandbox environments before each eval task — no cross-contamination between trials | P0 |
| FR2.4 | Fixture metadata (`fixture.yaml`) describes: scenario, difficulty, domain, language, required runtime, and dependency strategy | P1 |
| FR2.5 | Provide at least 5 fixture repos for MVP: TypeScript (simple), TypeScript (with bugs), Python (simple), shell scripts, and a Loa-style skill directory | P0 |
| FR2.6 | Fixture lifecycle: creation guide, versioning (semver tags), deprecation notice field in `fixture.yaml`, staleness check on eval run | P1 |
| FR2.7 | Dependency strategy per fixture: `prebaked` (vendored node_modules/venv), `offline-cache` (lockfile + cached packages), or `none` (no install needed). npm lifecycle scripts disabled by default (`--ignore-scripts`). | P0 |

### FR3: Code-Based Graders — Deterministic Scoring

Deterministic grading scripts that produce consistent pass/fail results. Follows loa-finn's "no LLM in the verification path" principle.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR3.1 | Graders are executable scripts (shell or TS) that receive the task workspace path and output a structured JSON result: `{pass: bool, score: 0-100, details: string, grader_version: string}` | P0 |
| FR3.2 | Provide a standard grader library covering: file existence, test execution (npm test / pytest), function export verification, pattern matching (grep-based), diff comparison, quality gate execution, secret scanning, constraint enforcement | P0 |
| FR3.3 | Graders must be deterministic — same input always produces same output. No network calls, no LLM invocations, no time-dependent logic | P0 |
| FR3.4 | Support composite graders that aggregate multiple sub-graders with configurable weights and aggregation strategy (`all_must_pass`, `weighted_average`, `any_pass`) | P1 |
| FR3.5 | Grader exit code contract: 0 = pass, 1 = fail, 2 = error (grader itself failed). Follows loa-finn's exit code pattern | P0 |
| FR3.6 | Per-grader timeout (default: 30s, configurable per task). Timeout = error (exit code 2), not fail. | P0 |
| FR3.7 | Future: model-based graders (LLM-as-judge) as a second grader type. Deferred to Phase 2. | P2 |

### FR4: Result Storage & Baseline Management

JSONL-based result storage with baseline comparison for regression detection.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR4.1 | Store eval results as JSONL entries with: task ID, trial number, timestamp, grader results, pass/fail, score, duration, model version, transcript hash, run ID | P0 |
| FR4.2 | Maintain baselines as committed YAML files (one per eval suite) with expected pass rates per task, pinned model version, and recording date | P0 |
| FR4.3 | Compare current eval run against baseline and report: improvements, regressions, unchanged, and new (no baseline) | P0 |
| FR4.4 | Baseline update workflow: run evals → review results → submit baseline update PR with rationale → CODEOWNERS review → merge | P0 |
| FR4.5 | CLI report showing pass rates, score distributions, and regression alerts in human-readable format | P0 |
| FR4.6 | Result retention: keep last 100 eval runs per suite. Configurable via `.loa.config.yaml` | P1 |
| FR4.7 | Baseline governance: updates require a PR with rationale in description. Baseline YAML files are owned by CODEOWNERS. Tasks in quarantine are labeled separately and do not affect regression scoring. | P0 |
| FR4.8 | Baseline diff reporting: when baselines change, the PR shows before/after for each task (pass rate, model version, trial count) | P1 |

### FR5: CLI Integration — `/eval` Command

The primary developer interface for running evals locally.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR5.1 | `/eval` — run all eval suites (default behavior) | P0 |
| FR5.2 | `/eval <suite>` — run a specific suite (e.g., `/eval regression`, `/eval skill-quality`) | P0 |
| FR5.3 | `/eval --task <id>` — run a single task (for development/debugging) | P0 |
| FR5.4 | `/eval --skill <name>` — run all tasks targeting a specific skill | P1 |
| FR5.5 | `/eval --update-baseline` — update baselines from current results (requires confirmation) | P0 |
| FR5.6 | `/eval --compare <run-id>` — compare two eval runs | P1 |
| FR5.7 | Display results in terminal with pass/fail indicators, scores, and regression alerts | P0 |

### FR6: CI Integration — GitHub Actions

Automated eval execution on PRs with results posted as comments.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR6.1 | GitHub Action workflow triggered on PRs that modify `.claude/skills/`, `.claude/protocols/`, `.claude/data/`, or `.loa.config.yaml` | P0 |
| FR6.2 | Run the `framework` + `regression` eval suites on every qualifying PR | P0 |
| FR6.3 | Post structured eval results as a PR comment (see PR Comment Format below) | P0 |
| FR6.4 | Block PR merge (via required check) if framework eval or regression eval score drops below baseline by configurable threshold (default: 10%) | P1 |
| FR6.5 | Support `eval-skip` label on PRs to bypass eval gate (for documentation-only changes) | P1 |
| FR6.6 | Cache fixture repos and dependency caches between CI runs to reduce setup time | P1 |
| FR6.7 | CI security: graders and harness scripts used in CI are sourced from the base branch, not the PR branch. Only task definitions and fixture content from the PR are used. | P0 |
| FR6.8 | CI execution environment: containerized with read-only root filesystem (except workspace mount), controlled env vars (no secrets exposed to eval), network namespace with egress blocked, npm lifecycle scripts disabled. | P0 |
| FR6.9 | Fork PR restriction: eval CI does not run on fork PRs (prevents untrusted code execution). Fork PRs get a comment explaining how to trigger evals after review. | P1 |

**PR Comment Format**:

```markdown
## Eval Results — `<suite-name>`

**Run ID**: `eval-run-<hash>` | **Duration**: 3m 42s | **Model**: claude-opus-4-6

### Summary
| Status | Count |
|--------|-------|
| ✅ Pass | 18 |
| ❌ Fail | 1 |
| ⚠️ Regression | 1 |
| 🆕 New (no baseline) | 2 |

### Regressions
| Task | Baseline | Current | Delta |
|------|----------|---------|-------|
| `implement-error-handling` | 100% (3/3) | 33% (1/3) | -67% ⛔ |

### Improvements
| Task | Baseline | Current | Delta |
|------|----------|---------|-------|
| `review-catches-xss` | 67% (2/3) | 100% (3/3) | +33% ✅ |

### New Tasks (no baseline)
- `validate-new-constraint`: 100% (3/3)
- `audit-finds-sqli`: 67% (2/3)

<details><summary>Full Results</summary>
[... per-task details ...]
</details>

---
*Eval Sandbox v1.0 | [View run details](evals/results/eval-run-<hash>.jsonl)*
```

### FR7: Framework Correctness Evals

Evals that test Loa's infrastructure contracts without requiring agent execution.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR7.1 | Validate all 48 constraints in `constraints.json` are enforced by the corresponding protocol or skill | P0 |
| FR7.2 | Validate golden path routing: `/loa`, `/plan`, `/build`, `/review`, `/ship` resolve to correct skills | P0 |
| FR7.3 | Validate skill index: all skills in `.claude/skills/` have valid `index.yaml` with required fields | P0 |
| FR7.4 | Validate quality gate pipeline: review + audit gates produce blocking results for known-bad inputs | P1 |
| FR7.5 | Validate beads integration: task lifecycle transitions are tracked correctly | P1 |
| FR7.6 | Validate config schema: `.loa.config.yaml` merges correctly with defaults and overrides | P1 |

### FR8: Error Handling & Partial Failure Semantics

> Flatline IMP-008 integration: Define how the system behaves when things go wrong.

| ID | Requirement | Priority |
|----|-------------|----------|
| FR8.1 | Error taxonomy: `infrastructure_error` (sandbox failed, grader crashed), `eval_failure` (task failed grading), `timeout` (trial/grader exceeded limit), `budget_exceeded` (cost cap hit) | P0 |
| FR8.2 | Retry policy: `infrastructure_error` retries once automatically. `eval_failure` does not retry (it's a real result). `timeout` counts as failure, no retry. `budget_exceeded` stops the suite. | P0 |
| FR8.3 | Suite abort vs continue: on infrastructure error after retry, log the error and continue to remaining tasks. Report partial results with clear indication of which tasks were skipped. | P0 |
| FR8.4 | CI exit codes: 0 = all pass, 1 = regressions detected, 2 = infrastructure errors (should not block merge), 3 = configuration error (harness broken) | P0 |
| FR8.5 | Partial results: always publish results for completed tasks even if the suite didn't finish. PR comment clearly marks incomplete runs. | P1 |

---

## 5. Technical & Non-Functional Requirements

### Performance

> Flatline SKP-004 integration: Tiered gating with realistic targets and explicit caching strategy.

| Suite | Target | Gate Type | Caching Strategy |
|-------|--------|-----------|-----------------|
| Framework correctness | <2 minutes | Required check (blocking) | None needed (no external deps) |
| Regression (code-based graders) | <5 minutes | Required check (blocking) | Fixture snapshots, package manager caches |
| Skill quality (agent execution) | <30 minutes | Async (non-blocking comment) | Pre-built fixture images, model response caching for identical prompts |
| E2E workflows | <2 hours | Scheduled (nightly), not per-PR | Full environment snapshots |

**Parallelism**: Tasks within a suite run in parallel (up to configurable concurrency limit, default: 4). Trials within a task run sequentially (to avoid resource contention).

**Hard timeouts**: Per-trial timeout (default: 120s for framework, 300s for skill quality). Per-suite timeout (default: 2x target). Timeout produces a structured error result, not a hang.

### Determinism

| Eval Tier | Determinism Guarantee | Pinned Parameters |
|-----------|----------------------|-------------------|
| Framework correctness | 100% deterministic | N/A (no LLM) |
| Regression (code-based graders) | Grader output deterministic; agent output varies | Grader version in results |
| Skill quality (agent execution) | Statistical (confidence intervals) | Model version, temperature, top_p, tool versions. All recorded per baseline. |

### Cost

| Requirement | Details |
|-------------|---------|
| Framework correctness evals | Zero LLM cost (pure shell/TS scripts) |
| Skill quality evals | ~$0.50-2.00 per task trial (Claude API for agent execution) |
| Metering | All eval API calls tracked in JSONL cost ledger (follows Hounfour pattern) |
| Budget cap | Per-run budget limit (default: $5.00). Suite aborts when cap reached, partial results published. |

### Security

> Flatline SKP-002, SKP-006 integration: Defense-in-depth sandbox model.

| Layer | Local Dev | CI |
|-------|-----------|-----|
| **Filesystem isolation** | Temp directory with fresh fixture clone | Container with read-only root, workspace mount only |
| **Environment** | Inherited (developer machine) | Controlled: no secrets, fixed locale/timezone, minimal PATH |
| **Network** | Advisory (graders should not use network) | Enforced: network namespace with egress blocked |
| **Process** | Standard user | Restricted: no privilege escalation, resource limits (CPU, memory, disk) |
| **Code trust** | All code from local repo | Graders/harness from base branch only. Task definitions from PR allowed (validated). Fork PRs blocked. |
| **Dependency safety** | Developer responsibility | npm `--ignore-scripts`, pip `--no-deps` with vendored wheels, no postinstall hooks |

**Threat model**: The CI eval system must assume that PR authors may be adversarial. Graders and harness infrastructure are trusted (sourced from base branch). Fixture content and task definitions from PRs are semi-trusted (validated before execution). Agent-generated code within sandboxes is untrusted (sandboxed execution).

**PATH_SAFETY**: Apply loa-finn's 4-layer defense for any file path operations within graders.

### Extensibility

| Requirement | Details |
|-------------|---------|
| Model-agnostic harness | Task definitions don't reference specific models — model is injected at runtime |
| Cross-repo ready | Harness architecture supports evaluating loa-finn and arrakis skills in future |
| Custom graders | Users can add graders by dropping scripts into the graders directory |

---

## 6. Scope & Prioritization

### Build Order

The four eval focuses are built iteratively, each layer building on the previous:

| Phase | Focus | Why This Order | Depends On |
|-------|-------|---------------|------------|
| **Phase 1** | Framework Correctness | Deterministic, no agent execution, validates infrastructure everything else depends on. Cheapest to run, fastest to build. | Nothing |
| **Phase 2** | Regression Protection | Establishes baselines + CI gate. Catches breakage from Phase 1 infra changes. Uses code-based graders. | Phase 1 (harness + graders) |
| **Phase 3** | Skill Output Quality | Tests agent behavior with fixture repos. Most novel and valuable layer. Requires agent execution. | Phase 2 (baselines + fixture repos) |
| **Phase 4** | End-to-End Workflows | Full plan→build→review→ship cycles. Most expensive, most realistic. | Phase 3 (skill evals + sandbox) |

### MVP Definition (Phases 1-2)

The minimum viable eval system delivers:

1. Eval harness that reads YAML task definitions (with schema versioning) and executes them
2. Fixture repository infrastructure (5 repos with dependency strategy)
3. Standard grader library (8 graders with exit code contract)
4. JSONL result storage with baseline comparison and governance workflow
5. `/eval` CLI command
6. Framework correctness eval suite (≥20 tasks)
7. Regression eval suite with baselines (≥10 tasks)
8. GitHub Actions workflow with PR comment reporting and CI security hardening
9. Error handling with error taxonomy, retry policy, and partial result publishing

### Phase 3 Additions

- Skill quality eval suite (≥30 tasks across 10 skills)
- Agent execution sandbox with transcript capture (structured JSONL transcripts)
- Multi-trial variance measurement (pass@k, pass^k) with confidence intervals
- Cost tracking per eval run with budget enforcement
- Container-based sandboxing for CI (read-only root, network isolation)
- Flake quarantine workflow

### Phase 4 Additions (Future)

- E2E workflow evals against realistic project scenarios
- Model-based graders (LLM-as-judge)
- Multi-model comparison (when Hounfour lands)
- Dashboard for eval trend visualization
- Human grader workflow for calibration

### Out of Scope (Explicit)

| Item | Reason |
|------|--------|
| Multi-model eval | Deferred until Hounfour provider abstraction lands |
| Web dashboard | JSONL + CLI + PR comments sufficient for MVP |
| User-facing eval (end users testing their projects) | This is a framework-internal tool |
| Performance benchmarking (latency, tokens) | Focus is on quality, not speed |
| Eval authoring UI | YAML files + fixture repos are the authoring interface |

---

## 7. Risks & Dependencies

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Agent execution in CI is expensive | High | Medium | Phase 1-2 use no agent execution. Phase 3+ runs async (non-blocking). Cost cap per run ($5 default). |
| Non-deterministic agent outputs make grading unreliable | High | High | Explicit determinism model (Section 2). Pinned model params per baseline. Confidence intervals. Flake quarantine. |
| Fixture repos become stale as Loa evolves | Medium | Medium | Fixtures are versioned (semver). Staleness checks on eval run. Deprecation field in fixture.yaml. |
| CI eval time exceeds acceptable PR latency | Medium | Medium | Tiered gating: framework (<2 min, blocking) + regression (<5 min, blocking) + skill quality (<30 min, async non-blocking). |
| False regression alerts block legitimate improvements | Medium | High | Configurable threshold (default: 10% drop). Flake quarantine. `eval-skip` label. Baseline update workflow with rationale. |
| CI security: malicious PR exfiltrates secrets via graders | Medium | Critical | Graders sourced from base branch. Fork PRs blocked. Container sandboxing with egress blocked. No secrets in eval env. |
| Baseline gaming: developers update baselines to paper over regressions | Low | Medium | Baseline updates require PR with rationale. CODEOWNERS review. Baseline diff reporting shows before/after. |

### Dependencies

| Dependency | Type | Status | Risk |
|------------|------|--------|------|
| Claude API access in CI | External | Available | API key management in GitHub secrets (not exposed to eval sandbox) |
| Fixture repo maintenance | Internal | New effort | Need ownership assignment |
| Beads (br) for task tracking | Internal | Available | Works without beads via opt-out |
| GitHub Actions minutes | External | Available | Cost scales with eval suite size |
| Node.js / TypeScript runtime | Internal | Available | Already in use for lib tests |
| Container runtime (Docker/Podman) for CI sandboxing | External | Available on GitHub runners | Phase 3+ requirement |

### Open Questions

| # | Question | Default Assumption |
|---|----------|-------------------|
| Q1 | Should eval results be stored in the Loa repo or a separate repo? | Same repo, under `evals/results/` (gitignored except baselines) |
| Q2 | How do we handle eval flakiness from model non-determinism? | 3 trials per task, pass rate threshold (2/3 must pass). Flake quarantine after 3 consecutive flaky runs. |
| Q3 | Should we eval against pinned model versions or latest? | Pin per baseline. Record model version. Baseline update required when model version changes. |
| Q4 | How do we bootstrap initial baselines? | Run evals against current main, commit results as v1 baseline with rationale. |

---

## 8. Eval Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        /eval CLI                                 │
│  Parse args → Load suite → Validate tasks → Execute → Report     │
├─────────────────────────────────────────────────────────────────┤
│                      EVAL HARNESS                                │
│  Task loader (YAML) · Schema validator · Trial executor          │
│  ↕ Reads task definitions, validates schema, runs trials         │
├─────────────────────────────────────────────────────────────────┤
│                    SANDBOX LAYER                                  │
│  Fixture cloner · Container manager (CI) / Temp dir (local)      │
│  ↕ Isolated environments per trial. Egress blocked in CI.        │
├──────────────────────┬──────────────────────────────────────────┤
│   GRADER LAYER       │        RESULT LAYER                       │
│  Code-based graders  │  JSONL storage · Baseline manager         │
│  Composite graders   │  Comparison engine · Flake detector       │
│  Exit code contract  │  PR comment formatter                     │
│  Per-grader timeout  │  Baseline governance                      │
├──────────────────────┴──────────────────────────────────────────┤
│                   REPORTING LAYER                                 │
│  CLI terminal output · GitHub PR comments · JSONL ledger          │
│  Error taxonomy · Partial result publishing                       │
└─────────────────────────────────────────────────────────────────┘
```

### Directory Structure

```
evals/
├── README.md                    # How to write and run evals
├── suites/                      # Named eval suites
│   ├── framework.yaml           # Framework correctness suite
│   ├── regression.yaml          # Regression protection suite
│   └── skill-quality.yaml       # Skill output quality suite
├── tasks/                       # Individual task definitions
│   ├── framework/               # Framework correctness tasks
│   │   ├── validate-constraints.yaml
│   │   ├── golden-path-routing.yaml
│   │   └── skill-index-integrity.yaml
│   ├── regression/              # Regression tasks
│   │   ├── implement-simple-function.yaml
│   │   └── review-catches-bug.yaml
│   └── skill-quality/           # Skill quality tasks
│       ├── implement-typescript-feature.yaml
│       └── audit-finds-xss.yaml
├── fixtures/                    # Test repositories
│   ├── hello-world-ts/          # Simple TypeScript project
│   │   └── fixture.yaml         # Metadata: deps=prebaked, lang=typescript
│   ├── buggy-auth-ts/           # TypeScript with known bugs
│   ├── simple-python/           # Simple Python project
│   ├── shell-scripts/           # Shell script project
│   └── loa-skill-dir/           # Mock Loa skill directory
├── graders/                     # Grading scripts
│   ├── file-exists.sh           # Check file existence
│   ├── tests-pass.sh            # Run test suite
│   ├── function-exported.sh     # Check function export
│   ├── pattern-match.sh         # Grep-based pattern check
│   ├── diff-compare.sh          # Compare against expected output
│   ├── quality-gate.sh          # Run Loa quality gates
│   ├── no-secrets.sh            # Scan for leaked secrets
│   └── constraint-enforced.sh   # Verify constraint enforcement
├── baselines/                   # Committed baseline scores (CODEOWNERS protected)
│   ├── framework.baseline.yaml
│   ├── regression.baseline.yaml
│   └── skill-quality.baseline.yaml
├── results/                     # Run results (gitignored except baselines)
│   └── .gitkeep
└── harness/                     # Harness implementation
    ├── run-eval.sh              # Main eval runner
    ├── sandbox.sh               # Sandbox provisioning (local: tmpdir, CI: container)
    ├── grade.sh                 # Grader orchestration with timeouts
    ├── report.sh                # CLI report generation
    ├── compare.sh               # Baseline comparison + flake detection
    └── pr-comment.sh            # GitHub PR comment formatter
```

---

## 9. Relationship to Existing Infrastructure

| Existing Component | Relationship to Eval System |
|---|---|
| `.claude/lib/__tests__/` | Complementary — unit tests test framework internals, evals test agent behavior |
| `.claude/scripts/test-skill-benchmarks.sh` | Predecessor — validates skill structure, not skill output quality |
| `.claude/scripts/test-flatline-autonomous.sh` | Inspiration — e2e test pattern for autonomous workflows |
| `grimoires/loa/a2a/` | Results storage precedent — eval results follow similar structure |
| loa-finn `tests/ground-truth/` | Direct ancestor — property-based testing and quality gate patterns |
| loa-finn `tests/fixtures/` | Pattern source — fixture-based testing approach |
| Hounfour cost ledger (JSONL) | Pattern source — metering and result storage format |
| Bridgebuilder review pipeline | Pattern source — structured findings with severity levels |

---

## 10. Configuration

```yaml
# .loa.config.yaml additions
eval:
  enabled: true
  suites:
    default: ["framework", "regression"]  # Suites to run by default
    ci: ["framework", "regression"]       # Suites for CI (blocking)
    ci_async: ["skill-quality"]           # Suites for CI (non-blocking async)
    full: ["framework", "regression", "skill-quality"]  # Full evaluation
  trials:
    default: 3                # Trials per task (overridable per task)
    ci: 1                     # Fewer trials in CI for speed
  timeout:
    per_trial: 120            # Default per-trial timeout (seconds)
    per_grader: 30            # Default per-grader timeout (seconds)
    per_suite_multiplier: 2   # Suite timeout = target * multiplier
  regression:
    threshold: 0.10           # 10% drop triggers regression alert
    block_merge: true         # Block PR merge on regression
    flake_quarantine:
      enabled: true
      consecutive_flaky_runs: 3  # Quarantine after N flaky runs
  results:
    retention: 100            # Keep last N runs per suite
    ledger_path: "evals/results/eval-ledger.jsonl"
  ci:
    post_pr_comment: true
    required_check: true
    skip_label: "eval-skip"
    fork_pr_policy: "block"   # block | comment-only
    sandbox:
      container: true         # Use container-based sandbox in CI
      network: "none"         # none | host (for special cases)
      ignore_scripts: true    # Disable npm lifecycle scripts
  cost:
    budget_per_run: 5.00      # USD cap per eval run
    track_usage: true
  baseline:
    require_rationale: true   # Baseline updates must include rationale
    pin_model_version: true   # Record model version per baseline
```

---

## 11. Flatline Protocol Integration Log

| Finding | Category | Action | Integration |
|---------|----------|--------|-------------|
| IMP-001 | HIGH_CONSENSUS | Auto-integrated | Task schema versioning added (FR1.7, FR1.8) |
| IMP-002 | HIGH_CONSENSUS | Auto-integrated | Transcript schema defined (FR1.4) |
| IMP-003 | HIGH_CONSENSUS | Auto-integrated | Composite grader semantics expanded (FR3.4) |
| IMP-004 | HIGH_CONSENSUS | Auto-integrated | Fixture lifecycle added (FR2.6) |
| IMP-005 | HIGH_CONSENSUS | Auto-integrated | Per-trial/per-grader timeouts (FR3.6, task example, config) |
| IMP-006 | HIGH_CONSENSUS | Auto-integrated | PR comment format specified (FR6 section) |
| IMP-007 | HIGH_CONSENSUS | Auto-integrated | Task validation on load (FR1.8) |
| IMP-008 | HIGH_CONSENSUS | Auto-integrated | Error handling section added (FR8) |
| IMP-009 | HIGH_CONSENSUS | Auto-integrated | Dependency strategy per fixture (FR2.7) |
| SKP-001 | BLOCKER (CRITICAL) | Accepted | Determinism model added (Section 2), pinned model params, flake quarantine |
| SKP-002 | BLOCKER (CRITICAL) | Accepted | CI security section (Section 5), base-branch graders (FR6.7-6.9), threat model |
| SKP-003 | BLOCKER (HIGH) | Accepted | Baseline governance (FR4.7-4.8), CODEOWNERS, rationale requirement |
| SKP-004 | BLOCKER (HIGH) | Accepted | Tiered gating (Section 5), caching strategy, parallelism, hard timeouts |
| SKP-006 | BLOCKER (HIGH) | Accepted | Container sandboxing (Section 5 Security), layered isolation model |

---

## Next Step

After PRD approval: `/architect` to create Software Design Document detailing harness implementation, grader contracts, sandbox isolation, and CI pipeline design.
