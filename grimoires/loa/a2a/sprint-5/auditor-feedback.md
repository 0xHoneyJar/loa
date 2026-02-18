# Sprint 5 Security Audit

**Sprint**: Sprint 1 — GoogleAdapter — Standard Gemini Models
**Global Sprint ID**: sprint-5
**Cycle**: cycle-026 (Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing)
**Auditor**: Paranoid Cypherpunk Auditor
**Decision**: APPROVED - LETS FUCKING GO

## Audit Scope

Reviewed all files listed in the implementation report against the security checklist. Code was read line-by-line for each file. Tests were executed and verified passing (70/70 adapter tests, 353/353 full suite, 0 regressions).

### Files Audited

| File | Lines | Verdict |
|------|-------|---------|
| `.claude/adapters/loa_cheval/providers/google_adapter.py` | 870 | PASS |
| `.claude/adapters/loa_cheval/providers/__init__.py` | 31 | PASS |
| `.claude/adapters/loa_cheval/types.py` | 181 | PASS |
| `.claude/adapters/loa_cheval/providers/concurrency.py` | 174 | PASS |
| `.claude/adapters/cheval.py` | 562 | PASS |
| `.claude/defaults/model-config.yaml` | 203 | PASS |
| `.claude/adapters/tests/test_google_adapter.py` | 959 | PASS |
| `.claude/adapters/tests/fixtures/gemini-*.json` | 8 fixtures | PASS |

## Security Checklist

### 1. Secrets & Credential Handling — PASS

- **API key resolution**: Google API key resolved via `_get_auth_header()` which reads from `config.auth` (sourced from `{env:GOOGLE_API_KEY}` interpolation). No hardcoded keys anywhere.
- **Header-based auth**: API key transmitted via `x-goog-api-key` header (lines 150-153 of google_adapter.py), not URL query parameters. The SDD mentioned legacy query param mode, but the implementation correctly defaults to header auth only.
- **Redaction in cheval.py**: `GOOGLE_API_KEY` added to the env-key redaction loop at line 403 of cheval.py. Any error message containing the key value gets `***REDACTED***` treatment.
- **No keys in logs**: Log statements (lines 585-591, 669-675) log only model_id, latency, and token counts. The test `test_api_key_not_in_logs` explicitly verifies this.
- **No keys in fixtures**: All 8 test fixture JSON files contain only response structures, no API keys or auth tokens.

### 2. Auth & Authorization — PASS

- **validate_config()** checks endpoint, auth, and type fields exist and are correct (lines 71-81).
- **_get_auth_header()** in base.py properly handles None auth, non-string LazyValue resolution, and empty strings with appropriate ConfigError raises.
- **No privilege escalation paths**: Adapter is a request-response client with no administrative API calls exposed. Health check uses read-only `models.list`.

### 3. Input Validation — PASS

- **Array content blocks rejected**: `_translate_messages()` raises `InvalidInputError` for non-string content arrays (lines 426-442). Lists unsupported types in error message. Suggests fallback provider when multimodal capabilities are missing.
- **Empty content filtered**: Lines 444-445 skip empty/whitespace-only content strings rather than sending empty parts.
- **Model routing boundary**: `complete()` branches on `api_mode` with explicit "interactions" check (line 66). Deep Research stub raises clear `InvalidInputError` rather than silently failing.
- **Context window enforcement**: `enforce_context_window()` called before any API call (line 122 for standard, line 188 for DR).
- **Mutually exclusive flags**: `--prompt` and `--input` are mutually exclusive (cheval.py lines 257-259).

### 4. Data Privacy — PASS

- **Deep Research `store` defaults to `false`**: Line 185 of google_adapter.py. Test `test_store_default_false` verifies this.
- **Thinking trace policy enforced**: JSON output only includes thinking when `--include-thinking` flag is set (cheval.py line 370). Text mode never prints thinking (line 377). Cost ledger records only token counts, never trace content.
- **No PII collection**: Adapter processes messages as pass-through to API. No local persistence of user content beyond the interaction persistence file (which stores only interaction_id, model, start_time, PID).

