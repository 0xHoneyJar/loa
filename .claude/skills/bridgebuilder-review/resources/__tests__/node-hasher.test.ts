import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { NodeHasher } from "../adapters/node-hasher.js";

describe("NodeHasher", () => {
  const hasher = new NodeHasher();

  it("produces correct SHA-256 for empty string", async () => {
    const result = await hasher.sha256("");
    assert.equal(
      result,
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    );
  });

  it("produces correct SHA-256 for known input", async () => {
    const result = await hasher.sha256("hello");
    assert.equal(
      result,
      "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
    );
  });

  it("produces consistent hashes", async () => {
    const a = await hasher.sha256("test-input");
    const b = await hasher.sha256("test-input");
    assert.equal(a, b);
  });

  it("produces different hashes for different inputs", async () => {
    const a = await hasher.sha256("input-a");
    const b = await hasher.sha256("input-b");
    assert.notEqual(a, b);
  });

  it("returns lowercase hex string of 64 characters", async () => {
    const result = await hasher.sha256("any-input");
    assert.equal(result.length, 64);
    assert.match(result, /^[0-9a-f]{64}$/);
  });
});
