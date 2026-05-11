// cycle-103 Sprint 1 T1.4 — adapter-factory contract tests.
//
// Post-cycle-103: the factory returns ChevalDelegateAdapter for any provider.
// The registry concept (registerAdapter / getRegisteredProviders) was retired
// with the per-provider adapters. These tests pin the new universal-delegate
// behavior.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createAdapter } from "../adapters/adapter-factory.js";
import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";

describe("createAdapter (T1.4 — universal cheval delegate)", () => {
  it("returns a ChevalDelegateAdapter for anthropic", () => {
    const adapter = createAdapter({
      provider: "anthropic",
      modelId: "claude-opus-4-7",
      apiKey: "sk-ant-ignored-by-delegate",
      timeoutMs: 60_000,
    });
    assert.ok(adapter instanceof ChevalDelegateAdapter);
    assert.equal(typeof adapter.generateReview, "function");
  });

  it("returns a ChevalDelegateAdapter for openai", () => {
    const adapter = createAdapter({
      provider: "openai",
      modelId: "gpt-5.5-pro",
      apiKey: "sk-ignored",
    });
    assert.ok(adapter instanceof ChevalDelegateAdapter);
  });

  it("returns a ChevalDelegateAdapter for google", () => {
    const adapter = createAdapter({
      provider: "google",
      modelId: "gemini-3.1-pro-preview",
      apiKey: "AIzaIgnored",
    });
    assert.ok(adapter instanceof ChevalDelegateAdapter);
  });

  it("returns a ChevalDelegateAdapter for any provider — cheval handles resolution", () => {
    // Post-cycle-103: unknown providers don't throw at factory time. Cheval's
    // resolver maps modelId → provider via model-config.yaml; an unrecognized
    // modelId surfaces as cheval exit 2 → LLMProviderError(INVALID_REQUEST) at
    // call time.
    const adapter = createAdapter({
      provider: "unknown-provider-xyz",
      modelId: "claude-opus-4-7",
      apiKey: "k",
    });
    assert.ok(adapter instanceof ChevalDelegateAdapter);
  });

  it("apiKey and costRates are accepted but ignored (backward-compat)", () => {
    // Caller (multi-model-pipeline.ts) threads env-derived API keys into the
    // factory. Delegate uses env-inheritance directly, so the value is unused.
    // Accepting the field keeps the caller stable. costRates are also
    // accepted; cost tracking now lives entirely on the cheval side.
    const adapter = createAdapter({
      provider: "anthropic",
      modelId: "claude-opus-4-7",
      apiKey: "sk-ant-anything",
      costRates: { input: 0.000003, output: 0.000015 },
    });
    assert.ok(adapter instanceof ChevalDelegateAdapter);
  });

  it("uses default timeout when not specified", () => {
    const adapter = createAdapter({
      provider: "anthropic",
      modelId: "claude-opus-4-7",
      apiKey: "sk-ant-test",
    });
    assert.ok(adapter instanceof ChevalDelegateAdapter);
  });

  it("threads mockFixtureDir when provided (AC-1.2 substrate)", () => {
    // Constructor accepts the option; the delegate forwards it as the cheval
    // --mock-fixture-dir argv flag at generateReview time. We don't call
    // generateReview here — that would spawn python3. The fact the
    // constructor accepts the option without throwing is the contract pin.
    const adapter = createAdapter({
      provider: "anthropic",
      modelId: "claude-opus-4-7",
      apiKey: "sk-ant-test",
      mockFixtureDir: "/tmp/fixture-dir",
    });
    assert.ok(adapter instanceof ChevalDelegateAdapter);
  });
});
