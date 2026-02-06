import { describe, it, expect, vi } from "vitest";
import { CircuitBreaker, type CircuitBreakerState } from "../circuit-breaker.js";
import { PersistenceError } from "../types.js";

describe("CircuitBreaker", () => {
  function createCB(
    config?: Partial<{ maxFailures: number; resetTimeMs: number; halfOpenRetries: number }>,
    options?: {
      onStateChange?: (from: CircuitBreakerState, to: CircuitBreakerState) => void;
      now?: () => number;
    },
  ) {
    return new CircuitBreaker(config, options);
  }

  // ── State Transitions ──────────────────────────────────

  it("starts in CLOSED state", () => {
    const cb = createCB();
    expect(cb.getState()).toBe("CLOSED");
  });

  it("transitions CLOSED → OPEN after maxFailures consecutive failures", () => {
    const transitions: Array<[CircuitBreakerState, CircuitBreakerState]> = [];
    const cb = createCB(
      { maxFailures: 3 },
      {
        onStateChange: (from, to) => transitions.push([from, to]),
      },
    );

    cb.recordFailure();
    expect(cb.getState()).toBe("CLOSED");

    cb.recordFailure();
    expect(cb.getState()).toBe("CLOSED");

    cb.recordFailure();
    expect(cb.getState()).toBe("OPEN");
    expect(transitions).toEqual([["CLOSED", "OPEN"]]);
  });

  it("resets failure count on success before reaching threshold", () => {
    const cb = createCB({ maxFailures: 3 });

    cb.recordFailure();
    cb.recordFailure();
    cb.recordSuccess();
    expect(cb.getFailureCount()).toBe(0);

    cb.recordFailure();
    cb.recordFailure();
    expect(cb.getState()).toBe("CLOSED");
  });

  // ── Execute Wrapper ────────────────────────────────────

  it("execute() passes through on CLOSED", async () => {
    const cb = createCB();
    const result = await cb.execute(async () => 42);
    expect(result).toBe(42);
  });

  it("execute() throws CB_OPEN when circuit is open", async () => {
    const cb = createCB({ maxFailures: 1 });
    cb.recordFailure();
    expect(cb.getState()).toBe("OPEN");

    await expect(cb.execute(async () => "nope")).rejects.toThrow(PersistenceError);
    try {
      await cb.execute(async () => "nope");
    } catch (e) {
      expect((e as PersistenceError).code).toBe("CB_OPEN");
    }
  });

  it("execute() records failure on function throw", async () => {
    const cb = createCB({ maxFailures: 2 });

    await expect(
      cb.execute(async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");

    expect(cb.getFailureCount()).toBe(1);
  });

  it("execute() records success on function resolve", async () => {
    const cb = createCB();
    cb.recordFailure();
    expect(cb.getFailureCount()).toBe(1);

    await cb.execute(async () => "ok");
    expect(cb.getFailureCount()).toBe(0);
  });

  // ── Timeout Recovery (OPEN → HALF_OPEN) ────────────────

  it("transitions OPEN → HALF_OPEN after resetTimeMs elapses", () => {
    let clock = 0;
    const transitions: Array<[CircuitBreakerState, CircuitBreakerState]> = [];

    const cb = createCB(
      { maxFailures: 1, resetTimeMs: 1000 },
      {
        now: () => clock,
        onStateChange: (from, to) => transitions.push([from, to]),
      },
    );

    cb.recordFailure();
    expect(cb.getState()).toBe("OPEN");

    clock = 500;
    expect(cb.getState()).toBe("OPEN");

    clock = 1000;
    expect(cb.getState()).toBe("HALF_OPEN");
    expect(transitions).toEqual([
      ["CLOSED", "OPEN"],
      ["OPEN", "HALF_OPEN"],
    ]);
  });

  // ── Half-Open Probe ────────────────────────────────────

  it("transitions HALF_OPEN → CLOSED after halfOpenRetries successes", () => {
    let clock = 0;
    const cb = createCB(
      { maxFailures: 1, resetTimeMs: 100, halfOpenRetries: 2 },
      {
        now: () => clock,
      },
    );

    cb.recordFailure();
    expect(cb.getState()).toBe("OPEN");

    clock = 100;
    expect(cb.getState()).toBe("HALF_OPEN");

    cb.recordSuccess();
    expect(cb.getState()).toBe("HALF_OPEN");

    cb.recordSuccess();
    expect(cb.getState()).toBe("CLOSED");
    expect(cb.getFailureCount()).toBe(0);
  });

  it("transitions HALF_OPEN → OPEN on failure during probe", () => {
    let clock = 0;
    const transitions: Array<[CircuitBreakerState, CircuitBreakerState]> = [];

    const cb = createCB(
      { maxFailures: 1, resetTimeMs: 100 },
      {
        now: () => clock,
        onStateChange: (from, to) => transitions.push([from, to]),
      },
    );

    cb.recordFailure();
    clock = 100;
    cb.getState(); // trigger HALF_OPEN

    cb.recordFailure();
    expect(cb.getState()).toBe("OPEN");

    const lastTransition = transitions[transitions.length - 1];
    expect(lastTransition).toEqual(["HALF_OPEN", "OPEN"]);
  });

  // ── Reset ──────────────────────────────────────────────

  it("reset() forces CLOSED regardless of current state", () => {
    const cb = createCB({ maxFailures: 1 });
    cb.recordFailure();
    expect(cb.getState()).toBe("OPEN");

    cb.reset();
    expect(cb.getState()).toBe("CLOSED");
    expect(cb.getFailureCount()).toBe(0);
  });
});
