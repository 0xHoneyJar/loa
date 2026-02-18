# Sprint Plan: Broader QMD Integration Across Core Skills

> Cycle: cycle-027 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#364](https://github.com/0xHoneyJar/loa/issues/364)
> Sprints: 3 | Team: 1 developer (AI-assisted)
> Flatline: Reviewed (2 HIGH_CONSENSUS integrated, 1 DISPUTED accepted, 6 BLOCKERS addressed)

## Overview

Three sprints implementing the unified context query interface and skill integrations:

1. **Sprint 1** (sprint-14): Foundation — unified query script + three-tier fallback + tests
2. **Sprint 2** (sprint-15): Skill integrations — 5 skills + integration tests
3. **Sprint 3** (sprint-16): Configuration + validation + documentation

Dependency: Sprint 1 → Sprint 2 + Sprint 3 (parallel after Sprint 1).

---

## Sprint 1: Unified Context Query Interface (sprint-14)

**Goal**: Create `qmd-context-query.sh` with three-tier fallback (QMD → CK → grep), token budget enforcement, and comprehensive unit tests.

### Tasks

#### BB-401: Script Skeleton and CLI Interface
- **Description**: Create `.claude/scripts/qmd-context-query.sh` with argument parsing (`--query`, `--scope`, `--budget`, `--format`, `--timeout`), config loading, and main entry point.
- **Acceptance Criteria**:
  - [ ] Script accepts all 5 flags with defaults
  - [ ] `--help` prints usage
  - [ ] Returns valid JSON `[]` with no arguments
  - [ ] `set -euo pipefail` and `shellcheck` clean
- **Estimated Effort**: Small

#### BB-402: QMD Tier Implementation
- **Description**: Implement `try_qmd()` that delegates to `qmd-sync.sh query` with collection name and timeout. Transform QMD output to unified JSON format.
- **Acceptance Criteria**:
  - [ ] Calls `qmd-sync.sh query` with correct args
  - [ ] Wraps call in `timeout` command
  - [ ] Returns `[]` if QMD binary unavailable
  - [ ] Returns `[]` if collection doesn't exist
  - [ ] Results include `source`, `score`, `content` fields
- **Estimated Effort**: Small
- **Dependencies**: BB-401

#### BB-403: CK Tier Implementation
- **Description**: Implement `try_ck()` using `ck --hybrid` with JSONL output. Transform to unified JSON format.
- **Acceptance Criteria**:
  - [ ] Calls `ck --hybrid` with correct args
  - [ ] Wraps call in `timeout` command
  - [ ] Returns `[]` if `ck` binary unavailable
  - [ ] Transforms JSONL output to JSON array
  - [ ] Results include `source`, `score`, `content` fields
- **Estimated Effort**: Small
- **Dependencies**: BB-401

#### BB-404: Grep Tier Implementation
- **Description**: Implement `try_grep()` using `grep -r -l -i` with keyword extraction from query. Terminal fallback — must always succeed.
- **Acceptance Criteria**:
  - [ ] Splits query into keywords (max 5)
  - [ ] Builds OR pattern for grep
  - [ ] Extracts snippets (first match, 200 chars)
  - [ ] Returns `[]` on no matches
  - [ ] Never fails (returns `[]` even on invalid paths)
  - [ ] Head limits prevent excessive file scanning
- **Estimated Effort**: Small
- **Dependencies**: BB-401

#### BB-405: Token Budget Enforcement
- **Description**: Implement `apply_token_budget()` that estimates tokens as `word_count × 1.3` and truncates results from lowest-scoring upward until within budget.
- **Acceptance Criteria**:
  - [ ] Processes results sorted by score (highest first)
  - [ ] Accurately estimates token count per result
  - [ ] Truncates at budget boundary
  - [ ] Returns `[]` on budget 0
  - [ ] Works with empty results
- **Estimated Effort**: Small
- **Dependencies**: BB-401

#### BB-406: Scope Resolution and Tier Annotation
- **Description**: Implement `resolve_scope()` mapping scope names to tier paths, and `annotate_tier()` tagging results with source tier. Read from config with hardcoded defaults.
- **Acceptance Criteria**:
  - [ ] All 5 scopes resolve correctly (grimoires, skills, notes, reality, all)
  - [ ] Config overrides work when `.loa.config.yaml` present
  - [ ] Defaults used when config absent
  - [ ] Each result tagged with `tier` field
- **Estimated Effort**: Small
- **Dependencies**: BB-401

#### BB-407: Unit Tests
- **Description**: Create `.claude/scripts/qmd-context-query-tests.sh` with tests for all tiers, fallback chain, token budget, scope resolution.
- **Acceptance Criteria**:
  - [ ] Tests for QMD tier (available, unavailable, timeout)
  - [ ] Tests for CK tier (available, unavailable)
  - [ ] Tests for grep tier (matches, no matches)
  - [ ] Tests for fallback chain (QMD→CK, QMD→CK→grep, full chain)
  - [ ] Tests for token budget (enforcement, zero budget, empty results)
  - [ ] Tests for scope resolution (defaults, config overrides)
  - [ ] Tests for tier annotation
  - [ ] All tests pass
- **Estimated Effort**: Medium
- **Dependencies**: BB-402, BB-403, BB-404, BB-405, BB-406

---

## Sprint 2: Skill Integrations (sprint-15)

**Goal**: Wire `qmd-context-query.sh` into 5 core skills with appropriate query construction, scope selection, and budget allocation.

### Tasks

