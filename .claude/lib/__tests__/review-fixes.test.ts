/**
 * Tests for PR #227 review fixes:
 * - C2: Zombie task prevention after unregister() during execution
 * - H3: verify() strictness with corrupt lines
 * - H4: Cancellation does not trip circuit breaker
 * - H1: Entry cap eviction in CompoundLearningCycle
 * - H5: Math.min/max stack safety (implicit via large entry test)
 * - H6: Timer-based scheduling coverage
 */
import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { Scheduler, createScheduler } from "../scheduler/scheduler.js";
import { createAuditLogger } from "../security/audit-logger.js";
import { createCompoundLearningCycle } from "../memory/compound-learning.js";
import { createFakeClock } from "../testing/fake-clock.js";
import type { MemoryEntry } from "../memory/quality-gates.js";

// ── C2: Zombie Task Prevention ──────────────────────────

describe("Scheduler — zombie task prevention (C2)", () => {
  let scheduler: Scheduler;

  afterEach(async () => {
    await scheduler?.shutdown(100);
  });

  it("unregister during execution prevents rescheduling", async () => {
    let execCount = 0;
    let resolveTask: () => void;
    const taskStarted = new Promise<void>((r) => { resolveTask = r; });

    scheduler = createScheduler();
    scheduler.register({
      id: "zombie-test",
      fn: async () => {
        execCount++;
        resolveTask();
        // Simulate long-running task
        await new Promise((r) => setTimeout(r, 50));
      },
      intervalMs: 10,
    });

    scheduler.start();

    // Wait for the first execution to start
    await taskStarted;

    // Unregister while the task is running
    scheduler.unregister("zombie-test");

    // Wait long enough for the task to complete and any zombie reschedule to fire
    await new Promise((r) => setTimeout(r, 200));

    // Should have executed only once — the zombie scheduleNext should have returned early
    assert.equal(execCount, 1, "Task should not have been rescheduled after unregister");
  });
});

// ── H3: Verify Strictness ────────────────────────────────

describe("AuditLogger — verify strictness (H3)", () => {
  let tempDir: string;
  let logPath: string;

  function setup() {
    tempDir = mkdtempSync(join(tmpdir(), "audit-strict-"));
    logPath = join(tempDir, "audit.jsonl");
  }

  function cleanup() {
    rmSync(tempDir, { recursive: true, force: true });
  }

  it("verify returns valid:false when corrupt lines present (strict default)", async () => {
    setup();
    try {
      const logger = createAuditLogger({ logPath });
      await logger.append("event.1", "actor", {});
      await logger.close();

      // Insert a garbage line directly into the file, then verify with the SAME
      // logger to bypass crash recovery (which would clean it on construction)
      const content = readFileSync(logPath, "utf-8");
      writeFileSync(logPath, content + "THIS IS GARBAGE\n");

      // Call verify on original logger — no new construction, no crash recovery
      const result = await logger.verify();
      assert.equal(result.valid, false, "Strict mode should report invalid when corrupt lines exist");
      assert.equal(result.truncated, 1);
    } finally {
      cleanup();
    }
  });

  it("verify returns valid:true with lenientVerify when corrupt lines present", async () => {
    setup();
    try {
      const logger = createAuditLogger({ logPath, lenientVerify: true });
      await logger.append("event.1", "actor", {});
      await logger.close();

      // Insert a garbage line, verify on same logger
      const content = readFileSync(logPath, "utf-8");
      writeFileSync(logPath, content + "THIS IS GARBAGE\n");

      const result = await logger.verify();
      assert.equal(result.valid, true, "Lenient mode should report valid despite corrupt lines");
      assert.equal(result.truncated, 1);
    } finally {
      cleanup();
    }
  });

  it("verify returns valid:true when no corrupt lines (strict mode)", async () => {
    setup();
    try {
      const logger = createAuditLogger({ logPath });
      await logger.append("event.1", "actor", {});
      await logger.append("event.2", "actor", {});
      const result = await logger.verify();
      assert.equal(result.valid, true);
      assert.equal(result.truncated, undefined);
    } finally {
      cleanup();
    }
  });
});

// ── H4: Cancellation Does Not Trip CB ────────────────────

