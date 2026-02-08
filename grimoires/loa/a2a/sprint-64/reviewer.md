# Sprint 1 (Global: sprint-64) — Implementation Report

## Sprint Goal
Hexagonal Foundation: Core domain + Port interfaces for Bridgebuilder skill extraction.

## Task Summary

| Task | Title | Status | GPT Review | Files |
|------|-------|--------|------------|-------|
| 1.1 | Port interfaces | DONE | Skipped (interfaces) | 7 port files + barrel |
| 1.2 | Domain types | DONE | Skipped (types) | core/types.ts |
| 1.3 | truncateFiles() | DONE | APPROVED (iter 2) | core/truncation.ts |
| 1.4 | PRReviewTemplate | DONE | APPROVED (iter 2) | core/template.ts |
| 1.5 | BridgebuilderContext | DONE | APPROVED (iter 1) | core/context.ts |
| 1.6 | ReviewPipeline | DONE | APPROVED (iter 2) | core/reviewer.ts |
| 1.7 | Core barrel | DONE | Skipped (re-exports) | core/index.ts |
| 1.8 | Unit tests | DONE | Skipped (tests) | 4 test files |

## Files Created

### Port Interfaces (`resources/ports/`)
- `git-provider.ts` — IGitProvider + PullRequest, PullRequestFile, PRReview, PreflightResult, RepoPreflightResult
- `llm-provider.ts` — ILLMProvider + ReviewRequest, ReviewResponse
- `review-poster.ts` — IReviewPoster + PostReviewInput, ReviewEvent
- `output-sanitizer.ts` — IOutputSanitizer + SanitizationResult
- `hasher.ts` — IHasher
- `logger.ts` — ILogger
- `context-store.ts` — IContextStore (persistence only, no hasChanged)
- `index.ts` — Barrel re-export

### Core Domain (`resources/core/`)
- `types.ts` — BridgebuilderConfig, ReviewItem, ReviewResult, ReviewError, ErrorCategory, RunSummary, TruncationResult
- `truncation.ts` — truncateFiles() pure function with exclude-pattern tracking, risk prioritization, byte budget, patch-optional handling
- `template.ts` — PRReviewTemplate class with injection hardening, canonical hash, structured output format
- `context.ts` — BridgebuilderContext class with hash-based change detection, store delegation
- `reviewer.ts` — ReviewPipeline orchestrator with 9-step pipeline, preflight, token guard, sanitizer modes, runtime enforcement
- `index.ts` — Core barrel export

### Tests (`resources/__tests__/`)
- `truncation.test.ts` — 12 tests: exclude patterns, risk sorting, budget, patch-optional, empty input, no mutation
- `template.test.ts` — 6 tests: injection hardening, PR metadata, output format, resolveItems, canonical hash, maxPrs
- `context.test.ts` — 7 tests: load delegation, hasChanged (null/match/differ), claimReview, finalizeReview ordering
- `reviewer.test.ts` — 11 tests: skip existing, dryRun, validation (empty/refusal/missing headings), marker, re-check guard, error categorization, sanitizer modes, preflight, runtime, summary counts

## GPT Review Findings Resolved

### truncation.ts (2 issues → fixed)
1. **Excluded-by-pattern files silently dropped** → Now tracked in excluded array with "(excluded by pattern)" annotation
2. **Falsy patch check** → Changed `!file.patch` to `file.patch == null` for proper null/undefined detection

### template.ts (1 issue → fixed)
1. **Heading mismatch** → Changed `## Positive Callouts` to `## Callouts` to match acceptance criteria

### reviewer.ts (1 issue → fixed)
1. **Token estimation ignored systemPrompt** → Changed to `(systemPrompt.length + userPrompt.length) / 4`

Additional self-fix: Replaced unsafe `git` accessor (cast through `unknown`) with proper constructor parameter.

## Architecture Compliance

- **Hexagonal boundary**: All core classes depend only on port interfaces. No adapter imports.
- **Pure functions**: truncateFiles() has no side effects, no mutations.
- **IContextStore separation**: Persistence only — hasChanged logic lives in BridgebuilderContext.
- **ESM conventions**: All imports use `.js` extensions for NodeNext resolution.
- **No secrets**: No hardcoded tokens, keys, or credentials.

## Known Deviations from SDD

1. **BridgebuilderContext.hasChanged()** takes `ReviewItem` instead of `(repo, prNumber, headSha)` — cleaner API, hash is pre-computed in ReviewItem
2. **ReviewPipeline constructor** takes `IGitProvider` directly for preflight, rather than accessing through template's private field
3. **TruncationResult.excluded** uses `Array<{filename, stats}>` instead of SDD's `summarized: PullRequestFile[]` — simpler, avoids carrying full file objects for stats-only entries

## Beads Task Status

All 8 tasks closed:
- bd-2bo, bd-2jv, bd-3nm, bd-2bg, bd-l4b, bd-18s, bd-160, bd-3m1
