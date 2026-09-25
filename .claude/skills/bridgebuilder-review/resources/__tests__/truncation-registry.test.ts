/**
 * cycle-126 Sprint 1 Task 1.4 (PRD FR-1.5, SDD D-1.5) — the generated table
 * takes the yaml's declared output (capped at 32K) and a reasoning flag per
 * entry; the 5-family is reasoning-class with a 32K output budget, entries
 * without a declaration keep the provider default, the fallback stays 4096.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { GENERATED_TOKEN_BUDGETS } from "../core/truncation.generated.js";
import { GENERATED_MODEL_REGISTRY, GENERATED_REASONING } from "../config.generated.js";

const FIVE = ["claude-opus-5", "claude-sonnet-5", "claude-fable-5-1"];

describe("generated truncation table (cycle-126)", () => {
  it("maxOutput 32000 for the 5-family (yaml 128K capped at BB_OUTPUT_CAP)", () => {
    for (const id of FIVE) {
      assert.equal(GENERATED_TOKEN_BUDGETS[id]?.maxOutput, 32_000, id);
      assert.equal(GENERATED_TOKEN_BUDGETS[id]?.maxInput, 160_000, id); // probed 180K − 20K headroom
    }
  });
  it("an entry without max_output_tokens keeps the provider default; the fallback stays 4096", () => {
    assert.equal(GENERATED_TOKEN_BUDGETS["claude-headless"]?.maxOutput, 8_192);
    assert.equal(GENERATED_TOKEN_BUDGETS["default"]?.maxOutput, 4_096);
  });
  it("an OpenAI entry follows its declaration too (gpt-5.5 → 32000)", () => {
    assert.equal(GENERATED_TOKEN_BUDGETS["gpt-5.5"]?.maxOutput, 32_000);
  });
});

describe("generated reasoning flag (cycle-126)", () => {
  it("true for the 5-family and the adaptive 4.6–4.8 entries, false for Haiku and the headless hops", () => {
    for (const id of FIVE) assert.equal(GENERATED_REASONING[id], true, id);
    assert.equal(GENERATED_REASONING["claude-sonnet-4-6"], true);
    assert.equal(GENERATED_REASONING["claude-haiku-4-5-20251001"], false);
    assert.equal(GENERATED_REASONING["codex-headless"], false);
  });
  it("the registry entries carry the same flag", () => {
    for (const [id, flag] of Object.entries(GENERATED_REASONING)) {
      assert.equal(GENERATED_MODEL_REGISTRY[id]?.reasoning, flag, id);
    }
  });
});
