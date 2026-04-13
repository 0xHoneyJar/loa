# Sprint Plan: Multi-Model Bridgebuilder Review

**PRD**: grimoires/loa/prd.md (v1.1)
**SDD**: grimoires/loa/sdd.md
**Date**: 2026-04-13
**Sprints**: 4 (Global IDs: 103-106)
**Total Tasks**: 29 + 1 E2E validation

---

## Sprint 1: Foundation — Config Extension, Adapter Interface, Factory

**Global ID**: 103
**Scope**: MEDIUM (6 tasks)
**FRs**: FR-1 (partial), FR-6
**Goal**: Establish the multi-model configuration system and adapter factory so provider implementations can be built on a validated foundation.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T1.1 | Extend `ReviewResponse` with optional `provider?`, `latencyMs?`, `estimatedCostUsd?`, `errorState?` fields. Extend `LLMProviderErrorCode` with `TIMEOUT`, `AUTH_ERROR`, `PROVIDER_ERROR` | `ports/llm-provider.ts` | FR-1 | G-3 |
| T1.2 | Add `postComment(owner, repo, prNumber, body): Promise<boolean>` to `IReviewPoster` interface | `ports/review-poster.ts` | FR-2 | G-2 |
| T1.3 | Add `MultiModelConfig` type and `MultiModelConfigSchema` zod validation schema | `core/types.ts`, `config.ts` | FR-6 | G-3 |
| T1.4 | Implement `loadMultiModelConfig()` using `yq` CLI extraction with yq availability check, integrate into `resolveConfig()` | `config.ts` | FR-6 | G-3 |
| T1.5 | Create `AdapterFactory` with `createAdapter(config): ILLMProvider` dispatching to anthropic/openai/google | `adapters/adapter-factory.ts` (new) | FR-1 | G-2, G-3 |
| T1.6 | Tests: config parsing (various YAML inputs, defaults, yq missing), adapter factory dispatch | `__tests__/config.test.ts`, `__tests__/adapter-factory.test.ts` | FR-1, FR-6 | G-3 |

### Acceptance Criteria
- [ ] `multi_model.enabled: false` produces identical behavior
- [ ] Config loading validates all nested fields with sensible defaults
- [ ] Clear error if yq missing when multi_model config detected
- [ ] API key validation respects graceful/strict mode
- [ ] All existing tests pass unchanged

---

## Sprint 2: Provider Adapters + Depth Enhancement

**Global ID**: 104
**Scope**: LARGE (9 tasks)
**FRs**: FR-1 (completion), FR-3, FR-7, FR-8
**Goal**: Implement OpenAI and Google adapters following the Anthropic SSE streaming pattern, and enhance review prompts with Permission to Question, FAANG parallels, lore weaving, and structural depth validation.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T2.1 | Create OpenAI adapter: SSE streaming `/v1/chat/completions`, system prompt in `messages[0]`, backoff (1s->2s->4s), 2 retries, timeout | `adapters/openai.ts` (new) | FR-1 | G-2 |
| T2.2 | Create Google adapter: SSE streaming `/v1beta/models/{model}:streamGenerateContent`, `systemInstruction.parts[0].text`, backoff, 2 retries | `adapters/google.ts` (new) | FR-1 | G-2 |
| T2.3 | Enhance `buildSystemPrompt()`: "Permission to Question the Question" directive (Condition 3), depth expectations (FAANG, metaphors, tech history, revenue, social/business, cross-repo) | `core/template.ts` | FR-3, FR-8 | G-1, G-4 |
| T2.4 | Lore integration: include lore entries in system prompt, weave naturally, use `short` for inline naming, `context` for deeper framing | `core/template.ts` | FR-7 | G-1, G-4 |
| T2.5 | Create depth checker: 8 boolean elements, pattern matching, configurable min threshold (default 5), JSONL logging | `core/depth-checker.ts` (new) | FR-3 | G-1, G-4 |
| T2.6 | Context window heterogeneity: truncation priority (persona > lore > cross-repo > diff), per-provider logging | `core/template.ts` | FR-3 | G-1 |
| T2.7 | OpenAI adapter tests: mock HTTP, SSE parsing, retry on 429/5xx, timeout | `__tests__/openai.test.ts` (new) | FR-1 | G-3 |
| T2.8 | Google adapter tests: mock HTTP, SSE Google format, system prompt handling, retry | `__tests__/google.test.ts` (new) | FR-1 | G-3 |
| T2.9 | Depth checker tests: pattern detection for 8 elements, min threshold, edge cases | `__tests__/depth-checker.test.ts` (new) | FR-3 | G-1, G-3 |

