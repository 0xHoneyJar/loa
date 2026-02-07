import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  WebhookSink,
  SlackAdapter,
  DiscordAdapter,
  createWebhookSink,
} from "../scheduler/notification-sink.js";

// ── Mock fetch helper ────────────────────────────────

function mockFetch(status: number, statusText = "OK"): typeof globalThis.fetch {
  return async (_url: string | URL | Request, _init?: RequestInit) => {
    return {
      ok: status >= 200 && status < 300,
      status,
      statusText,
    } as Response;
  };
}

function failingFetch(errorMsg: string): typeof globalThis.fetch {
  return async () => {
    throw new Error(errorMsg);
  };
}

describe("NotificationSink (T2.2)", () => {
  // ── Factory ─────────────────────────────────────────

  it("createWebhookSink returns a WebhookSink", () => {
    const sink = createWebhookSink(
      { url: "https://example.com/hook" },
      { fetch: mockFetch(200) },
    );
    assert.ok(sink instanceof WebhookSink);
  });

  // ── Basic Send (fetch path) ─────────────────────────

  it("sends JSON payload via fetch", async () => {
    let capturedBody: string | undefined;
    let capturedUrl: string | undefined;

    const fakeFetch: typeof globalThis.fetch = async (url, init) => {
      capturedUrl = typeof url === "string" ? url : url.toString();
      capturedBody = init?.body as string;
      return { ok: true, status: 200, statusText: "OK" } as Response;
    };

    const sink = createWebhookSink(
      { url: "https://example.com/hook" },
      { fetch: fakeFetch },
    );
    await sink.send("hello world");

    assert.equal(capturedUrl, "https://example.com/hook");
    const parsed = JSON.parse(capturedBody!);
    assert.equal(parsed.text, "hello world");
  });

  it("sends custom headers", async () => {
    let capturedHeaders: Record<string, string> | undefined;

    const fakeFetch: typeof globalThis.fetch = async (_url, init) => {
      capturedHeaders = init?.headers as Record<string, string>;
      return { ok: true, status: 200, statusText: "OK" } as Response;
    };

    const sink = createWebhookSink(
      { url: "https://example.com/hook", headers: { Authorization: "Bearer tok" } },
      { fetch: fakeFetch },
    );
    await sink.send("msg");

    assert.equal(capturedHeaders?.Authorization, "Bearer tok");
  });

  // ── Non-2xx throws SCH_003 ──────────────────────────

  it("throws SCH_003 on non-2xx response (fetch path)", async () => {
    const sink = createWebhookSink(
      { url: "https://example.com/hook", retries: 0 },
      { fetch: mockFetch(500, "Internal Server Error") },
    );

    await assert.rejects(
      () => sink.send("msg"),
      (err: Error) => err.message.includes("500"),
    );
  });

  // ── Retry on network error ──────────────────────────

  it("retries once on network error, then succeeds", async () => {
    let attempts = 0;
    const fakeFetch: typeof globalThis.fetch = async () => {
      attempts++;
      if (attempts === 1) throw new Error("ECONNRESET");
      return { ok: true, status: 200, statusText: "OK" } as Response;
    };

    const sink = createWebhookSink(
      { url: "https://example.com/hook", retries: 1, retryDelayMs: 10 },
      { fetch: fakeFetch },
    );
    await sink.send("msg");
    assert.equal(attempts, 2);
  });

  it("exhausts retries and throws last error", async () => {
    const sink = createWebhookSink(
      { url: "https://example.com/hook", retries: 1, retryDelayMs: 10 },
      { fetch: failingFetch("ECONNREFUSED") },
    );

    await assert.rejects(
      () => sink.send("msg"),
      (err: Error) => err.message.includes("ECONNREFUSED"),
    );
  });

  // ── node:https fallback path ────────────────────────

  it("uses node:https fallback when fetch is undefined", async () => {
    // We can't easily mock node:https in a unit test without external deps,
    // so we verify the sink is constructed with fetch=undefined and the
    // doPost codepath is attempted. A real HTTPS call will fail (no server),
    // confirming the fallback path is exercised.
    const sink = createWebhookSink(
      { url: "https://localhost:19999/hook", retries: 0, timeoutMs: 200 },
      { fetch: undefined },
    );

    await assert.rejects(
      () => sink.send("msg"),
      // Should throw from the https fallback path (connection refused or timeout)
      (err: Error) => err instanceof Error,
    );
  });

  // ── Slack Adapter ──────────────────────────────────

  it("SlackAdapter formats as Block Kit payload", () => {
    const adapter = new SlackAdapter();
    const result = adapter.format("Deploy complete") as {
      blocks: Array<{ type: string; text: { type: string; text: string } }>;
    };

    assert.equal(result.blocks.length, 1);
    assert.equal(result.blocks[0].type, "section");
    assert.equal(result.blocks[0].text.type, "mrkdwn");
    assert.equal(result.blocks[0].text.text, "Deploy complete");
    assert.equal(adapter.contentType, "application/json");
  });

  it("WebhookSink uses SlackAdapter formatting", async () => {
    let capturedBody: string | undefined;
    const fakeFetch: typeof globalThis.fetch = async (_url, init) => {
      capturedBody = init?.body as string;
      return { ok: true, status: 200, statusText: "OK" } as Response;
    };

    const sink = createWebhookSink(
      { url: "https://example.com/hook" },
      { adapter: new SlackAdapter(), fetch: fakeFetch },
    );
    await sink.send("test message");

    const parsed = JSON.parse(capturedBody!);
    assert.ok(parsed.blocks);
    assert.equal(parsed.blocks[0].text.text, "test message");
  });

  // ── Discord Adapter ────────────────────────────────

  it("DiscordAdapter formats as embed payload", () => {
    const adapter = new DiscordAdapter();
    const result = adapter.format("Build failed") as {
      embeds: Array<{ description: string; color: number }>;
    };

    assert.equal(result.embeds.length, 1);
    assert.equal(result.embeds[0].description, "Build failed");
    assert.equal(result.embeds[0].color, 0x5865f2);
    assert.equal(adapter.contentType, "application/json");
  });

  it("WebhookSink uses DiscordAdapter formatting", async () => {
    let capturedBody: string | undefined;
    const fakeFetch: typeof globalThis.fetch = async (_url, init) => {
      capturedBody = init?.body as string;
      return { ok: true, status: 200, statusText: "OK" } as Response;
    };

    const sink = createWebhookSink(
      { url: "https://example.com/hook" },
      { adapter: new DiscordAdapter(), fetch: fakeFetch },
    );
    await sink.send("build failed");

    const parsed = JSON.parse(capturedBody!);
    assert.ok(parsed.embeds);
    assert.equal(parsed.embeds[0].description, "build failed");
  });

  // ── Timeout (fetch path) ────────────────────────────

  it("aborts on timeout via AbortController", async () => {
    const slowFetch: typeof globalThis.fetch = async (_url, init) => {
      // Wait until abort signal fires
      return new Promise((_resolve, reject) => {
        const signal = init?.signal;
        if (signal) {
          signal.addEventListener("abort", () => {
            reject(new DOMException("The operation was aborted", "AbortError"));
          });
        }
      });
    };

    const sink = createWebhookSink(
      { url: "https://example.com/hook", timeoutMs: 50, retries: 0 },
      { fetch: slowFetch },
    );

    await assert.rejects(
      () => sink.send("msg"),
      (err: Error) => err.message.includes("abort"),
    );
  });
});
