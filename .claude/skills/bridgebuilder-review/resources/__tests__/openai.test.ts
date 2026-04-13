import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { OpenAIAdapter } from "../adapters/openai.js";
import { LLMProviderError } from "../ports/llm-provider.js";

/**
 * Helper to create a mock SSE stream from event data.
 */
function createSSEStream(events: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  const chunks = events.map((e) => encoder.encode(e));
  let index = 0;
  return new ReadableStream({
    pull(controller) {
      if (index < chunks.length) {
        controller.enqueue(chunks[index++]);
      } else {
        controller.close();
      }
    },
  });
}

function mockFetchResponse(
  status: number,
  events: string[],
  headers?: Record<string, string>,
): Response {
  return new Response(createSSEStream(events), {
    status,
    headers: { "Content-Type": "text/event-stream", ...headers },
  });
}

// Store and restore global fetch
let originalFetch: typeof globalThis.fetch;

describe("OpenAIAdapter", () => {
  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("throws if apiKey is empty", () => {
    assert.throws(
      () => new OpenAIAdapter("", "gpt-4o"),
      /OPENAI_API_KEY required/,
    );
  });

  it("throws if model is empty", () => {
    assert.throws(
      () => new OpenAIAdapter("sk-test", ""),
      /OpenAI model is required/,
    );
  });

  it("sends correct request format with system prompt in messages[0]", async () => {
    let capturedBody: string | undefined;

    globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
      capturedBody = init?.body as string;
      const events = [
        'data: {"model":"gpt-4o","choices":[{"delta":{"role":"assistant"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"Review output"}}]}\n\n',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":50}}\n\n',
        "data: [DONE]\n\n",
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o");
    await adapter.generateReview({
      systemPrompt: "You are a reviewer",
      userPrompt: "Review this code",
      maxOutputTokens: 4096,
    });

    assert.ok(capturedBody);
    const parsed = JSON.parse(capturedBody);
    assert.equal(parsed.messages[0].role, "system");
    assert.equal(parsed.messages[0].content, "You are a reviewer");
    assert.equal(parsed.messages[1].role, "user");
    assert.equal(parsed.messages[1].content, "Review this code");
    assert.equal(parsed.model, "gpt-4o");
    assert.equal(parsed.stream, true);
  });

  it("sends Authorization Bearer header", async () => {
    let capturedHeaders: Record<string, string> | undefined;

    globalThis.fetch = async (_input: RequestInfo | URL, init?: RequestInit) => {
      capturedHeaders = Object.fromEntries(
        (init?.headers as Headers)?.entries?.() ??
        Object.entries(init?.headers as Record<string, string> ?? {}),
      );
      const events = [
        'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}\n\n',
        "data: [DONE]\n\n",
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new OpenAIAdapter("sk-test-key-123", "gpt-4o");
    await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });

    assert.ok(capturedHeaders);
    assert.equal(capturedHeaders["Authorization"], "Bearer sk-test-key-123");
  });

  it("collects streamed content correctly", async () => {
    globalThis.fetch = async () => {
      const events = [
        'data: {"model":"gpt-4o-2024-08-06","choices":[{"delta":{"role":"assistant"}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"Hello "}}]}\n\n',
        'data: {"choices":[{"delta":{"content":"world"}}]}\n\n',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":200,"completion_tokens":100}}\n\n',
        "data: [DONE]\n\n",
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o");
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 4096,
    });

    assert.equal(result.content, "Hello world");
    assert.equal(result.inputTokens, 200);
    assert.equal(result.outputTokens, 100);
    assert.equal(result.model, "gpt-4o-2024-08-06");
    assert.equal(result.provider, "openai");
    assert.ok(typeof result.latencyMs === "number");
    assert.ok(typeof result.estimatedCostUsd === "number");
    assert.ok(result.estimatedCostUsd! > 0);
  });

  it("retries on 429 rate limit", async () => {
    let callCount = 0;

    globalThis.fetch = async () => {
      callCount++;
      if (callCount === 1) {
        return new Response("Rate limited", { status: 429 });
      }
      const events = [
        'data: {"choices":[{"delta":{"content":"ok"}}]}\n\n',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}\n\n',
        "data: [DONE]\n\n",
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o", 10_000);
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });

    assert.equal(callCount, 2);
    assert.equal(result.content, "ok");
  });

  it("retries on 5xx server error", async () => {
    let callCount = 0;

    globalThis.fetch = async () => {
      callCount++;
      if (callCount === 1) {
        return new Response("Server error", { status: 500 });
      }
      const events = [
        'data: {"choices":[{"delta":{"content":"recovered"}}]}\n\n',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}\n\n',
        "data: [DONE]\n\n",
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o", 10_000);
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });

    assert.equal(callCount, 2);
    assert.equal(result.content, "recovered");
  });

  it("throws AUTH_ERROR on 401", async () => {
    globalThis.fetch = async () => new Response("Unauthorized", { status: 401 });

    const adapter = new OpenAIAdapter("sk-bad-key", "gpt-4o");
    await assert.rejects(
      adapter.generateReview({
        systemPrompt: "sys",
        userPrompt: "usr",
        maxOutputTokens: 100,
      }),
      (err: LLMProviderError) => {
        assert.equal(err.code, "AUTH_ERROR");
        return true;
      },
    );
  });

  it("throws INVALID_REQUEST on 400", async () => {
    globalThis.fetch = async () => new Response("Bad request", { status: 400 });

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o");
    await assert.rejects(
      adapter.generateReview({
        systemPrompt: "sys",
        userPrompt: "usr",
        maxOutputTokens: 100,
      }),
      (err: LLMProviderError) => {
        assert.equal(err.code, "INVALID_REQUEST");
        return true;
      },
    );
  });

  it("throws TIMEOUT on abort", async () => {
    globalThis.fetch = async (_input: RequestInfo | URL, init?: RequestInit) => {
      // Simulate a timeout by waiting for abort
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          const err = new Error("The operation was aborted");
          err.name = "AbortError";
          reject(err);
        });
      });
    };

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o", 50); // 50ms timeout
    await assert.rejects(
      adapter.generateReview({
        systemPrompt: "sys",
        userPrompt: "usr",
        maxOutputTokens: 100,
      }),
      (err: LLMProviderError) => {
        assert.equal(err.code, "TIMEOUT");
        return true;
      },
    );
  });

  it("computes cost estimate from token counts", async () => {
    globalThis.fetch = async () => {
      const events = [
        'data: {"choices":[{"delta":{"content":"review"}}]}\n\n',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1000,"completion_tokens":500}}\n\n',
        "data: [DONE]\n\n",
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o", 120_000, {
      costRates: { input: 0.01, output: 0.03 },
    });
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 4096,
    });

    // 1000/1000 * 0.01 + 500/1000 * 0.03 = 0.01 + 0.015 = 0.025
    assert.ok(result.estimatedCostUsd != null);
    assert.ok(Math.abs(result.estimatedCostUsd! - 0.025) < 0.001);
  });

  it("skips malformed SSE lines gracefully", async () => {
    globalThis.fetch = async () => {
      const events = [
        'data: {"choices":[{"delta":{"content":"before"}}]}\n\n',
        "data: {invalid json}\n\n",
        'data: {"choices":[{"delta":{"content":" after"}}]}\n\n',
        'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}\n\n',
        "data: [DONE]\n\n",
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new OpenAIAdapter("sk-test", "gpt-4o");
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });

    assert.equal(result.content, "before after");
  });
});
