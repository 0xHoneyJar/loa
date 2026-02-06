/**
 * Beads WAL Adapter — framework-grade bridge between beads_rust and WAL.
 *
 * Records beads state transitions to the Write-Ahead Log for crash recovery.
 * Portable: depends only on the framework WAL interface, not container paths.
 *
 * SECURITY: All beadIds are validated before use in paths to prevent
 * path traversal attacks. Checksums use 128-bit (32 hex char) truncation
 * for adequate collision resistance.
 *
 * @module .claude/lib/persistence/beads/beads-wal-adapter
 */

import { createHash, randomUUID } from "crypto";

/**
 * Minimal WAL interface — only what BeadsWALAdapter needs.
 * Keeps the beads bridge decoupled from the full WALManager.
 */
export interface IBeadsWAL {
  append(operation: string, path: string, data?: Buffer): Promise<number>;
  replay(visitor: (entry: IBeadsWALEntry) => void | Promise<void>): Promise<void>;
  getEntriesSince?(seq: number): Promise<IBeadsWALEntry[]>;
  getStatus(): { seq: number };
}

/** WAL entry shape consumed during replay. */
export interface IBeadsWALEntry {
  operation: string;
  path: string;
  data?: string; // base64
}

/**
 * SECURITY: Bead ID validation pattern (no path traversal chars).
 */
const BEAD_ID_PATTERN = /^[a-zA-Z0-9_-]+$/;
const MAX_BEAD_ID_LENGTH = 128;

/**
 * SECURITY: Allowed operation types for WAL (whitelist)
 */
const ALLOWED_OPERATIONS = new Set([
  "create",
  "update",
  "close",
  "reopen",
  "label",
  "comment",
  "dep",
]);

/** Operation types that can be recorded in WAL */
export type BeadOperation = "create" | "update" | "close" | "reopen" | "label" | "comment" | "dep";

/** WAL entry for a beads state transition */
export interface BeadWALEntry {
  id: string;
  timestamp: string;
  operation: BeadOperation;
  beadId: string;
  payload: Record<string, unknown>;
  checksum: string;
}

/** Configuration for BeadsWALAdapter */
export interface BeadsWALConfig {
  pathPrefix?: string;
  verbose?: boolean;
}

function validateBeadId(beadId: unknown): asserts beadId is string {
  if (typeof beadId !== "string" || !beadId) {
    throw new Error("Invalid beadId: must be a non-empty string");
  }
  if (beadId.length > MAX_BEAD_ID_LENGTH) {
    throw new Error(`Invalid beadId: exceeds max length ${MAX_BEAD_ID_LENGTH}`);
  }
  if (!BEAD_ID_PATTERN.test(beadId)) {
    throw new Error("Invalid beadId: contains forbidden characters");
  }
}

function validateOperation(operation: unknown): asserts operation is BeadOperation {
  if (typeof operation !== "string" || !ALLOWED_OPERATIONS.has(operation)) {
    throw new Error(`Invalid operation: ${String(operation)}`);
  }
}

function validateWALEntry(data: unknown): asserts data is BeadWALEntry {
  if (!data || typeof data !== "object") {
    throw new Error("Invalid WAL entry: must be an object");
  }
  const entry = data as Record<string, unknown>;
  if (typeof entry.id !== "string" || !entry.id) {
    throw new Error("Invalid WAL entry: missing id");
  }
  if (typeof entry.timestamp !== "string" || !entry.timestamp) {
    throw new Error("Invalid WAL entry: missing timestamp");
  }
  if (typeof entry.checksum !== "string" || !entry.checksum) {
    throw new Error("Invalid WAL entry: missing checksum");
  }
  validateBeadId(entry.beadId);
  validateOperation(entry.operation);
  if (!entry.payload || typeof entry.payload !== "object" || Array.isArray(entry.payload)) {
    throw new Error("Invalid WAL entry: payload must be an object");
  }
}

