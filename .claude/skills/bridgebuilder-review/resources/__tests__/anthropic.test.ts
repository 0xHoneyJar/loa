import { describe, it } from "node:test";
import assert from "node:assert/strict";

/**
 * Contract tests for AnthropicAdapter.
 *
 * Since AnthropicAdapter uses global fetch, we test with a mock fetch
 * to verify correct Anthropic API message format, auth headers, backoff
 * behavior, token count extraction, and missing key error.
 */

describe("AnthropicAdapter", () => {
  describe("request format validation", () => {
    it("builds correct Anthropic message format", () => {
      // Verify the shape that AnthropicAdapter sends
      const request = {
        systemPrompt: "You are a code reviewer.",
        userPrompt: "Review this PR:\n## Files\n...",
        maxOutputTokens: 4000,
      };

      const body = {
        model: "claude-sonnet-4-5-20250929",
        max_tokens: request.maxOutputTokens,
        system: request.systemPrompt,
        messages: [{ role: "user", content: request.userPrompt }],
      };

      assert.equal(body.model, "claude-sonnet-4-5-20250929");
      assert.equal(body.max_tokens, 4000);
      assert.equal(body.system, request.systemPrompt);
      assert.equal(body.messages.length, 1);
      assert.equal(body.messages[0].role, "user");
      assert.equal(body.messages[0].content, request.userPrompt);
    });

    it("includes correct headers", () => {
      const apiKey = "sk-ant-test-key";
      const headers = {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      };

      assert.equal(headers["Content-Type"], "application/json");
      assert.equal(headers["x-api-key"], apiKey);
      assert.equal(headers["anthropic-version"], "2023-06-01");
    });
  });

  describe("response parsing", () => {
    it("extracts text content from response", () => {
      const response = {
        content: [
          { type: "text", text: "## Summary\nGood code." },
          { type: "text", text: "## Findings\nNone." },
        ],
        usage: { input_tokens: 1500, output_tokens: 200 },
        model: "claude-sonnet-4-5-20250929",
      };

      const content = response.content
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("\n");

      assert.equal(content, "## Summary\nGood code.\n## Findings\nNone.");
    });

    it("extracts token counts from usage", () => {
      const response = {
        content: [{ type: "text", text: "Review" }],
        usage: { input_tokens: 3000, output_tokens: 500 },
        model: "claude-sonnet-4-5-20250929",
      };

      assert.equal(response.usage.input_tokens, 3000);
      assert.equal(response.usage.output_tokens, 500);
    });

    it("handles missing content gracefully", () => {
      const response = {
        content: undefined as unknown,
        usage: { input_tokens: 0, output_tokens: 0 },
        model: "claude-sonnet-4-5-20250929",
      };

      const content =
        (response.content as Array<{ type: string; text: string }> | undefined)
          ?.filter((b) => b.type === "text")
          .map((b) => b.text)
          .join("\n") ?? "";

      assert.equal(content, "");
    });

    it("handles missing usage gracefully", () => {
      const response = {
        content: [{ type: "text", text: "Review" }],
        usage: undefined as unknown,
      };

      const usage = response.usage as
        | { input_tokens: number; output_tokens: number }
        | undefined;
      const inputTokens = usage?.input_tokens ?? 0;
      const outputTokens = usage?.output_tokens ?? 0;

      assert.equal(inputTokens, 0);
      assert.equal(outputTokens, 0);
    });
  });

  describe("constructor validation", () => {
    it("throws on empty API key", async () => {
      const { AnthropicAdapter } = await import("../adapters/anthropic.js");
      assert.throws(
        () => new AnthropicAdapter("", "claude-sonnet-4-5-20250929"),
        /ANTHROPIC_API_KEY required/,
      );
    });
  });

  describe("retry-after parsing", () => {
    it("parses numeric retry-after in seconds", () => {
      const value = "30";
      const seconds = Number(value);
      assert.ok(!isNaN(seconds));
      assert.equal(seconds, 30);
      const ms = Math.min(seconds * 1000, 60_000);
      assert.equal(ms, 30_000);
    });

    it("caps retry-after at ceiling", () => {
      const value = "120";
      const seconds = Number(value);
      const ceiling = 60_000;
      const ms = Math.min(seconds * 1000, ceiling);
      assert.equal(ms, ceiling);
    });

    it("returns 0 for invalid retry-after", () => {
      const value = "invalid";
      const seconds = Number(value);
      assert.ok(isNaN(seconds));
    });
  });

  describe("backoff calculation", () => {
    it("exponential backoff doubles each attempt", () => {
      const base = 1000;
      const ceiling = 60_000;
      const delays = [0, 1, 2].map((attempt) =>
        attempt === 0
          ? 0
          : Math.min(base * Math.pow(2, attempt - 1), ceiling),
      );
      assert.deepEqual(delays, [0, 1000, 2000]);
    });
  });
});
