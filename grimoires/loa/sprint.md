# Sprint Plan: Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing

> Cycle: cycle-026 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#365](https://github.com/0xHoneyJar/loa/issues/365)
> Sprints: 5 | Estimated: ~1550 lines across 14 files (6 new, 8 modified) + bridge iteration
> Parallelism: Sprints 2 and 3 are independent after Sprint 1 completes; Sprint 4 runs after all
> Flatline: Reviewed (2 HIGH_CONSENSUS integrated, 1 DISPUTED accepted, 6 BLOCKERS addressed)

## Sprint 1: GoogleAdapter — Standard Gemini Models

**Goal**: Implement the core Google provider adapter for standard Gemini 2.5/3 models. This is foundational — Deep Research and metering both depend on a working adapter with message translation, thinking config, error mapping, and response parsing.

**Global Sprint ID**: sprint-5

### Task 1.1: Create GoogleAdapter skeleton and provider registration

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`
**Also**: `.claude/adapters/loa_cheval/providers/__init__.py`

Implement the `GoogleAdapter` class extending `ProviderAdapter` with all method stubs and register it in the adapter registry.

**Acceptance Criteria**:
- [ ] `GoogleAdapter` extends `ProviderAdapter` (from `base.py`)
- [ ] Implements `complete()`, `validate_config()`, `health_check()`
- [ ] `complete()` branches on `api_mode == "interactions"` (stub for Sprint 2)
- [ ] `validate_config()` checks `GOOGLE_API_KEY` env var exists
- [ ] `health_check()` makes a lightweight `models.list` API probe against same base URL used by `generateContent` (Flatline SKP-003: startup self-test)
- [ ] Centralized `_build_url(path)` method for all endpoint construction — base URL + API version in one place (Flatline SKP-003)
- [ ] API version pinned to `v1beta` by default, configurable via `model_config.extra.api_version` (Flatline SKP-003)
- [ ] HTTP client strategy: httpx preferred with `connect_timeout=5s`, `read_timeout=120s`; urllib fallback with same timeouts (Flatline IMP-002)
- [ ] Registered as `"google": GoogleAdapter` in `_ADAPTER_REGISTRY`
- [ ] Import path: `from loa_cheval.providers.google_adapter import GoogleAdapter`
- [ ] Python 3.8 compatible (no walrus operator, no `match`)

### Task 1.2: Implement _translate_messages()

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Translate OpenAI canonical message format to Gemini format per SDD 4.1.2.

**Acceptance Criteria**:
- [ ] System messages extracted and concatenated into single `systemInstruction` string
- [ ] Multiple system messages concatenated with double newline
- [ ] `"assistant"` role mapped to `"model"` role
- [ ] `"content": str` converted to `"parts": [{"text": str}]`
- [ ] Array content blocks (images, tool_calls) raise `InvalidInputError` with descriptive message listing unsupported types (Flatline SKP-002)
- [ ] Before raising, check `model_config.capabilities` — if google model lacks needed capability, suggest fallback provider in error message (Flatline SKP-002)
- [ ] Empty content strings skipped (no empty parts sent)
- [ ] Returns `Tuple[Optional[str], List[Dict]]` — (system_instruction, contents)

### Task 1.3: Implement _build_thinking_config()

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Build model-aware thinking configuration per SDD 4.1.3.

**Acceptance Criteria**:
- [ ] Gemini 3 models (`gemini-3-*`): returns `{"thinkingConfig": {"thinkingLevel": level}}`
- [ ] Gemini 2.5 models (`gemini-2.5-*`): returns `{"thinkingConfig": {"thinkingBudget": budget}}`
- [ ] `thinking_level` read from `model_config.extra` (default: `"high"`)
- [ ] `thinking_budget` read from `model_config.extra` (default: `-1` for dynamic)
- [ ] `thinking_budget: 0` returns `None` (disables thinking)
- [ ] Other model families return `None`

### Task 1.4: Implement _complete_standard() and _parse_response()

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Implement the standard `generateContent` flow per SDD 4.1.4 and 4.1.5.

**Acceptance Criteria**:
- [ ] Builds request body with `contents`, `generationConfig`, optional `systemInstruction`, optional `thinkingConfig`
- [ ] Auth via `x-goog-api-key` header (default) or query param (legacy), controlled by `auth_mode` in config
- [ ] URL constructed via `_build_url()` (Flatline SKP-003: centralized endpoint)
- [ ] Retryable status codes defined: 429, 500, 503 — retry with exponential backoff + jitter (Flatline IMP-001)
- [ ] Max 3 retries per call, initial backoff 1s, max backoff 8s, jitter 0-500ms (Flatline IMP-001)
- [ ] `_parse_response()` receives explicit `model_id` parameter (no closure over request)
- [ ] `finishReason: SAFETY` raises `InvalidInputError` with safety ratings
- [ ] `finishReason: RECITATION` raises `InvalidInputError`
- [ ] `finishReason: MAX_TOKENS` logs warning, returns truncated response
- [ ] Separates thought parts (`"thought": true`) from content parts
- [ ] Populates `CompletionResult.thinking` from thought parts (or `None`)
- [ ] Populates `Usage` from `usageMetadata` (promptTokenCount, candidatesTokenCount, thoughtsTokenCount)
- [ ] `Usage.source` = `"actual"` when usageMetadata present, `"estimated"` otherwise
- [ ] When `usageMetadata` missing: use conservative estimate based on prompt length + max_tokens, mark `source: "estimated"` (Flatline SKP-007)
- [ ] When `usageMetadata` partial (e.g., missing `thoughtsTokenCount`): default missing fields to 0 with warning log (Flatline SKP-007)
- [ ] Schema-tolerant field access: use `.get()` with defaults for all `usageMetadata` fields (Flatline SKP-001)
- [ ] Empty candidates list raises `InvalidInputError`
- [ ] Latency measured with `time.monotonic()`
- [ ] All log messages use structured format `{event, provider, model, latency_ms, ...}` (Flatline IMP-009)
- [ ] API keys, prompt content, and thinking traces NEVER appear in log output (Flatline IMP-009)

### Task 1.5: Implement error mapping

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Map Google API HTTP status codes to Hounfour error types per SDD 4.1.6.

**Acceptance Criteria**:
- [ ] 400 (INVALID_ARGUMENT, FAILED_PRECONDITION) → `InvalidInputError`
- [ ] 401 (UNAUTHENTICATED) → `ConfigError` (exit code 4)
- [ ] 403 (PERMISSION_DENIED) → `ProviderUnavailableError`
- [ ] 404 (NOT_FOUND) → `InvalidInputError`
- [ ] 429 (RESOURCE_EXHAUSTED) → `RateLimitError`
- [ ] 500, 503 → `ProviderUnavailableError`
- [ ] Error response body parsed for `error.message` when available
- [ ] Unknown status codes fall through to `ProviderUnavailableError`

### Task 1.6: Extend ModelConfig and model-config.yaml

**File**: `.claude/adapters/loa_cheval/types.py`
**Also**: `.claude/defaults/model-config.yaml`

Add Gemini 3 models, Deep Research config, new aliases, and agent bindings per SDD 4.7 and 5.1.

**Acceptance Criteria**:
- [ ] `ModelConfig` extended with `api_mode: Optional[str]` and `extra: Optional[Dict[str, Any]]`
- [ ] Config loader parses `api_mode` and `extra` from YAML into `ModelConfig`
- [ ] `gemini-3-flash` and `gemini-3-pro` added to `providers.google.models`
- [ ] `deep-research-pro` added with `api_mode: interactions` and polling config
- [ ] Aliases added: `deep-thinker`, `fast-thinker`, `researcher`
- [ ] Agent bindings added: `deep-researcher`, `deep-thinker`, `fast-thinker`, `literature-reviewer`
- [ ] Placeholder pricing populated for all new models
- [ ] Existing models/aliases/bindings unchanged (backward compatible)

### Task 1.7: Add --prompt flag to cheval.py

**File**: `.claude/adapters/cheval.py`

Add `--prompt` argument for inline prompt text (alternative to `--input`/stdin).

**Acceptance Criteria**:
- [ ] `--prompt TEXT` accepted as argument
- [ ] When `--prompt` provided, overrides `--input` and stdin
- [ ] Prompt text wrapped as `[{"role": "user", "content": TEXT}]` message list
- [ ] Works with existing `--agent`, `--output-format`, `--max-tokens` flags
- [ ] Error if both `--prompt` and `--input` provided (mutually exclusive)

### Task 1.8: Unit tests for GoogleAdapter

**File**: `.claude/adapters/tests/test_google_adapter.py`

Comprehensive unit tests for all GoogleAdapter methods per SDD 8.1.

**Acceptance Criteria**:
- [ ] `test_translate_messages_basic` — user/assistant to Gemini format
- [ ] `test_translate_messages_system` — system message to systemInstruction
- [ ] `test_translate_messages_multiple_system` — multiple system concatenated
- [ ] `test_translate_messages_unsupported` — array content raises InvalidInputError
- [ ] `test_translate_messages_empty_content` — empty strings skipped
- [ ] `test_build_thinking_gemini3` — thinkingLevel for gemini-3-pro
- [ ] `test_build_thinking_gemini25` — thinkingBudget for gemini-2.5-pro
- [ ] `test_build_thinking_disabled` — thinkingBudget=0 returns None
- [ ] `test_build_thinking_other_model` — non-Gemini returns None
- [ ] `test_parse_response_with_thinking` — thought parts separated
- [ ] `test_parse_response_no_thinking` — thinking=None when no thought parts
- [ ] `test_parse_response_safety_block` — SAFETY finishReason raises error
- [ ] `test_parse_response_recitation` — RECITATION raises error
- [ ] `test_parse_response_max_tokens` — MAX_TOKENS returns truncated + warning
- [ ] `test_parse_response_empty_candidates` — raises InvalidInputError
- [ ] `test_parse_usage_metadata` — all token counts populated
- [ ] `test_error_mapping_400` — 400 → InvalidInputError
- [ ] `test_error_mapping_429` — 429 → RateLimitError
- [ ] `test_error_mapping_500` — 500 → ProviderUnavailableError
- [ ] `test_validate_config_missing_key` — missing GOOGLE_API_KEY reported
- [ ] `test_parse_response_missing_usage` — no usageMetadata → conservative estimate with source="estimated" (Flatline SKP-007)
- [ ] `test_parse_response_partial_usage` — missing thoughtsTokenCount → default 0 (Flatline SKP-007)
- [ ] `test_parse_response_unknown_finish_reason` — unknown finishReason → log warning, return content (Flatline SKP-001)
- [ ] `test_retry_on_429` — retries with backoff on 429 (Flatline IMP-001)
- [ ] `test_retry_on_500` — retries with backoff on 500 (Flatline IMP-001)
- [ ] `test_no_retry_on_400` — no retry on 400 (non-retryable) (Flatline IMP-001)
- [ ] `test_translate_messages_capability_check` — array content suggests fallback provider (Flatline SKP-002)
- [ ] `test_log_redaction` — verify API key and prompt content absent from log output (Flatline IMP-009)
- [ ] All tests run without live API (mocked HTTP)

### Task 1.9: Mock API response fixtures

**File**: `.claude/adapters/tests/fixtures/gemini-standard-response.json`
**Also**: `.claude/adapters/tests/fixtures/gemini-thinking-response.json`
**Also**: `.claude/adapters/tests/fixtures/gemini-safety-block.json`
**Also**: `.claude/adapters/tests/fixtures/gemini-error-429.json`

**Acceptance Criteria**:
- [ ] Standard response fixture with content parts and usageMetadata
- [ ] Thinking response fixture with `"thought": true` parts interleaved
- [ ] Safety block fixture with SAFETY finishReason and safetyRatings
- [ ] Rate limit error fixture (429 HTTP status with error body)
- [ ] All fixtures match actual Gemini API response structure

---

## Sprint 2: Deep Research Adapter

**Goal**: Extend GoogleAdapter with Deep Research support via the Interactions API. Implement blocking-poll, non-blocking mode, concurrency control, and citation normalization. Depends on Sprint 1 (needs working GoogleAdapter).

**Global Sprint ID**: sprint-6

### Task 2.1: Implement _complete_deep_research() blocking-poll

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Implement the Interactions API blocking-poll flow per SDD 4.2.1.

**Acceptance Criteria**:
- [ ] `POST /v1beta/models/{model}:createInteraction` with `background: true`
- [ ] `store` defaults to `false` (privacy, per Flatline SKP-002)
- [ ] `store` configurable via `model_config.extra.store`
- [ ] Extracts `interaction_id` from response `name` field (schema-tolerant parsing)
- [ ] Polls with exponential backoff: initial_delay → 2x → capped at max_delay
- [ ] Schema-tolerant status check: accepts `status`, `state` field names; case-insensitive
- [ ] Completes on `completed`, `done`, `succeeded` states
- [ ] Fails on `failed`, `error`, `cancelled` states with error message
- [ ] Progress logged to stderr every 30s (structured format, no prompt content — Flatline IMP-009)
- [ ] `TimeoutError` raised after configurable timeout (default 600s)
- [ ] Polling config read from `model_config.extra.polling`
- [ ] Auth via `x-goog-api-key` header (consistent with standard flow)
- [ ] Pinned to v1beta API endpoint via `_build_url()` (Flatline IMP-005/SKP-003)
- [ ] Poll requests retry on transient 429/5xx with backoff before failing (Flatline SKP-009)
- [ ] Unknown/unexpected status values logged as warning, continue polling (Flatline SKP-009)
- [ ] Interaction metadata (id, model, start_time) persisted to `.run/.dr-interactions.json` for recovery (Flatline SKP-009)
- [ ] On process restart, `poll_interaction()` can resume from persisted metadata (Flatline SKP-009)
- [ ] `interaction_id` used as idempotency key in cost ledger — duplicate entries with same ID are deduplicated (Flatline Beads SKP-002)

### Task 2.2: Implement Deep Research output normalization

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Post-process Deep Research output into structured format per SDD 4.2.3 and PRD SKP-001.

**Acceptance Criteria**:
- [ ] `_normalize_citations()` extracts markdown citation patterns (`[N]` references)
- [ ] Extracts DOI patterns (`10.XXXX/...`)
- [ ] Extracts URLs
- [ ] Returns structured dict: `{summary, claims, citations, raw_output}`
- [ ] When extraction yields nothing: returns `raw_output` with `citations: []` and logs warning
- [ ] Never fails — degraded output (raw_output only) is acceptable
- [ ] `_parse_deep_research_response()` calls `_normalize_citations()` on raw output
- [ ] Result returned as `CompletionResult` with normalized content as JSON string

### Task 2.3: Create FLockSemaphore concurrency control

**File**: `.claude/adapters/loa_cheval/providers/concurrency.py` (new)

Implement file-lock semaphore for limiting concurrent API calls per SDD 4.2.4 / Flatline SKP-005.

**Acceptance Criteria**:
- [ ] `FLockSemaphore(name, max_concurrent, lock_dir)` constructor
- [ ] Context-manager protocol (`__enter__`, `__exit__`) for safe acquire/release
- [ ] `acquire(timeout)` tries each slot with `LOCK_NB`, returns slot index
- [ ] File descriptor stored in `_held_fd` to prevent GC-induced lock release
- [ ] PID written to lock file for stale-lock detection
- [ ] `_check_stale_lock()` removes lock if owning PID no longer exists
- [ ] `release()` unlocks and closes file descriptor
- [ ] `TimeoutError` raised when all slots occupied after timeout
- [ ] Lock files created in `.run/` directory with mode 0o644
- [ ] `.run/` directory created with `os.makedirs(exist_ok=True)` if missing (Flatline SKP-008)
- [ ] Lock acquisition logged with slot index and PID (Flatline SKP-008)
- [ ] Documented: unsupported on NFS/CIFS (flock advisory only); CI containers must use local tmpfs (Flatline SKP-008)
- [ ] Manual unlock: `rm .run/.semaphore-{name}-*.lock` documented in adapter README (Flatline SKP-008)
- [ ] Works with Python 3.8+ and POSIX (fcntl)

### Task 2.4: Wire concurrency into GoogleAdapter

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Use FLockSemaphore to limit concurrent API calls.

**Acceptance Criteria**:
- [ ] Standard models: `FLockSemaphore("google-standard", max_concurrent=5)`
- [ ] Deep Research: `FLockSemaphore("google-deep-research", max_concurrent=3)`
- [ ] Max concurrent values configurable via model-config.yaml `routing.concurrency`
- [ ] Semaphore acquired before API call, released after (via context manager)
- [ ] `TimeoutError` from semaphore mapped to exit code 3

### Task 2.5: Implement non-blocking mode (--async, --poll, --cancel)

**File**: `.claude/adapters/cheval.py`
**Also**: `.claude/adapters/loa_cheval/providers/google_adapter.py`

Add non-blocking Deep Research invocation per SDD 4.2.2 and 4.5.

**Acceptance Criteria**:
- [ ] `--async` flag returns immediately with interaction metadata JSON
- [ ] Returns exit code 8 (INTERACTION_PENDING) on success
- [ ] `--poll INTERACTION_ID` checks status, returns result if complete
- [ ] `--poll` returns exit code 0 if complete, exit code 8 if still pending
- [ ] `--cancel INTERACTION_ID` sends best-effort cancellation (idempotent — cancelling already-cancelled is no-op, Flatline SKP-009)
- [ ] Budget reservation created at `create_interaction()` time, reconciled at poll completion (Flatline Beads SKP-002)
- [ ] Cancel releases budget reservation if interaction not yet completed (Flatline Beads SKP-002)
- [ ] Both `--poll` and `--cancel` require `--agent` to identify provider
- [ ] GoogleAdapter gains `create_interaction()`, `poll_interaction()`, `cancel_interaction()` methods
- [ ] Error handling: invalid interaction ID → exit code 2

### Task 2.6: Add --include-thinking flag

**File**: `.claude/adapters/cheval.py`

Implement thinking trace policy per SDD 4.6 and PRD SKP-004.

**Acceptance Criteria**:
- [ ] `--include-thinking` flag added to argparse
- [ ] Text output format: thinking NEVER printed regardless of flag
- [ ] JSON output without `--include-thinking`: `result.thinking` set to `null`
- [ ] JSON output with `--include-thinking`: `result.thinking` populated
- [ ] Cost ledger records `tokens_reasoning` count only (never trace content)
- [ ] No trace content in `.run/audit.jsonl`

### Task 2.7: Unit tests for Deep Research and concurrency

**File**: `.claude/adapters/tests/test_google_adapter.py` (extend)
**Also**: `.claude/adapters/tests/test_concurrency.py` (new)

**Acceptance Criteria**:
- [ ] `test_deep_research_blocking_poll` — mock poll sequence → completed
- [ ] `test_deep_research_timeout` — mock forever-pending → TimeoutError
- [ ] `test_deep_research_failure` — mock failed status → ProviderUnavailableError
- [ ] `test_deep_research_store_default_false` — verify `store: false` in request body
- [ ] `test_normalize_citations_with_dois` — DOI extraction
- [ ] `test_normalize_citations_with_urls` — URL extraction
- [ ] `test_normalize_citations_empty` — no citations → empty list + raw_output
- [ ] `test_schema_tolerant_status` — "status" and "state" fields both accepted
- [ ] `test_semaphore_acquire_release` — basic acquire/release cycle
- [ ] `test_semaphore_max_concurrent` — max slots enforced
- [ ] `test_semaphore_context_manager` — acquire on enter, release on exit (even on exception)
- [ ] `test_semaphore_stale_lock` — stale PID lock cleaned up
- [ ] `test_deep_research_poll_retry_on_5xx` — transient 500 during poll → retry, then complete (Flatline SKP-009)
- [ ] `test_deep_research_unknown_status` — unknown status string → continue polling (Flatline SKP-009)
- [ ] `test_deep_research_cancel_idempotent` — cancel already-cancelled → no error (Flatline SKP-009)
- [ ] `test_deep_research_interaction_persistence` — metadata saved to .run for recovery (Flatline SKP-009)
- [ ] All unit tests mocked (no live API)
- [ ] `test_semaphore_real_flock` — integration test using REAL flock on Linux tmpdir (Flatline SKP-008)
- [ ] `test_semaphore_concurrent_processes` — fork 2 processes competing for 1 slot → one blocks (Flatline SKP-008)
- [ ] `test_semaphore_crash_recovery` — kill -9 during critical section → stale lock detected and recovered on next acquire (Flatline Beads IMP-004)
- [ ] `test_budget_dedupe_interaction_id` — duplicate ledger entry with same interaction_id → ignored (Flatline Beads SKP-002)

### Task 2.8: Deep Research mock fixtures

**File**: `.claude/adapters/tests/fixtures/gemini-deep-research-create.json`
**Also**: `.claude/adapters/tests/fixtures/gemini-deep-research-pending.json`
**Also**: `.claude/adapters/tests/fixtures/gemini-deep-research-completed.json`
**Also**: `.claude/adapters/tests/fixtures/gemini-deep-research-failed.json`

**Acceptance Criteria**:
- [ ] Create interaction response with `name` field
- [ ] Pending poll response with `status: "processing"`
- [ ] Completed response with `output` containing research text with citations
- [ ] Failed response with `status: "failed"` and error object
- [ ] All fixtures match Interactions API response structure

---

## Sprint 3: Metering Activation + Flatline Routing + Feature Flags

**Goal**: Wire the BudgetEnforcer in cheval.py, extend pricing for per-task models, activate Flatline routing through Hounfour, and implement granular feature flags. Depends on Sprint 1 (needs working adapter pipeline). Independent of Sprint 2.

**Global Sprint ID**: sprint-7

### Task 3.1: Extend PricingEntry for per-task pricing

**File**: `.claude/adapters/loa_cheval/metering/pricing.py`

Add per-task pricing support for Deep Research per SDD 4.3.2.

**Acceptance Criteria**:
- [ ] `PricingEntry` gains `per_task_micro_usd: int = 0` field
- [ ] `PricingEntry` gains `pricing_mode: str = "token"` field ("token", "task", "hybrid")
- [ ] `find_pricing()` reads `per_task_micro_usd` and `pricing_mode` from config
- [ ] `calculate_total_cost()` handles `pricing_mode == "task"`: returns `per_task_micro_usd` as total
- [ ] `calculate_total_cost()` handles `pricing_mode == "hybrid"`: token cost + per-task sum
- [ ] Existing token-based pricing unaffected (backward compatible)

### Task 3.2: Wire BudgetEnforcer in cheval.py

**File**: `.claude/adapters/cheval.py`

Replace `NoOpBudgetHook` with real `BudgetEnforcer` per SDD 4.3.1.

**Acceptance Criteria**:
- [ ] Import `BudgetEnforcer` from `loa_cheval.metering.budget`
- [ ] Read `metering` config section from Hounfour config
- [ ] Create `BudgetEnforcer` with ledger path and trace ID
- [ ] Pass `budget_hook` to `invoke_with_retry()` (or call pre/post directly if retry unavailable)
- [ ] `BudgetExceededError` mapped to exit code 6
- [ ] Budget check gated by `hounfour.metering: true` feature flag
- [ ] When `metering: false`, use `NoOpBudgetHook` (existing behavior)
- [ ] Log budget decisions (allow/block/downgrade) with structured format (Flatline IMP-009)
- [ ] Integration test: assert ledger entries correct under missing/partial Usage metadata (Flatline SKP-007)

### Task 3.3: Implement atomic budget check (Flatline SKP-006)

**File**: `.claude/adapters/loa_cheval/metering/budget.py`

Replace check-then-act with atomic check+reserve per SDD 4.3.4.

**Acceptance Criteria**:
- [ ] `pre_call_atomic()` locks daily-spend file with `fcntl.flock(LOCK_EX)`
- [ ] Atomically reads current spend, checks limit, writes reservation
- [ ] Returns `ALLOW`, `BLOCK`, or `DOWNGRADE`
- [ ] `post_call()` reconciles reservation with actual cost (exactly-once via `interaction_id` dedupe, Flatline Beads SKP-002)
- [ ] Lock released in `finally` block (never leaked)
- [ ] Daily spend file path follows `_daily_spend_path()` convention
- [ ] Creates spend file if missing (first call of the day)

### Task 3.4: Implement TokenBucketLimiter (Flatline IMP-006)

**File**: `.claude/adapters/loa_cheval/metering/rate_limiter.py` (new)

Per-provider RPM/TPM rate limiting per SDD 4.3.5.

**Acceptance Criteria**:
- [ ] `TokenBucketLimiter(rpm, tpm)` constructor with configurable limits
- [ ] `check(provider, estimated_tokens)` returns True if within limits
- [ ] `record(provider, tokens_used)` records usage after completion
- [ ] State stored in `.run/.ratelimit-{provider}.json` (flock-protected, mode 0o600 — Flatline Beads IMP-003)
- [ ] Token bucket refills based on elapsed time since last check
- [ ] Default limits: Google 60 RPM / 1M TPM, OpenAI 500 RPM / 2M TPM
- [ ] Limits configurable via `routing.rate_limits` in model-config.yaml

### Task 3.5: Extend cost ledger for Deep Research entries

**File**: `.claude/adapters/loa_cheval/metering/ledger.py`

Add `pricing_mode` and `interaction_id` fields to ledger entries per SDD 4.3.3.

**Acceptance Criteria**:
- [ ] Ledger entries gain `pricing_mode` field ("token" or "task")
- [ ] Ledger entries gain optional `interaction_id` field (for Deep Research)
- [ ] Deep Research entries: `tokens_in: 0, tokens_out: N, cost_micro_usd: per_task, pricing_mode: "task"`
- [ ] Existing token-based entries unchanged (backward compatible)
- [ ] JSONL append with flock still works correctly

### Task 3.6: Implement granular feature flags

**File**: `.claude/adapters/cheval.py`
**Also**: `.loa.config.yaml`

Replace single `flatline_routing` with per-subsystem flags per SDD 4.4.

**Acceptance Criteria**:
- [ ] Config section: `hounfour.google_adapter`, `hounfour.deep_research`, `hounfour.flatline_routing`, `hounfour.metering`, `hounfour.thinking_traces`
- [ ] `google_adapter: false` blocks Google provider with `ConfigError`
- [ ] `deep_research: false` blocks Deep Research models with `ConfigError`
- [ ] `metering: false` uses `NoOpBudgetHook`
- [ ] `thinking_traces: false` suppresses thinking config in request body
- [ ] Each flag defaults to `true` (opt-out, not opt-in)
- [ ] `.loa.config.yaml` updated with all flags documented
- [ ] `.loa.config.yaml.example` updated as well

### Task 3.7: Wire Flatline routing through Hounfour

**File**: `.claude/scripts/flatline-orchestrator.sh`

Route Flatline model calls through `cheval.py` when enabled per SDD 6.1.

**Acceptance Criteria**:
- [ ] New `call_model_via_hounfour()` function invokes `cheval.py`
- [ ] Checks `hounfour.flatline_routing` flag via `yq`
- [ ] When `true`: uses `call_model_via_hounfour()`
- [ ] When `false`: uses existing `call_model_legacy()` behavior
- [ ] Agent bindings for Flatline roles already exist (no config changes needed)
- [ ] Stderr from cheval.py captured to `${output_file}.err`
- [ ] Exit code propagated correctly
- [ ] All 4 parallel Flatline calls (2 reviewers + 2 skeptics) route through Hounfour

### Task 3.8: Update Agent Teams reference documentation

**File**: `.claude/loa/reference/agent-teams-reference.md`

Add Template 4: Model-Heterogeneous Expert Swarm per PRD FR-5.

**Acceptance Criteria**:
- [ ] New "Template 4: Model-Heterogeneous Expert Swarm" topology section
- [ ] Describes TeamCreate lead + N domain expert teammates pattern
- [ ] Documents `cheval.py` invocation pattern from teammate Bash
- [ ] Includes agent binding presets (deep-researcher, deep-thinker, fast-thinker, literature-reviewer)
- [ ] Cost considerations: per-task Deep Research costs, daily budget limits
- [ ] Environment variable inheritance note (`GOOGLE_API_KEY` from lead process)
- [ ] Example: MAGI-style construct with 3 research tracks

### Task 3.9: Unit tests for metering extensions

**File**: `.claude/adapters/tests/test_pricing_extended.py` (new)

**Acceptance Criteria**:
- [ ] `test_per_task_pricing` — Deep Research → per_task_micro_usd as total
- [ ] `test_hybrid_pricing` — token cost + per-task cost summed
- [ ] `test_pricing_mode_detection` — config `pricing_mode` field parsed correctly
- [ ] `test_budget_atomic_check` — concurrent pre_call_atomic() correctly serialized
- [ ] `test_budget_reservation_reconcile` — post_call adjusts over/under-estimated reservation
- [ ] `test_rate_limiter_rpm` — requests within/exceeding RPM limit
- [ ] `test_rate_limiter_tpm` — tokens within/exceeding TPM limit
- [ ] `test_rate_limiter_refill` — bucket refills after elapsed time
- [ ] `test_feature_flag_google_disabled` — google_adapter: false → ConfigError
- [ ] `test_feature_flag_metering_disabled` — metering: false → NoOpBudgetHook
- [ ] `test_budget_with_missing_usage` — partial/missing usage → conservative estimate used for budget (Flatline SKP-007)
- [ ] `test_budget_with_task_pricing` — Deep Research per-task cost correctly deducted from daily budget (Flatline SKP-007)

### Task 3.10: Integration tests (cheval.py end-to-end)

**File**: `.claude/adapters/tests/test_cheval_google.sh`

**Acceptance Criteria**:
- [ ] `test_dry_run_google` — `--dry-run` resolves google provider correctly
- [ ] `test_invoke_standard_mock` — mock generateContent → CompletionResult via stdout
- [ ] `test_invoke_deep_research_mock` — mock Interactions API → poll → result
- [ ] `test_async_mode` — `--async` returns interaction metadata JSON with exit code 8
- [ ] `test_budget_enforcement` — BudgetEnforcer blocks when over daily limit
- [ ] `test_feature_flag_disabled` — `google_adapter: false` → ConfigError exit code
- [ ] `test_thinking_trace_redaction` — without --include-thinking → thinking is null
- [ ] `test_prompt_flag` — `--prompt "test"` sends inline prompt correctly
- [ ] Tests use mock HTTP server or monkeypatched http_post (no live API)

### Task 3.11: Live API smoke tests

**File**: `.claude/adapters/tests/test_google_smoke.sh`

**Acceptance Criteria**:
- [ ] Skips gracefully if `GOOGLE_API_KEY` not set
- [ ] Gemini 2.5 Flash: standard completion returns content
- [ ] Gemini 2.5 Pro: thinking-enabled completion returns content + usage
- [ ] Gemini 3 Flash: thinkingLevel completion (if available, skip on 404)
- [ ] Gemini 3 Pro: thinkingLevel:high (if available, skip on 404)
- [ ] Deep Research: short query with 60s timeout (if available, skip on 404)
- [ ] Each test validates exit code 0 and non-empty stdout

---

---

## Sprint 4: Hounfour v7 Protocol Alignment

**Goal**: Align Loa's type vocabulary, ecosystem declarations, trust model, and documentation with loa-hounfour v7.0.0. The runtime bridge (Sprints 1-3) is operational; this sprint ensures the metadata and type vocabulary match the current protocol version across the ecosystem.

**Global Sprint ID**: sprint-8

### Task 4.1: Update ecosystem protocol versions

**File**: `.loa.config.yaml`

Update the 3 `butterfreezone.ecosystem[].protocol` entries to reflect actual pinned versions.

**Acceptance Criteria**:
- [x] `loa-finn` entry: `protocol: loa-hounfour@5.0.0` (was `@4.6.0`)
- [x] `loa-hounfour` entry: `protocol: loa-hounfour@7.0.0` (was `@4.6.0`)
- [x] `arrakis` entry: `protocol: loa-hounfour@7.0.0` (was `@4.6.0`)
- [x] No other config sections changed

### Task 4.2: Migrate model-permissions.yaml to trust_scopes

**File**: `.claude/data/model-permissions.yaml`

Replace flat `trust_level: high|medium` with 6-dimensional `trust_scopes` per SDD 11.5.2.

**Acceptance Criteria**:
- [x] All 5 model entries gain `trust_scopes` with 6 dimensions
- [x] `claude-code:session`: high data_access, financial, delegation, model_selection, external_communication; none governance
- [x] `openai:gpt-5.2`: all none (read-only remote model)
- [x] `moonshot:kimi-k2-thinking`: all none (remote analysis)
- [x] `qwen-local:qwen3-coder-next`: medium data_access; all others none
- [x] `anthropic:claude-opus-4-6`: all none (remote model)
- [x] `trust_level` retained as backward-compatible summary field alongside `trust_scopes`
- [x] File header updated with "Hounfour v6+ CapabilityScopedTrust vocabulary"

### Task 4.3: Fix provider type enum in schema

**File**: `.claude/schemas/model-config.schema.json`

Add `"google"` to the provider `type` enum.

**Acceptance Criteria**:
- [x] Provider type enum: `["openai", "anthropic", "openai_compat", "google"]`
- [x] No other schema changes

### Task 4.4: Update capability-schema.md with trust_scopes and v7 type mapping

**File**: `docs/architecture/capability-schema.md`

Three additions:
1. Update trust gradient to show trust_scopes for each level
2. Add "Hounfour v7 Type Mapping" section with Loa pattern correspondences
3. Add "Hounfour Version Lineage" section

**Acceptance Criteria**:
- [x] Trust gradient section shows 6 trust_scopes dimensions for each L1-L4 level
- [x] v7 type mapping table with 5 entries: BridgeTransferSaga, DelegationOutcome, MonetaryPolicy, PermissionBoundary, GovernanceProposal
- [x] Each mapping cites specific Loa file:line and hounfour type
- [x] Version lineage table: v3.0.0 through v7.0.0 with codenames and key additions

### Task 4.5: Update lore entry for hounfour

**File**: `.claude/data/lore/mibera/core.yaml`

Extend the `hounfour` entry's `context` field with v7 era description.

**Acceptance Criteria**:
- [x] Context mentions v7.0.0 "Composition-Aware Economic Protocol"
- [x] References saga patterns, delegation outcomes, monetary policy
- [x] `source` field updated to `loa-hounfour@7.0.0`
- [x] Existing fields (`id`, `term`, `short`, `tags`) unchanged or minimally updated
- [x] Related entries unchanged

### Task 4.6: Regenerate BUTTERFREEZONE.md

Run `butterfreezone-gen.sh` to regenerate the project README from updated sources.

**Acceptance Criteria**:
- [x] BUTTERFREEZONE.md regenerated with updated ecosystem versions
- [x] `butterfreezone-validate.sh` passes with zero failures and zero `proto_version` warnings
- [x] AGENT-CONTEXT block reflects current state

### Task 4.7: Validate all existing tests still pass

Run the full test suite to ensure no regressions from documentation/schema changes.

**Acceptance Criteria**:
- [x] All adapter tests pass (353+ tests, 0 failures)
- [x] All bats tests pass (unit + integration)
- [x] `butterfreezone-validate.sh --strict` passes
- [x] No new warnings in test output

---

## Sprint 5: Bridge Iteration — Metering Correctness and Test Coverage

**Goal**: Address Bridgebuilder findings from bridge-20260218-1402f0 iteration 1. Fix the cross-process clock bug in rate_limiter.py (BB-401), correct token estimation (BB-404), harden budget fallback (BB-405), clean dead code (BB-403), and add missing test coverage for financial arithmetic (BB-406).

**Global Sprint ID**: sprint-9
**Source**: Bridge iteration 1 findings (severity score 17.0)

### Task 5.1: Fix time.monotonic() cross-process bug in rate_limiter.py

**File**: `.claude/adapters/loa_cheval/metering/rate_limiter.py`
**Finding**: BB-401 (HIGH)

Replace `time.monotonic()` with `time.time()` for persisted state. Monotonic clock values are per-process and produce negative elapsed time when read by a different process.

**Acceptance Criteria**:
- [x] `time.monotonic()` replaced with `time.time()` in `_refill()` and `record()` for state persistence
- [x] In-process interval measurement (if any) continues to use `time.monotonic()`
- [x] Add cross-process test: subprocess writes state, parent reads and verifies non-negative refill
- [x] Existing rate limiter tests still pass

### Task 5.2: Fix token estimation using output content for input estimate

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`
**Finding**: BB-404 (MEDIUM)

