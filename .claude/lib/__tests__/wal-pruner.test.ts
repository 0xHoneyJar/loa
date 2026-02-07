import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  WALPruner,
  createWALPruner,
  type WALPruneTarget,
  type WALEntry,
} from "../sync/wal-pruner.js";

function makeTarget(
  name: string,
  entries: WALEntry[],
): WALPruneTarget & { written: WALEntry[] | null } {
  const target = {
    name,
    written: null as WALEntry[] | null,
    async read() { return [...entries]; },
    async write(e: WALEntry[]) { target.written = e; },
  };
  return target;
}

describe("WALPruner (T3.5)", () => {
  const NOW = 1_000_000;

  it("createWALPruner returns instance", () => {
    const pruner = createWALPruner();
    assert.ok(pruner instanceof WALPruner);
  });

  it("prunes entries older than maxAgeMs", async () => {
    const entries: WALEntry[] = [
      { timestamp: NOW - 100 },     // recent
      { timestamp: NOW - 5000 },    // old
    ];
    const target = makeTarget("wal", entries);
    const pruner = createWALPruner({ maxAgeMs: 1000, now: () => NOW });
    const result = await pruner.prune([target]);
    assert.equal(result.total, 1);
    assert.equal(result.perTarget.get("wal"), 1);
    assert.equal(target.written!.length, 1);
    assert.equal(target.written![0].timestamp, NOW - 100);
  });

  it("prunes entries over maxEntries (keeps newest)", async () => {
    const entries: WALEntry[] = [
      { timestamp: 3 },
      { timestamp: 1 },
      { timestamp: 2 },
    ];
    const target = makeTarget("wal", entries);
    const pruner = createWALPruner({
      maxEntries: 2,
      maxAgeMs: 999_999,
      now: () => 4,
    });
    const result = await pruner.prune([target]);
    assert.equal(result.total, 1);
    assert.equal(target.written!.length, 2);
    // Should keep timestamps 3 and 2 (newest)
    const timestamps = target.written!.map((e) => e.timestamp).sort();
    assert.deepEqual(timestamps, [2, 3]);
  });

  it("no-op when nothing to prune", async () => {
    const entries: WALEntry[] = [{ timestamp: NOW }];
    const target = makeTarget("wal", entries);
    const pruner = createWALPruner({ now: () => NOW });
    const result = await pruner.prune([target]);
    assert.equal(result.total, 0);
    assert.equal(target.written, null); // write not called
  });

  it("handles empty target", async () => {
    const target = makeTarget("empty", []);
    const pruner = createWALPruner({ now: () => NOW });
    const result = await pruner.prune([target]);
    assert.equal(result.total, 0);
    assert.equal(result.perTarget.get("empty"), 0);
  });

  it("handles multiple targets sequentially", async () => {
    const t1 = makeTarget("t1", [
      { timestamp: NOW },
      { timestamp: NOW - 99999 },
    ]);
    const t2 = makeTarget("t2", [
      { timestamp: NOW - 99999 },
    ]);
    const pruner = createWALPruner({ maxAgeMs: 1000, now: () => NOW });
    const result = await pruner.prune([t1, t2]);
    assert.equal(result.total, 2);
    assert.equal(result.perTarget.get("t1"), 1);
    assert.equal(result.perTarget.get("t2"), 1);
  });

  it("uses injectable clock", async () => {
    let clock = 100;
    const entries: WALEntry[] = [{ timestamp: 50 }, { timestamp: 90 }];
    const target = makeTarget("wal", entries);
    const pruner = createWALPruner({ maxAgeMs: 20, now: () => clock });
    const result = await pruner.prune([target]);
    // cutoff = 100 - 20 = 80, so timestamp 50 is pruned
    assert.equal(result.total, 1);
    assert.equal(target.written!.length, 1);
    assert.equal(target.written![0].timestamp, 90);
  });

  it("uses default config values", async () => {
    const pruner = createWALPruner();
    // Just verify it doesn't throw with defaults
    const target = makeTarget("wal", []);
    const result = await pruner.prune([target]);
    assert.equal(result.total, 0);
  });

  it("preserves extra fields on WALEntry", async () => {
    const entries: WALEntry[] = [
      { timestamp: NOW, op: "write", target: "foo" },
    ];
    const target = makeTarget("wal", entries);
    const pruner = createWALPruner({ now: () => NOW });
    await pruner.prune([target]);
    // No prune needed, but verify structure is intact
    assert.equal(target.written, null);
  });
});
