/**
 * Notification Sink — webhook delivery with Slack/Discord adapters.
 *
 * Uses global fetch() (Node 18+) with node:https fallback.
 * Per SDD Section 4.3.3.
 */
import * as https from "node:https";
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface INotificationChannel {
  send(message: string): Promise<void>;
}

export interface WebhookSinkConfig {
  url: string;
  headers?: Record<string, string>;
  timeoutMs?: number;
  retries?: number;
  retryDelayMs?: number;
}

export interface NotificationAdapter {
  format(message: string): unknown;
  contentType: string;
}

// ── node:https fallback ──────────────────────────────

function httpsPost(
  url: string,
  body: string,
  headers: Record<string, string>,
  timeoutMs: number,
  signal: AbortSignal,
): Promise<{ statusCode: number; body: string }> {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = https.request(
      {
        hostname: parsed.hostname,
        port: parsed.port || 443,
        path: parsed.pathname + parsed.search,
        method: "POST",
        headers: {
          "Content-Type": headers["Content-Type"] ?? "application/json",
          "Content-Length": Buffer.byteLength(body).toString(),
          ...headers,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk: Buffer) => { data += chunk.toString(); });
        res.on("end", () => {
          resolve({ statusCode: res.statusCode ?? 0, body: data });
        });
      },
    );

    req.on("error", reject);

    const timer = setTimeout(() => {
      req.destroy(new Error("Request timed out"));
    }, timeoutMs);

    const onAbort = () => {
      clearTimeout(timer);
      req.destroy(new Error("Request aborted"));
    };
    signal.addEventListener("abort", onAbort, { once: true });

    req.on("close", () => {
      clearTimeout(timer);
      signal.removeEventListener("abort", onAbort);
    });

    req.write(body);
    req.end();
  });
}

// ── WebhookSink ──────────────────────────────────────

export class WebhookSink implements INotificationChannel {
  private readonly url: string;
  private readonly headers: Record<string, string>;
  private readonly timeoutMs: number;
  private readonly retries: number;
  private readonly retryDelayMs: number;
  private readonly adapter?: NotificationAdapter;
  /** Injected fetch for testing; defaults to globalThis.fetch */
  private readonly fetchFn: typeof globalThis.fetch | undefined;

  constructor(
    config: WebhookSinkConfig,
    opts?: { adapter?: NotificationAdapter; fetch?: typeof globalThis.fetch | undefined },
  ) {
    this.url = config.url;
    this.headers = config.headers ?? {};
    this.timeoutMs = config.timeoutMs ?? 10_000;
    this.retries = config.retries ?? 1;
    this.retryDelayMs = config.retryDelayMs ?? 2000;
    this.adapter = opts?.adapter;
    this.fetchFn = opts?.fetch !== undefined ? opts.fetch : globalThis.fetch;
  }

  async send(message: string): Promise<void> {
    const payload = this.adapter ? this.adapter.format(message) : { text: message };
    const body = JSON.stringify(payload);
    const contentType = this.adapter?.contentType ?? "application/json";

    let lastError: Error | null = null;
    for (let attempt = 0; attempt <= this.retries; attempt++) {
      if (attempt > 0) {
        await new Promise((r) => setTimeout(r, this.retryDelayMs));
      }
      try {
        await this.doPost(body, contentType);
        return;
      } catch (err: unknown) {
        lastError = err instanceof Error ? err : new Error(String(err));
      }
    }
    throw lastError!;
  }

  private async doPost(body: string, contentType: string): Promise<void> {
    const headers = { "Content-Type": contentType, ...this.headers };

    if (this.fetchFn) {
      const ac = new AbortController();
      const timer = setTimeout(() => ac.abort(), this.timeoutMs);
      try {
        const res = await this.fetchFn(this.url, {
          method: "POST",
          headers,
          body,
          signal: ac.signal,
        });
        if (!res.ok) {
          throw new LoaLibError(
            `Webhook returned ${res.status}: ${res.statusText}`,
            "SCH_003",
            true,
          );
        }
      } finally {
        clearTimeout(timer);
      }
    } else {
      // Fallback to node:https
      const ac = new AbortController();
      const result = await httpsPost(this.url, body, headers, this.timeoutMs, ac.signal);
      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw new LoaLibError(
          `Webhook returned ${result.statusCode}`,
          "SCH_003",
          true,
        );
      }
    }
  }
}

// ── Adapters ─────────────────────────────────────────

export class SlackAdapter implements NotificationAdapter {
  contentType = "application/json";

  format(message: string): unknown {
    return {
      blocks: [
        {
          type: "section",
          text: { type: "mrkdwn", text: message },
        },
      ],
    };
  }
}

export class DiscordAdapter implements NotificationAdapter {
  contentType = "application/json";

  format(message: string): unknown {
    return {
      embeds: [
        {
          description: message,
          color: 0x5865f2,
        },
      ],
    };
  }
}

// ── Factory ──────────────────────────────────────────

export function createWebhookSink(
  config: WebhookSinkConfig,
  opts?: { adapter?: NotificationAdapter; fetch?: typeof globalThis.fetch | undefined },
): WebhookSink {
  return new WebhookSink(config, opts);
}
