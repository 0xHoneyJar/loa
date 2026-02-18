# PRD: Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing

> Cycle: cycle-026 | Author: janitooor + Claude
> Source: [#365](https://github.com/0xHoneyJar/loa/issues/365)
> Priority: P1 (infrastructure — unlocks multi-model agent capabilities)
> Flatline: Reviewed (4 HIGH_CONSENSUS integrated, 5 BLOCKERS addressed)

## 1. Problem Statement

Loa's Hounfour subsystem has a complete model routing architecture — alias resolution, agent bindings, provider registry, circuit breakers, metering — but **no runtime bridge**. The Python adapter system (`loa_cheval`) has OpenAI and Anthropic adapters. The Google provider is configured in `model-config.yaml` but has no adapter implementation. The `hounfour.flatline_routing` flag is `false`.

**Result**: Every agent in every workflow — TeamCreate teammates, Flatline reviewers, translation agents — runs as Claude Opus 4.6 talking to itself. The model routing infrastructure exists on paper but never executes.

**Impact for specialized domains**: When building vertical expert agents (health, science, engineering), the ceiling is training-data synthesis. A pharmacology expert reasoning about GHK-Cu's effect on follicle stem cells should pull clinical evidence from PubMed, not reconstruct from a knowledge cutoff. A longevity researcher modeling epigenetic cascades needs science-grade extended reasoning, not standard completion.

**The Straylight exemplar** ([#365](https://github.com/0xHoneyJar/loa/issues/365)): A Personal Health OS construct with MAGI tracks (MELCHIOR/peptides, BALTHASAR/longevity, CASPER/neurotech) where 4 TeamCreate domain experts produced a 739-line handoff document — all from the same model's training data. With model routing, MELCHIOR delegates literature review to Deep Research (cited DOIs), BALTHASAR delegates complex pathway modeling to Deep Think (science-grade reasoning), and safety-critical protocol decisions route through multi-model adversarial review.

> Sources: #365 (field observation from Straylight construct build)

## 2. Goals & Success Metrics

### Goals

1. **Activate the Hounfour runtime bridge**: End-to-end model invocation via `cheval.py` for all configured providers (OpenAI, Anthropic, Google).
2. **Implement Google provider adapter**: Support Gemini 2.5 (Flash/Pro) and Gemini 3 (Flash/Pro) models with `thinkingLevel` parameter.
3. **Implement Deep Research adapter**: Support Gemini Deep Research via the Interactions API with blocking-poll pattern and configurable timeout.
4. **Activate Flatline routing through Hounfour**: Set `flatline_routing: true` and wire Flatline Protocol to invoke external models via `cheval.py` instead of requiring manual API calls.
5. **Enable TeamCreate agents to invoke external models**: Teammates call `cheval.py` via Bash for subtask delegation (literature review, deep reasoning, consensus checks).
6. **Provide agent binding presets for research/reasoning roles**: Pre-configured bindings for common expert agent patterns.

### Success Metrics

| Metric | Target |
|--------|--------|
| `cheval.py --agent reviewing-code` invokes OpenAI GPT-5.2 | End-to-end pass |
| `cheval.py --agent deep-researcher` invokes Gemini Deep Research | Returns cited report with DOIs |
| `cheval.py --agent deep-thinker` invokes Gemini 3 Pro with `thinkingLevel: high` | Returns thinking trace + response |
| Flatline Protocol runs through Hounfour (no manual API calls) | All 4 parallel calls route correctly |
| TeamCreate teammate invokes `cheval.py` successfully | Tool output returned to agent |
| Google adapter handles Gemini API errors gracefully | Correct exit codes, fallback to configured chain |
| All existing tests pass (no regressions) | 100% pass rate |
| Metering records cost for all external model calls | Ledger entries for every invocation |

## 3. User & Stakeholder Context

### Primary Persona: Construct Developer

A developer building vertical expert agents using Loa constructs. They configure MAGI-style knowledge tracks where different domain experts need different model capabilities — some need research (cited literature), some need extended reasoning (multi-step scientific inference), some need standard completion (structured output).

**Pain**: Every TeamCreate expert is Claude Opus talking to itself. Research outputs cite training data, not sources. Reasoning depth is bounded by standard completion.

### Secondary Persona: Loa Framework User

A developer using Loa's Flatline Protocol for multi-model adversarial review. Today, Flatline is documented as multi-model but requires the `flatline_routing` flag to be active and Hounfour to actually invoke external models.

**Pain**: Flatline "multi-model" review uses a single model unless the user manually configures external API calls.

### Stakeholder: Framework Maintainer (THJ)

Wants the Hounfour infrastructure investment (cycles 013, 021) to deliver value. Model routing is the infrastructure layer that makes constructs, Flatline, and TeamCreate meaningfully multi-model.

## 4. Functional Requirements

### Phase 1 (MVP — this cycle)

#### FR-1: Google Provider Adapter

Implement `GoogleAdapter` extending `ProviderAdapter` base class (`.claude/adapters/loa_cheval/providers/base.py`).

**Standard Gemini models** (2.5 Flash, 2.5 Pro, 3 Flash, 3 Pro):
- Use `generateContent` REST API (`POST /v1beta/models/{model}:generateContent`)
- Support `generationConfig.temperature`, `generationConfig.maxOutputTokens`
- Support `thinkingConfig.thinkingLevel` for Gemini 3 models (low/medium/high)
- Support `thinkingConfig.thinkingBudget` for Gemini 2.5 models (128-32768 tokens)
- Parse `candidates[0].content.parts[*].text` → `CompletionResult.content`
- Parse `usageMetadata` → `Usage` (promptTokenCount, candidatesTokenCount, thoughtsTokenCount)
- Extract thinking traces from thought parts → `CompletionResult.thinking`
- Map Gemini error codes to Hounfour error types (400→InvalidInput, 429→RateLimited, 500+→ProviderUnavailable)

**Message format translation** (Flatline SKP-003: explicitly scope supported content):
- OpenAI canonical `{"role": "user", "content": "..."}` → Gemini `{"role": "user", "parts": [{"text": "..."}]}`
- System messages → `systemInstruction` field (Gemini doesn't use system role in contents array)
- **Supported content types**: text-only messages (`{"role": str, "content": str}`). Array content blocks, images, tool calls, and multimodal parts are NOT supported in MVP — adapter MUST raise `InvalidInputError` for unsupported content types rather than silently dropping content.
- **Conformance tests required**: role ordering (user/assistant alternation), multiple system messages (concatenate into single systemInstruction), empty content strings, and mixed role sequences.

**Registration**: Add `"google": GoogleAdapter` to `_ADAPTER_REGISTRY` in `__init__.py`.

#### FR-2: Gemini 3 Model Configuration

Add Gemini 3 models to `model-config.yaml`:

```yaml
gemini-3-flash:
  capabilities: [chat, thinking_traces]
  context_window: 1048576
  pricing:
    input_per_mtok: <TBD from pricing page>
    output_per_mtok: <TBD from pricing page>
gemini-3-pro:
  capabilities: [chat, thinking_traces, deep_reasoning]
  context_window: 1048576
  pricing:
    input_per_mtok: <TBD from pricing page>
    output_per_mtok: <TBD from pricing page>
```

Add thinking-aware aliases:
```yaml
deep-thinker: "google:gemini-3-pro"       # Science-grade extended reasoning
fast-thinker: "google:gemini-3-flash"      # Quick reasoning with thinking traces
researcher: "google:gemini-2.5-pro"        # Large context with grounded search
```

#### FR-3: Deep Research Adapter

Extend `GoogleAdapter` with Deep Research support for the Interactions API.

**Detection**: If model ID matches `deep-research-*` pattern, use Interactions API flow instead of `generateContent`.

**Flow**:
1. `POST /v1beta/models/{model}:createInteraction` with `background: true`, `store: true`
2. Poll `GET /v1beta/models/{model}/interactions/{id}` with exponential backoff (1s, 2s, 4s, 8s... capped at 30s)
3. On `status: "completed"`, extract `output` → `CompletionResult.content`
4. On `status: "failed"`, raise `ProviderUnavailableError`
5. On timeout (configurable, default 600s / 10 minutes), raise `TimeoutError` with partial results if available

**Configuration** (in `model-config.yaml`):
```yaml
deep-research-pro:
  capabilities: [deep_research, web_search, file_search]
  context_window: 1048576
  api_mode: interactions  # Signals GoogleAdapter to use Interactions API
  polling:
    initial_delay_seconds: 2
    max_delay_seconds: 30
    timeout_seconds: 600
  pricing:
    per_task_micro_usd: 3000000  # ~$3/task average
```

**Output contract** (Flatline SKP-001: define strict schema):

Deep Research responses MUST be post-processed into a normalized structure before returning as `CompletionResult.content`. The adapter extracts and validates:

```json
{
  "summary": "string — research synthesis",
  "claims": [{"text": "string", "confidence": "high|medium|low"}],
  "citations": [{"title": "string", "doi": "string|null", "url": "string|null", "source": "string"}],
  "raw_output": "string — unprocessed model response (fallback)"
}
```

When citations are missing or DOIs unresolvable: return `raw_output` with `citations: []` and log a warning. Do NOT fail the request — degraded output is better than no output.

**Dual-mode invocation** (Flatline SKP-002: avoid hanging workflows):

- **Blocking mode** (default): `cheval.py --agent deep-researcher --prompt "..."` — polls internally, returns when complete or timeout. Progress logged to stderr every 30s.
- **Non-blocking mode**: `cheval.py --agent deep-researcher --prompt "..." --async` — returns immediately with `{"interaction_id": "...", "status_endpoint": "..."}`. Caller polls separately via `cheval.py --poll <interaction_id>`.
- **Cancellation**: `cheval.py --cancel <interaction_id>` — best-effort cancellation of running interaction.
- **Concurrency limit**: Max 3 concurrent Deep Research interactions per provider (configurable). Additional requests queue with backpressure.

**I/O contract**: In blocking mode, same as standard `complete()` — returns `CompletionResult`. In non-blocking mode, returns JSON with interaction metadata. The caller is responsible for polling.

#### FR-4: Hounfour Runtime Activation

Enable end-to-end model invocation:

1. Set `hounfour.flatline_routing: true` in `.loa.config.yaml`
2. Wire Flatline Protocol scripts to invoke `cheval.py` for GPT-5.2 and Opus calls instead of direct API calls
3. Wire `/gpt-review` to invoke through `cheval.py`
4. Ensure `cheval.py` loads merged config (defaults + user overrides) correctly

**Backward compatibility**: If `flatline_routing: false`, existing behavior is preserved (no external calls).

#### FR-5: TeamCreate → Hounfour Bridge

Enable teammates to invoke external models via Bash:

```bash
# Teammate invokes Deep Research for literature review
python .claude/adapters/cheval.py --agent deep-researcher \
  --prompt "Survey GHK-Cu effects on follicle stem cell activation. Return cited sources with DOIs."

# Teammate invokes Deep Think for complex reasoning
python .claude/adapters/cheval.py --agent deep-thinker \
  --prompt "Model the interaction between rapamycin-induced autophagy and senolytics in cellular senescence pathways."
```

**No changes to TeamCreate API needed**. Teammates already have Bash access. The bridge is `cheval.py` itself.

**Exit code contract** (Flatline IMP-004: autonomous teammates need reliable branching):

| Exit Code | Meaning | Teammate Action |
|-----------|---------|-----------------|
| 0 | Success | Parse stdout as response |
| 1 | API error (retryable) | Retry or fallback |
| 2 | Invalid input | Fix prompt/agent name |
| 3 | Timeout | Increase timeout or use --async |
| 4 | Missing API key | Report to lead |
| 5 | Invalid response | Log and retry |
| 6 | Budget exceeded | Report to lead |
| 7 | Context too large | Reduce input |
| 8 | Interaction pending (--async mode) | Poll later |

Stderr MUST contain structured error JSON for exit codes >0. Stdout is reserved for model output only.

**Credential security** (Flatline IMP-001): API keys resolved exclusively via `{env:VARIABLE}` credential chain. For multi-agent workflows, document that `GOOGLE_API_KEY` must be available in the teammate's environment (inherited from lead's process). Future: support scoped credentials and rotation via secret manager integration.

**Documentation**: Update `.claude/loa/reference/agent-teams-reference.md` with:
- New "Template 4: Model-Heterogeneous Expert Swarm" topology
- Agent binding presets for research/reasoning roles
- Cost considerations for multi-model TeamCreate workflows

#### FR-6: Agent Binding Presets

Add research/reasoning agent bindings to `model-config.yaml`:

```yaml
agents:
  # ... existing bindings ...

  # Research agents — invoke via cheval.py for subtask delegation
  deep-researcher:
    model: "google:deep-research-pro"
    temperature: 0.3
    requires:
      deep_research: true

  deep-thinker:
    model: deep-thinker  # alias → google:gemini-3-pro
    temperature: 0.5
    requires:
      thinking_traces: true
      deep_reasoning: preferred

  fast-thinker:
    model: fast-thinker  # alias → google:gemini-3-flash
    temperature: 0.5
    requires:
      thinking_traces: true

  literature-reviewer:
    model: researcher     # alias → google:gemini-2.5-pro
    temperature: 0.3
    requires:
      thinking_traces: preferred
```

### Phase 2 (Future — not this cycle)

- **Grounding with Google Search**: Enable Gemini's `googleSearchRetrieval` tool for real-time web access with citation metadata
- **Streaming Deep Research**: Real-time progress updates from long-running research tasks
- **Auto model selection**: Classify subtask type (research/reasoning/generation) and route to optimal model automatically
- **Cost dashboard**: Per-teammate, per-agent cost rollup in metering ledger
- **Gemini context caching**: Use cached content API for repeated context (construct knowledge bases)

## 5. Technical & Non-Functional Requirements

### Performance

| Requirement | Target |
|-------------|--------|
| Standard Gemini completion latency | <10s for 2.5 Flash, <30s for 3 Pro |
| Deep Research completion time | 1-10 min typical, 60 min max |
| Deep Research polling overhead | <5% of total time (exponential backoff) |
| Adapter cold start (first call) | <2s (HTTP client detection + config load) |

### Concurrency (Flatline IMP-002, IMP-004)

Concurrent `cheval.py` invocations from multiple TeamCreate teammates MUST be safe:

- **Cost ledger**: Uses `fcntl.flock()` for atomic JSONL appends (already implemented in `metering/ledger.py`). Safe for concurrent writes.
- **Circuit breaker state**: Per-provider, in-memory only (each cheval.py process has its own). No shared file state. If persistent circuit breaker state is needed later, use flock-protected JSON.
- **Max concurrent calls per provider**: Configurable (default: 5 for standard models, 3 for Deep Research). Enforced via flock-based semaphore file.

### Cost (Flatline SKP-005: unified cost model)

| Model | Pricing Model | Estimated Cost |
|-------|--------------|----------------|
| Gemini 2.5 Flash | Per-token | $0.15/1M input, $0.60/1M output |
| Gemini 2.5 Pro | Per-token | $1.25/1M input, $10.00/1M output |
| Gemini 3 Pro | Per-token | TBD (pricing not yet published) |
| Deep Research | Per-task | $2-5 average per interaction |

**Unified cost model** (Flatline IMP-008): Extend `metering/pricing.py` to support both token-based and per-task pricing:

- Token-based models: `cost = (input_tokens * input_per_mtok + output_tokens * output_per_mtok) / 1_000_000` (existing)
- Per-task models: `cost = per_task_micro_usd` (new field in `PricingEntry`)
- Adapter emits normalized cost event: `{provider, model, units: "tokens"|"task", unit_counts: {input, output, reasoning} | {tasks: 1}, cost_micro_usd, pricing_source: "config"|"estimated"}`
- Budget enforcement applies uniformly: daily spend counter sums micro-USD regardless of pricing model.

**Budget enforcement**: Activate `BudgetEnforcer` in `cheval.py` (currently `NoOpBudgetHook`). Wire `invoke_with_retry()` to use real budget hook with config from `metering` section. Daily budget limits apply across all providers.

### Security

- API keys resolved via existing credential chain (`{env:GOOGLE_API_KEY}`)
- No API keys in code, config, or logs
- Deep Research `store: true` creates server-side interaction state — document data retention implications in config comments
- Secret scanning patterns updated for Google API keys (`AIzaSy[A-Za-z0-9_-]{33}`)

**Thinking trace policy** (Flatline SKP-004):
- Thinking traces are **opt-in** via `--include-thinking` flag on `cheval.py`. Default: traces are requested from the model but NOT included in stdout output.
- Cost ledger records `tokens_reasoning` count only — NEVER trace content.
- Traces are NEVER written to `.run/audit.jsonl` or any log file.
- When `--json` output is used with `--include-thinking`, traces appear in `result.thinking` field.
- When `--include-thinking` is omitted, `result.thinking` is `null` even if the model returned traces.

### Reliability

- Circuit breaker: 5 consecutive failures → OPEN (60s reset)
- Fallback chain: `google → openai` (configurable)
- Retry: 3 per-provider retries with exponential backoff
- Deep Research: Separate timeout from standard calls (default 600s vs 120s)

### Compatibility

- **Python**: 3.8+ (match existing adapter requirements)
- **HTTP client**: httpx preferred, urllib fallback (match existing pattern)
- **Config**: Backward-compatible — new models/aliases/agents added, nothing removed

**Granular feature flags** (Flatline IMP-010: avoid single coarse flag):

Replace `hounfour.flatline_routing: true/false` with per-subsystem flags:

```yaml
hounfour:
  google_adapter: true        # Enable Google provider adapter
  deep_research: true         # Enable Deep Research (Interactions API)
  flatline_routing: true      # Route Flatline through cheval.py
  metering: true              # Activate cost recording + budget enforcement
  thinking_traces: true       # Request thinking traces from supported models
```

Each flag independently enables its subsystem. `flatline_routing: false` preserves existing Flatline behavior. Rollback: set any flag to `false` to disable that specific capability without affecting others.

## 6. Scope & Prioritization

### In Scope (MVP)

1. Google provider adapter (`GoogleAdapter`) with Gemini 2.5 + 3 support
2. `thinkingLevel` and `thinkingBudget` parameter support
3. Deep Research adapter via Interactions API with blocking-poll
4. Gemini 3 model configurations and aliases
5. Agent binding presets for research/reasoning roles
6. Flatline routing activation through Hounfour
7. Agent Teams documentation update (Template 4: Expert Swarm)
8. Tests: unit tests for GoogleAdapter, integration tests for cheval.py, smoke tests for live API

### Out of Scope

- Google Search grounding (`googleSearchRetrieval` tool) — Phase 2
- Streaming Deep Research — Phase 2
- Auto model selection/classification — Phase 2
- Cost dashboard UI — Phase 2
- Gemini context caching — Phase 2
- Changes to Claude Code's TeamCreate API (model parameter) — depends on upstream
- Direct Gemini-as-agent (teammates must be Claude; external models are tools)

### Explicit Non-Goals

- **Not replacing Claude**: External models are tools that teammates invoke for specific subtasks. Claude remains the orchestration runtime for all agents.
- **Not building a generic multi-model framework**: This activates an existing architecture (Hounfour) with a specific provider (Google). The adapter pattern already handles other providers.
- **Not merging cycle-021**: Investigation revealed that branch's Gemini work was at the shell script layer (`model-adapter.sh.legacy`), not the Python adapter system. The scoring-engine changes regressed validation. We build the Google adapter fresh.

## 7. Risks & Dependencies

### Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Gemini 3 API changes during preview | Medium | Medium | Pin to specific API version, test in CI |
| Deep Research timeout behavior varies | Medium | Low | Configurable timeout, graceful degradation |
| Google API rate limits for multi-agent workflows | Medium | Medium | Circuit breaker + per-provider retry |
| `thinkingLevel` behavior differs from documentation | Low | Low | Integration tests with live API |

### External Dependencies

| Dependency | Status | Risk |
|-----------|--------|------|
| `GOOGLE_API_KEY` environment variable | Required | User must configure |
| Gemini 3 Pro API access | Early access / Preview | May require waitlist |
| Deep Research API (`deep-research-pro-preview-12-2025`) | Preview | May change before GA |
| httpx Python package | Optional (urllib fallback) | Low risk |

### Business Risks

| Risk | Mitigation |
|------|------------|
| Cost escalation from multi-model workflows | Budget enforcement via existing metering, daily limits |
| Deep Research server-side data storage (privacy) | Document in config, user opt-in via agent binding |
| Gemini preview models deprecated | Fallback chain to stable models |

## 8. Architecture Notes (for SDD)

### Key Design Decisions

1. **GoogleAdapter extends ProviderAdapter**: Same interface as OpenAI/Anthropic adapters. `complete()` handles both standard and Deep Research flows, branching on model config's `api_mode` field.

2. **Deep Research uses blocking-poll internally**: The adapter's `complete()` method blocks and polls the Interactions API. Callers see a normal synchronous response. This matches the existing adapter I/O contract and avoids introducing async complexity.

3. **Message format translation in adapter**: Gemini's message format (`parts[]` vs `content` string, `systemInstruction` vs system role) is handled entirely within `GoogleAdapter`. The resolver and cheval.py pass canonical OpenAI-format messages.

4. **No changes to TeamCreate API**: Teammates invoke `cheval.py` via Bash. This is the lowest-friction integration — no new tools, no MCP servers, no framework changes. The bridge is the CLI itself.

5. **Thinking traces flow through**: `CompletionResult.thinking` is already in the type system. Google adapter populates it from Gemini's thought parts. Callers that use thinking traces (Flatline skeptic/dissenter) get them automatically.

### Integration Points

```
TeamCreate Teammate
    │
    ├── Bash: python cheval.py --agent deep-researcher --prompt "..."
    │       │
    │       ├── resolver.py: deep-researcher → google:deep-research-pro
    │       ├── GoogleAdapter.complete(): Interactions API poll loop
    │       └── stdout: CompletionResult.content (cited report)
    │
    └── Bash: python cheval.py --agent deep-thinker --prompt "..."
            │
            ├── resolver.py: deep-thinker → google:gemini-3-pro
            ├── GoogleAdapter.complete(): generateContent with thinkingLevel:high
            └── stdout: CompletionResult.content + thinking trace
```

## 9. Reference Links

- [Gemini Thinking mode docs](https://ai.google.dev/gemini-api/docs/thinking)
- [Gemini Deep Research API docs](https://ai.google.dev/gemini-api/docs/deep-research)
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Straylight construct](https://github.com/zkSoju/straylight) (exemplar use case)
- [Claude improved web search](https://claude.com/blog/improved-web-search-with-dynamic-filtering) (comment context)
- Existing adapter code: `.claude/adapters/loa_cheval/providers/`
- Hounfour config: `.claude/defaults/model-config.yaml`
- Agent Teams reference: `.claude/loa/reference/agent-teams-reference.md`