#### BB-408: `/implement` Context Injection
- **Description**: Add context injection to the implementing-tasks skill. Query grimoires scope with task description before execution. Inject as "Relevant Context" section.
- **Acceptance Criteria**:
  - [ ] Queries grimoires scope with task description + file names
  - [ ] Injects context into implementation prompt
  - [ ] Respects budget (2000 tokens default)
  - [ ] Graceful no-op when `qmd_context.enabled: false`
  - [ ] No behavior change for existing tests
- **Estimated Effort**: Small
- **Dependencies**: Sprint 1 complete

#### BB-409: `/review-sprint` Context Injection
- **Description**: Add context injection to the reviewing-code skill. Query grimoires scope with changed file names + sprint goal before review.
- **Acceptance Criteria**:
  - [ ] Queries grimoires scope with changed files + sprint goal
  - [ ] Injects context into review prompt
  - [ ] Respects budget (1500 tokens default)
  - [ ] Graceful no-op when disabled
  - [ ] No behavior change for existing tests
- **Estimated Effort**: Small
- **Dependencies**: Sprint 1 complete

#### BB-410: `/ride` Context Injection
- **Description**: Add context injection to the riding-codebase skill. Query reality scope with module names during documentation analysis.
- **Acceptance Criteria**:
  - [ ] Queries reality scope with module names
  - [ ] Injects context during drift analysis
  - [ ] Respects budget (2000 tokens default)
  - [ ] Graceful no-op when disabled
  - [ ] No behavior change for existing tests
- **Estimated Effort**: Small
- **Dependencies**: Sprint 1 complete

#### BB-411: `/run-bridge` Context Injection
- **Description**: Add context injection to bridge-orchestrator.sh. Query grimoires scope with PR diff summary before Bridgebuilder review.
- **Acceptance Criteria**:
  - [ ] Queries grimoires scope with diff summary + changed modules
  - [ ] Injects lore/vision context into review prompt
  - [ ] Respects budget (2500 tokens default)
  - [ ] Graceful no-op when disabled
  - [ ] No behavior change for existing tests
- **Estimated Effort**: Small
- **Dependencies**: Sprint 1 complete

#### BB-412: Gate 0 Pre-flight Context Injection
- **Description**: Add context injection to Gate 0 pre-flight checks. Query notes scope for known issues relevant to the current skill.
- **Acceptance Criteria**:
  - [ ] Queries notes scope with skill name + "configuration prerequisites"
  - [ ] Surfaces relevant blockers/known issues
  - [ ] Respects budget (1000 tokens default)
  - [ ] Graceful no-op when disabled
- **Estimated Effort**: Small
- **Dependencies**: Sprint 1 complete

#### BB-413: Integration Tests
- **Description**: Create integration tests verifying context flows from query to skill invocation.
- **Acceptance Criteria**:
  - [ ] Test: `/implement` receives context from query
  - [ ] Test: `/review-sprint` receives context
  - [ ] Test: `/ride` receives reality context
  - [ ] Test: `/run-bridge` receives lore context
  - [ ] Test: Gate 0 receives notes context
  - [ ] Test: Disabled config produces no context
  - [ ] All tests pass
- **Estimated Effort**: Medium
- **Dependencies**: BB-408 through BB-412

---

## Sprint 3: Configuration and Validation (sprint-16)

**Goal**: Add configuration section to `.loa.config.yaml.example`, implement config parsing, and run end-to-end validation.

### Tasks

#### BB-414: Configuration Section in `.loa.config.yaml.example`
- **Description**: Add `qmd_context` section to `.loa.config.yaml.example` with all scope mappings, budget defaults, and skill overrides.
- **Acceptance Criteria**:
  - [ ] `qmd_context` section with `enabled`, `default_budget`, `timeout_seconds`
  - [ ] `scopes` with all 4 scope definitions (grimoires, skills, notes, reality)
  - [ ] `skill_overrides` for all 5 integrated skills
  - [ ] Comments explaining each option
  - [ ] Consistent with existing config style
- **Estimated Effort**: Small

#### BB-415: Config Parsing in Query Script
- **Description**: Implement robust config parsing in `qmd-context-query.sh` that reads `.loa.config.yaml` for scope mappings and budget overrides.
- **Acceptance Criteria**:
  - [ ] Reads `qmd_context.enabled` flag
  - [ ] Reads `qmd_context.scopes.*` for each scope
  - [ ] Reads `qmd_context.skill_overrides.*` for per-skill budgets
  - [ ] Falls back to defaults when config absent or yq unavailable
  - [ ] Validates budget is positive integer
- **Estimated Effort**: Small
- **Dependencies**: BB-414

#### BB-416: End-to-End Validation
- **Description**: Verify the complete pipeline works: config → query → tier selection → results → budget enforcement → skill injection. Ensure all existing tests pass.
- **Acceptance Criteria**:
  - [ ] All unit tests from Sprint 1 pass
  - [ ] All integration tests from Sprint 2 pass
  - [ ] Script works with no config file (defaults)
  - [ ] Script works with no QMD and no CK (grep-only)
  - [ ] All pre-existing Loa tests pass
  - [ ] No regressions in existing skill behavior
- **Estimated Effort**: Medium
- **Dependencies**: BB-415, Sprint 2 complete

#### BB-417: NOTES.md Update
- **Description**: Update `grimoires/loa/NOTES.md` with implementation observations, decisions made, and any discovered issues.
- **Acceptance Criteria**:
  - [ ] Documents architectural decisions
  - [ ] Notes any edge cases discovered
  - [ ] Lists any deferred improvements
- **Estimated Effort**: Small
- **Dependencies**: BB-416
