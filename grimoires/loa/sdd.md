# SDD: Multi-Model Bridgebuilder Review

**PRD**: grimoires/loa/prd.md (v1.1)
**Date**: 2026-04-13
**Status**: Draft

---

## 1. Architecture Overview

### 1.1 Current Architecture

Bridgebuilder follows hexagonal (ports and adapters) architecture:

```
                    ┌─────────────┐
                    │   main.ts   │ (composition root)
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         ┌─────────┐ ┌──────────┐ ┌──────────┐
         │  Ports   │ │   Core   │ │ Adapters │
         │(interfaces)│ │(business) │(implementations)│
         └─────────┘ └──────────┘ └──────────┘
```

**Ports** (interfaces in `resources/ports/`):
- `ILLMProvider` — `generateReview(request) -> ReviewResponse` (`llm-provider.ts:28-29`)
- `IReviewPoster` — `postReview(input) -> boolean` (`review-poster.ts:12-19`)
- `IGitProvider`, `IOutputSanitizer`, `IHasher`, `ILogger`, `IContextStore`

**Core** (business logic in `resources/core/`):
- `ReviewPipeline` — orchestrates single/two-pass review (`reviewer.ts`, 1040+ lines)
- `PRReviewTemplate` — builds system/user prompts (`template.ts`)
- `FindingSchema` / `FindingsBlockSchema` — zod validation (`schemas.ts`)
- `BridgebuilderConfig` — 5-level config resolution (`config.ts`)

**Adapters** (implementations in `resources/adapters/`):
- `AnthropicAdapter` — HTTP POST + SSE streaming, 120-300s tiered timeout, retry with exponential backoff (`anthropic.ts`, 223 lines)
- `GitHubCLIAdapter` — implements both `IGitProvider` and `IReviewPoster` via `gh` CLI
- `PatternSanitizer`, `NodeHasher`, `ConsoleLogger`, `NoOpContextStore`

**Composition root** (`adapters/index.ts:27-57`):
- `createLocalAdapters(config, anthropicApiKey) -> LocalAdapters` — wires all ports to concrete adapters

### 1.2 Target Architecture

The multi-model extension preserves the hexagonal architecture, adding:
- New adapter implementations (OpenAI, Google) behind the existing `ILLMProvider` port
- A new `MultiModelPipeline` that orchestrates N parallel `ReviewPipeline` instances
- A Bridgebuilder-specific scoring module for consensus
- Extended `IReviewPoster` with comment posting (separate from review posting)

```
                        ┌──────────────┐
                        │    main.ts   │
                        └──────┬───────┘
                               │
                    ┌──────────┴──────────┐
                    ▼                     ▼
          ┌─────────────────┐   ┌────────────────┐
          │ ReviewPipeline  │   │ MultiModelPipeline│ (NEW)
          │ (single-model)  │   │ (N-model parallel)│
          └────────┬────────┘   └────────┬─────────┘
                   │                     │
                   │            ┌────────┴────────┐
                   │            ▼        ▼        ▼
                   │     ┌──────────┐ ┌──────┐ ┌──────┐
                   │     │ReviewPipe│ │Review│ │Review│
                   │     │(Anthropic)│ │(OpenAI)│(Google)│
                   │     └──────────┘ └──────┘ └──────┘
                   │                     │
                   │            ┌────────┴────────┐
                   │            ▼                  ▼
                   │     ┌──────────────┐  ┌────────────┐
                   │     │BridgeScorer  │  │CommentPoster│
                   │     │(consensus)   │  │(per-model)  │
                   │     └──────────────┘  └────────────┘
                   │                     │
                   ▼                     ▼
          ┌─────────────────────────────────────┐
          │        IReviewPoster (extended)      │
          └─────────────────────────────────────┘
```

**Routing logic** in `main.ts`:
```
IF multi_model.enabled AND iteration matches strategy:
  → MultiModelPipeline (N models in parallel + consensus)
ELSE:
  → ReviewPipeline (existing single-model, unchanged)
```

---

## 2. Component Design

### 2.1 Provider Adapter Interface (FR-1)

**Extending the existing `ILLMProvider` port** (`ports/llm-provider.ts`):

