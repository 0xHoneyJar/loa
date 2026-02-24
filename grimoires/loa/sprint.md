# Sprint Plan: Two-Pass Bridge Review — Excellence Hardening (cycle-039, Bridge Iteration 2)

## Overview

**PRD:** grimoires/loa/prd.md v1.0
**SDD:** grimoires/loa/sdd.md v1.0
**Source:** Bridgebuilder Review Iteration 1 (bridge-20260225-23e5c4)
**Sprints:** 1 (single sprint addressing all 6 actionable findings)
**Scope:** 3 MEDIUM + 3 LOW findings from bridge review

---

## Sprint 2: Excellence Hardening — Post-Processing Dedup + Correctness Fixes (global sprint-64)

**Goal**: Address all 6 actionable Bridgebuilder findings from iteration 1 — extract shared post-processing method, add category preservation, consolidate prompt duplication, return parsed JSON, fix fallback gap, and wire test fixtures.

**Scope**: MEDIUM (6 tasks)

### Deliverables

- [ ] `reviewer.ts` has shared `postAndFinalize()` method replacing 4 duplicate post-processing paths
- [ ] `validateFindingPreservation()` checks category preservation in addition to count, IDs, severities
- [ ] `template.ts` convergence user prompt methods consolidated (shared rendering helpers)
- [ ] `extractFindingsJSON()` returns `{ raw, parsed }` eliminating triple-parse
- [ ] Pass 2 missing findings markers triggers explicit fallback to unenriched output
- [ ] Test fixtures loaded via `fs.readFileSync` in test suite (or removed if redundant)

### Acceptance Criteria

- [ ] AC-1: Post-processing flow (sanitize → recheck → dryRun → post → finalize) exists in exactly ONE method
- [ ] AC-2: `finishWithUnenrichedOutput`, `finishWithPass1AsReview`, and tail of `processItemTwoPass` all delegate to shared method
- [ ] AC-3: Single-pass `processItem` also delegates to the shared post-processing method
- [ ] AC-4: `validateFindingPreservation()` returns false when Pass 2 changes a finding's category
- [ ] AC-5: New test: category-changed fixture fails validation
- [ ] AC-6: Convergence user prompt rendering logic exists in one place (shared helpers or single method)
- [ ] AC-7: `extractFindingsJSON()` returns `{ raw: string; parsed: FindingsPayload } | null`
- [ ] AC-8: Callers of `extractFindingsJSON()` use `.parsed` instead of re-parsing
- [ ] AC-9: When `extractFindingsJSON()` returns null for Pass 2 AND `isValidResponse()` passes, system falls back to unenriched output
- [ ] AC-10: Test fixtures are loaded from disk in at least one test case per fixture file
- [ ] AC-11: All existing 164 tests pass with zero modification
- [ ] AC-12: No changes to downstream consumers (findings parser, GitHub trail, convergence scorer)

### Technical Tasks

- [ ] **Task 2.1**: Extract shared `postAndFinalize()` method in `reviewer.ts` → **[medium-1]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - Extract the repeated sanitize → recheck-guard-with-retry → dryRun → post → finalize sequence into a shared private method
  - Signature: `private async postAndFinalize(item: ReviewItem, body: string, result: Partial<ReviewResult>): Promise<ReviewResult>`
  - Replace the 4 copies: `finishWithUnenrichedOutput` (lines 645-698), `finishWithPass1AsReview` (lines 988-1035), `processItemTwoPass` tail (lines 910-974), and single-pass `processItem` (lines 400-492)
  - Each caller builds its own `body` string and `result` fields, then delegates to `postAndFinalize`
  - **AC**: AC-1, AC-2, AC-3, AC-11

- [ ] **Task 2.2**: Add category preservation to `validateFindingPreservation()` → **[medium-2]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - After the severity check loop (line 604), add: `if (f2.category !== f1.category) return false;`
  - Create new test fixture: `pass2-category-changed.md` — same 3 findings as pass1-valid-findings.json but with F003 category changed from "test-coverage" to "quality"
  - Add test: `validateFindingPreservation rejects category reclassification`
  - **AC**: AC-4, AC-5, AC-11

