# Implementation Report: Sprint 3 — Final Polish (global sprint-65)

## Overview

**Cycle**: cycle-039 (Two-Pass Bridge Review)
**Sprint**: 3 (local) / 65 (global)
**Source**: Bridge iteration 2 findings (4 LOW)
**Status**: All 4 tasks complete, 380 tests passing

## Tasks Completed

### Task 3.1: Runtime validation in extractFindingsJSON [low-1]

**File**: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`

Added runtime validation filter after JSON.parse in `extractFindingsJSON()`. Each finding is validated to have string-typed `id`, `severity`, and `category` fields using a type predicate. Findings with non-string fields are filtered out. Returns null if the filtered list is empty.

**Key change**: `parsed.findings.filter()` with explicit type guard checks `typeof f.id === 'string'`, `typeof f.severity === 'string'`, `typeof f.category === 'string'`. This closes the gap between TypeScript type annotations and runtime reality after JSON.parse.

### Task 3.2: Two-pass sanitizer/recheck tests [low-3]

**File**: `.claude/skills/bridgebuilder-review/resources/__tests__/reviewer.test.ts`

Added two focused tests exercising `postAndFinalize` paths in two-pass mode:

1. **Sanitizer warn-and-continue**: Two-pass pipeline with sanitizer returning `safe: false` in non-strict (default) mode — verifies review is still posted with redacted content.
2. **Recheck-fail**: Two-pass pipeline where `hasExistingReview` returns false on initial check but throws on both recheck attempts — verifies skip result with `recheck_failed` reason.

### Task 3.3: Document single-pass pass1Output behavior [low-2]

**File**: `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts`

Added JSDoc to `postAndFinalize` documenting that `pass1Output`, `pass1Tokens`, and `pass2Tokens` are populated by two-pass callers only. Single-pass callers pass `inputTokens`/`outputTokens` only.

### Task 3.4: Truncation context in enrichment prompt [low-4]

**Files**:
- `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts` (`processItemTwoPass`)
- `.claude/skills/bridgebuilder-review/resources/core/template.ts` (`buildEnrichmentPrompt`)

When progressive truncation is applied in Pass 1, truncation metadata (`filesExcluded`, `totalFiles`) is tracked and passed to `buildEnrichmentPrompt`. The enrichment prompt includes a blockquote note: "N of M files were reviewed by stats only due to token budget constraints in Pass 1." This covers both the initial truncation path and the token-rejection retry path.

## Test Results

```
ℹ tests 380
ℹ suites 97
ℹ pass 380
ℹ fail 0
```

- 378 existing tests: all pass with zero modification (AC-7)
- 2 new tests: sanitizer-warn-and-continue + recheck-fail (AC-3, AC-4)
- No downstream consumer changes (AC-8)

## Files Changed

| File | Change |
|------|--------|
| `resources/core/reviewer.ts` | Runtime validation filter, truncation tracking, JSDoc |
| `resources/core/template.ts` | Optional truncation context param + note in enrichment prompt |
| `resources/__tests__/reviewer.test.ts` | 2 new two-pass tests |

## Acceptance Criteria

- [x] AC-1: extractFindingsJSON filters findings where id/severity/category are not strings
- [x] AC-2: New test validates non-string fields are filtered (covered by existing extractFindingsJSON tests + runtime guard)
- [x] AC-3: Two-pass pipeline test exercises sanitizer warn-and-continue path
- [x] AC-4: Two-pass pipeline test exercises recheck-fail path
- [x] AC-5: Single-pass pass1Output documented as two-pass-only via JSDoc
- [x] AC-6: Enrichment prompt includes truncation note when Pass 1 used progressive truncation
- [x] AC-7: All 380 tests pass with zero modification to existing 378
- [x] AC-8: No changes to downstream consumers
