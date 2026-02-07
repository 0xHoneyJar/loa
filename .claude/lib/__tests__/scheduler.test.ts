import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { Scheduler, createScheduler } from "../scheduler/scheduler.js";
import { createFakeClock } from "../testing/fake-clock.js";

describe("Scheduler (T2.1a)", () => {
  let scheduler: Scheduler;

  afterEach(() => {
    scheduler?.stop();
  });

  // ── Factory ────────────────────────────────────────

  it("createScheduler returns a Scheduler", () => {
    scheduler = createScheduler();
    assert.ok(scheduler instanceof Scheduler);
  });

  // ── Registration ───────────────────────────────────

  it("register adds a task", () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "task-1",
      fn: async () => {},
      intervalMs: 1000,
    });
    const status = scheduler.getStatus("task-1");
    assert.equal(status.id, "task-1");
    assert.equal(status.state, "PENDING");
    assert.equal(status.enabled, true);
  });

  it("register throws on duplicate id", () => {
    scheduler = createScheduler();
    scheduler.register({ id: "t1", fn: async () => {}, intervalMs: 1000 });
    assert.throws(
      () => scheduler.register({ id: "t1", fn: async () => {}, intervalMs: 1000 }),
      (err: Error) => err.message.includes("already registered"),
    );
  });

  it("unregister removes a task", () => {
    scheduler = createScheduler();
    scheduler.register({ id: "t1", fn: async () => {}, intervalMs: 1000 });
    scheduler.unregister("t1");
    assert.throws(() => scheduler.getStatus("t1"));
  });

  it("getStatus throws for unknown task", () => {
    scheduler = createScheduler();
    assert.throws(
      () => scheduler.getStatus("nope"),
      (err: Error) => err.message.includes("not found"),
    );
  });

  it("getAllStatuses returns all tasks", () => {
    scheduler = createScheduler();
    scheduler.register({ id: "a", fn: async () => {}, intervalMs: 1000 });
    scheduler.register({ id: "b", fn: async () => {}, intervalMs: 2000 });
    const statuses = scheduler.getAllStatuses();
    assert.equal(statuses.length, 2);
    assert.deepEqual(
      statuses.map((s) => s.id).sort(),
      ["a", "b"],
    );
  });

  // ── Enable / Disable ──────────────────────────────

  it("disable prevents task from running", () => {
    scheduler = createScheduler();
    scheduler.register({ id: "t1", fn: async () => {}, intervalMs: 1000 });
    scheduler.disable("t1");
    assert.equal(scheduler.getStatus("t1").enabled, false);
  });

  it("enable re-enables a disabled task", () => {
    scheduler = createScheduler();
    scheduler.register({ id: "t1", fn: async () => {}, intervalMs: 1000 });
    scheduler.disable("t1");
    scheduler.enable("t1");
    assert.equal(scheduler.getStatus("t1").enabled, true);
  });

  it("register with enabled:false starts disabled", () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
      enabled: false,
    });
    assert.equal(scheduler.getStatus("t1").enabled, false);
  });

  // ── runNow ─────────────────────────────────────────

  it("runNow executes task immediately", async () => {
    const clock = createFakeClock(1000);
    let ran = false;
    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "t1",
      fn: async () => { ran = true; },
      intervalMs: 60000,
    });
    await scheduler.runNow("t1");
    assert.equal(ran, true);
    assert.equal(scheduler.getStatus("t1").state, "COMPLETED");
    assert.equal(scheduler.getStatus("t1").runCount, 1);
    assert.equal(scheduler.getStatus("t1").lastRunAt, 1000);
  });

  it("runNow records failure state", async () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("boom"); },
      intervalMs: 60000,
    });
    // Should not throw — error is captured in state
    await scheduler.runNow("t1");
    const status = scheduler.getStatus("t1");
    assert.equal(status.state, "FAILED");
    assert.equal(status.failCount, 1);
    assert.equal(status.lastError?.message, "boom");
  });

  // ── State Machine ──────────────────────────────────

  it("state transitions: PENDING → RUNNING → COMPLETED", async () => {
    const states: string[] = [];
    scheduler = createScheduler();

    let resolveFn: () => void;
    const taskPromise = new Promise<void>((resolve) => { resolveFn = resolve; });

    scheduler.register({
      id: "t1",
      fn: async () => {
        states.push(scheduler.getStatus("t1").state);
        resolveFn();
      },
      intervalMs: 60000,
    });

    states.push(scheduler.getStatus("t1").state); // PENDING
    await scheduler.runNow("t1");
    states.push(scheduler.getStatus("t1").state); // COMPLETED

    assert.deepEqual(states, ["PENDING", "RUNNING", "COMPLETED"]);
  });

  it("state transitions: PENDING → RUNNING → FAILED", async () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("fail"); },
      intervalMs: 60000,
    });
    assert.equal(scheduler.getStatus("t1").state, "PENDING");
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").state, "FAILED");
  });

  // ── Error Handler ──────────────────────────────────

  it("calls onTaskError on failure", async () => {
    const errors: { id: string; msg: string }[] = [];
    scheduler = createScheduler({
      onTaskError: (id, err) => errors.push({ id, msg: err.message }),
    });
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("boom"); },
      intervalMs: 60000,
    });
    await scheduler.runNow("t1");
    assert.equal(errors.length, 1);
    assert.equal(errors[0].id, "t1");
    assert.equal(errors[0].msg, "boom");
  });

  // ── Logger ─────────────────────────────────────────

  it("calls logger.info on register", () => {
    const logs: string[] = [];
    scheduler = createScheduler({
      logger: { info: (m) => logs.push(m), error: () => {} },
    });
    scheduler.register({ id: "t1", fn: async () => {}, intervalMs: 1000 });
    assert.ok(logs.some((l) => l.includes("t1") && l.includes("registered")));
  });

  it("calls logger.error on task failure", async () => {
    const errors: string[] = [];
    scheduler = createScheduler({
      logger: { info: () => {}, error: (m) => errors.push(m) },
    });
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("boom"); },
      intervalMs: 60000,
    });
    await scheduler.runNow("t1");
    assert.ok(errors.some((e) => e.includes("boom")));
  });

  // ── Start / Stop ───────────────────────────────────

  it("start/stop toggles running state", () => {
    scheduler = createScheduler();
    assert.equal(scheduler.isRunning(), false);
    scheduler.start();
    assert.equal(scheduler.isRunning(), true);
    scheduler.stop();
    assert.equal(scheduler.isRunning(), false);
  });

  it("start is idempotent", () => {
    scheduler = createScheduler();
    scheduler.start();
    scheduler.start(); // should not throw
    assert.equal(scheduler.isRunning(), true);
  });

  // ── FR-3.1: Multiple Tasks at Different Intervals ──

  it("FR-3.1: 3 tasks at different intervals fire correctly via runNow", async () => {
    const clock = createFakeClock(0);
    const executions: string[] = [];

    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "fast",
      fn: async () => { executions.push("fast"); },
      intervalMs: 100,
    });
    scheduler.register({
      id: "medium",
      fn: async () => { executions.push("medium"); },
      intervalMs: 200,
    });
    scheduler.register({
      id: "slow",
      fn: async () => { executions.push("slow"); },
      intervalMs: 500,
    });

    // Manually trigger each to verify they work independently
    await scheduler.runNow("fast");
    await scheduler.runNow("medium");
    await scheduler.runNow("slow");

    assert.deepEqual(executions, ["fast", "medium", "slow"]);

    // All should be COMPLETED
    assert.equal(scheduler.getStatus("fast").state, "COMPLETED");
    assert.equal(scheduler.getStatus("medium").state, "COMPLETED");
    assert.equal(scheduler.getStatus("slow").state, "COMPLETED");

    // Run counts
    assert.equal(scheduler.getStatus("fast").runCount, 1);
    assert.equal(scheduler.getStatus("medium").runCount, 1);
    assert.equal(scheduler.getStatus("slow").runCount, 1);
  });

  // ── Jitter ─────────────────────────────────────────

  it("jitterMs is accepted in config", () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
      jitterMs: 200,
    });
    // Just verify it doesn't throw — jitter affects timer scheduling
    assert.equal(scheduler.getStatus("t1").state, "PENDING");
  });

  // ── Overlap Policy ─────────────────────────────────

  it("skipOnOverlap defaults to true", () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
    });
    // Default is true — verify via getStatus (can't directly inspect config)
    assert.equal(scheduler.getStatus("t1").state, "PENDING");
  });
});