```typescript
// Extended ReviewResponse — backward compatible
// (existing fields preserved, new fields optional)
export interface ReviewResponse {
  content: string;
  inputTokens: number;
  outputTokens: number;
  model: string;
  // NEW: multi-model fields [IMP-003]
  provider?: string;          // "anthropic" | "openai" | "google"
  latencyMs?: number;         // wall-clock time
  estimatedCostUsd?: number;  // per IMP-001 telemetry
  errorState?: LLMProviderErrorCode | null;
}

// Extended error codes [IMP-006]
export type LLMProviderErrorCode =
  | "TOKEN_LIMIT"
  | "RATE_LIMITED"
  | "INVALID_REQUEST"
  | "NETWORK"
  | "TIMEOUT"        // NEW
  | "AUTH_ERROR"     // NEW
  | "PROVIDER_ERROR"; // NEW
```

The `ILLMProvider` interface (`generateReview(request) -> ReviewResponse`) remains unchanged — new adapters implement the same contract.

**New adapters:**

| File | Provider | Auth | Endpoint | Streaming |
|------|----------|------|----------|-----------|
| `adapters/openai.ts` | OpenAI | `Authorization: Bearer {OPENAI_API_KEY}` | `/v1/chat/completions` (stream) | SSE `data:` lines |
| `adapters/google.ts` | Google | `x-goog-api-key: {GOOGLE_API_KEY}` | `/v1beta/models/{model}:streamGenerateContent` | SSE `data:` lines |

Each adapter follows the `AnthropicAdapter` pattern (`adapters/anthropic.ts`):
- SSE streaming to avoid TTFB timeout
- Exponential backoff: 1s → 2s → 4s, ceiling 60s
- Max 2 retries
- Provider-specific response normalization to `ReviewResponse`
- [IMP-009] **Per-provider system prompt handling**: Each adapter manages system prompt placement according to the provider's API contract. Anthropic: `system` field. OpenAI: `messages[0].role = "system"`. Google: `systemInstruction.parts[0].text` (separate from content). The `ReviewRequest` interface provides `systemPrompt` and `userPrompt` as separate strings — each adapter maps these to its provider's format without duplication.

**Adapter Factory** (`adapters/adapter-factory.ts`, new file):

```typescript
export interface AdapterConfig {
  provider: string;
  modelId: string;
  apiKey: string;
  timeoutMs?: number;
}

export function createAdapter(config: AdapterConfig): ILLMProvider {
  switch (config.provider) {
    case "anthropic": return new AnthropicAdapter(config.apiKey, config.modelId, config.timeoutMs ?? 120_000);
    case "openai":    return new OpenAIAdapter(config.apiKey, config.modelId, config.timeoutMs ?? 120_000);
    case "google":    return new GoogleAdapter(config.apiKey, config.modelId, config.timeoutMs ?? 120_000);
    default: throw new Error(`Unknown provider: ${config.provider}. Available: anthropic, openai, google`);
  }
}
```

The factory is the extension point for future providers (FR-1 extensibility requirement).

### 2.2 Multi-Model Pipeline (FR-2)

**New file: `core/multi-model-pipeline.ts`**

Orchestrates N parallel review pipelines with consensus:

```typescript
export interface MultiModelReviewResult {
  modelResults: Array<{
    provider: string;
    modelId: string;
    result: ReviewResult;
    findings: ValidatedFinding[];
    posted: boolean;
  }>;
  consensus: ConsensusResult;
  totalLatencyMs: number;
  telemetry: Array<{ provider: string; inputTokens: number; outputTokens: number; latencyMs: number; estimatedCostUsd: number }>;
}
```

**Execution flow:**

1. **Parallel reviews**: `Promise.allSettled()` across all configured adapters. Each model runs its own two-pass (convergence + enrichment) via a separate `ReviewPipeline` instance.

2. **Per-model comment posting**: Each completed review posted **sequentially** (not parallel) as a separate GitHub comment via the extended `IReviewPoster.postComment()` method. Comments prefixed with numbered model identity: `## [1/4] Bridgebuilder Review — Claude Opus 4.6`, `## [2/4] Bridgebuilder Review — Codex 5.2`, etc. Sequential posting guarantees ordering on the PR thread.

