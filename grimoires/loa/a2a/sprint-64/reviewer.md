# Sprint 64 Implementation Report — Excellence Hardening (Bridge Iteration 2)

**Sprint**: 2 (global 64) | **Cycle**: 039
**Source**: Bridgebuilder Review Iteration 1 (bridge-20260225-23e5c4)
**Scope**: 6 tasks addressing 3 MEDIUM + 3 LOW findings

## Summary

All 6 tasks from the bridge iteration 1 review have been implemented. The changes eliminate 4-way code duplication in post-processing paths, add category preservation to the finding validation guard, consolidate convergence prompt rendering, return parsed JSON to eliminate triple-parse, fix a fallback gap when Pass 2 loses structured markers, and wire fixture-based tests with ESM-compatible imports.

**Test results**: 378 pass, 0 fail (up from 373 — 5 new fixture-based tests added).

## Task Completion

### Task 2.1: Extract shared `postAndFinalize()` method — [medium-1] DONE

**File**: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`

Extracted the repeated sanitize → recheck-guard-with-retry → dryRun → post → finalize sequence into a single private method:

```typescript
private async postAndFinalize(
  item: ReviewItem,
  body: string,
  resultFields: Omit<ReviewResult, "item" | "posted" | "skipped">,
): Promise<ReviewResult>
```

Refactored all 4 callers to delegate:
1. Single-pass `processItem` tail
2. `finishWithUnenrichedOutput`
3. `processItemTwoPass` tail (happy path)
4. `finishWithPass1AsReview`

Each caller builds its own `body` string and `resultFields`, then delegates to `postAndFinalize`.

**AC satisfied**: AC-1, AC-2, AC-3, AC-11

### Task 2.2: Category preservation in `validateFindingPreservation()` — [medium-2] DONE

**File**: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`

Changed method signature to accept parsed objects directly (instead of JSON strings):
```typescript
private validateFindingPreservation(
  pass1Findings: { findings: Array<{ id: string; severity: string; category: string; ... }> },
  pass2Findings: { findings: Array<{ id: string; severity: string; category: string; ... }> },
): boolean
```

Added `if (f2.category !== f1.category) return false;` after the severity check.

**New fixture**: `__tests__/fixtures/pass2-category-changed.md` — F003 category changed from "test-coverage" to "quality".

**New tests**:
- "falls back when Pass 2 reclassifies category" (inline data)
- Fixture-based: "validateFindingPreservation rejects pass2-category-changed.md fixture"

**AC satisfied**: AC-4, AC-5, AC-11

### Task 2.3: Consolidate convergence user prompt methods — [medium-3] DONE

**File**: `.claude/skills/bridgebuilder-review/resources/core/template.ts`

Extracted 3 private helpers:
- `renderPRMetadata(item: ReviewItem): string[]` — PR header lines (title, author, base, head SHA, labels)
- `renderExcludedFiles(excluded: Array<{filename: string; stats: string}>): string[]` — truncated file entries
- `renderConvergenceFormat(): string[]` — findings-only format instructions

Both `buildConvergenceUserPrompt` and `buildConvergenceUserPromptFromTruncation` now delegate to these shared helpers. The only difference between them is the file iteration source (`TruncationResult.included` vs `ProgressiveTruncationResult.files`).

**AC satisfied**: AC-6, AC-11

### Task 2.4: Return `{ raw, parsed }` from `extractFindingsJSON()` — [low-1] DONE

**File**: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`

Changed return type from `string | null` to:
```typescript
{ raw: string; parsed: { findings: Array<{ id: string; severity: string; category: string; [key: string]: unknown }> } } | null
```

Returns `{ raw: jsonStr, parsed }` instead of discarding the parsed object. Callers in `processItemTwoPass` updated to use `.raw` for the enrichment prompt and `.parsed` for validation — eliminating the triple-parse pattern.

**AC satisfied**: AC-7, AC-8, AC-11

### Task 2.5: Fix Pass 2 missing markers fallback — [low-2] DONE

**File**: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`

Added explicit fallback when `extractFindingsJSON(pass2Response.content)` returns null:
```typescript
} else {
  // Pass 2 lost structured findings markers — fall back to unenriched output
  this.logger.warn("Pass 2 missing findings markers, using Pass 1 output", { ... });
  return this.finishWithUnenrichedOutput(...);
}
```

Previously, when Pass 2 produced valid prose but no `<!-- bridge-findings-start/end -->` markers, the code would fall through to the `isValidResponse` check and could post un-validated content.

**New test**: "falls back when Pass 2 has valid prose but no findings markers"

**AC satisfied**: AC-9, AC-11

### Task 2.6: Wire test fixtures — [low-3] DONE

**Files**: `__tests__/reviewer.test.ts`, fixture files

Added ESM-compatible imports (`readFileSync`, `join`, `dirname`, `fileURLToPath`) and created a "fixture-based tests" describe block with 5 tests:

1. `pass1-valid-findings.json` → should extract and process successfully
2. `pass1-malformed.txt` → should skip (no valid findings)
3. `pass2-findings-added.md` → should fall back (added finding)
4. `pass2-severity-changed.md` → should fall back (severity reclassified)
5. `pass2-category-changed.md` → should fall back (category reclassified)

**AC satisfied**: AC-10, AC-11

### Task 2.E2E: End-to-End Validation DONE

- Full test suite: 378 pass, 0 fail
- Single-pass processItem path works via `postAndFinalize` delegation
- Two-pass happy path works via `postAndFinalize` delegation
- Fallback paths verified: Pass 2 failure, finding modification, missing markers, category change

**AC satisfied**: AC-11, AC-12

## Files Changed

| File | Changes |
|------|---------|
| `resources/core/reviewer.ts` | `postAndFinalize()` extracted; `extractFindingsJSON()` return type changed; `validateFindingPreservation()` accepts parsed objects + category check; Pass 2 missing markers fallback |
| `resources/core/template.ts` | `renderPRMetadata()`, `renderExcludedFiles()`, `renderConvergenceFormat()` helpers extracted; convergence methods refactored |
| `resources/__tests__/reviewer.test.ts` | ESM imports added; 2 inline tests + 5 fixture-based tests added |
| `resources/__tests__/fixtures/pass2-category-changed.md` | New fixture: F003 category changed |

## Risks & Notes

- No downstream consumer changes needed — findings parser, GitHub trail, convergence scorer all receive the same shaped output
- The `postAndFinalize` extraction preserves all behavior including strict mode recheck, dry-run gating, and finalize callback
- Category preservation is additive — existing tests don't exercise category changes so no regressions possible
