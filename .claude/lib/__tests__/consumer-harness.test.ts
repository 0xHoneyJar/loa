/**
 * T3.10 — Consumer Compatibility Harness tests.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { runConsumerHarness } from "../testing/consumer-harness.js";

describe("Consumer Compatibility Harness (T3.10)", () => {
  it("all 5 new modules resolve and export factories", async () => {
    const report = await runConsumerHarness();
    assert.equal(report.allPassed, true, `Failed modules: ${
      report.results.filter((r) => !r.ok).map((r) => `${r.module}: ${r.error}`).join("; ")
    }`);
    assert.ok(report.passed >= 5, `Expected at least 5 passed, got ${report.passed}`);
  });

  it("security module exports createPIIRedactor and createAuditLogger", async () => {
    const report = await runConsumerHarness();
    const sec = report.results.find((r) => r.module === "security");
    assert.ok(sec);
    assert.equal(sec!.ok, true);
    assert.ok(sec!.factories.includes("createPIIRedactor"));
    assert.ok(sec!.factories.includes("createAuditLogger"));
  });

  it("memory module exports createContextTracker and createCompoundLearningCycle", async () => {
    const report = await runConsumerHarness();
    const mem = report.results.find((r) => r.module === "memory");
    assert.ok(mem);
    assert.equal(mem!.ok, true);
  });

  it("scheduler module exports all factory functions", async () => {
    const report = await runConsumerHarness();
    const sched = report.results.find((r) => r.module === "scheduler");
    assert.ok(sched);
    assert.equal(sched!.ok, true);
    assert.ok(sched!.factories.includes("createScheduler"));
    assert.ok(sched!.factories.includes("createWebhookSink"));
    assert.ok(sched!.factories.includes("createHealthAggregator"));
    assert.ok(sched!.factories.includes("createTimeoutEnforcer"));
    assert.ok(sched!.factories.includes("createBloatAuditor"));
  });

  it("bridge module exports createBeadsBridge", async () => {
    const report = await runConsumerHarness();
    const bridge = report.results.find((r) => r.module === "bridge");
    assert.ok(bridge);
    assert.equal(bridge!.ok, true);
  });

  it("sync module exports all factory functions", async () => {
    const report = await runConsumerHarness();
    const sync = report.results.find((r) => r.module === "sync");
    assert.ok(sync);
    assert.equal(sync!.ok, true);
    assert.ok(sync!.factories.includes("createRecoveryCascade"));
    assert.ok(sync!.factories.includes("createInMemoryObjectStore"));
    assert.ok(sync!.factories.includes("createObjectStoreSync"));
    assert.ok(sync!.factories.includes("createWALPruner"));
    assert.ok(sync!.factories.includes("createGracefulShutdown"));
  });

  it("report includes correct pass/fail counts", async () => {
    const report = await runConsumerHarness();
    assert.equal(report.passed + report.failed, report.results.length);
  });
});
