# Sprint Plan: Bridge Iteration 2 — Boundary Hardening and Test Coverage

> Cycle: cycle-027 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: Bridge review bridge-20260219-7f28c4 iteration 1
> Sprints: 2 | Team: 1 developer (AI-assisted)
> Bridge: Iteration 2 of 3 — addressing 1 HIGH, 3 MEDIUM, 3 LOW findings

## Overview

Two sprints addressing Bridgebuilder findings from iteration 1:

1. **Sprint 1** (sprint-17): Security & correctness fixes — dead code, JSON escaping, input validation, symlink protection
2. **Sprint 2** (sprint-18): Test coverage & documentation — injectable config, precedence tests, config cross-references

Dependency: Sprint 1 → Sprint 2 (tests depend on code changes).

---

## Sprint 1: Security and Correctness Hardening (sprint-17)

**Goal**: Address all HIGH and MEDIUM findings: wire or remove dead code, escape JSON fields, validate --skill input, prevent symlink traversal in grep tier.

### Tasks

#### BB-418: Wire load_bridge_context() into Orchestration Loop (high-1)
- **Description**: The `load_bridge_context()` function at `bridge-orchestrator.sh:157-167` is defined but never called. Wire it into the iteration loop before the BRIDGEBUILDER_REVIEW signal, passing the current sprint goal as the query argument, so that QMD context is available during bridge reviews.
- **Acceptance Criteria**:
  - [x] `load_bridge_context()` is called in the orchestration loop before BRIDGEBUILDER_REVIEW
  - [x] `BRIDGE_CONTEXT` variable is passed to the review signal handler
  - [x] If QMD script is missing or disabled, `BRIDGE_CONTEXT` is empty (graceful no-op)
  - [x] No regressions in bridge orchestrator tests
- **Estimated Effort**: Small
- **Finding**: high-1 (severity_weighted_score: 5)

#### BB-419: Escape rel_path in Grep Tier JSON Construction (medium-1)
- **Description**: At `qmd-context-query.sh:392`, `rel_path` is embedded directly into a JSON string without jq escaping. Add jq escaping for `rel_path` the same way `snippet` is escaped on line 384.
- **Acceptance Criteria**:
  - [x] `rel_path` is escaped via `jq -Rs` before JSON embedding
  - [x] Filenames containing quotes, backslashes, or special characters produce valid JSON
  - [x] Existing grep tier tests still pass
  - [x] No silent data loss for valid results
- **Estimated Effort**: Small
- **Finding**: medium-1 (severity_weighted_score: 2)

#### BB-420: Validate --skill Argument with Regex (medium-2)
- **Description**: At `qmd-context-query.sh:97-98`, the `--skill` argument is parsed with no validation. Add a regex check restricting skill names to `[a-z_-]+` before interpolation into yq selector.
- **Acceptance Criteria**:
  - [x] `--skill` value validated against `^[a-z_-]+$` regex after parsing
  - [x] Invalid values silently reset to empty string
  - [x] Valid skill names (implement, review_sprint, ride, run_bridge, gate0) pass validation
  - [x] No regressions in existing tests
- **Estimated Effort**: Small
- **Finding**: medium-2 (severity_weighted_score: 2)

#### BB-421: Prevent Symlink Traversal in Grep Tier (medium-3)
- **Description**: At `qmd-context-query.sh:367-375`, `grep -r` follows symlinks by default, potentially bypassing the `realpath` + `PROJECT_ROOT` prefix check. Add per-file `realpath` validation for each grep match to ensure results stay within PROJECT_ROOT.
- **Acceptance Criteria**:
  - [x] Each grep match file has its `realpath` validated against PROJECT_ROOT prefix
  - [x] Symlinks pointing outside PROJECT_ROOT are excluded from results
  - [x] Non-symlink paths within PROJECT_ROOT continue to work
  - [x] Existing grep tier tests still pass
- **Estimated Effort**: Small
- **Finding**: medium-3 (severity_weighted_score: 2)

---

## Sprint 2: Test Coverage and Documentation (sprint-18)

**Goal**: Address all LOW findings: make CONFIG_FILE injectable for unit testing, add --skill override precedence test, add config cross-reference documentation.

### Tasks

#### BB-422: Make CONFIG_FILE Injectable via Environment Variable (low-1)
- **Description**: Extract `CONFIG_FILE` as an injectable environment variable (`QMD_CONFIG_FILE`) in `qmd-context-query.sh` to enable unit testing of the disabled config path. Update the no-op test to actually exercise the disabled path.
- **Acceptance Criteria**:
  - [x] Script respects `QMD_CONFIG_FILE` env var when set
  - [x] Default behavior unchanged when env var unset
  - [x] `test_disabled_returns_empty()` now exercises the real disabled config path
  - [x] All existing 24 unit tests still pass
- **Estimated Effort**: Small
- **Finding**: low-1 (severity_weighted_score: 1)

#### BB-423: Add --skill Override Precedence Test (low-2)
- **Description**: Add a test exercising the full priority chain: CLI `--budget` > skill override from config > config default > hardcoded default. Uses the `QMD_CONFIG_FILE` injection from BB-422.
- **Acceptance Criteria**:
  - [x] Test creates temp config with `skill_overrides.test.budget: 500` and `default_budget: 3000`
  - [x] Test verifies `--skill test` (no explicit --budget) uses 500
  - [x] Test verifies `--budget 100 --skill test` uses 100 (CLI wins)
  - [x] All tests pass
- **Estimated Effort**: Small
- **Finding**: low-2 (severity_weighted_score: 1)
- **Dependencies**: BB-422

#### BB-424: Add Config Skill Override Cross-Reference Documentation (low-3)
- **Description**: Add a comment above `skill_overrides` in `.loa.config.yaml.example` mapping each key to its skill invocation.
- **Acceptance Criteria**:
  - [x] Comment documents: implement → /implement, review_sprint → /review-sprint, ride → /ride, run_bridge → /run-bridge, gate0 → preflight.sh
  - [x] Comment is concise and follows existing config style
- **Estimated Effort**: Small
- **Finding**: low-3 (severity_weighted_score: 1)

#### BB-425: Full Test Suite Validation
- **Description**: Run all unit and integration tests, verify zero regressions.
- **Acceptance Criteria**:
  - [x] All unit tests pass (including new tests from BB-422, BB-423)
  - [x] All integration tests pass
  - [x] Total test count documented
- **Estimated Effort**: Small
- **Dependencies**: BB-422, BB-423, BB-424