When `usageMetadata` is missing, input tokens are estimated from output content. Should estimate from input messages instead.

**Acceptance Criteria**:
- [x] Input token estimation uses the original input messages (not output content)
- [x] Output token estimation uses output content (unchanged)
- [x] Safety-blocked responses: input estimated from messages, output = 0
- [x] Add test for token estimation with missing usageMetadata
- [x] Add test for safety-blocked response estimation

### Task 5.3: Fix budget fallback path — ensure post_call on error

**File**: `.claude/adapters/cheval.py`
**Finding**: BB-405 (MEDIUM)

The ImportError fallback path (when `invoke_with_retry` is unavailable) does `pre_call → complete() → post_call`. If `complete()` raises, `post_call` is never called.

**Acceptance Criteria**:
- [x] Fallback path wrapped in `try/finally` to ensure `post_call` runs on error
- [x] Failed requests record zero cost (not missing cost)
- [x] Add test for budget accounting on adapter failure in fallback path

### Task 5.4: Remove dead code in google_adapter.py

**File**: `.claude/adapters/loa_cheval/providers/google_adapter.py`
**Finding**: BB-403 (LOW)

Remove unused `_detect_http_client_for_get()` call in `poll_interaction()`.

**Acceptance Criteria**:
- [x] Unused `client = _detect_http_client_for_get()` call removed from `poll_interaction()`
- [x] `_detect_http_client_for_get()` function definition retained if used by `_poll_get()`, removed otherwise
- [x] No behavioral change — `_poll_get()` continues to work

