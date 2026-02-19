# Sprint 3 (sprint-16) Implementation Report: Configuration and Validation

## Executive Summary

Added `qmd_context` configuration section to `.loa.config.yaml.example`, enhanced config parsing with `--skill` flag for per-skill overrides, validated all tests pass end-to-end, and updated NOTES.md with architectural decisions and learnings. All 46 tests pass (24 unit + 22 integration). No regressions.

## Tasks Completed

### BB-414: Configuration Section in `.loa.config.yaml.example`
- **File**: `.loa.config.yaml.example:1621-1673`
- **Approach**: Added comprehensive `qmd_context` section after the bridgebuilder configuration block. Includes all config keys documented in SDD section 6.1.
- **Content**:
  - `enabled`: Master switch (default true)
  - `default_budget`: Global budget default (2000)
  - `timeout_seconds`: Per-tier timeout (5)
  - `scopes`: All 4 scope definitions (grimoires, skills, notes, reality) with QMD collection, CK path, and grep paths
  - `skill_overrides`: Per-skill budget and scope overrides for all 5 integrated skills (implement, review_sprint, ride, run_bridge, gate0)
  - Comments explaining each option
  - Style matches existing config sections

### BB-415: Config Parsing in Query Script
- **File**: `.claude/scripts/qmd-context-query.sh:29-36` (new variables), `87-91` (new --skill flag), `161-176` (skill override parsing)
- **Approach**: Added `--skill` flag to CLI that reads `qmd_context.skill_overrides.<name>.budget` and `.scope` from config. CLI flags take precedence (tracked via `BUDGET_EXPLICIT` and `SCOPE_EXPLICIT` booleans).
- **Config keys parsed**:
  - `qmd_context.enabled` (pre-existing)
  - `qmd_context.default_budget` (pre-existing, fixed sentinel logic)
  - `qmd_context.timeout_seconds` (pre-existing)
  - `qmd_context.scopes.*` (pre-existing)
  - `qmd_context.skill_overrides.<name>.budget` (NEW)
  - `qmd_context.skill_overrides.<name>.scope` (NEW)
- **Precedence**: `--budget` flag > `skill_overrides` > `default_budget` > hardcoded default (2000)

### BB-416: End-to-End Validation
- **Tests run**:
  - Unit tests (Sprint 1): 24/24 PASS
  - Integration tests (Sprint 2): 22/22 PASS
  - Manual grep-only test (no config, temp directory): PASS
  - Disabled config test: PASS (returns `[]`)
  - All existing pre-commit hooks pass (verified by commit)
- **Validation matrix**:
  | Scenario | Status |
  |----------|--------|
  | Full config present | PASS |
  | No config file (defaults) | PASS |
  | No QMD, no CK (grep-only) | PASS |
  | `qmd_context.enabled: false` | PASS (empty array) |
  | Invalid scope | PASS (empty array) |
  | Zero budget | PASS (empty array) |

### BB-417: NOTES.md Update
- **File**: `grimoires/loa/NOTES.md`
- **Updates**:
  - Current Focus: Updated to cycle-027, sprint-16
  - Decisions: Added D-007 through D-011 documenting architectural choices (three-tier fallback, jq reduce for budget, SKILL.md instruction pattern, per-skill budgets, --skill flag)
  - Learnings: Added L-009 through L-011 documenting keyword sanitization pattern, path traversal prevention, and bridge context call site gap

## Technical Highlights

### Config Precedence
Clean three-level precedence chain:
1. CLI flags (`--budget`, `--scope`) — highest priority, tracked via `*_EXPLICIT` booleans
2. Skill overrides (`--skill` + config) — middle priority
3. Global config + hardcoded defaults — lowest priority

### No Breaking Changes
- New `--skill` flag is optional — all existing callers continue to work
- Config section is additive — no existing config keys modified
- `BUDGET_EXPLICIT`/`SCOPE_EXPLICIT` tracking replaces fragile sentinel comparison

## Testing Summary

| Suite | Tests | Status |
|-------|-------|--------|
| Unit tests (Sprint 1) | 24/24 | PASS |
| Integration tests (Sprint 2) | 22/22 | PASS |
| E2E validation (Sprint 3) | manual | PASS |
| **Total** | **46/46** | **PASS** |

## Verification Steps

1. Run unit tests: `bash .claude/scripts/qmd-context-query-tests.sh` → 24/24
2. Run integration tests: `bash .claude/scripts/qmd-context-integration-tests.sh` → 22/22
3. Verify config example: `grep -c 'qmd_context' .loa.config.yaml.example` → should show section exists
4. Verify --skill flag: `.claude/scripts/qmd-context-query.sh --help` → shows --skill option
5. Verify NOTES.md: `grep 'D-007\|D-008\|D-009\|D-010\|D-011' grimoires/loa/NOTES.md` → all decisions present
