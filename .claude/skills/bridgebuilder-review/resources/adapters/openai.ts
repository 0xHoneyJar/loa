import {
  LLMProviderError,
} from "../ports/llm-provider.js";
import type {
  ILLMProvider,
  ReviewRequest,
  ReviewResponse,
} from "../ports/llm-provider.js";

const API_URL = "https://api.openai.com/v1/chat/completions";
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CEILING_MS = 60_000;

/** Default cost rates (USD per 1K tokens) — overridable via config.cost_rates. */
const DEFAULT_COST_INPUT = 0.01;
const DEFAULT_COST_OUTPUT = 0.03;

export interface OpenAIAdapterOptions {
  costRates?: { input: number; output: number };
}

export class OpenAIAdapter implements ILLMProvider {
  private readonly apiKey: string;
  private readonly model: string;
  private readonly timeoutMs: number;
  private readonly costInput: number;
  private readonly costOutput: number;

  constructor(
    apiKey: string,
    model: string,
    timeoutMs: number = DEFAULT_TIMEOUT_MS,
    options?: OpenAIAdapterOptions,
  ) {
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

  async generateReview(request: ReviewRequest): Promise<ReviewResponse> {
    const startMs = Date.now();

    // OpenAI: system prompt goes in messages[0] as role: "system"
    const body = JSON.stringify({
      model: this.model,
      max_completion_tokens: request.maxOutputTokens,
      messages: [
        { role: "system", content: request.systemPrompt },
        { role: "user", content: request.userPrompt },
      ],
      stream: true,
      stream_options: { include_usage: true },
    });

    let lastError: Error | undefined;
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
        const response = await fetch(API_URL, {
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

        const result = await collectOpenAIStream(response, controller.signal);
        clearTimeout(timer);

        const latencyMs = Date.now() - startMs;
        const estimatedCostUsd =
          (result.inputTokens / 1000) * this.costInput +
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
      } catch (err: unknown) {
        clearTimeout(timer);

        if (err instanceof LLMProviderError) throw err;

        const name = (err as Error | undefined)?.name ?? "";
        const msg = err instanceof Error ? err.message : String(err);

        if (name === "AbortError") {
          lastError = new LLMProviderError("TIMEOUT", "OpenAI API request timed out");
          continue;
        }

        if (err instanceof TypeError || /ECONNRESET|ENOTFOUND|EAI_AGAIN|ETIMEDOUT/i.test(msg)) {
          lastError = new LLMProviderError("NETWORK", "OpenAI API network error");
          continue;
        }

        throw err;
      }
    }

    throw lastError ?? new LLMProviderError("NETWORK", "OpenAI API failed after retries");
  }
}

/** Collect an SSE stream from the OpenAI Chat Completions API. */
async function collectOpenAIStream(
  response: Response,
  _signal: AbortSignal,
): Promise<{ content: string; inputTokens: number; outputTokens: number; model?: string }> {
  let content = "";
  let inputTokens = 0;
  let outputTokens = 0;
  let model: string | undefined;

  if (!response.body) {
    throw new Error("OpenAI API stream: no response body");
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
        const data = line.slice(6).trim();
        if (data === "[DONE]") continue;

        let event: OpenAIStreamEvent;
        try {
          event = JSON.parse(data) as OpenAIStreamEvent;
        } catch {
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
  } finally {
    reader.releaseLock();
  }

  return { content, inputTokens, outputTokens, model };
}

interface OpenAIStreamEvent {
  model?: string;
  choices?: Array<{
    delta?: { content?: string; role?: string };
    finish_reason?: string | null;
  }>;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
    total_tokens?: number;
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseRetryAfter(value: string | null): number {
  if (!value) return 0;
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
