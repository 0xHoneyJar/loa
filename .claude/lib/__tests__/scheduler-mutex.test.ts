import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { Scheduler, createScheduler } from "../scheduler/scheduler.js";
import { createFakeClock } from "../testing/fake-clock.js";

describe("Scheduler Mutex, Cancellation, Shutdown (T2.1c)", () => {
  let scheduler: Scheduler;

  afterEach(async () => {
    await scheduler?.shutdown(100);
  });

  // ── Mutex Groups ─────────────────────────────────

  it("tasks in the same mutex group execute serially", async () => {
    const clock = createFakeClock(1000);
    const order: string[] = [];
    scheduler = createScheduler({ clock });

    let resolveA!: () => void;
    const promiseA = new Promise<void>((r) => { resolveA = r; });

    scheduler.register({
      id: "a",
      fn: async () => {
        order.push("a-start");
        await promiseA;
        order.push("a-end");
      },
      intervalMs: 1000,
      mutexGroup: "g1",
    });

    scheduler.register({
      id: "b",
      fn: async () => {
        order.push("b-start");
        order.push("b-end");
      },
      intervalMs: 1000,
      mutexGroup: "g1",
    });

    // Start both concurrently — b should wait for a
    const runA = scheduler.runNow("a");
    const runB = scheduler.runNow("b");

    // a is running, b should be queued
    await new Promise((r) => setTimeout(r, 10));
    assert.deepEqual(order, ["a-start"]);

    // Let a finish
    resolveA();
    await runA;
    await runB;

    assert.deepEqual(order, ["a-start", "a-end", "b-start", "b-end"]);
  });

  it("tasks in different mutex groups execute concurrently", async () => {
    const clock = createFakeClock(1000);
    const order: string[] = [];
    scheduler = createScheduler({ clock });

    let resolveA!: () => void;
    const promiseA = new Promise<void>((r) => { resolveA = r; });
    let resolveB!: () => void;
    const promiseB = new Promise<void>((r) => { resolveB = r; });

    scheduler.register({
      id: "a",
      fn: async () => {
        order.push("a-start");
        await promiseA;
        order.push("a-end");
      },
      intervalMs: 1000,
      mutexGroup: "g1",
    });

    scheduler.register({
      id: "b",
      fn: async () => {
        order.push("b-start");
        await promiseB;
        order.push("b-end");
      },
      intervalMs: 1000,
      mutexGroup: "g2",
    });

    const runA = scheduler.runNow("a");
    const runB = scheduler.runNow("b");

    await new Promise((r) => setTimeout(r, 10));
    // Both should have started since they're in different groups
    assert.ok(order.includes("a-start"));
    assert.ok(order.includes("b-start"));

    resolveA();
    resolveB();
    await runA;
    await runB;
  });

  it("tasks without mutex group are not serialized", async () => {
    const clock = createFakeClock(1000);
    const order: string[] = [];
    scheduler = createScheduler({ clock });

    let resolveA!: () => void;
    const promiseA = new Promise<void>((r) => { resolveA = r; });

    scheduler.register({
      id: "a",
      fn: async () => {
        order.push("a-start");
        await promiseA;
        order.push("a-end");
      },
      intervalMs: 1000,
    });

    scheduler.register({
      id: "b",
      fn: async () => {
        order.push("b-start");
        order.push("b-end");
      },
      intervalMs: 1000,
    });

    const runA = scheduler.runNow("a");
    const runB = scheduler.runNow("b");

    await new Promise((r) => setTimeout(r, 10));
    // Both start independently
    assert.ok(order.includes("a-start"));
    assert.ok(order.includes("b-start"));

    resolveA();
    await runA;
    await runB;
  });

  // ── Cancellation ─────────────────────────────────

  it("cancel() aborts a running task via AbortSignal", async () => {
    const clock = createFakeClock(1000);
    let signalAborted = false;
    scheduler = createScheduler({ clock });

    let resolveTask!: () => void;
    const taskPromise = new Promise<void>((r) => { resolveTask = r; });

    scheduler.register({
      id: "t1",
      fn: async (signal) => {
        await taskPromise;
        signalAborted = signal?.aborted ?? false;
      },
      intervalMs: 1000,
    });

    const run = scheduler.runNow("t1");

    await new Promise((r) => setTimeout(r, 10));
    scheduler.cancel("t1");

    resolveTask();
    await run;

    assert.equal(signalAborted, true);
    assert.equal(scheduler.getStatus("t1").state, "FAILED");
    assert.equal(scheduler.getStatus("t1").lastError?.message, "Task was cancelled");
  });

  it("fn receives AbortSignal on every execution", async () => {
    const clock = createFakeClock(1000);
    let receivedSignal = false;
    scheduler = createScheduler({ clock });

    scheduler.register({
      id: "t1",
      fn: async (signal) => {
        receivedSignal = signal instanceof AbortSignal;
      },
      intervalMs: 1000,
    });

    await scheduler.runNow("t1");
    assert.equal(receivedSignal, true);
    assert.equal(scheduler.getStatus("t1").state, "COMPLETED");
  });

  it("cancel on non-running task is a no-op", () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
    });

    // Should not throw
    scheduler.cancel("t1");
    assert.equal(scheduler.getStatus("t1").state, "PENDING");
  });

  // ── Shutdown ─────────────────────────────────────

  it("shutdown() stops timers and aborts running tasks", async () => {
    const clock = createFakeClock(1000);
    let signalAborted = false;
    scheduler = createScheduler({ clock });

    let resolveTask!: () => void;
    const taskPromise = new Promise<void>((r) => { resolveTask = r; });

    scheduler.register({
      id: "t1",
      fn: async (signal) => {
        await taskPromise;
        signalAborted = signal?.aborted ?? false;
      },
      intervalMs: 1000,
    });

    const run = scheduler.runNow("t1");

    await new Promise((r) => setTimeout(r, 10));

    // Shutdown while task is running
    resolveTask();
    await scheduler.shutdown(200);
    await run;

    assert.equal(signalAborted, true);
    assert.equal(scheduler.isRunning(), false);
  });

  it("shutdown() waits for running tasks to drain", async () => {
    const clock = createFakeClock(1000);
    let taskFinished = false;
    scheduler = createScheduler({ clock });

    scheduler.register({
      id: "t1",
      fn: async () => {
        await new Promise((r) => setTimeout(r, 50));
        taskFinished = true;
      },
      intervalMs: 1000,
    });

    scheduler.runNow("t1"); // fire-and-forget
    await new Promise((r) => setTimeout(r, 10));

    await scheduler.shutdown(5000);
    assert.equal(taskFinished, true);
  });

  it("shutdown() respects timeout and does not wait forever", async () => {
    const clock = createFakeClock(1000);
    scheduler = createScheduler({ clock });

    scheduler.register({
      id: "t1",
      fn: async () => {
        // Task that never finishes
        await new Promise(() => {});
      },
      intervalMs: 1000,
    });

    scheduler.runNow("t1"); // fire-and-forget
    await new Promise((r) => setTimeout(r, 10));

    const start = Date.now();
    await scheduler.shutdown(100);
    const elapsed = Date.now() - start;

    // Should have timed out around 100ms, not wait forever
    assert.ok(elapsed < 500, `Shutdown took ${elapsed}ms, expected ~100ms`);
  });

  it("shutdown() is idempotent", async () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
    });

    await scheduler.shutdown(100);
    await scheduler.shutdown(100); // should not throw
  });

  it("shutdown() logs start and complete", async () => {
    const infos: string[] = [];
    scheduler = createScheduler({
      logger: { info: (m) => infos.push(m), error: () => {} },
    });
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
    });

    await scheduler.shutdown(100);
    assert.ok(infos.some((m) => m.includes("shutting down")));
    assert.ok(infos.some((m) => m.includes("shutdown complete")));
  });
});
