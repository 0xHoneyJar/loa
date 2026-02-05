/**
 * Tests for File-Based WAL Adapter
 *
 * Includes isomorphism verification tests (RFC #198) that ensure the
 * append-only optimization produces identical results to the previous
 * read-modify-write implementation.
 *
 * @module beads/__tests__/file-wal
 */

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm, readFile } from "fs/promises";
import { tmpdir } from "os";
import { join } from "path";
import { FileWALAdapter, createFileWAL } from "../reference/file-wal";
import type { WALEntry } from "../interfaces";

// =============================================================================
// Test Helpers
// =============================================================================

let tempDir: string;
let walPath: string;

beforeEach(async () => {
  tempDir = await mkdtemp(join(tmpdir(), "wal-test-"));
  walPath = join(tempDir, "test-wal.jsonl");
});

afterEach(async () => {
  await rm(tempDir, { recursive: true, force: true });
});

function createTestEntry(
  overrides?: Partial<Omit<WALEntry, "id" | "timestamp">>,
): Omit<WALEntry, "id" | "timestamp"> {
  return {
    operation: "create",
    beadId: null,
    payload: { title: "Test", type: "task" },
    status: "pending",
    ...overrides,
  };
}

// =============================================================================
// Core Functionality
// =============================================================================

describe("FileWALAdapter", () => {
  describe("append", () => {
    it("should append entries to JSONL file", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      const id1 = await wal.append(createTestEntry());
      const id2 = await wal.append(createTestEntry({ operation: "update" }));

      expect(id1).toBeTruthy();
      expect(id2).toBeTruthy();
      expect(id1).not.toBe(id2);

      const content = await readFile(walPath, "utf-8");
      const lines = content.split("\n").filter((l) => l.trim());
      expect(lines).toHaveLength(2);
    });

    it("should generate unique IDs", async () => {
      const wal = new FileWALAdapter({ path: walPath });
      const ids = new Set<string>();

      for (let i = 0; i < 50; i++) {
        const id = await wal.append(createTestEntry());
        ids.add(id);
      }

      expect(ids.size).toBe(50);
    });

    it("should set retryCount to 0", async () => {
      const wal = new FileWALAdapter({ path: walPath });
      await wal.append(createTestEntry());

      const entries = await wal.getPendingEntries();
      expect(entries[0].retryCount).toBe(0);
    });
  });

  describe("getPendingEntries", () => {
    it("should return empty array for non-existent file", async () => {
      const wal = new FileWALAdapter({ path: walPath });
      const entries = await wal.getPendingEntries();
      expect(entries).toEqual([]);
    });

    it("should only return pending entries", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      const id1 = await wal.append(createTestEntry());
      await wal.append(createTestEntry());
      await wal.append(createTestEntry());

      await wal.markApplied(id1);

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(2);
      expect(pending.find((e) => e.id === id1)).toBeUndefined();
    });
  });

  describe("markApplied", () => {
    it("should change entry status to applied", async () => {
      const wal = new FileWALAdapter({ path: walPath });
      const id = await wal.append(createTestEntry());

      await wal.markApplied(id);

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(0);
    });

    it("should be O(1) - append-only, not rewrite", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      // Add entries
      const ids: string[] = [];
      for (let i = 0; i < 10; i++) {
        ids.push(await wal.append(createTestEntry()));
      }

      // Mark first as applied - should append a delta, not rewrite
      await wal.markApplied(ids[0]);

      const content = await readFile(walPath, "utf-8");
      const lines = content.split("\n").filter((l) => l.trim());

      // Should have 10 entries + 1 delta = 11 lines
      expect(lines).toHaveLength(11);

      // Last line should be a delta record
      const lastRecord = JSON.parse(lines[10]);
      expect(lastRecord._delta).toBe(true);
      expect(lastRecord.entryId).toBe(ids[0]);
      expect(lastRecord.updates.status).toBe("applied");
    });
  });

  describe("markFailed", () => {
    it("should increment retryCount and set error", async () => {
      const wal = new FileWALAdapter({ path: walPath, maxRetries: 3 });
      const id = await wal.append(createTestEntry());

      await wal.markFailed(id, "Network error");

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(1);
      expect(pending[0].retryCount).toBe(1);
      expect(pending[0].error).toBe("Network error");
      expect(pending[0].status).toBe("pending"); // Still pending (1 < 3)
    });

    it("should change to failed after max retries", async () => {
      const wal = new FileWALAdapter({ path: walPath, maxRetries: 2 });
      const id = await wal.append(createTestEntry());

      await wal.markFailed(id, "Error 1");
      await wal.markFailed(id, "Error 2");

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(0); // Entry is now "failed", not pending
    });

    it("should handle non-existent entry gracefully", async () => {
      const wal = new FileWALAdapter({ path: walPath });
      await wal.append(createTestEntry());

      // Should not throw
      await wal.markFailed("nonexistent-id", "error");
    });
  });

  describe("replay", () => {
    it("should execute pending entries and mark applied", async () => {
      const wal = new FileWALAdapter({ path: walPath });
      const executed: string[] = [];

      await wal.append(createTestEntry({ payload: { step: 1 } }));
      await wal.append(createTestEntry({ payload: { step: 2 } }));

      const count = await wal.replay(async (entry) => {
        executed.push(entry.id);
      });

      expect(count).toBe(2);
      expect(executed).toHaveLength(2);

      // All should be applied now
      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(0);
    });

    it("should mark failed entries on executor error", async () => {
      const wal = new FileWALAdapter({ path: walPath, maxRetries: 3 });
      let callCount = 0;

      await wal.append(createTestEntry());

      const count = await wal.replay(async () => {
        callCount++;
        throw new Error("executor failed");
      });

      expect(count).toBe(0);
      expect(callCount).toBe(1);

      // Entry should still be pending (retryCount=1 < maxRetries=3)
      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(1);
      expect(pending[0].retryCount).toBe(1);
    });
  });

  describe("truncate", () => {
    it("should remove old applied entries", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      const id1 = await wal.append(createTestEntry());
      const id2 = await wal.append(createTestEntry());
      await wal.append(createTestEntry()); // id3 stays pending

      await wal.markApplied(id1);
      await wal.markApplied(id2);

      // Truncate entries older than now (removes all applied)
      await wal.truncate(new Date(Date.now() + 1000).toISOString());

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(1); // Only id3 remains
    });

    it("should produce a compacted file after truncate", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      const id = await wal.append(createTestEntry());
      await wal.markApplied(id);

      // Before truncate: should have entry + delta
      let content = await readFile(walPath, "utf-8");
      let lines = content.split("\n").filter((l) => l.trim());
      expect(lines).toHaveLength(2); // 1 entry + 1 delta

      await wal.truncate(new Date(Date.now() + 1000).toISOString());

      // After truncate: file is compacted (no deltas)
      content = await readFile(walPath, "utf-8");
      lines = content.split("\n").filter((l) => l.trim());
      // Applied entry was removed by truncate, so file should be empty or minimal
      for (const line of lines) {
        const record = JSON.parse(line);
        expect(record._delta).toBeUndefined();
      }
    });
  });

  // ===========================================================================
  // Compaction Tests (RFC #198)
  // ===========================================================================

  describe("compact", () => {
    it("should resolve all deltas into entries", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      const id1 = await wal.append(createTestEntry());
      const id2 = await wal.append(createTestEntry());
      await wal.markApplied(id1);

      // Before compact: 2 entries + 1 delta
      let content = await readFile(walPath, "utf-8");
      let lines = content.split("\n").filter((l) => l.trim());
      expect(lines).toHaveLength(3);

      const compacted = await wal.compact();
      expect(compacted).toBe(true);

      // After compact: 2 entries, no deltas
      content = await readFile(walPath, "utf-8");
      lines = content.split("\n").filter((l) => l.trim());
      expect(lines).toHaveLength(2);

      // Verify no deltas remain
      for (const line of lines) {
        const record = JSON.parse(line);
        expect(record._delta).toBeUndefined();
      }

      // Verify state is preserved
      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(1);
      expect(pending[0].id).toBe(id2);
    });

    it("should return false when already compact", async () => {
      const wal = new FileWALAdapter({ path: walPath });
      await wal.append(createTestEntry());

      // No deltas, so compact should be a no-op
      const compacted = await wal.compact();
      expect(compacted).toBe(false);
    });

    it("should handle non-existent WAL file", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      // File doesn't exist yet — compact should be a no-op
      const compacted = await wal.compact();
      expect(compacted).toBe(false);
    });
  });

  describe("maybeCompact (non-existent file)", () => {
    it("should handle non-existent WAL file", async () => {
      const wal = new FileWALAdapter({
        path: walPath,
        minEntriesForCompaction: 1,
      });

      // File doesn't exist — should return false (0 < 1 threshold)
      const compacted = await wal.maybeCompact();
      expect(compacted).toBe(false);
    });
  });

  describe("maybeCompact", () => {
    it("should not compact when below entry threshold", async () => {
      const wal = new FileWALAdapter({
        path: walPath,
        minEntriesForCompaction: 100,
      });

      for (let i = 0; i < 10; i++) {
        const id = await wal.append(createTestEntry());
        await wal.markApplied(id);
      }

      const compacted = await wal.maybeCompact();
      expect(compacted).toBe(false);
    });

    it("should not compact when applied ratio below threshold", async () => {
      const wal = new FileWALAdapter({
        path: walPath,
        minEntriesForCompaction: 5,
        compactionThreshold: 0.9,
      });

      // 10 entries, only 5 applied = 50% < 90% threshold
      for (let i = 0; i < 10; i++) {
        const id = await wal.append(createTestEntry());
        if (i < 5) {
          await wal.markApplied(id);
        }
      }

      const compacted = await wal.maybeCompact();
      expect(compacted).toBe(false);
    });

    it("should compact when both thresholds met", async () => {
      const wal = new FileWALAdapter({
        path: walPath,
        minEntriesForCompaction: 5,
        compactionThreshold: 0.5,
      });

      // 10 entries, 8 applied = 80% > 50% threshold, 10 > 5 min
      for (let i = 0; i < 10; i++) {
        const id = await wal.append(createTestEntry());
        if (i < 8) {
          await wal.markApplied(id);
        }
      }

      const compacted = await wal.maybeCompact();
      expect(compacted).toBe(true);

      // Verify file was compacted
      const content = await readFile(walPath, "utf-8");
      const lines = content.split("\n").filter((l) => l.trim());
      for (const line of lines) {
        const record = JSON.parse(line);
        expect(record._delta).toBeUndefined();
      }
    });
  });

  // ===========================================================================
  // Isomorphism Verification (RFC #198)
  // ===========================================================================

  describe("Isomorphism: append-only produces same results as read-modify-write", () => {
    it("should resolve entries identically after multiple status changes", async () => {
      const wal = new FileWALAdapter({ path: walPath, maxRetries: 5 });

      const id1 = await wal.append(createTestEntry({ payload: { task: "A" } }));
      const id2 = await wal.append(createTestEntry({ payload: { task: "B" } }));
      const id3 = await wal.append(createTestEntry({ payload: { task: "C" } }));

      // Complex sequence of status changes
      await wal.markFailed(id1, "Error 1");
      await wal.markFailed(id1, "Error 2");
      await wal.markApplied(id2);
      await wal.markFailed(id3, "Error 3");
      await wal.markApplied(id1); // Recovered after 2 failures

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(1);
      expect(pending[0].id).toBe(id3);
      expect(pending[0].retryCount).toBe(1);
      expect(pending[0].error).toBe("Error 3");
    });

    it("should compact without changing observable state", async () => {
      const wal = new FileWALAdapter({ path: walPath, maxRetries: 5 });

      // Build up complex state
      const ids: string[] = [];
      for (let i = 0; i < 20; i++) {
        ids.push(await wal.append(createTestEntry({ payload: { index: i } })));
      }

      // Apply various status changes
      for (let i = 0; i < 15; i++) {
        await wal.markApplied(ids[i]);
      }
      await wal.markFailed(ids[15], "fail-15");
      await wal.markFailed(ids[16], "fail-16");

      // Snapshot state BEFORE compaction
      const pendingBefore = await wal.getPendingEntries();
      const pendingIdsBefore = pendingBefore.map((e) => e.id).sort();
      const pendingStatusBefore = pendingBefore.map((e) => ({
        id: e.id,
        status: e.status,
        retryCount: e.retryCount,
        error: e.error,
      }));

      // Compact
      await wal.compact();

      // Snapshot state AFTER compaction
      const pendingAfter = await wal.getPendingEntries();
      const pendingIdsAfter = pendingAfter.map((e) => e.id).sort();
      const pendingStatusAfter = pendingAfter.map((e) => ({
        id: e.id,
        status: e.status,
        retryCount: e.retryCount,
        error: e.error,
      }));

      // ISOMORPHISM CHECK: same pending entries, same state
      expect(pendingIdsAfter).toEqual(pendingIdsBefore);
      expect(pendingStatusAfter).toEqual(pendingStatusBefore);
    });

    it("should handle interleaved appends and status changes", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      // Simulate real workflow: append, apply, append, fail, append, apply...
      const id1 = await wal.append(createTestEntry({ payload: { step: 1 } }));
      await wal.markApplied(id1);

      const id2 = await wal.append(createTestEntry({ payload: { step: 2 } }));
      await wal.markFailed(id2, "transient");

      const id3 = await wal.append(createTestEntry({ payload: { step: 3 } }));
      await wal.markApplied(id3);

      // id2 retried successfully
      await wal.markApplied(id2);

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(0);
    });

    it("should preserve entry order after compaction", async () => {
      const wal = new FileWALAdapter({ path: walPath });

      const id1 = await wal.append(createTestEntry({ payload: { order: 1 } }));
      const id2 = await wal.append(createTestEntry({ payload: { order: 2 } }));
      const id3 = await wal.append(createTestEntry({ payload: { order: 3 } }));

      await wal.markApplied(id2); // Apply middle one

      await wal.compact();

      const pending = await wal.getPendingEntries();
      expect(pending).toHaveLength(2);

      // Order should be preserved: id1 before id3
      expect(pending[0].id).toBe(id1);
      expect(pending[0].payload).toEqual({ order: 1 });
      expect(pending[1].id).toBe(id3);
      expect(pending[1].payload).toEqual({ order: 3 });
    });
  });

  // ===========================================================================
  // Factory Function
  // ===========================================================================

  describe("createFileWAL", () => {
    it("should create adapter with config", () => {
      const wal = createFileWAL({ path: walPath });
      expect(wal).toBeInstanceOf(FileWALAdapter);
    });

    it("should accept optional config", () => {
      const wal = createFileWAL({
        path: walPath,
        maxRetries: 5,
        compactionThreshold: 0.8,
        minEntriesForCompaction: 100,
      });
      expect(wal).toBeInstanceOf(FileWALAdapter);
    });
  });
});