### Task 5.5: Add test coverage for RemainderAccumulator and overflow guard

**File**: `.claude/adapters/tests/test_pricing_extended.py`
**Finding**: BB-406 (MEDIUM)

Add tests for the two untested financial arithmetic features.

**Acceptance Criteria**:
- [x] Test RemainderAccumulator carry behavior across multiple calls
- [x] Test RemainderAccumulator with zero remainder (no carry)
- [x] Test calculate_cost_micro with values near MAX_SAFE_PRODUCT boundary
- [x] Test calculate_cost_micro with values exceeding MAX_SAFE_PRODUCT
- [x] All new tests pass alongside existing tests

### Task 5.6: Document rate limiter advisory semantics

**File**: `.claude/adapters/loa_cheval/metering/rate_limiter.py`
**Finding**: reframe-1 (REFRAME)

Add docstring clarifying that the rate limiter is advisory (optimistic check), not enforcing. Budget enforcement is the hard gate.

**Acceptance Criteria**:
- [x] Module-level docstring explains advisory vs enforcing semantics
- [x] `check()` method docstring notes non-atomic read (advisory only)
- [x] `record()` method docstring notes atomic write
- [x] Reference to BudgetEnforcer as the enforcing layer

---

## Dependency Graph

```
Sprint 1 (GoogleAdapter core)
    │
    ├──── Sprint 2 (Deep Research)     [blocks on Task 1.1-1.5]
    │
    ├──── Sprint 3 (Metering + Flags)  [blocks on Task 1.1, 1.6, 1.7]
    │
    └──── Sprint 4 (v7 Protocol Alignment)  [blocks on Sprints 1-3 complete]
```

