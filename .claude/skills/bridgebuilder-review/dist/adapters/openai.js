import { LLMProviderError, } from "../ports/llm-provider.js";
import { GENERATED_MODEL_REGISTRY } from "../config.generated.js";
import { formatDiagnosticDetail } from "./diagnostic-context.js";
// OpenAI has two endpoints depending on model family:
//   - /v1/chat/completions — for GPT-4, non-Responses chat models
//   - /v1/responses        — for codex models (gpt-5.3-codex), gpt-5.5,
//                            gpt-5.5-pro, and other reasoning-capable models
// Calling a Responses-family model against /chat/completions returns
// "This is not a chat model ... Did you mean to use v1/completions?".
// The cycle-095 Python adapter at
// .claude/adapters/loa_cheval/providers/openai_adapter.py reads
// `endpoint_family` from the model registry to make this routing
// decision. The TS adapter does the same — single source of truth
// is .claude/defaults/model-config.yaml (compiled into
// config.generated.ts by gen-bb-registry.ts).
const CHAT_URL = "https://api.openai.com/v1/chat/completions";
const RESPONSES_URL = "https://api.openai.com/v1/responses";
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CEILING_MS = 60_000;
/**
 * Determine whether a model uses the Responses API based on its
 * `endpoint_family` in the generated model registry. Falls back to a
 * legacy `codex`-substring heuristic for unknown models — covers any
 * future codex variant operators add via `model_aliases_extra` before
 * the registry is regenerated.
 *
 * Returns true → /v1/responses; false → /v1/chat/completions.
 */
