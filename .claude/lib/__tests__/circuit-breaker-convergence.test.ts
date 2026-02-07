/**
 * T3.8b — Circuit Breaker Convergence Enhancement tests.
 *
 * Tests for taskId tracking and probe counter added for finn convergence.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { CircuitBreaker } from "../persistence/circuit-breaker.js";

describe("CircuitBreaker Convergence (T3.8b)", () => {
  // ── taskId ────────────────────────────────────────

  it("getTaskId() returns undefined when not configured", () => {
    const cb = new CircuitBreaker();
    assert.equal(cb.getTaskId(), undefined);
  });

  it("getTaskId() returns configured taskId", () => {
    const cb = new CircuitBreaker({ taskId: "task-42" });
    assert.equal(cb.getTaskId(), "task-42");
  });

  // ── probeCount ────────────────────────────────────

  it("getProbeCount() returns 0 initially", () => {
    const cb = new CircuitBreaker();
    assert.equal(cb.getProbeCount(), 0);
  });

  it("probeCount not incremented when enableProbeCounter is false", async () => {
    let clock = 0;
    const cb = new CircuitBreaker(
      { maxFailures: 1, resetTimeMs: 100 },
      { now: () => clock },
    );

    cb.recordFailure();
    clock = 100;
    assert.equal(cb.getState(), "HALF_OPEN");

    await cb.execute(async () => "ok");
    assert.equal(cb.getProbeCount(), 0);
  });

  it("probeCount incremented on HALF_OPEN execute when enabled", async () => {
    let clock = 0;
    const cb = new CircuitBreaker(
      { maxFailures: 1, resetTimeMs: 100, halfOpenRetries: 3, enableProbeCounter: true },
      { now: () => clock },
    );

    cb.recordFailure();
    clock = 100;
    assert.equal(cb.getState(), "HALF_OPEN");

    await cb.execute(async () => "probe1");
    assert.equal(cb.getProbeCount(), 1);

    await cb.execute(async () => "probe2");
    assert.equal(cb.getProbeCount(), 2);
  });

  it("probeCount not incremented on CLOSED execute", async () => {
    const cb = new CircuitBreaker(
      { enableProbeCounter: true },
    );
    await cb.execute(async () => "ok");
    assert.equal(cb.getProbeCount(), 0);
  });

  it("taskId and probeCounter work together", async () => {
    let clock = 0;
    const cb = new CircuitBreaker(
      { maxFailures: 1, resetTimeMs: 50, taskId: "sync-job", enableProbeCounter: true },
      { now: () => clock },
    );

    assert.equal(cb.getTaskId(), "sync-job");

    cb.recordFailure();
    clock = 50;

    await cb.execute(async () => "probe");
    assert.equal(cb.getProbeCount(), 1);
    assert.equal(cb.getState(), "CLOSED");
  });
});