3. **Cross-scoring**: Completed reviews fed into `BridgebuilderScorer` for consensus.

4. **Consensus summary**: Final comment posted with model attribution and agreement patterns.

**Failure handling** (respects `api_key_mode` config):
- `graceful` (default): `Promise.allSettled()` allows partial failures. Failed models logged, available models posted. Consensus computed on available results. Minimum 1 model required.
- `strict`: Any model failure halts the pipeline.

**GitHub comment size** [IMP-004]: Reviews exceeding 65,536 characters split into continuation comments: `## Bridgebuilder Review — Codex 5.2 (Part 1/2)`.

### 2.3 Review Depth Enhancement (FR-3, FR-7, FR-8)

**Modifying `template.ts`** — two new prompt components:

**a) Enhanced enrichment system prompt** (extends `buildSystemPrompt()` at `template.ts:390`):

When depth enhancement is enabled, the system prompt includes:

```
## Condition 3: Permission to Question the Question

You have explicit permission to question the frame of this work.
Do not limit yourself to "are there bugs?" — ask "what is being
built here, and does the architecture serve that purpose?"

You may:
- Question whether the problem is correctly framed
- Propose REFRAME findings that challenge assumptions
- Connect this work to broader patterns in tech history
- Surface revenue/business model implications
- Reference related work across the ecosystem

## Depth Expectations

Your review should include:
- FAANG parallels: Connect decisions to patterns at Google, Netflix, Stripe, etc.
- Metaphors/analogies: Make architectural concepts tangible
- Tech/corporate history: Cambrian explosions, blue-chip open source moments
- Revenue/business model parallels: How technical choices enable business models
- Social/business dimension: Community, team, user impact
- Cross-repo awareness: Reference concurrent work (issues, PRs from context)

## Lore Integration

The following lore entries provide naming etymology and philosophical context.
Weave them naturally into your narrative where relevant — do not force connections.

{lore_entries}
```

**b) Structural depth checklist** (`core/depth-checker.ts`, new file):

```typescript
export interface DepthCheckResult {
  passed: boolean;
  score: number;           // 0-8 (number of elements present)
  minRequired: number;     // from config (default 5)
  elements: {
    faang_parallels: boolean;
    metaphors: boolean;
    frame_questioning: boolean;
    cross_repo_refs: boolean;
    tech_history: boolean;
    social_business: boolean;
    revenue_parallels: boolean;
    concurrent_work: boolean;
  };
}
```

Detection uses pattern matching on review content (e.g., regex for company names, "similar to when...", issue/PR references, "business model", "revenue"). Logged per review to `grimoires/loa/ratings/depth-checks.jsonl`.

**c) Context window heterogeneity** [IMP-010]:

When providers have different context limits, truncation priority (highest to lowest):
1. Persona + "Permission to Question" directive (never truncated)
2. Lore entries (truncated last)
3. Cross-repo context summaries
4. PR diff (truncated first — existing progressive truncation from `truncation.ts`)

Truncation decisions logged per provider.

### 2.4 Consensus & Cross-Scoring (FR-4)

**New file: `core/scoring.ts`**

The scoring module is TypeScript (per [IMP-005]), not shell. The consensus math is extracted from `scoring-engine.sh` and reimplemented in TypeScript for type safety and testability.

```typescript
export interface ConsensusResult {
  highConsensus: ScoredFinding[];   // all models agree, score > threshold
  disputed: ScoredFinding[];        // delta > threshold
  lowValue: ScoredFinding[];        // all models score low
  blockers: ScoredFinding[];        // critical concern flagged
  modelAgreementPercent: number;
  summary: string;                  // human-readable summary for GitHub comment
}

export interface ScoredFinding {
  id: string;
  description: string;
  scores: Array<{ provider: string; modelId: string; score: number }>;
  averageScore: number;
  delta: number;
  agreement: "HIGH" | "DISPUTED" | "LOW";
  originModel: string;             // which model first identified this
  confirmedBy: string[];           // which models confirmed
}
```

**Dual-Track Consensus** [IMP-002, reframe-1]:

The scoring module uses two distinct tracks, recognizing that code findings and educational depth serve different purposes:

