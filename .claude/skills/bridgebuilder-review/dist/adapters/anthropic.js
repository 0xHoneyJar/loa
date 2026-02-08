const API_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CEILING_MS = 60_000;
export class AnthropicAdapter {
    apiKey;
    model;
    timeoutMs;
    constructor(apiKey, model, timeoutMs = DEFAULT_TIMEOUT_MS) {
        if (!apiKey) {
            throw new Error("ANTHROPIC_API_KEY required (set via environment)");
        }
        if (!model) {
            throw new Error("Anthropic model is required");
        }
        this.apiKey = apiKey;
        this.model = model;
        this.timeoutMs = timeoutMs;
    }
    async generateReview(request) {
        const body = JSON.stringify({
            model: this.model,
            max_tokens: request.maxOutputTokens,
            system: request.systemPrompt,
            messages: [{ role: "user", content: request.userPrompt }],
        });
        let lastError;
        let retryAfterMs = 0;
        for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
            if (attempt > 0) {
                // Use retry-after if server provided it, otherwise exponential backoff
                const delay = retryAfterMs > 0
                    ? retryAfterMs
                    : Math.min(BACKOFF_BASE_MS * Math.pow(2, attempt - 1), BACKOFF_CEILING_MS);
                retryAfterMs = 0;
                await sleep(delay);
            }
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), this.timeoutMs);
            try {
                const response = await fetch(API_URL, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "x-api-key": this.apiKey,
                        "anthropic-version": API_VERSION,
                    },
                    body,
                    signal: controller.signal,
                });
                clearTimeout(timer);
                if (response.status === 429 || response.status >= 500) {
                    retryAfterMs = parseRetryAfter(response.headers.get("retry-after"));
                    // Do not include response body — may contain sensitive details
                    lastError = new Error(`Anthropic API ${response.status}`);
                    continue;
                }
                if (!response.ok) {
                    // Do not include response body — may contain echoed prompt content
                    throw new Error(`Anthropic API ${response.status}`);
                }
                let data;
                try {
                    data = (await response.json());
                }
                catch {
                    // Truncated/invalid JSON from proxy/CDN — treat as retryable
                    lastError = new Error("Anthropic API invalid JSON response");
                    continue;
                }
                const content = data.content
                    ?.filter((b) => b.type === "text")
                    .map((b) => b.text)
                    .join("\n") ?? "";
                return {
                    content,
                    inputTokens: data.usage?.input_tokens ?? 0,
                    outputTokens: data.usage?.output_tokens ?? 0,
                    model: data.model ?? this.model,
                };
            }
            catch (err) {
                clearTimeout(timer);
                const name = err?.name ?? "";
                const msg = err instanceof Error ? err.message : String(err);
                // Retry on timeouts
                if (name === "AbortError") {
                    lastError = new Error("Anthropic API request timed out");
                    continue;
                }
                // Retry on transient network errors (TypeError from fetch, connection resets)
                if (err instanceof TypeError || /ECONNRESET|ENOTFOUND|EAI_AGAIN|ETIMEDOUT/i.test(msg)) {
                    lastError = new Error(`Anthropic API network error`);
                    continue;
                }
                throw err;
            }
        }
        throw lastError ?? new Error("Anthropic API failed after retries");
    }
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
/** Parse retry-after header — supports seconds (numeric) and HTTP-date formats. */
function parseRetryAfter(value) {
    if (!value)
        return 0;
    const seconds = Number(value);
    if (!isNaN(seconds) && seconds > 0) {
        return Math.min(seconds * 1000, BACKOFF_CEILING_MS);
    }
    // Try HTTP-date format
    const date = Date.parse(value);
    if (!isNaN(date)) {
        const delayMs = date - Date.now();
        return delayMs > 0 ? Math.min(delayMs, BACKOFF_CEILING_MS) : 0;
    }
    return 0;
}
//# sourceMappingURL=anthropic.js.map