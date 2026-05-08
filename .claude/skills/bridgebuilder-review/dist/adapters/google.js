import { LLMProviderError, } from "../ports/llm-provider.js";
import { formatDiagnosticDetail } from "./diagnostic-context.js";
const API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CEILING_MS = 60_000;
/** Default cost rates (USD per 1K tokens) — overridable via config.cost_rates. */
const DEFAULT_COST_INPUT = 0.00125;
const DEFAULT_COST_OUTPUT = 0.005;
export class GoogleAdapter {
    apiKey;
    model;
    timeoutMs;
    costInput;
    costOutput;
    constructor(apiKey, model, timeoutMs = DEFAULT_TIMEOUT_MS, options) {
        if (!apiKey) {
            throw new Error("GOOGLE_API_KEY required (set via environment)");
        }
        if (!model) {
            throw new Error("Google model is required");
        }
        this.apiKey = apiKey;
        this.model = model;
        this.timeoutMs = timeoutMs;
        this.costInput = options?.costRates?.input ?? DEFAULT_COST_INPUT;
        this.costOutput = options?.costRates?.output ?? DEFAULT_COST_OUTPUT;
    }
    async generateReview(request) {
        const startMs = Date.now();
        // Google: system prompt goes in systemInstruction.parts[0].text
        const body = JSON.stringify({
            systemInstruction: {
                parts: [{ text: request.systemPrompt }],
            },
            contents: [
                {
                    role: "user",
                    parts: [{ text: request.userPrompt }],
                },
            ],
            generationConfig: {
                maxOutputTokens: request.maxOutputTokens,
            },
        });
        // API key auth via URL query parameter is Google's required pattern for
        // the Gemini REST API (https://ai.google.dev/gemini-api/docs/api-key).
        // Unlike OpenAI (Authorization header) and Anthropic (x-api-key header),
        // Google's public REST endpoint mandates `?key=`. This is not our design
        // choice — it is the documented auth mechanism.
        //
        // Risk: the key appears in the URL and could leak via HTTP access logs,
        // proxy logs, CDN logs, or error messages that include the full URL.
        //
        // Mitigation: this adapter runs in a server-side CLI context (Node.js
        // fetch, no browser → no Referer header, no CDN/proxy intermediaries in
        // typical deployments). `streamUrl` is passed to fetch() and never logged.
        //
        // CAUTION: do not add `logger.debug(streamUrl)` or include streamUrl in
        // any error message. If Google's API evolves to support header-based auth,
        // migrate to that pattern. See Issue #464 A3.
        const streamUrl = `${API_BASE}/${this.model}:streamGenerateContent?key=${this.apiKey}&alt=sse`;
        let lastError;
        let retryAfterMs = 0;
        for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
            if (attempt > 0) {
                const delay = retryAfterMs > 0
                    ? retryAfterMs
                    : Math.min(BACKOFF_BASE_MS * Math.pow(2, attempt - 1), BACKOFF_CEILING_MS);
                retryAfterMs = 0;
                await sleep(delay);
            }
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), this.timeoutMs);
            try {
                const response = await fetch(streamUrl, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                    },
                    body,
                    signal: controller.signal,
                });
                if (response.status === 401 || response.status === 403) {
                    clearTimeout(timer);
                    throw new LLMProviderError("AUTH_ERROR", `Google API ${response.status}`);
                }
                if (response.status === 429) {
                    clearTimeout(timer);
                    retryAfterMs = parseRetryAfter(response.headers.get("retry-after"));
                    lastError = new LLMProviderError("RATE_LIMITED", `Google API ${response.status}`);
                    continue;
                }
                if (response.status >= 500) {
                    clearTimeout(timer);
                    lastError = new LLMProviderError("PROVIDER_ERROR", `Google API ${response.status}`);
                    continue;
                }
                if (!response.ok) {
                    clearTimeout(timer);
                    throw new LLMProviderError("INVALID_REQUEST", `Google API ${response.status}`);
                }
                const result = await collectGoogleStream(response, controller.signal);
                clearTimeout(timer);
                const latencyMs = Date.now() - startMs;
                const estimatedCostUsd = (result.inputTokens / 1000) * this.costInput +
                    (result.outputTokens / 1000) * this.costOutput;
                return {
                    content: result.content,
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens,
                    model: result.model ?? this.model,
                    provider: "google",
                    latencyMs,
                    estimatedCostUsd,
                };
            }
            catch (err) {
                clearTimeout(timer);
                if (err instanceof LLMProviderError)
                    throw err;
                const name = err?.name ?? "";
                const msg = err instanceof Error ? err.message : String(err);
                // Issue #789: diagnostic-context preservation. Detail string
                // captures the underlying error name + message + (one level of)
                // cause + request size + attempt count + model. The
                // formatDiagnosticDetail helper sanitizes any auth tokens
                // before inclusion (see diagnostic-context.ts header).
                const detail = formatDiagnosticDetail(err, body.length, attempt, MAX_RETRIES + 1, this.model);
                if (name === "AbortError") {
                    lastError = new LLMProviderError("TIMEOUT", `Google API request timed out — ${detail}`);
                    continue;
                }
                if (err instanceof TypeError || /ECONNRESET|ENOTFOUND|EAI_AGAIN|ETIMEDOUT/i.test(msg)) {
                    lastError = new LLMProviderError("NETWORK", `Google API network error — ${detail}`);
                    continue;
                }
                throw err;
            }
        }
        throw lastError ?? new LLMProviderError("NETWORK", `Google API failed after retries (model=${this.model})`);
    }
}
/** Collect an SSE stream from the Google Gemini streamGenerateContent API. */
async function collectGoogleStream(response, _signal) {
    let content = "";
    let inputTokens = 0;
    let outputTokens = 0;
    let model;
    if (!response.body) {
        throw new Error("Google API stream: no response body");
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    try {
        while (true) {
            const { done, value } = await reader.read();
            if (done)
                break;
            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() ?? "";
            for (const line of lines) {
                if (!line.startsWith("data: "))
                    continue;
                const data = line.slice(6).trim();
                if (!data)
                    continue;
                let event;
                try {
                    event = JSON.parse(data);
                }
                catch {
                    continue;
                }
                if (event.modelVersion) {
                    model = event.modelVersion;
                }
                // Content parts
                const parts = event.candidates?.[0]?.content?.parts;
                if (parts) {
                    for (const part of parts) {
                        if (part.text) {
                            content += part.text;
                        }
                    }
                }
                // Usage metadata (typically in last chunk)
                if (event.usageMetadata) {
                    inputTokens = event.usageMetadata.promptTokenCount ?? inputTokens;
                    outputTokens = event.usageMetadata.candidatesTokenCount ?? outputTokens;
                }
            }
        }
    }
    finally {
        reader.releaseLock();
    }
    return { content, inputTokens, outputTokens, model };
}
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
function parseRetryAfter(value) {
    if (!value)
        return 0;
    const seconds = Number(value);
    if (!isNaN(seconds) && seconds > 0) {
        return Math.min(seconds * 1000, BACKOFF_CEILING_MS);
    }
    const date = Date.parse(value);
    if (!isNaN(date)) {
        const delayMs = date - Date.now();
        return delayMs > 0 ? Math.min(delayMs, BACKOFF_CEILING_MS) : 0;
    }
    return 0;
}
//# sourceMappingURL=google.js.map