### Acceptance Criteria
- [ ] Each adapter produces valid ReviewResponse from mock API responses
- [ ] Per-provider system prompt placement: Anthropic `system`, OpenAI `messages[0]`, Google `systemInstruction`
- [ ] Depth checker detects >= 6/8 elements in a rich review sample
- [ ] Enhanced prompts apply to both single-model and multi-model modes
- [ ] Each adapter's `estimatedCostUsd` computed from configurable rates

**Dependencies**: Sprint 1

---

## Sprint 3: Multi-Model Pipeline + Consensus

**Global ID**: 105
**Scope**: LARGE (8 tasks)
**FRs**: FR-2, FR-4, FR-9, FR-10
**Goal**: Orchestrate N parallel model reviews with dual-track consensus, cross-repo context, and iteration strategy routing.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T3.1 | Create `MultiModelPipeline`: parallel execution via `Promise.allSettled()`, per-model two-pass, graceful/strict failure handling, concurrency limiting (default 3) | `core/multi-model-pipeline.ts` (new) | FR-2 | G-2 |
| T3.2 | Create `BridgebuilderScorer`: dual-track — Track 1 (convergence: HIGH_CONSENSUS/DISPUTED/LOW_VALUE/BLOCKER), Track 2 (diversity: dedup via Levenshtein, preserve unique perspectives) | `core/scoring.ts` (new) | FR-4 | G-2 |
| T3.3 | Create `CrossScorer`: pairwise fan-out N*(N-1) calls, bounded 4K output, 1 retry with 2x backoff, graceful fallback to no-consensus | `core/cross-scorer.ts` (new) | FR-4 | G-2 |
| T3.4 | Create `CrossRepoContext`: auto-detect GitHub refs from PR/commits, fetch via `gh` CLI (5s/ref, 30s total), manual refs from config, skip inaccessible with warning | `core/cross-repo.ts` (new) | FR-9 | G-1 |
| T3.5 | Extend GitHub CLI adapter: `postComment()` with 65K char splitting, continuation headers (`[1/4]`), sequential posting for ordering | `adapters/github-cli.ts` | FR-2 | G-2, G-4 |
| T3.6 | Modify bridge orchestrator: read `iteration_strategy` via yq, add `is_multi_model_iteration()` function, emit `SIGNAL:BRIDGEBUILDER_REVIEW_MULTI:$iteration` | `bridge-orchestrator.sh` | FR-10 | G-2 |
| T3.7 | Pipeline integration tests: mock adapters, parallel execution, scoring, comment ordering, graceful degradation, strict failure, feature-off parity | `__tests__/multi-model.test.ts` (new) | FR-2 | G-2, G-3 |
| T3.8 | Scoring tests: consensus math matches scoring-engine.sh for same inputs, dual-track classification, threshold configurability | `__tests__/scoring.test.ts` (new) | FR-4 | G-2 |

### Acceptance Criteria
- [ ] 3-model parallel review completes with all models posting separate comments
- [ ] Comments posted sequentially with `[1/4]` numbering
- [ ] Consensus summary correctly classifies findings with model attribution
- [ ] Dual-track: convergence for code findings, diversity for educational depth
- [ ] Cross-repo context adds references from linked issues
- [ ] `enabled: false` produces identical output to current pipeline
- [ ] Concurrency limited to `Math.min(models.length, 3)`

**Dependencies**: Sprint 2

---

## Sprint 4: Integration, Rating, Progress, E2E Validation

