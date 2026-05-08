import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { GoogleAdapter } from "../adapters/google.js";
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

let originalFetch: typeof globalThis.fetch;

describe("GoogleAdapter", () => {
  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("throws if apiKey is empty", () => {
    assert.throws(
      () => new GoogleAdapter("", "gemini-2.5-pro"),
      /GOOGLE_API_KEY required/,
    );
  });

  it("throws if model is empty", () => {
    assert.throws(
      () => new GoogleAdapter("test-key", ""),
      /Google model is required/,
    );
  });

  it("sends system prompt in systemInstruction.parts[0].text", async () => {
    let capturedBody: string | undefined;
    let capturedUrl: string | undefined;

    globalThis.fetch = async (input: RequestInfo | URL, init?: RequestInit) => {
      capturedUrl = typeof input === "string" ? input : input.toString();
      capturedBody = init?.body as string;
      const events = [
        'data: {"candidates":[{"content":{"parts":[{"text":"Review output"}],"role":"model"}}],"usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":50}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro");
    await adapter.generateReview({
      systemPrompt: "You are a reviewer",
      userPrompt: "Review this code",
      maxOutputTokens: 4096,
    });

    assert.ok(capturedBody);
    const parsed = JSON.parse(capturedBody);
    assert.equal(parsed.systemInstruction.parts[0].text, "You are a reviewer");
    assert.equal(parsed.contents[0].role, "user");
    assert.equal(parsed.contents[0].parts[0].text, "Review this code");
    assert.equal(parsed.generationConfig.maxOutputTokens, 4096);

    // API key in URL query parameter
    assert.ok(capturedUrl);
    assert.ok(capturedUrl.includes("key=test-key"));
    assert.ok(capturedUrl.includes("gemini-2.5-pro:streamGenerateContent"));
    assert.ok(capturedUrl.includes("alt=sse"));
  });

  it("does not send Authorization header (key in URL)", async () => {
    let capturedHeaders: Record<string, string> | undefined;

    globalThis.fetch = async (_input: RequestInfo | URL, init?: RequestInit) => {
      capturedHeaders = Object.fromEntries(
        Object.entries(init?.headers as Record<string, string> ?? {}),
      );
      const events = [
        'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]}}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro");
    await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });

    assert.ok(capturedHeaders);
    assert.equal(capturedHeaders["Authorization"], undefined);
  });

  it("collects streamed content from Google format", async () => {
    globalThis.fetch = async () => {
      const events = [
        'data: {"candidates":[{"content":{"parts":[{"text":"Hello "}],"role":"model"}}],"modelVersion":"gemini-2.5-pro-preview-05-06"}\n\n',
        'data: {"candidates":[{"content":{"parts":[{"text":"world"}],"role":"model"}}]}\n\n',
        'data: {"candidates":[{"content":{"parts":[{"text":"!"}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":200,"candidatesTokenCount":100,"totalTokenCount":300}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro");
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 4096,
    });

    assert.equal(result.content, "Hello world!");
    assert.equal(result.inputTokens, 200);
    assert.equal(result.outputTokens, 100);
    assert.equal(result.model, "gemini-2.5-pro-preview-05-06");
    assert.equal(result.provider, "google");
    assert.ok(typeof result.latencyMs === "number");
    assert.ok(typeof result.estimatedCostUsd === "number");
  });

  it("retries on 429 rate limit", async () => {
    let callCount = 0;

    globalThis.fetch = async () => {
      callCount++;
      if (callCount === 1) {
        return new Response("Rate limited", { status: 429 });
      }
      const events = [
        'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]}}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro", 10_000);
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
        return new Response("Internal error", { status: 503 });
      }
      const events = [
        'data: {"candidates":[{"content":{"parts":[{"text":"recovered"}]}}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro", 10_000);
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

    const adapter = new GoogleAdapter("bad-key", "gemini-2.5-pro");
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

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro");
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
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => {
          const err = new Error("The operation was aborted");
          err.name = "AbortError";
          reject(err);
        });
      });
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro", 50);
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
        'data: {"candidates":[{"content":{"parts":[{"text":"review"}]}}],"usageMetadata":{"promptTokenCount":1000,"candidatesTokenCount":500}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro", 120_000, {
      costRates: { input: 0.00125, output: 0.005 },
    });
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 4096,
    });

    // 1000/1000 * 0.00125 + 500/1000 * 0.005 = 0.00125 + 0.0025 = 0.00375
    assert.ok(result.estimatedCostUsd != null);
    assert.ok(Math.abs(result.estimatedCostUsd! - 0.00375) < 0.0001);
  });

  it("skips malformed SSE lines gracefully", async () => {
    globalThis.fetch = async () => {
      const events = [
        'data: {"candidates":[{"content":{"parts":[{"text":"before"}]}}]}\n\n',
        "data: {invalid json here}\n\n",
        'data: {"candidates":[{"content":{"parts":[{"text":" after"}]}}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro");
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });

    assert.equal(result.content, "before after");
  });

  it("handles multiple text parts in a single chunk", async () => {
    globalThis.fetch = async () => {
      const events = [
        'data: {"candidates":[{"content":{"parts":[{"text":"part1"},{"text":"part2"}]}}],"usageMetadata":{"promptTokenCount":10,"candidatesTokenCount":5}}\n\n',
      ];
      return mockFetchResponse(200, events);
    };

    const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro");
    const result = await adapter.generateReview({
      systemPrompt: "sys",
      userPrompt: "usr",
      maxOutputTokens: 100,
    });

    assert.equal(result.content, "part1part2");
  });

  // Issue #789: diagnostic-context preservation. Mirrors upstream PR #781
  // for the cheval Python adapters. The previous error message was just
  // "Google API network error" — operators couldn't distinguish failure
  // modes. The new surface includes underlying error name, message,
  // optional cause, request size, attempt, and model.
  describe("diagnostic-context preservation (issue #789)", () => {
    it("NETWORK error preserves underlying TypeError name + message", async () => {
      let attempts = 0;
      globalThis.fetch = async () => {
        attempts++;
        const err = new TypeError("Premature stream close before final chunk");
        throw err;
      };

      const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro", 1000);
      await assert.rejects(
        adapter.generateReview({
          systemPrompt: "sys",
          userPrompt: "usr",
          maxOutputTokens: 100,
        }),
        (err: Error) => {
          assert.match(err.message, /Google API network error/);
          assert.match(err.message, /TypeError: Premature stream close before final chunk/);
          assert.match(err.message, /request_size=\d+B/);
          assert.match(err.message, /model=gemini-2.5-pro/);
          return true;
        },
      );
      // Adapter retries 3 times (initial + 2 retries) before giving up.
      assert.equal(attempts, 3);
    });

    it("NETWORK error preserves err.cause when set (Node.js fetch UND_ERR_*)", async () => {
      globalThis.fetch = async () => {
        const cause = new Error("UND_ERR_SOCKET");
        cause.name = "UND_ERR_SOCKET";
        const err = new TypeError("fetch failed");
        // @ts-expect-error — Node.js fetch wraps low-level errors in cause
        err.cause = cause;
        throw err;
      };

      const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro", 1000);
      await assert.rejects(
        adapter.generateReview({
          systemPrompt: "sys",
          userPrompt: "usr",
          maxOutputTokens: 100,
        }),
        (err: Error) => {
          assert.match(err.message, /TypeError: fetch failed/);
          assert.match(err.message, /cause=UND_ERR_SOCKET/);
          return true;
        },
      );
    });

    it("sanitization redacts API key from error messages", async () => {
      globalThis.fetch = async () => {
        const err = new TypeError(
          "fetch to https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:streamGenerateContent?key=AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&alt=sse failed",
        );
        throw err;
      };

      const adapter = new GoogleAdapter("test-key", "gemini-2.5-pro", 100);
      await assert.rejects(
        adapter.generateReview({
          systemPrompt: "sys",
          userPrompt: "usr",
          maxOutputTokens: 100,
        }),
        (err: Error) => {
          // The API key MUST NOT appear in the error message surface.
          assert.doesNotMatch(err.message, /AIzaSy/);
          assert.match(err.message, /\?key=<redacted>/);
          return true;
        },
      );
    });
  });
});
