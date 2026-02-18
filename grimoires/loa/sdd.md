# SDD: Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing

> Cycle: cycle-026 | Author: janitooor + Claude
> Source PRD: `grimoires/loa/prd.md` ([#365](https://github.com/0xHoneyJar/loa/issues/365))
> Flatline: Reviewed (5 HIGH_CONSENSUS integrated, 6 BLOCKERS addressed)
> Phase 1.5 added: 2026-02-18 (Hounfour v7 Protocol Alignment)

## 1. Executive Summary

This SDD designs the activation of Loa's Hounfour model routing subsystem. The infrastructure exists — alias resolution, agent bindings, circuit breakers, metering modules — but the Google provider adapter is missing and the runtime bridge is inactive. This cycle implements the `GoogleAdapter`, wires metering, activates Flatline routing, and enables TeamCreate agents to invoke external models via `cheval.py`.

**Architecture principle**: Extend the existing adapter pattern. No new abstractions. The Google adapter follows the same `ProviderAdapter` → `http_post()` → `CompletionResult` contract as OpenAI and Anthropic.

## 2. System Architecture

### 2.1 Component Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│ Callers                                                          │
│  ┌─────────────────┐  ┌───────────────┐  ┌────────────────────┐ │
│  │ Flatline Scripts │  │ TeamCreate    │  │ /gpt-review        │ │
│  │ (scoring-engine) │  │ Teammates     │  │ (direct invocation)│ │
│  └────────┬────────┘  └──────┬────────┘  └─────────┬──────────┘ │
│           │                  │                      │            │
│           └──────────────────┼──────────────────────┘            │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │                      cheval.py                            │   │
│  │  CLI → resolve_execution() → get_adapter() → complete()   │   │
│  │                              │                            │   │
│  │  New: --prompt, --async, --poll, --cancel                 │   │
│  │  New: --include-thinking                                  │   │
│  └───────────────────────────────┬───────────────────────────┘   │
│                                  ▼                               │
│  ┌───────────────────────────────────────────────────────────┐   │
│  │                    invoke_with_retry()                     │   │
│  │  Retry + Circuit Breaker + BudgetEnforcer (newly wired)   │   │
│  └───────────────────────────────┬───────────────────────────┘   │
│                                  ▼                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ OpenAIAdapter│  │AnthropicAdapt│  │   GoogleAdapter       │   │
│  │ (existing)   │  │ (existing)   │  │   (NEW — this cycle)  │   │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘   │
│         ▼                 ▼                      ▼               │
│  ┌──────────┐      ┌──────────┐      ┌────────────────────────┐ │
│  │ OpenAI   │      │Anthropic │      │ Google AI              │ │
│  │ API      │      │ API      │      │ generateContent        │ │
│  └──────────┘      └──────────┘      │ Interactions (DR)      │ │
│                                      └────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
1. Caller invokes: python cheval.py --agent deep-thinker --prompt "..."
2. cheval.py: parse args → load_config() → resolve_execution()
3. resolver.py: deep-thinker → alias → google:gemini-3-pro
4. cheval.py: _build_provider_config("google", config) → get_adapter(config)
5. invoke_with_retry(adapter, request, config, budget_hook=BudgetEnforcer)
   a. BudgetEnforcer.pre_call() → check daily spend
   b. GoogleAdapter.complete(request)
      i.   _translate_messages() → Gemini format
      ii.  Build body with thinkingConfig.thinkingLevel: "high"
      iii. http_post() → generateContent
      iv.  _parse_response() → CompletionResult
   c. BudgetEnforcer.post_call(result) → record to cost-ledger.jsonl
6. cheval.py: print result.content to stdout
```

## 3. Technology Stack

| Component | Technology | Justification |
|-----------|-----------|---------------|
| Google adapter | Python 3.8+ | Match existing adapters |
| HTTP client | httpx (preferred) / urllib (fallback) | Match existing `http_post()` pattern |
| Async polling | `time.sleep()` + loop | No async runtime needed, matches blocking I/O contract |
| Config | YAML (model-config.yaml) | Match existing 4-layer config merge |
| Cost ledger | JSONL + fcntl.flock | Match existing metering module |
| Concurrency | flock-based semaphore files | No external deps, POSIX standard |

## 4. Component Design

### 4.1 GoogleAdapter

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

```python
class GoogleAdapter(ProviderAdapter):
    """Google Gemini provider adapter (SDD §4.1)."""

    # --- ProviderAdapter interface ---
    def complete(self, request: CompletionRequest) -> CompletionResult
    def validate_config(self) -> List[str]
    def health_check(self) -> bool

    # --- Internal ---
    def _complete_standard(self, request) -> CompletionResult    # generateContent
    def _complete_deep_research(self, request) -> CompletionResult  # Interactions API
    def _translate_messages(self, messages) -> Tuple[Optional[str], List[Dict]]
    def _build_generation_config(self, request, model_config) -> Dict
    def _build_thinking_config(self, model_id, model_config) -> Optional[Dict]
    def _parse_response(self, resp, latency_ms) -> CompletionResult
    def _parse_deep_research_response(self, resp, latency_ms) -> CompletionResult
    def _normalize_citations(self, raw_output) -> Dict
```

#### 4.1.1 `complete()` — Mode Branch

```python
def complete(self, request: CompletionRequest) -> CompletionResult:
    model_config = self._get_model_config(request.model)
    enforce_context_window(request, model_config)

    api_mode = getattr(model_config, 'api_mode', None)
    if api_mode == 'interactions' or request.model.startswith('deep-research'):
        return self._complete_deep_research(request)
    return self._complete_standard(request)
```

#### 4.1.2 `_translate_messages()` — Format Conversion

**Input**: Canonical OpenAI format `[{"role": "system"|"user"|"assistant", "content": str}]`
**Output**: `(system_instruction: str | None, contents: [{"role": "user"|"model", "parts": [{"text": str}]}])`

Translation rules:
1. System messages → concatenated into single `systemInstruction` string (Gemini uses separate field)
2. `"assistant"` role → `"model"` role (Gemini convention)
3. `"content": str` → `"parts": [{"text": str}]`
4. Array content blocks → `InvalidInputError` (text-only in MVP, per PRD SKP-003)
5. Empty content → skip (don't send empty parts)

#### 4.1.3 `_build_thinking_config()` — Model-Aware Thinking

```python
def _build_thinking_config(self, model_id: str, model_config: ModelConfig) -> Optional[Dict]:
    """Build thinkingConfig based on model family."""
    extra = getattr(model_config, 'extra', {})

    if model_id.startswith('gemini-3'):
        # Gemini 3: thinkingLevel (low/medium/high)
        level = extra.get('thinking_level', 'high')
        return {"thinkingConfig": {"thinkingLevel": level}}

    if model_id.startswith('gemini-2.5'):
        # Gemini 2.5: thinkingBudget (128-32768 tokens, -1 for dynamic)
        budget = extra.get('thinking_budget', -1)
        if budget == 0:
            return None  # Disable thinking
        return {"thinkingConfig": {"thinkingBudget": budget}}

    return None  # No thinking for older models
```

#### 4.1.4 `_complete_standard()` — generateContent

```python
def _complete_standard(self, request: CompletionRequest) -> CompletionResult:
    system_instruction, contents = self._translate_messages(request.messages)

    body = {
        "contents": contents,
        "generationConfig": self._build_generation_config(request, model_config),
    }

    if system_instruction:
        body["systemInstruction"] = {"parts": [{"text": system_instruction}]}

    thinking_config = self._build_thinking_config(request.model, model_config)
    if thinking_config:
        body.update(thinking_config)

    auth = self._get_auth_header()
    url = f"{self.config.endpoint}/models/{request.model}:generateContent"
    headers = {"Content-Type": "application/json"}

    # Auth strategy (Flatline SKP-001/IMP-003): prefer header over query param
    auth_mode = self.config.extra.get("auth_mode", "header")  # "header" | "query"
    if auth_mode == "header":
        headers["x-goog-api-key"] = auth  # Google's recommended header auth
    else:
        url += f"?key={auth}"  # Legacy query param (leak-prone, not recommended)

    start = time.monotonic()
    status, resp = http_post(url, headers, body, ...)
    latency_ms = int((time.monotonic() - start) * 1000)

    # Error handling (same pattern as OpenAI/Anthropic)
    ...

    return self._parse_response(resp, latency_ms)
```

#### 4.1.5 `_parse_response()` — Standard Model Response

**Note**: `model_id` is passed explicitly to avoid scope error (Flatline SKP-003).

```python
def _parse_response(self, resp: Dict, latency_ms: int, model_id: str) -> CompletionResult:
    candidates = resp.get("candidates", [])
    if not candidates:
        raise InvalidInputError("Gemini response contains no candidates")

    # Check finishReason (Flatline IMP-002)
    finish_reason = candidates[0].get("finishReason", "STOP")
    if finish_reason == "SAFETY":
        raise InvalidInputError(
            f"Gemini safety filter blocked response. "
            f"Safety ratings: {candidates[0].get('safetyRatings', [])}"
        )
    if finish_reason == "RECITATION":
        raise InvalidInputError("Gemini blocked response due to recitation/copyright concern")
    # MAX_TOKENS: response is truncated but usable — log warning, don't fail
    if finish_reason == "MAX_TOKENS":
        logger.warning("Gemini response truncated (MAX_TOKENS)")

    parts = candidates[0].get("content", {}).get("parts", [])

    # Separate text parts from thinking parts
    content_parts = []
    thinking_parts = []
    for part in parts:
        if part.get("thought", False):
            thinking_parts.append(part.get("text", ""))
        else:
            content_parts.append(part.get("text", ""))

    content = "\n".join(content_parts)
    thinking = "\n".join(thinking_parts) if thinking_parts else None

    # Usage metadata
    usage_data = resp.get("usageMetadata", {})
    usage = Usage(
        input_tokens=usage_data.get("promptTokenCount", 0),
        output_tokens=usage_data.get("candidatesTokenCount", 0),
        reasoning_tokens=usage_data.get("thoughtsTokenCount", 0),
        source="actual" if usage_data else "estimated",
    )

    return CompletionResult(
        content=content,
        tool_calls=None,  # Not supported in MVP
        thinking=thinking,
        usage=usage,
        model=resp.get("modelVersion", model_id),  # Explicit param, not closure
        latency_ms=latency_ms,
        provider=self.provider,
    )
```

#### 4.1.6 Error Mapping Table (Flatline IMP-001)

| Google HTTP Status | google.rpc.Status | Gemini-Specific | Hounfour Error Type |
|-------------------|-------------------|-----------------|---------------------|
| 400 | INVALID_ARGUMENT | Invalid model, bad content | `InvalidInputError` |
| 400 | FAILED_PRECONDITION | Model not available in region | `InvalidInputError` |
| 401 | UNAUTHENTICATED | Invalid API key | `ConfigError` (exit 4) |
| 403 | PERMISSION_DENIED | Quota/billing issue | `ProviderUnavailableError` |
| 404 | NOT_FOUND | Model not found | `InvalidInputError` |
| 429 | RESOURCE_EXHAUSTED | Rate limit | `RateLimitError` |
| 500 | INTERNAL | Server error | `ProviderUnavailableError` |
| 503 | UNAVAILABLE | Service overloaded | `ProviderUnavailableError` |
| 200 + SAFETY finishReason | — | Safety filter | `InvalidInputError` |
| 200 + RECITATION finishReason | — | Copyright block | `InvalidInputError` |
| 200 + no candidates | — | Empty response | `InvalidInputError` |

### 4.2 Deep Research Integration

**File**: Same `google_adapter.py`, method `_complete_deep_research()`

#### 4.2.1 Blocking-Poll Mode (default)

```python
def _complete_deep_research(self, request: CompletionRequest) -> CompletionResult:
    model_config = self._get_model_config(request.model)
    extra = getattr(model_config, 'extra', {})
    polling = extra.get('polling', {})

    timeout_s = polling.get('timeout_seconds', 600)
    initial_delay = polling.get('initial_delay_seconds', 2)
    max_delay = polling.get('max_delay_seconds', 30)

    # Step 1: Create interaction
    auth = self._get_auth_header()
    create_url = f"{self.config.endpoint}/models/{request.model}:createInteraction"
    headers = {"Content-Type": "application/json", "x-goog-api-key": auth}

    # store defaults to false for privacy (Flatline SKP-002)
    store_enabled = extra.get("store", False)
    body = {
        "userInput": {"parts": [{"text": request.messages[-1]["content"]}]},
        "background": True,
        "store": store_enabled,
    }

    start = time.monotonic()
    status, resp = http_post(create_url, headers, body, ...)
    interaction_id = resp.get("name", "").split("/")[-1]

    # Validate interaction_id (Flatline SKP-004: schema-tolerant parsing)
    interaction_name = resp.get("name", "")
    if not interaction_name:
        raise InvalidInputError("Deep Research createInteraction returned no 'name' field")
    interaction_id = interaction_name.split("/")[-1] if "/" in interaction_name else interaction_name

    # Step 2: Poll with exponential backoff (Flatline IMP-005: pinned API version)
    # Pin to v1beta — document exact endpoint for contract tests
    delay = initial_delay
    poll_url = f"{self.config.endpoint}/models/{request.model}/interactions/{interaction_id}"

    while (time.monotonic() - start) < timeout_s:
        time.sleep(delay)
        poll_status, poll_resp = http_get(poll_url, headers)

        # Schema-tolerant status check (Flatline SKP-004)
        state = poll_resp.get("status") or poll_resp.get("state") or ""
        state = state.lower()

        if state in ("completed", "done", "succeeded"):
            return self._parse_deep_research_response(poll_resp, ...)
        if state in ("failed", "error", "cancelled"):
            error_msg = poll_resp.get("error", {}).get("message", "unknown")
            raise ProviderUnavailableError(self.provider, f"Deep Research failed: {error_msg}")

        # Progress log to stderr
        elapsed = int(time.monotonic() - start)
        if elapsed % 30 == 0:
            logger.warning("Deep Research polling... %ds elapsed, status=%s", elapsed, state)

        delay = min(delay * 2, max_delay)

    raise TimeoutError(f"Deep Research timed out after {timeout_s}s")
```

#### 4.2.2 Non-Blocking Mode (`--async`)

When `cheval.py --async` is passed:

```python
# In cheval.py cmd_invoke():
if args.async_mode:
    # Only create the interaction, return metadata
    interaction = adapter.create_interaction(request)
    print(json.dumps({
        "interaction_id": interaction["id"],
        "status": "pending",
        "poll_command": f"python cheval.py --poll {interaction['id']} --agent {agent_name}",
        "cancel_command": f"python cheval.py --cancel {interaction['id']} --agent {agent_name}",
    }))
    return EXIT_CODES["INTERACTION_PENDING"]  # exit code 8
```

New `GoogleAdapter` methods for non-blocking:
- `create_interaction(request) -> Dict` — POST createInteraction, return metadata
- `poll_interaction(interaction_id) -> CompletionResult | None` — GET status, return result if completed
- `cancel_interaction(interaction_id) -> bool` — Best-effort cancellation

#### 4.2.3 Deep Research Output Normalization

```python
def _normalize_citations(self, raw_output: str) -> Dict:
    """Post-process Deep Research output into structured format (PRD SKP-001)."""
    # Attempt to extract structured data from raw research output
    result = {
        "summary": "",
        "claims": [],
        "citations": [],
        "raw_output": raw_output,
    }

    # Extract markdown citations [N] patterns
    # Extract DOI patterns (10.XXXX/...)
    # Extract URLs
    # If extraction yields results, populate structured fields
    # If not, return raw_output only with empty structured fields + warning

    return result
```

#### 4.2.4 Concurrency Control

**File**: `.claude/adapters/loa_cheval/providers/concurrency.py` (new)

```python
class FLockSemaphore:
    """File-lock-based semaphore for limiting concurrent API calls (Flatline SKP-005).

    Implements context-manager protocol for safe acquire/release.
    Stores file descriptors to prevent GC-induced lock release.
    Writes PID to lock file for stale-lock detection.
    """

    def __init__(self, name: str, max_concurrent: int, lock_dir: str = ".run"):
        self._name = name
        self._max = max_concurrent
        self._lock_dir = lock_dir
        self._held_fd: Optional[IO] = None
        self._held_slot: Optional[int] = None
        os.makedirs(lock_dir, exist_ok=True)

    def __enter__(self) -> "FLockSemaphore":
        self.acquire()
        return self

    def __exit__(self, *exc) -> None:
        self.release()

    def acquire(self, timeout: float = 30.0) -> int:
        """Acquire a slot. Returns slot index. Raises TimeoutError if full."""
        deadline = time.monotonic() + timeout

        while time.monotonic() < deadline:
            for slot in range(self._max):
                lock_path = f"{self._lock_dir}/.semaphore-{self._name}-{slot}.lock"
                try:
                    fd = open(lock_path, "w")
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    fd.write(str(os.getpid()))
                    fd.flush()
                    self._held_fd = fd  # Prevent GC
                    self._held_slot = slot
                    return slot
                except (BlockingIOError, OSError):
                    fd.close()
                    # Check for stale lock (process no longer exists)
                    self._check_stale_lock(lock_path)
                    continue
            time.sleep(1)

        raise TimeoutError(f"All {self._max} slots occupied for {self._name}")

    def release(self) -> None:
        """Release held slot."""
        if self._held_fd is not None:
            try:
                fcntl.flock(self._held_fd, fcntl.LOCK_UN)
                self._held_fd.close()
            except OSError:
                pass
            self._held_fd = None
            self._held_slot = None

    def _check_stale_lock(self, lock_path: str) -> None:
        """Remove lock file if owning PID no longer exists."""
        try:
            with open(lock_path, "r") as f:
                pid = int(f.read().strip())
            os.kill(pid, 0)  # Check if process exists
        except (ValueError, ProcessLookupError, PermissionError, FileNotFoundError):
            try:
                os.unlink(lock_path)
            except FileNotFoundError:
                pass
```

**Usage in GoogleAdapter**:
```python
# Standard models: max 5 concurrent
# Deep Research: max 3 concurrent (configurable)
semaphore = FLockSemaphore("google-standard", max_concurrent=5)
dr_semaphore = FLockSemaphore("google-deep-research", max_concurrent=3)
```

### 4.3 Metering Activation

#### 4.3.1 Wire BudgetEnforcer in cheval.py

**File**: `.claude/adapters/cheval.py` — modify `cmd_invoke()`

```python
# Current (line 266-272):
try:
    from loa_cheval.providers.retry import invoke_with_retry
    result = invoke_with_retry(adapter, request, hounfour)
except ImportError:
    result = adapter.complete(request)

# New:
from loa_cheval.metering.budget import BudgetEnforcer
metering = hounfour.get("metering", {})
ledger_path = metering.get("ledger_path", "grimoires/loa/a2a/cost-ledger.jsonl")
budget_hook = BudgetEnforcer(hounfour, ledger_path, trace_id=os.environ.get("LOA_TRACE_ID"))

try:
    from loa_cheval.providers.retry import invoke_with_retry
    result = invoke_with_retry(adapter, request, hounfour, budget_hook=budget_hook)
except ImportError:
    budget_status = budget_hook.pre_call(request)
    if budget_status == "BLOCK":
        raise BudgetExceededError(...)
    result = adapter.complete(request)
    budget_hook.post_call(result)
```

#### 4.3.2 Extend PricingEntry for Per-Task Pricing

**File**: `.claude/adapters/loa_cheval/metering/pricing.py`

```python
@dataclass
class PricingEntry:
    """Per-model pricing — supports token-based and per-task models."""
    provider: str
    model: str
    input_per_mtok: int = 0       # micro-USD per 1M input tokens
    output_per_mtok: int = 0      # micro-USD per 1M output tokens
    reasoning_per_mtok: int = 0   # micro-USD per 1M reasoning tokens
    per_task_micro_usd: int = 0   # micro-USD per task (Deep Research)
    pricing_mode: str = "token"   # "token" | "task" | "hybrid"
```

**Extend `find_pricing()`** to read `per_task_micro_usd` from config.

**Extend `calculate_total_cost()`**:
```python
if pricing.pricing_mode == "task":
    return CostBreakdown(
        input_cost_micro=0,
        output_cost_micro=0,
        reasoning_cost_micro=0,
        total_cost_micro=pricing.per_task_micro_usd,
        ...
    )
elif pricing.pricing_mode == "hybrid":
    # Token cost + per-task cost
    token_cost = calculate_token_cost(...)
    return CostBreakdown(total_cost_micro=token_cost.total + pricing.per_task_micro_usd, ...)
```

#### 4.3.3 Ledger Entry Extension

Add `pricing_mode` field to ledger entries for Deep Research:

```json
{
  "ts": "...",
  "provider": "google",
  "model": "deep-research-pro",
  "tokens_in": 0,
  "tokens_out": 4500,
  "cost_micro_usd": 3000000,
  "pricing_mode": "task",
  "interaction_id": "abc123"
}
```

### 4.3.4 Atomic Budget Check (Flatline SKP-006)

Replace check-then-act with atomic check+reserve:

```python
def pre_call_atomic(self, request: CompletionRequest, estimated_cost: int) -> str:
    """Atomic budget check with reservation."""
    if not self._enabled:
        return ALLOW

    # Lock daily-spend file for atomic read-check-reserve
    spend_path = _daily_spend_path(self._ledger_path)
    with open(spend_path, "r+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            data = json.load(f)
            current_spend = data.get("total_micro_usd", 0)

            if current_spend + estimated_cost >= self._daily_limit:
                return BLOCK if self._on_exceeded == "block" else DOWNGRADE

            # Write reservation
            data["total_micro_usd"] = current_spend + estimated_cost
            data["reservations"] = data.get("reservations", 0) + 1
            f.seek(0)
            json.dump(data, f)
            f.truncate()
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)

    return ALLOW
```

Post-call reconciles reservation with actual cost (adjusts if over/under-estimated).

### 4.3.5 Rate Limiting (Flatline IMP-006)

Token-bucket rate limiter per provider, in addition to circuit breaker:

```python
class TokenBucketLimiter:
    """Per-provider RPM/TPM rate limiting."""

    def __init__(self, rpm: int = 60, tpm: int = 1_000_000):
        self._rpm = rpm
        self._tpm = tpm
        # State stored in .run/.ratelimit-{provider}.json (flock-protected)

    def check(self, provider: str, estimated_tokens: int) -> bool:
        """Returns True if request is within limits."""
        ...

    def record(self, provider: str, tokens_used: int) -> None:
        """Record token usage after completion."""
        ...
```

Default limits (configurable in model-config.yaml):
```yaml
routing:
  rate_limits:
    google:
      rpm: 60           # Requests per minute
      tpm: 1000000      # Tokens per minute
    openai:
      rpm: 500
      tpm: 2000000
```

### 4.4 Feature Flags

**File**: `.loa.config.yaml` — new granular flags replace single `flatline_routing`

```yaml
hounfour:
  google_adapter: true        # Enable Google provider adapter
  deep_research: true         # Enable Deep Research (Interactions API)
  flatline_routing: true      # Route Flatline through cheval.py
  metering: true              # Activate cost recording + budget enforcement
  thinking_traces: true       # Request thinking traces from supported models
```

**Implementation**: `cheval.py` checks flags before proceeding:

```python
flags = hounfour.get("hounfour", {})

# Block Google adapter if disabled
if resolved.provider == "google" and not flags.get("google_adapter", True):
    raise ConfigError("Google adapter disabled (hounfour.google_adapter: false)")

# Block Deep Research if disabled
if request.model.startswith("deep-research") and not flags.get("deep_research", True):
    raise ConfigError("Deep Research disabled (hounfour.deep_research: false)")
```

### 4.5 cheval.py CLI Extensions

New arguments:

| Argument | Description | Used By |
|----------|-------------|---------|
| `--prompt TEXT` | Inline prompt (alternative to --input/stdin) | TeamCreate teammates |
| `--async` | Non-blocking mode for Deep Research | Long-running research |
| `--poll ID` | Poll existing interaction status | Follow-up to --async |
| `--cancel ID` | Cancel running interaction | Cleanup |
| `--include-thinking` | Include thinking traces in output | Research agents |

**`--prompt` implementation**:
```python
# In cmd_invoke(), after existing input loading:
if args.prompt:
    input_text = args.prompt
```

### 4.6 Thinking Trace Policy

Per PRD SKP-004:

1. GoogleAdapter always requests thinking traces from supported models (needed for `tokens_reasoning` count)
2. `CompletionResult.thinking` is always populated internally
3. In `cheval.py` output:
   - `--output-format text`: thinking is NEVER printed
   - `--output-format json` without `--include-thinking`: `result.thinking` set to `null`
   - `--output-format json` with `--include-thinking`: `result.thinking` included
4. Cost ledger: only `tokens_reasoning` count, never trace content
5. `.run/audit.jsonl`: no trace content

### 4.7 ModelConfig Extension

**File**: `.claude/adapters/loa_cheval/types.py`

```python
@dataclass
class ModelConfig:
    """Per-model configuration within a provider."""
    capabilities: List[str] = field(default_factory=list)
    context_window: int = 128000
    pricing: Optional[Dict[str, int]] = None
    api_mode: Optional[str] = None          # "interactions" for Deep Research
    extra: Optional[Dict[str, Any]] = None  # thinking_level, thinking_budget, polling
```

The `extra` dict carries model-specific configuration:
- `thinking_level`: "low" | "medium" | "high" (Gemini 3)
- `thinking_budget`: int (Gemini 2.5, 128-32768 or -1 for dynamic)
- `polling.initial_delay_seconds`, `polling.max_delay_seconds`, `polling.timeout_seconds`

### 4.8 Provider Registry Update

**File**: `.claude/adapters/loa_cheval/providers/__init__.py`

```python
from loa_cheval.providers.google_adapter import GoogleAdapter

_ADAPTER_REGISTRY: Dict[str, Type[ProviderAdapter]] = {
    "openai": OpenAIAdapter,
    "anthropic": AnthropicAdapter,
    "openai_compat": OpenAIAdapter,
    "google": GoogleAdapter,    # NEW
}
```

## 5. Configuration Changes

### 5.1 model-config.yaml — New Models and Aliases

```yaml
# Under providers.google.models:
gemini-3-flash:
  capabilities: [chat, thinking_traces]
  context_window: 1048576
  extra:
    thinking_level: high      # default for Gemini 3 Flash
  pricing:
    input_per_mtok: 150000    # Placeholder — update when published
    output_per_mtok: 600000

gemini-3-pro:
  capabilities: [chat, thinking_traces, deep_reasoning]
  context_window: 1048576
  extra:
    thinking_level: high      # default for Gemini 3 Pro
  pricing:
    input_per_mtok: 1250000   # Placeholder — update when published
    output_per_mtok: 10000000

deep-research-pro:
  capabilities: [deep_research, web_search, file_search]
  context_window: 1048576
  api_mode: interactions
  extra:
    polling:
      initial_delay_seconds: 2
      max_delay_seconds: 30
      timeout_seconds: 600
  pricing:
    per_task_micro_usd: 3000000
    pricing_mode: task

# Under aliases:
deep-thinker: "google:gemini-3-pro"
fast-thinker: "google:gemini-3-flash"
researcher: "google:gemini-2.5-pro"

# Under agents:
deep-researcher:
  model: "google:deep-research-pro"
  temperature: 0.3
  requires:
    deep_research: true

deep-thinker:
  model: deep-thinker
  temperature: 0.5
  requires:
    thinking_traces: true
    deep_reasoning: preferred

fast-thinker:
  model: fast-thinker
  temperature: 0.5
  requires:
    thinking_traces: true

literature-reviewer:
  model: researcher
  temperature: 0.3
  requires:
    thinking_traces: preferred
```

### 5.2 .loa.config.yaml — Feature Flags

```yaml
hounfour:
  google_adapter: true
  deep_research: true
  flatline_routing: true
  metering: true
  thinking_traces: true
```

## 6. Flatline Integration

### 6.1 Routing Flatline Through Hounfour

When `hounfour.flatline_routing: true`, Flatline scripts invoke `cheval.py` instead of direct API calls.

**File**: `.claude/scripts/flatline-orchestrator.sh` — modify `call_model()` function:

```bash
call_model_via_hounfour() {
    local agent="$1"   # e.g., "flatline-reviewer", "flatline-skeptic"
    local input_file="$2"
    local output_file="$3"

    python .claude/adapters/cheval.py \
        --agent "$agent" \
        --input "$input_file" \
        --output-format json \
        --max-tokens 8192 \
        > "$output_file" 2>"${output_file}.err"

    return $?
}
```

**Backward compatibility**: Check flag before routing:

```bash
if [[ "$(yq '.hounfour.flatline_routing // false' .loa.config.yaml)" == "true" ]]; then
    call_model_via_hounfour "$agent" "$input" "$output"
else
    call_model_legacy "$agent" "$input" "$output"  # existing behavior
fi
```

### 6.2 Agent Bindings for Flatline

Existing Flatline agent bindings already route correctly:

```yaml
flatline-reviewer:
  model: reviewer        # → openai:gpt-5.2
flatline-skeptic:
  model: reasoning       # → openai:gpt-5.2
flatline-scorer:
  model: reviewer
flatline-dissenter:
  model: reasoning
```

No changes needed — these resolve through the existing alias chain.

## 7. Security Design

### 7.1 API Key Handling

- Google API key: `{env:GOOGLE_API_KEY}` — resolved at call time by `_get_auth_header()`
- Key passed as URL query parameter (`?key=...`) per Google API convention
- URL with key NEVER logged — `http_post()` uses separate URL and headers
- Add `GOOGLE_API_KEY` to error message redaction in `cheval.py` (line 318)

### 7.2 Secret Scanning

Add Google API key pattern to `.loa.config.yaml` secret scanning:

```yaml
flatline_protocol:
  secret_scanning:
    patterns:
      - "AIzaSy[A-Za-z0-9_-]{33}"
      - "GOOG[A-Za-z0-9_-]{16,}"
```

### 7.3 Deep Research Data Retention

Deep Research uses `store: true` which persists interaction data on Google's servers. Document in config:

```yaml
# deep-research-pro config comment:
# NOTE: store: true creates server-side interaction state.
# Interaction data is subject to Google's data retention policies.
# Do not send sensitive/proprietary content through Deep Research.
```

## 8. Test Strategy

### 8.1 Unit Tests

**File**: `.claude/adapters/tests/test_google_adapter.py`

| Test | What It Validates |
|------|------------------|
| `test_translate_messages_basic` | User/assistant → Gemini format |
| `test_translate_messages_system` | System message → systemInstruction |
| `test_translate_messages_multiple_system` | Multiple system → concatenated |
| `test_translate_messages_unsupported` | Array content → InvalidInputError |
| `test_build_thinking_gemini3` | thinkingLevel: high for gemini-3-pro |
| `test_build_thinking_gemini25` | thinkingBudget for gemini-2.5-pro |
| `test_parse_response_with_thinking` | Thought parts separated from content |
| `test_parse_response_no_thinking` | No thought parts → thinking=None |
| `test_parse_usage_metadata` | promptTokenCount, candidatesTokenCount, thoughtsTokenCount |
| `test_error_400` | 400 → InvalidInputError |
| `test_error_429` | 429 → RateLimitError |
| `test_error_500` | 500 → ProviderUnavailableError |
| `test_normalize_citations` | Extract DOIs and URLs from raw research output |
| `test_validate_config` | Required fields check |
| `test_health_check` | Models list endpoint probe |

### 8.2 Unit Tests — Pricing Extension

**File**: `.claude/adapters/tests/test_pricing_extended.py`

| Test | What It Validates |
|------|------------------|
| `test_per_task_pricing` | Deep Research → per_task_micro_usd |
| `test_hybrid_pricing` | Token + per-task cost sum |
| `test_pricing_mode_detection` | Config pricing_mode field parsed correctly |

### 8.3 Integration Tests

**File**: `.claude/adapters/tests/test_cheval_google.sh`

| Test | What It Validates |
|------|------------------|
| `test_dry_run_google` | `--dry-run` resolves google provider |
| `test_invoke_standard_mock` | Mock generateContent → CompletionResult |
| `test_invoke_deep_research_mock` | Mock Interactions API → poll → result |
| `test_async_mode` | `--async` returns interaction metadata |
| `test_budget_enforcement` | BudgetEnforcer blocks when over limit |
| `test_feature_flag_disabled` | `google_adapter: false` → ConfigError |
| `test_thinking_trace_redaction` | Without --include-thinking → null |

### 8.4 Smoke Tests (Live API)

**File**: `.claude/adapters/tests/test_google_smoke.sh`

Requires `GOOGLE_API_KEY` env var. Skips gracefully if not set.

| Test | Model |
|------|-------|
| Gemini 2.5 Flash completion | gemini-2.5-flash |
| Gemini 2.5 Pro with thinking | gemini-2.5-pro |
| Gemini 3 Flash with thinkingLevel | gemini-3-flash (if available) |
| Gemini 3 Pro with thinkingLevel:high | gemini-3-pro (if available) |
| Deep Research (short query, 60s timeout) | deep-research-pro (if available) |

## 9. File Manifest

### New Files

| Path | Description |
|------|-------------|
| `.claude/adapters/loa_cheval/providers/google_adapter.py` | Google/Gemini provider adapter |
| `.claude/adapters/loa_cheval/providers/concurrency.py` | FLockSemaphore for concurrent call limiting |
| `.claude/adapters/tests/test_google_adapter.py` | Unit tests |
| `.claude/adapters/tests/test_pricing_extended.py` | Pricing extension tests |
| `.claude/adapters/tests/test_cheval_google.sh` | Integration tests |
| `.claude/adapters/tests/test_google_smoke.sh` | Live API smoke tests |
| `.claude/adapters/tests/fixtures/gemini-*.json` | Mock API response fixtures |

### Modified Files

| Path | Changes |
|------|---------|
| `.claude/adapters/loa_cheval/providers/__init__.py` | Add GoogleAdapter to registry |
| `.claude/adapters/loa_cheval/types.py` | Extend ModelConfig with api_mode, extra |
| `.claude/adapters/loa_cheval/metering/pricing.py` | Add per_task_micro_usd, pricing_mode |
| `.claude/adapters/loa_cheval/config/loader.py` | Parse new ModelConfig fields from YAML |
| `.claude/adapters/cheval.py` | --prompt, --async, --poll, --cancel, --include-thinking, BudgetEnforcer wiring |
| `.claude/defaults/model-config.yaml` | Gemini 3 models, Deep Research, new aliases/agents |
| `.loa.config.yaml` | Granular feature flags |
| `.claude/scripts/flatline-orchestrator.sh` | Hounfour routing branch |
| `.claude/loa/reference/agent-teams-reference.md` | Template 4: Expert Swarm |

## 10. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Google API key in URL query param visible in logs | http_post() doesn't log URLs; add to redaction list |
| Deep Research 60min max timeout exceeds typical CI limits | Default 10min, configurable. Non-blocking mode for long research. |
| Gemini 3 preview API may change | Pin to v1beta, add version check in adapter |
| Circuit breaker state per-process means no cross-process state sharing | Acceptable for MVP. flock-based shared state is Phase 2. |
| Pricing TBD for Gemini 3 Pro | Use placeholder pricing, document as estimated. Update when published. |

## 11. Development Order

| Sprint | Scope | Dependencies |
|--------|-------|-------------|
| Sprint 1 | GoogleAdapter (standard models) + model config + provider registry + unit tests | None |
| Sprint 2 | Deep Research adapter + non-blocking mode + concurrency + citation normalization | Sprint 1 |
| Sprint 3 | Metering activation + pricing extension + Flatline routing + feature flags + integration tests | Sprint 1 |
| Sprint 4 | Hounfour v7 Protocol Alignment (FR-7 through FR-11) | Sprints 1-3 (runtime bridge complete) |

Sprints 2 and 3 are independent of each other and could run in parallel after Sprint 1 completes.
Sprint 4 is a standalone alignment sprint that depends on the runtime bridge being operational.

## 11.5 Phase 1.5 — Hounfour v7 Protocol Alignment Design

### 11.5.1 Ecosystem Version Declarations (FR-7)

**Files**: `.loa.config.yaml`, `BUTTERFREEZONE.md`

The ecosystem version declarations use a `pkg@version` format consumed by
`butterfreezone-validate.sh:validate_protocol_version()` (line 650). The function:
1. Parses `pkg-name@declared_version` from config
2. Checks `npm view @0xhoneyjar/${pkg_name} version` for live version
3. Falls back to `gh api repos/0xHoneyJar/${pkg_name}/releases/latest`
4. Emits WARN on mismatch (advisory only, never blocks)

**Change**: Update 3 entries in `.loa.config.yaml` → `butterfreezone.ecosystem[].protocol`:

```yaml
# FROM:
- repo: 0xHoneyJar/loa-finn
  protocol: loa-hounfour@4.6.0      # stale — finn is pinned to e5b9f16 (v5.0.0)
- repo: 0xHoneyJar/loa-hounfour
  protocol: loa-hounfour@4.6.0      # stale — published v7.0.0
- repo: 0xHoneyJar/arrakis
  protocol: loa-hounfour@4.6.0      # stale — pinned to d091a3c (v7.0.0)

# TO:
- repo: 0xHoneyJar/loa-finn
  protocol: loa-hounfour@5.0.0      # pinned to e5b9f16 (v5.0.0, Multi-Model Release)
- repo: 0xHoneyJar/loa-hounfour
  protocol: loa-hounfour@7.0.0      # current release (Composition-Aware Economic Protocol)
- repo: 0xHoneyJar/arrakis
  protocol: loa-hounfour@7.0.0      # pinned to d091a3c (v7.0.0 merge commit)
```

**Post-update**: Run `butterfreezone-gen.sh` to regenerate `BUTTERFREEZONE.md`.
Run `butterfreezone-validate.sh` to verify zero `proto_version` warnings.

### 11.5.2 Trust Scopes Migration (FR-8)

**Files**: `.claude/data/model-permissions.yaml`, `docs/architecture/capability-schema.md`

#### model-permissions.yaml

The current file uses flat `trust_level: high|medium` for each model entry.
Hounfour v6.0.0 replaced `AgentIdentity.trust_level` with `trust_scopes: CapabilityScopedTrust`.

The 6 dimensions map to Loa's permission landscape as follows:

| Dimension | Loa Meaning | claude-code:session | openai:gpt-5.2 | google:* (remote) |
|-----------|-------------|--------------------|-----------------|--------------------|
| `data_access` | Can read/write files | high | none | none |
| `financial` | Can authorize spend | high (BudgetEnforcer) | none | none |
| `delegation` | Can spawn agents | high (TeamCreate) | none | none |
| `model_selection` | Can choose models | high (resolve_execution) | none | none |
| `governance` | Can vote/decide | none (CLI, not governance) | none | none |
| `external_communication` | Can call external APIs | high | none | none |

For local models (like `qwen-local:qwen3-coder-next`) that have file access:

| Dimension | Value | Reason |
|-----------|-------|--------|
| `data_access` | medium | Can read/write files but sandboxed |
| `financial` | none | No budget authority |
| `delegation` | none | Cannot spawn agents |
| `model_selection` | none | Fixed model |
| `governance` | none | No governance role |
| `external_communication` | none | No network access |

**Design decision**: Keep `trust_level` as a backward-compatible summary field alongside
`trust_scopes`. Consumers that understand v6+ use `trust_scopes`; older consumers use
`trust_level`. This matches hounfour's own migration pattern where additive fields coexist
with deprecated ones until the next major version removes them.

#### capability-schema.md

The trust gradient (L1-L4) is Loa's abstraction — it maps to but is not identical to
hounfour's `trust_scopes`. Update the gradient definition to show the scopes each level
implies:

```yaml
trust_gradient:
  L1:
    name: "Tests Present"
    trust_scopes:
      data_access: read_only
      financial: none
      delegation: none
      model_selection: basic    # cheap, fast_code pools only
      governance: none
      external_communication: none
  L2:
    name: "CI Verified"
    trust_scopes:
      data_access: read_only
      financial: metered        # within budget limits
      delegation: none
      model_selection: standard # + reviewer pool
      governance: none
      external_communication: rate_limited
  L3:
    name: "Property-Based"
    trust_scopes:
      data_access: scoped       # within declared capability scopes
      financial: metered
      delegation: supervised    # can delegate but lead must approve
      model_selection: full     # + reasoning pool
      governance: observer      # can see but not vote
      external_communication: rate_limited
  L4:
    name: "Formal"
    trust_scopes:
      data_access: full
      financial: budgeted       # self-managed within allocation
      delegation: autonomous    # can delegate freely
      model_selection: full     # + architect pool
      governance: voting        # can participate in decisions
      external_communication: full
```

### 11.5.3 Provider Type Schema Fix (FR-9)

**File**: `.claude/schemas/model-config.schema.json`

The provider `type` enum is:
```json
"type": { "enum": ["openai", "anthropic", "openai_compat"] }
```

Add `"google"`:
```json
"type": { "enum": ["openai", "anthropic", "openai_compat", "google"] }
```

This is a schema-code alignment fix — the GoogleAdapter already handles `type: "google"`
in the adapter registry, but the JSON Schema would reject it during validation.

### 11.5.4 Hounfour v7 Type Mapping Documentation (FR-10)

**File**: `docs/architecture/capability-schema.md` — new section

This is documentation-only: no code changes. The mapping documents how Loa's internal
patterns correspond to hounfour v7 protocol types, enabling cross-repo reviewers (including
Bridgebuilder) to understand architectural parallels.

| Hounfour v7 Type | Loa Pattern | File:Line | Structural Parallel |
|-----------------|-------------|-----------|---------------------|
| `BridgeTransferSaga` | `invoke_with_retry()` retry+fallback chain | `.claude/adapters/loa_cheval/providers/retry.py` | Both implement saga-like compensation: retry is "try next step", fallback is "compensate with alternate provider" |
| `DelegationOutcome` | Flatline `consensus_summary` | `.claude/scripts/flatline-orchestrator.sh` | Both model multi-actor decision outcomes (unanimous/majority/deadlock maps to HIGH_CONSENSUS/DISPUTED/BLOCKER) |
| `MonetaryPolicy` | `RemainderAccumulator` conservation | `.claude/adapters/loa_cheval/metering/pricing.py` | Both enforce monetary conservation invariants (micro-USD arithmetic, no floating-point loss) |
| `PermissionBoundary` | MAY permission grants | `CLAUDE.loa.md` permission_grants section | Both model constrained experimentation: "you may do X if conditions Y" with reporting requirements |
| `GovernanceProposal` | Flatline scoring consensus | `.claude/scripts/flatline-orchestrator.sh` | Both implement weighted multi-actor voting (each model is a weighted voter in Flatline) |

### 11.5.5 Lore Update (FR-11)

**File**: `.claude/data/lore/mibera/core.yaml` — update hounfour entry

Current `context` references the hounfour as "the Flatline Protocol's multi-model review
space." Extend with v7 era context:

```yaml
- id: hounfour
  term: "Hounfour"
  short: "The multi-model orchestration space"
  context: >
    The hounfour (also peristyle) is the Vodou temple where ceremonies
    take place. In the Loa ecosystem, the hounfour is the runtime bridge
    that routes agent invocations across providers — the space where models
    meet. v7.0.0 ("The Composition-Aware Economic Protocol") extends the
    hounfour with saga patterns for cross-registry transfers, delegation
    outcomes for multi-actor conflict resolution, and monetary policy for
    conservation invariants.
  source: "loa-hounfour@7.0.0"
  tags: [infrastructure, multi-model, economy]
```

**File**: `docs/architecture/capability-schema.md` — add version lineage section:

```markdown
## Hounfour Version Lineage

| Version | Codename | Key Addition |
|---------|----------|-------------|
| v3.0.0 | Constitutional | Agent identity, billing, conversations |
| v4.6.0 | Agent Economy | Performance, reputation, governance |
| v5.0.0 | Multi-Model | Barrel decomposition, conservation properties |
| v6.0.0 | Capability-Scoped Trust | trust_scopes replaces trust_level |
| v7.0.0 | Composition-Aware Economic Protocol | Sagas, delegation outcomes, monetary policy |
```

### 11.5.6 BUTTERFREEZONE Regeneration

After all file updates, regenerate BUTTERFREEZONE.md:

```bash
.claude/scripts/butterfreezone-gen.sh
.claude/scripts/butterfreezone-validate.sh --strict
```

The regeneration will pick up:
- Updated ecosystem protocol versions from `.loa.config.yaml`
- Updated trust vocabulary from `model-permissions.yaml`
- Updated architecture docs from `capability-schema.md`

### 11.5.7 File Manifest — Phase 1.5

| Path | Change Type | Description |
|------|------------|-------------|
| `.loa.config.yaml` | Modified | Update 3 ecosystem protocol versions |
| `.claude/data/model-permissions.yaml` | Modified | trust_level → trust_scopes (6-dimensional) |
| `.claude/schemas/model-config.schema.json` | Modified | Add "google" to provider type enum |
| `docs/architecture/capability-schema.md` | Modified | trust_scopes gradient, v7 type mapping, version lineage |
| `.claude/data/lore/mibera/core.yaml` | Modified | Update hounfour entry with v7 context |
| `BUTTERFREEZONE.md` | Regenerated | Picks up all above changes |

## 12. Reference

- PRD: `grimoires/loa/prd.md`
- Existing adapter code: `.claude/adapters/loa_cheval/providers/`
- Provider base: `.claude/adapters/loa_cheval/providers/base.py`
- Anthropic adapter (reference): `.claude/adapters/loa_cheval/providers/anthropic_adapter.py`
- Hounfour config: `.claude/defaults/model-config.yaml`
- Metering: `.claude/adapters/loa_cheval/metering/`
- Agent Teams: `.claude/loa/reference/agent-teams-reference.md`
- [Gemini API Reference](https://ai.google.dev/gemini-api/docs)
