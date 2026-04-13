import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import { readRatingWithTimeout } from "../core/rating.js";

/**
 * Regression tests for bug-20260413-i464-9d4f51 / Issue #464 A1:
 *
 * Multi-model pipeline displayed the rating prompt but never read stdin,
 * leaving FR-5 unimplemented. readRatingWithTimeout() wires a non-blocking
 * readline reader with a configurable timeout so a valid 1-5 input is
 * captured and invalid/no input is tolerated gracefully.
 */
describe("readRatingWithTimeout", () => {
  it("captures a valid rating (1-5) from stdin", async () => {
    const input = new PassThrough();
    const output = new PassThrough();

    const pending = readRatingWithTimeout({
      input,
      output,
      timeoutMs: 5000,
    });

    // Simulate user entering "4" and pressing Enter
    input.write("4\n");

    const result = await pending;
    assert.equal(result.score, 4);
    assert.equal(result.timedOut, false);
  });

  it("returns { score: null, timedOut: true } when timeout elapses", async () => {
    const input = new PassThrough();
    const output = new PassThrough();

    // No input written — timeout should fire
    const result = await readRatingWithTimeout({
      input,
      output,
      timeoutMs: 50,
    });

    assert.equal(result.score, null);
    assert.equal(result.timedOut, true);
  });

  it("returns { score: null } when user presses Enter without input (skip)", async () => {
    const input = new PassThrough();
    const output = new PassThrough();

    const pending = readRatingWithTimeout({
      input,
      output,
      timeoutMs: 5000,
    });

    input.write("\n");

    const result = await pending;
    assert.equal(result.score, null);
    assert.equal(result.timedOut, false);
  });

  it("returns { score: null } for invalid input (non-numeric)", async () => {
    const input = new PassThrough();
    const output = new PassThrough();

    const pending = readRatingWithTimeout({
      input,
      output,
      timeoutMs: 5000,
    });

    input.write("abc\n");

    const result = await pending;
    assert.equal(result.score, null);
    assert.equal(result.timedOut, false);
  });

  it("returns { score: null } for out-of-range input (6)", async () => {
    const input = new PassThrough();
    const output = new PassThrough();

    const pending = readRatingWithTimeout({
      input,
      output,
      timeoutMs: 5000,
    });

    input.write("6\n");

    const result = await pending;
    assert.equal(result.score, null);
    assert.equal(result.timedOut, false);
  });
});
