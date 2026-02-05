/**
 * Reference Implementation: File-Based WAL Adapter
 *
 * A simple file-based Write-Ahead Log using JSONL format.
 * This is a REFERENCE IMPLEMENTATION for demonstration and testing.
 * Production deployments may want a more robust solution.
 *
 * @module beads/reference/file-wal
 * @version 1.0.0
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
}

/**
 * File-based Write-Ahead Log Adapter
 *
 * Stores entries in a JSONL file (one JSON object per line).
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

  constructor(config: FileWALConfig) {
    this.path = config.path;
    this.maxRetries = config.maxRetries ?? 3;
  }

  /**
   * Append a new entry to the WAL
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
   */
  async getPendingEntries(): Promise<WALEntry[]> {
    const entries = await this.readAll();
    return entries.filter((e) => e.status === "pending");
  }

  /**
   * Mark an entry as applied
   */
  async markApplied(entryId: string): Promise<void> {
    await this.updateEntry(entryId, { status: "applied" });
  }

  /**
   * Mark an entry as failed
   */
  async markFailed(entryId: string, error: string): Promise<void> {
    const entries = await this.readAll();
    const entry = entries.find((e) => e.id === entryId);

    if (!entry) return;

    const retryCount = (entry.retryCount ?? 0) + 1;
    const status = retryCount >= this.maxRetries ? "failed" : "pending";

    await this.updateEntry(entryId, { status, error, retryCount });
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
   */
  async truncate(olderThan: string): Promise<void> {
    const cutoff = new Date(olderThan).getTime();
    const entries = await this.readAll();

    const kept = entries.filter((e) => {
      if (e.status !== "applied") return true;
      return new Date(e.timestamp).getTime() >= cutoff;
    });

    await this.writeAll(kept);
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  private async readAll(): Promise<WALEntry[]> {
    try {
      await access(this.path, constants.F_OK);
    } catch {
      return [];
    }

    const content = await readFile(this.path, "utf-8");
    const lines = content.split("\n").filter((l) => l.trim());

    return lines.map((line) => JSON.parse(line) as WALEntry);
  }

  private async writeAll(entries: WALEntry[]): Promise<void> {
    const content = entries.map((e) => JSON.stringify(e)).join("\n") + "\n";
    await writeFile(this.path, content, "utf-8");
  }

  private async updateEntry(
    entryId: string,
    updates: Partial<WALEntry>,
  ): Promise<void> {
    const entries = await this.readAll();
    const updated = entries.map((e) =>
      e.id === entryId ? { ...e, ...updates } : e,
    );
    await this.writeAll(updated);
  }
}

/**
 * Factory function
 */
export function createFileWAL(config: FileWALConfig): FileWALAdapter {
  return new FileWALAdapter(config);
}