/**
 * Adapter between beads_rust operations and framework WAL.
 *
 * Provides crash-resilient persistence for beads state transitions
 * by recording operations to WAL before they're committed to SQLite.
 */
export class BeadsWALAdapter {
  private readonly wal: IBeadsWAL;
  private readonly pathPrefix: string;
  private readonly verbose: boolean;

  constructor(wal: IBeadsWAL, config?: BeadsWALConfig) {
    this.wal = wal;
    this.pathPrefix = config?.pathPrefix ?? ".beads/wal";
    this.verbose = config?.verbose ?? false;
  }

  /**
   * Record a beads transition to WAL.
   *
   * @returns WAL sequence number
   * @throws if beadId or operation fails validation
   */
  async recordTransition(
    entry: Omit<BeadWALEntry, "id" | "timestamp" | "checksum">,
  ): Promise<number> {
    validateBeadId(entry.beadId);
    validateOperation(entry.operation);

    const fullEntry: BeadWALEntry = {
      ...entry,
      id: randomUUID(),
      timestamp: new Date().toISOString(),
      checksum: this.computeChecksum(entry.payload),
    };

    const seq = await this.wal.append(
      "write",
      `${this.pathPrefix}/${entry.beadId}/${fullEntry.id}.json`,
      Buffer.from(JSON.stringify(fullEntry)),
    );

    if (this.verbose) {
      console.log(`[beads-wal] recorded ${entry.operation} (seq=${seq})`);
    }

    return seq;
  }

  /**
   * Replay all beads transitions from WAL.
   * Returns entries sorted by timestamp. Invalid entries are skipped.
   */
  async replay(): Promise<BeadWALEntry[]> {
    const entries: BeadWALEntry[] = [];

    await this.wal.replay((walEntry: IBeadsWALEntry) => {
      if (walEntry.operation === "write" && walEntry.path.startsWith(this.pathPrefix)) {
        try {
          if (!walEntry.data) return;
          const jsonStr = Buffer.from(walEntry.data, "base64").toString("utf-8");
          const parsed: unknown = JSON.parse(jsonStr);
          validateWALEntry(parsed);
          const entry = parsed as BeadWALEntry;
          if (this.verifyChecksum(entry)) {
            entries.push(entry);
          }
        } catch {
          // Skip invalid entries
        }
      }
    });

    entries.sort((a, b) => a.timestamp.localeCompare(b.timestamp));
    return entries;
  }

  /**
   * Get transitions since a specific sequence number.
   */
  async getTransitionsSince(seq: number): Promise<BeadWALEntry[]> {
    if (!this.wal.getEntriesSince) {
      return []; // WAL doesn't support incremental queries
    }
    const walEntries = await this.wal.getEntriesSince(seq);
    const beadEntries: BeadWALEntry[] = [];

    for (const walEntry of walEntries) {
      if (
        walEntry.operation === "write" &&
        walEntry.path.startsWith(this.pathPrefix) &&
        walEntry.data
      ) {
        try {
          const jsonStr = Buffer.from(walEntry.data, "base64").toString("utf-8");
          const parsed: unknown = JSON.parse(jsonStr);
          validateWALEntry(parsed);
          const entry = parsed as BeadWALEntry;
          if (this.verifyChecksum(entry)) {
            beadEntries.push(entry);
          }
        } catch {
          // Skip invalid entries
        }
      }
    }

    return beadEntries;
  }

  /** Get the current WAL sequence number. */
  getCurrentSeq(): number {
    return this.wal.getStatus().seq;
  }

  /** Compute SHA-256 checksum of payload (truncated to 32 hex chars = 128 bits). */
  private computeChecksum(payload: Record<string, unknown>): string {
    return createHash("sha256").update(JSON.stringify(payload)).digest("hex").slice(0, 32);
  }

  /** Verify entry checksum matches payload. */
  private verifyChecksum(entry: BeadWALEntry): boolean {
    return entry.checksum === this.computeChecksum(entry.payload);
  }
}
