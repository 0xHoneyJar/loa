# Sprint Plan: Bridgebuilder v2.1 — Review Findings Polish

**Source**: PR #266 Bridgebuilder Review Comments (Sprint 1 Review + Bridgebuilder Persona Review)
**PRD Reference**: `grimoires/loa/prd-bridgebuilder-263.md`
**SDD Reference**: `grimoires/loa/sdd-bridgebuilder-263.md`
**Date**: 2026-02-09
**Branch**: `feature/bridgebuilder-v2.1`
**Team**: 1 AI engineer (Claude)

---

## Overview

PR #266 (Bridgebuilder v2) received a comprehensive review with 6 findings (F-1 through F-6) plus 1 dead code observation from the Sprint 1 review. Additionally, the closing review identified 4 v3 roadmap items, 2 of which are scoped as concrete improvements for this polish cycle.

### Fix Inventory (from PR #266 comments)

| Source | ID | Severity | Title | Sprint |
|--------|----|----------|-------|--------|
| Bridgebuilder F-3 | BB-F3 | Medium | String-based error classification → typed port errors | Sprint 1 |
| Bridgebuilder F-1 | BB-F1 | Medium | Token calibration logging (estimated vs actual) | Sprint 1 |
| Sprint 1 Review | S1-NOTE | Low | TIER2_FILENAMES dead code (unreachable due to SECURITY_PATTERNS priority) | Sprint 1 |
| Bridgebuilder F-5 | BB-F5 | Low | Rename `personaPath` → `repoOverridePath` for clarity | Sprint 1 |
| Bridgebuilder F-6 | BB-F6 | Info | Documentation alignment ("3→1→0" vs actual Level 2 starting at 1) | Sprint 1 |
| Bridgebuilder F-4 | BB-F4 | Low | Glob matching: use `path.matchesGlob()` (Node 22+) or add `**` support | Sprint 2 |
| Closing Note | V3-1 | Medium | Incremental review context (delta-only on PR updates) | Sprint 2 |
| Closing Note | V3-2 | Low | Multi-model persona routing (per-persona model selection) | Sprint 2 |

---

## Sprint 1: Core Quality & Naming Polish

**Goal**: Address the two Medium findings (typed errors, token calibration) plus quick cleanup items.
**Estimated tasks**: 5
**Files touched**: `truncation.ts`, `reviewer.ts`, `types.ts`, `main.ts`, `config.ts`, port interfaces

### Task 1.1: Typed Port Errors (BB-F3)

**Description**: Replace string-based error classification in `reviewer.ts:classifyError()` with typed error classes defined in port interfaces. Each port should declare its error vocabulary; adapters map internal errors to port error codes. The pipeline classifies by type, not message content.

**Files**:
- `resources/ports/git-provider.ts` — add `GitProviderError` type with codes: `RATE_LIMITED`, `NOT_FOUND`, `FORBIDDEN`, `NETWORK`
- `resources/ports/llm-provider.ts` — add `LLMProviderError` type with codes: `TOKEN_LIMIT`, `RATE_LIMITED`, `INVALID_REQUEST`, `NETWORK`
- `resources/core/reviewer.ts` — refactor `classifyError()` to check `instanceof` typed errors, keep string-matching as fallback for unknown errors
- `resources/core/types.ts` — move `ReviewError` source union to use port error codes
- `resources/adapters/` — wrap adapter errors in typed port error classes

**Acceptance Criteria**:
- [ ] `GitProviderError` type exported from git-provider port with `code` field
- [ ] `LLMProviderError` type exported from llm-provider port with `code` field
- [ ] `classifyError()` checks `instanceof` before falling back to string matching
- [ ] Token rejection detection (`isTokenRejection`) uses typed error `code === "TOKEN_LIMIT"` as primary check, string patterns as fallback
- [ ] All existing tests pass (string-matching fallback preserves backward compat)
- [ ] New tests: typed error classification for each port error code
- [ ] No behavior change for callers — same `ReviewError` output shape

**Dependencies**: None
**Estimated effort**: Medium

### Task 1.2: Token Calibration Logging (BB-F1)

**Description**: Add calibration logging that records estimated tokens vs actual tokens (from LLM API response) after each review. This enables coefficient tuning over time. Log to stderr as structured JSON for machine parsing.

**Files**:
- `resources/core/reviewer.ts` — after successful LLM call, log calibration data: `{ estimated, actual, ratio, model, level }`
- `resources/core/truncation.ts` — add `estimatePromptTokens()` helper that returns breakdown alongside total
- `resources/core/types.ts` — add `CalibrationEntry` type if needed