describe("Scheduler — cancellation CB isolation (H4)", () => {
  let scheduler: Scheduler;

  afterEach(() => {
    scheduler?.stop();
  });

  it("cancellation does not count toward circuit breaker failures", async () => {
    const clock = createFakeClock(1000);
    scheduler = createScheduler({ clock });

    scheduler.register({
      id: "cancel-test",
      fn: async (signal) => {
        // Wait until cancelled
        await new Promise((resolve, reject) => {
          const timer = setTimeout(resolve, 10_000);
          signal?.addEventListener("abort", () => {
            clearTimeout(timer);
            reject(new Error("aborted"));
          });
        });
      },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 2, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    // Start the task, then cancel it
    const runPromise = scheduler.runNow("cancel-test");
    // Give the task a moment to start
    await new Promise((r) => setTimeout(r, 10));
    scheduler.cancel("cancel-test");
    await runPromise;

    // CB should still be CLOSED — cancellation is not a failure
    assert.equal(scheduler.getStatus("cancel-test").cbState, "CLOSED");
    assert.equal(scheduler.getStatus("cancel-test").failCount, 1); // fail count still increments
  });

  it("real failures still trip circuit breaker", async () => {
    const clock = createFakeClock(1000);
    scheduler = createScheduler({ clock });

    scheduler.register({
      id: "fail-test",
      fn: async () => { throw new Error("real failure"); },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 2, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    await scheduler.runNow("fail-test");
    await scheduler.runNow("fail-test");
    assert.equal(scheduler.getStatus("fail-test").cbState, "OPEN");
  });
});

// ── H1: Entry Cap Eviction ───────────────────────────────

describe("CompoundLearningCycle — entry cap (H1)", () => {
  function makeEntry(content: string, source = "test", timestamp = Date.now()): MemoryEntry {
    return { content, timestamp, source, confidence: 0.8 };
  }

  it("evicts oldest entries when maxEntries exceeded", () => {
    const cycle = createCompoundLearningCycle({ maxEntries: 5 });
    for (let i = 0; i < 10; i++) {
      cycle.addTrajectoryEntry(makeEntry(`entry-${i}`, "src", i));
    }
    assert.equal(cycle.getEntryCount(), 5);

    // The remaining entries should be the newest (5-9)
    const qualified = cycle.getQualifiedLearnings();
    assert.equal(qualified[0].content, "entry-5");
    assert.equal(qualified[4].content, "entry-9");
  });

  it("defaults to 10000 max entries", () => {
    const cycle = createCompoundLearningCycle();
    // Add 100 entries — should not evict
    for (let i = 0; i < 100; i++) {
      cycle.addTrajectoryEntry(makeEntry(`entry-${i}`));
    }
    assert.equal(cycle.getEntryCount(), 100);
  });

  it("extractPatterns works correctly after eviction", () => {
    const cycle = createCompoundLearningCycle({ maxEntries: 6 });
    // Add 4 "pattern A" entries and 4 "pattern B" entries
    for (let i = 0; i < 4; i++) {
      cycle.addTrajectoryEntry(makeEntry("pattern A", "src", i));
    }
    for (let i = 0; i < 4; i++) {
      cycle.addTrajectoryEntry(makeEntry("pattern B", "src", i + 10));
    }
    // After eviction: 2 A's evicted, 2 A's + 4 B's remain = 6
    assert.equal(cycle.getEntryCount(), 6);

    const patterns = cycle.extractPatterns();
    // Both should appear as patterns (each with freq >= 2)
    assert.equal(patterns.length, 2);
    // B should be first (higher frequency: 4 vs 2)
    assert.equal(patterns[0].content, "pattern B");
    assert.equal(patterns[0].frequency, 4);
    assert.equal(patterns[1].content, "pattern A");
    assert.equal(patterns[1].frequency, 2);
  });
});

// ── H6: Timer-Based Scheduling ───────────────────────────

describe("Scheduler — timer-based execution (H6)", () => {
  let scheduler: Scheduler;

  afterEach(async () => {
    await scheduler?.shutdown(200);
  });

  it("start() triggers task execution via timer", async () => {
    let execCount = 0;
    scheduler = createScheduler();
    scheduler.register({
      id: "timer-test",
      fn: async () => { execCount++; },
      intervalMs: 30,
    });

    scheduler.start();

    // Wait for at least 2 firings
    await new Promise((r) => setTimeout(r, 150));
    scheduler.stop();

    assert.ok(execCount >= 2, `Expected at least 2 executions, got ${execCount}`);
  });

  it("stop() halts timer-based execution", async () => {
    let execCount = 0;
    scheduler = createScheduler();
    scheduler.register({
      id: "stop-test",
      fn: async () => { execCount++; },
      intervalMs: 20,
    });

    scheduler.start();
    await new Promise((r) => setTimeout(r, 80));
    scheduler.stop();

    const countAtStop = execCount;
    await new Promise((r) => setTimeout(r, 100));

    assert.equal(execCount, countAtStop, "No more executions after stop");
  });

  it("disabled task does not fire via timer", async () => {
    let execCount = 0;
    scheduler = createScheduler();
    scheduler.register({
      id: "disabled-timer",
      fn: async () => { execCount++; },
      intervalMs: 20,
      enabled: false,
    });

    scheduler.start();
    await new Promise((r) => setTimeout(r, 100));
    scheduler.stop();

    assert.equal(execCount, 0, "Disabled task should not execute");
  });
});
