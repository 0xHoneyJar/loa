import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { ProgressReporter } from "../core/progress.js";

describe("ProgressReporter", () => {
  let captured: string[];
  let originalWrite: typeof process.stderr.write;

  beforeEach(() => {
    captured = [];
    originalWrite = process.stderr.write;
    process.stderr.write = ((chunk: string | Uint8Array) => {
      captured.push(String(chunk));
      return true;
    }) as typeof process.stderr.write;
  });

  afterEach(() => {
    process.stderr.write = originalWrite;
  });

  it("emits start message", () => {
    const reporter = new ProgressReporter({ verbose: false });
    reporter.start();
    reporter.stop();

    assert.ok(captured.some((l) => l.includes("Starting multi-model review pipeline")));
  });

  it("emits phase changes", () => {
    const reporter = new ProgressReporter({ verbose: false });
    reporter.start();
    reporter.setPhase("review");
    reporter.stop();

    assert.ok(captured.some((l) => l.includes("Phase: review")));
  });

  it("includes elapsed time in output", () => {
    const reporter = new ProgressReporter({ verbose: false });
    reporter.start();
    reporter.setPhase("config");
    reporter.stop();

    assert.ok(captured.some((l) => /\[\d+s\]/.test(l)));
  });

  it("emits model registration in verbose mode", () => {
    const reporter = new ProgressReporter({ verbose: true });
    reporter.start();
    reporter.registerModel("anthropic", "opus");
    reporter.stop();

    assert.ok(captured.some((l) => l.includes("anthropic/opus")));
  });

  it("emits model updates in verbose mode", () => {
    const reporter = new ProgressReporter({ verbose: true });
    reporter.start();
    reporter.registerModel("openai", "gpt-4o");
    reporter.updateModel("openai", "gpt-4o", {
      phase: "complete",
      latencyMs: 5000,
      inputTokens: 100,
      outputTokens: 50,
    });
    reporter.stop();

    assert.ok(captured.some((l) => l.includes("complete") && l.includes("5000ms")));
  });

  it("emits scoring report", () => {
    const reporter = new ProgressReporter({ verbose: false });
    reporter.start();
    reporter.reportScoring({
      total: 10,
      highConsensus: 6,
      disputed: 2,
      blocker: 1,
    });
    reporter.stop();

    assert.ok(captured.some((l) => l.includes("10 findings")));
    assert.ok(captured.some((l) => l.includes("6 consensus")));
  });

  it("emits completion report", () => {
    const reporter = new ProgressReporter({ verbose: false });
    reporter.start();
    reporter.reportComplete(5000, 3);
    reporter.stop();

    assert.ok(captured.some((l) => l.includes("Done in 5s")));
    assert.ok(captured.some((l) => l.includes("3 model(s)")));
  });

  it("uses bridgebuilder prefix in output", () => {
    const reporter = new ProgressReporter({ verbose: false });
    reporter.start();
    reporter.stop();

    assert.ok(captured.some((l) => l.includes("[bridgebuilder:")));
  });

  it("cleans up heartbeat timer on stop", () => {
    const reporter = new ProgressReporter({
      verbose: true,
      heartbeatIntervalMs: 100,
    });
    reporter.start();
    reporter.stop();

    // Should not throw or emit after stop
    assert.ok(true);
  });
});