**Global ID**: 106
**Scope**: MEDIUM (6 tasks + E2E)
**FRs**: FR-5, FR-11, E2E all FRs
**Goal**: Complete the feedback loop with human rating, progress visibility, main.ts wiring, and end-to-end validation.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T4.1 | Create rating system: `RatingEntry` interface, JSONL storage in `grimoires/loa/ratings/`, per-iteration 1-5 prompt, configurable timeout, non-blocking, rubric per SKP-006 | `core/rating.ts` (new) | FR-5 | G-1 |
| T4.2 | Create progress reporter: stderr output, per-phase + per-model activity, configurable verbosity, no gaps > 30s | `core/progress.ts` (new) | FR-11 | G-1, G-4 |
| T4.3 | Wire `main.ts`: load multi-model config, validate API keys, route to MultiModelPipeline or ReviewPipeline based on `enabled` flag | `main.ts` | FR-2 | G-2, G-3 |
| T4.4 | Token budget enforcement: pre-flight input estimation, progressive truncation, runtime cumulative check | `core/multi-model-pipeline.ts` | FR-6 | G-1 |
| T4.5 | Update `createLocalAdapters()` for multiple providers via adapter factory when multi-model enabled, single-adapter path when disabled | `adapters/index.ts` | FR-1 | G-3 |
| T4.6 | Tests: rating storage/retrieval/timeout, progress formatting/verbosity | `__tests__/rating.test.ts`, `__tests__/progress.test.ts` (new) | FR-5, FR-11 | G-1, G-3 |

### E2E Goal Validation

| Goal | Validation | Expected Result |
|------|-----------|-----------------|
| G-1 | Run multi-model review, check depth checklist, capture rating | Depth >= 5/8 elements; rating prompt appears |
| G-2 | Run 3-model review, verify consensus summary | HIGH_CONSENSUS present; model attribution correct |
| G-3 | Run full test suite with `enabled: false` | All existing tests pass; output identical |
| G-4 | Verify metaphors, FAANG parallels, business insights in output | Structural depth checklist pass |

### Acceptance Criteria
- [ ] Rating prompt appears after review with timeout
- [ ] Rating never blocks autonomous execution
- [ ] Progress updates every <= 30s with model activity details
- [ ] `main.ts` correctly routes based on config
- [ ] Token budget enforcement works when configured
- [ ] All 11 FRs pass acceptance criteria
- [ ] All 4 PRD goals validated

**Dependencies**: Sprint 3

---

## PRD Goal Mapping

| Goal | Contributing Tasks | Validation |
|------|-------------------|------------|
| G-1: Review depth parity | T2.3, T2.4, T2.5, T2.6, T3.4, T4.1, T4.2, T4.4 | E2E |
| G-2: Multi-model confidence | T1.2, T1.5, T2.1, T2.2, T3.1-T3.8, T4.3 | E2E |
| G-3: Zero regression | T1.1, T1.3, T1.4, T1.6, T2.7-T2.9, T3.7, T4.3, T4.5 | E2E |
| G-4: Stakeholder accessibility | T2.3, T2.4, T2.5, T3.5, T4.2 | E2E |

---

## Risk Register

| Risk | Sprint | Probability | Impact | Mitigation |
|------|--------|-------------|--------|------------|
| OpenAI/Google API format differences | 2 | Medium | Medium | Per-provider adapter tests with mock responses |
| Cross-scoring latency | 3 | Medium | Medium | Bounded output (4K), 1 retry, fallback to no-consensus |
| CI runner OOM from parallel reviews | 3 | Low | High | Concurrency limit (default 3), configurable |
| Scoring math divergence from scoring-engine.sh | 3 | Medium | Medium | Validate TS port against shell output for identical inputs |
| yq dependency availability | 1 | Medium | Medium | Clear error + fallback to single-model |
| GitHub comment rate limiting | 3 | Low | Medium | Sequential posting with backoff |

---

## Assumptions

1. Cycle-048 authorizes System Zone writes to `.claude/skills/bridgebuilder-review/resources/`
2. `zod` dependency available in Bridgebuilder build chain (confirmed: `schemas.ts` imports `"zod/v4"`)
3. `yq` CLI available in dev and CI environments

---

*4 sprints, 29 tasks + E2E, all 11 FRs covered, all 4 PRD goals mapped*
