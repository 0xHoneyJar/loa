# Sprint 2 (sprint-15) Implementation Report: Skill Integrations

## Executive Summary

Wired `qmd-context-query.sh` into 5 core skills with appropriate query construction, scope selection, and budget allocation. All integrations follow the same pattern: check for script existence and config enablement, run query with skill-specific parameters, include output as advisory context. All 22 integration tests pass. All 24 Sprint 1 unit tests pass (no regressions).

## Tasks Completed

### BB-408: `/implement` Context Injection
- **File**: `.claude/skills/implementing-tasks/SKILL.md:395-398`
- **Approach**: Added step 8 to `<grounding_requirements>` section. Instructs agent to query grimoires scope with task descriptions and file names before implementation.
- **Parameters**: `--scope grimoires --budget 2000 --format text`
- **Safety**: Graceful no-op when script missing or disabled. Sprint plan acceptance criteria remain source of truth.

### BB-409: `/review-sprint` Context Injection
- **File**: `.claude/skills/reviewing-code/SKILL.md:317-320`
- **Approach**: Added step 8 to `<grounding_requirements>` section. Instructs agent to query grimoires scope with changed file names and sprint goal.
- **Parameters**: `--scope grimoires --budget 1500 --format text`
- **Safety**: Graceful no-op. Acceptance criteria and code remain primary sources.

### BB-410: `/ride` Context Injection
- **File**: `.claude/skills/riding-codebase/SKILL.md:129-136`
- **Approach**: Added `### QMD Reality Context (Optional)` section after enrichment flags. Instructs agent to query reality scope with module names during drift analysis.
- **Parameters**: `--scope reality --budget 2000 --format text`
- **Safety**: Graceful no-op. Labeled as "Optional".

### BB-411: `/run-bridge` Context Injection
- **File**: `.claude/scripts/bridge-orchestrator.sh:155-166`
- **Approach**: Added `load_bridge_context()` function after `load_bridge_config()`. Accepts query string, calls `qmd-context-query.sh`, stores result in `BRIDGE_CONTEXT` variable.
- **Parameters**: `--scope grimoires --budget 2500 --format text`
- **Safety**: Checks script exists and is executable. Falls back to empty string on any error.

### BB-412: Gate 0 Pre-flight Context Injection
- **File**: `.claude/scripts/preflight.sh:289-299`
- **Approach**: Added check #8 in `run_integrity_checks()` before final "complete" message. Queries notes scope for known issues relevant to the current skill.
- **Parameters**: `--scope notes --budget 1000 --format text`
- **Safety**: Checks script exists and is executable. Outputs to stderr only. Falls back silently.

### BB-413: Integration Tests
- **File**: `.claude/scripts/qmd-context-integration-tests.sh` (new, 181 lines)
- **Coverage**: 22 tests across all 5 integrations plus cross-cutting disabled config test
  - BB-408: 4 tests (script reference, scope, budget, graceful no-op)
  - BB-409: 4 tests (script reference, scope, budget, graceful no-op)
  - BB-410: 4 tests (script reference, scope, budget, graceful no-op)
  - BB-411: 4 tests (function presence, script reference, budget, context variable)
  - BB-412: 4 tests (script reference, scope, budget, context surfacing)
  - Cross-cutting: 2 tests (disabled config returns empty, all SKILL.md check enabled flag)

## Technical Highlights

### Integration Pattern
Every skill integration follows the same minimal, additive pattern:
1. Check script existence and `qmd_context.enabled` config
2. Build skill-specific query from available context
3. Call `qmd-context-query.sh` with appropriate scope and budget
4. Include output as advisory context (never authoritative)
5. Graceful no-op on any failure

### No Breaking Changes
- SKILL.md modifications are additive (new step appended to existing list)
- Shell script modifications are additive (new function, new check block)
- All existing behavior preserved — no code paths modified, only extended
- All Sprint 1 unit tests pass (24/24)

### Budget Differentiation
Budgets tuned per-skill based on context importance:
| Skill | Budget | Rationale |
|-------|--------|-----------|
| /implement | 2000 | Full context for implementation decisions |
| /review-sprint | 1500 | Focused on architectural alignment |
| /ride | 2000 | Needs broad reality comparison |
| /run-bridge | 2500 | Richest context for Bridgebuilder review |
| Gate 0 | 1000 | Minimal — just known issues |

## Testing Summary

| Suite | Tests | Status |
|-------|-------|--------|
| Unit tests (Sprint 1) | 24/24 | PASS |
| Integration tests (Sprint 2) | 22/22 | PASS |
| **Total** | **46/46** | **PASS** |

### How to Run
```bash
# Unit tests
bash .claude/scripts/qmd-context-query-tests.sh

# Integration tests
bash .claude/scripts/qmd-context-integration-tests.sh
```

## Known Limitations

1. Integration tests verify structural presence (grep-based), not runtime behavior. Full runtime testing would require mocking skill invocations.
2. The `load_bridge_context()` function is defined but not yet called from the main orchestration loop — it's available for the bridge skill to call during review construction.
3. SKILL.md integrations are instructions for the agent, not executable code. Actual context injection happens when the agent follows the instructions during skill execution.

## Verification Steps

1. Run unit tests: `bash .claude/scripts/qmd-context-query-tests.sh` → 24/24
2. Run integration tests: `bash .claude/scripts/qmd-context-integration-tests.sh` → 22/22
3. Verify SKILL.md changes are additive: `git diff .claude/skills/` shows only appended steps
4. Verify shell script changes are additive: `git diff .claude/scripts/` shows only new functions/blocks
