# Sprint Plan: Skill Benchmark Audit — Anthropic Best Practices

**Version**: 1.1.0 (Flatline-hardened)
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md (v1.1.0)
**SDD**: grimoires/loa/sdd.md (v1.0.0)
**Issue**: #261

---

## Flatline Sprint Review Summary

| Metric | Value |
|--------|-------|
| Models | Claude Opus 4.6 + GPT-5.2 |
| Agreement | 90% |
| HIGH_CONSENSUS integrated | 4 (IMP-001, IMP-002, IMP-003, IMP-006) |
| BLOCKERS accepted | 3 (SKP-003, SKP-006, SKP-007) |
| DISPUTED logged | 1 (IMP-010 — deferred, observation monitoring is over-scoped) |
| SKP-001 (CI integration) | Addressed via IMP-003 (same recommendation) |

---

## Sprint 1: Validation Foundation + Size Compliance (P0)

**Goal**: Create the structural validation test suite, test it with fixtures, fix the only hard-limit violation, and add CI integration.

### Task 1: Create benchmark configuration
- **File**: `.claude/schemas/skill-benchmark.json`
- **Description**: Create JSON config with thresholds (max_words: 5000, max_description_chars: 1024, min_error_references: 5, trigger patterns, forbidden frontmatter patterns)
- **Acceptance Criteria**:
  - [ ] File exists and is valid JSON
  - [ ] All threshold values match PRD requirements
  - [ ] jq can parse it without errors
  - [ ] Script handles missing/malformed config gracefully with clear error message (IMP-002)

### Task 2: Create structural validation script
- **File**: `.claude/scripts/validate-skill-benchmarks.sh`
- **Description**: Bash script implementing 10 checks from SDD Section 3.1.1. Must follow existing `validate-skills.sh` output format. Reads thresholds from `skill-benchmark.json`. Uses POSIX-compatible tools only (no GNU-specific flags).
- **Acceptance Criteria**:
  - [ ] All 10 checks implemented (SKILL.md exists, word count, no README, kebab-case, name match, no XML frontmatter, description length, WHEN pattern, error refs, frontmatter valid)
  - [ ] Checks 1-7 and 10 are blocking (FAIL); checks 8-9 are warnings
  - [ ] Output matches format: `PASS/FAIL/WARN: skill-name (details)`
  - [ ] Summary shows total/passed/failed/warnings
  - [ ] Exit code 0 if no FAILs, exit code 1 if any FAILs
  - [ ] Script is executable (`chmod +x`)
  - [ ] Graceful error on missing/invalid benchmark config JSON (IMP-002)

### Task 3: Create test fixtures for validation script (SKP-007)
- **Dir**: `.claude/skills/__test-compliant__/` and `.claude/skills/__test-noncompliant__/`
- **Description**: Create deliberately compliant and non-compliant skill directories as test fixtures. Run validator against both to prove all 10 checks work. Clean up fixture dirs after test.
- **Acceptance Criteria**:
  - [ ] Compliant fixture: passes all 10 checks
  - [ ] Non-compliant fixture: triggers FAIL on word count, missing SKILL.md, README.md present, bad folder name, XML in frontmatter
  - [ ] Test script verifies validator catches all failure modes
  - [ ] Fixture dirs prefixed with `__` to avoid confusion with real skills
  - [ ] Cleanup step removes fixture dirs after test run (IMP-006)

### Task 4: Update skill-index schema
- **File**: `.claude/schemas/skill-index.schema.json`
- **Description**: Raise description maxLength from 500 to 1024. Add optional `negative_triggers` array field.
- **Acceptance Criteria**:
  - [ ] `description.maxLength` is 1024
  - [ ] `negative_triggers` field added with type array of strings
  - [ ] Existing `validate-skills.sh` still passes

### Task 5: Refactor riding-codebase SKILL.md
- **File**: `.claude/skills/riding-codebase/SKILL.md` + 3 new reference files
- **Description**: Extract ~2,400 words of reference material to `resources/references/`. Create backup (`SKILL.md.bak`). Target ≤4,500 words in SKILL.md.
- **Acceptance Criteria**:
  - [ ] SKILL.md is ≤ 4,500 words (`wc -w`)
  - [ ] 3 reference files created: `output-formats.md`, `analysis-checklists.md`, `deep-analysis-guide.md`
  - [ ] SKILL.md links to reference files with `See: resources/references/...`
  - [ ] Core instructions (phases 0-1, edge cases) remain inline
  - [ ] `SKILL.md.bak` backup exists
  - [ ] `validate-skill-benchmarks.sh` passes for riding-codebase
  - [ ] Behavioral smoke test: invoke `/ride` on a small test repo before and after refactoring, verify output is functionally equivalent (SKP-003)

### Task 6: Rollback playbook (IMP-001)
- **Description**: Document explicit rollback steps for Sprint 1 changes.
- **Acceptance Criteria**:
  - [ ] Rollback steps documented in sprint report: restore SKILL.md.bak, revert schema, remove validation script
  - [ ] Decision criteria: who decides to rollback, what signals trigger it
  - [ ] Re-validation steps after rollback

### Task 7: Run full validation + CI integration (IMP-003)
- **Description**: Execute both validation scripts, verify all checks pass, and document CI integration point.
- **Acceptance Criteria**:
  - [ ] `validate-skills.sh` exits 0
  - [ ] `validate-skill-benchmarks.sh` exits 0 (riding-codebase under limit)
  - [ ] Only expected warnings remain (5 skills with low error refs — addressed in Sprint 2)
  - [ ] CI integration documented: which GitHub Actions workflow to add the validator to, with the exact step definition

