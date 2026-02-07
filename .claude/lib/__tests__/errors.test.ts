import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { LoaLibError } from "../errors.js";

describe("LoaLibError", () => {
  it("extends Error with required fields", () => {
    const err = new LoaLibError("test message", "SEC_001", false);
    assert.ok(err instanceof Error);
    assert.ok(err instanceof LoaLibError);
    assert.equal(err.message, "test message");
    assert.equal(err.code, "SEC_001");
    assert.equal(err.retryable, false);
    assert.equal(err.cause, undefined);
  });

  it("sets name to LoaLibError", () => {
    const err = new LoaLibError("msg", "BRG_002", true);
    assert.equal(err.name, "LoaLibError");
  });

  it("preserves cause chain", () => {
    const cause = new Error("root cause");
    const err = new LoaLibError("wrapper", "SYN_001", true, cause);
    assert.equal(err.cause, cause);
    assert.equal(err.cause.message, "root cause");
  });

  it("serializes cleanly to JSON (no circular refs)", () => {
    const cause = new Error("inner");
    const err = new LoaLibError("outer", "MEM_001", false, cause);
    const json = JSON.stringify(err.toJSON());
    const parsed = JSON.parse(json);

    assert.equal(parsed.name, "LoaLibError");
    assert.equal(parsed.message, "outer");
    assert.equal(parsed.code, "MEM_001");
    assert.equal(parsed.retryable, false);
    assert.deepEqual(parsed.cause, { name: "Error", message: "inner" });
  });

  it("serializes without cause when none provided", () => {
    const err = new LoaLibError("solo", "SCH_001", true);
    const parsed = JSON.parse(JSON.stringify(err.toJSON()));
    assert.equal(parsed.cause, undefined);
  });

  it("supports retryable flag for different error codes", () => {
    const retryable = new LoaLibError("timeout", "BRG_002", true);
    const notRetryable = new LoaLibError("not found", "BRG_001", false);
    assert.equal(retryable.retryable, true);
    assert.equal(notRetryable.retryable, false);
  });
});
