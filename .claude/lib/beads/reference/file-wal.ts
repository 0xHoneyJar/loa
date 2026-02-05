/**
 * Reference Implementation: File-Based WAL Adapter
 *
 * A simple file-based Write-Ahead Log using JSONL format.
 * This is a REFERENCE IMPLEMENTATION for demonstration and testing.
 * Production deployments may want a more robust solution.
 *
 * OPTIMIZATION (RFC #198): Append-only writes with periodic compaction.
 * Previous implementation did full file read + rewrite on every status
 * update (O(n²) for n entries). Now uses append-only writes with lazy
 * state resolution during reads.
 *
 * Complexity:
 *   markApplied: O(1) append
 *   markFailed:  O(n) read + O(1) append (needs retryCount for decision)
 *
 * Isomorphism guarantee: For any sequence of operations, the resolved
 * state (getPendingEntries, replay, truncate) produces identical results
 * to the previous read-modify-write implementation.
 *
 * @module beads/reference/file-wal
 * @version 1.1.0
 */

import { appendFile, readFile, writeFile, access } from "fs/promises";
import { constants } from "fs";
import { randomUUID } from "crypto";

import type { WALEntry, IWALAdapter } from "../interfaces";

/**
 * Configuration for FileWALAdapter
 */
export interface FileWALConfig {
  /** Path to the WAL file (JSONL format) */
  path: string;

  /** Maximum retries for failed entries (default: 3) */
  maxRetries?: number;

  /**
   * Ratio of applied entries to total entries that triggers compaction.
   * When `applied / total >= compactionThreshold`, compact() is called
   * automatically after truncate() or when entry count exceeds
   * minEntriesForCompaction.
   * Default: 0.7 (70%)
   */
  compactionThreshold?: number;

  /**
   * Minimum number of raw entries before auto-compaction is considered.
   * Prevents compaction overhead on small WALs.
   * Default: 50
   */
  minEntriesForCompaction?: number;
}

/**
 * Internal record type for append-only status changes.
 * When a status update occurs, we append a delta record instead of
 * rewriting the entire file.
 */
interface WALDelta {
  /** Discriminator to distinguish from WALEntry */
  _delta: true;
  /** ID of the entry being updated */
  entryId: string;
  /** Fields that can be updated via delta (constrained to status-related fields) */
  updates: Pick<Partial<WALEntry>, "status" | "error" | "retryCount">;
}

/** Union type for lines in the JSONL file */
type WALRecord = WALEntry | WALDelta;

function isDelta(record: WALRecord): record is WALDelta {
  return "_delta" in record && record._delta === true;
}

/**
 * File-based Write-Ahead Log Adapter
 *
 * Stores entries in a JSONL file (one JSON object per line).
 * Uses append-only writes for O(1) status updates.
 * Suitable for single-process, low-volume use cases.
 *
 * **NOT RECOMMENDED** for:
 * - Multi-process access (no locking)
 * - High-volume logging (no rotation)
 * - Distributed systems (no coordination)
 *
 * @example
 * ```typescript
 * const wal = new FileWALAdapter({ path: ".beads/wal.jsonl" });
 *
 * // Log an operation before executing
 * const entryId = await wal.append({
 *   operation: "create",
 *   beadId: null,
 *   payload: { title: "New task", type: "task" },
 *   status: "pending",
 * });
 *
 * // Execute the operation...
 * await wal.markApplied(entryId);
 * ```
 */
export class FileWALAdapter implements IWALAdapter {
  private readonly path: string;
  private readonly maxRetries: number;
  private readonly compactionThreshold: number;
  private readonly minEntriesForCompaction: number;

  constructor(config: FileWALConfig) {
    this.path = config.path;
    this.maxRetries = config.maxRetries ?? 3;
    this.compactionThreshold = config.compactionThreshold ?? 0.7;
    this.minEntriesForCompaction = config.minEntriesForCompaction ?? 50;
  }

  /**
   * Append a new entry to the WAL
   *
   * O(1) - single append to file
   */
  async append(entry: Omit<WALEntry, "id" | "timestamp">): Promise<string> {
    const id = randomUUID();
    const timestamp = new Date().toISOString();

    const fullEntry: WALEntry = {
      id,
      timestamp,
      ...entry,
      retryCount: 0,
    };

    const line = JSON.stringify(fullEntry) + "\n";
    await appendFile(this.path, line, "utf-8");

    return id;
  }

  /**
   * Get all entries with pending status
   *
   * Resolves append-only records into materialized state, then filters.
   */
  async getPendingEntries(): Promise<WALEntry[]> {
    const entries = await this.resolveEntries();
    return entries.filter((e) => e.status === "pending");
  }

  /**
   * Mark an entry as applied
   *
   * O(1) - appends a delta record instead of rewriting the file
   */
  async markApplied(entryId: string): Promise<void> {
    await this.appendDelta(entryId, { status: "applied" });
  }

  /**
   * Mark an entry as failed
   *
   * O(n) read + O(1) append. Reads the current retryCount from the
   * resolved state to determine whether to mark as "failed" (exhausted)
   * or "pending" (retriable). The read is inherent — retryCount must
   * be known to decide final status.
   */
  async markFailed(entryId: string, error: string): Promise<void> {
    // We need the current entry state to compute retryCount
    const entries = await this.resolveEntries();
    const entry = entries.find((e) => e.id === entryId);

    if (!entry) return;

    const retryCount = (entry.retryCount ?? 0) + 1;
    const status = retryCount >= this.maxRetries ? "failed" : "pending";

    await this.appendDelta(entryId, { status, error, retryCount });
  }

