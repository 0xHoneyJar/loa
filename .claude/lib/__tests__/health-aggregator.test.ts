import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  HealthAggregator,
  createHealthAggregator,
  type IHealthReporter,
  type HealthState,
} from "../scheduler/health-aggregator.js";

function mockReporter(name: string, state: HealthState, message?: string): IHealthReporter {
  return { name, check: () => ({ name, state, message }) };
}

function throwingReporter(name: string, errorMsg: string): IHealthReporter {
  return {
    name,
    check: () => { throw new Error(errorMsg); },
  };
}

describe("HealthAggregator (T2.3)", () => {
  // ── Factory ─────────────────────────────────────────

  it("createHealthAggregator returns a HealthAggregator", () => {
    const agg = createHealthAggregator();
    assert.ok(agg instanceof HealthAggregator);
  });

  // ── All Healthy ─────────────────────────────────────

  it("overall healthy when all subsystems healthy", async () => {
    const agg = createHealthAggregator();
    agg.addReporter(mockReporter("db", "healthy"));
    agg.addReporter(mockReporter("cache", "healthy"));

    const report = await agg.check();
    assert.equal(report.overall, "healthy");
    assert.equal(report.subsystems.length, 2);
  });

  // ── Degraded ────────────────────────────────────────

  it("overall degraded when any subsystem is degraded", async () => {
    const agg = createHealthAggregator();
    agg.addReporter(mockReporter("db", "healthy"));
    agg.addReporter(mockReporter("cache", "degraded", "high latency"));

    const report = await agg.check();
    assert.equal(report.overall, "degraded");
  });

  // ── Unhealthy ───────────────────────────────────────

  it("overall unhealthy when any subsystem is unhealthy", async () => {
    const agg = createHealthAggregator();
    agg.addReporter(mockReporter("db", "unhealthy", "connection refused"));
    agg.addReporter(mockReporter("cache", "healthy"));

    const report = await agg.check();
    assert.equal(report.overall, "unhealthy");
  });

  it("unhealthy takes precedence over degraded", async () => {
    const agg = createHealthAggregator();
    agg.addReporter(mockReporter("db", "unhealthy"));
    agg.addReporter(mockReporter("cache", "degraded"));
    agg.addReporter(mockReporter("api", "healthy"));

    const report = await agg.check();
    assert.equal(report.overall, "unhealthy");
  });

  // ── Empty ───────────────────────────────────────────

  it("overall healthy when no reporters registered", async () => {
    const agg = createHealthAggregator();
    const report = await agg.check();
    assert.equal(report.overall, "healthy");
    assert.equal(report.subsystems.length, 0);
  });

  // ── Throwing Reporter ───────────────────────────────

  it("treats throwing reporter as unhealthy", async () => {
    const agg = createHealthAggregator();
    agg.addReporter(mockReporter("db", "healthy"));
    agg.addReporter(throwingReporter("cache", "connection failed"));

    const report = await agg.check();
    assert.equal(report.overall, "unhealthy");
    const cacheSub = report.subsystems.find((s) => s.name === "cache");
    assert.equal(cacheSub?.state, "unhealthy");
    assert.equal(cacheSub?.message, "connection failed");
  });

  // ── Async Reporter ──────────────────────────────────

  it("supports async reporters", async () => {
    const agg = createHealthAggregator();
    agg.addReporter({
      name: "async-db",
      check: async () => {
        await new Promise((r) => setTimeout(r, 5));
        return { name: "async-db", state: "healthy" as HealthState };
      },
    });

    const report = await agg.check();
    assert.equal(report.overall, "healthy");
    assert.equal(report.subsystems[0].name, "async-db");
  });

  // ── Subsystem Details ───────────────────────────────

  it("returns individual subsystem details", async () => {
    const agg = createHealthAggregator();
    agg.addReporter(mockReporter("db", "healthy"));
    agg.addReporter(mockReporter("cache", "degraded", "slow response"));

    const report = await agg.check();
    const db = report.subsystems.find((s) => s.name === "db");
    const cache = report.subsystems.find((s) => s.name === "cache");

    assert.equal(db?.state, "healthy");
    assert.equal(cache?.state, "degraded");
    assert.equal(cache?.message, "slow response");
  });
});
