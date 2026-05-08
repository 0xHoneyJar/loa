/**
 * Diagnostic-context formatter for LLM provider adapter errors.
 *
 * Closes the diagnostic-context gap that issue #789 surfaced for the
 * bridgebuilder TS adapters: when a model call fails with a `TypeError`
 * (the most common Node.js `fetch` failure mode for premature stream
 * close, RemoteProtocolError, malformed SSE, TLS reset, etc.), the
 * existing catch blocks rewrap the failure as a generic
 * `LLMProviderError("NETWORK", "Google/OpenAI/Anthropic API network
 * error")` — losing the underlying cause, the request size, the
 * attempt count, and the model identifier.
 *
 * Operators triaging a multi-model bridge run see "Google API network
 * error" for every failure class and cannot distinguish:
 *   - Premature stream close mid-response
 *   - Connection reset (ECONNRESET / ETIMEDOUT)
 *   - DNS failure (ENOTFOUND)
 *   - TLS handshake failure
 *   - Malformed SSE chunk
 *   - Body parse error
 *
 * This module mirrors the pattern landed upstream in PR #781
 * (cheval #774 closure) where the Python cheval adapters gained a
 * typed `ConnectionLostError` carrying `transport_class` +
 * `request_size_bytes`. The TypeScript adapters now carry the same
 * diagnostic context inline in the `LLMProviderError.message` (the
 * existing `LLMProviderError` class is read-only at the field level
 * to preserve cross-runner contract; the message string is the
 * extension surface).
 *
 * **Sanitization rule.** The diagnostic detail MUST NOT include:
 *   - Request body (potentially contains user prompts)
 *   - Request headers (contains API keys / auth tokens)
 *   - Response body content (potentially contains generated content)
 *   - URL query strings (contain `?key=...` for Google)
 *
 * Only the underlying `Error.name` + `Error.message` is included. If
 * the error has a `cause` chain (Node.js `fetch` wraps low-level
 * `UND_ERR_*` errors in `err.cause`), one level of cause is unwrapped
 * — sufficient for diagnosis without exposing arbitrary nested state.
 *
 * @see https://github.com/0xHoneyJar/loa/issues/789 — bridgebuilder TS adapter regression
 * @see https://github.com/0xHoneyJar/loa/pull/781 — cheval Python equivalent (closed #774)
 * @since v1.X.0 — TS adapter diagnostic-context backport
 */

/**
 * Format a diagnostic-context string for inclusion in an
 * `LLMProviderError.message`. Returns a string suitable for appending
 * after the provider-specific prefix (e.g., `"Google API network
 * error: <detail>"`).
 *
 * Caller is responsible for the prefix; this helper formats only the
 * detail portion.
 *
 * @param err - The caught error. May be any value (the catch clause
 *              is `unknown`-typed in the adapters).
 * @param requestSizeBytes - The byte length of the request body.
 *                           Surfaces the "did the request reach
 *                           Google's edge" question without exposing
 *                           the body content.
 * @param attempt - 0-indexed attempt number (the call number, not
 *                  the retry number).
 * @param maxAttempts - Total attempts the adapter will make
 *                      (`MAX_RETRIES + 1`).
 * @param model - Model identifier (e.g., `"gemini-2.5-pro"`). Surfaces
 *                which model the failure came from in multi-model runs.
 */
export function formatDiagnosticDetail(
  err: unknown,
  requestSizeBytes: number,
  attempt: number,
  maxAttempts: number,
  model: string,
): string {
  const errName = err instanceof Error ? err.name : typeof err;
  const errMessage = err instanceof Error
    ? sanitizeMessage(err.message)
    : sanitizeMessage(String(err));

  // Unwrap one level of `err.cause` — Node.js `fetch` wraps undici
  // low-level errors (UND_ERR_SOCKET, UND_ERR_BODY_TIMEOUT, etc.) in
  // `err.cause` when the network path fails mid-stream. The cause is
  // the operator-actionable signal.
  let causeDetail = "";
  if (err instanceof Error && err.cause !== undefined) {
    const cause = err.cause;
    const causeName = cause instanceof Error ? cause.name : typeof cause;
    const causeMessage = cause instanceof Error
      ? sanitizeMessage(cause.message)
      : sanitizeMessage(String(cause));
    causeDetail = `; cause=${causeName}: ${causeMessage}`;
  }

  return (
    `${errName}: ${errMessage}${causeDetail} ` +
    `(request_size=${requestSizeBytes}B, attempt=${attempt + 1}/${maxAttempts}, model=${model})`
  );
}

/**
 * Strip patterns that may carry secrets from an error message before
 * including it in a diagnostic surface. Conservative: rejects anything
 * that looks like an auth token, API key, or URL query string.
 *
 * The bridgebuilder error messages are surfaced via `console.warn`
 * (per `multi-model-pipeline.ts:248`), the GitHub PR comment
 * (per the multi-model post path), and the audit JSONL log — three
 * surfaces where a leaked credential would be persisted. The
 * sanitization is the floor.
 */
function sanitizeMessage(msg: string): string {
  return msg
    // Strip URL query strings (Google API key auth uses ?key=...).
    .replace(/\?key=[A-Za-z0-9_\-]+/g, "?key=<redacted>")
    // Strip Bearer / api-key headers if they leak into messages.
    .replace(/[Bb]earer\s+[A-Za-z0-9_\-.]+/g, "Bearer <redacted>")
    .replace(/[Aa]pi[-_]?key[=:]\s*[A-Za-z0-9_\-]+/g, "api-key=<redacted>")
    // Cap length so a runaway response body in `err.message` doesn't
    // produce 100KB log lines.
    .slice(0, 1024);
}
