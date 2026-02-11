# PRD: Eval Traceability & Output Contracts — Scientific Agent Optimization

**Version**: 1.0.0
**Status**: Draft
**Author**: Discovery Phase (plan-and-analyze)
**Issue**: [loa #286](https://github.com/0xHoneyJar/loa/issues/286)
**Date**: 2026-02-12
**Prior Art**: [PR #282](https://github.com/0xHoneyJar/loa/pull/282) — Eval Sandbox (cycle-002)
**Feedback Source**: `eileen1337` review comments on PR #282

---

## 1. Problem Statement

The Eval Sandbox (cycle-002) established the **measurement infrastructure** for Loa: deterministic framework evals, stochastic agent evals, CI regression gates, Wilson CI statistical comparison, and a dual-checkout trust model. It answers "is this change better or worse?" with empirical evidence.

**What's still missing is the ability to answer _why_.**

When a regression is detected, the current system tells you:
- "Task `impl-hello-world-ts` pass rate dropped from 1.0 to 0.67"
- "Wilson CI [0.12, 0.94] overlaps with baseline"

But it **cannot** tell you:
- **Which prompt/constraint change caused it** — `model_version` is "none" for framework evals, and there's no `constraints_registry_version` or `skill_prompt_version` in the result record
- **What specifically failed in the output** — graders check for file existence and pattern matches, but don't validate that the agent's output conforms to the skill's documented output contract (required sections, verdict format, citation coverage)
- **How to reproduce the failure scientifically** — no A/B variant management, no paired comparison framework, no sequential testing for cost optimization
- **Whether the failure is structural or semantic** — all graders return binary pass/fail; no rubric scoring that distinguishes "completely wrong format" from "right format but missing one section"

Eileen (`eileen1337`) identified this gap precisely in 6 comments on PR #282:

> *"The next step to 'optimize agent outputs' is to connect it to agent-facing specs... Add to every eval result record: `constraints_registry_version`, `skill_prompt_version`, `harness_sha`, `model_version`. Then your optimization work becomes scientific."*

> *"Output contracts turn 'quality' from subjective to testable."*

### The Missing Loop

```
registry change → eval run → regression detected → ??? → fix prompt/skill/spec → re-run → ship
                                                    ↑
                                           Can't attribute cause.
                                           Can't validate output structure.
                                           Can't run controlled experiments.
```

This PRD closes the `???` gap by implementing 8 capabilities that transform the eval sandbox from a regression detector into a **scientific optimization platform**.

> Sources: [PR #282 comments](https://github.com/0xHoneyJar/loa/pull/282) from `eileen1337`, Anthropic eval guidance, cycle-002 PRD/SDD

---

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurable Outcome |
|---|------|-------------------|
| G1 | **Attribution**: Every eval result traces to specific registry/prompt versions | 100% of result records include `constraints_version`, `skill_prompt_version`, `harness_sha` |
| G2 | **Output Contracts**: Agent outputs are validated against skill-specific schemas | Top 3 skills (implementing-tasks, reviewing-code, auditing-security) have enforceable output contracts |
| G3 | **Scoring**: Quality is measured on a continuous scale, not just pass/fail | New rubric graders produce 0-100 scores with per-dimension breakdown |
| G4 | **Scientific Experimentation**: A/B testing of prompt/policy changes | `compare.sh` supports variant comparison with paired statistical tests |
| G5 | **Cost Efficiency**: Eval runs use adaptive trial counts | Sequential testing (Wald SPRT) reduces trial count by 30% on average |
| G6 | **Self-Correction**: High-stakes outputs go through critic/reviser loops | Critic/reviser loop available for danger_level >= high skills |
| G7 | **Comprehensive Instrumentation**: Every run logs enough data for root cause analysis | Per-constraint violation tracking, tool call traces, score breakdowns in results |
| G8 | **Eval Coverage**: Sufficient eval tasks to catch real regressions | 30+ eval tasks per target skill (90+ total for top 3) |

### Success Criteria

| Metric | Target | Measurement |
|--------|--------|-------------|
| Attribution coverage | 100% of results | Grep result JSONL for version fields |
| Output contract enforcement | 3 skills | Count skills with output-schema graders |
| Scoring resolution | Avg 5+ distinct score values per task | Analyze score distribution in results |
| A/B comparison capability | Working `--variant` flag | Manual test |
| Sequential testing savings | ≥20% fewer trials vs fixed-count | Compare total trials with/without SPRT |
| Critic/reviser improvement | ≥15% compliance rate increase | Before/after on same eval set |
| Eval task count | ≥30 per target skill | Count task YAML files |

---

## 3. Users & Stakeholders

### Primary Users

| Persona | Role | Key Needs |
|---------|------|-----------|
| **Framework Developer** | Modifies skills, protocols, constraints | "I changed a constraint — did anything break? What specifically?" |
| **Agent Developer** | Tunes prompts, adjusts behavior | "I rewrote the /implement prompt — is it better? By how much?" |
| **CI Pipeline** | Automated regression detection | Version-stamped results, regression attribution, cost-efficient trials |

### Secondary Users

| Persona | Role | Key Needs |
|---------|------|-----------|
| **Hounfour Routing Layer** | Multi-model provider abstraction | Per-model eval results for empirical routing decisions |
| **Security Auditor** | Reviews eval trust model | Grader trust chain, output contract integrity |

---

## 4. Functional Requirements

### FR-1: Result Schema Enhancement (P0 — Attribution)

**What**: Add version traceability fields to every eval result record.

**Current schema** (run-eval.sh L413-428):
```json
{
  "run_id", "task_id", "trial", "timestamp", "duration_ms",
  "model_version": "none", "status", "graders", "composite",
  "error", "schema_version": 1
}
```

**Enhanced schema** (schema_version: 2):
```json
{
  "run_id", "task_id", "trial", "timestamp", "duration_ms",
  "model_version", "status", "graders", "composite", "error",
  "schema_version": 2,
  "versions": {
    "constraints_registry": "1.0.0",
    "harness_sha": "abc1234",
    "skill_prompt": "1.0.0",
    "loa_version": "1.33.0"
  }
}
```

**Fields**:
| Field | Source | Value |
|-------|--------|-------|
| `versions.constraints_registry` | `jq -r '.version' .claude/data/constraints.json` | "1.0.0" |
| `versions.harness_sha` | `git rev-parse --short HEAD -- evals/harness/` | Short SHA of harness dir |
| `versions.skill_prompt` | `yq '.version // "0.0.0"' .claude/skills/{skill}/index.yaml` | Per-skill version (new field) |
| `versions.loa_version` | Parse from CLAUDE.loa.md header | "1.33.0" |

**Acceptance Criteria**:
- [ ] All result records include `versions` object
- [ ] `schema_version` bumped to 2
- [ ] `compare.sh` handles mixed v1/v2 results gracefully (backward compatible)
- [ ] Run-meta.json includes aggregate version info
- [ ] Version fields populated from live data, not hardcoded

### FR-2: Skill Prompt Versioning (P0 — Prerequisite)

**What**: Add `version` field to skill `index.yaml` files.

**Current index.yaml** (no version field):
```yaml
name: implementing-tasks
description: "..."
danger_level: moderate
```

**Enhanced index.yaml**:
```yaml
name: implementing-tasks
version: "1.0.0"
description: "..."
danger_level: moderate
```

**Acceptance Criteria**:
- [ ] All 21 skill `index.yaml` files include `version: "1.0.0"` (initial)
- [ ] `skill-index.schema.json` updated with `version` field (semver pattern)
- [ ] `skill-index-validator.sh` validates version field presence
- [ ] Framework eval task added to verify all skills have version fields

### FR-3: Output Contract Schemas (P1 — Contracts)

**What**: Define JSON-like schemas for the structured output of top 3 skills.

**Target skills and their output contracts**:

| Skill | Output File | Contract |
|-------|------------|----------|
| implementing-tasks | `reviewer.md` | Required sections: Executive Summary, Tasks Completed (per-task with files table), Testing Summary, Version Update |
| reviewing-code | `engineer-feedback.md` | Verdict format ("All good" OR "CHANGES REQUIRED"), critical issues with file:line refs, acceptance criteria checklist |
| auditing-security | `auditor-sprint-feedback.md` | Verdict (APPROVED/CHANGES_REQUIRED), severity count table, findings with PoC and CWE/OWASP refs |

**Contract format** (new files in `.claude/schemas/`):
```json
{
  "skill": "implementing-tasks",
  "output_file": "reviewer.md",
  "required_sections": [
    {"heading": "Executive Summary", "min_words": 50},
    {"heading": "Tasks Completed", "repeatable": true},
    {"heading": "Testing Summary"}
  ],
  "required_patterns": [
    {"pattern": "\\| File \\| Action \\|", "description": "Files table"},
    {"pattern": "Coverage.*\\d+%", "description": "Coverage metric"}
  ],
  "forbidden_patterns": [
    {"pattern": "TODO|FIXME|PLACEHOLDER", "description": "Incomplete markers"}
  ]
}
```

**Acceptance Criteria**:
- [ ] Contract schemas created for 3 target skills
- [ ] Contracts derived from existing SKILL.md templates (not invented)
- [ ] Contract format is machine-readable (JSON)
- [ ] Contracts versioned alongside skill version

### FR-4: Output Contract Grader (P1 — Enforcement)

**What**: New grader `output-contract.sh` that validates agent output against contract schemas.

**Grader behavior**:
- Input: `$1=workspace`, `$2=contract-schema-path`
- Reads the contract schema
- Locates the output file in workspace
- Validates: required sections present, required patterns match, forbidden patterns absent
- Returns graduated score (not just pass/fail):
  - 100: All checks pass
  - 75: Required sections present but some patterns missing
  - 50: Major sections missing
  - 0: Output file missing or fundamentally wrong format

**Acceptance Criteria**:
- [ ] Grader validates section presence via heading detection
- [ ] Grader validates pattern presence via regex
- [ ] Grader rejects forbidden patterns
- [ ] Score is graduated (0-100), not binary
- [ ] Grader outputs per-check breakdown in `details`
- [ ] ReDoS protection on all pattern checks (existing pattern-match.sh safeguards)
- [ ] Added to grader allowlist

### FR-5: Rubric Scoring Graders (P1 — Quality Signals)

**What**: Graders that produce meaningful intermediate scores based on measurable quality dimensions.

**New graders**:

| Grader | What It Scores | Score Calculation |
|--------|---------------|-------------------|
| `constraint-compliance.sh` | % of applicable constraints the output respects | `(passed_constraints / total_applicable) * 100` |
| `citation-coverage.sh` | % of claims with file:line references | `(cited_claims / total_claims) * 100` |
| `completeness.sh` | % of acceptance criteria addressed in output | `(addressed_criteria / total_criteria) * 100` |

**Acceptance Criteria**:
- [ ] Each grader produces 0-100 score (not binary)
- [ ] Each grader outputs dimension-level breakdown in `details` JSON
- [ ] Graders work with existing composite strategies (weighted_average becomes useful)
- [ ] Tasks can use `composite_strategy: weighted_average` with these graders

### FR-6: Eval Set Expansion (P2 — Coverage)

**What**: Expand from 11 regression tasks to 30+ per target skill.

**Task sources**:
1. **Real failure patterns**: Mine past session trajectories for common failure modes
2. **Template variations**: Same fixture, different prompts testing different aspects
3. **Edge cases**: Adversarial inputs, missing context, ambiguous requirements
4. **Cross-skill handoffs**: Output of skill A must be valid input for skill B

**New fixture requirements**:
- 5+ additional fixture repositories covering: Python Flask app, Rust CLI, monorepo, security-focused app
- Each fixture must have `fixture.yaml` with known properties and expected outcomes

**Acceptance Criteria**:
- [ ] ≥30 eval tasks for implementing-tasks
- [ ] ≥30 eval tasks for reviewing-code
- [ ] ≥30 eval tasks for auditing-security
- [ ] ≥5 new fixture repositories
- [ ] Task YAML schema extended with `context` and `requirements` fields
- [ ] Tasks cover: happy path, edge cases, adversarial inputs, cross-skill handoffs

### FR-7: A/B Variant Comparison (P2 — Scientific Experimentation)

**What**: Run eval suites against two prompt/policy variants and compare statistically.

**New CLI interface**:
```bash
# Run variant A (current)
./evals/harness/run-eval.sh --suite regression --variant baseline

# Run variant B (new prompt)
./evals/harness/run-eval.sh --suite regression --variant experiment-1

# Compare A vs B
./evals/harness/compare.sh --results-a results-baseline.jsonl --results-b results-experiment-1.jsonl --paired
```

**Statistical method**: Paired comparison across same eval cases. McNemar's test for pass/fail, Wilcoxon signed-rank for scores.

**Acceptance Criteria**:
- [ ] `run-eval.sh` accepts `--variant` flag, recorded in results
- [ ] `compare.sh` supports dual-result comparison (not just results-vs-baseline)
- [ ] Paired statistical tests implemented (McNemar's + Wilcoxon)
- [ ] Results clearly show "Variant A wins on N tasks, B wins on M tasks, tied on K"
- [ ] PR comments can show A/B comparison

### FR-8: Sequential Testing (P2 — Cost Optimization)

**What**: Implement Wald's Sequential Probability Ratio Test (SPRT) for adaptive trial counts.

**Current behavior**: Fixed trial count (1 for framework, 3 for regression). Early stopping only when regression is inevitable.

**Enhanced behavior**: After each trial, compute likelihood ratio. Stop when evidence is strong enough (either pass or fail), continue only when ambiguous.

**Parameters**:
- Alpha (Type I error): 0.05
- Beta (Type II error): 0.10
- Effect size: 0.15 (minimum meaningful difference)

**Expected savings**: ~30% fewer trials on clear pass/fail tasks. Full trial count only on ambiguous tasks.

**Acceptance Criteria**:
- [ ] SPRT implemented in run-eval.sh trial loop
- [ ] Configurable alpha, beta, effect size in suite YAML
- [ ] Results include `early_stopped_reason: "sprt_accept" | "sprt_reject" | "max_trials"`
- [ ] Total trial savings tracked and reported
- [ ] Fallback to fixed-count if SPRT parameters invalid

### FR-9: Critic/Reviser Loop (P3 — Self-Correction)

**What**: For high-stakes skills, agent output goes through an automated critique → revision cycle before final grading.

**Loop structure**:
```
1. Generator produces draft output
2. Critic checks against output contract + rubric, lists violations
3. Reviser addresses violations, produces revised output
4. Grade revised output (or loop back to step 2, max 3 iterations)
5. Circuit breaker: if violations don't decrease after 2 iterations, stop
```

**Integration point**: New task YAML field `critic_reviser: true` enables the loop. Only applicable to `skill-quality` and `e2e` category tasks.

**Acceptance Criteria**:
- [ ] Critic/reviser loop implemented in run-eval.sh
- [ ] Configurable max iterations (default 3) and circuit breaker
- [ ] Results include `revisions: N` and per-revision scores
- [ ] Loop only activates for tasks with `critic_reviser: true`
- [ ] Critic uses output contract schema (FR-3) as its reference
- [ ] Cost tracked per revision (token usage)
- [ ] Loop does NOT apply to framework evals (deterministic)

### FR-10: Comprehensive Instrumentation (P1 — Logging)

**What**: Every eval run logs sufficient data for root cause analysis.

**New fields in per-trial results**:
```json
{
  "constraint_violations": [
    {"constraint_id": "C-PROC-001", "status": "pass"},
    {"constraint_id": "C-PROC-004", "status": "fail", "detail": "Missing section"}
  ],
  "score_breakdown": {
    "structure": 85,
    "completeness": 70,
    "citation_coverage": 90,
    "constraint_compliance": 95
  }
}
```

**New run-level analytics**:
```json
{
  "analytics": {
    "total_trials_run": 45,
    "total_trials_saved": 12,
    "avg_score_by_dimension": {"structure": 82, "completeness": 75},
    "top_violations": [
      {"constraint_id": "C-PROC-004", "violation_count": 8},
      {"constraint_id": "C-PROC-015", "violation_count": 3}
    ]
  }
}
```

**Acceptance Criteria**:
- [ ] Per-trial results include `constraint_violations` array (when applicable graders run)
- [ ] Per-trial results include `score_breakdown` object (when scoring graders run)
- [ ] Run-level analytics computed in `finalize_results()`
- [ ] Top violations surfaced in PR comments
- [ ] Analytics queryable: "which constraints fail most?"

---

## 5. Non-Functional Requirements

| # | Requirement | Target |
|---|------------|--------|
| NFR-1 | Backward compatibility | v1 results still parseable by v2 harness |
| NFR-2 | Performance | Version field lookup adds <100ms per run (not per trial) |
| NFR-3 | Storage | Instrumentation adds <20% to JSONL size |
| NFR-4 | Security | Output contract graders inherit existing trust model (base branch) |
| NFR-5 | Cost | Sequential testing saves ≥20% of trial costs |
| NFR-6 | Shell compatibility | All new graders work on Bash 4.0+ (same as existing) |

---

## 6. Technical Constraints

| Constraint | Implication |
|------------|------------|
| Shell-based harness (ADR-003) | All graders must be Bash scripts; complex scoring may use inline Python |
| No LLM in grader path (cycle-002 principle) | Rubric graders must use code-based heuristics, not LLM judges |
| Dual-checkout trust model | New graders live in `evals/graders/`, inherit trust from base branch |
| JSONL storage (ADR-001) | Results remain append-only JSONL; schema must be self-describing |
| mikefarah/yq pinned (ADR-002) | YAML parsing uses Go yq; skill version reading uses same tool |

**Exception**: Critic/reviser loop (FR-9) necessarily involves LLM execution. This is in the *execution* path, not the *grading* path. The graders that evaluate the revised output are still code-based.

---

## 7. Scope & Prioritization

### In Scope (This Cycle)

| Priority | Feature | FRs |
|----------|---------|-----|
| **P0** | Result schema enhancement + skill versioning | FR-1, FR-2 |
| **P1** | Output contracts + scoring graders + instrumentation | FR-3, FR-4, FR-5, FR-10 |
| **P2** | Eval set expansion + A/B comparison + sequential testing | FR-6, FR-7, FR-8 |
| **P3** | Critic/reviser loop | FR-9 |

### Out of Scope

| Item | Reason |
|------|--------|
| LLM-based judge graders (type: `model`) | Deferred to future cycle; requires separate trust model analysis |
| Cross-repo eval tasks | Hounfour routing layer not yet available |
| Real-time eval dashboard | CLI + PR comments sufficient for current scale |
| Automated prompt optimization | A/B framework enables manual optimization; auto-tuning is a separate initiative |
| Per-constraint versioning | Registry-level version + git SHA sufficient for attribution |

### Build Order

```
Sprint 1: FR-1 + FR-2 (schema + skill versioning) — Foundation
Sprint 2: FR-3 + FR-4 + FR-5 (contracts + scoring graders) — Validation
Sprint 3: FR-10 + FR-6 (instrumentation + eval expansion) — Coverage
Sprint 4: FR-7 + FR-8 (A/B + sequential testing) — Experimentation
Sprint 5: FR-9 (critic/reviser loop) — Self-correction
```

Each sprint builds on the previous. Sprint 1 is prerequisite for all others. Sprint 2 enables Sprint 3's expanded eval tasks to use scoring graders. Sprint 4 requires Sprint 3's larger eval set for meaningful A/B results.

---

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Output contract schemas become maintenance burden | Medium | Medium | Derive schemas mechanically from SKILL.md templates; version alongside skill |
| Rubric scoring heuristics produce misleading scores | Medium | High | Validate scoring against human judgment on 20+ cases before deploying |
| Sequential testing (SPRT) produces incorrect accept/reject | Low | High | Conservative parameters (alpha=0.05, beta=0.10); fallback to fixed-count |
| Eval set expansion creates 100+ fixtures to maintain | Medium | Medium | Reuse existing 5 fixtures with varied prompts; new fixtures only for new languages |
| Critic/reviser loop enters infinite regression | Low | Medium | Circuit breaker (max 3 iterations, stop if violations don't decrease) |
| Schema v2 breaks existing CI pipeline | Low | High | Backward-compatible: v2 harness reads v1 results; v1 harness ignores unknown fields |
| A/B comparison leads to p-hacking | Medium | Medium | Require pre-registered hypothesis in variant metadata; paired tests only |

---

## 9. Dependencies

| Dependency | Status | Impact if Unavailable |
|------------|--------|----------------------|
| Eval Sandbox (cycle-002) | Merged (PR #282) | Blocker — entire cycle builds on it |
| constraints.json version field | Exists ("1.0.0") | None — already available |
| Skill index.yaml files | Exist (21 skills) | FR-2 adds version field |
| Python 3 (inline) | Available in harness | Required for SPRT math |
| jq | Available in harness | Required for JSON manipulation |
| yq (mikefarah) | Pinned v4.40.5 | Required for YAML parsing |

---

## 10. Eileen's Suggestions — Traceability Matrix

| # | Eileen Suggestion | FR Mapping | Status |
|---|-------------------|-----------|--------|
| 1 | Define "good output" as measurable signals | FR-5 (rubric graders) | Covered |
| 2 | Build eval set (30-50 per skill) | FR-6 (eval expansion) | Covered |
| 3 | Add output contracts | FR-3, FR-4 (schemas + grader) | Covered |
| 4 | Compose prompts/policies from registry | FR-1, FR-2 (versioning) | Covered |
| 5 | Build regression harness (CI for quality) | Already done (cycle-002); FR-10 extends | Covered |
| 6 | Controlled experiments (A/B) | FR-7 (variant comparison) | Covered |
| 7 | Critic/reviser loop | FR-9 | Covered |
| 8 | Instrumentation | FR-1, FR-10 (version fields + analytics) | Covered |

**Eileen's "one concrete do this next"**:
> Add to every eval result record: `constraints_registry_version`, `skill_prompt_version`, `harness_sha`, `model_version`

This is FR-1, our P0 priority. Sprint 1 delivers exactly this.

---

## Appendix A: Current vs Target Result Schema

### Current (schema_version 1)
```json
{
  "run_id": "run-20260211-...",
  "task_id": "impl-hello-world-ts",
  "trial": 1,
  "timestamp": "2026-02-11T06:26:49Z",
  "duration_ms": 334,
  "model_version": "none",
  "status": "completed",
  "graders": [{"name": "file-exists.sh", "pass": true, "score": 100, ...}],
  "composite": {"strategy": "all_must_pass", "pass": true, "score": 100},
  "error": null,
  "schema_version": 1
}
```

### Target (schema_version 2)
```json
{
  "run_id": "run-20260212-...",
  "task_id": "impl-hello-world-ts",
  "trial": 1,
  "timestamp": "2026-02-12T10:00:00Z",
  "duration_ms": 450,
  "model_version": "claude-opus-4-6",
  "status": "completed",
  "graders": [
    {"name": "output-contract.sh", "pass": true, "score": 85, "details": {...}},
    {"name": "citation-coverage.sh", "pass": true, "score": 92, "details": {...}},
    {"name": "completeness.sh", "pass": false, "score": 60, "details": {...}}
  ],
  "composite": {"strategy": "weighted_average", "pass": true, "score": 79},
  "error": null,
  "schema_version": 2,
  "versions": {
    "constraints_registry": "1.0.0",
    "harness_sha": "abc1234",
    "skill_prompt": "1.0.0",
    "loa_version": "1.33.0"
  },
  "constraint_violations": [
    {"constraint_id": "C-PROC-001", "status": "pass"},
    {"constraint_id": "C-PROC-004", "status": "fail", "detail": "Missing section: Testing Summary"}
  ],
  "score_breakdown": {
    "structure": 85,
    "completeness": 60,
    "citation_coverage": 92,
    "constraint_compliance": 95
  },
  "variant": "baseline",
  "early_stopped_reason": null,
  "revisions": 0
}
```

---

## Appendix B: Eileen's Original Comments (Reference)

**Comment 1** — Core traceability:
> "Add to every eval result record: constraints_registry_version, skill_prompt_version, harness_sha, model_version. Then your optimization work becomes scientific."

**Comment 2** — Output contracts:
> "The next step is to push contracts 'up the stack': not just 'grader returns 0/1/2' but 'agent output must conform to schema X / sections Y / citations Z'"

**Comment 3** — Registry composition:
> "The missing piece is: attach version IDs from that registry into eval results so you can attribute regressions to 'policy v1.3.2' instead of 'something changed.'"

**Comment 4** — Controlled experiments:
> "The natural next evolution: sequential/adaptive trials to save eval budget."

**Comment 5** — High-stakes reliability:
> "Don't let the model grade itself without constraints."

**Comment 6** — Comprehensive 8-point framework:
> "If you want the most leverage quickly, we can produce these three artifacts: (1) A rubric + scoring spec, (2) An output contract for your top skill, (3) An eval suite + regression runner design."
