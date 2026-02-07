import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  CompoundLearningCycle,
  createCompoundLearningCycle,
} from "../memory/compound-learning.js";
import type { MemoryEntry } from "../memory/quality-gates.js";

describe("CompoundLearningCycle", () => {
  // ── Helper ─────────────────────────────────────────

  function makeEntry(
    content: string,
    source = "test",
    timestamp = Date.now(),
  ): MemoryEntry {
    return { content, timestamp, source, confidence: 0.8 };
  }

  // ── Factory ────────────────────────────────────────

  it("createCompoundLearningCycle returns instance", () => {
    const cycle = createCompoundLearningCycle();
    assert.ok(cycle instanceof CompoundLearningCycle);
  });

  // ── addTrajectoryEntry ─────────────────────────────

  it("accumulates entries", () => {
    const cycle = createCompoundLearningCycle();
    cycle.addTrajectoryEntry(makeEntry("entry 1"));
    cycle.addTrajectoryEntry(makeEntry("entry 2"));
    assert.equal(cycle.getEntryCount(), 2);
  });

  // ── extractPatterns ────────────────────────────────

  it("identifies recurring patterns by frequency", () => {
    const cycle = createCompoundLearningCycle();
    cycle.addTrajectoryEntry(makeEntry("pattern A", "src1", 100));
    cycle.addTrajectoryEntry(makeEntry("pattern A", "src2", 200));
    cycle.addTrajectoryEntry(makeEntry("pattern A", "src1", 300));
    cycle.addTrajectoryEntry(makeEntry("unique B", "src1", 400));

    const patterns = cycle.extractPatterns();
    assert.equal(patterns.length, 1); // Only "pattern A" has frequency > 1
    assert.equal(patterns[0].frequency, 3);
    assert.equal(patterns[0].content, "pattern A");
    assert.equal(patterns[0].firstSeen, 100);
    assert.equal(patterns[0].lastSeen, 300);
    assert.deepEqual(patterns[0].sources, ["src1", "src2"]);
  });

  it("confidence scales with frequency (max at 5)", () => {
    const cycle = createCompoundLearningCycle();
    for (let i = 0; i < 5; i++) {
      cycle.addTrajectoryEntry(makeEntry("repeated pattern", "src", i));
    }
    const patterns = cycle.extractPatterns();
    assert.equal(patterns[0].confidence, 1);
  });

  it("returns empty array when no recurring patterns", () => {
    const cycle = createCompoundLearningCycle();
    cycle.addTrajectoryEntry(makeEntry("unique 1"));
    cycle.addTrajectoryEntry(makeEntry("unique 2"));
    const patterns = cycle.extractPatterns();
    assert.equal(patterns.length, 0);
  });

  it("sorts patterns by frequency descending", () => {
    const cycle = createCompoundLearningCycle();
    // 2 occurrences of A
    cycle.addTrajectoryEntry(makeEntry("A"));
    cycle.addTrajectoryEntry(makeEntry("A"));
    // 3 occurrences of B
    cycle.addTrajectoryEntry(makeEntry("B"));
    cycle.addTrajectoryEntry(makeEntry("B"));
    cycle.addTrajectoryEntry(makeEntry("B"));

    const patterns = cycle.extractPatterns();
    assert.equal(patterns[0].content, "B");
    assert.equal(patterns[1].content, "A");
  });

  // ── getQualifiedLearnings ──────────────────────────

  it("returns all entries when no quality gates", () => {
    const cycle = createCompoundLearningCycle();
    cycle.addTrajectoryEntry(makeEntry("entry 1"));
    cycle.addTrajectoryEntry(makeEntry("entry 2"));
    const qualified = cycle.getQualifiedLearnings();
    assert.equal(qualified.length, 2);
  });

  it("filters entries through quality gate function", () => {
    const cycle = createCompoundLearningCycle({
      qualityGates: (entry) => ({
        pass: !entry.content.includes("bad"),
      }),
    });
    cycle.addTrajectoryEntry(makeEntry("good entry here"));
    cycle.addTrajectoryEntry(makeEntry("bad entry here"));
    cycle.addTrajectoryEntry(makeEntry("another good one"));

    const qualified = cycle.getQualifiedLearnings();
    assert.equal(qualified.length, 2);
  });

  // ── Logger ─────────────────────────────────────────

  it("calls logger on addTrajectoryEntry", () => {
    const logs: string[] = [];
    const cycle = createCompoundLearningCycle({
      logger: { info: (msg) => logs.push(msg) },
    });
    cycle.addTrajectoryEntry(makeEntry("test", "my-source"));
    assert.equal(logs.length, 1);
    assert.ok(logs[0].includes("my-source"));
  });
});