---

## Sprint 2: Description Standardization + Error Handling (P1-P2)

**Goal**: Bring all 19 skill descriptions into compliance (batched) and add error handling to underserved skills.

### Task 1a: Standardize descriptions — Batch 1 (skills 1-5)
- **Files**: `auditing-security`, `autonomous-agent`, `bridgebuilder-review`, `browsing-constructs`, `continuous-learning` index.yaml
- **Description**: Update 5 descriptions to follow `[What] + [When] + [Capabilities]` formula. Run validation after batch.
- **Acceptance Criteria**:
  - [ ] 5 descriptions follow the 3-line template, ≤ 1,024 chars
  - [ ] Contain "Use when" or equivalent trigger context
  - [ ] No trigger file paths dropped
  - [ ] `validate-skill-benchmarks.sh` passes for these 5 (SKP-006)

### Task 1b: Standardize descriptions — Batch 2 (skills 6-10)
- **Files**: `deploying-infrastructure`, `designing-architecture`, `discovering-requirements`, `enhancing-prompts`, `flatline-knowledge` index.yaml
- **Acceptance Criteria**: Same as Task 1a for these 5 skills

### Task 1c: Standardize descriptions — Batch 3 (skills 11-15)
- **Files**: `implementing-tasks`, `mounting-framework`, `planning-sprints`, `reviewing-code`, `riding-codebase` index.yaml
- **Acceptance Criteria**: Same as Task 1a for these 5 skills

### Task 1d: Standardize descriptions — Batch 4 (skills 16-19)
- **Files**: `rtfm-testing`, `run-mode`, `simstim-workflow`, `translating-for-executives` index.yaml
- **Acceptance Criteria**: Same as Task 1a for these 4 skills

### Task 2: Add error handling to bridgebuilder-review
- **File**: `.claude/skills/bridgebuilder-review/SKILL.md`
- **Description**: Add `## Error Handling` section with error table and troubleshooting. Cover: API failures, auth errors, rate limits, dry-run edge cases, large PR handling.
- **Acceptance Criteria**:
  - [ ] Error handling section added with ≥ 5 error references
  - [ ] Error table with cause and resolution columns
  - [ ] Word count still under 5,000
  - [ ] `validate-skill-benchmarks.sh` passes

### Task 3: Add error handling to designing-architecture
- **File**: `.claude/skills/designing-architecture/SKILL.md`
- **Description**: Add error handling for: PRD not found, clarification loop timeout, SDD generation failure.
- **Acceptance Criteria**:
  - [ ] Error handling section added with ≥ 5 error references
  - [ ] Word count still under 5,000

### Task 4: Add error handling to flatline-knowledge
- **File**: `.claude/skills/flatline-knowledge/SKILL.md`
- **Description**: Add error handling for: NotebookLM auth, API timeout, cache miss, model unavailable.
- **Acceptance Criteria**:
  - [ ] Error handling section added with ≥ 5 error references
  - [ ] Word count still under 5,000

### Task 5: Add error handling to mounting-framework
- **File**: `.claude/skills/mounting-framework/SKILL.md`
- **Description**: Add error handling for: Permission denied, existing mount, partial install, version mismatch.
- **Acceptance Criteria**:
  - [ ] Error handling section added with ≥ 5 error references
  - [ ] Word count still under 5,000

### Task 6: Add error handling to planning-sprints
- **File**: `.claude/skills/planning-sprints/SKILL.md`
- **Description**: Add error handling for: PRD/SDD missing, capacity estimation, dependency cycles, empty sprint.
- **Acceptance Criteria**:
  - [ ] Error handling section added with ≥ 5 error references
  - [ ] Word count still under 5,000

### Task 7: Final validation pass
- **Description**: Run both validation scripts. All 19 skills must pass with zero failures and zero warnings.
- **Acceptance Criteria**:
  - [ ] `validate-skills.sh` exits 0
  - [ ] `validate-skill-benchmarks.sh` exits 0 with 0 warnings
  - [ ] All 19 SKILL.md files ≤ 5,000 words
  - [ ] All 19 descriptions ≤ 1,024 chars with trigger context
  - [ ] All 19 skills have ≥ 5 error references

---

## NFR Compliance

| NFR | Verification |
|-----|-------------|
| NFR-1: Zero behavioral regressions | SKILL.md.bak backups + validation before/after + behavioral smoke test for riding-codebase (SKP-003) |
| NFR-2: No new dependencies | Script uses bash, wc, grep, jq (all existing, POSIX-compatible) |
| NFR-3: Backward compatible | Trigger arrays unchanged; descriptions batched to isolate regressions (SKP-006) |
| NFR-4: Documentation-only | No application code changes |

---

## Risk Mitigations

| Risk | Mitigation | Owner |
|------|-----------|-------|
| R-1: Triggering breaks | Run validation before/after every skill change | Sprint 1 T2 |
| R-5: Post-merge regression | SKILL.md.bak copies, 7-day observation, documented rollback playbook (IMP-001) | Sprint 1 T6 |
| R-6: Validator false positives | Test fixtures prove all 10 checks against known inputs (SKP-007) | Sprint 1 T3 |
| R-7: Description batch regression | 4 batches of 5 skills with validation between each (SKP-006) | Sprint 2 T1a-d |
| R-8: CI drift | Document exact CI integration step (IMP-003) | Sprint 1 T7 |
