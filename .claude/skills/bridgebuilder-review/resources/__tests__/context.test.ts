import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { BridgebuilderContext } from "../core/context.js";
import type { IContextStore } from "../ports/context-store.js";
import type { ReviewItem, ReviewResult } from "../core/types.js";

function mockStore(overrides?: Partial<IContextStore>): IContextStore {
  return {
    load: async () => {},
    getLastHash: async () => null,
    setLastHash: async () => {},
    claimReview: async () => true,
    finalizeReview: async () => {},
    getLastReviewedSha: async () => null,
    setLastReviewedSha: async () => {},
    ...overrides,
  };
}

function mockItem(hash = "abc123"): ReviewItem {
  return {
    owner: "test",
    repo: "repo",
    pr: {
      number: 1,
      title: "PR",
      headSha: "sha1",
      baseBranch: "main",
      labels: [],
      author: "dev",
    },
    files: [],
    hash,
  };
}

function mockResult(item: ReviewItem): ReviewResult {
  return { item, posted: true, skipped: false };
}

describe("BridgebuilderContext", () => {
  describe("load", () => {
    it("delegates to store.load()", async () => {
      let called = false;
      const store = mockStore({ load: async () => { called = true; } });
      const ctx = new BridgebuilderContext(store);

      await ctx.load();
      assert.ok(called);
    });
  });

  describe("hasChanged", () => {
    it("returns true when no stored hash (NoOp / first time)", async () => {
      const store = mockStore({ getLastHash: async () => null });
      const ctx = new BridgebuilderContext(store);

      assert.equal(await ctx.hasChanged(mockItem()), true);
    });

    it("returns false when stored hash matches item hash", async () => {
      const store = mockStore({ getLastHash: async () => "abc123" });
      const ctx = new BridgebuilderContext(store);

      assert.equal(await ctx.hasChanged(mockItem("abc123")), false);
    });

    it("returns true when stored hash differs from item hash", async () => {
      const store = mockStore({ getLastHash: async () => "old-hash" });
      const ctx = new BridgebuilderContext(store);

      assert.equal(await ctx.hasChanged(mockItem("new-hash")), true);
    });

    it("passes correct owner/repo/prNumber to store", async () => {
      let capturedArgs: unknown[] = [];
      const store = mockStore({
        getLastHash: async (...args: unknown[]) => {
          capturedArgs = args;
          return null;
        },
      });
      const ctx = new BridgebuilderContext(store);
      const item = mockItem();

      await ctx.hasChanged(item);

      assert.equal(capturedArgs[0], "test");
      assert.equal(capturedArgs[1], "repo");
      assert.equal(capturedArgs[2], 1);
    });
  });

  describe("claimReview", () => {
    it("delegates to store and returns result", async () => {
      const store = mockStore({ claimReview: async () => false });
      const ctx = new BridgebuilderContext(store);

      assert.equal(await ctx.claimReview(mockItem()), false);
    });
  });

  describe("finalizeReview", () => {
    it("calls setLastHash, setLastReviewedSha, then finalizeReview on store", async () => {
      const callOrder: string[] = [];
      const store = mockStore({
        setLastHash: async () => { callOrder.push("setLastHash"); },
        setLastReviewedSha: async () => { callOrder.push("setLastReviewedSha"); },
        finalizeReview: async () => { callOrder.push("finalizeReview"); },
      });
      const ctx = new BridgebuilderContext(store);
      const item = mockItem("hash-value");
      const result = mockResult(item);

      await ctx.finalizeReview(item, result);

      assert.deepEqual(callOrder, ["setLastHash", "setLastReviewedSha", "finalizeReview"]);
    });

    it("passes item hash to setLastHash", async () => {
      let storedHash: string | undefined;
      const store = mockStore({
        setLastHash: async (_o, _r, _p, hash) => { storedHash = hash; },
      });
      const ctx = new BridgebuilderContext(store);
      const item = mockItem("my-hash");

      await ctx.finalizeReview(item, mockResult(item));

      assert.equal(storedHash, "my-hash");
    });
  });
});
