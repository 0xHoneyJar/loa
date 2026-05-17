/**
 * Pins deriveTimeoutMs predicate across all 3 providers in the BB triad.
 *
 * Origin: sprint-bug-165 (closes KF-010, issue #921). The cycle-100 #789a
 * predicate only granted the 1_800_000ms (30-min) budget to OpenAI gpt-*-pro;
 * reasoning-class Anthropic Opus + Google Gemini Pro fell into the 300_000ms
 * tier and SIGTERMed on realistic BB prompts. This test pins the multi-provider
 * extension so future predicate edits cannot silently re-narrow the scope.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { deriveTimeoutMs } from "../core/multi-model-pipeline.js";
import type { BridgebuilderConfig } from "../core/types.js";

const REASONING_BUDGET_MS = 1_800_000;

function makeConfig(maxInputTokens: number): BridgebuilderConfig {
  return {
    repos: [],
    model: "stub",
    maxPrs: 1,
    maxFilesPerPr: 1,
    maxDiffBytes: 1,
    maxInputTokens,
    maxOutputTokens: 1,
    dimensions: [],
    reviewMarker: "",
    repoOverridePath: "",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default",
    maxRuntimeMinutes: 1,
  };
}

describe("deriveTimeoutMs — reasoning-class predicate across all 3 providers", () => {
  const largeContextConfig = makeConfig(150_000);
  const midContextConfig = makeConfig(75_000);
  const smallContextConfig = makeConfig(25_000);

  it("OpenAI gpt-5.5-pro → 30-min budget (anti-regression of cycle-100 #789a)", () => {
    assert.equal(
      deriveTimeoutMs("openai", "gpt-5.5-pro", largeContextConfig),
      REASONING_BUDGET_MS,
    );
  });

  it("OpenAI gpt-5.6-pro → 30-min budget (forward-compat for next-gen Pro)", () => {
    assert.equal(
      deriveTimeoutMs("openai", "gpt-5.6-pro", largeContextConfig),
      REASONING_BUDGET_MS,
    );
  });

  it("OpenAI gpt-5.3-codex → tier-based (non-reasoning despite /v1/responses path)", () => {
    assert.equal(
      deriveTimeoutMs("openai", "gpt-5.3-codex", largeContextConfig),
      300_000,
    );
  });

  it("Anthropic claude-opus-4-7 → 30-min budget (NEW — closes KF-010)", () => {
    assert.equal(
      deriveTimeoutMs("anthropic", "claude-opus-4-7", largeContextConfig),
      REASONING_BUDGET_MS,
    );
  });

  it("Google gemini-3.1-pro-preview → 30-min budget (NEW — closes KF-010)", () => {
    assert.equal(
      deriveTimeoutMs("google", "gemini-3.1-pro-preview", largeContextConfig),
      REASONING_BUDGET_MS,
    );
  });

  it("Anthropic claude-sonnet-4-6 → tier-based (non-Opus Anthropic, non-reasoning)", () => {
    assert.equal(
      deriveTimeoutMs("anthropic", "claude-sonnet-4-6", largeContextConfig),
      300_000,
    );
  });

  it("Google gemini-3.1-flash → tier-based (non-Pro Google, non-reasoning)", () => {
    assert.equal(
      deriveTimeoutMs("google", "gemini-3.1-flash", largeContextConfig),
      300_000,
    );
  });

  it("tier-based ladder: maxInputTokens 75_000 → 180_000ms for non-reasoning", () => {
    assert.equal(
      deriveTimeoutMs("anthropic", "claude-sonnet-4-6", midContextConfig),
      180_000,
    );
  });

  it("tier-based ladder: maxInputTokens 25_000 → 120_000ms for non-reasoning", () => {
    assert.equal(
      deriveTimeoutMs("google", "gemini-3.1-flash", smallContextConfig),
      120_000,
    );
  });

  it("predicate is case-insensitive: Anthropic claude-OPUS-4-7 still reasoning", () => {
    assert.equal(
      deriveTimeoutMs("anthropic", "claude-OPUS-4-7", largeContextConfig),
      REASONING_BUDGET_MS,
    );
  });

  it("unknown provider falls through to tier ladder", () => {
    assert.equal(
      deriveTimeoutMs("xenocorp", "claude-opus-4-7", largeContextConfig),
      300_000,
    );
  });
});
