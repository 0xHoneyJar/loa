# Sprint 5 Implementation Report

**Sprint**: Sprint 1 — GoogleAdapter — Standard Gemini Models
**Global Sprint ID**: sprint-5
**Cycle**: cycle-026 (Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing)
**Branch**: `feat/cycle-026-hounfour-routing`

## Summary

Implemented the Google Gemini provider adapter for standard models (Gemini 2.5/3) with message translation, thinking configuration, retry logic, error mapping, and comprehensive unit tests. Extended `ModelConfig` with `api_mode` and `extra` fields. Added new models, aliases, and agent bindings to the config registry.

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `.claude/adapters/loa_cheval/providers/google_adapter.py` | **Created** | GoogleAdapter with complete(), _translate_messages(), _build_thinking_config(), _complete_standard(), _parse_response(), error mapping, retry logic |
| `.claude/adapters/loa_cheval/providers/__init__.py` | Modified | Added `"google": GoogleAdapter` to `_ADAPTER_REGISTRY` |
| `.claude/adapters/loa_cheval/types.py` | Modified | Added `api_mode: Optional[str]` and `extra: Optional[Dict[str, Any]]` to `ModelConfig` |
| `.claude/adapters/cheval.py` | Modified | Added `--prompt` flag, `GOOGLE_API_KEY` to redaction list, `INTERACTION_PENDING` exit code, `_build_provider_config()` extended for `api_mode`/`extra` |
| `.claude/defaults/model-config.yaml` | Modified | Added gemini-3-flash, gemini-3-pro, deep-research-pro models; deep-thinker, fast-thinker, researcher aliases; 4 new agent bindings |
| `.claude/adapters/tests/test_google_adapter.py` | **Created** | 49 unit tests covering all adapter methods |
| `.claude/adapters/tests/fixtures/gemini-standard-response.json` | **Created** | Standard Gemini API response fixture |
| `.claude/adapters/tests/fixtures/gemini-thinking-response.json` | **Created** | Thinking response with `thought: true` parts |
| `.claude/adapters/tests/fixtures/gemini-safety-block.json` | **Created** | Safety-blocked response fixture |
| `.claude/adapters/tests/fixtures/gemini-error-429.json` | **Created** | Rate limit error response fixture |

## Task Completion

### Task 1.1: GoogleAdapter skeleton + registration
- [x] `GoogleAdapter` extends `ProviderAdapter`
- [x] Implements `complete()`, `validate_config()`, `health_check()`
- [x] `complete()` branches on `api_mode == "interactions"` (stub for Sprint 2)
- [x] `validate_config()` checks endpoint, auth, type
- [x] `health_check()` uses `models.list` API probe via `_build_url()` (SKP-003)
- [x] Centralized `_build_url(path)` — base URL + API version in one place (SKP-003)
- [x] API version pinned to `v1beta`, configurable via config
- [x] HTTP client: httpx preferred, urllib fallback (IMP-002)
- [x] Registered as `"google": GoogleAdapter` in `_ADAPTER_REGISTRY`
- [x] Python 3.8 compatible (no walrus, no match)

### Task 1.2: _translate_messages()
- [x] System messages extracted → single `systemInstruction` string
- [x] Multiple system messages concatenated with `\n\n`
- [x] `"assistant"` → `"model"` role mapping
- [x] `"content": str` → `"parts": [{"text": str}]`
- [x] Array content blocks raise `InvalidInputError` with type listing (SKP-002)
- [x] Capability check suggests fallback provider (SKP-002)
- [x] Empty content strings skipped
- [x] Returns `Tuple[Optional[str], List[Dict]]`

### Task 1.3: _build_thinking_config()
- [x] Gemini 3: `thinkingLevel` (string)
- [x] Gemini 2.5: `thinkingBudget` (int, -1 dynamic)
- [x] `thinking_budget: 0` → `None` (disables)
- [x] Other models → `None`

### Task 1.4: _complete_standard() + _parse_response()
- [x] Request body with contents, generationConfig, systemInstruction, thinkingConfig
- [x] Auth via `x-goog-api-key` header
- [x] URL via `_build_url()` (SKP-003)
- [x] Retryable codes 429/500/503 with exponential backoff + jitter (IMP-001)
- [x] Max 3 retries, 1s initial, 8s max, 0-500ms jitter (IMP-001)
- [x] `_parse_response()` receives explicit `model_id` parameter
- [x] SAFETY → `InvalidInputError` with safety ratings
- [x] RECITATION → `InvalidInputError`
- [x] MAX_TOKENS → warning + truncated response
- [x] Thought parts separated from content parts
- [x] Usage from `usageMetadata` with schema-tolerant `.get()` (SKP-001)
- [x] Missing usageMetadata → conservative estimate, `source: "estimated"` (SKP-007)
- [x] Partial usageMetadata → default 0, warning log (SKP-007)
- [x] Unknown finishReason → warning, return content (SKP-001)
- [x] Latency via `time.monotonic()`
- [x] Structured log format, no API keys/prompts in logs (IMP-009)

