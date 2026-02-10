# PRD: Hounfour Upstream Extraction — Multi-Model Provider Abstraction for Loa

**Version**: 1.1.0
**Status**: Draft (revised per Flatline Protocol review)
**Author**: Discovery Phase (plan-and-analyze)
**Issue**: [loa-finn #31](https://github.com/0xHoneyJar/loa-finn/issues/31) (upstream extraction)
**Date**: 2026-02-10

---

## 1. Problem Statement

Loa's multi-model integration is currently **ad-hoc and hardcoded**. The Flatline Protocol calls GPT-5.2 through direct API invocations in `gpt-review-api.sh` (850 lines), while `model-adapter.sh` (827 lines) contains a growing associative-array registry of providers, models, cost tables, and retry logic — all in bash. The skill schema (`skill-index.schema.json`) only supports `["sonnet", "opus", "haiku"]` as model options, locking skills to Anthropic.

Meanwhile, the complete solution already exists: **loa-finn has implemented Phases 0-5 of the Hounfour RFC** (loa-finn #31) — 40,170 lines across 229 files, covering provider abstraction (`cheval.py`), routing with fallback/downgrade chains, capability-based model selection, budget enforcement, circuit breakers, ensemble orchestration, and skill decomposition into model-agnostic `persona.md` files. This code works. It's been reviewed by Bridgebuilder (4 review rounds), cross-model reviewed by GPT-5.2 (42+ findings fixed), and tested with 578+ assertions.

**The gap**: None of these patterns are available in the upstream Loa framework. Any loa-powered project that isn't loa-finn gets zero multi-model capability. The ad-hoc bash integrations in `.claude/scripts/` will continue to accumulate complexity until they're replaced by the principled abstractions that loa-finn has already proven.

**Source**: [Hounfour RFC](https://github.com/0xHoneyJar/loa-finn/issues/31) handoff directions (comment `finn-analysis: rfc31-handoff-directions-2026-02-09`).

## 2. Goals & Success Metrics

### Goals

| # | Goal | Measurable Outcome |
|---|------|-------------------|
| G1 | Replace ad-hoc bash model integration with principled provider abstraction | `model-adapter.sh` replaced by config-driven routing through `cheval.py` |
| G2 | Make multi-model routing available to any loa-powered project | Config schema + default templates ship in `.claude/` System Zone |
| G3 | Enable skill portability across model providers | Skills decomposed into `persona.md` (model-agnostic) + `SKILL.md` (native runtime) |
| G4 | Unify Flatline Protocol model calls through the Hounfour router | `flatline-orchestrator.sh` and `gpt-review-api.sh` route through `model-invoke` |
| G5 | Provide framework-level budget enforcement and cost visibility | JSONL cost ledger with `/cost-report` command |

### Success Metrics

| # | Metric | Current | Target |
|---|--------|---------|--------|
| M1 | Model providers configurable per project | 2 (hardcoded Anthropic + OpenAI) | 4+ (any OpenAI-compatible) |
| M2 | Skills with model-agnostic `persona.md` | 0/19 | 8+ core agents |
| M3 | Skill schema model options | 3 (sonnet/opus/haiku) | Alias-based (any configured model) |
| M4 | Ad-hoc API calls bypassing model adapter | 2 (gpt-review-api.sh, flatline-orchestrator.sh) | 0 |
| M5 | Cost tracking granularity | Per-call in model-adapter.sh | Per-agent, per-model, per-sprint JSONL |

## 3. User & Stakeholder Context

### Primary Persona: Loa Framework User

Developers who adopt Loa for their projects. Currently locked to Claude Code as the only model backend. They need the ability to configure alternative models for cost optimization, resilience, or capability matching — without modifying any `.claude/` files.

### Secondary Persona: loa-finn Integration

loa-finn has built Hounfour as its runtime model layer. The upstream extraction creates a shared contract: Loa defines the schemas, defaults, and routing abstractions; loa-finn implements the runtime adapters. This prevents contract drift between the framework and its primary runtime.

### Tertiary Persona: Construct Authors

Developers building Loa Constructs (skill packs). Model-agnostic skills (`persona.md` + `output-schema.md`) enable constructs that work across any model provider, increasing the addressable user base.

## 4. Functional Requirements

### FR-1: Configuration Schema v2 (MUST)

Extend `.loa.config.yaml` with the Hounfour configuration schema. The schema defines providers, aliases, agent bindings, routing rules, and metering.

**Key sections**:
- `providers`: Registry of model providers with type, endpoint, auth, and per-model capabilities
- `aliases`: Short names resolving to `provider:model-id` pairs (e.g., `reasoning: "moonshot:kimi-k2-thinking"`)
- `agents`: Per-agent model binding with required capabilities
- `routing`: Fallback chains (availability) and downgrade chains (cost)
- `metering`: Budget enforcement with per-phase/sprint/project scoping

**Naming convention**: `provider:model-id` everywhere. Aliases are Loa-internal shorthand. Model IDs match the string sent to the provider API. Provider keys in config match provider keys in pricing.

**Precedence** (lowest → highest):
1. System Zone defaults (`.claude/defaults/model-config.yaml`)
2. Project config (`.loa.config.yaml`)
3. Environment variables (`LOA_MODEL=...`) — opt-in only, limited to model alias override
4. CLI override (`--model provider:model-id`)

**Env var scope**: Only `LOA_MODEL` (alias override) and `LOA_PROVIDER_<NAME>_KEY` (auth) are recognized. Env vars cannot override routing, pricing, or agent bindings — those are project-level concerns that must be reproducible. Use `model-invoke --print-effective-config` to debug resolution.

**Debug command**: `model-invoke --print-effective-config` outputs the merged config with source annotations (which layer each value came from).

**Source**: Hounfour RFC §6.1-6.3, proven in loa-finn PR #36.

### FR-2: Provider Abstraction — `model-invoke` + `cheval.py` (MUST)

Ship the Hounfour adapter as a framework primitive:

- **`model-invoke`**: Shell wrapper in `.claude/scripts/` that delegates to `cheval.py`. Thin dispatcher — `exec python3 .claude/adapters/cheval.py "$@"`.
- **`cheval.py`**: Python adapter core in `.claude/adapters/`. Handles config loading, variable interpolation (`{env:VAR}`, `{file:path}`), alias resolution, capability checking, request building (OpenAI-compatible wire format), response normalization, thinking trace extraction, and JSONL metering.

**Ownership**: Loa upstream owns `cheval.py` as the **reference adapter implementation**. loa-finn may wrap it (HTTP sidecar via `cheval_server.py`) but the core request/response translation lives upstream. Bug fixes and security patches to provider wire format handling are made in Loa, not in downstream forks. The extraction principle ("ports upstream, adapters in loa-finn") applies to *runtime infrastructure* (Redis, sidecar lifecycle, JWT auth) — not to the adapter itself.

**Execution modes**:
- `native_runtime`: Agent runs inside Claude Code. `model-invoke` is NOT called. SKILL.md is loaded directly.
- `remote_model`: Agent's persona is sent as system prompt to an HTTP-accessible model via `cheval.py`.

**The adapter is stateless** — it never executes tools. Tool-call loops are owned by the orchestrator (loa-finn in server mode, or the calling agent in CLI mode).

**Secret handling**:
- `{env:VAR}` interpolation is restricted to keys matching `^LOA_` or provider-specific `^(OPENAI|ANTHROPIC|MOONSHOT)_API_KEY$`. All other env vars are rejected.
- `{file:path}` is restricted to files under `.loa.config.d/` or paths explicitly allowlisted in config. Symlinks are never followed. File must be owned by current user with mode <= 0640.
- Auth headers are NEVER logged, even at debug level. Error messages redact any value that was sourced from `{env:}` or `{file:}`.
- Prompt/response content is NEVER written to the cost ledger. Only metadata (tokens, cost, timing, agent name) is recorded.

**Provider compatibility**: The "OpenAI-compatible wire format" is defined as the subset of the OpenAI Chat Completions API that `cheval.py` supports, NOT the full API surface. Specifically: `messages` array, `model`, `temperature`, `max_tokens`, `tools` (function calling), `tool_choice`, and `stream`. Each provider adapter includes a conformance test suite with golden request/response fixtures. MVP supports 2 verified providers (OpenAI, Anthropic). Additional providers require passing the conformance test suite before being added to defaults.

**Source**: Hounfour RFC §5.1-5.5, §7.1-7.2, proven in loa-finn PRs #36 and #39.

### FR-3: Skill Decomposition for Portability (MUST)

Decompose the 8 core agent skills into model-portable structure:

```
.claude/skills/<skill-name>/
├── SKILL.md              # Claude Code native_runtime entry point (unchanged)
├── persona.md            # Model-agnostic persona → system prompt for remote_model
├── evaluation-criteria.md # What this agent evaluates (optional)
└── output-schema.md      # Expected output format for validation (optional)
```

`remote_model` reads `persona.md` as system prompt + `output-schema.md` as formatting instruction. `native_runtime` uses `SKILL.md` which wraps everything. Zero breakage on the native path.

**8 core agents to decompose**:
1. `discovering-requirements` (plan-and-analyze)
2. `designing-architecture` (architect)
3. `planning-sprints` (sprint-plan)
4. `implementing-tasks` (implement) — `native_runtime` only
5. `reviewing-code` (review-sprint)
6. `auditing-security` (audit-sprint)
7. `translating-for-executives` (translate)
8. `riding-codebase` (ride) — `native_runtime` only

**Source**: Hounfour RFC §5.6, implemented in loa-finn PR #36 (16 persona.md + output-schema.md files).

### FR-4: Default Provider & Pricing Templates (MUST)

Ship sensible defaults that work out-of-the-box:

- `.claude/defaults/model-config.yaml`: Default provider registry (claude-code, openai, moonshot, qwen-local), default aliases, default agent bindings, default pricing
- Config schema validation via JSON Schema in `.claude/schemas/model-config.schema.json`

**Default agent bindings** (conservative profile — maximize quality):
```yaml
implementing-tasks:          { model: native, requires: { native_runtime: true } }
designing-architecture:      { model: native }
reviewing-code:              { model: reviewer, temperature: 0.3 }
flatline-challenger:         { model: reasoning, requires: { thinking_traces: required } }
translating-for-executives:  { model: cheap }
```

**Source**: Hounfour RFC Appendix A, proven in loa-finn.

### FR-5: Flatline Protocol Unification (SHOULD)

Refactor the Flatline Protocol to route all model calls through `model-invoke` / `cheval.py` instead of making direct API calls:

- `flatline-orchestrator.sh` calls `model-invoke` with agent name + prompt file
- `gpt-review-api.sh` calls `model-invoke` instead of direct `curl` to OpenAI
- `model-adapter.sh` (827 lines) becomes a thin compatibility shim that delegates to `model-invoke`, then is deprecated

This eliminates the duplicate model registry (bash associative arrays vs. YAML config), duplicate retry logic, and duplicate cost tracking.

**Source**: Hounfour RFC §14 Phase 1, proven in loa-finn PR #36.

### FR-6: Cost Ledger & `/cost-report` Command (SHOULD)

Implement framework-level cost tracking:

- Every `cheval.py` invocation appends one JSONL line to the cost ledger (default: `grimoires/loa/a2a/cost-ledger.jsonl`)
- Fields: `ts`, `trace_id`, `request_id`, `agent`, `provider`, `model`, `tokens_in`, `tokens_out`, `tokens_reasoning`, `latency_ms`, `cost_micro_usd`, `phase_id`, `sprint_id`
- `/cost-report` command reads the ledger and generates a markdown summary with per-agent, per-model, and per-provider breakdowns

**Concurrency safety**: Ledger writes use atomic append (write to temp file + `os.rename()` to final path with `.{pid}.tmp` suffix, then append to ledger under `fcntl.flock(LOCK_EX)` on Unix). On platforms without `flock`, fall back to per-process temp files merged by `/cost-report`. Corrupted lines (incomplete JSON) are silently skipped during reads with a warning counter.

**Cost calculation**:
- All costs are tracked in **micro-USD** (1 USD = 1,000,000 micro-USD) using integer arithmetic only — no floating point in the cost path. This matches loa-finn's proven approach.
- **Enforcement point**: Pre-call budget check (estimate based on `max_tokens` × output price + prompt token count × input price). Post-call reconciliation updates the actual cost. If post-call actual exceeds pre-call estimate by >20%, a warning is logged.
- **Retry accounting**: Each retry is a separate ledger entry with the same `trace_id` but different `request_id`. Budget enforcement counts all entries for a trace.
- **Missing usage fields**: If provider returns no token counts, cost is estimated from `max_tokens` config (worst case). A `usage_source: "estimated"` field is added to the ledger entry.
- **Unknown pricing**: If no pricing entry exists for a model, cost is recorded as `0` with `pricing_source: "unknown"`. A warning is logged. Budget enforcement treats unknown-cost calls as zero (permissive) — the alternative (blocking) would break new provider onboarding.

**Source**: Hounfour RFC §9, proven in loa-finn PRs #36 and #39.

### FR-7: Routing — Fallback & Downgrade Chains (SHOULD)

Config-driven routing for resilience and cost optimization:

- **Fallback** (availability): Provider is down → walk fallback chain, skip entries that don't satisfy agent's `requires` capabilities
- **Downgrade** (cost): Budget exceeded → walk downgrade chain to cheaper model
- **Health checks**: Provider-specific probes with circuit breaker (CLOSED → OPEN → HALF_OPEN)

Resolution algorithm is deterministic: config-driven, capability-filtered, no randomness.

**Source**: Hounfour RFC §6.4, proven in loa-finn PR #36 (`walkChain()` with cycle detection).

### FR-8: Skill Schema Update (MUST)

Update `.claude/schemas/skill-index.schema.json` to support alias-based model specification:

```json
"model": {
  "type": "string",
  "description": "Model alias or provider:model-id for this skill. Resolves through the Hounfour provider registry."
}
```

Remove the hardcoded `enum: ["sonnet", "opus", "haiku"]` — any configured alias or `provider:model-id` is valid.

**Source**: Hounfour RFC §5.4, current schema limitation.

## 5. Technical & Non-Functional Requirements

### NFR-1: Zero Breaking Changes on Native Path

All existing skills continue to work exactly as they do today when running in Claude Code (`native_runtime` mode). The `SKILL.md` files are unchanged. Model routing only activates when the resolved agent binding points to a `remote_model` provider.

### NFR-2: Python Dependency Management

`cheval.py` requires `httpx` and `pyyaml`. These are installed via `.claude/adapters/requirements.txt`. The adapter gracefully degrades to `urllib.request` (stdlib) if `httpx` is not available.

### NFR-3: Three-Zone Model Compliance

- **System Zone** (`.claude/`): Config schema, default templates, adapters, `model-invoke` wrapper — all framework-managed
- **State Zone** (`grimoires/`): Cost ledger, metering data — user-writable
- **App Zone** (`src/`, `lib/`): Unaffected

### NFR-4: Backward Compatibility

- Existing `.loa.config.yaml` files without Hounfour sections continue to work (defaults applied)
- `model-adapter.sh` remains as a compatibility shim during transition
- Skills without `persona.md` default to `SKILL.md` as system prompt for `remote_model`

### NFR-5: Performance

- `cheval.py` config loading: < 100ms (cached after first load)
- No additional latency on `native_runtime` path (model routing is a config lookup, not an API call)
- Cost ledger append: < 10ms per entry (JSONL append with `flock` — see FR-6 concurrency safety)

## 6. Scope & Prioritization

### MVP (This Cycle)

1. **Configuration schema v2** — Hounfour config sections in `.loa.config.yaml` (FR-1)
2. **`cheval.py` + `model-invoke`** — Provider adapter shipped in `.claude/adapters/` (FR-2)
3. **Skill decomposition** — `persona.md` for 8 core agents (FR-3)
4. **Default templates** — `.claude/defaults/model-config.yaml` (FR-4)
5. **Skill schema update** — Remove hardcoded model enum (FR-8)

### Stretch

6. **Flatline unification** — Route Flatline through `model-invoke` (FR-5)
7. **Cost ledger** — JSONL metering + `/cost-report` (FR-6)
8. **Routing chains** — Fallback + downgrade + health checks (FR-7)

### Out of Scope

- **loa-finn runtime changes** — loa-finn already has its Hounfour implementation; this PRD is about upstream extraction only
- **Arrakis distribution layer** — Tenant isolation, JWT auth, per-NFT routing remain in arrakis
- **Redis-backed state** — Server-side scaling concerns stay in loa-finn
- **Streaming support** — SSE/streaming is a runtime concern, not a framework concern
- **NativeRuntimeAdapter** — Claude Code as `remote_model` via Anthropic API remains in loa-finn

## 7. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Python not available on all systems | Low | High | `cheval.py` falls back to stdlib `urllib`; document Python 3.8+ requirement |
| Config schema breaks existing `.loa.config.yaml` | Low | High | New sections are additive; existing configs work unchanged via defaults |
| `persona.md` quality varies across models | Medium | Medium | Ship fidelity test fixtures (golden inputs with structural assertions) per Bridgebuilder Finding #7 |
| Flatline refactor breaks cross-model review | Medium | High | Keep `model-adapter.sh` as shim during transition; feature flag for new path |
| `model-invoke` adds latency to Flatline | Low | Low | Python cold start ~200ms; config cached after first load |

### Dependencies

| Dependency | Status | Notes |
|-----------|--------|-------|
| Hounfour RFC (loa-finn #31) | Complete (Phases 0-5) | 40,170 lines across 4 PRs |
| `cheval.py` reference implementation | Available | loa-finn `src/hounfour/` + `.claude/adapters/cheval.py` |
| Persona files (8 agents) | Available | loa-finn `.claude/skills/*/persona.md` |
| Config schema | Available | Hounfour RFC §6.3 |
| Skill index schema | In `.claude/schemas/` | Needs model enum update |

## 8. Implementation Hints

### Extraction Principle: Ports Go Upstream, Adapters Stay in loa-finn

The key design principle from the RFC handoff: Loa upstream gets the **interfaces and routing logic**. loa-finn keeps the **runtime implementations**.

| Goes to Loa upstream | Stays in loa-finn |
|---------------------|-------------------|
| `cheval.py` reference adapter (owned upstream) | `cheval_server.py` HTTP sidecar wrapper |
| `ModelPort` interface (as documentation) | `NativeRuntimeAdapter` implementation |
| `BudgetEnforcer` interface | `RedisBudgetEnforcer` implementation |
| `ProviderRegistry` + routing logic | Redis state backend |
| `walkChain()` fallback logic | Sidecar manager |
| `EnsembleOrchestrator` pattern | `UsageReporter` (arrakis-specific) |
| `calculateCostMicro()` integer arithmetic | JWT auth (arrakis-specific) |
| `HounfourError` types | BYOK proxy client |
| Persona loader | Gateway/stream-bridge |
| Provider conformance test fixtures | Streaming transport (SSE consumer) |

### Key Files to Create

| File | Description |
|------|------------|
| `.claude/adapters/cheval.py` | Python adapter core (extract from loa-finn) |
| `.claude/adapters/requirements.txt` | `httpx`, `pyyaml` |
| `.claude/scripts/model-invoke` | Shell wrapper → `exec python3 .claude/adapters/cheval.py "$@"` |
| `.claude/defaults/model-config.yaml` | Default provider/pricing/agent templates |
| `.claude/schemas/model-config.schema.json` | JSON Schema for config validation |
| `.claude/protocols/model-routing.md` | Human-readable routing spec |
| `.claude/scripts/cost-report.sh` | JSONL ledger → markdown summary |

### Key Files to Modify

| File | Change |
|------|--------|
| `.loa.config.yaml.example` | Add Hounfour config sections |
| `.claude/schemas/skill-index.schema.json` | Replace model enum with string |
| `.claude/scripts/flatline-orchestrator.sh` | Route through `model-invoke` |
| `.claude/scripts/gpt-review-api.sh` | Route through `model-invoke` |
| `.claude/scripts/model-adapter.sh` | Become shim → `model-invoke` |
| `.claude/skills/*/` (8 agents) | Add `persona.md` + `output-schema.md` |

### Source Files in loa-finn

All extraction source code lives at `/home/merlin/Documents/thj/code/loa-finn/src/hounfour/`:

| loa-finn Source | What to Extract |
|----------------|-----------------|
| `registry.ts` | `ProviderRegistry`, alias resolution, capability validation |
| `router.ts` | `walkChain()` fallback/downgrade, `resolveExecution()` |
| `types.ts` | `ModelPortBase`, `CompletionRequest/Result`, `ModelCapabilities` |
| `budget.ts` | `BudgetEnforcer` interface |
| `health.ts` | Circuit breaker port + health check contract |
| `pricing.ts` | `calculateCostMicro()` integer arithmetic |
| `ensemble.ts` | `EnsembleOrchestrator` with merge strategies |
| `pool-registry.ts` | `PoolRegistry` with tier authorization |
| `errors.ts` | `HounfourError`, error code union type |

---

*Generated from loa-finn Issue #31 (Hounfour RFC) handoff directions via /plan-and-analyze. Codebase grounded against model-adapter.sh (827 lines), gpt-review-api.sh (850 lines), flatline-orchestrator.sh (929 lines), skill-index.schema.json, and loa-finn Hounfour source (229 files, 40,170 lines).*