**Track 1 — Convergence (Code Findings)**:
Cross-scoring with adversarial consensus. Applies to: CRITICAL, HIGH, MEDIUM, LOW, BLOCKER severity findings.

1. **Normalization**: Each model's findings parsed via `FindingsBlockSchema` (`schemas.ts:41-44`). Findings deduplicated by file + category + description similarity (cosine similarity on description text, threshold 0.8).
2. **Fan-out pattern**: Pairwise — each model scores each other model's code findings. For 3 models: 6 scoring calls.
3. **Aggregation**: Pairwise scores averaged per finding to produce global consensus score. Thresholds from config (default: `high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700`).

**Track 2 — Diversity (Educational Depth)**:
Aggregation without scoring. Applies to: PRAISE, SPECULATION, REFRAME, VISION severity findings, and enrichment fields (faang_parallel, metaphor, teachable_moment, connection, revenue/business parallels).

1. **Collection**: All unique depth elements and educational findings gathered from all models.
2. **Deduplication**: Semantically similar insights merged (same concept, different wording), but genuinely different perspectives preserved. [IMP-001] Similarity measured via normalized Levenshtein distance on lowercased descriptions (threshold 0.8) — no external embedding dependency. Tokenized bag-of-words cosine as optional upgrade path.
3. **Presentation**: All unique perspectives included in the consensus summary — celebrating diversity rather than homogenizing through scoring.

**[IMP-002] Concurrency limits**: Parallel review fan-out defaults to `Math.min(models.length, 3)` concurrent requests. Configurable via `multi_model.max_concurrency` (default: 3). Prevents memory/connection exhaustion in CI runners.

**[IMP-003] Cross-scoring failure handling**: Cross-scoring is a separate failure domain from review generation. If cross-scoring fails (timeout, rate limit): fall back to "no consensus" — post individual reviews without consensus summary, log the failure. Cross-scoring retries: 1 retry with 2x backoff, then fail gracefully.

**[IMP-005] Token budget enforcement**: When `token_budget.per_model` or `token_budget.total` is set (non-null):
- **Pre-flight**: Estimate input tokens per model based on prompt + diff + context size. If estimate exceeds per_model budget, apply progressive truncation (diff → cross-repo → lore).
- **Runtime**: After each model completes, check cumulative tokens against total budget. If exceeded, skip remaining models and proceed to consensus with available results.
- **Default (null)**: No enforcement — provider context limits are the only ceiling.

This dual-track design recognizes that cross-scoring a Netflix parallel against a Stripe parallel destroys the diversity being sought. Code bugs need consensus; educational insights need collection.

### 2.5 Cross-Repo Context Sourcing (FR-9)

**New file: `core/cross-repo.ts`**

```typescript
export interface CrossRepoContext {
  autoDetected: CrossRepoRef[];
  manualRefs: CrossRepoRef[];
  summaries: Array<{ ref: CrossRepoRef; title: string; summary: string }>;
}

export interface CrossRepoRef {
  type: "issue" | "pr" | "discussion";
  owner: string;
  repo: string;
  number: number;
  source: "auto" | "manual";
}
```

**Auto-detection**: Parse PR description and commit messages for GitHub reference patterns:
- `owner/repo#123`
- `https://github.com/owner/repo/issues/123`
- `https://github.com/owner/repo/pull/123`

**Fetching**: Via `gh` CLI — `gh issue view` / `gh pr view` for titles and body excerpts. Timeout per ref (5s), total timeout (30s). Inaccessible refs skipped with warning.

**Manual config**: `multi_model.cross_repo.manual_refs[]` in `.loa.config.yaml`.

### 2.6 Human Rating Feedback Loop (FR-5)

**New file: `core/rating.ts`**

```typescript
export interface RatingEntry {
  timestamp: string;       // ISO 8601
  iteration: number;
  bridgeRunId: string;
  modelsUsed: string[];    // ["claude-opus-4-6", "codex-5.2", "gemini-2.5-pro"]
  multiModel: boolean;
  rating: number | null;   // 1-5, null if timeout
  freeText?: string;
  timeout: boolean;
  depthCheck: DepthCheckResult;
}
```

