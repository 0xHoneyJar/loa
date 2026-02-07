/**
 * T3.8a — Circuit Breaker Golden Tests.
 *
 * Captures current observable behavior of CircuitBreaker BEFORE modification.
 * Only uses public API: execute, recordSuccess, recordFailure, getState,
 * reset, getFailureCount. No internal field assertions.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { CircuitBreaker, type CircuitBreakerState } from "../persistence/circuit-breaker.js";
import { PersistenceError } from "../persistence/types.js";

function createCB(
  config?: Partial<{ maxFailures: number; resetTimeMs: number; halfOpenRetries: number }>,
  options?: {
    onStateChange?: (from: CircuitBreakerState, to: CircuitBreakerState) => void;
    now?: () => number;
  },
) {
  return new CircuitBreaker(config, options);
}

describe("CircuitBreaker Golden Tests (T3.8a)", () => {
  // ── Initial State ─────────────────────────────────

  it("starts in CLOSED state", () => {
    assert.equal(createCB().getState(), "CLOSED");
  });

  it("initial failure count is 0", () => {
    assert.equal(createCB().getFailureCount(), 0);
  });

  // ── CLOSED → OPEN ────────────────────────────────

  it("CLOSED → OPEN after N consecutive failures", () => {
    const transitions: [string, string][] = [];
    const cb = createCB(
      { maxFailures: 3 },
      { onStateChange: (f, t) => transitions.push([f, t]) },
    );

    cb.recordFailure();
    assert.equal(cb.getState(), "CLOSED");
    cb.recordFailure();
    assert.equal(cb.getState(), "CLOSED");
    cb.recordFailure();
    assert.equal(cb.getState(), "OPEN");
    assert.deepEqual(transitions, [["CLOSED", "OPEN"]]);
  });

  it("success resets failure count before threshold", () => {
    const cb = createCB({ maxFailures: 3 });
    cb.recordFailure();
    cb.recordFailure();
    cb.recordSuccess();
    assert.equal(cb.getFailureCount(), 0);
    cb.recordFailure();
    cb.recordFailure();
    assert.equal(cb.getState(), "CLOSED");
  });

  // ── OPEN → HALF_OPEN (injectable clock) ───────────

  it("OPEN → HALF_OPEN after resetTimeMs elapses", () => {
    let clock = 0;
    const transitions: [string, string][] = [];
    const cb = createCB(
      { maxFailures: 1, resetTimeMs: 1000 },
      { now: () => clock, onStateChange: (f, t) => transitions.push([f, t]) },
    );

    cb.recordFailure();
    assert.equal(cb.getState(), "OPEN");

    clock = 500;
    assert.equal(cb.getState(), "OPEN");

    clock = 1000;
    assert.equal(cb.getState(), "HALF_OPEN");
    assert.deepEqual(transitions, [
      ["CLOSED", "OPEN"],
      ["OPEN", "HALF_OPEN"],
    ]);
  });

  // ── HALF_OPEN → CLOSED ───────────────────────────

  it("HALF_OPEN → CLOSED after halfOpenRetries successes", () => {
    let clock = 0;
    const cb = createCB(
      { maxFailures: 1, resetTimeMs: 100, halfOpenRetries: 2 },
      { now: () => clock },
    );

    cb.recordFailure();
    clock = 100;
    assert.equal(cb.getState(), "HALF_OPEN");

    cb.recordSuccess();
    assert.equal(cb.getState(), "HALF_OPEN");

    cb.recordSuccess();
    assert.equal(cb.getState(), "CLOSED");
    assert.equal(cb.getFailureCount(), 0);
  });

  // ── HALF_OPEN → OPEN on failure ──────────────────

  it("HALF_OPEN → OPEN on probe failure", () => {
    let clock = 0;
    const cb = createCB(
      { maxFailures: 1, resetTimeMs: 100 },
      { now: () => clock },
    );

    cb.recordFailure();
    clock = 100;
    cb.getState(); // trigger HALF_OPEN

    cb.recordFailure();
    assert.equal(cb.getState(), "OPEN");
  });

  // ── execute() ─────────────────────────────────────

  it("execute() passes through on CLOSED", async () => {
    const cb = createCB();
    const result = await cb.execute(async () => 42);
    assert.equal(result, 42);
  });

  it("execute() throws CB_OPEN when circuit is open", async () => {
    const cb = createCB({ maxFailures: 1 });
    cb.recordFailure();
    await assert.rejects(
      () => cb.execute(async () => "nope"),
      (err: PersistenceError) => err.code === "CB_OPEN",
    );
  });

  it("execute() records failure on throw", async () => {
    const cb = createCB({ maxFailures: 3 });
    await assert.rejects(() => cb.execute(async () => { throw new Error("boom"); }));
    assert.equal(cb.getFailureCount(), 1);
  });

  it("execute() records success on resolve", async () => {
    const cb = createCB();
    cb.recordFailure();
    assert.equal(cb.getFailureCount(), 1);
    await cb.execute(async () => "ok");
    assert.equal(cb.getFailureCount(), 0);
  });

  // ── reset() ───────────────────────────────────────

  it("reset() forces CLOSED from OPEN", () => {
    const cb = createCB({ maxFailures: 1 });
    cb.recordFailure();
    assert.equal(cb.getState(), "OPEN");
    cb.reset();
    assert.equal(cb.getState(), "CLOSED");
    assert.equal(cb.getFailureCount(), 0);
  });

  // ── getFailureCount() ─────────────────────────────

  it("getFailureCount() tracks consecutive failures", () => {
    const cb = createCB({ maxFailures: 10 });
    cb.recordFailure();
    assert.equal(cb.getFailureCount(), 1);
    cb.recordFailure();
    assert.equal(cb.getFailureCount(), 2);
    cb.recordSuccess();
    assert.equal(cb.getFailureCount(), 0);
  });
});
