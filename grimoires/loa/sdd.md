# SDD: Hounfour Upstream Extraction — Multi-Model Provider Abstraction

**Version**: 1.1.0
**Status**: Draft (Flatline-reviewed)
**Author**: Architecture Phase (architect)
**PRD**: grimoires/loa/prd.md (v1.1.0)
**Issue**: [loa-finn #31](https://github.com/0xHoneyJar/loa-finn/issues/31) (upstream extraction)
**Date**: 2026-02-10

---

## 1. Executive Summary

This SDD defines the architecture for extracting Hounfour multi-model provider abstractions from loa-finn into the upstream Loa framework. The design introduces three new subsystems — a Python provider adapter (`cheval.py`), a YAML configuration schema for model routing, and a skill decomposition pattern (`persona.md`) — while preserving zero breaking changes on the existing `native_runtime` path.

The architecture follows the hexagonal (ports and adapters) pattern: Loa owns the ports (interfaces, schemas, routing logic, reference adapter) while loa-finn and other runtimes implement the adapters (Redis state, sidecar lifecycle, JWT auth). All model API calls flow through a single `model-invoke` entry point, eliminating the current ad-hoc dual-path integration.

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Skill Invocation Layer                       │
│  /flatline-review, /gpt-review, /bridgebuilder, /architect...  │
│  Skills reference agents by name (e.g., "reviewing-code")       │
└──────────────────────────┬──────────────────────────────────────┘
                           │ agent name + prompt
┌──────────────────────────▼──────────────────────────────────────┐
│                    Orchestration Layer                           │
│  flatline-orchestrator.sh, gpt-review-api.sh                    │
│  Calls: model-invoke --agent <name> --input <file>              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ shell exec
┌──────────────────────────▼──────────────────────────────────────┐
│                   model-invoke (shell wrapper)                   │
│  exec python3 .claude/adapters/cheval.py "$@"                   │
└──────────────────────────┬──────────────────────────────────────┘
                           │ python
┌──────────────────────────▼──────────────────────────────────────┐
│                      cheval.py (Python Adapter)                  │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ Config   │  │ Routing  │  │ Provider │  │ Metering │       │
│  │ Loader   │  │ Engine   │  │ Adapters │  │ (JSONL)  │       │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘       │
│                                                                  │
│  Config Loader:  Merge defaults + project + env + CLI           │
│  Routing Engine: Resolve alias → provider:model, walk chains    │
│  Provider Adapters: OpenAI, Anthropic (conformance-tested)      │
│  Metering: Append to cost-ledger.jsonl with flock               │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTPS
┌──────────────────────────▼──────────────────────────────────────┐
│                   Provider API Layer                              │
│  OpenAI: POST /v1/chat/completions                              │
│  Anthropic: POST /v1/messages                                    │
│  OpenAI-compatible: POST /v1/chat/completions (Moonshot, vLLM)  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Execution Mode Decision

```
Agent invoked (e.g., "reviewing-code")
    │
    ▼
Read agent binding from config
    │
    ├── model: "native" ──────────► native_runtime path
    │                                 (SKILL.md loaded directly by Claude Code)
    │                                 (model-invoke NOT called)
    │                                 (ZERO changes to current behavior)
    │
    └── model: "<alias>" ─────────► remote_model path
          │                           (resolve alias → provider:model-id)
          │                           (load persona.md as system prompt)
          │                           (call cheval.py)
          │
          ▼
        model-invoke --agent reviewing-code --input review.md
```

### 2.3 Compatibility Guarantees

**Zero-breaking-change contract scope**: The `native_runtime` path (SKILL.md loaded directly by Claude Code) is guaranteed unchanged. This means:
1. Skills bound to `model: native` in agent config are NEVER routed through `model-invoke`
2. `model-invoke` includes a hard guard: if the resolved agent has `requires.native_runtime: true`, invocation fails with exit code 2 (`INVALID_CONFIG`) rather than silently routing to a remote model
3. `native` is a reserved alias that always resolves to Claude Code session — it cannot be reassigned in config

**Compatibility matrix** (migration regression tests):

| Skill | Pre-Migration Path | Post-Migration Path | Test |
|-------|-------------------|-------------------|------|
| `/implement` | SKILL.md (Claude Code) | SKILL.md (Claude Code) | `native_runtime` guard prevents `model-invoke` |
| `/ride` | SKILL.md (Claude Code) | SKILL.md (Claude Code) | Same as above |
| `/flatline-review` | `model-adapter.sh` → curl | `model-invoke` → cheval.py | Golden fixture comparison |
| `/gpt-review` | `gpt-review-api.sh` → curl | `model-invoke` → cheval.py | Golden fixture comparison |

**Migration linter**: `model-invoke --validate-bindings` checks all agent names referenced by scripts exist in config and have valid model bindings. Runs as part of the test suite and can be invoked manually.

### 2.4 Component Ownership

| Component | Owner | Location |
|-----------|-------|----------|
| Config schema + defaults | Loa upstream | `.claude/defaults/`, `.claude/schemas/` |
| `cheval.py` reference adapter | Loa upstream | `.claude/adapters/cheval.py` |
| `model-invoke` wrapper | Loa upstream | `.claude/scripts/model-invoke` |
| `persona.md` + `output-schema.md` | Loa upstream (per skill) | `.claude/skills/*/` |
| Cost ledger | Per-project | `grimoires/loa/a2a/cost-ledger.jsonl` |
| `model-adapter.sh` (deprecated) | Loa upstream (shim) | `.claude/scripts/model-adapter.sh` |
| `cheval_server.py` (HTTP sidecar) | loa-finn | loa-finn repo |
| Redis state backend | loa-finn | loa-finn repo |
| JWT/tenant auth | arrakis | arrakis repo |

---

## 3. Technology Stack

| Layer | Technology | Justification |
|-------|-----------|---------------|
| Adapter runtime | Python 3.8+ | Already required by NotebookLM integration; `cheval.py` needs `httpx` for HTTP/2 and connection pooling |
| Adapter fallback | `urllib.request` (stdlib) | Zero-dep mode when `httpx` not installed |
| Config format | YAML (via `yq` or `pyyaml`) | Consistent with existing `.loa.config.yaml`; `yq` already required (v4+) |
| Config validation | JSON Schema | Consistent with existing `.claude/schemas/*.schema.json` |
| Cost ledger | JSONL (append-only) | Proven in loa-finn; simple, greppable, tooling-friendly |
| Shell wrapper | Bash 4.0+ | Consistent with existing `.claude/scripts/`; associative arrays for shim |
| Concurrency control | `fcntl.flock` (Python) | POSIX-standard, available on all target platforms (Linux, macOS) |

### 3.1 Python Dependencies

```
# .claude/adapters/requirements.txt
httpx>=0.24.0    # HTTP/2, connection pooling, timeout control
pyyaml>=6.0      # Config loading (also used by yq)
```

**Graceful degradation**: If `httpx` is not installed, `cheval.py` falls back to `urllib.request` with reduced functionality (no HTTP/2, no connection pooling, basic timeout handling). A startup warning is logged.

---

## 4. Component Design

### 4.1 Configuration System

#### 4.1.1 Config Merge Pipeline

```
┌────────────────────┐
│ System Zone Defaults│  .claude/defaults/model-config.yaml
│ (lowest precedence) │  Ships with framework, never edited by user
└─────────┬──────────┘
          │ merge (deep)
┌─────────▼──────────┐
│ Project Config      │  .loa.config.yaml (hounfour: section)
│                     │  User-controlled, per-project
└─────────┬──────────┘
          │ merge (deep)
┌─────────▼──────────┐
│ Environment Vars    │  LOA_MODEL, LOA_PROVIDER_*_KEY only
│ (opt-in, limited)   │  Cannot override routing/pricing/bindings
└─────────┬──────────┘
          │ override
┌─────────▼──────────┐
│ CLI Arguments       │  --model, --agent, --timeout
│ (highest precedence)│  Per-invocation overrides
└────────────────────┘
```

#### 4.1.2 Config Schema

```yaml
# .loa.config.yaml (new hounfour: section)
hounfour:
  # Provider registry
  providers:
    openai:
      type: openai                    # openai | anthropic | openai_compat
      endpoint: "https://api.openai.com/v1"
      auth: "{env:OPENAI_API_KEY}"
      models:
        gpt-5.2:
          capabilities: [chat, tools, function_calling]
          context_window: 128000
          pricing: { input_per_mtok: 10000, output_per_mtok: 30000 }  # micro-USD
        gpt-5.2-codex:
          capabilities: [chat, tools, function_calling, code]
          context_window: 200000
          pricing: { input_per_mtok: 15000, output_per_mtok: 60000 }

    anthropic:
      type: anthropic
      endpoint: "https://api.anthropic.com/v1"
      auth: "{env:ANTHROPIC_API_KEY}"
      models:
        claude-opus-4-6:
          capabilities: [chat, tools, function_calling, thinking_traces]
          context_window: 200000
          pricing: { input_per_mtok: 5000, output_per_mtok: 25000 }

  # Aliases (short names → provider:model)
  aliases:
    native: "claude-code:session"       # Claude Code native runtime
    reviewer: "openai:gpt-5.2"
    reasoning: "openai:gpt-5.2"         # Placeholder until moonshot configured
    cheap: "openai:gpt-5.2"             # Placeholder until qwen configured
    opus: "anthropic:claude-opus-4-6"

  # Agent bindings (agent name → model + requirements)
  agents:
    implementing-tasks:
      model: native
      requires: { native_runtime: true }
    designing-architecture:
      model: native
    reviewing-code:
      model: reviewer
      temperature: 0.3
    auditing-security:
      model: native
    planning-sprints:
      model: native
    discovering-requirements:
      model: native
    translating-for-executives:
      model: cheap
    riding-codebase:
      model: native
      requires: { native_runtime: true }
    flatline-reviewer:
      model: reviewer
    flatline-skeptic:
      model: reasoning
      requires: { thinking_traces: preferred }

  # Routing
  routing:
    fallback:
      openai: [anthropic]               # If OpenAI down, try Anthropic
      anthropic: [openai]               # If Anthropic down, try OpenAI
    downgrade:
      reviewer: [cheap]                  # If budget exceeded, downgrade

  # Metering
  metering:
    enabled: true
    ledger_path: "grimoires/loa/a2a/cost-ledger.jsonl"
    budget:
      daily_micro_usd: 500000000         # $500/day default (effectively unlimited)
      warn_at_percent: 80
      on_exceeded: downgrade             # downgrade | block | warn
```

#### 4.1.3 Secret Handling

| Interpolation | Allowed Sources | Validation |
|--------------|-----------------|------------|
| `{env:VAR}` | `^LOA_.*`, `^OPENAI_API_KEY$`, `^ANTHROPIC_API_KEY$`, `^MOONSHOT_API_KEY$` | Regex allowlist; reject all others |
| `{file:path}` | Files under `.loa.config.d/` or paths in `hounfour.secret_paths` allowlist | No symlinks, owner match, mode ≤ 0640 |

**Redaction rules**:
- Values sourced from `{env:}` or `{file:}` are tagged as `_REDACTED_` in all log output
- Error messages containing auth headers show `Authorization: Bearer ***REDACTED***`
- Cost ledger NEVER contains prompt text, response text, or auth values

### 4.2 cheval.py — Provider Adapter

#### 4.2.1 Module Structure

```
.claude/adapters/
├── pyproject.toml           # Package metadata (loa_cheval), version, entry points
├── cheval.py                # CLI entry point (exec wrapper)
├── loa_cheval/
│   ├── __init__.py          # Public API surface (re-exports)
│   ├── __version__.py       # Semantic version (e.g., "1.0.0")
│   ├── types.py             # CompletionRequest, CompletionResult, Usage dataclasses
│   ├── providers/
│   │   ├── __init__.py
│   │   ├── base.py          # ProviderAdapter abstract base
│   │   ├── openai_adapter.py  # OpenAI + OpenAI-compatible
│   │   └── anthropic_adapter.py # Anthropic Messages API
│   ├── config/
│   │   ├── __init__.py
│   │   ├── loader.py        # Config merge pipeline
│   │   ├── interpolation.py # {env:VAR}, {file:path}, {cmd:} resolution
│   │   └── validation.py    # JSON Schema validation
│   ├── routing/
│   │   ├── __init__.py
│   │   ├── resolver.py      # Alias resolution + agent binding lookup
│   │   └── chains.py        # Fallback + downgrade chain walker
│   └── metering/
│       ├── __init__.py
│       ├── ledger.py        # JSONL append with flock + daily summary
│       └── pricing.py       # Integer micro-USD cost calculation
└── tests/
    ├── fixtures/             # Golden request/response per provider
    ├── test_config.py
    ├── test_routing.py
    ├── test_pricing.py
    ├── test_providers.py     # Contract tests (schema validation, not just fixtures)
    └── test_redaction.py     # Forced-failure secret leakage tests
```

#### 4.2.2 CLI Interface

```bash
# Basic invocation
model-invoke --agent reviewing-code --input review-content.md

# With overrides
model-invoke --agent reviewing-code --input review-content.md --model openai:gpt-5.2-codex

# System prompt from persona.md
model-invoke --agent reviewing-code --system .claude/skills/reviewing-code/persona.md --input review-content.md

# Effective config debug
model-invoke --print-effective-config

# Dry run (validate config, print resolved model, don't call API)
model-invoke --agent reviewing-code --dry-run
```

**I/O Contract**:
- **stdout**: Model response content ONLY (raw text or JSON depending on `--output-format`). No log messages, no metadata.
- **stderr**: All diagnostic output (logs, warnings, errors). When `--json-errors` is set (default for orchestrator callers), errors are JSON:
  ```json
  {"error": true, "code": "RATE_LIMITED", "provider": "openai", "message": "429 Too Many Requests", "retries_left": 2, "attempt": 1}
  ```
- **Exit code + stderr JSON** together form the error contract. Exit code for quick shell checks, JSON for programmatic handling.

**Error Taxonomy** (stderr JSON `code` field):

| Code | Category | Exit Code | Retryable |
|------|----------|-----------|-----------|
| `SUCCESS` | — | 0 | — |
| `API_ERROR` | Transport | 1 | Yes |
| `RATE_LIMITED` | Transport | 1 | Yes (backoff) |
| `PROVIDER_UNAVAILABLE` | Transport | 1 | Yes (fallback) |
| `INVALID_INPUT` | User | 2 | No |
| `INVALID_CONFIG` | User | 2 | No |
| `TIMEOUT` | Transport | 3 | Yes |
| `MISSING_API_KEY` | Auth | 4 | No |
| `INVALID_RESPONSE` | Provider | 5 | Yes (once) |
| `BUDGET_EXCEEDED` | Policy | 6 | No |
| `CONTEXT_TOO_LARGE` | User | 7 | No (truncate input) |

**Exit codes** (compatible with existing `model-adapter.sh`, extended):

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | API error (retries exhausted) |
| 2 | Invalid input / config |
| 3 | Timeout |
| 4 | Missing API key |
| 5 | Invalid response format |
| 6 | Budget exceeded |
| 7 | Context too large (input exceeds model context_window) |

#### 4.2.3 Provider Adapter Interface

```python
class ProviderAdapter(ABC):
    """Base class for model provider adapters."""

    @abstractmethod
    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Send completion request, return normalized result."""

    @abstractmethod
    def validate_config(self, provider_config: dict) -> list[str]:
        """Validate provider-specific config. Return list of errors."""

    @abstractmethod
    def health_check(self, provider_config: dict) -> bool:
        """Quick health probe. Returns True if provider is reachable."""
```

```python
@dataclass
class CompletionRequest:
    messages: list[dict]           # [{"role": "system"|"user"|"assistant", "content": str}]
    model: str                     # Provider-specific model ID
    temperature: float = 0.7
    max_tokens: int = 4096
    tools: list[dict] | None = None
    tool_choice: str | None = None
    metadata: dict | None = None   # agent, trace_id, sprint_id (not sent to provider)

@dataclass
class CompletionResult:
    content: str                   # Model response text
    tool_calls: list[dict] | None  # Normalized tool call format
    thinking: str | None           # Reasoning/thinking trace (if provider supports)
    usage: Usage                   # Token counts
    model: str                     # Actual model used (may differ from requested)
    latency_ms: int
    provider: str

@dataclass
class Usage:
    input_tokens: int
    output_tokens: int
    reasoning_tokens: int = 0
    source: str = "actual"         # "actual" | "estimated"
```

#### 4.2.4 Context Window Enforcement

Pre-call token estimation prevents oversized requests from failing at the provider:

```python
def estimate_tokens(messages: list[dict]) -> int:
    """Best-effort token estimation. Provider-specific tokenizer preferred, fallback to heuristic."""
    # Priority 1: tiktoken (if installed) for OpenAI models
    # Priority 2: anthropic tokenizer (if installed) for Anthropic models
    # Priority 3: Heuristic: len(text) / 3.5 (conservative estimate for English)
    ...

def enforce_context_window(request: CompletionRequest, model_config: dict) -> CompletionRequest:
    """Check input fits within model context window. Raises ContextTooLargeError if not."""
    max_tokens = model_config.get("context_window", 128000)
    reserved_output = request.max_tokens  # Reserve space for response
    available = max_tokens - reserved_output

    estimated = estimate_tokens(request.messages)
    if estimated > available:
        raise ContextTooLargeError(
            f"Input ~{estimated} tokens exceeds available {available} tokens "
            f"(context_window={max_tokens}, reserved_output={reserved_output})"
        )
    return request
```

**Failure mode**: `ContextTooLargeError` → exit code 7. Callers (orchestrators) are responsible for truncation or chunking strategies.

#### 4.2.5 Request/Response Normalization

The canonical response schema is versioned (`schema_version: 1`) and validated by JSON Schema (`model-response.schema.json`). All provider adapters normalize responses to this schema before returning.

| Provider | Request Transform | Response Transform |
|----------|------------------|-------------------|
| OpenAI | Pass-through (native format) | Extract `choices[0].message.content`, `tool_calls`, `usage` |
| Anthropic | `messages` → Anthropic format, `system` extracted from messages | Extract `content[0].text`, `tool_use` blocks, `usage`, `thinking` blocks |
| OpenAI-compatible | Same as OpenAI | Same as OpenAI + handle missing fields gracefully |

**Tool call canonical format** (normalized from provider-specific formats):

```json
{
  "id": "call_abc123",
  "function": { "name": "search", "arguments": "{\"query\": \"...\"}" },
  "type": "function"
}
```

**Feature support matrix** (behavior when unsupported):

| Feature | OpenAI | Anthropic | OpenAI-compat | When Unsupported |
|---------|--------|-----------|---------------|-----------------|
| `tools` | ✓ | ✓ | Varies | Fail with `INVALID_INPUT` if agent requires tools |
| `function_calling` | ✓ | ✓ | Varies | Same as tools |
| `thinking_traces` | ✗ | ✓ | ✗ | `CompletionResult.thinking = None` (degrade silently) |
| `max_tokens` | ✓ | ✓ | ✓ | Use provider default |

**Contract tests**: Each provider adapter has contract tests that validate output against the canonical JSON Schema, not just golden fixture byte-equality. This catches provider API drift that changes structure but not content.

#### 4.2.5 Retry Logic

```python
def invoke_with_retry(adapter, request, config, ledger_path):
    max_retries = config.get("max_retries", 3)
    max_total_attempts = config.get("max_total_attempts", 6)  # Global hard cap
    max_provider_switches = config.get("max_provider_switches", 2)
    base_delay = 1.0  # seconds

    total_attempts = 0
    provider_switches = 0

    for attempt in range(max_retries + 1):
        # Global attempt budget check
        total_attempts += 1
        if total_attempts > max_total_attempts:
            raise RetriesExhaustedError(
                f"Global attempt limit ({max_total_attempts}) reached"
            )

        # Budget check BEFORE each attempt
        budget = check_budget(request.metadata["agent"], config, ledger_path)
        if budget == BudgetStatus.BLOCK:
            raise BudgetExceededError("Daily budget exceeded")

        # Circuit breaker check
        if get_circuit_state(adapter.provider) == CircuitState.OPEN:
            # Skip to fallback without counting as a retry
            fallback = resolve_fallback(request.metadata["agent"], config)
            if fallback and provider_switches < max_provider_switches:
                provider_switches += 1
                adapter = get_adapter(fallback.provider)
                request.model = fallback.model_id
                continue
            raise ProviderUnavailableError(f"Circuit open for {adapter.provider}")

        try:
            result = adapter.complete(request)
            # Post-call cost reconciliation
            record_cost(result.usage, config, ledger_path)
            return result
        except RateLimitError:
            record_failed_attempt(adapter.provider)
            delay = base_delay * (2 ** attempt) + random.uniform(0, 1)
            time.sleep(delay)
        except ProviderUnavailableError:
            record_failed_attempt(adapter.provider)
            fallback = resolve_fallback(request.metadata["agent"], config)
            if fallback and provider_switches < max_provider_switches:
                provider_switches += 1
                adapter = get_adapter(fallback.provider)
                request.model = fallback.model_id
                continue
            raise
    raise RetriesExhaustedError(f"Failed after {total_attempts} attempts")
```

#### 4.2.6 Circuit Breaker State Machine

Each provider has an independent circuit breaker stored in `.run/circuit-breaker-{provider}.json`:

```
CLOSED ──[failure_count >= threshold]──► OPEN
  ▲                                        │
  │                                    [reset_timeout expires]
  │                                        │
  └───[probe succeeds]──── HALF_OPEN ◄────┘
                              │
                          [probe fails]
                              │
                              ▼
                            OPEN (reset timer restarts)
```

**Configuration**:

```yaml
hounfour:
  routing:
    circuit_breaker:
      failure_threshold: 5        # Consecutive failures to trip
      reset_timeout_seconds: 60   # Time in OPEN before probing
      half_open_max_probes: 1     # Concurrent probes in HALF_OPEN
      count_window_seconds: 300   # Rolling window for failure count
```

**State file format** (`.run/circuit-breaker-openai.json`):

```json
{
  "provider": "openai",
  "state": "CLOSED",
  "failure_count": 0,
  "last_failure_ts": null,
  "opened_at": null,
  "half_open_probes": 0
}
```

**Interaction with retries and fallback**: Circuit breaker is checked BEFORE retry attempts. If a provider is OPEN, it is skipped immediately and the fallback chain is consulted. A HALF_OPEN provider accepts one probe request; if the probe succeeds, the breaker resets to CLOSED; if it fails, it returns to OPEN. Retries only occur against providers in CLOSED or HALF_OPEN state.

#### 4.2.7 Global Attempt Budget

To prevent cost amplification from retry + fallback cascading:

```python
MAX_TOTAL_ATTEMPTS = 6  # Hard cap across all providers per invocation
MAX_PROVIDER_SWITCHES = 2  # Maximum fallback chain depth per invocation

# Budget check occurs BEFORE each attempt
# Post-call reconciliation occurs AFTER each attempt (success or failure)
```

Each `model-invoke` invocation tracks a running attempt counter. When `MAX_TOTAL_ATTEMPTS` is reached, the invocation fails with exit code 1 regardless of remaining fallback options.

### 4.3 Skill Decomposition

#### 4.3.1 File Structure Per Skill

```
.claude/skills/reviewing-code/
├── SKILL.md              # Existing (unchanged) — Claude Code native_runtime
├── persona.md            # NEW — Model-agnostic system prompt
├── output-schema.md      # NEW — Expected output format
├── evaluation-criteria.md # NEW — What this agent evaluates
├── index.yaml            # Existing — Updated model field
└── resources/            # Existing (unchanged)
```

#### 4.3.2 persona.md Contract

The `persona.md` file serves as the system prompt when an agent runs via `remote_model`. It must:

1. **Define role and expertise** — Who is this agent?
2. **Specify task structure** — What are the inputs, what are the outputs?
3. **Set quality bar** — What are the evaluation criteria?
4. **Reference output-schema.md** — How should the response be formatted?
5. **Be model-agnostic** — No Claude-specific or GPT-specific instructions

**Example** (`reviewing-code/persona.md`):

```markdown
# Senior Technical Reviewer

You are a senior technical lead reviewing sprint implementation.

## Your Responsibilities
- Verify acceptance criteria are met
- Review code quality and maintainability
- Check test coverage and edge cases
- Identify security vulnerabilities
- Verify architecture alignment

## Input
You will receive an implementation report and relevant code files.

## Output
Follow the output format in output-schema.md. Your verdict is either:
- "All good" — Implementation meets all standards
- Detailed feedback — Specific issues with file paths and line numbers
```

#### 4.3.3 Portability Classification

| Agent | native_runtime | remote_model | Notes |
|-------|---------------|-------------|-------|
| implementing-tasks | Required | Not portable | Needs Write/Edit/Bash tools, session state |
| riding-codebase | Required | Not portable | Needs Glob/Grep/Read extensively |
| designing-architecture | Default | Portable | System prompt sufficient |
| planning-sprints | Default | Portable | System prompt sufficient |
| discovering-requirements | Default | Portable | System prompt sufficient |
| reviewing-code | Default | Portable | Primary Flatline consumer |
| auditing-security | Default | Portable | Primary Flatline consumer |
| translating-for-executives | Default | Portable | No tool access needed |

### 4.4 Flatline Protocol Integration

#### 4.4.1 Current Call Path (Before)

```
flatline-orchestrator.sh
  └── model-adapter.sh --model gpt-5.2 --mode review --input doc.md
        └── curl https://api.openai.com/v1/chat/completions ...

  └── model-adapter.sh --model opus --mode skeptic --input doc.md
        └── curl https://api.anthropic.com/v1/messages ...
```

#### 4.4.2 New Call Path (After)

```
flatline-orchestrator.sh
  └── model-invoke --agent flatline-reviewer --input doc.md
        └── cheval.py (resolves "flatline-reviewer" → openai:gpt-5.2)
              └── httpx POST https://api.openai.com/v1/chat/completions

  └── model-invoke --agent flatline-skeptic --input doc.md
        └── cheval.py (resolves "flatline-skeptic" → openai:gpt-5.2)
              └── httpx POST https://api.openai.com/v1/chat/completions
```

#### 4.4.3 Compatibility Shim

During transition, `model-adapter.sh` is preserved as a shim:

```bash
# model-adapter.sh (shim version)
# Translates legacy --model/--mode flags to model-invoke --agent format

AGENT_MAP=(
    ["review"]="flatline-reviewer"
    ["skeptic"]="flatline-skeptic"
    ["score"]="flatline-scorer"
    ["dissent"]="flatline-dissenter"
)

agent="${AGENT_MAP[$mode]}"
exec .claude/scripts/model-invoke --agent "$agent" --input "$input" "$@"
```

### 4.5 Cost Ledger

#### 4.5.1 JSONL Entry Format

```json
{
  "ts": "2026-02-10T15:30:00.000Z",
  "trace_id": "tr-abc123",
  "request_id": "req-def456",
  "agent": "reviewing-code",
  "provider": "openai",
  "model": "gpt-5.2",
  "tokens_in": 4200,
  "tokens_out": 1800,
  "tokens_reasoning": 0,
  "latency_ms": 3200,
  "cost_micro_usd": 94000,
  "usage_source": "actual",
  "pricing_source": "config",
  "phase_id": "flatline_prd",
  "sprint_id": null,
  "attempt": 1
}
```

#### 4.5.2 Atomic Write Protocol

```python
def append_ledger(entry: dict, ledger_path: str):
    """Append a single JSONL line with concurrency safety."""
    line = json.dumps(entry, separators=(",", ":")) + "\n"
    encoded = line.encode("utf-8")

    fd = os.open(ledger_path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        os.write(fd, encoded)
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
```

#### 4.5.3 Budget Enforcement

```python
def check_budget(agent: str, config: dict, ledger_path: str) -> BudgetStatus:
    """Pre-call budget check. Returns ALLOW, WARN, DOWNGRADE, or BLOCK.

    Uses an atomic daily summary file for O(1) reads instead of scanning
    the full JSONL ledger. The summary is updated atomically on each append.
    """
    daily_limit = config["metering"]["budget"]["daily_micro_usd"]
    warn_pct = config["metering"]["budget"]["warn_at_percent"]

    # Read daily summary (O(1)) instead of scanning ledger (O(n))
    spent = read_daily_spend(ledger_path)  # Reads .daily-spend-{date}.json

    if spent >= daily_limit:
        action = config["metering"]["budget"]["on_exceeded"]
        if action == "block":
            return BudgetStatus.BLOCK
        elif action == "downgrade":
            return BudgetStatus.DOWNGRADE
        return BudgetStatus.WARN
    elif spent >= daily_limit * warn_pct / 100:
        return BudgetStatus.WARN
    return BudgetStatus.ALLOW

def update_daily_spend(entry_cost_micro: int, ledger_path: str):
    """Atomically update daily spend counter. Called after each ledger append.

    Uses flock-protected read-modify-write on a per-day summary file.
    File: {ledger_dir}/.daily-spend-{YYYY-MM-DD}.json
    Format: {"date": "2026-02-10", "total_micro_usd": 1234567, "entry_count": 42}
    """
    today = datetime.utcnow().strftime("%Y-%m-%d")
    summary_path = os.path.join(os.path.dirname(ledger_path), f".daily-spend-{today}.json")

    fd = os.open(summary_path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        data = json.loads(os.read(fd, 4096) or '{"total_micro_usd": 0, "entry_count": 0}')
        data["date"] = today
        data["total_micro_usd"] = data.get("total_micro_usd", 0) + entry_cost_micro
        data["entry_count"] = data.get("entry_count", 0) + 1
        os.lseek(fd, 0, os.SEEK_SET)
        os.ftruncate(fd, 0)
        os.write(fd, json.dumps(data).encode("utf-8"))
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
```

**Budget enforcement mode**: Budget is **best-effort** under concurrent invocations. The pre-call check uses the summary counter (fast O(1)), but parallel invocations may pass the check simultaneously before either records cost. Expected overshoot is bounded by `MAX_TOTAL_ATTEMPTS × max_cost_per_call` — documented in operational runbook. For strict enforcement in CI, use `on_exceeded: block` with a pre-job budget reset.

---

## 5. Data Architecture

### 5.1 Configuration Files (Read-Only at Runtime)

| File | Zone | Format | Purpose |
|------|------|--------|---------|
| `.claude/defaults/model-config.yaml` | System | YAML | Framework defaults |
| `.claude/schemas/model-config.schema.json` | System | JSON Schema | Config validation |
| `.claude/schemas/skill-index.schema.json` | System | JSON Schema | Skill definition (updated) |
| `.loa.config.yaml` | Project | YAML | User overrides |

### 5.2 Runtime State (Written During Execution)

| File | Zone | Format | Purpose |
|------|------|--------|---------|
| `grimoires/loa/a2a/cost-ledger.jsonl` | State | JSONL | Cost tracking |
| `.run/circuit-breaker-*.json` | Ephemeral | JSON | Circuit breaker state per provider |

### 5.3 Skill Artifacts (Framework-Managed)

| File | Zone | Format | Purpose |
|------|------|--------|---------|
| `.claude/skills/*/persona.md` | System | Markdown | Model-agnostic agent persona |
| `.claude/skills/*/output-schema.md` | System | Markdown | Expected output format |
| `.claude/skills/*/evaluation-criteria.md` | System | Markdown | Quality evaluation criteria |

---

## 6. Security Architecture

### 6.1 Secret Management

```
┌──────────────────────────────────────┐
│ Config Layer                          │
│ auth: "{env:OPENAI_API_KEY}"         │  ← Placeholder in config
└──────────────┬───────────────────────┘
               │ interpolation
┌──────────────▼───────────────────────┐
│ Interpolation Engine                  │
│ Allowlist: ^LOA_.*, ^OPENAI_API_KEY$ │  ← Regex validation
│ Reject all non-matching env vars      │
│ File: .loa.config.d/ only, no symlinks│
└──────────────┬───────────────────────┘
               │ resolved value
┌──────────────▼───────────────────────┐
│ Provider Adapter                      │
│ Authorization: Bearer <value>         │  ← Used in HTTP header
│ NEVER logged, NEVER in ledger         │
└──────────────────────────────────────┘
```

### 6.2 Secret Provider Interface

The interpolation engine supports three secret sources with a formal extension mechanism:

| Source | Syntax | Default Allowlist | Extension |
|--------|--------|------------------|-----------|
| Environment | `{env:VAR}` | `^LOA_.*`, `^OPENAI_API_KEY$`, `^ANTHROPIC_API_KEY$`, `^MOONSHOT_API_KEY$` | `hounfour.secret_env_allowlist: ["^CUSTOM_.*"]` in config |
| File | `{file:path}` | Files under `.loa.config.d/` | `hounfour.secret_paths: ["/etc/secrets/"]` in config |
| Command | `{cmd:command}` | Disabled by default | `hounfour.secret_commands_enabled: true` (opt-in) |

**Extension mechanism**: Users can extend the env allowlist via config without editing core code:

```yaml
hounfour:
  secret_env_allowlist:
    - "^AZURE_OPENAI_.*"
    - "^GOOGLE_AI_.*"
```

The core allowlist is always applied first. User extensions are additive only (cannot remove core patterns). All resolved values are tagged `_REDACTED_` in any output path.

**Redaction CI test**: The test suite includes forced-failure scenarios that assert:
1. `httpx` connection errors do not include `Authorization` headers in exception messages
2. `urllib.request` fallback errors do not include auth in repr()
3. Debug-level log output contains `***REDACTED***` for all secret values
4. Python tracebacks from cheval.py do not contain env var values (custom exception handler strips them)

### 6.3 Threat Mitigations

| Threat | Mitigation |
|--------|------------|
| API key in process list | `cheval.py` reads key in-process, never passed as CLI arg |
| Key in logs | All `{env:}`/`{file:}` values tagged `_REDACTED_` in log output |
| Prompt injection via persona | `persona.md` is framework-managed (System Zone); user cannot modify |
| Config injection via env | Only `LOA_MODEL` and `LOA_PROVIDER_*_KEY` are accepted |
| JSONL ledger leaks prompts | Ledger contains ONLY metadata (tokens, cost, timing, agent name) |
| Symlink traversal | `{file:path}` rejects symlinks, validates owner and mode |
| Concurrent ledger corruption | `fcntl.flock(LOCK_EX)` for exclusive write access |

---

## 7. Integration Points

### 7.1 Flatline Protocol

| Current Integration | New Integration |
|-------------------|----------------|
| `model-adapter.sh` direct API calls | `model-invoke --agent flatline-*` |
| `gpt-review-api.sh` hardcoded OpenAI curl | `model-invoke --agent gpt-reviewer` |
| Scoring engine reads raw API responses | Scoring engine reads normalized `CompletionResult` |

### 7.2 Skill Index Schema

**Before** (line 19-24 of `skill-index.schema.json`):
```json
"model": {
  "type": "string",
  "enum": ["sonnet", "opus", "haiku"],
  "default": "sonnet"
}
```

**After**:
```json
"model": {
  "type": "string",
  "default": "native",
  "description": "Model alias or provider:model-id. Resolves through Hounfour provider registry. Use 'native' for Claude Code native runtime."
}
```

### 7.3 loa-finn Downstream

#### 7.3.1 Package Structure

`cheval.py` is structured as an installable Python package (`loa_cheval`) to prevent brittle direct-path imports:

```
.claude/adapters/
├── pyproject.toml              # Package metadata, version, entry points
├── loa_cheval/                 # Importable package
│   ├── __init__.py             # Public API re-exports
│   ├── __version__.py          # Semantic version string
│   ├── types.py                # CompletionRequest, CompletionResult, Usage
│   ├── providers/              # Provider adapters
│   ├── config/                 # Config loading
│   ├── routing/                # Alias resolution
│   └── metering/               # Cost ledger
├── cheval.py                   # CLI entry point (imports from loa_cheval)
└── tests/
```

**Installation**: `pip install -e .claude/adapters/` (editable for development) or `pip install .claude/adapters/` (fixed version).

#### 7.3.2 Public API Surface

The `__init__.py` exports the stable public API:

```python
# loa-finn imports from upstream package
from loa_cheval import (
    CompletionRequest,
    CompletionResult,
    Usage,
    ProviderAdapter,
    OpenAIAdapter,
    AnthropicAdapter,
    ConfigLoader,
    calculate_cost_micro,
    __version__,
)
```

**Deprecation policy**: Public symbols are deprecated for one minor version before removal. Deprecated imports log a warning with migration instructions.

#### 7.3.3 Downstream Integration Tests

loa-finn pins to a version range (`loa_cheval>=1.0,<2.0`) and runs contract tests against the public API surface on each upstream update. The contract tests validate:
1. All public symbols are importable
2. `CompletionRequest`/`CompletionResult` dataclass fields match expected schema
3. `ProviderAdapter.complete()` signature is unchanged

loa-finn adds: Redis-backed circuit breaker, sidecar lifecycle management, streaming SSE transport, JWT auth, tenant routing.

---

## 8. Scalability & Performance

### 8.1 Performance Characteristics

| Operation | Target | Mechanism |
|-----------|--------|-----------|
| Config loading | < 100ms | Cached after first load per process |
| Alias resolution | < 1ms | Dictionary lookup |
| `native_runtime` overhead | 0ms | Config check only, no `model-invoke` call |
| Cost ledger append | < 10ms | `flock` + single `write()` syscall |
| Python cold start | ~200ms | One-time per `model-invoke` invocation |

### 8.2 Scaling Considerations

This is a **CLI-first framework** — not a server. Concurrency is limited to:
- Flatline Protocol: 4 parallel model calls (2 review + 2 skeptic)
- `/run sprint-plan`: Sequential sprint execution
- CI: Potentially parallel across jobs

The `flock`-based ledger is sufficient for this concurrency profile. Server-side scaling (Redis, connection pooling) remains in loa-finn.

---

## 9. Testing Strategy

### 9.1 Provider Conformance Tests

Each provider adapter has golden test fixtures:

```
.claude/adapters/tests/fixtures/
├── openai/
│   ├── chat-completion-request.json    # Expected request body
│   ├── chat-completion-response.json   # Mocked response
│   ├── tool-call-request.json
│   ├── tool-call-response.json
│   └── error-rate-limit.json
└── anthropic/
    ├── messages-request.json
    ├── messages-response.json
    ├── thinking-response.json
    └── error-overloaded.json
```

### 9.2 Config Validation Tests

- Schema validation passes for `model-config.yaml` defaults
- Invalid interpolation patterns rejected (`{env:INVALID_KEY}`)
- Merge pipeline produces expected output for defaults + project + env combinations
- Circular fallback chains detected and rejected

### 9.3 Cost Calculation Tests

- Integer arithmetic produces expected micro-USD values for known token counts
- Budget enforcement triggers at correct thresholds
- Missing usage fields produce estimated costs
- Retry accounting counts all attempts

---

## 10. Migration Strategy

### 10.1 Phase 1: Ship Adapter (No Breaking Changes)

1. Create `.claude/adapters/` with `cheval.py` and dependencies
2. Create `.claude/defaults/model-config.yaml` with defaults
3. Create `.claude/schemas/model-config.schema.json`
4. Create `persona.md` for 8 core agents
5. Update `skill-index.schema.json` model field
6. Ship `model-invoke` wrapper script

At this point, everything works as before. `model-adapter.sh` is unchanged. The new path is available but not active.

### 10.2 Phase 2: Flatline Unification

1. Update `flatline-orchestrator.sh` to call `model-invoke` instead of `model-adapter.sh`
2. Update `gpt-review-api.sh` to call `model-invoke` instead of direct curl
3. Convert `model-adapter.sh` to compatibility shim
4. Feature flag: `hounfour.flatline_routing: true` (default false initially)

### 10.3 Phase 3: Cost Ledger + Routing

1. Enable JSONL metering in `cheval.py`
2. Implement fallback/downgrade chain walking
3. Add circuit breaker state files
4. Ship `/cost-report` command

---

## 11. Technical Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Python cold start adds latency to Flatline | Medium | Low | Config caching; 200ms is <1% of typical Flatline runtime (30-60s) |
| Provider API drift (vendor changes response format) | Medium | Medium | Conformance test suite catches drift; version-pinned adapters |
| Config merge produces unexpected results | Low | High | `--print-effective-config` debug command; merge tests |
| `cheval.py` import in loa-finn breaks on upstream update | Low | High | Semantic versioning on `cheval.py`; conformance test contract |
| Stale circuit breaker blocks requests after recovery | Low | Medium | `HALF_OPEN` state with probe requests; configurable reset timeout |

---

## 12. Future Considerations

### 12.1 Streaming Support (Deferred)

**Decision**: Streaming is an explicit non-goal for MVP. All current orchestration (Flatline, GPT review, skill invocation) is batch-only — the caller submits a request and waits for the complete response.

**Rationale**: Streaming (SSE/async iterators) materially complicates the adapter surface (partial events, cancellation semantics, error mid-stream, backpressure). The CLI stdout contract (§4.2.2) assumes complete output.

**Migration path**: If streaming is needed (e.g., interactive agent UIs in loa-finn):
1. Add `stream: bool` to `CompletionRequest`
2. `ProviderAdapter.complete()` returns `CompletionResult` (batch) or `Iterator[StreamEvent]` (stream)
3. `StreamEvent` type: `content_delta | tool_call_delta | thinking_delta | done | error`
4. loa-finn's `cheval_server.py` wraps the iterator in SSE transport
5. CLI `model-invoke` would use `--stream` flag and emit events line-by-line to stdout

This interface is designed to be additive — existing batch callers remain unchanged.

### 12.2 Ensemble Orchestration

loa-finn has implemented `EnsembleOrchestrator` with three merge strategies (`first_complete`, `best_of_n`, `consensus`). If demand materializes for framework-level ensemble support, the interface can be extracted from loa-finn. This is explicitly deferred from MVP.

### 12.3 Model Quality Benchmarking

The `persona.md` + `output-schema.md` pattern enables automated quality benchmarking: run the same task on multiple models, compare output against structural assertions. This would inform adaptive model routing. Deferred until M2 (8+ agents with persona.md) is achieved.

### 12.4 Construct Portability

Once skill decomposition is proven with 8 core agents, the pattern can be standardized for Loa Constructs. A construct could ship `persona.md` + `output-schema.md` alongside `SKILL.md`, making it usable on any configured provider.

---

*Generated from PRD v1.1.0. Architecture grounded against model-adapter.sh (827 lines), skill-index.schema.json (332 lines), flatline-orchestrator.sh (929 lines), and loa-finn Hounfour source (229 files, 40,170 lines). Flatline SDD review integrated 5 HIGH_CONSENSUS improvements and resolved 6 BLOCKERS into v1.1.0.*
