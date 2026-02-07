import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { Scheduler, createScheduler } from "../scheduler/scheduler.js";
import { createFakeClock } from "../testing/fake-clock.js";

describe("Scheduler Circuit Breaker (T2.1b)", () => {
  let scheduler: Scheduler;

  afterEach(() => {
    scheduler?.stop();
  });

  // ── CB State Reporting ─────────────────────────────

  it("status shows cbState when CB configured", () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 3, resetTimeMs: 5000 },
    });
    const status = scheduler.getStatus("t1");
    assert.equal(status.cbState, "CLOSED");
  });

  it("status has undefined cbState when no CB", () => {
    scheduler = createScheduler();
    scheduler.register({
      id: "t1",
      fn: async () => {},
      intervalMs: 1000,
    });
    assert.equal(scheduler.getStatus("t1").cbState, undefined);
  });

  // ── CB Opens After N Failures ──────────────────────

  it("CB opens after maxFailures consecutive failures", async () => {
    const clock = createFakeClock(1000);
    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("fail"); },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 3, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    // 3 consecutive failures should open the CB
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").cbState, "CLOSED"); // 1 failure
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").cbState, "CLOSED"); // 2 failures
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").cbState, "OPEN"); // 3 failures → OPEN
  });

  // ── CB Skips Execution When Open ───────────────────

  it("skips execution when CB is OPEN", async () => {
    const clock = createFakeClock(1000);
    let callCount = 0;
    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "t1",
      fn: async () => {
        callCount++;
        throw new Error("fail");
      },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 2, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    // Open the CB
    await scheduler.runNow("t1"); // call 1
    await scheduler.runNow("t1"); // call 2 → OPEN
    assert.equal(callCount, 2);
    assert.equal(scheduler.getStatus("t1").cbState, "OPEN");

    // Should skip — fn NOT called
    await scheduler.runNow("t1");
    assert.equal(callCount, 2); // Still 2 — fn was not invoked
  });

  // ── CB Transitions to HALF_OPEN ────────────────────

  it("transitions to HALF_OPEN after reset timeout", async () => {
    const clock = createFakeClock(1000);
    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("fail"); },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 2, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    // Open the CB
    await scheduler.runNow("t1");
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").cbState, "OPEN");

    // Advance past reset timeout
    clock.advanceBy(5001);

    // Should now be HALF_OPEN (lazy transition on getState)
    assert.equal(scheduler.getStatus("t1").cbState, "HALF_OPEN");
  });

  // ── HALF_OPEN → CLOSED on Success ─────────────────

  it("HALF_OPEN → CLOSED on successful probe", async () => {
    const clock = createFakeClock(1000);
    let shouldFail = true;
    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "t1",
      fn: async () => {
        if (shouldFail) throw new Error("fail");
      },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 2, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    // Open the CB
    await scheduler.runNow("t1");
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").cbState, "OPEN");

    // Advance to HALF_OPEN
    clock.advanceBy(5001);
    assert.equal(scheduler.getStatus("t1").cbState, "HALF_OPEN");

    // Successful probe
    shouldFail = false;
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").cbState, "CLOSED");
    assert.equal(scheduler.getStatus("t1").state, "COMPLETED");
  });

  // ── HALF_OPEN → OPEN on Failure ────────────────────

  it("HALF_OPEN → OPEN on failed probe", async () => {
    const clock = createFakeClock(1000);
    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("still failing"); },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 2, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    // Open → HALF_OPEN
    await scheduler.runNow("t1");
    await scheduler.runNow("t1");
    clock.advanceBy(5001);
    assert.equal(scheduler.getStatus("t1").cbState, "HALF_OPEN");

    // Failed probe → back to OPEN
    await scheduler.runNow("t1");
    assert.equal(scheduler.getStatus("t1").cbState, "OPEN");
  });

  // ── Success Resets Failure Count ───────────────────

  it("success resets failure count (CB stays closed)", async () => {
    const clock = createFakeClock(1000);
    let callNum = 0;
    scheduler = createScheduler({ clock });
    scheduler.register({
      id: "t1",
      fn: async () => {
        callNum++;
        if (callNum === 2) return; // success on 2nd call
        throw new Error("fail");
      },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 3, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    await scheduler.runNow("t1"); // fail (1)
    assert.equal(scheduler.getStatus("t1").cbState, "CLOSED");
    await scheduler.runNow("t1"); // success → resets count
    assert.equal(scheduler.getStatus("t1").cbState, "CLOSED");
    await scheduler.runNow("t1"); // fail (1 again, not 2)
    assert.equal(scheduler.getStatus("t1").cbState, "CLOSED");
    await scheduler.runNow("t1"); // fail (2)
    assert.equal(scheduler.getStatus("t1").cbState, "CLOSED"); // still < 3
  });

  // ── Logger Reports CB Skip ─────────────────────────

  it("logs when skipping due to open CB", async () => {
    const clock = createFakeClock(1000);
    const infos: string[] = [];
    scheduler = createScheduler({
      clock,
      logger: { info: (m) => infos.push(m), error: () => {} },
    });
    scheduler.register({
      id: "t1",
      fn: async () => { throw new Error("fail"); },
      intervalMs: 1000,
      circuitBreaker: { maxFailures: 1, resetTimeMs: 5000, halfOpenRetries: 1 },
    });

    await scheduler.runNow("t1"); // → OPEN
    infos.length = 0; // clear registration logs
    await scheduler.runNow("t1"); // should skip
    assert.ok(infos.some((m) => m.includes("circuit breaker OPEN")));
  });
});
