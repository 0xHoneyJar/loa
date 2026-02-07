import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  TimeoutEnforcer,
  createTimeoutEnforcer,
} from "../scheduler/timeout-enforcer.js";

describe("TimeoutEnforcer (T2.4)", () => {
  // ── Factory ─────────────────────────────────────────

  it("createTimeoutEnforcer returns a TimeoutEnforcer", () => {
    const te = createTimeoutEnforcer();
    assert.ok(te instanceof TimeoutEnforcer);
  });

  // ── Basic Execution ─────────────────────────────────

  it("run() executes fn and returns result", async () => {
    const te = createTimeoutEnforcer({ defaultTimeoutMs: 5000 });
    const result = await te.run(async () => 42);
    assert.equal(result, 42);
  });

  it("run() passes AbortSignal to fn", async () => {
    const te = createTimeoutEnforcer();
    let receivedSignal = false;
    await te.run(async (signal) => {
      receivedSignal = signal instanceof AbortSignal;
    });
    assert.equal(receivedSignal, true);
  });

  // ── Timeout ─────────────────────────────────────────

  it("throws SCH_001 when fn exceeds timeout", async () => {
    const te = createTimeoutEnforcer({ defaultTimeoutMs: 50 });

    await assert.rejects(
      () => te.run(async (signal) => {
        return new Promise((_resolve, reject) => {
          const timer = setTimeout(() => {}, 10_000);
          signal.addEventListener("abort", () => {
            clearTimeout(timer);
            reject(new Error("aborted"));
          });
        });
      }),
      (err: Error) => err.message.includes("timed out") && err.message.includes("50ms"),
    );
  });

  // ── Per-call timeout override ───────────────────────

  it("opts.timeoutMs overrides default", async () => {
    const te = createTimeoutEnforcer({ defaultTimeoutMs: 50 });

    // Should succeed with longer per-call timeout
    const result = await te.run(
      async () => {
        await new Promise((r) => setTimeout(r, 30));
        return "ok";
      },
      { timeoutMs: 5000 },
    );
    assert.equal(result, "ok");
  });

  // ── Model-based timeout ─────────────────────────────

  it("getTimeoutMs returns default when no model specified", () => {
    const te = createTimeoutEnforcer({ defaultTimeoutMs: 30_000 });
    assert.equal(te.getTimeoutMs(), 30_000);
  });

  it("getTimeoutMs returns model-specific timeout", () => {
    const te = createTimeoutEnforcer({
      defaultTimeoutMs: 30_000,
      modelTimeouts: { "opus": 120_000, "haiku": 10_000 },
    });
    assert.equal(te.getTimeoutMs("opus"), 120_000);
    assert.equal(te.getTimeoutMs("haiku"), 10_000);
  });

  it("getTimeoutMs returns default for unknown model", () => {
    const te = createTimeoutEnforcer({
      defaultTimeoutMs: 30_000,
      modelTimeouts: { "opus": 120_000 },
    });
    assert.equal(te.getTimeoutMs("sonnet"), 30_000);
  });

  it("run uses model timeout from opts", async () => {
    const te = createTimeoutEnforcer({
      defaultTimeoutMs: 50,
      modelTimeouts: { "opus": 5000 },
    });

    // Should succeed with model timeout (5s) despite short default (50ms)
    const result = await te.run(
      async () => {
        await new Promise((r) => setTimeout(r, 30));
        return "ok";
      },
      { model: "opus" },
    );
    assert.equal(result, "ok");
  });

  // ── Signal Composition ──────────────────────────────

  it("composes with caller-provided signal (external abort)", async () => {
    const te = createTimeoutEnforcer({ defaultTimeoutMs: 5000 });
    const externalAc = new AbortController();

    const promise = te.run(async (signal) => {
      return new Promise((_resolve, reject) => {
        signal.addEventListener("abort", () => {
          reject(new Error("signal aborted"));
        });
      });
    }, { signal: externalAc.signal });

    // Abort externally
    externalAc.abort();

    await assert.rejects(
      () => promise,
      (err: Error) => err.message.includes("signal aborted"),
    );
  });

  it("composes with already-aborted external signal", async () => {
    const te = createTimeoutEnforcer({ defaultTimeoutMs: 5000 });
    const externalAc = new AbortController();
    externalAc.abort(); // Already aborted

    let signalWasAborted = false;
    await te.run(async (signal) => {
      signalWasAborted = signal.aborted;
    }, { signal: externalAc.signal });

    assert.equal(signalWasAborted, true);
  });

  // ── Error Propagation ───────────────────────────────

  it("propagates fn errors unchanged", async () => {
    const te = createTimeoutEnforcer();

    await assert.rejects(
      () => te.run(async () => { throw new Error("boom"); }),
      (err: Error) => err.message === "boom",
    );
  });
});