**Acceptance Criteria**:
- [ ] After each successful LLM call, log calibration entry to stderr via logger: `{ phase: "calibration", estimatedTokens, actualInputTokens, ratio, model, truncationLevel }`
- [ ] Ratio = actualInputTokens / estimatedTokens (shows if coefficient is accurate)
- [ ] Only logs when `response.inputTokens` is available (some providers may not return it)
- [ ] No behavior change — logging only, no coefficient auto-tuning yet
- [ ] Test: mock LLM response with inputTokens, verify calibration log emitted

**Dependencies**: None
**Estimated effort**: Small

### Task 1.3: Remove Dead TIER2_FILENAMES Code (S1-NOTE)

**Description**: The Sprint 1 review noted that `SECURITY.md` and `CODEOWNERS` both match `SECURITY_PATTERNS` before reaching `TIER2_FILENAMES` (line 192 of truncation.ts), making those filename overrides unreachable. Remove the dead code and update tests.

**Files**:
- `resources/core/truncation.ts` — remove `TIER2_FILENAMES` Set and the corresponding check in `classifyLoaFile()`

**Acceptance Criteria**:
- [ ] `TIER2_FILENAMES` constant removed from `truncation.ts`
- [ ] `classifyLoaFile()` no longer checks basename against TIER2_FILENAMES
- [ ] `SECURITY.md` still classified as `"exception"` (covered by SECURITY_PATTERNS)
- [ ] `CODEOWNERS` still classified as `"exception"` (covered by SECURITY_PATTERNS)
- [ ] All existing tests pass
- [ ] Comment added at `classifyLoaFile()` explaining that security patterns take priority: "SECURITY.md and CODEOWNERS match SECURITY_PATTERNS above — no separate filename check needed"

**Dependencies**: None
**Estimated effort**: Small

### Task 1.4: Rename personaPath → repoOverridePath (BB-F5)

**Description**: Rename `BridgebuilderConfig.personaPath` to `repoOverridePath` to eliminate naming confusion with `YamlConfig.persona_path` (which maps to `personaFilePath`). This is a pure clarity rename — no behavior change.

**Files**:
- `resources/core/types.ts` — rename field in `BridgebuilderConfig`
- `resources/config.ts` — update DEFAULTS and resolveConfig references
- `resources/main.ts` — update loadPersona references
- `resources/__tests__/config.test.ts` — update test references
- `resources/__tests__/persona.test.ts` — update test references

**Acceptance Criteria**:
- [ ] `BridgebuilderConfig.personaPath` renamed to `repoOverridePath`
- [ ] DEFAULTS constant updated
- [ ] `resolveConfig()` maps correctly (persona_path YAML still maps to `personaFilePath` for custom paths, `review_marker` default still goes to `repoOverridePath`)
- [ ] `loadPersona()` reads from `config.repoOverridePath`
- [ ] All 269 existing tests pass
- [ ] No behavior change — pure rename

**Dependencies**: None
**Estimated effort**: Small

### Task 1.5: Documentation Alignment (BB-F6)

**Description**: The PR description and comments reference "3→1→0" context reduction, but Level 2 in code starts at context=1 (not 3). Context=3 is the default git diff format used by Level 1 (full patches). Add inline documentation clarifying this.

**Files**:
- `resources/core/truncation.ts` — add comment at progressive truncation Level 2 section explaining the context=3 is implicit in Level 1's full patch

**Acceptance Criteria**:
- [ ] Comment at `progressiveTruncate()` Level 2 section (around line 585) explaining: "Level 1 uses full patches which include default git context (3 lines). Level 2 reduces: context=1, then context=0. The '3→1→0' reduction spans Level 1→Level 2."
- [ ] No code changes — documentation only
- [ ] Comment at LEVEL_DISCLAIMERS explaining the relationship between levels and context

**Dependencies**: None
**Estimated effort**: Trivial

---

## Sprint 2: Glob Upgrade & New Capabilities

**Goal**: Upgrade glob matching for Node 22+ and implement two high-value v3 features from the roadmap.
**Estimated tasks**: 3
**Files touched**: `truncation.ts`, `reviewer.ts`, `template.ts`, `types.ts`, `config.ts`, context module

### Task 2.1: Enhanced Glob Matching (BB-F4)

**Description**: Upgrade `matchesExcludePattern()` in `truncation.ts` to support `**` recursive glob matching. Use `path.matchesGlob()` (Node 22+, available since Node 22.5.0) when available, falling back to the existing simplified implementation. This maintains zero-dep while gaining proper glob support on modern runtimes.

**Files**:
- `resources/core/truncation.ts` — upgrade `matchesExcludePattern()` with `path.matchesGlob()` detection and fallback
- `resources/__tests__/loa-detection.test.ts` — add tests for `**` patterns

