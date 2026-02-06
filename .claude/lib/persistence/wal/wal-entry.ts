/**
 * WAL Entry types and ID generation.
 *
 * Entry IDs are time-sortable: `${timestamp}-${seq}-${hex4}`
 * Backwards-compatible with legacy UUID entries.
 */

import { createHash } from "crypto";

// ── Entry Types ──────────────────────────────────────────────

export type WALOperation = "write" | "delete" | "mkdir";

export interface WALEntry {
  id: string;
  seq: number;
  timestamp: string;
  operation: WALOperation;
  path: string;
  checksum?: string;
  data?: string;
  entryChecksum: string;
}

export interface WALSegment {
  id: string;
  path: string;
  size: number;
  entries: number;
  createdAt: string;
  closedAt?: string;
}

export interface WALCheckpoint {
  lastSeq: number;
  activeSegment: string;
  segments: WALSegment[];
  lastCheckpointAt: string;
  rotationPhase: "none" | "checkpoint_written" | "rotating";
}

// ── ID Generation ────────────────────────────────────────────

let seqCounter = 0;

/**
 * Generate a time-sortable entry ID: `{timestamp}-{seq}-{hex4}`
 * Monotonic within a process (seq increments), sortable across processes (timestamp prefix).
 */
export function generateEntryId(): string {
  const ts = Date.now();
  const seq = seqCounter++;
  const hex4 = Math.floor(Math.random() * 0xffff)
    .toString(16)
    .padStart(4, "0");
  return `${ts}-${seq}-${hex4}`;
}

/**
 * Check if an entry ID is a legacy UUID format.
 * UUID v4: 8-4-4-4-12 hex pattern
 */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isLegacyUUID(id: string): boolean {
  return UUID_RE.test(id);
}

/**
 * Extract timestamp from a time-sortable ID. Returns 0 for UUIDs.
 */
export function extractTimestamp(id: string): number {
  if (isLegacyUUID(id)) return 0;
  const ts = parseInt(id.split("-")[0], 10);
  return isNaN(ts) ? 0 : ts;
}

// ── Checksum Utilities ───────────────────────────────────────

export function computeDataChecksum(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

export function computeEntryChecksum(entry: Omit<WALEntry, "entryChecksum">): string {
  const sorted = JSON.stringify(entry, Object.keys(entry).sort());
  return createHash("sha256").update(sorted).digest("hex").substring(0, 16);
}

/**
 * Verify an entry's integrity checksum.
 */
export function verifyEntry(entry: WALEntry): boolean {
  const { entryChecksum, ...rest } = entry;
  return computeEntryChecksum(rest) === entryChecksum;
}