**Storage**: `grimoires/loa/ratings/review-ratings.jsonl` (state zone, JSONL pattern).

**Rating rubric** [SKP-006]:
- **1**: No depth — findings only, no educational content
- **2**: Some context — basic observations beyond code
- **3**: Adequate — some FAANG parallels or metaphors present
- **4**: Rich — educational content with FAANG/business parallels, frame-questioning
- **5**: Exceptional — matches best manual reviews, full milieu context

**Non-blocking**: Rating prompt displayed via stdout. Configurable timeout (default 60s). On timeout, entry logged with `rating: null, timeout: true`. Autonomous execution never blocked.

**[speculation-1] Model profiling schema**: Rating entries include `modelsUsed` and `depthCheck` results. Consensus entries include `originModel` and `confirmedBy` per finding. This data supports future model strength profiling: after 20+ cycles, analysis can reveal which models excel at security detection, educational depth, architectural alternatives, etc. Schema is designed for this future use without requiring current implementation of profiling logic.

**Retrospective command**: Optional end-of-cycle rating via CLI argument.

### 2.7 Configuration Extension (FR-6)

**Extending `config.ts`** — the existing YAML parser (`loadYamlConfig()` at `config.ts:185`) uses regex-based parsing that handles flat key-value pairs. The nested `multi_model` config requires a different approach.

**Design decision**: Use `yq` CLI extraction for the nested `multi_model` block (consistent with `scoring-engine.sh` and `bridge-orchestrator.sh` patterns), then pass the JSON output to zod validation.

**[high-1] yq availability check**: At startup, when `multi_model` config is detected in the YAML file (via simple grep), validate that `yq` is available on PATH. If missing, emit a clear error: `"Multi-model config detected but yq is not installed. Install with: brew install yq (macOS) or snap install yq (Linux)"` and fall back to single-model mode rather than silently disabling.

```typescript
// New zod schema for multi_model config
export const MultiModelConfigSchema = z.object({
  enabled: z.boolean().default(false),
  models: z.array(z.object({
    provider: z.string(),
    model_id: z.string(),
    role: z.enum(["primary", "reviewer"]).default("reviewer"),
  })).default([]),
  iteration_strategy: z.union([
    z.enum(["every", "final"]),
    z.array(z.number()),
  ]).default("final"),
  api_key_mode: z.enum(["graceful", "strict"]).default("graceful"),
  consensus: z.object({
    enabled: z.boolean().default(true),
    scoring_thresholds: z.object({
      high_consensus: z.number().default(700),
      disputed_delta: z.number().default(300),
      low_value: z.number().default(400),
      blocker: z.number().default(700),
    }).default({}),
  }).default({}),
  token_budget: z.object({
    per_model: z.number().nullable().default(null),
    total: z.number().nullable().default(null),
  }).default({}),
  depth: z.object({
    structural_checklist: z.boolean().default(true),
    checklist_min_elements: z.number().default(5),
    permission_to_question: z.boolean().default(true),
    lore_active_weaving: z.boolean().default(true),
  }).default({}),
  cross_repo: z.object({
    auto_detect: z.boolean().default(true),
    manual_refs: z.array(z.string()).default([]),
  }).default({}),
  rating: z.object({
    enabled: z.boolean().default(true),
    timeout_seconds: z.number().default(60),
    retrospective_command: z.boolean().default(true),
  }).default({}),
  progress: z.object({
    verbose: z.boolean().default(true),
  }).default({}),
});

export type MultiModelConfig = z.infer<typeof MultiModelConfigSchema>;
```

**Config loading** (new function in `config.ts`):

```typescript
function loadMultiModelConfig(): MultiModelConfig {
  try {
    const result = execSync(
      'yq eval ".run_bridge.bridgebuilder.multi_model" .loa.config.yaml -o json',
      { encoding: "utf8", timeout: 5000 }
    );
    if (result.trim() === "null") return MultiModelConfigSchema.parse({});
    return MultiModelConfigSchema.parse(JSON.parse(result));
  } catch {
    return MultiModelConfigSchema.parse({});  // defaults: disabled
  }
}
```

**API key validation** (at startup in `main.ts`):

