import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  BloatAuditor,
  createBloatAuditor,
  type FileSystemScanner,
} from "../scheduler/bloat-auditor.js";

function mockScanner(counts: Record<string, number>): FileSystemScanner {
  return {
    countFiles: (path: string) => counts[path] ?? 0,
  };
}

describe("BloatAuditor (T2.6)", () => {
  // ── Factory ─────────────────────────────────────────

  it("createBloatAuditor returns a BloatAuditor", () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({}),
      paths: {},
    });
    assert.ok(auditor instanceof BloatAuditor);
  });

  // ── Clean Report ────────────────────────────────────

  it("returns clean report when all counts below thresholds", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({
        "/etc/cron.d": 5,
        "/var/state": 10,
        "/usr/scripts": 20,
      }),
      paths: {
        crons: "/etc/cron.d",
        state: "/var/state",
        scripts: "/usr/scripts",
      },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, true);
    assert.equal(report.warnings.length, 0);
  });

  it("returns clean when no paths configured", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({}),
      paths: {},
    });

    const report = await auditor.audit();
    assert.equal(report.clean, true);
  });

  // ── Excessive Crons ─────────────────────────────────

  it("warns on excessive crons", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({ "/crons": 25 }),
      paths: { crons: "/crons" },
      thresholds: { maxCrons: 20 },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, false);
    assert.equal(report.warnings.length, 1);
    assert.equal(report.warnings[0].type, "excessive_crons");
    assert.equal(report.warnings[0].count, 25);
    assert.equal(report.warnings[0].threshold, 20);
  });

  // ── Orphan State Files ──────────────────────────────

  it("warns on orphan state files", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({ "/state": 60 }),
      paths: { state: "/state" },
      thresholds: { maxStateFiles: 50 },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, false);
    assert.equal(report.warnings.length, 1);
    assert.equal(report.warnings[0].type, "orphan_state");
    assert.equal(report.warnings[0].count, 60);
  });

  // ── Script Proliferation ────────────────────────────

  it("warns on script proliferation", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({ "/scripts": 150 }),
      paths: { scripts: "/scripts" },
      thresholds: { maxScripts: 100 },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, false);
    assert.equal(report.warnings.length, 1);
    assert.equal(report.warnings[0].type, "script_proliferation");
  });

  // ── Multiple Warnings ──────────────────────────────

  it("reports multiple warnings at once", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({
        "/crons": 30,
        "/state": 80,
        "/scripts": 200,
      }),
      paths: {
        crons: "/crons",
        state: "/state",
        scripts: "/scripts",
      },
      thresholds: { maxCrons: 20, maxStateFiles: 50, maxScripts: 100 },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, false);
    assert.equal(report.warnings.length, 3);
    const types = report.warnings.map((w) => w.type).sort();
    assert.deepEqual(types, ["excessive_crons", "orphan_state", "script_proliferation"]);
  });

  // ── Default Thresholds ──────────────────────────────

  it("uses default thresholds (20, 50, 100)", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({
        "/crons": 21,
        "/state": 51,
        "/scripts": 101,
      }),
      paths: {
        crons: "/crons",
        state: "/state",
        scripts: "/scripts",
      },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, false);
    assert.equal(report.warnings.length, 3);
  });

  // ── At Threshold (boundary) ─────────────────────────

  it("does not warn when count equals threshold", async () => {
    const auditor = createBloatAuditor({
      scanner: mockScanner({ "/crons": 20 }),
      paths: { crons: "/crons" },
      thresholds: { maxCrons: 20 },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, true);
  });

  // ── Async Scanner ───────────────────────────────────

  it("supports async scanner", async () => {
    const asyncScanner: FileSystemScanner = {
      countFiles: async (path: string) => {
        await new Promise((r) => setTimeout(r, 5));
        return path === "/crons" ? 25 : 0;
      },
    };

    const auditor = createBloatAuditor({
      scanner: asyncScanner,
      paths: { crons: "/crons" },
      thresholds: { maxCrons: 20 },
    });

    const report = await auditor.audit();
    assert.equal(report.clean, false);
    assert.equal(report.warnings[0].count, 25);
  });
});
