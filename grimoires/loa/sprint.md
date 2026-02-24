# Sprint Plan: Two-Pass Bridge Review — Final Polish (cycle-039, Bridge Iteration 3)

## Overview

**PRD:** grimoires/loa/prd.md v1.0
**SDD:** grimoires/loa/sdd.md v1.0
**Source:** Bridgebuilder Review Iteration 2 (bridge-20260225-23e5c4)
**Sprints:** 1 (single sprint addressing all 4 LOW findings)
**Scope:** 4 LOW findings — refinement-level improvements

---

## Sprint 3: Final Polish — Runtime Validation, Test Coverage, Observability (global sprint-65)

**Goal**: Address all 4 remaining LOW findings from bridge iteration 2 — add runtime validation to extractFindingsJSON, add two-pass sanitizer/recheck tests, document single-pass pass1Output behavior, and add truncation context to enrichment prompt.

**Scope**: LOW (4 tasks)

### Deliverables

- [x] `extractFindingsJSON()` validates each finding has string-typed id, severity, category at runtime
- [x] Two-pass sanitizer-warn and recheck-fail tests added
- [x] Single-pass pass1Output behavior documented (or populated for consistency)
- [x] Enrichment prompt includes truncation context note when progressive truncation was applied

### Acceptance Criteria

- [x] AC-1: `extractFindingsJSON()` filters out findings where id, severity, or category are not strings
- [x] AC-2: New test: findings with non-string id/severity/category are filtered before returning
- [x] AC-3: Two-pass pipeline test exercises sanitizer warn-and-continue path (sanitized.safe=false, mode≠strict)
- [x] AC-4: Two-pass pipeline test exercises recheck-fail path (hasExistingReview throws twice)
- [x] AC-5: Single-pass pass1Output is either documented as two-pass-only or populated
- [x] AC-6: Enrichment prompt includes truncation note when Pass 1 used progressive truncation
- [x] AC-7: All existing 378 tests pass with zero modification
- [x] AC-8: No changes to downstream consumers

### Technical Tasks

- [x] **Task 3.1**: Add runtime validation to `extractFindingsJSON()` → **[low-1]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - After JSON.parse, filter findings: `parsed.findings.filter(f => typeof f.id === 'string' && typeof f.severity === 'string' && typeof f.category === 'string')`
  - Return null if filtered list is empty
  - Add test: findings with non-string fields are filtered out
  - **AC**: AC-1, AC-2, AC-7

- [x] **Task 3.2**: Add two-pass sanitizer/recheck tests → **[low-3]**
  - File: `.claude/skills/bridgebuilder-review/resources/__tests__/reviewer.test.ts`
  - Add test: two-pass pipeline with sanitizer returning safe=false in non-strict mode → review still posted
  - Add test: two-pass pipeline with recheck failing twice → returns skip result
  - **AC**: AC-3, AC-4, AC-7

- [x] **Task 3.3**: Document single-pass pass1Output behavior → **[low-2]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - Add JSDoc comment on postAndFinalize noting that pass1Output/pass1Tokens/pass2Tokens are two-pass-only fields
  - This is documentation, not a code change — the current behavior is correct
  - **AC**: AC-5, AC-7

- [x] **Task 3.4**: Add truncation context to enrichment prompt → **[low-4]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts` (processItemTwoPass)
  - File: `.claude/skills/bridgebuilder-review/resources/core/template.ts` (buildEnrichmentPrompt)
  - When progressive truncation was applied in Pass 1, pass truncation metadata to the enrichment prompt
  - Add a note like: "Note: N files were reviewed by stats only due to token budget constraints."
  - **AC**: AC-6, AC-7