```typescript
function validateApiKeys(config: MultiModelConfig): { valid: string[]; missing: string[] } {
  const ENV_MAP: Record<string, string> = {
    anthropic: "ANTHROPIC_API_KEY",
    openai: "OPENAI_API_KEY",
    google: "GOOGLE_API_KEY",
  };
  // Check each configured model's provider key
  // In strict mode: throw if any missing
  // In graceful mode: filter to available models, warn about missing
}
```

### 2.8 Progress Visibility (FR-11)

**New file: `core/progress.ts`**

```typescript
export interface ProgressReporter {
  report(phase: string, model: string, activity: string): void;
}
```

Implementation writes to stderr (not stdout, to avoid interfering with JSON output):

```
[bridgebuilder] Initializing multi-model review (3 models)...
[bridgebuilder] Claude Opus 4.6 — starting convergence pass...
[bridgebuilder] Codex 5.2 — starting convergence pass...
[bridgebuilder] Gemini 2.5 Pro — starting convergence pass...
[bridgebuilder] Claude Opus 4.6 — convergence complete (12 findings), starting enrichment...
[bridgebuilder] Codex 5.2 — convergence complete (8 findings), starting enrichment...
[bridgebuilder] Claude Opus 4.6 — enrichment complete, posting review...
[bridgebuilder] Cross-scoring phase — 6 pairwise evaluations...
[bridgebuilder] Consensus: 7 HIGH, 2 DISPUTED, 0 BLOCKERS
```

When `progress.verbose: false`, only phase transitions logged (not per-model activity).

### 2.9 Bridge Orchestrator Integration (FR-10)

**Modifying `bridge-orchestrator.sh`** (lines 340-487):

The orchestrator reads iteration strategy from config:

```bash
strategy=$(yq eval '.run_bridge.bridgebuilder.multi_model.iteration_strategy // "final"' .loa.config.yaml)
```

Before emitting `SIGNAL:BRIDGEBUILDER_REVIEW:$iteration`, checks:

```bash
if is_multi_model_iteration "$iteration" "$depth" "$strategy"; then
  echo "SIGNAL:BRIDGEBUILDER_REVIEW_MULTI:$iteration"
else
  echo "SIGNAL:BRIDGEBUILDER_REVIEW:$iteration"
fi
```

The `is_multi_model_iteration()` function:
- `"every"` → always true
- `"final"` → true only when `$iteration == $depth`
- `[1,3,5]` → true when iteration number is in the array

---

## 3. Data Models

### 3.1 Extended ReviewResponse

```typescript
// Backward-compatible extension of existing ReviewResponse (llm-provider.ts:7-12)
export interface ReviewResponse {
  content: string;
  inputTokens: number;
  outputTokens: number;
  model: string;
  provider?: string;
  latencyMs?: number;
  estimatedCostUsd?: number;
  errorState?: LLMProviderErrorCode | null;
}
```

### 3.2 MultiModelConfig

See Section 2.7 — zod schema with defaults. Validated at startup.

### 3.3 Rating Entry

See Section 2.6 — JSONL entries in `grimoires/loa/ratings/review-ratings.jsonl`.

### 3.4 Consensus Findings

See Section 2.4 — `ConsensusResult` with `ScoredFinding[]` arrays.

---

## 4. API Contracts

### 4.1 OpenAI Chat Completions (Codex 5.2)

```
POST https://api.openai.com/v1/chat/completions
Headers:
  Authorization: Bearer {OPENAI_API_KEY}
  Content-Type: application/json
Body:
  {
    "model": "{model_id}",
    "messages": [
      { "role": "system", "content": "{systemPrompt}" },
      { "role": "user", "content": "{userPrompt}" }
    ],
    "stream": true,
    "max_completion_tokens": {maxOutputTokens}
  }
Stream events: data: {"choices": [{"delta": {"content": "..."}}]}
Terminal: data: [DONE]
```

### 4.1.1 Cross-Scoring Prompt Contract [IMP-004]

```
POST (to each model) — cross-scoring request
Input:
  systemPrompt: "You are evaluating code review findings from another model..."
  userPrompt:
    - Original PR diff summary (truncated to 2K tokens)
    - Source model's findings JSON (full)
    - Scoring rubric: "Score 0-1000 on accuracy, specificity, actionability"
Output:
  ReviewResponse.content: JSON array of { finding_id, score, rationale }
```

