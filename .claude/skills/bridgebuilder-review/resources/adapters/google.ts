import {
  LLMProviderError,
} from "../ports/llm-provider.js";
import type {
  ILLMProvider,
  ReviewRequest,
  ReviewResponse,
} from "../ports/llm-provider.js";

const API_BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const DEFAULT_TIMEOUT_MS = 120_000;
const MAX_RETRIES = 2;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CEILING_MS = 60_000;

/** Default cost rates (USD per 1K tokens) — overridable via config.cost_rates. */
const DEFAULT_COST_INPUT = 0.00125;
const DEFAULT_COST_OUTPUT = 0.005;

export interface GoogleAdapterOptions {
  costRates?: { input: number; output: number };
}

export class GoogleAdapter implements ILLMProvider {
  private readonly apiKey: string;
  private readonly model: string;
  private readonly timeoutMs: number;
  private readonly costInput: number;
  private readonly costOutput: number;

  constructor(
    apiKey: string,
    model: string,
    timeoutMs: number = DEFAULT_TIMEOUT_MS,
    options?: GoogleAdapterOptions,
  ) {
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

  async generateReview(request: ReviewRequest): Promise<ReviewResponse> {
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
        const estimatedCostUsd =
          (result.inputTokens / 1000) * this.costInput +
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
      } catch (err: unknown) {
        clearTimeout(timer);

        if (err instanceof LLMProviderError) throw err;

        const name = (err as Error | undefined)?.name ?? "";
        const msg = err instanceof Error ? err.message : String(err);

        if (name === "AbortError") {
          lastError = new LLMProviderError("TIMEOUT", "Google API request timed out");
          continue;
        }

        if (err instanceof TypeError || /ECONNRESET|ENOTFOUND|EAI_AGAIN|ETIMEDOUT/i.test(msg)) {
          lastError = new LLMProviderError("NETWORK", "Google API network error");
          continue;
        }

        throw err;
      }
    }

    throw lastError ?? new LLMProviderError("NETWORK", "Google API failed after retries");
  }
}

/** Collect an SSE stream from the Google Gemini streamGenerateContent API. */
async function collectGoogleStream(
  response: Response,
  _signal: AbortSignal,
): Promise<{ content: string; inputTokens: number; outputTokens: number; model?: string }> {
  let content = "";
  let inputTokens = 0;
  let outputTokens = 0;
  let model: string | undefined;

  if (!response.body) {
    throw new Error("Google API stream: no response body");
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
        if (!data) continue;

        let event: GoogleStreamEvent;
        try {
          event = JSON.parse(data) as GoogleStreamEvent;
        } catch {
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
  } finally {
    reader.releaseLock();
  }

  return { content, inputTokens, outputTokens, model };
}

interface GoogleStreamEvent {
  modelVersion?: string;
  candidates?: Array<{
    content?: {
      parts?: Array<{ text?: string }>;
      role?: string;
    };
    finishReason?: string;
  }>;
  usageMetadata?: {
    promptTokenCount?: number;
    candidatesTokenCount?: number;
    totalTokenCount?: number;
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
