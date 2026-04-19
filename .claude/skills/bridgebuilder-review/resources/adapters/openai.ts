import {
  LLMProviderError,
} from "../ports/llm-provider.js";
import type {
  ILLMProvider,
  ReviewRequest,
  ReviewResponse,
} from "../ports/llm-provider.js";

// OpenAI has two endpoints depending on model family:
//   - /v1/chat/completions — for GPT-4, GPT-5, GPT-5.2, non-codex chat models
//   - /v1/responses        — for codex models (gpt-5.3-codex and other "codex" variants)
// Calling a codex model against /chat/completions returns 404 with message
// "This is not a chat model ... Did you mean to use v1/completions?"
// See issue #585. Mirrors the routing split in
// .claude/adapters/loa_cheval/providers/openai_adapter.py.
const CHAT_URL = "https://api.openai.com/v1/chat/completions";
const RESPONSES_URL = "https://api.openai.com/v1/responses";
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CEILING_MS = 60_000;

/**
 * Codex models use the Responses API, not Chat Completions.
 * Detection mirrors the Python adapter (`"codex" in model`).
 */
function isCodexModel(model: string): boolean {
  return /codex/i.test(model);
}

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

    const useResponses = isCodexModel(this.model);
    const apiUrl = useResponses ? RESPONSES_URL : CHAT_URL;

    // Codex models (Responses API): single `input` string combining system + user.
    // Chat models (Chat Completions API): structured messages array with role tags.
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

/**
 * Collect an SSE stream from the OpenAI Responses API (codex models).
 *
 * Responses API events are typed: `response.output_text.delta` carries the
 * text deltas, `response.completed` carries the final usage. This is a
 * different wire format from Chat Completions — do not share the parser.
 */
async function collectResponsesStream(
  response: Response,
  _signal: AbortSignal,
): Promise<{ content: string; inputTokens: number; outputTokens: number; model?: string }> {
  let content = "";
  let inputTokens = 0;
  let outputTokens = 0;
  let model: string | undefined;

  if (!response.body) {
    throw new Error("OpenAI Responses API stream: no response body");
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
        if (data === "[DONE]" || !data) continue;

        let event: ResponsesStreamEvent;
        try {
          event = JSON.parse(data) as ResponsesStreamEvent;
        } catch {
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
  } finally {
    reader.releaseLock();
  }

  return { content, inputTokens, outputTokens, model };
}

interface ResponsesStreamEvent {
  type?: string;
  delta?: string;
  response?: {
    model?: string;
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      total_tokens?: number;
    };
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
