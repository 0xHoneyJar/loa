import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { createLocalAdapters } from "../adapters/index.js";
import type { BridgebuilderConfig } from "../core/types.js";

// ---------------------------------------------------------------------------
// Regression tests for cycle-109 followup #880 Defect 1
//
// createLocalAdapters() previously threw unconditionally when
// anthropicApiKey was empty. That defeats the substrate-degraded path
// where operators set BRIDGEBUILDER_MODEL=claude-headless to route
// through Claude Code OAuth subscription (no API key required).
//
// Fix: skip the API-key precondition when config.model resolves to a
// kind:cli headless adapter (claude-headless / codex-headless /
// gemini-headless). The ChevalDelegateAdapter handles its own auth
// routing internally (post-PR #892 the subprocess env is also stripped
// of ANTHROPIC_API_KEY).
// ---------------------------------------------------------------------------

function makeConfig(overrides: Partial<BridgebuilderConfig> = {}): BridgebuilderConfig {
  return {
    repo: "0xHoneyJar/loa",
    pr: 1,
    model: "claude-opus-4-7",
    reviewMarker: "<!-- bridgebuilder -->",
    timeoutSeconds: 600,
    maxRetries: 3,
    ...overrides,
  } as BridgebuilderConfig;
}

describe("createLocalAdapters precondition (cycle-109 #880 Defect 1)", () => {
  it("throws when API-mode model + ANTHROPIC_API_KEY is empty", () => {
    assert.throws(
      () => createLocalAdapters(makeConfig({ model: "claude-opus-4-7" }), ""),
      /ANTHROPIC_API_KEY required/,
    );
  });

  it("allows BRIDGEBUILDER_MODEL=claude-headless without ANTHROPIC_API_KEY", () => {
    // Operator routes BB through Claude Code OAuth subscription. No
    // API key in env; BB must NOT throw the precondition.
    const adapters = createLocalAdapters(
      makeConfig({ model: "claude-headless" }),
      "",
    );
    assert.ok(adapters.llm, "llm adapter wired");
    assert.ok(adapters.git, "git adapter wired");
  });

  it("allows BRIDGEBUILDER_MODEL=codex-headless without API key (symmetric)", () => {
    const adapters = createLocalAdapters(
      makeConfig({ model: "codex-headless" }),
      "",
    );
    assert.ok(adapters.llm);
  });

  it("allows BRIDGEBUILDER_MODEL=gemini-headless without API key (symmetric)", () => {
    const adapters = createLocalAdapters(
      makeConfig({ model: "gemini-headless" }),
      "",
    );
    assert.ok(adapters.llm);
  });

  it("allows any *-headless alias suffix (defense-in-depth)", () => {
    // Future-proof: operator may declare a custom alias like
    // `enterprise-headless`. The kind:cli convention is the contract;
    // the precondition should match the convention, not enumerate
    // every known headless alias.
    const adapters = createLocalAdapters(
      makeConfig({ model: "enterprise-headless" }),
      "",
    );
    assert.ok(adapters.llm);
  });

  it("API-mode model still requires the key (positive control)", () => {
    // Even when one of the three known headless aliases is the default,
    // a different API-mode model name MUST still trigger the precondition.
    assert.throws(
      () => createLocalAdapters(makeConfig({ model: "gpt-5.5-pro" }), ""),
      /ANTHROPIC_API_KEY required/,
    );
  });

  it("API key present + headless model is harmless (no false-rejection)", () => {
    // Operator may set ANTHROPIC_API_KEY for another reason but route BB
    // via claude-headless. Precondition is satisfied either way.
    const adapters = createLocalAdapters(
      makeConfig({ model: "claude-headless" }),
      "sk-ant-test",
    );
    assert.ok(adapters.llm);
  });
});
