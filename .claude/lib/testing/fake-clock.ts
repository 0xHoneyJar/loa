/**
 * Deterministic fake clock for testing time-dependent code.
 * Satisfies the `{ now(): number }` interface used by all injectable clocks.
 */
export interface FakeClock {
  now(): number;
  advanceBy(ms: number): void;
  set(ms: number): void;
}

export function createFakeClock(startMs: number = 0): FakeClock {
  let current = startMs;

  return {
    now: () => current,
    advanceBy(ms: number) {
      if (ms < 0) throw new RangeError("advanceBy requires non-negative ms");
      current += ms;
    },
    set(ms: number) {
      current = ms;
    },
  };
}