Each cross-scoring call is bounded to 4K output tokens. Total cross-scoring cost is predictable: N*(N-1) calls at ~4K output each.

### 4.1.2 Cost Estimation [IMP-006]

`estimatedCostUsd` in `ReviewResponse` computed from configurable per-1K-token rates:

```typescript
const COST_RATES: Record<string, { input: number; output: number }> = {
  "anthropic": { input: 0.015, output: 0.075 },  // per 1K tokens
  "openai": { input: 0.01, output: 0.03 },
  "google": { input: 0.00, output: 0.00 },         // free tier default
};
```

Rates configurable in `.loa.config.yaml` under `multi_model.cost_rates`. Updated when provider pricing changes — not hardcoded.

### 4.2 Google Gemini (generateContent)

```
POST https://generativelanguage.googleapis.com/v1beta/models/{model_id}:streamGenerateContent?key={GOOGLE_API_KEY}&alt=sse
Headers:
  Content-Type: application/json
Body:
  {
    "contents": [
      { "role": "user", "parts": [{ "text": "{systemPrompt}\n\n{userPrompt}" }] }
    ],
    "generationConfig": { "maxOutputTokens": {maxOutputTokens} },
    "systemInstruction": { "parts": [{ "text": "{systemPrompt}" }] }
  }
Stream events: data: {"candidates": [{"content": {"parts": [{"text": "..."}]}}]}
```

### 4.3 GitHub Comment Posting

```bash
gh api repos/{owner}/{repo}/issues/{pr}/comments -f body="{comment_body}"
```

Per-model comments and consensus summary posted as issue comments (not PR reviews), allowing unlimited length with splitting at 65,536 chars.

---

## 5. File Inventory

### 5.1 New Files

| File | Purpose | Est. Lines |
|------|---------|-----------|
| `resources/adapters/openai.ts` | OpenAI/Codex adapter | ~250 |
| `resources/adapters/google.ts` | Google/Gemini adapter | ~250 |
| `resources/adapters/adapter-factory.ts` | Factory for provider creation | ~40 |
| `resources/core/multi-model-pipeline.ts` | N-model parallel orchestration | ~300 |
| `resources/core/scoring.ts` | Consensus calculation (TypeScript port) | ~200 |
| `resources/core/cross-scorer.ts` | Cross-scoring fan-out | ~150 |
| `resources/core/depth-checker.ts` | Structural depth checklist | ~100 |
| `resources/core/rating.ts` | Human rating collection + storage | ~120 |
| `resources/core/cross-repo.ts` | Cross-repo context sourcing | ~150 |
| `resources/core/progress.ts` | Progress visibility reporting | ~60 |
| `resources/__tests__/openai.test.ts` | OpenAI adapter tests | ~150 |
| `resources/__tests__/google.test.ts` | Google adapter tests | ~150 |
| `resources/__tests__/multi-model.test.ts` | Pipeline integration tests | ~200 |
| `resources/__tests__/scoring.test.ts` | Scoring module tests | ~150 |
| `resources/__tests__/depth-checker.test.ts` | Depth checklist tests | ~80 |

### 5.2 Modified Files

| File | Change | Impact |
|------|--------|--------|
| `resources/ports/llm-provider.ts` | Extend `ReviewResponse`, add error codes | Low — backward compatible |
| `resources/ports/review-poster.ts` | Add `postComment()` method | Low — additive |
| `resources/core/types.ts` | Add `MultiModelConfig` type | Low — additive |
| `resources/core/schemas.ts` | Add consensus finding schema | Low — additive |
| `resources/core/template.ts` | Add depth-enhanced prompts, Permission to Question | Medium — new prompt building paths |
| `resources/core/reviewer.ts` | Route to multi-model when enabled | Low — routing gate only |
| `resources/config.ts` | Add `loadMultiModelConfig()`, extend config types | Medium — new parsing path |
| `resources/adapters/index.ts` | Update `createLocalAdapters()` for multiple providers | Medium — composition root change |
| `resources/adapters/github-cli.ts` | Add `postComment()` with splitting | Low — additive |
| `resources/main.ts` | Wire multi-model pipeline, API key validation | Medium — new entry path |
| `.claude/scripts/bridge-orchestrator.sh` | Add iteration strategy routing | Low — signal routing |