- [ ] **Task 2.3**: Consolidate convergence user prompt methods in `template.ts` → **[medium-3]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/template.ts`
  - Extract shared rendering logic into private helpers:
    - `private renderPRMetadata(item: ReviewItem): string[]` — PR header, labels, etc.
    - `private renderExcludedFiles(excluded: Array<{filename: string; stats: string}>): string[]`
    - `private renderConvergenceFormat(): string[]` — the "Expected Response Format" section
  - Refactor `buildConvergenceUserPrompt()` and `buildConvergenceUserPromptFromTruncation()` to use shared helpers
  - Only the file iteration differs (TruncationResult.included vs ProgressiveTruncationResult.files)
  - **AC**: AC-6, AC-11

- [ ] **Task 2.4**: Return `{ raw, parsed }` from `extractFindingsJSON()` → **[low-1]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - Change return type from `string | null` to `{ raw: string; parsed: { findings: Array<{ id: string; severity: string; category: string; [key: string]: unknown }> } } | null`
  - Return `{ raw: jsonStr, parsed }` instead of discarding the parsed object
  - Update both callers in `processItemTwoPass()` to use `.raw` for string operations and `.parsed` for validation
  - Update `validateFindingPreservation()` to accept parsed objects directly instead of re-parsing
  - **AC**: AC-7, AC-8, AC-11

- [ ] **Task 2.5**: Fix Pass 2 missing markers fallback → **[low-2]**
  - File: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`
  - At lines 876-888: when `pass2FindingsJSON` is null (markers missing or malformed), explicitly fall back to unenriched output BEFORE the `isValidResponse` check
  - Logic: if `extractFindingsJSON(pass2Response.content)` returns null → `this.finishWithUnenrichedOutput(...)` (because Pass 2 lost the structured findings)
  - Add test: Pass 2 produces valid prose (has ## Summary + ## Findings) but no `<!-- bridge-findings-start/end -->` markers → system falls back to unenriched output
  - **AC**: AC-9, AC-11

- [ ] **Task 2.6**: Wire test fixtures to test suite → **[low-3]**
  - Files: `.claude/skills/bridgebuilder-review/resources/__tests__/reviewer.test.ts`, fixture files
  - Add fixture-loading tests that read from disk:
    - Load `pass1-valid-findings.json` → verify `extractFindingsJSON()` parses correctly
    - Load `pass2-enriched-valid.md` → verify `extractFindingsJSON()` extracts enriched findings
    - Load `pass2-findings-added.md` → verify `validateFindingPreservation()` returns false
    - Load `pass2-severity-changed.md` → verify `validateFindingPreservation()` returns false
    - Load `pass1-malformed.txt` → verify `extractFindingsJSON()` returns null
  - Use `import { readFileSync } from 'fs'` and `import { join } from 'path'`
  - **AC**: AC-10, AC-11

### Task 2.E2E: End-to-End Goal Validation

- [ ] Run full test suite — all 164+ existing tests pass, new tests pass
- [ ] Verify `processItem` single-pass path still works end-to-end (delegating to `postAndFinalize`)
- [ ] Verify `processItemTwoPass` happy path still works (delegating to `postAndFinalize`)
- [ ] Verify fallback paths: Pass 2 failure, finding modification, missing markers all fall back correctly

### Dependencies

- Task 2.1 (postAndFinalize) should be done first — it touches the most code
- Task 2.4 (extractFindingsJSON return type) should be done before Task 2.5 (fallback fix) — parsed result used in fallback logic
- Task 2.2 (category preservation) and Task 2.3 (template consolidation) are independent
- Task 2.6 (fixture wiring) depends on Task 2.2 (new fixture) and Task 2.4 (return type change)

### Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| `postAndFinalize` extraction breaks subtle behavior differences | Each caller currently has identical post-processing; verify with existing test suite |
| Category preservation breaks existing tests | Existing fixtures don't test categories; only new fixture exercises this path |
| Template helper extraction changes prompt output | Compare rendered prompts before/after with snapshot tests |
| `extractFindingsJSON` return type change cascades | Only 2 callers exist in `processItemTwoPass`; update both simultaneously |
