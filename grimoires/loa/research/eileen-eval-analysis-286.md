# Deep Analysis: Eileen's Eval Feedback vs Current Implementation

**Issue**: [#286](https://github.com/0xHoneyJar/loa/issues/286)
**Source**: `eileen1337` review comments on [PR #282](https://github.com/0xHoneyJar/loa/pull/282)
**Date**: 2026-02-12
**Status**: Living Document

---

## Executive Summary

Eileen provided 6 comments on PR #282 (Eval Sandbox) identifying 8 concrete enhancements to transform the eval framework from a regression detector into a scientific optimization platform. This document maps each suggestion against the current codebase, identifies gaps, and assesses feasibility.

**Key finding**: ~60% of the infrastructure Eileen describes already exists in some form. The primary gaps are: (1) version traceability in result records, (2) output contract enforcement via graders, and (3) A/B variant management.

---

## Current State Inventory

### Result Schema (run-eval.sh L413-428)

Per-trial JSONL records currently include:
```json
{
  "run_id": "run-20260211-062649-1c27b11f",
  "task_id": "config-has-run-mode",
  "trial": 1,
  "timestamp": "2026-02-11T06:26:49Z",
  "duration_ms": 334,
  "model_version": "none",
  "status": "completed",
  "graders": [{"name": "...", "pass": true, "score": 100, "grader_version": "1.0.0", ...}],
  "composite": {"strategy": "all_must_pass", "pass": true, "score": 100},
  "error": null,
  "schema_version": 1
}
```

Run metadata (run-meta.json) adds: `git_sha`, `git_branch`, `harness_version` ("1.0.0"), `cost_usd`, `environment`.

### Grader Infrastructure

9 code-based graders, all returning binary 0 or 100 scores:

| Grader | Purpose | Score Range |
|--------|---------|-------------|
| file-exists.sh | Check file presence | 0 or 100 |
| pattern-match.sh | Regex search (ReDoS protected) | 0 or 100 |
| function-exported.sh | Language-aware export check | 0 or 100 |
| constraint-enforced.sh | Constraint in enforcement layers | 0 or 100 |
| tests-pass.sh | Run test suite (allowlisted commands) | 0 or 100 |
| diff-compare.sh | Compare against expected output | 0 or 100 |
| quality-gate.sh | Skill index, constraints, config validity | 0 or 100 |
| skill-index-validator.sh | Index.yaml structural checks | 0 or 100 |
| no-secrets.sh | Secret pattern scanning | 0 or 100 |

**Key observation**: `weighted_average` composite strategy exists but is unused — all tasks use `all_must_pass`.

### Versioning Infrastructure

| Component | Version Field | Location |
|-----------|--------------|----------|
| Constraints registry | `"version": "1.0.0"` | `.claude/data/constraints.json` L3 |
| Harness | `HARNESS_VERSION="1.0.0"` | `evals/harness/run-eval.sh` L17 |
| Git SHA | `git rev-parse --short HEAD` | run-meta.json |
| Skill prompts | **NONE** | No `version` field in skill `index.yaml` |
| Loa framework | `version: 1.33.0` | `.claude/loa/CLAUDE.loa.md` header |

### Output Contract Templates

Templates exist for all 3 target skills but are NOT machine-validated:

| Skill | Template | Required Sections |
|-------|----------|-------------------|
| implementing-tasks | `resources/templates/implementation-report.md` | Executive Summary, Tasks Completed, Testing Summary, Version Update |
| reviewing-code | `resources/templates/review-feedback.md` | Verdict, Critical Issues (with file:line), Acceptance Criteria Check |
| auditing-security | `resources/templates/sprint-audit-feedback.md` | Verdict, Severity Table, Findings (with PoC + CWE/OWASP) |

24 JSON schemas exist in `.claude/schemas/` but NONE validate skill output content.

---

## Suggestion-by-Suggestion Analysis

### 1. Define "Good Output" as Measurable Signals

**Eileen's ask**: Constraint compliance rate, schema validity, grounding coverage, verbosity control — all scored numerically.

**What exists**:
- Graders return `score: 0-100` — infrastructure supports continuous scoring
- `weighted_average` composite strategy would enable nuanced scoring
- No grader produces intermediate scores (all binary 0/100)

**Gap assessment**: MEDIUM
- Infrastructure is ready; just need graders that use the full 0-100 range
- "Constraint compliance" requires knowing which constraints apply to a given output — mapping doesn't exist
- "Grounding coverage" (% of claims with citations) is heuristic but implementable via regex

**Pros**:
- Unlocks Pareto analysis: "80% of failures come from 3 constraint violations"
- Enables trend tracking: "structure scores improving, completeness declining"
- No schema changes needed — just new graders

**Cons**:
- Risk of metric gaming: agents optimize for measurable signals at expense of actual quality
- Scoring heuristics need calibration against human judgment
- "Verbosity control" is subjective — token count is measurable but "appropriate length" isn't

**Recommendation**: HIGH PRIORITY. Build 3 scoring graders (constraint-compliance, citation-coverage, completeness) and start using `weighted_average`.

---

### 2. Build an Eval Set (30-50 Cases per Skill)

**Eileen's ask**: Eval cases with `input`, `context`, `requirements`, `grading`. Focus on real failures.

**What exists**:
- 11 regression tasks (4 implementation, 4 review, 3 bug detection)
- Task YAML has `prompt` but no `context` or `requirements` fields
- 5 fixture repos (hello-world-ts, buggy-auth-ts, etc.)
- All tasks are synthetic (none from real failure patterns)

**Gap assessment**: LARGE
- Need 10x more tasks and fixtures
- Schema extension needed for `context` and `requirements`
- Creating realistic fixtures from real failures requires mining past sessions

**Pros**:
- Highest-ROI investment: more tasks = better regression detection
- Fixture architecture already supports this growth
- Each new task is incremental (YAML + optional fixture)

**Cons**:
- 30-50 tasks x 3 skills = 90-150 new YAML files + fixtures to maintain
- Agent evals are expensive: 3 trials x 150 tasks at LLM cost
- Early stopping mitigates but doesn't eliminate cost
- Risk of low-quality tasks that don't test meaningful behavior

**Recommendation**: MEDIUM PRIORITY. Start with 15 tasks per skill (45 total), focusing on edge cases and cross-skill handoffs. Scale to 30+ after infrastructure (contracts, scoring) is in place.

---

### 3. Add Output Contracts

**Eileen's ask**: Structured schemas for agent outputs. JSON Schema or section structure validation.

**What exists**:
- SKILL.md templates define implicit contracts with required sections, verdict formats, citation patterns
- `skill-index.schema.json` declares output paths/formats but doesn't validate content
- No grader validates output structure
- `pattern-match.sh` could check section headers but is brittle

**Gap assessment**: MEDIUM
- Templates already define the contracts — formalization is incremental
- Need: JSON contract schemas + `output-contract.sh` grader
- Grader must handle markdown structure (heading detection, pattern matching)

**Pros**:
- Closes the loop between "what the skill should produce" and "what we verify"
- Contract violations become measurable: "implementing-tasks has 85% structure compliance"
- Contracts serve as documentation AND enforcement

**Cons**:
- Markdown schema validation is inherently fuzzy — formatting varies
- Over-strict contracts reduce agent creativity (novel insights may not fit template)
- Maintenance burden: every template change requires contract update
- Need to decide: "must have section" vs "must have section with specific content"

**Recommendation**: HIGH PRIORITY. Derive contracts mechanically from existing templates. Start with section presence + verdict format (high confidence) before adding content depth checks.

---

### 4. Compose Prompts/Policies from Registry Like Software

**Eileen's ask**: Semantic versioning for registry modules, conflict detection, version IDs in eval results.

**What exists**:
- `constraints.json` has `"version": "1.0.0"` (registry-level semver)
- Individual constraints have `id` but no per-constraint version
- Skills have `index.yaml` with NO version field
- `harness_version` already in run-meta.json
- `git_sha` already provides implicit traceability

**Gap assessment**: SMALL for registry version, LARGE for skill versioning
- Adding `constraints_registry_version` to results: ~5 lines of code
- Adding `version` to skill index.yaml: needs touching all 21 files + schema + validator

**Pros**:
- Enables "regression started at constraints v1.4.0" analysis
- `git_sha` alone is too coarse — can't distinguish "constraint change" from "fixture change"
- Versioning discipline forces intentional changes

**Cons**:
- `skill_prompt_version` requires maintaining semver across 21 skills — overhead
- Per-constraint versioning is overkill — registry version + git SHA sufficient
- Conflict detection requires semantic understanding of constraint interactions (complex)
- Risk of versioning bureaucracy slowing development

**Recommendation**: P0 for registry version in results. Add `version` field to skill index.yaml with initial "1.0.0" for all skills. Defer per-constraint versioning and conflict detection.

---

### 5. Build Regression Harness (CI for Agent Quality)

**Eileen's ask**: Deterministic checks + judge-based scoring, per-constraint violation tracking.

**What exists**:
- **Already built**: Full eval sandbox with CI pipeline, baseline comparison, Wilson CI, regression gates
- Missing: judge-based scoring (no `model`-type grader implementation)
- Missing: per-constraint violation tracking in results

**Gap assessment**: SMALL
- Core infrastructure IS this harness
- Adding constraint ID tracking to graders is incremental
- Judge graders deferred (trust model concern)

**Pros**:
- Foundation exists — enhancement, not greenfield
- Per-constraint violation tracking enables "C-PROC-004 violations went up after v1.3.2"

**Cons**:
- LLM judge grading introduces non-determinism (flaky CI)
- Judge calls add cost ($0.05-0.15 per judgment)
- Trust issue: judge model != evaluated model (but who judges the judge?)

**Recommendation**: LOW PRIORITY (mostly done). Add constraint ID tracking to grader output format. Defer LLM judges.

---

### 6. Controlled Experiments (A/B Testing)

**Eileen's ask**: A/B prompt/policy testing, paired comparison across same eval cases.

**What exists**:
- `compare.sh` supports baseline comparison with delta computation
- Model version skew detection marks cross-model results as `advisory`
- Wilson CI for statistical rigor
- **No A/B framework** — always "current vs baseline", never "variant A vs variant B"

**Gap assessment**: MEDIUM
- Building on compare.sh is natural
- Need: `--variant` flag in run-eval.sh, dual-result comparison in compare.sh
- Statistical tests: McNemar's (pass/fail), Wilcoxon (scores)

**Pros**:
- Enables scientific prompt optimization: "this constraint rewrite improved compliance by 12%"
- Path to Hounfour routing layer's empirical model selection
- Sequential testing (Suggestion 8) reduces A/B cost

**Cons**:
- Adds complexity: two baselines, variant tracking, paired analysis
- Requires larger eval sets for statistical significance (depends on Suggestion 2)
- Risk of p-hacking without pre-registration discipline
- Storage doubles (results for both variants)

**Recommendation**: MEDIUM PRIORITY. Implement after eval set expansion (Suggestion 2) provides enough tasks for meaningful comparison.

---

### 7. Critic/Reviser Loop for High-Stakes Skills

**Eileen's ask**: Generator -> Critic -> Reviser pipeline for high-reliability output.

**What exists**:
- Flatline Protocol provides multi-model adversarial review (but for documents, not agent outputs)
- Review -> Audit cycle implements two-pass validation (but session-level, not output-level)
- `/run` mode implements iterate-on-feedback but via full session cycles

**Gap assessment**: MEDIUM
- Patterns exist but not as automated output-level loops
- Needs: in-eval-loop critic, revision mechanism, circuit breaker

**Pros**:
- Dramatically improves constraint compliance and format adherence
- High-stakes skills (auditing-security) benefit most
- Circuit breaker prevents infinite loops

**Cons**:
- Adds 2-3x latency per eval task
- Token cost triples (generate + critique + revise)
- Recursive risk: critic finds issue -> reviser introduces new issue
- Philosophical tension: improving output vs teaching dependency on post-processing

**Recommendation**: LOW PRIORITY. Implement last (Sprint 5). The critic/reviser is most valuable AFTER output contracts and scoring graders exist (they define what the critic checks against).

---

### 8. Comprehensive Instrumentation

**Eileen's ask**: Per-run logging of registry versions, constraint pass/fail, score breakdowns, latency, tokens.

**What exists**:
- Already tracked: `run_id`, `task_id`, `trial`, `duration_ms`, `graders[]`, `composite`, `model_version`, `git_sha`, `harness_version`, `cost_usd`
- Missing: `constraints_registry_version`, `skill_prompt_version`, per-constraint violation array, score breakdowns
- Trajectory logging exists (`grimoires/loa/a2a/trajectory/`) but isn't integrated with eval results

**Gap assessment**: SMALL for version fields, MEDIUM for constraint-level tracking
- Adding version fields is trivial (~10 lines)
- Per-constraint violation tracking requires graders to report which constraints they checked
- Tool call tracing doesn't exist in agent evals (framework evals don't invoke agents)

**Pros**:
- Most logging infrastructure exists — just needs fields
- Linking results to trajectory logs enables "why did this trial fail?" debugging
- Enables the Pareto analysis Eileen describes

**Cons**:
- Per-constraint tracking requires ALL graders to report constraint IDs (interface change)
- Storage growth at scale
- Tool call tracing requires agent eval execution (future scope)

**Recommendation**: HIGH PRIORITY for version fields (overlaps with Suggestion 4). MEDIUM PRIORITY for constraint-level tracking.

---

## Priority Matrix

| # | Suggestion | Gap | Effort | Impact | Priority |
|---|-----------|-----|--------|--------|----------|
| 4 | Registry versioning in results | Small | Low | High | **P0** |
| 8 | Instrumentation (version fields) | Small | Low | High | **P0** |
| 3 | Output contracts | Medium | Medium | High | **P1** |
| 1 | Measurable quality signals | Medium | Medium | High | **P1** |
| 5 | Regression harness enhancements | Small | Low | Medium | **P2** |
| 2 | Eval set expansion | Large | High | High | **P2** |
| 6 | A/B experiments | Medium | Medium | Medium | **P3** |
| 7 | Critic/reviser loop | Medium | High | Medium | **P3** |

---

## Proposed Build Order

```
Sprint 1: Schema + Skill Versioning (FR-1, FR-2)
  └─ Add version fields to results, add version to skill index.yaml

Sprint 2: Output Contracts + Scoring Graders (FR-3, FR-4, FR-5)
  └─ Contract schemas for top 3 skills, output-contract.sh grader, scoring graders

Sprint 3: Instrumentation + Eval Expansion (FR-10, FR-6)
  └─ Constraint violation tracking, score breakdowns, 45+ new eval tasks

Sprint 4: A/B Comparison + Sequential Testing (FR-7, FR-8)
  └─ Variant management, paired statistical tests, Wald SPRT

Sprint 5: Critic/Reviser Loop (FR-9)
  └─ In-eval critic, revision mechanism, circuit breaker
```

Each sprint builds on the previous. Sprint 1 is prerequisite for all others.

---

## Appendix: Eileen's Original Comments

### Comment 1 (Core Traceability)
> "Add to every eval result record: constraints_registry_version, skill_prompt_version, harness_sha, model_version. Then your optimization work becomes scientific: 'Regression started at constraints v1.4.0', 'Improved after skill prompt v2.1.3', 'Only regresses on model X'"

### Comment 2 (Output Contracts)
> "The next step is to push contracts 'up the stack': not just 'grader returns 0/1/2' but 'agent output must conform to schema X / sections Y / citations Z'"

### Comment 3 (Registry Composition)
> "The missing piece is: attach version IDs from that registry into eval results so you can attribute regressions to 'policy v1.3.2' instead of 'something changed.'"

### Comment 4 (Controlled Experiments)
> "The natural next evolution: sequential/adaptive trials to save eval budget."

### Comment 5 (High-Stakes Reliability)
> "Don't let the model grade itself without constraints."

### Comment 6 (8-Point Framework)
> "If you want the most leverage quickly: (1) A rubric + scoring spec, (2) An output contract for your top skill, (3) An eval suite + regression runner design."
