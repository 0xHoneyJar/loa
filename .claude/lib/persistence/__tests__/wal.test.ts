import { mkdtempSync, rmSync, existsSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { describe, it, expect, beforeEach, afterEach } from "vitest";
import type { WALEntry } from "../wal/wal-entry.js";
import { compactEntries } from "../wal/wal-compaction.js";
import {
  generateEntryId,
  isLegacyUUID,
  extractTimestamp,
  verifyEntry,
  computeEntryChecksum,
} from "../wal/wal-entry.js";
import { WALManager } from "../wal/wal-manager.js";
import { evaluateDiskPressure } from "../wal/wal-pressure.js";

describe("WAL", () => {
  let walDir: string;

  beforeEach(() => {
    walDir = mkdtempSync(join(tmpdir(), "wal-test-"));
  });

  afterEach(async () => {
    rmSync(walDir, { recursive: true, force: true });
  });

  // ── 1. Append ────────────────────────────────────────────

  it("appends entries with incrementing sequence numbers", async () => {
    const wal = new WALManager({ walDir });
    await wal.initialize();

    const seq1 = await wal.append("write", "/test/a.txt", Buffer.from("hello"));
    const seq2 = await wal.append("write", "/test/b.txt", Buffer.from("world"));
    const seq3 = await wal.append("delete", "/test/a.txt");

    expect(seq1).toBe(1);
    expect(seq2).toBe(2);
    expect(seq3).toBe(3);
    expect(wal.getStatus().seq).toBe(3);

    await wal.shutdown();
  });

  // ── 2. Replay ────────────────────────────────────────────

  it("replays all entries in sequence order", async () => {
    const wal = new WALManager({ walDir });
    await wal.initialize();

    await wal.append("write", "/a.txt", Buffer.from("data-a"));
    await wal.append("write", "/b.txt", Buffer.from("data-b"));
    await wal.append("delete", "/a.txt");
    await wal.shutdown();

    // Re-open and replay
    const wal2 = new WALManager({ walDir });
    await wal2.initialize();

    const replayed: WALEntry[] = [];
    const result = await wal2.replay(async (entry) => {
      replayed.push(entry);
    });

    expect(result.replayed).toBe(3);
    expect(result.errors).toBe(0);
    expect(replayed[0].path).toBe("/a.txt");
    expect(replayed[0].operation).toBe("write");
    expect(replayed[1].path).toBe("/b.txt");
    expect(replayed[2].operation).toBe("delete");

    await wal2.shutdown();
  });

  // ── 3. Compaction ────────────────────────────────────────

  it("compaction keeps only latest write per path", () => {
    const entries: WALEntry[] = [
      makeEntry(1, "write", "/x.txt", "v1"),
      makeEntry(2, "write", "/y.txt", "v1"),
      makeEntry(3, "write", "/x.txt", "v2"),
      makeEntry(4, "write", "/x.txt", "v3"),
      makeEntry(5, "delete", "/y.txt"),
    ];

    const compacted = compactEntries(entries);

    // /x.txt latest write (seq 4) + /y.txt delete (seq 5)
    expect(compacted).toHaveLength(2);
    expect(compacted[0].seq).toBe(4);
    expect(compacted[0].path).toBe("/x.txt");
    expect(compacted[1].seq).toBe(5);
    expect(compacted[1].operation).toBe("delete");
  });

  // ── 4. Disk Pressure ────────────────────────────────────

  it("evaluates disk pressure levels correctly", () => {
    const config = {
      warningBytes: 100,
      criticalBytes: 200,
    };

    expect(evaluateDiskPressure(50, config)).toBe("normal");
    expect(evaluateDiskPressure(100, config)).toBe("warning");
    expect(evaluateDiskPressure(150, config)).toBe("warning");
    expect(evaluateDiskPressure(200, config)).toBe("critical");
    expect(evaluateDiskPressure(300, config)).toBe("critical");
  });

  // ── 5. Limit/Pagination ─────────────────────────────────

  it("replay supports sinceSeq and limit for pagination", async () => {
    const wal = new WALManager({ walDir });
    await wal.initialize();

    for (let i = 0; i < 10; i++) {
      await wal.append("write", `/file-${i}.txt`, Buffer.from(`data-${i}`));
    }
    await wal.shutdown();

    const wal2 = new WALManager({ walDir });
    await wal2.initialize();

    // Page 1: entries 1-3
    const page1: WALEntry[] = [];
    await wal2.replay(async (e) => page1.push(e), { sinceSeq: 0, limit: 3 });
    expect(page1).toHaveLength(3);
    expect(page1[0].seq).toBe(1);

    // Page 2: entries 4-6
    const page2: WALEntry[] = [];
    await wal2.replay(async (e) => page2.push(e), { sinceSeq: 3, limit: 3 });
    expect(page2).toHaveLength(3);
    expect(page2[0].seq).toBe(4);

    // getEntriesSince with limit
    const entries = await wal2.getEntriesSince(7, 2);
    expect(entries).toHaveLength(2);
    expect(entries[0].seq).toBe(8);

    await wal2.shutdown();
  });

  // ── 6. Backwards Compat ─────────────────────────────────

  it("handles legacy UUID entry IDs", () => {
    expect(isLegacyUUID("550e8400-e29b-41d4-a716-446655440000")).toBe(true);
    expect(isLegacyUUID("1707000000000-0-a1b2")).toBe(false);

    const id = generateEntryId();
    expect(isLegacyUUID(id)).toBe(false);
    expect(extractTimestamp(id)).toBeGreaterThan(0);
    expect(extractTimestamp("550e8400-e29b-41d4-a716-446655440000")).toBe(0);
  });

  // ── 7. Flock / Lock ────────────────────────────────────

  it("creates PID lockfile on initialize", async () => {
    const wal = new WALManager({ walDir });
    await wal.initialize();

    const pidPath = join(walDir, "wal.pid");
    expect(existsSync(pidPath)).toBe(true);
    const pid = readFileSync(pidPath, "utf-8").trim();
    expect(parseInt(pid, 10)).toBe(process.pid);

    await wal.shutdown();
    expect(existsSync(pidPath)).toBe(false);
  });

  // ── 8. PID Fallback ────────────────────────────────────

  it("takes over lock from dead process PID file", async () => {
    // Simulate stale PID file from a dead process
    writeFileSync(join(walDir, "wal.pid"), "999999999", "utf-8");

    const wal = new WALManager({ walDir });
    await wal.initialize();

    // Should have taken over
    const pid = readFileSync(join(walDir, "wal.pid"), "utf-8").trim();
    expect(parseInt(pid, 10)).toBe(process.pid);

    await wal.shutdown();
  });

  // ── 9. Concurrent Append Safety ─────────────────────────

  it("handles concurrent appends without data loss", async () => {
    const wal = new WALManager({ walDir });
    await wal.initialize();

    // Fire 20 appends concurrently
    const promises = Array.from({ length: 20 }, (_, i) =>
      wal.append("write", `/concurrent-${i}.txt`, Buffer.from(`data-${i}`)),
    );

    const seqs = await Promise.all(promises);

    // All seqs should be unique
    const uniqueSeqs = new Set(seqs);
    expect(uniqueSeqs.size).toBe(20);

    // Verify all entries can be replayed
    const entries = await wal.getEntriesSince(0);
    expect(entries).toHaveLength(20);

    await wal.shutdown();
  });
});

// ── Helper ─────────────────────────────────────────────────

function makeEntry(seq: number, operation: string, path: string, dataStr?: string): WALEntry {
  const entry: Omit<WALEntry, "entryChecksum"> = {
    id: generateEntryId(),
    seq,
    timestamp: new Date().toISOString(),
    operation: operation as WALEntry["operation"],
    path,
  };

  if (dataStr) {
    entry.data = Buffer.from(dataStr).toString("base64");
  }

  return { ...entry, entryChecksum: computeEntryChecksum(entry) };
}