### 5. API Security — PASS

- **Retry with backoff**: `_call_with_retry()` implements exponential backoff with jitter (lines 643-678). Retryable codes limited to {429, 500, 503}. Max 3 retries, 1s initial, 8s max, 0-500ms jitter. Non-retryable errors (400, 401, 403, 404) fail immediately.
- **Concurrency control**: `FLockSemaphore` limits concurrent API calls (5 for standard, 3 for Deep Research). Uses POSIX flock with stale-lock detection via PID checking. Context manager ensures release on exception.
- **Timeout enforcement**: Configurable connect_timeout (10s default) and read_timeout (120s default) passed through to HTTP client. Deep Research has separate, longer timeouts.
- **Circuit breaker**: Existing circuit breaker from retry module applies across the `invoke_with_retry` path.

### 6. Error Handling — PASS

- **No info disclosure**: Error messages from Google API are surfaced but redacted for sensitive values. `_extract_error_message()` safely navigates the error response structure (lines 629-637).
- **Structured error output**: All errors go to stderr as JSON (cheval.py `_error_json()`). Stdout reserved for model output only.
- **Graceful degradation**: Missing `usageMetadata` falls back to conservative estimates with `source: "estimated"` (lines 571-583). Partial metadata defaults missing fields to 0 with warning log. Unknown `finishReason` values log warning and return content rather than crashing.
- **Exception safety**: `_poll_get()` catches all expected exception types (httpx.HTTPError, URLError, OSError, JSONDecodeError) and returns 503 status codes for graceful degradation (lines 785-829). This was the F1 finding from the review, now resolved.
- **Health check**: Returns False on any exception rather than propagating (line 97).

### 7. Code Quality — PASS

- **Python 3.8 compatible**: No walrus operators, no match statements, no f-strings in the adapter file (uses `%s` formatting). Type annotations use comment syntax for backward compatibility.
- **Module-level functions**: `_translate_messages`, `_build_thinking_config`, `_parse_response` are standalone functions for testability, matching the pattern in `anthropic_adapter.py`.
- **Explicit parameters**: `_parse_response()` receives `model_id` as an explicit parameter (not closure capture), preventing scope bugs.
- **No unused imports**: The F3 finding (unused `import json as _json` local import) was resolved per the engineer feedback.
- **Test coverage**: 70 tests covering all adapter methods, all error paths, all edge cases. Test class organization mirrors the implementation structure.

## Observations (Non-Blocking)

### OBS-1: FLockSemaphore advisory lock limitation (LOW)

Advisory locks are cooperative only. A process that does not use `FLockSemaphore` can still make API calls. This is acceptable for the current architecture where all calls route through `cheval.py`, but should be documented if other entry points are added.

**Status**: Acknowledged in concurrency.py docstring (lines 8-10). No action needed.

### OBS-2: Interaction persistence file not cleaned up (LOW)

`.run/.dr-interactions.json` accumulates entries over time but is never pruned. For long-running projects, this file could grow unbounded.

**Status**: Low priority. File size is trivial (a few KB per interaction). Can be addressed in a future cycle.

### OBS-3: URL regex in citation extraction (LOW)

The URL regex on line 706 (`https?://[^\s<>"'\]),]+[^\s<>"'\]),.]`) may miss some edge cases or match trailing punctuation. This is a best-effort extraction and the code correctly falls back to `raw_output` when extraction yields nothing.

**Status**: Acceptable for MVP. The `_normalize_citations` function is designed to never fail (try/except on line 719).

## Verdict

The implementation is secure, well-tested, and follows established patterns. All OWASP-relevant concerns are addressed. API keys are properly handled. Input validation rejects unsupported content. Error handling is comprehensive with no information disclosure. The code is backward compatible with zero regressions across the full 353-test suite.

**APPROVED - LETS FUCKING GO**
