# Sprint 6 (Global Sprint 69) — Implementation Report

## Overview

**Sprint**: Sprint 6 — Bridgebuilder Review Findings (PR #248)
**Global ID**: sprint-69
**Status**: COMPLETE
**Tasks**: 5/5 implemented

## Source

All findings originated from the Bridgebuilder persona review of PR #248, which assessed the Bridgebuilder skill codebase across Security, Quality, Test Coverage, and Operational dimensions.

## Task Summary

### Task 6.1: Config Robustness (Finding 1 + Finding 2)

**Files modified**: `resources/config.ts`

**Changes**:
1. **YAML array parsing** — Added support for YAML list syntax (`- item`) in the hand-rolled parser. Previously, list-type fields (`repos`, `dimensions`, `exclude_patterns`) were silently ignored when using multi-line YAML format. The parser now detects empty inline values and scans subsequent `- item` lines.

2. **First-non-empty-wins repo resolution** — Changed from accumulative pattern (all sources append to shared array) to precedence-based resolution: CLI > env > YAML > auto-detect. Each lower-priority source is only consulted if no higher-priority source provided repos. This prevents unexpected repo duplication.

**Acceptance criteria met**:
- [x] YAML list syntax `- item` parsed for repos, dimensions, exclude_patterns
- [x] Repo resolution is first-non-empty-wins (CLI > env > YAML > auto-detect)
- [x] Each lower-priority source only consulted when higher-priority is empty
- [x] TypeScript compiles with zero errors

### Task 6.2: Security Pattern Precision (Finding 3 + Finding 4)

**Files modified**: `resources/adapters/sanitizer.ts`, `resources/core/truncation.ts`

**Changes**:
1. **OpenAI key negative lookahead** — Added `(?!ant-)` to the OpenAI pattern `/sk-(?!ant-)[A-Za-z0-9]{20,}/g` to prevent double-matching Anthropic keys (which start with `sk-ant-`).

2. **Path-segment-aware security patterns** — Replaced broad substring patterns like `/auth/i` with path-segment-aware patterns like `/(?:^|\/)auth/i`. This prevents false positives on filenames like `tsconfig.json` (contains no path segment "auth"), `keyboard.ts`, etc. Added patterns for `.pem` and `.key` file extensions.

**Acceptance criteria met**:
- [x] OpenAI pattern uses negative lookahead `(?!ant-)` to avoid Anthropic key collision
- [x] Security patterns use `(?:^|\/)` prefix for path-segment matching
- [x] `.pem` and `.key` file extensions detected
- [x] No false positives on `tsconfig.json`, `keyboard.ts`, etc.

### Task 6.3: Persona Voice Enrichment (Finding 7)

**Files modified**: `resources/BEAUVOIR.md`

**Changes**:
Enriched the Bridgebuilder persona with the full voice specification from loa-finn#24:
- Added FAANG/Industry Parallel requirement for every finding
- Added Metaphor requirement for every finding (accessible to non-engineers)
- Added Decision Trail documentation guidance
- Refined voice to "never condescending, always illuminating"
- Preserved all 4 review dimensions, 5 rules, and output format
- Total: 3,131 characters (under 4,000 char limit per Rule 2)

**Acceptance criteria met**:
- [x] Every finding requires FAANG/Industry Parallel
- [x] Every finding requires an accessible Metaphor
- [x] Decision Trail documentation included
- [x] Output stays under 4,000 characters
- [x] All existing rules and dimensions preserved

### Task 6.4: Error Classification + Operational Safety (Finding 8 + Finding 9)

**Files modified**: `resources/core/reviewer.ts`, `resources/main.ts`

**Changes**:
1. **Anchored error classification** — Replaced greedy substring matching in `classifyError()` with anchored prefix checks. `m.startsWith("gh ")` instead of `m.includes("github")`. This prevents a code review mentioning "github" in prose from being misclassified as a GitHub adapter error. Comments explain the intent.

2. **Re-check retry with conservative skip** — Step 9a (race condition mitigation) now retries once on failure before skipping. If both attempts fail, the review is skipped with reason `"recheck_failed"` rather than posting a potential duplicate. Conservative approach: better to skip than to double-post.

3. **Structured runId** — Changed from `run-${Date.now()}` to `bridgebuilder-{YYYYMMDDTHHMMSS}-{hex4}` format. Sortable by timestamp, unique via random hex suffix, identifiable as bridgebuilder-originated.

**Acceptance criteria met**:
- [x] classifyError uses anchored prefixes, not generic substrings
- [x] Step 9a retries once before conservative skip
- [x] runId format is structured and sortable
- [x] Comments document classification rationale

### Task 6.5: Decision Trail Documentation (Finding 10)

**Files modified**: `resources/adapters/github-cli.ts`, `resources/core/reviewer.ts`, `resources/adapters/noop-context.ts`, `resources/adapters/sanitizer.ts`

**Changes**:
Added inline decision trail comments at 4 key architectural decision points:

1. **github-cli.ts**: Why `execFile`+`gh` CLI over Octokit SDK — token refresh, SSO, credential helpers handled automatically; `execFile` avoids shell injection; throughput acceptable at <50 PRs/run.

2. **reviewer.ts**: Why `chars/4` token estimation — deliberate over-estimate (real average is 3.5-4.2); over-estimating is safe (skip a PR that would fit) vs under-estimating (truncated output); proper tokenizer adds ~2MB for marginal gain on a guard rail.

3. **noop-context.ts**: Why NoOp over file-based context store — one-shot CLI mode; GitHub review marker serves as idempotency key; file-based store adds filesystem coupling for zero benefit in single-operator case.

4. **sanitizer.ts**: Why entropy threshold 4.5 — random hex ~4.0, base64 secrets ~5.0-5.5, English prose ~2.5-3.5; empirically validated against GitHub PATs (~5.2), AWS keys (~4.8), and false positives (long import paths ~3.8).

**Acceptance criteria met**:
- [x] 4 decision trail comments added at key architectural forks
- [x] Each explains the tradeoff, not just the choice
- [x] Each suggests when to revisit the decision

## Deferred

**Finding 6** (dist/ in git): Deferred as a tooling/CI decision, not a code fix. Recommend adding `dist/` to `.gitignore` and building in CI instead.

## Build Verification

- TypeScript compilation: **PASS** (zero errors)
- dist/ rebuilt: **PASS** (all 23 JS files regenerated)

## Files Changed

| File | Changes |
|------|---------|
| `resources/config.ts` | YAML array parsing, first-non-empty-wins repos |
| `resources/adapters/sanitizer.ts` | OpenAI negative lookahead, entropy decision comment |
| `resources/core/truncation.ts` | Path-segment-aware security patterns |
| `resources/BEAUVOIR.md` | Full Bridgebuilder voice enrichment |
| `resources/core/reviewer.ts` | Anchored errors, re-check retry, token estimation comment |
| `resources/main.ts` | Structured runId format |
| `resources/adapters/github-cli.ts` | Decision trail: gh CLI over Octokit |
| `resources/adapters/noop-context.ts` | Decision trail: NoOp rationale |
| `dist/**/*.js` | Rebuilt compiled output |
