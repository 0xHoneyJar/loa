import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { MultiModelConfigSchema, validateApiKeys, PROVIDER_API_KEY_ENV } from "../config.js";

describe("MultiModelConfigSchema", () => {
  it("returns defaults when parsed with empty object", () => {
    const config = MultiModelConfigSchema.parse({});
    assert.equal(config.enabled, false);
    assert.deepEqual(config.models, []);
    assert.equal(config.iteration_strategy, "final");
    assert.equal(config.api_key_mode, "graceful");
    assert.equal(config.consensus.enabled, true);
    assert.equal(config.consensus.scoring_thresholds.high_consensus, 700);
    assert.equal(config.consensus.scoring_thresholds.disputed_delta, 300);
    assert.equal(config.consensus.scoring_thresholds.low_value, 400);
    assert.equal(config.consensus.scoring_thresholds.blocker, 700);
    assert.equal(config.token_budget.per_model, null);
    assert.equal(config.token_budget.total, null);
    assert.equal(config.depth.structural_checklist, true);
    assert.equal(config.depth.checklist_min_elements, 5);
    assert.equal(config.depth.permission_to_question, true);
    assert.equal(config.depth.lore_active_weaving, true);
    assert.equal(config.cross_repo.auto_detect, true);
    assert.deepEqual(config.cross_repo.manual_refs, []);
    assert.equal(config.rating.enabled, true);
    assert.equal(config.rating.timeout_seconds, 60);
    assert.equal(config.progress.verbose, true);
  });

  it("parses full 3-model configuration", () => {
    const config = MultiModelConfigSchema.parse({
      enabled: true,
      models: [
        { provider: "anthropic", model_id: "claude-opus-4-6", role: "primary" },
        { provider: "openai", model_id: "codex-5.2", role: "reviewer" },
        { provider: "google", model_id: "gemini-2.5-pro", role: "reviewer" },
      ],
      iteration_strategy: "every",
      api_key_mode: "strict",
      consensus: {
        scoring_thresholds: { high_consensus: 800 },
      },
      token_budget: { per_model: 100000 },
    });

    assert.equal(config.enabled, true);
    assert.equal(config.models.length, 3);
    assert.equal(config.models[0].role, "primary");
    assert.equal(config.models[1].provider, "openai");
    assert.equal(config.iteration_strategy, "every");
    assert.equal(config.api_key_mode, "strict");
    assert.equal(config.consensus.scoring_thresholds.high_consensus, 800);
    // Unset thresholds get defaults
    assert.equal(config.consensus.scoring_thresholds.disputed_delta, 300);
    assert.equal(config.token_budget.per_model, 100000);
    assert.equal(config.token_budget.total, null); // default
  });

  it("supports array iteration strategy", () => {
    const config = MultiModelConfigSchema.parse({
      iteration_strategy: [1, 3, 5],
    });
    assert.deepEqual(config.iteration_strategy, [1, 3, 5]);
  });

  it("defaults model role to reviewer", () => {
    const config = MultiModelConfigSchema.parse({
      models: [{ provider: "openai", model_id: "codex-5.2" }],
    });
    assert.equal(config.models[0].role, "reviewer");
  });

  it("rejects invalid api_key_mode", () => {
    assert.throws(() => {
      MultiModelConfigSchema.parse({ api_key_mode: "invalid" });
    });
  });

  it("rejects invalid iteration_strategy", () => {
    assert.throws(() => {
      MultiModelConfigSchema.parse({ iteration_strategy: "sometimes" });
    });
  });

  it("accepts null token budgets", () => {
    const config = MultiModelConfigSchema.parse({
      token_budget: { per_model: null, total: null },
    });
    assert.equal(config.token_budget.per_model, null);
    assert.equal(config.token_budget.total, null);
  });

  it("accepts custom cost rates", () => {
    const config = MultiModelConfigSchema.parse({
      cost_rates: {
        anthropic: { input: 0.015, output: 0.075 },
        openai: { input: 0.01, output: 0.03 },
      },
    });
    assert.equal(config.cost_rates?.anthropic?.input, 0.015);
    assert.equal(config.cost_rates?.openai?.output, 0.03);
  });
});

describe("validateApiKeys", () => {
  const originalEnv = { ...process.env };

  it("identifies available and missing keys", () => {
    process.env.ANTHROPIC_API_KEY = "sk-test-key";
    process.env.OPENAI_API_KEY = "sk-openai-test";
    delete process.env.GOOGLE_API_KEY;

    const config = MultiModelConfigSchema.parse({
      enabled: true,
      models: [
        { provider: "anthropic", model_id: "claude-opus-4-6" },
        { provider: "openai", model_id: "codex-5.2" },
        { provider: "google", model_id: "gemini-2.5-pro" },
      ],
    });

    const result = validateApiKeys(config);
    assert.equal(result.valid.length, 2);
    assert.equal(result.missing.length, 1);
    assert.equal(result.missing[0].provider, "google");
    assert.equal(result.missing[0].envVar, "GOOGLE_API_KEY");

    // Restore
    process.env = { ...originalEnv };
  });

  it("reports unknown provider as missing", () => {
    const config = MultiModelConfigSchema.parse({
      enabled: true,
      models: [{ provider: "mistral", model_id: "mistral-large" }],
    });

    const result = validateApiKeys(config);
    assert.equal(result.valid.length, 0);
    assert.equal(result.missing.length, 1);
    assert.ok(result.missing[0].envVar.includes("Unknown provider"));
  });

  it("returns empty lists for no models", () => {
    const config = MultiModelConfigSchema.parse({ enabled: true });
    const result = validateApiKeys(config);
    assert.equal(result.valid.length, 0);
    assert.equal(result.missing.length, 0);
  });
});

describe("PROVIDER_API_KEY_ENV", () => {
  it("maps the three initial providers", () => {
    assert.equal(PROVIDER_API_KEY_ENV.anthropic, "ANTHROPIC_API_KEY");
    assert.equal(PROVIDER_API_KEY_ENV.openai, "OPENAI_API_KEY");
    assert.equal(PROVIDER_API_KEY_ENV.google, "GOOGLE_API_KEY");
  });
});
