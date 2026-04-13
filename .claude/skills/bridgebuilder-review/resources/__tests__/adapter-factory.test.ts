import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  createAdapter,
  registerAdapter,
  getRegisteredProviders,
} from "../adapters/adapter-factory.js";
import type { ILLMProvider, ReviewRequest, ReviewResponse } from "../ports/llm-provider.js";

describe("createAdapter", () => {
  it("creates Anthropic adapter for known provider", () => {
    const adapter = createAdapter({
      provider: "anthropic",
      modelId: "claude-opus-4-6",
      apiKey: "sk-ant-test",
      timeoutMs: 60_000,
    });
    assert.ok(adapter);
    assert.equal(typeof adapter.generateReview, "function");
  });

  it("throws for unknown provider", () => {
    assert.throws(
      () =>
        createAdapter({
          provider: "unknown-provider",
          modelId: "some-model",
          apiKey: "key",
        }),
      (err: Error) => {
        assert.ok(err.message.includes("Unknown provider"));
        assert.ok(err.message.includes("unknown-provider"));
        assert.ok(err.message.includes("anthropic")); // lists available
        return true;
      },
    );
  });

  it("uses default timeout when not specified", () => {
    // Should not throw — default timeout applies
    const adapter = createAdapter({
      provider: "anthropic",
      modelId: "claude-opus-4-6",
      apiKey: "sk-ant-test",
    });
    assert.ok(adapter);
  });
});

describe("registerAdapter", () => {
  it("registers and creates a custom provider", () => {
    const mockProvider: ILLMProvider = {
      async generateReview(_req: ReviewRequest): Promise<ReviewResponse> {
        return {
          content: "mock review",
          inputTokens: 100,
          outputTokens: 50,
          model: "mock-model",
          provider: "mock",
        };
      },
    };

    registerAdapter("mock", () => mockProvider);

    const adapter = createAdapter({
      provider: "mock",
      modelId: "mock-model",
      apiKey: "mock-key",
    });
    assert.ok(adapter);
    assert.equal(adapter, mockProvider);
  });
});

describe("getRegisteredProviders", () => {
  it("includes anthropic in registered providers", () => {
    const providers = getRegisteredProviders();
    assert.ok(providers.includes("anthropic"));
  });

  it("includes custom registered providers", () => {
    registerAdapter("test-provider", () => ({
      async generateReview(): Promise<ReviewResponse> {
        return { content: "", inputTokens: 0, outputTokens: 0, model: "" };
      },
    }));
    const providers = getRegisteredProviders();
    assert.ok(providers.includes("test-provider"));
  });
});
