/**
 * WAL Compaction — delta-based reduction.
 *
 * Keeps only the latest write per path, reducing segment size
 * while preserving the final state. O(n) single pass.
 */

import type { WALEntry } from "./wal-entry.js";

/**
 * Compact a list of WAL entries by keeping only the latest operation per path.
 * For each path, only the most recent operation (write, mkdir, or delete) is kept.
 * A write after a delete correctly supersedes the delete for that path.
 *
 * @returns Compacted entries in original order (stable sort by seq)
 */
export function compactEntries(entries: WALEntry[]): WALEntry[] {
  // Track the latest entry per path — always keyed by the actual path.
  // Each new operation for a path overwrites the previous one,
  // so delete→write correctly keeps the write.
  const latestByPath = new Map<string, WALEntry>();

  for (const entry of entries) {
    latestByPath.set(entry.path, entry);
  }

  // Return entries sorted by seq (preserves causality)
  return Array.from(latestByPath.values()).sort((a, b) => a.seq - b.seq);
}

/**
 * Calculate compaction ratio.
 * @returns Ratio between 0 (no reduction) and 1 (all entries removed)
 */
export function compactionRatio(original: number, compacted: number): number {
  if (original === 0) return 0;
  return 1 - compacted / original;
}
