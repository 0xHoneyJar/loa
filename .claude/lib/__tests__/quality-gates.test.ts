import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  temporalGate,
  speculationGate,
  instructionGate,
  confidenceGate,
  qualityGate,
  technicalGate,
  evaluateAllGates,
  type MemoryEntry,
} from "../memory/quality-gates.js";
import { createFakeClock } from "../testing/fake-clock.js";

describe("Quality Gates", () => {
  // ── Helper ─────────────────────────────────────────

  function makeEntry(overrides: Partial<MemoryEntry> = {}): MemoryEntry {
    return {
      content: "Fixed the authentication bug in login module",
      timestamp: Date.now(),
      source: "test",
      confidence: 0.8,
      ...overrides,
    };
  }

  // ── Temporal Gate ──────────────────────────────────

  describe("temporalGate", () => {
    it("passes for recent entries", () => {
      const clock = createFakeClock(1000);
      const entry = makeEntry({ timestamp: 900 });
      const result = temporalGate(entry, 200, clock);
      assert.equal(result.pass, true);
    });

    it("fails for old entries", () => {
      const clock = createFakeClock(1000);
      const entry = makeEntry({ timestamp: 500 });
      const result = temporalGate(entry, 200, clock);
      assert.equal(result.pass, false);
      assert.ok(result.reason?.includes("too old"));
    });
  });

  // ── Speculation Gate ───────────────────────────────

  describe("speculationGate", () => {
    it("FR-2.1: entry with 'might' is filtered", () => {
      const entry = makeEntry({ content: "This might cause issues" });
      const result = speculationGate(entry);
      assert.equal(result.pass, false);
      assert.ok(result.reason?.includes("might"));
    });

    it("passes for non-speculative content", () => {
      const entry = makeEntry({ content: "Fixed the authentication bug" });
      assert.equal(speculationGate(entry).pass, true);
    });

    it("detects 'probably'", () => {
      const entry = makeEntry({ content: "This is probably wrong" });
      assert.equal(speculationGate(entry).pass, false);
    });

    it("detects 'perhaps'", () => {
      const entry = makeEntry({ content: "Perhaps we should refactor" });
      assert.equal(speculationGate(entry).pass, false);
    });
  });

  // ── Instruction Gate ───────────────────────────────

  describe("instructionGate", () => {
    it("filters instruction content", () => {
      const entry = makeEntry({ content: "Please update the config file" });
      assert.equal(instructionGate(entry).pass, false);
    });

    it("passes non-instruction content", () => {
      const entry = makeEntry({ content: "Updated the config file successfully" });
      assert.equal(instructionGate(entry).pass, true);
    });
  });

  // ── Confidence Gate ────────────────────────────────

  describe("confidenceGate", () => {
    it("passes high confidence", () => {
      const entry = makeEntry({ confidence: 0.9 });
      assert.equal(confidenceGate(entry, 0.5).pass, true);
    });

    it("fails low confidence", () => {
      const entry = makeEntry({ confidence: 0.3 });
      const result = confidenceGate(entry, 0.5);
      assert.equal(result.pass, false);
      assert.ok(result.reason?.includes("0.3"));
    });

    it("passes when confidence is undefined", () => {
      const entry = makeEntry({ confidence: undefined });
      assert.equal(confidenceGate(entry).pass, true);
    });
  });

  // ── Quality Gate ───────────────────────────────────

  describe("qualityGate", () => {
    it("fails short content", () => {
      const entry = makeEntry({ content: "hi" });
      assert.equal(qualityGate(entry).pass, false);
    });

    it("fails repetitive content", () => {
      const entry = makeEntry({ content: "test test test test test" });
      assert.equal(qualityGate(entry).pass, false);
    });

    it("passes substantive content", () => {
      const entry = makeEntry({ content: "Fixed the authentication bug in the login module" });
      assert.equal(qualityGate(entry).pass, true);
    });
  });

  // ── Technical Gate ─────────────────────────────────

  describe("technicalGate", () => {
    it("passes content with technical terms", () => {
      const entry = makeEntry({ content: "The function handles error cases" });
      assert.equal(technicalGate(entry).pass, true);
    });

    it("fails non-technical content", () => {
      const entry = makeEntry({ content: "The weather is nice today indeed" });
      assert.equal(technicalGate(entry).pass, false);
    });
  });

  // ── Composite ──────────────────────────────────────

  describe("evaluateAllGates", () => {
    it("passes when all gates pass", () => {
      const entry = makeEntry();
      const result = evaluateAllGates(entry);
      assert.equal(result.pass, true);
    });

    it("returns first failure", () => {
      const entry = makeEntry({ content: "This might work with the function" });
      const result = evaluateAllGates(entry);
      assert.equal(result.pass, false);
      assert.ok(result.reason?.includes("might"));
    });

    it("respects maxAgeMs config", () => {
      const clock = createFakeClock(10000);
      const entry = makeEntry({ timestamp: 1000 });
      const result = evaluateAllGates(entry, { maxAgeMs: 5000, clock });
      assert.equal(result.pass, false);
      assert.ok(result.reason?.includes("too old"));
    });

    it("respects confidenceThreshold config", () => {
      const entry = makeEntry({ confidence: 0.3 });
      const result = evaluateAllGates(entry, { confidenceThreshold: 0.5 });
      assert.equal(result.pass, false);
    });
  });
});
