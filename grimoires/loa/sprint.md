# Sprint Plan: Skill Benchmark Audit — Anthropic Best Practices

**Version**: 1.0.0
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md (v1.1.0)
**SDD**: grimoires/loa/sdd.md (v1.0.0)
**Issue**: #261

---

## Sprint 1: Validation Foundation + Size Compliance (P0)

**Goal**: Create the structural validation test suite and fix the only hard-limit violation.

### Task 1: Create benchmark configuration
- **File**: `.claude/schemas/skill-benchmark.json`
- **Description**: Create JSON config with thresholds (max_words: 5000, max_description_chars: 1024, min_error_references: 5, trigger patterns, forbidden frontmatter patterns)
- **Acceptance Criteria**:
  - [ ] File exists and is valid JSON
  - [ ] All threshold values match PRD requirements
  - [ ] jq can parse it without errors

### Task 2: Create structural validation script
- **File**: `.claude/scripts/validate-skill-benchmarks.sh`
- **Description**: Bash script implementing 10 checks from SDD Section 3.1.1. Must follow existing `validate-skills.sh` output format. Reads thresholds from `skill-benchmark.json`.
- **Acceptance Criteria**:
  - [ ] All 10 checks implemented (SKILL.md exists, word count, no README, kebab-case, name match, no XML frontmatter, description length, WHEN pattern, error refs, frontmatter valid)
  - [ ] Checks 1-7 and 10 are blocking (FAIL); checks 8-9 are warnings
  - [ ] Output matches format: `PASS/FAIL/WARN: skill-name (details)`
  - [ ] Summary shows total/passed/failed/warnings
  - [ ] Exit code 0 if no FAILs, exit code 1 if any FAILs
  - [ ] Script is executable (`chmod +x`)

### Task 3: Update skill-index schema
- **File**: `.claude/schemas/skill-index.schema.json`
- **Description**: Raise description maxLength from 500 to 1024. Add optional `negative_triggers` array field.
- **Acceptance Criteria**:
  - [ ] `description.maxLength` is 1024
  - [ ] `negative_triggers` field added with type array of strings
  - [ ] Existing `validate-skills.sh` still passes

### Task 4: Refactor riding-codebase SKILL.md
- **File**: `.claude/skills/riding-codebase/SKILL.md` + 3 new reference files
- **Description**: Extract ~2,400 words of reference material to `resources/references/`. Create backup (`SKILL.md.bak`). Target ≤4,500 words in SKILL.md.
- **Acceptance Criteria**:
  - [ ] SKILL.md is ≤ 4,500 words (`wc -w`)
  - [ ] 3 reference files created: `output-formats.md`, `analysis-checklists.md`, `deep-analysis-guide.md`
  - [ ] SKILL.md links to reference files with `See: resources/references/...`
  - [ ] Core instructions (phases 0-1, edge cases) remain inline
  - [ ] `SKILL.md.bak` backup exists
  - [ ] `validate-skill-benchmarks.sh` passes for riding-codebase

### Task 5: Run full validation
- **Description**: Execute both validation scripts and verify all checks pass.
- **Acceptance Criteria**:
  - [ ] `validate-skills.sh` exits 0
  - [ ] `validate-skill-benchmarks.sh` exits 0 (riding-codebase under limit)
  - [ ] Only expected warnings remain (5 skills with low error refs — addressed in Sprint 2)

---

## Sprint 2: Description Standardization + Error Handling (P1-P2)

**Goal**: Bring all 19 skill descriptions into compliance and add error handling to underserved skills.

### Task 1: Standardize 19 skill descriptions
- **Files**: 19 `index.yaml` files across `.claude/skills/*/`
- **Description**: Update each description to follow Anthropic's `[What] + [When] + [Capabilities]` formula. Preserve existing trigger file paths. Stay under 1,024 characters.
- **Acceptance Criteria**:
  - [ ] All 19 descriptions follow the 3-line template
  - [ ] All descriptions ≤ 1,024 characters
  - [ ] All descriptions contain "Use when" or equivalent trigger context
  - [ ] No trigger file paths dropped from descriptions that reference them
  - [ ] `validate-skill-benchmarks.sh` shows 0 description warnings

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
| NFR-1: Zero behavioral regressions | SKILL.md.bak backups + validation before/after |
| NFR-2: No new dependencies | Script uses bash, wc, grep, jq (all existing) |
| NFR-3: Backward compatible | Trigger arrays unchanged; descriptions only updated |
| NFR-4: Documentation-only | No application code changes |

---

## Risk Mitigations

| Risk | Mitigation | Owner |
|------|-----------|-------|
| R-1: Triggering breaks | Run validation before/after every skill change | Sprint 1 T2 |
| R-5: Post-merge regression | SKILL.md.bak copies, 7-day observation window | Sprint 1 T4 |
