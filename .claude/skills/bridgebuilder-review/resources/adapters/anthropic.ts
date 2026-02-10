import {
  LLMProviderError,
} from "../ports/llm-provider.js";
import type {
  ILLMProvider,
  ReviewRequest,
  ReviewResponse,
} from "../ports/llm-provider.js";

const API_URL = "https://api.anthropic.com/v1/messages";
const API_VERSION = "2023-06-01";
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CEILING_MS = 60_000;

export class AnthropicAdapter implements ILLMProvider {
  private readonly apiKey: string;
  private readonly model: string;
  private readonly timeoutMs: number;

  constructor(apiKey: string, model: string, timeoutMs: number = DEFAULT_TIMEOUT_MS) {
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

  async generateReview(request: ReviewRequest): Promise<ReviewResponse> {
    // Use streaming to avoid Cloudflare's 60s TTFB proxy timeout.
    // Without streaming, the API generates the full response before sending
    // any bytes. For large reviews (>2000 tokens) this exceeds 60s, and
    // Cloudflare kills the connection with a TCP RST (UND_ERR_SOCKET).
    const body = JSON.stringify({
      model: this.model,
      max_tokens: request.maxOutputTokens,
      system: request.systemPrompt,
      messages: [{ role: "user", content: request.userPrompt }],
      stream: true,
    });

    let lastError: Error | undefined;
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

        if (response.status === 429) {
          clearTimeout(timer);
          retryAfterMs = parseRetryAfter(response.headers.get("retry-after"));
          lastError = new LLMProviderError("RATE_LIMITED", `Anthropic API ${response.status}`);
          continue;
        }

        if (response.status >= 500) {
          clearTimeout(timer);
          retryAfterMs = parseRetryAfter(response.headers.get("retry-after"));
          // Do not include response body — may contain sensitive details
          lastError = new LLMProviderError("NETWORK", `Anthropic API ${response.status}`);
          continue;
        }

        if (!response.ok) {
          clearTimeout(timer);
          // Do not include response body — may contain echoed prompt content
          throw new LLMProviderError("INVALID_REQUEST", `Anthropic API ${response.status}`);
        }

        // Collect streamed SSE response
        const result = await collectStream(response, controller.signal);
        clearTimeout(timer);

        return {
          content: result.content,
          inputTokens: result.inputTokens,
          outputTokens: result.outputTokens,
          model: result.model ?? this.model,
        };
      } catch (err: unknown) {
        clearTimeout(timer);

        const name = (err as Error | undefined)?.name ?? "";
        const msg = err instanceof Error ? err.message : String(err);

        // Retry on timeouts
        if (name === "AbortError") {
          lastError = new LLMProviderError("NETWORK", "Anthropic API request timed out");
          continue;
        }

        // Retry on transient network errors (TypeError from fetch, connection resets)
        if (err instanceof TypeError || /ECONNRESET|ENOTFOUND|EAI_AGAIN|ETIMEDOUT/i.test(msg)) {
          lastError = new LLMProviderError("NETWORK", "Anthropic API network error");
          continue;
        }

        throw err;
      }
    }

    throw lastError ?? new LLMProviderError("NETWORK", "Anthropic API failed after retries");
  }
}

/** Collect an SSE stream from the Anthropic Messages API into a single response. */
async function collectStream(
  response: Response,
  _signal: AbortSignal,
): Promise<{ content: string; inputTokens: number; outputTokens: number; model?: string }> {
  let content = "";
  let inputTokens = 0;
  let outputTokens = 0;
  let model: string | undefined;

  if (!response.body) {
    throw new Error("Anthropic API stream: no response body");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const data = line.slice(6);
        if (data === "[DONE]") continue;

        let event: StreamEvent;
        try {
          event = JSON.parse(data) as StreamEvent;
        } catch {
          continue; // Skip malformed events
        }

        if (event.type === "message_start" && event.message) {
          model = event.message.model;
          inputTokens = event.message.usage?.input_tokens ?? 0;
        } else if (event.type === "content_block_delta" && event.delta?.text) {
          content += event.delta.text;
        } else if (event.type === "message_delta" && event.usage) {
          outputTokens = event.usage.output_tokens ?? 0;
        } else if (event.type === "error") {
          throw new Error(`Anthropic API stream error: ${event.error?.message ?? "unknown"}`);
        }
      }
    }
  } finally {
    reader.releaseLock();
  }

  return { content, inputTokens, outputTokens, model };
}

interface StreamEvent {
  type: string;
  message?: { model?: string; usage?: { input_tokens?: number } };
  delta?: { text?: string };
  usage?: { output_tokens?: number };
  error?: { message?: string };
}

interface AnthropicResponse {
  content?: Array<{ type: string; text: string }>;
  usage?: { input_tokens: number; output_tokens: number };
  model?: string;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Parse retry-after header — supports seconds (numeric) and HTTP-date formats. */
function parseRetryAfter(value: string | null): number {
  if (!value) return 0;
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
