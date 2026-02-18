# Sprint 6 Security Audit

**Sprint**: Sprint 2 — Deep Research Adapter
**Global Sprint ID**: sprint-6
**Cycle**: cycle-026 (Hounfour Runtime Bridge — Model-Heterogeneous Agent Routing)
**Auditor**: Paranoid Cypherpunk Auditor
**Date**: 2026-02-18

## Verdict

**APPROVED - LETS FUCKING GO**

## Audit Scope

Files audited:

| File | Lines | Focus |
|------|-------|-------|
| `.claude/adapters/loa_cheval/providers/google_adapter.py` | 870 | Full security review |
| `.claude/adapters/loa_cheval/providers/concurrency.py` | 174 | Concurrency + lock safety |
| `.claude/adapters/cheval.py` | 562 | CLI entry point + new DR commands |
| `.claude/adapters/tests/test_google_adapter.py` | 959 | Test coverage review |
| `.claude/adapters/tests/test_concurrency.py` | 154 | Concurrency test coverage |
| `.claude/adapters/tests/fixtures/gemini-deep-research-*.json` | 4 files | Fixture safety |

## Security Checklist

### 1. Secrets & Credentials

| Check | Status | Notes |
|-------|--------|-------|
| No hardcoded API keys in source | PASS | Auth flows through `_get_auth_header()` from config |
| No hardcoded API keys in fixtures | PASS | Fixtures use synthetic data only |
| Test API key is obviously fake | PASS | `"test-google-api-key"` and `"AIzaSyDEADBEEF1234567890"` (test-only) |
| Error message redaction | PASS | `cheval.py:401-406` strips `GOOGLE_API_KEY` from error messages |
| Log redaction verified by test | PASS | `TestLogRedaction.test_api_key_not_in_logs` confirms API key + prompt content absent from logs |
| API key transmitted via header only | PASS | `x-goog-api-key` header, not query parameter. Good -- no URL logging leaks |

### 2. Input Validation

| Check | Status | Notes |
|-------|--------|-------|
| `create_interaction` validates interaction ID | PASS | Lines 198-201: raises `InvalidInputError` if no ID returned |
| Empty user content handled | PASS | `cheval.py:273-275` rejects empty input before reaching adapter |
| Array content blocks rejected | PASS | `_translate_messages` raises `InvalidInputError` for non-string content blocks |
| Mutual exclusion of `--prompt`/`--input` | PASS | `cheval.py:257-259` enforced |
| `--poll` and `--cancel` require `--agent` | PASS | `cmd_poll:438-440`, `cmd_cancel:481-483` guard checked |

### 3. Authentication & Authorization

| Check | Status | Notes |
|-------|--------|-------|
| Feature flags gate provider access | PASS | `_check_feature_flags` blocks Google and DR models when disabled |
| Budget enforcement hooks wired | PASS | `BudgetEnforcer` pre/post call pattern; `BLOCK` status raises `BudgetExceededError` |
| No privilege escalation paths | PASS | CLI is a single-user tool; no auth escalation vectors |

### 4. Concurrency & Race Conditions

| Check | Status | Notes |
|-------|--------|-------|
| `FLockSemaphore` uses `LOCK_NB` | PASS | Non-blocking try with backoff; no deadlock risk |
| Semaphore release in `__exit__` | PASS | Context manager pattern ensures release on exception |
| `_persist_interaction` flock-protected | PASS | `fcntl.flock(LOCK_EX)` around read-modify-write (Review CONCERN-5 fix) |
| Stale lock detection via PID check | PASS | `os.kill(pid, 0)` probe + cleanup on `OSError` |
| Lock file permissions | PASS | `0o644` -- readable by others but only writable by owner |
| Semaphore timeout configurable | PASS | DR path uses `timeout=max_poll_time` (Review CONCERN-4 fix) |

### 5. Error Handling & Information Disclosure

| Check | Status | Notes |
|-------|--------|-------|
| No stack traces to stdout | PASS | All errors go to stderr via `_error_json()` |
| Sensitive data stripped from unexpected errors | PASS | `cheval.py:401-406` redacts known API key env vars |
| Poll progress logs omit prompt content | PASS | Line 364 comment: "no prompt content -- IMP-009"; logs only interaction ID + elapsed time |
| Citation extraction never fails | PASS | `_normalize_citations` wraps everything in try/except, returns raw_output on failure |
| Unknown poll states logged, not crashed | PASS | Lines 358-362: warning logged, polling continues |

### 6. API Security

| Check | Status | Notes |
|-------|--------|-------|
| Retry with exponential backoff + jitter | PASS | `_call_with_retry`: 1s base, 2x growth, 8s cap, 500ms random jitter |
| Retry capped at 3 attempts | PASS | `_MAX_RETRIES = 3`; no infinite loops |
| Poll timeout enforced | PASS | `poll_interaction` checks `elapsed >= timeout` every cycle |
| Retryable status codes scoped | PASS | Only 429, 500, 503 are retried; 400/401/403/404 fail immediately |
| Cancel is best-effort/idempotent | PASS | Returns True for status < 500, including 400 (already cancelled) |
| URL construction centralized | PASS | `_build_url` prevents version doubling; no user input in URL path |

### 7. Data Privacy

| Check | Status | Notes |
|-------|--------|-------|
| `store: false` by default | PASS | Deep Research `store` defaults to `False` (Flatline SKP-002) |
| Interaction persistence is local | PASS | `.run/.dr-interactions.json` -- local filesystem only, not transmitted |
| Thinking traces gated by `--include-thinking` | PASS | `cheval.py:370-371`: thinking only in JSON output when flag set; NEVER in text mode (line 377) |

### 8. Code Quality

| Check | Status | Notes |
|-------|--------|-------|
| Type annotations present | PASS | All functions have type comment annotations |
| Consistent error hierarchy | PASS | Uses established `ChevalError` subtypes throughout |
| No unused imports | PASS | Clean import blocks |
| Test coverage adequate | PASS | 22 new adapter tests + 8 concurrency tests; covers happy path, error paths, edge cases, concurrent scenarios |
| Fixtures are representative | PASS | 4 DR fixtures covering create, pending, completed, and failed states |
| httpx/urllib dual-path tested | PASS | `_poll_get` and `_detect_http_client_for_get` both handle ImportError fallback |

### 9. Review Concerns Addressed

| Concern | Fix Verified |
|---------|-------------|
| CONCERN-2: Missing context window validation in DR path | PASS -- `enforce_context_window(request, model_config)` at line 188 |
| CONCERN-4: Semaphore timeout too short for DR | PASS -- `FLockSemaphore` accepts `timeout` in constructor; DR uses `timeout=max_poll_time` |
| CONCERN-5: Race condition in `_persist_interaction()` | PASS -- `fcntl.flock(LOCK_EX)` with try/finally unlock around read-modify-write |

## Findings

**No security issues found.** Implementation is solid:

- Auth is never logged, never in URLs, and redacted from error messages
- Concurrency control uses POSIX-standard advisory locks with stale detection
- All user input is validated before reaching API calls
- Error handling is comprehensive without information disclosure
- Retry/timeout behavior is bounded and configurable
- The thinking trace policy correctly defaults to suppressed

## Notes

- The `_INTERACTIONS_FILE` path (`.run/.dr-interactions.json`) is hardcoded rather than configurable. This is acceptable for the current scope but should be made configurable if the persistence layer grows.
- The stale lock detection in `_check_stale_lock` uses `os.kill(pid, 0)` which could false-positive if the PID was recycled. The window is extremely narrow and the consequence is benign (failed lock acquisition, not data loss), so this is not a blocker.