---

## 6. Security Design

### 6.1 API Key Handling

- Keys read from environment variables only (existing SKP-003 pattern)
- Keys never logged, never included in review output
- Keys never passed to other models (each adapter reads its own key)
- Missing key detection at startup (graceful/strict mode)

### 6.2 Secret Redaction

- Existing `PatternSanitizer` (gitleaks patterns) applied to ALL model outputs before GitHub posting
- Applied per-model, not just on consensus summary
- Cross-repo context summaries also passed through sanitizer

### 6.3 Prompt Injection Hardening

- Existing `INJECTION_HARDENING` prefix (`template.ts:25-26`) applied to all models
- Cross-repo content marked as `## External Context (untrusted)` in prompt

---

## 7. Testing Strategy

### 7.1 Unit Tests

| Test | Target | Approach |
|------|--------|----------|
| OpenAI adapter | `openai.ts` | Mock HTTP responses, verify normalization to `ReviewResponse` |
| Google adapter | `google.ts` | Mock HTTP responses, verify SSE parsing |
| Adapter factory | `adapter-factory.ts` | Verify correct adapter instantiation per provider |
| Scoring module | `scoring.ts` | Verify consensus math matches `scoring-engine.sh` output for same inputs |
| Depth checker | `depth-checker.ts` | Verify pattern detection for each checklist element |
| Config parser | `config.ts` | Verify `loadMultiModelConfig()` with various YAML inputs |
| Comment splitting | `github-cli.ts` | Verify split at 65,536 chars with continuation headers |

### 7.2 Integration Tests

| Test | Scope |
|------|-------|
| Multi-model pipeline end-to-end | Mock adapters → parallel execution → scoring → comment posting |
| Graceful degradation | One adapter fails → pipeline continues with remaining |
| Strict mode failure | One adapter fails → pipeline halts |
| Feature-off parity | `enabled: false` → identical output to current Bridgebuilder |

### 7.3 Quality Metrics Validation [SKP-006]

- Rating entries include `depthCheck` results for correlation analysis
- Anti-gaming: depth elements must reference specific PR files (not boilerplate)
- Actionable finding rate tracked: findings leading to code changes / total

---

## 8. Backward Compatibility

### 8.1 Zero-Change Guarantee

When `multi_model.enabled: false` (default):

1. `loadMultiModelConfig()` returns defaults with `enabled: false`
2. `main.ts` creates single `AnthropicAdapter` via existing `createLocalAdapters()`
3. `ReviewPipeline` processes items via existing single/two-pass flow
4. No new code paths executed
5. No additional API calls
6. No additional GitHub comments
7. No performance overhead (config check is a single boolean)

### 8.2 Interface Compatibility

- `ReviewResponse` extensions are optional fields — existing adapters don't break
- `IReviewPoster.postComment()` is additive — `postReview()` unchanged
- `BridgebuilderConfig` gains optional `multiModel?` field
- All existing CLI flags, env vars, and YAML config unchanged

---

## 9. Deployment Considerations

### 9.1 Build

TypeScript compiled to `dist/` via existing `npm run build` pipeline. New adapters included in compilation. No new runtime dependencies (HTTP calls use Node.js built-in `fetch`/`https`).

### 9.2 Configuration Rollout

1. Add `multi_model` block to `.loa.config.yaml` with `enabled: false`
2. Set API keys: `OPENAI_API_KEY`, `GOOGLE_API_KEY`
3. Set `enabled: true` to activate
4. Adjust `iteration_strategy` as desired

### 9.3 Monitoring

- Per-adapter telemetry (tokens, latency, cost) logged to review summary JSON
- Rating data in `grimoires/loa/ratings/review-ratings.jsonl`
- Depth check results in `grimoires/loa/ratings/depth-checks.jsonl`
- Consensus metrics in review summary and GitHub consensus comment

---

*Generated from PRD v1.1 — Flatline-reviewed, 7 HIGH_CONSENSUS findings integrated*
