import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ContextTracker, createContextTracker } from "../memory/context-tracker.js";

describe("ContextTracker", () => {
  // ── Helper ─────────────────────────────────────────

  const mockCounter = { count: (text: string) => text.split(/\s+/).length };

  function makeTracker(maxTokens = 100) {
    return createContextTracker({ maxTokens, tokenCounter: mockCounter });
  }

  // ── Factory ────────────────────────────────────────

  it("createContextTracker returns a ContextTracker", () => {
    const t = makeTracker();
    assert.ok(t instanceof ContextTracker);
  });

  // ── Track ──────────────────────────────────────────

  it("track returns token count and level", () => {
    const t = makeTracker(100);
    const result = t.track("hello world foo");
    assert.equal(result.tokens, 3);
    assert.equal(result.totalUsed, 3);
    assert.equal(result.level, "normal");
  });

  it("accumulates tokens across track calls", () => {
    const t = makeTracker(100);
    t.track("a b c"); // 3
    const r = t.track("d e f g"); // 4
    assert.equal(r.totalUsed, 7);
  });

  // ── Threshold Transitions ──────────────────────────

  it("transitions to warning at 60%", () => {
    const t = makeTracker(100);
    t.track(Array(60).fill("w").join(" ")); // 60 tokens = 60%
    assert.equal(t.getUsage().level, "warning");
  });

  it("transitions to critical at 70%", () => {
    const t = makeTracker(100);
    t.track(Array(70).fill("w").join(" "));
    assert.equal(t.getUsage().level, "critical");
  });

  it("transitions to emergency at 80%", () => {
    const t = makeTracker(100);
    t.track(Array(80).fill("w").join(" "));
    assert.equal(t.getUsage().level, "emergency");
  });

  // ── getUsage ───────────────────────────────────────

  it("getUsage returns current state", () => {
    const t = makeTracker(200);
    t.track("a b c d e"); // 5 tokens
    const usage = t.getUsage();
    assert.equal(usage.used, 5);
    assert.equal(usage.max, 200);
    assert.equal(usage.percent, 0.025);
    assert.equal(usage.level, "normal");
  });

  // ── Reset ──────────────────────────────────────────

  it("reset clears counters", () => {
    const t = makeTracker(100);
    t.track("a b c d e");
    t.reset();
    const usage = t.getUsage();
    assert.equal(usage.used, 0);
    assert.equal(usage.level, "normal");
  });

  // ── Custom Thresholds ──────────────────────────────

  it("respects custom thresholds", () => {
    const t = createContextTracker({
      maxTokens: 100,
      tokenCounter: mockCounter,
      thresholds: { warning: 0.3, critical: 0.5, emergency: 0.7 },
    });
    t.track(Array(35).fill("w").join(" ")); // 35%
    assert.equal(t.getUsage().level, "warning");
  });
});