function usesResponsesEndpoint(model) {
    const entry = GENERATED_MODEL_REGISTRY[model];
    if (entry?.endpointFamily === "responses")
        return true;
    if (entry?.endpointFamily === "chat")
        return false;
    // Fallback for unknown models (operator-added via model_aliases_extra
    // that haven't been baked into the compiled registry yet).
    return /codex/i.test(model);
}
/** Default cost rates (USD per 1K tokens) — overridable via config.cost_rates. */
const DEFAULT_COST_INPUT = 0.01;
const DEFAULT_COST_OUTPUT = 0.03;
export class OpenAIAdapter {
    apiKey;
    model;
    timeoutMs;
    costInput;
    costOutput;
    constructor(apiKey, model, timeoutMs = DEFAULT_TIMEOUT_MS, options) {
        if (!apiKey) {
            throw new Error("OPENAI_API_KEY required (set via environment)");
        }
        if (!model) {
            throw new Error("OpenAI model is required");
        }
        this.apiKey = apiKey;
        this.model = model;
        this.timeoutMs = timeoutMs;
        this.costInput = options?.costRates?.input ?? DEFAULT_COST_INPUT;
        this.costOutput = options?.costRates?.output ?? DEFAULT_COST_OUTPUT;
    }
    async generateReview(request) {
        const startMs = Date.now();
        const useResponses = usesResponsesEndpoint(this.model);
        const apiUrl = useResponses ? RESPONSES_URL : CHAT_URL;
        // Responses API (codex / gpt-5.5 / gpt-5.5-pro): single `input` string
        //                                                   combining system + user.
        // Chat Completions API (gpt-4 / gpt-5.x non-Responses): structured messages
        //                                                       array with role tags.
        const body = useResponses
            ? JSON.stringify({
                model: this.model,
                input: `${request.systemPrompt}\n\n---\n\n${request.userPrompt}`,
                stream: true,
            })
            : JSON.stringify({
                model: this.model,
                max_completion_tokens: request.maxOutputTokens,
                messages: [
                    { role: "system", content: request.systemPrompt },
                    { role: "user", content: request.userPrompt },
                ],
                stream: true,
                stream_options: { include_usage: true },
            });
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
                const response = await fetch(apiUrl, {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        "Authorization": `Bearer ${this.apiKey}`,
                    },
                    body,
                    signal: controller.signal,
                });
                if (response.status === 401 || response.status === 403) {
                    clearTimeout(timer);
                    throw new LLMProviderError("AUTH_ERROR", `OpenAI API ${response.status}`);
                }
                if (response.status === 429) {
                    clearTimeout(timer);
                    retryAfterMs = parseRetryAfter(response.headers.get("retry-after"));
                    lastError = new LLMProviderError("RATE_LIMITED", `OpenAI API ${response.status}`);
                    continue;
                }
                if (response.status >= 500) {
                    clearTimeout(timer);
                    retryAfterMs = parseRetryAfter(response.headers.get("retry-after"));
                    lastError = new LLMProviderError("PROVIDER_ERROR", `OpenAI API ${response.status}`);
                    continue;
                }
                if (!response.ok) {
                    clearTimeout(timer);
                    throw new LLMProviderError("INVALID_REQUEST", `OpenAI API ${response.status}`);
                }
                const result = useResponses
                    ? await collectResponsesStream(response, controller.signal)
                    : await collectOpenAIStream(response, controller.signal);
                clearTimeout(timer);
                const latencyMs = Date.now() - startMs;
                const estimatedCostUsd = (result.inputTokens / 1000) * this.costInput +
                    (result.outputTokens / 1000) * this.costOutput;
                return {
                    content: result.content,
                    inputTokens: result.inputTokens,
                    outputTokens: result.outputTokens,
                    model: result.model ?? this.model,
                    provider: "openai",
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
                // Issue #789: diagnostic-context preservation. See
                // adapters/diagnostic-context.ts for the format + sanitization
                // contract. Mirrors the pattern landed upstream in PR #781 for
                // the cheval Python adapters.
                const detail = formatDiagnosticDetail(err, body.length, attempt, MAX_RETRIES + 1, this.model);
                if (name === "AbortError") {
                    lastError = new LLMProviderError("TIMEOUT", `OpenAI API request timed out — ${detail}`);
                    continue;
                }
                if (err instanceof TypeError || /ECONNRESET|ENOTFOUND|EAI_AGAIN|ETIMEDOUT/i.test(msg)) {
                    lastError = new LLMProviderError("NETWORK", `OpenAI API network error — ${detail}`);
                    continue;
                }
                throw err;
            }
        }
        throw lastError ?? new LLMProviderError("NETWORK", `OpenAI API failed after retries (model=${this.model})`);
    }
}
/** Collect an SSE stream from the OpenAI Chat Completions API. */
async function collectOpenAIStream(response, _signal) {
    let content = "";
    let inputTokens = 0;
    let outputTokens = 0;
    let model;
    if (!response.body) {
        throw new Error("OpenAI API stream: no response body");
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
                if (data === "[DONE]")
                    continue;
                let event;
                try {
                    event = JSON.parse(data);
                }
                catch {
                    continue;
                }
                if (event.model) {
                    model = event.model;
                }
                // Content delta
                if (event.choices?.[0]?.delta?.content) {
                    content += event.choices[0].delta.content;
                }
                // Usage data (sent in final chunk when stream_options.include_usage = true)
                if (event.usage) {
                    inputTokens = event.usage.prompt_tokens ?? 0;
                    outputTokens = event.usage.completion_tokens ?? 0;
                }
            }
        }
    }
    finally {
        reader.releaseLock();
    }
    return { content, inputTokens, outputTokens, model };
}
/**
 * Collect an SSE stream from the OpenAI Responses API (codex models).
 *
 * Responses API events are typed: `response.output_text.delta` carries the
 * text deltas, `response.completed` carries the final usage. This is a
 * different wire format from Chat Completions — do not share the parser.
 */
async function collectResponsesStream(response, _signal) {
    let content = "";
    let inputTokens = 0;
    let outputTokens = 0;
    let model;
    if (!response.body) {
        throw new Error("OpenAI Responses API stream: no response body");
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
                if (data === "[DONE]" || !data)
                    continue;
                let event;
                try {
                    event = JSON.parse(data);
                }
                catch {
                    continue;
                }
                // Text deltas arrive as `response.output_text.delta` with a `delta` string.
                if (event.type === "response.output_text.delta" && typeof event.delta === "string") {
                    content += event.delta;
                }
                // Final event carries model + usage.
                if (event.type === "response.completed" && event.response) {
                    if (event.response.model) {
                        model = event.response.model;
                    }
                    if (event.response.usage) {
                        inputTokens = event.response.usage.input_tokens ?? 0;
                        outputTokens = event.response.usage.output_tokens ?? 0;
                    }
                }
                // Fallback: model ID is also present on the initial response.created event.
                if (event.type === "response.created" && event.response?.model && !model) {
                    model = event.response.model;
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
//# sourceMappingURL=openai.js.map