  /**
   * Replay all pending entries
   */
  async replay(executor: (entry: WALEntry) => Promise<void>): Promise<number> {
    const pending = await this.getPendingEntries();
    let replayed = 0;

    for (const entry of pending) {
      try {
        await executor(entry);
        await this.markApplied(entry.id);
        replayed++;
      } catch (e) {
        const error = e instanceof Error ? e.message : String(e);
        await this.markFailed(entry.id, error);
      }
    }

    return replayed;
  }

  /**
   * Truncate WAL by removing old applied entries
   *
   * This is one of the safe compaction points. After truncation,
   * auto-compaction is triggered if thresholds are met.
   */
  async truncate(olderThan: string): Promise<void> {
    const cutoff = new Date(olderThan).getTime();
    const entries = await this.resolveEntries();

    const kept = entries.filter((e) => {
      if (e.status !== "applied") return true;
      return new Date(e.timestamp).getTime() >= cutoff;
    });

    // truncate always writes compacted form (no deltas)
    await this.writeCompacted(kept);
  }

  /**
   * Compact the WAL file by resolving all deltas into entries.
   *
   * Safe to call at any time. Produces a file with zero delta records
   * that is semantically identical to the current state.
   *
   * Recommended compaction points:
   * - After sprint completion (natural checkpoint)
   * - During PREFLIGHT phase (before critical work)
   * - On explicit user request
   *
   * NOT recommended during:
   * - Flatline review (latency-sensitive)
   * - Mid-sprint implementation (could lose recovery window)
   * - Active circuit breaker state (state is critical)
   */
  async compact(): Promise<boolean> {
    const rawRecords = await this.readAllRaw();
    const deltaCount = rawRecords.filter(isDelta).length;

    if (deltaCount === 0) {
      return false; // Already compact
    }

    const entries = this.materializeEntries(rawRecords);
    await this.writeCompacted(entries);
    return true;
  }

  /**
   * Check if auto-compaction should be triggered.
   * Returns true if compaction was performed.
   */
  async maybeCompact(): Promise<boolean> {
    const rawRecords = await this.readAllRaw();

    if (rawRecords.length < this.minEntriesForCompaction) {
      return false;
    }

    const entries = this.materializeEntries(rawRecords);
    const appliedCount = entries.filter((e) => e.status === "applied").length;
    const appliedRatio = entries.length > 0 ? appliedCount / entries.length : 0;

    if (appliedRatio < this.compactionThreshold) {
      return false;
    }

    await this.writeCompacted(entries);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  /**
   * Read all raw records from the JSONL file (entries + deltas)
   */
  private async readAllRaw(): Promise<WALRecord[]> {
    try {
      await access(this.path, constants.F_OK);
    } catch {
      return [];
    }

    const content = await readFile(this.path, "utf-8");
    const lines = content.split("\n").filter((l) => l.trim());

    return lines.map((line) => JSON.parse(line) as WALRecord);
  }

  /**
   * Resolve raw records into materialized WALEntry array.
   * Applies all deltas to their target entries in order.
   *
   * This is the core of the append-only optimization:
   * entries are written once, deltas are appended, and state
   * is materialized on read.
   */
  private async resolveEntries(): Promise<WALEntry[]> {
    const records = await this.readAllRaw();
    return this.materializeEntries(records);
  }

  /**
   * Pure function: materialize entries from raw records.
   * Applies deltas in order to produce final state.
   */
  private materializeEntries(records: WALRecord[]): WALEntry[] {
    const entryMap = new Map<string, WALEntry>();

    for (const record of records) {
      if (isDelta(record)) {
        const existing = entryMap.get(record.entryId);
        if (existing) {
          entryMap.set(record.entryId, { ...existing, ...record.updates });
        }
      } else {
        entryMap.set(record.id, record);
      }
    }

    // Preserve insertion order (Map maintains insertion order)
    return Array.from(entryMap.values());
  }

  /**
   * Append a delta record (status change) to the WAL file.
   * O(1) - single file append, no read required.
   */
  private async appendDelta(
    entryId: string,
    updates: WALDelta["updates"],
  ): Promise<void> {
    const delta: WALDelta = {
      _delta: true,
      entryId,
      updates,
    };
    const line = JSON.stringify(delta) + "\n";
    await appendFile(this.path, line, "utf-8");
  }

  /**
   * Write compacted entries (no deltas) to the WAL file.
   * Used by truncate() and compact().
   *
   * NOTE: Not atomic. A crash mid-write could leave the file partially
   * written. Production implementations should use write-to-temp +
   * rename (atomic on POSIX) for crash safety.
   */
  private async writeCompacted(entries: WALEntry[]): Promise<void> {
    if (entries.length === 0) {
      await writeFile(this.path, "", "utf-8");
      return;
    }
    const content = entries.map((e) => JSON.stringify(e)).join("\n") + "\n";
    await writeFile(this.path, content, "utf-8");
  }
}

/**
 * Factory function
 */
export function createFileWAL(config: FileWALConfig): FileWALAdapter {
  return new FileWALAdapter(config);
}
