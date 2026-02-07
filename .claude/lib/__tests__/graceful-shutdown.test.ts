import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  GracefulShutdown,
  createGracefulShutdown,
} from "../sync/graceful-shutdown.js";

describe("GracefulShutdown (T3.6)", () => {
  it("createGracefulShutdown returns instance", () => {
    const gs = createGracefulShutdown();
    assert.ok(gs instanceof GracefulShutdown);
  });

  it("runs drain → sync → exit(0) sequence", async () => {
    const order: string[] = [];
    let exitCode = -1;
    const gs = createGracefulShutdown({
      onDrain: async () => { order.push("drain"); },
      onSync: async () => { order.push("sync"); },
      exit: (code) => { exitCode = code; order.push("exit"); },
    });
    await gs.shutdown();
    assert.deepEqual(order, ["drain", "sync", "exit"]);
    assert.equal(exitCode, 0);
  });

  it("exits with 0 when no callbacks", async () => {
    let exitCode = -1;
    const gs = createGracefulShutdown({
      exit: (code) => { exitCode = code; },
    });
    await gs.shutdown();
    assert.equal(exitCode, 0);
  });

  it("exits with 1 on drain error", async () => {
    let exitCode = -1;
    const logs: string[] = [];
    const gs = createGracefulShutdown({
      onDrain: async () => { throw new Error("drain failed"); },
      exit: (code) => { exitCode = code; },
      log: (msg) => { logs.push(msg); },
    });
    await gs.shutdown();
    assert.equal(exitCode, 1);
    assert.ok(logs.some((l) => l.includes("drain failed")));
  });

  it("exits with 1 on sync error", async () => {
    let exitCode = -1;
    const gs = createGracefulShutdown({
      onDrain: async () => {},
      onSync: async () => { throw new Error("sync failed"); },
      exit: (code) => { exitCode = code; },
      log: () => {},
    });
    await gs.shutdown();
    assert.equal(exitCode, 1);
  });

  it("drain timeout triggers exit(1)", async () => {
    let exitCode = -1;
    const gs = createGracefulShutdown({
      drainTimeoutMs: 50,
      onDrain: () => new Promise(() => {}), // never resolves
      exit: (code) => { exitCode = code; },
      log: () => {},
    });
    await gs.shutdown();
    assert.equal(exitCode, 1);
  });

  it("idempotent — second call is no-op", async () => {
    let callCount = 0;
    const gs = createGracefulShutdown({
      exit: () => { callCount++; },
    });
    await gs.shutdown();
    await gs.shutdown();
    assert.equal(callCount, 1);
  });

  it("isShuttingDown returns correct state", async () => {
    const gs = createGracefulShutdown({
      exit: () => {},
    });
    assert.equal(gs.isShuttingDown(), false);
    await gs.shutdown();
    assert.equal(gs.isShuttingDown(), true);
  });

  it("register does not throw", () => {
    const gs = createGracefulShutdown({
      exit: () => {},
    });
    // Just verify register doesn't throw
    gs.register();
  });
});
