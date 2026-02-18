# PRD: Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing

> Cycle: cycle-026 | Author: janitooor + Claude
> Source: [#365](https://github.com/0xHoneyJar/loa/issues/365), [#368](https://github.com/0xHoneyJar/loa/pull/368)
> Priority: P1 (infrastructure — unlocks multi-model agent capabilities)
> Flatline: Reviewed (4 HIGH_CONSENSUS integrated, 5 BLOCKERS addressed)
> Phase 1.5 added: 2026-02-18 (Hounfour v7 Protocol Alignment)

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

| Metric | Target | Phase |
|--------|--------|-------|
| `cheval.py --agent reviewing-code` invokes OpenAI GPT-5.2 | End-to-end pass | 1 |
| `cheval.py --agent deep-researcher` invokes Gemini Deep Research | Returns cited report with DOIs | 1 |
| `cheval.py --agent deep-thinker` invokes Gemini 3 Pro with `thinkingLevel: high` | Returns thinking trace + response | 1 |
| Flatline Protocol runs through Hounfour (no manual API calls) | All 4 parallel calls route correctly | 1 |
| TeamCreate teammate invokes `cheval.py` successfully | Tool output returned to agent | 1 |
| Google adapter handles Gemini API errors gracefully | Correct exit codes, fallback to configured chain | 1 |
| All existing tests pass (no regressions) | 100% pass rate | 1, 1.5 |
| Metering records cost for all external model calls | Ledger entries for every invocation | 1 |
| Ecosystem protocol versions match actual pins | 3/3 entries correct | 1.5 |
| `model-permissions.yaml` uses trust_scopes (6-dimensional) | All 5 model entries migrated | 1.5 |
| `model-config.schema.json` validates all provider types | Schema accepts `"google"` type | 1.5 |
| `butterfreezone-validate.sh` passes (no proto_version warnings) | Zero warnings | 1.5 |
| Hounfour v7 type mapping documented | 5 type correspondences cited | 1.5 |

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

### Phase 1.5 (Hounfour v7 Protocol Alignment — this cycle, post-MVP)

> **Context**: loa-hounfour has evolved from v4.6.0 (declared in ecosystem) to v7.0.0 ("The
> Composition-Aware Economic Protocol"). arrakis is already on v7.0.0. loa-finn is on v5.0.0.
> Loa's own declarations and type vocabulary are stale by 3 major versions. Phase 1 activated
> the runtime bridge; Phase 1.5 aligns the bridge with the current protocol.
>
> **FAANG parallel**: This is the "API versioning catch-up" pattern that every platform team
> encounters. When Stripe migrated from API v1 to v3, they didn't touch the payment processing
> core — they updated the type vocabulary, the schema declarations, and the inter-service
> contracts. The runtime was already correct; the metadata was wrong. Same pattern here.
>
> Sources: [loa-hounfour CHANGELOG](https://github.com/0xHoneyJar/loa-hounfour/blob/main/CHANGELOG.md),
> [arrakis PR #63](https://github.com/0xHoneyJar/arrakis/pull/63),
> [loa-finn #66](https://github.com/0xHoneyJar/loa-finn/issues/66)

#### FR-7: Ecosystem Protocol Version Alignment

Update all ecosystem protocol version declarations from `loa-hounfour@4.6.0` to reflect the
actual version each consumer is pinned to.

**`.loa.config.yaml` ecosystem entries**:
```yaml
butterfreezone:
  ecosystem:
    - repo: 0xHoneyJar/loa-finn
      protocol: loa-hounfour@5.0.0    # was @4.6.0 — pinned to e5b9f16
    - repo: 0xHoneyJar/loa-hounfour
      protocol: loa-hounfour@7.0.0    # was @4.6.0 — current release
    - repo: 0xHoneyJar/arrakis
      protocol: loa-hounfour@7.0.0    # was @4.6.0 — pinned to d091a3c
```

**BUTTERFREEZONE.md**: Regenerate via `butterfreezone-gen.sh` after config update. The
`validate_protocol_version()` check will stop emitting staleness warnings.

**Acceptance criteria**:
- [ ] All 3 ecosystem protocol entries reflect actual pinned versions
- [ ] `butterfreezone-validate.sh` passes with no `proto_version` warnings
- [ ] BUTTERFREEZONE.md AGENT-CONTEXT block matches config

#### FR-8: Trust Vocabulary Migration (trust_level → trust_scopes)

Hounfour v6.0.0 replaced the flat `trust_level` field on `AgentIdentity` with
`trust_scopes: CapabilityScopedTrust` — a 6-dimensional capability-scoped trust model.

**6 trust dimensions**:
| Dimension | Meaning |
|-----------|---------|
| `data_access` | What data can the agent read/write |
| `financial` | Can the agent authorize spend |
| `delegation` | Can the agent delegate to other agents |
| `model_selection` | Can the agent choose which model to use |
| `governance` | Can the agent participate in governance decisions |
| `external_communication` | Can the agent communicate outside the system |

**Files requiring migration**:

1. **`.claude/data/model-permissions.yaml`** — Currently uses flat `trust_level: high|medium`.
   Migrate to `trust_scopes` with per-dimension values:
   ```yaml
   claude-code:session:
     trust_scopes:
       data_access: high
       financial: high      # Can authorize spend via BudgetEnforcer
       delegation: high     # Can spawn TeamCreate teammates
       model_selection: high # Can invoke any configured model
       governance: none     # No governance participation (CLI tool)
       external_communication: high  # Can call external APIs
   openai:gpt-5.2:
     trust_scopes:
       data_access: none    # Receives document content only
       financial: none
       delegation: none
       model_selection: none
       governance: none
       external_communication: none  # Read-only remote model
   ```

2. **`docs/architecture/capability-schema.md`** — Trust gradient section references
   `hounfour_trust` mapping. Update to reference `trust_scopes` vocabulary:
   - L1 (Tests Present) → basic scopes: `{data_access: read, financial: none, ...}`
   - L2 (CI Verified) → verified scopes: add `model_selection: review_tier`
   - L3 (Property-Based) → hardened scopes: add `delegation: supervised`
   - L4 (Formal) → proven scopes: full scope access

3. **`BUTTERFREEZONE.md`** — Regeneration picks up the new trust vocabulary from updated
   sources. The existing `trust_level: L2-verified` declaration in AGENT-CONTEXT is Loa's
   own trust level (not a hounfour `AgentIdentity` field) and remains valid as a simplified
   representation. Add `trust_scopes_version: v6` metadata field to signal v6+ awareness.

**Backward compatibility**: The trust gradient (L1-L4) remains as Loa's external interface.
The `trust_scopes` mapping is the internal representation that aligns with hounfour v6+'s
`CapabilityScopedTrust` type. Consumers that don't understand `trust_scopes` fall back to
the L-level classification.

**Acceptance criteria**:
- [ ] `model-permissions.yaml` uses 6-dimensional `trust_scopes` for all 5 models
- [ ] `capability-schema.md` trust gradient references `trust_scopes` vocabulary
- [ ] BUTTERFREEZONE.md includes `trust_scopes_version` metadata

#### FR-9: Provider Type Schema Fix

The JSON schema at `.claude/schemas/model-config.schema.json` defines provider `type` as:
```json
"type": { "enum": ["openai", "anthropic", "openai_compat"] }
```

This is missing `"google"` — the provider type added in Phase 1 (cycle-026 sprint-1).
This is a schema-code mismatch: the code works (GoogleAdapter handles `type: "google"`)
but the validation schema would reject it.

**Fix**: Add `"google"` to the provider type enum.

**Acceptance criteria**:
- [ ] Schema includes `"google"` in provider type enum
- [ ] Schema validation passes for all entries in `model-config.yaml`

#### FR-10: Hounfour v7 Type Awareness in Documentation

Update documentation to reflect the v7 protocol's compositional model. The key v7 additions
that affect how Loa understands the ecosystem:

1. **`BridgeTransferSaga`** — Garcia-Molina saga pattern for cross-registry value transfer.
   Loa doesn't instantiate these, but Bridgebuilder reviews should understand the pattern
   when reviewing arrakis billing code that uses it.

2. **`DelegationOutcome`** — Conflict resolution with dissent recording. Relevant to
   Flatline Protocol's consensus/dispute classification (HIGH_CONSENSUS, DISPUTED).
   Document the structural parallel.

3. **`MonetaryPolicy`** — Minting-conservation coupling. Relevant to metering:
   Loa's `RemainderAccumulator` pattern in `pricing.py` implements the same conservation
   invariant. Document this equivalence.

4. **`PermissionBoundary`** — MAY permission semantics with reporting and revocation.
   Directly models the MAY rules in CLAUDE.loa.md's permission grants. Document this
   as the formal type that Loa's textual permissions map to.

5. **`GovernanceProposal`** — Weighted voting mechanism. Relevant to Flatline's
   multi-model scoring where each model acts as a weighted voter.

**Output**: Update `docs/architecture/capability-schema.md` with a "Hounfour v7 Type
Mapping" section that documents how Loa's internal patterns correspond to hounfour protocol
types. This is documentation, not code — but it makes the ecosystem legible to both humans
and agents doing cross-repo reviews.

**Acceptance criteria**:
- [ ] capability-schema.md includes v7 type mapping section
- [ ] Each mapping cites specific Loa code (file:line) and hounfour type

#### FR-11: Lore and Cultural Alignment

Update lore entries that reference specific hounfour concepts to reflect the v7 vocabulary:

1. **`mibera/core.yaml` — hounfour entry**: Update context to mention the Composition-Aware
   Economic Protocol (v7) as the current era of the hounfour.

2. **Version-aware ecosystem narrative**: The `butterfreezone.culture` section in
   `.loa.config.yaml` references "Hounfour" as a naming convention. No change needed there.
   But the capability-schema.md should document the hounfour version lineage:
   - v3.0.0: "Constitutional" — agent identity, billing, conversations
   - v4.6.0: "Agent Economy" — performance, reputation, governance
   - v5.0.0: "Multi-Model" — barrel decomposition, conservation properties
   - v6.0.0: "Capability-Scoped Trust" — trust_scopes replaces trust_level
   - v7.0.0: "Composition-Aware Economic Protocol" — sagas, delegation outcomes, monetary policy

**Acceptance criteria**:
- [ ] Lore entry updated with v7 context
- [ ] Version lineage documented in capability-schema.md

### Phase 2 (Future — not this cycle)

- **Grounding with Google Search**: Enable Gemini's `googleSearchRetrieval` tool for real-time web access with citation metadata
- **Streaming Deep Research**: Real-time progress updates from long-running research tasks
- **Auto model selection**: Classify subtask type (research/reasoning/generation) and route to optimal model automatically
- **Cost dashboard**: Per-teammate, per-agent cost rollup in metering ledger
- **Gemini context caching**: Use cached content API for repeated context (construct knowledge bases)
- **trust_scopes enforcement at runtime**: Currently documentation-level. Future: enforce trust_scopes during `resolve_execution()` — check that resolved model's trust dimensions meet agent's requirements
- **Constraint evaluator builtins**: If Loa ever validates hounfour constraints locally, align with v7's 31 builtins (up from 10 in v3)
- **BillingEntry protocol alignment**: Adopt hounfour's `BillingEntry` type via Strangler Fig pattern (as arrakis Sprint 255 did) for cross-system ledger compatibility

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

### In Scope — Phase 1 (MVP, completed)

1. Google provider adapter (`GoogleAdapter`) with Gemini 2.5 + 3 support
2. `thinkingLevel` and `thinkingBudget` parameter support
3. Deep Research adapter via Interactions API with blocking-poll
4. Gemini 3 model configurations and aliases
5. Agent binding presets for research/reasoning roles
6. Flatline routing activation through Hounfour
7. Agent Teams documentation update (Template 4: Expert Swarm)
8. Tests: unit tests for GoogleAdapter, integration tests for cheval.py, smoke tests for live API

### In Scope — Phase 1.5 (v7 Protocol Alignment, this cycle)

9. Ecosystem protocol version updates (FR-7)
10. trust_level → trust_scopes migration in model-permissions and capability-schema (FR-8)
11. Provider type schema fix for "google" (FR-9)
12. Hounfour v7 type awareness documentation (FR-10)
13. Lore and cultural alignment updates (FR-11)
14. BUTTERFREEZONE.md regeneration

### Out of Scope

- Google Search grounding (`googleSearchRetrieval` tool) — Phase 2
- Streaming Deep Research — Phase 2
- Auto model selection/classification — Phase 2
- Cost dashboard UI — Phase 2
- Gemini context caching — Phase 2
- Changes to Claude Code's TeamCreate API (model parameter) — depends on upstream
- Direct Gemini-as-agent (teammates must be Claude; external models are tools)
- trust_scopes runtime enforcement — Phase 2 (documentation-only in Phase 1.5)
- Constraint evaluator builtin alignment — Phase 2 (31 builtins, Loa doesn't evaluate locally)
- BillingEntry Strangler Fig adoption — Phase 2 (arrakis pattern, not needed for Loa MVP)

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

### Phase 1.5 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| loa-finn upgrades to v7 before Loa ships, causing version mismatch | Low | Low | Version declarations are per-repo; update on next sync |
| trust_scopes vocabulary evolves in v8+ | Low | Low | Loa's trust gradient (L1-L4) is an abstraction layer over hounfour scopes |
| BUTTERFREEZONE consumers don't understand trust_scopes_version | Low | None | Backward-compatible: consumers ignore unknown fields (schema v1.0 contract) |

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

### Phase 1 (Runtime Bridge)
- [Gemini Thinking mode docs](https://ai.google.dev/gemini-api/docs/thinking)
- [Gemini Deep Research API docs](https://ai.google.dev/gemini-api/docs/deep-research)
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Straylight construct](https://github.com/zkSoju/straylight) (exemplar use case)
- [Claude improved web search](https://claude.com/blog/improved-web-search-with-dynamic-filtering) (comment context)
- Existing adapter code: `.claude/adapters/loa_cheval/providers/`
- Hounfour config: `.claude/defaults/model-config.yaml`
- Agent Teams reference: `.claude/loa/reference/agent-teams-reference.md`

### Phase 1.5 (v7 Protocol Alignment)
- [loa-hounfour v7.0.0 CHANGELOG](https://github.com/0xHoneyJar/loa-hounfour/blob/main/CHANGELOG.md)
- [loa-hounfour MIGRATION.md](https://github.com/0xHoneyJar/loa-hounfour/blob/main/MIGRATION.md) (v6→v7 guide)
- [loa-hounfour PR #1](https://github.com/0xHoneyJar/loa-hounfour/pull/1) — Protocol Types v3.0.0 (constitutional layer)
- [loa-hounfour PR #2](https://github.com/0xHoneyJar/loa-hounfour/pull/2) — Agent Economy v4.6.0 (civilizational layer)
- [arrakis PR #63](https://github.com/0xHoneyJar/arrakis/pull/63) — Billing implementation (v7.0.0 pinned)
- [arrakis #62](https://github.com/0xHoneyJar/arrakis/issues/62) — Billing RFC (lot_invariant, micro-USD)
- [loa-finn #66](https://github.com/0xHoneyJar/loa-finn/issues/66) — Launch readiness (v5.0.0 pinned)
- [loa-finn #31](https://github.com/0xHoneyJar/loa-finn/issues/31) — Hounfour RFC (permission scape)
- [loa #247](https://github.com/0xHoneyJar/loa/issues/247) — Ecosystem integration history
- Capability schema: `docs/architecture/capability-schema.md`
- Model permissions: `.claude/data/model-permissions.yaml`
- Config schema: `.claude/schemas/model-config.schema.json`
- Lore: `.claude/data/lore/mibera/core.yaml` (hounfour entry)