**Acceptance Criteria**:
- [ ] `matchesExcludePattern()` uses `path.matchesGlob()` when available (typeof check)
- [ ] Falls back to current simplified matching on Node <22
- [ ] Supports `**` recursive patterns: `src/**/*.test.ts` matches `src/core/utils.test.ts`
- [ ] Supports `?` single character wildcards
- [ ] Existing patterns (`*.md`, `src/*`, `src/*.test.ts`) continue working identically
- [ ] No new dependencies
- [ ] Tests: recursive patterns, fallback behavior, character wildcards

**Dependencies**: None
**Estimated effort**: Medium

### Task 2.2: Incremental Review Context (V3-1)

**Description**: When a PR updates after an initial review, only review the delta (new commits since last review). The `BridgebuilderContext` already tracks a `hash` per PR (based on headSha + sorted filenames). Extend it to persist the reviewed-at SHA and, on subsequent runs, filter the diff to only include files changed since that SHA.

**Files**:
- `resources/core/types.ts` — add `lastReviewedSha` to persisted context
- `resources/core/context.ts` — persist reviewed SHA on finalize, expose `getLastReviewedSha()`
- `resources/core/template.ts` — when incremental context available, add banner: `[Incremental: reviewing changes since <sha>]`
- `resources/core/reviewer.ts` — pass incremental context to template when available
- `resources/ports/git-provider.ts` — add `getCommitDiff(owner, repo, base, head)` to port interface
- `resources/adapters/` — implement `getCommitDiff` using `gh api repos/{owner}/{repo}/compare/{base}...{head}`

**Acceptance Criteria**:
- [ ] On first review of a PR, behavior unchanged (full diff review)
- [ ] On subsequent review of same PR (headSha changed), review only delta since last reviewed SHA
- [ ] `lastReviewedSha` persisted in context store alongside existing hash
- [ ] Banner in prompt: `[Incremental: reviewing N files changed since <short-sha>]`
- [ ] If incremental diff fails (e.g., force push), fall back to full review with warning
- [ ] `--force-full-review` CLI flag to bypass incremental mode
- [ ] Tests: incremental detection, delta filtering, fallback on force push, CLI override

**Dependencies**: Task 2.1 (not strictly, but sequential for clean diffs)
**Estimated effort**: Large

### Task 2.3: Multi-Model Persona Routing (V3-2)

**Description**: Extend persona packs to optionally specify a preferred model. The `TOKEN_BUDGETS` table already supports per-model coefficients. Add a `model` frontmatter field to persona .md files. When set, it overrides the configured model for that review. CLI `--model` flag still wins (consistent with CLI-wins precedence).

**Files**:
- `resources/personas/*.md` — add optional YAML frontmatter with `model` field
- `resources/main.ts` — parse frontmatter from persona content, apply model override
- `resources/core/types.ts` — add `personaModel` field to config
- `resources/config.ts` — integrate persona model into precedence: CLI --model > persona model > env > yaml > default

**Acceptance Criteria**:
- [ ] Persona files can include optional YAML frontmatter: `---\nmodel: claude-opus-4-6\n---`
- [ ] When persona specifies model and no CLI `--model` override, use persona's model
- [ ] CLI `--model` always wins over persona model (consistent precedence)
- [ ] Default personas ship without model override (no behavior change)
- [ ] `security` persona gets suggested model in comment (not default — user opt-in): `# model: claude-opus-4-6  # Uncomment for deeper reasoning`
- [ ] `quick` persona gets suggested model in comment: `# model: claude-haiku-4-5  # Uncomment for speed`
- [ ] Logging shows model source: `persona:security` when persona model active
- [ ] Token budget automatically adjusts to persona's model (uses `getTokenBudget()`)
- [ ] Tests: frontmatter parsing, model override, CLI precedence, no-frontmatter passthrough

**Dependencies**: None
**Estimated effort**: Medium

---

## Summary

| Sprint | Tasks | Severity Coverage | Estimated Effort |
|--------|-------|-------------------|-----------------|
| Sprint 1 | 5 tasks (1.1–1.5) | 2 Medium, 2 Low, 1 Info | Medium |
| Sprint 2 | 3 tasks (2.1–2.3) | 1 Low, 1 Medium (feature), 1 Low (feature) | Large |

### Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Typed errors break adapter contract | Low | Medium | String-matching fallback preserves backward compat |
| Node 22 detection false positive | Low | Low | typeof check + fallback |
| Incremental diff miss on force push | Medium | Medium | SHA comparison + full-review fallback |
| Persona frontmatter parsing edge cases | Low | Low | Missing/malformed frontmatter → ignore, use config model |

### Out of Scope

| Item | Reason |
|------|--------|
| Token coefficient auto-tuning | Requires production data collection first (Task 1.2 is the prerequisite) |
| GitLab/Bitbucket adapters | Separate architecture decision |
| AST-aware diff analysis | Major feature, needs own PRD |
| PR auto-approval | Security risk, explicitly forbidden |