Sprints 2 and 3 are parallelizable after Sprint 1 completes.
Sprint 4 runs after all Phase 1 work is complete.

## Risk Assessment

| Risk | Sprint | Mitigation |
|------|--------|------------|
| Gemini 3 models not yet accessible | S1 | Graceful skip in smoke tests; unit tests mocked |
| Deep Research API schema evolves during preview | S2 | Schema-tolerant polling, pinned v1beta |
| flock semantics vary across OS/filesystem | S2, S3 | POSIX standard, tested on Linux |
| Pricing TBD for Gemini 3 | S3 | Placeholder values, documented as estimated |
| Flatline orchestrator bash changes break existing flow | S3 | Feature flag guards, existing path preserved |

## Success Criteria

All PRD success metrics pass:

**Phase 1 (Sprints 1-3)**:
1. `cheval.py --agent reviewing-code` invokes OpenAI GPT-5.2 (existing, validates routing)
2. `cheval.py --agent deep-researcher` invokes Gemini Deep Research with cited output
3. `cheval.py --agent deep-thinker` invokes Gemini 3 Pro with thinking traces
4. Flatline Protocol routes through Hounfour (all 4 parallel calls)
5. TeamCreate teammate invokes `cheval.py` successfully
6. Google adapter handles errors with correct exit codes
7. All existing tests pass (no regressions)
8. Metering records cost for all external model calls

**Phase 1.5 (Sprint 4)**:
9. Ecosystem protocol versions match actual pins (3/3 entries correct)
10. `model-permissions.yaml` uses 6-dimensional trust_scopes for all 5 models
11. `model-config.schema.json` validates `"google"` provider type
12. `butterfreezone-validate.sh` passes with zero proto_version warnings
13. Hounfour v7 type mapping documented with 5 type correspondences
14. All existing tests still pass (zero regressions from documentation changes)