### Task 1.5: Error mapping
- [x] 400 → `InvalidInputError`
- [x] 401 → `ConfigError`
- [x] 403 → `ProviderUnavailableError`
- [x] 404 → `InvalidInputError`
- [x] 429 → `RateLimitError`
- [x] 500/503 → `ProviderUnavailableError`
- [x] Unknown → `ProviderUnavailableError`
- [x] Error body parsed for `error.message`

### Task 1.6: ModelConfig + model-config.yaml
- [x] `ModelConfig` extended with `api_mode` and `extra`
- [x] `_build_provider_config()` parses both fields from YAML
- [x] gemini-3-flash, gemini-3-pro added
- [x] deep-research-pro added with `api_mode: interactions`
- [x] Aliases: deep-thinker, fast-thinker, researcher
- [x] Agent bindings: deep-researcher, deep-thinker, fast-thinker, literature-reviewer
- [x] Placeholder pricing populated
- [x] Backward compatible — existing models/aliases/bindings unchanged

### Task 1.7: --prompt flag
- [x] `--prompt TEXT` accepted
- [x] Overrides --input and stdin
- [x] Mutually exclusive with --input (error if both)
- [x] Works with existing flags
- [x] GOOGLE_API_KEY added to redaction list
- [x] INTERACTION_PENDING exit code added

### Task 1.8: Unit tests — 49 tests passing
- [x] Message translation: basic, system, multiple system, unsupported array, empty content, capability check
- [x] Thinking config: gemini-3, gemini-2.5, disabled, other model, no extra
- [x] Response parsing: standard, thinking, safety, recitation, max_tokens, empty candidates, missing usage, partial usage, unknown finish reason
- [x] Error mapping: 400, 401, 403, 404, 429, 500, 503, unknown
- [x] Retry: 429, 500, no-retry-400, exhausted
- [x] Config validation: valid, missing endpoint, missing auth, wrong type
- [x] URL construction: standard, models list, without version
- [x] Integration: standard complete, thinking complete, API error, deep research stub
- [x] Log redaction: API key and prompt absent from logs
- [x] Registry: google in registry, get_adapter returns GoogleAdapter

### Task 1.9: Mock fixtures
- [x] gemini-standard-response.json — content + usageMetadata
- [x] gemini-thinking-response.json — thought parts interleaved
- [x] gemini-safety-block.json — SAFETY finishReason + safetyRatings
- [x] gemini-error-429.json — rate limit error body

## Test Results

```
49 passed in 7.77s (Google adapter tests)
293 passed, 9 skipped in 10.07s (full adapter test suite)
```

Zero regressions. All existing tests continue to pass.

## Flatline Findings Addressed

| Finding | Status | Implementation |
|---------|--------|---------------|
| IMP-001 (retry/backoff) | Addressed | `_call_with_retry()` with exponential backoff + jitter |
| IMP-002 (HTTP client) | Addressed | httpx preferred, urllib fallback with same timeouts |
| IMP-009 (logging/redaction) | Addressed | Structured logs, no keys/prompts in output |
| SKP-001 (schema-tolerant) | Addressed | `.get()` with defaults for all response fields |
| SKP-002 (array content) | Addressed | InvalidInputError with type listing + fallback suggestion |
| SKP-003 (endpoint centralization) | Addressed | `_build_url()` centralizes URL construction |
| SKP-007 (usage correctness) | Addressed | Conservative estimates, partial metadata handling |

## Architecture Decisions

1. **Retry at adapter level**: Retry logic lives in `_call_with_retry()` inside the Google adapter, not in the shared base. This avoids changing the existing retry module interface while Sprint 1 is focused on Google-specific behavior.

2. **Module-level functions**: `_translate_messages`, `_build_thinking_config`, `_parse_response` are module-level functions (not methods) for testability — matching the pattern used in `anthropic_adapter.py`.

3. **Deep Research stub**: `_complete_deep_research()` raises `InvalidInputError` with a clear message. Sprint 2 will implement the Interactions API path.

4. **Health check GET**: Uses a separate `_detect_http_client_for_get()` helper since `http_post()` in base.py only does POST. The health probe hits `models.list` (same base URL as generateContent) per SKP-003.
