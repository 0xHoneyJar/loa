import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createFakeClock } from "../testing/fake-clock.js";

describe("createFakeClock", () => {
  it("starts at 0 by default", () => {
    const clock = createFakeClock();
    assert.equal(clock.now(), 0);
  });

  it("starts at provided time", () => {
    const clock = createFakeClock(1000);
    assert.equal(clock.now(), 1000);
  });

  it("advanceBy increments deterministically", () => {
    const clock = createFakeClock(100);
    clock.advanceBy(50);
    assert.equal(clock.now(), 150);
    clock.advanceBy(25);
    assert.equal(clock.now(), 175);
  });

  it("set overrides current time", () => {
    const clock = createFakeClock(100);
    clock.set(9999);
    assert.equal(clock.now(), 9999);
  });

  it("advanceBy rejects negative values", () => {
    const clock = createFakeClock();
    assert.throws(() => clock.advanceBy(-1), RangeError);
  });

  it("satisfies { now(): number } interface", () => {
    const clock = createFakeClock(42);
    const injectable: { now(): number } = clock;
    assert.equal(injectable.now(), 42);
  });
});
