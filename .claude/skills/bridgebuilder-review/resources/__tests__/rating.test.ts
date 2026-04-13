import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  parseRatingInput,
  buildRatingPrompt,
  createRatingEntry,
  RATING_RUBRIC,
} from "../core/rating.js";

describe("parseRatingInput", () => {
  it("returns score for valid input 1-5", () => {
    assert.equal(parseRatingInput("1"), 1);
    assert.equal(parseRatingInput("3"), 3);
    assert.equal(parseRatingInput("5"), 5);
  });

  it("returns null for empty input (skip)", () => {
    assert.equal(parseRatingInput(""), null);
    assert.equal(parseRatingInput("  "), null);
  });

  it("returns null for out-of-range numbers", () => {
    assert.equal(parseRatingInput("0"), null);
    assert.equal(parseRatingInput("6"), null);
    assert.equal(parseRatingInput("-1"), null);
  });

  it("returns null for non-numeric input", () => {
    assert.equal(parseRatingInput("abc"), null);
    assert.equal(parseRatingInput("five"), null);
  });

  it("trims whitespace", () => {
    assert.equal(parseRatingInput("  3  "), 3);
  });
});

describe("buildRatingPrompt", () => {
  it("includes model and iteration info", () => {
    const prompt = buildRatingPrompt("run-123", "claude-opus-4-6", 2);
    assert.ok(prompt.includes("claude-opus-4-6"));
    assert.ok(prompt.includes("iteration 2"));
    assert.ok(prompt.includes("run-123"));
  });

  it("includes all rubric dimensions", () => {
    const prompt = buildRatingPrompt("run-123", "gpt-4o", 1);
    for (const key of Object.keys(RATING_RUBRIC)) {
      assert.ok(prompt.includes(key), `Should include dimension: ${key}`);
    }
  });

  it("includes scale description", () => {
    const prompt = buildRatingPrompt("run-123", "opus", 1);
    assert.ok(prompt.includes("1 (poor)"));
    assert.ok(prompt.includes("5 (excellent)"));
  });
});

describe("createRatingEntry", () => {
  it("creates entry with required fields", () => {
    const entry = createRatingEntry("run-123", 1, "opus", 4);
    assert.equal(entry.runId, "run-123");
    assert.equal(entry.iteration, 1);
    assert.equal(entry.model, "opus");
    assert.equal(entry.score, 4);
    assert.equal(entry.category, "overall");
    assert.ok(entry.timestamp);
  });

  it("includes optional fields", () => {
    const entry = createRatingEntry("run-123", 1, "opus", 5, {
      provider: "anthropic",
      category: "depth",
      comment: "Great FAANG parallels",
    });
    assert.equal(entry.provider, "anthropic");
    assert.equal(entry.category, "depth");
    assert.equal(entry.comment, "Great FAANG parallels");
  });
});

describe("RATING_RUBRIC", () => {
  it("has 4 dimensions", () => {
    assert.equal(Object.keys(RATING_RUBRIC).length, 4);
  });

  it("includes depth, accuracy, actionability, overall", () => {
    assert.ok("depth" in RATING_RUBRIC);
    assert.ok("accuracy" in RATING_RUBRIC);
    assert.ok("actionability" in RATING_RUBRIC);
    assert.ok("overall" in RATING_RUBRIC);
  });
});
