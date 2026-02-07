import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { validateMECE } from "../scheduler/mece-validator.js";

describe("MECE Validator (T2.5)", () => {
  // ── Valid Configurations ────────────────────────────

  it("returns valid for empty task list", () => {
    const report = validateMECE([]);
    assert.equal(report.valid, true);
    assert.equal(report.overlaps.length, 0);
    assert.equal(report.gaps.length, 0);
  });

  it("returns valid for unique tasks with different intervals", () => {
    const report = validateMECE([
      { id: "a", intervalMs: 1000 },
      { id: "b", intervalMs: 5000 },
      { id: "c", intervalMs: 60000 },
    ]);
    assert.equal(report.valid, true);
  });

  it("returns valid for same mutex group with different intervals", () => {
    const report = validateMECE([
      { id: "a", intervalMs: 1000, mutexGroup: "g1" },
      { id: "b", intervalMs: 5000, mutexGroup: "g1" },
    ]);
    assert.equal(report.valid, true);
  });

  // ── Duplicate IDs ──────────────────────────────────

  it("detects duplicate task IDs", () => {
    const report = validateMECE([
      { id: "a", intervalMs: 1000 },
      { id: "a", intervalMs: 2000 },
    ]);
    assert.equal(report.valid, false);
    assert.equal(report.overlaps.length, 1);
    assert.ok(report.overlaps[0].reason.includes("Duplicate"));
  });

  it("detects multiple duplicates", () => {
    const report = validateMECE([
      { id: "a", intervalMs: 1000 },
      { id: "a", intervalMs: 2000 },
      { id: "b", intervalMs: 3000 },
      { id: "b", intervalMs: 4000 },
    ]);
    assert.equal(report.valid, false);
    assert.equal(report.overlaps.length, 2);
  });

  // ── Mutex Group Overlaps ───────────────────────────

  it("detects near-identical intervals in same mutex group", () => {
    const report = validateMECE([
      { id: "a", intervalMs: 1000, mutexGroup: "g1" },
      { id: "b", intervalMs: 1050, mutexGroup: "g1" },
    ]);
    assert.equal(report.valid, false);
    assert.equal(report.overlaps.length, 1);
    assert.ok(report.overlaps[0].reason.includes("mutex group"));
  });

  it("does not flag different mutex groups", () => {
    const report = validateMECE([
      { id: "a", intervalMs: 1000, mutexGroup: "g1" },
      { id: "b", intervalMs: 1000, mutexGroup: "g2" },
    ]);
    assert.equal(report.valid, true);
  });

  it("does not flag same group with sufficiently different intervals", () => {
    const report = validateMECE([
      { id: "a", intervalMs: 1000, mutexGroup: "g1" },
      { id: "b", intervalMs: 5000, mutexGroup: "g1" },
    ]);
    assert.equal(report.valid, true);
  });

  // ── Pure Function ──────────────────────────────────

  it("does not modify input array", () => {
    const tasks = [
      { id: "a", intervalMs: 1000 },
      { id: "b", intervalMs: 2000 },
    ];
    const copy = JSON.parse(JSON.stringify(tasks));
    validateMECE(tasks);
    assert.deepEqual(tasks, copy);
  });
});
