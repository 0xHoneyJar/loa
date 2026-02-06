/**
 * Framework WAL Manager — Segmented Write-Ahead Log
 *
 * Extracted from deploy/loa-identity/wal/wal-manager.ts with enhancements:
 * - Time-sortable entry IDs (no UUID dependency)
 * - Delta-based compaction (keep latest write per path)
 * - Disk pressure monitoring (warning/critical thresholds)
 * - replay() with sinceSeq + limit pagination
 * - flock locking with PID-file fallback
 * - Backwards-compatible UUID entry parsing
 */

import { existsSync } from "fs";
import {
  appendFile,
  readFile,
  writeFile,
  mkdir,
  rename,
  unlink,
  stat,
  readdir,
  open,
  type FileHandle,
} from "fs/promises";
import { join } from "path";
import type { WALEntry, WALOperation, WALCheckpoint, WALSegment } from "./wal-entry.js";
import { PersistenceError } from "../types.js";
import { compactEntries, compactionRatio } from "./wal-compaction.js";
import {
  generateEntryId,
  computeDataChecksum,
  computeEntryChecksum,
  verifyEntry,
} from "./wal-entry.js";
import {
  evaluateDiskPressure,
  type DiskPressureConfig,
  type DiskPressureStatus,
} from "./wal-pressure.js";

// ── flock binding (optional) ─────────────────────────────────

let flock: ((fd: number, operation: number) => Promise<void>) | null = null;
try {
  const fsExt = await import("fs-ext").catch(() => null);
  if (fsExt?.flock) {
    flock = (fd: number, operation: number): Promise<void> =>
      new Promise((resolve, reject) => {
        fsExt.flock(fd, operation, (err: Error | null) => {
          if (err) reject(err);
          else resolve();
        });
      });
  }
} catch {
  // fs-ext not available
}

const LOCK_EX = 2;
const LOCK_NB = 4;
const LOCK_UN = 8;

// ── Config ───────────────────────────────────────────────────

export interface WALManagerConfig {
  walDir: string;
  /** Max segment size in bytes. Default: 10MB */
  maxSegmentSize?: number;
  /** Max segment age in ms. Default: 1 hour */
  maxSegmentAge?: number;
  /** Max retained segments. Default: 10 */
  maxSegments?: number;
  /** Disk pressure thresholds */
  diskPressure?: Partial<DiskPressureConfig>;
}

// ── WAL Manager ──────────────────────────────────────────────

export class WALManager {
  private readonly walDir: string;
  private readonly maxSegmentSize: number;
  private readonly maxSegmentAge: number;
  private readonly maxSegments: number;
  private readonly pressureConfig: Partial<DiskPressureConfig>;

  private checkpoint: WALCheckpoint | null = null;
  private currentSegmentPath: string | null = null;
  private currentSegmentSize = 0;
  private seq = 0;
  private lockHandle: FileHandle | null = null;
  private initialized = false;
  private initPromise: Promise<void> | null = null;
  private writeChain: Promise<number> = Promise.resolve(0);

  constructor(config: WALManagerConfig) {
    this.walDir = config.walDir;
    this.maxSegmentSize = config.maxSegmentSize ?? 10 * 1024 * 1024;
    this.maxSegmentAge = config.maxSegmentAge ?? 60 * 60 * 1000;
    this.maxSegments = config.maxSegments ?? 10;
    this.pressureConfig = config.diskPressure ?? {};
  }

  // ── Lifecycle ────────────────────────────────────────────

  async initialize(): Promise<void> {
    if (this.initialized) return;
    if (this.initPromise) return this.initPromise;
    this.initPromise = this._doInitialize();
    return this.initPromise;
  }

  private async _doInitialize(): Promise<void> {
    if (!existsSync(this.walDir)) {
      await mkdir(this.walDir, { recursive: true });
    }

    await this.acquireLock();
    await this.loadCheckpoint();

    if (this.checkpoint!.rotationPhase !== "none") {
      await this.recoverFromInterruptedRotation();
    }

    if (!this.checkpoint!.activeSegment) {
      await this.createNewSegment();
    } else {
      this.currentSegmentPath = join(this.walDir, this.checkpoint!.activeSegment);
      if (existsSync(this.currentSegmentPath)) {
        const stats = await stat(this.currentSegmentPath);
        this.currentSegmentSize = stats.size;
      }
    }

    this.seq = this.checkpoint!.lastSeq;
    this.initialized = true;
  }

  async shutdown(): Promise<void> {
    if (!this.initialized) return;
    await this.saveCheckpoint();
    await this.releaseLock();
    this.initialized = false;
  }

  // ── Write Operations ─────────────────────────────────────

  /**
   * Append an entry. Writes are serialized via a promise chain to prevent
   * interleaved file writes (single-writer pattern matches flock design).
   */
  append(operation: WALOperation, path: string, data?: Buffer): Promise<number> {
    // Chain writes to prevent concurrent file corruption
    const next = this.writeChain.then(() => this._doAppend(operation, path, data));
    this.writeChain = next.catch(() => 0); // Keep chain alive on error
    return next;
  }

  private async _doAppend(operation: WALOperation, path: string, data?: Buffer): Promise<number> {
    if (!this.initialized) await this.initialize();

    // Check disk pressure
    const pressure = this.getDiskPressure();
    if (pressure === "critical") {
      throw new PersistenceError(
        "DISK_PRESSURE_CRITICAL",
        `WAL disk pressure critical (${this.getTotalSize()} bytes). Compact or free space.`,
      );
    }
    if (pressure === "warning") {
      await this.compact();
    }

    await this.maybeRotate();

    const entry: Omit<WALEntry, "entryChecksum"> = {
      id: generateEntryId(),
      seq: ++this.seq,
      timestamp: new Date().toISOString(),
      operation,
      path,
    };

    if (data) {
      entry.checksum = computeDataChecksum(data);
      entry.data = data.toString("base64");
    }

    const entryChecksum = computeEntryChecksum(entry);
    const fullEntry: WALEntry = { ...entry, entryChecksum };

    const line = JSON.stringify(fullEntry) + "\n";
    await appendFile(this.currentSegmentPath!, line, "utf-8");
    await this.fsyncFile(this.currentSegmentPath!);

    this.currentSegmentSize += Buffer.byteLength(line);
    this.checkpoint!.lastSeq = this.seq;

    const activeSegment = this.checkpoint!.segments.find(
      (s) => s.id === this.checkpoint!.activeSegment,
    );
    if (activeSegment) {
      activeSegment.size = this.currentSegmentSize;
      activeSegment.entries++;
    }

    return this.seq;
  }

  // ── Read Operations ──────────────────────────────────────

  /**
   * Replay WAL entries, optionally starting from a sequence number
   * and limited to a maximum count.
   */
  async replay(
    callback: (entry: WALEntry) => Promise<void>,
    options?: { sinceSeq?: number; limit?: number },
  ): Promise<{ replayed: number; errors: number }> {
    if (!this.initialized) await this.initialize();

    const sinceSeq = options?.sinceSeq ?? 0;
    const limit = options?.limit ?? Infinity;
    let replayed = 0;
    let errors = 0;

    const sortedSegments = [...this.checkpoint!.segments].sort(
      (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
    );

    for (const segment of sortedSegments) {
      const segPath = join(this.walDir, segment.id);
      if (!existsSync(segPath)) continue;

      const content = await readFile(segPath, "utf-8");
      const lines = content.split("\n").filter(Boolean);

      for (const line of lines) {
        if (replayed >= limit) return { replayed, errors };

        try {
          const entry = JSON.parse(line) as WALEntry;

          if (entry.seq <= sinceSeq) continue;

          if (!verifyEntry(entry)) {
            errors++;
            continue; // Skip corrupt entry, keep replaying valid ones
          }

          await callback(entry);
          replayed++;
        } catch {
          errors++;
        }
      }
    }

    return { replayed, errors };
  }

  /**
   * Get entries since a given sequence number, with optional limit.
   */
  async getEntriesSince(sinceSeq: number, limit?: number): Promise<WALEntry[]> {
    if (!this.initialized) await this.initialize();

    const entries: WALEntry[] = [];
    const max = limit ?? Infinity;

    // Sort segments by creation time (matches replay() ordering)
    const sortedSegments = [...this.checkpoint!.segments].sort(
      (a, b) => new Date(a.createdAt).getTime() - new Date(b.createdAt).getTime(),
    );

    for (const segment of sortedSegments) {
      const segPath = join(this.walDir, segment.id);
      if (!existsSync(segPath)) continue;

      const content = await readFile(segPath, "utf-8");
      const lines = content.split("\n").filter(Boolean);

      for (const line of lines) {
        if (entries.length >= max) return entries.sort((a, b) => a.seq - b.seq);

        try {
          const entry = JSON.parse(line) as WALEntry;
          if (entry.seq > sinceSeq) {
            entries.push(entry);
          }
        } catch {
          // Skip invalid entries
        }
      }
    }

    return entries.sort((a, b) => a.seq - b.seq);
  }

  // ── Compaction ───────────────────────────────────────────

  /**
   * Compact all closed segments by keeping only the latest write per path.
   * The active segment is never compacted (it's still receiving writes).
   */
  async compact(): Promise<{ originalEntries: number; compactedEntries: number; ratio: number }> {
    if (!this.initialized) await this.initialize();

    const closedSegments = this.checkpoint!.segments.filter(
      (s) => s.closedAt && s.id !== this.checkpoint!.activeSegment,
    );

    if (closedSegments.length === 0) return { originalEntries: 0, compactedEntries: 0, ratio: 0 };

    // Read all entries from closed segments
    const allEntries: WALEntry[] = [];
    for (const segment of closedSegments) {
      const segPath = join(this.walDir, segment.id);
      if (!existsSync(segPath)) continue;

      const content = await readFile(segPath, "utf-8");
      const lines = content.split("\n").filter(Boolean);

      for (const line of lines) {
        try {
          allEntries.push(JSON.parse(line));
        } catch {
          /* skip */
        }
      }
    }

    const compacted = compactEntries(allEntries);
    const ratio = compactionRatio(allEntries.length, compacted.length);

    if (ratio === 0)
      return { originalEntries: allEntries.length, compactedEntries: compacted.length, ratio };

    // Write compacted entries to a new segment
    const compactedSegId = `segment-compacted-${Date.now()}.wal`;
    const compactedPath = join(this.walDir, compactedSegId);
    const lines = compacted.map((e) => JSON.stringify(e)).join("\n") + "\n";
    await writeFile(compactedPath, lines, "utf-8");
    await this.fsyncFile(compactedPath);

    // Remove old closed segments
    for (const segment of closedSegments) {
      const segPath = join(this.walDir, segment.id);
      try {
        await unlink(segPath);
      } catch {
        /* ok */
      }
      const idx = this.checkpoint!.segments.findIndex((s) => s.id === segment.id);
      if (idx !== -1) this.checkpoint!.segments.splice(idx, 1);
    }

    // Add compacted segment
    this.checkpoint!.segments.unshift({
      id: compactedSegId,
      path: compactedPath,
      size: Buffer.byteLength(lines),
      entries: compacted.length,
      createdAt: new Date().toISOString(),
      closedAt: new Date().toISOString(),
    });

    await this.saveCheckpoint();

    return { originalEntries: allEntries.length, compactedEntries: compacted.length, ratio };
  }

  // ── Disk Pressure ────────────────────────────────────────

  getDiskPressure(): DiskPressureStatus {
    return evaluateDiskPressure(this.getTotalSize(), this.pressureConfig);
  }

  getTotalSize(): number {
    return this.checkpoint?.segments.reduce((sum, s) => sum + s.size, 0) ?? 0;
  }

  // ── Status ───────────────────────────────────────────────

  getStatus(): {
    seq: number;
    activeSegment: string;
    segmentCount: number;
    totalSize: number;
    diskPressure: DiskPressureStatus;
  } {
    return {
      seq: this.seq,
      activeSegment: this.checkpoint?.activeSegment ?? "",
      segmentCount: this.checkpoint?.segments.length ?? 0,
      totalSize: this.getTotalSize(),
      diskPressure: this.getDiskPressure(),
    };
  }

  // ── Private: Locking ─────────────────────────────────────

  private async acquireLock(): Promise<void> {
    const lockPath = join(this.walDir, "wal.lock");
    const pidPath = join(this.walDir, "wal.pid");

    this.lockHandle = await open(lockPath, "w");

    if (flock) {
      try {
        await flock(this.lockHandle.fd, LOCK_EX | LOCK_NB);
      } catch (e: unknown) {
        const err = e as NodeJS.ErrnoException;
        if (err.code === "EAGAIN" || err.code === "EWOULDBLOCK") {
          await this.lockHandle.close();
          this.lockHandle = null;

          if (existsSync(pidPath)) {
            const existingPid = await readFile(pidPath, "utf-8");
            throw new PersistenceError(
              "WAL_LOCK_FAILED",
              `WAL locked by process ${existingPid.trim()}.`,
            );
          }
          throw new PersistenceError("WAL_LOCK_FAILED", "WAL locked by another process.");
        }
      }
    }

    // PID-file fallback
    if (existsSync(pidPath)) {
      const existingPid = await readFile(pidPath, "utf-8");
      const pid = parseInt(existingPid.trim(), 10);

      try {
        process.kill(pid, 0);
        if (!flock) {
          if (this.lockHandle) {
            await this.lockHandle.close();
            this.lockHandle = null;
          }
          throw new PersistenceError("WAL_LOCK_FAILED", `WAL locked by process ${pid}.`);
        }
      } catch (e: unknown) {
        if ((e as NodeJS.ErrnoException).code !== "ESRCH") throw e;
        // Dead process, take over
      }
    }

    const tempPid = `${pidPath}.tmp.${process.pid}`;
    await writeFile(tempPid, process.pid.toString(), "utf-8");
    await rename(tempPid, pidPath);
  }

  private async releaseLock(): Promise<void> {
    const pidPath = join(this.walDir, "wal.pid");

    if (this.lockHandle) {
      try {
        if (flock) await flock(this.lockHandle.fd, LOCK_UN);
        await this.lockHandle.close();
        this.lockHandle = null;
      } catch {
        /* ok */
      }
    }

    try {
      const existingPid = await readFile(pidPath, "utf-8");
      if (parseInt(existingPid.trim(), 10) === process.pid) {
        await unlink(pidPath);
      }
    } catch {
      /* ok */
    }
  }

  // ── Private: Checkpoint ──────────────────────────────────

  private async loadCheckpoint(): Promise<void> {
    const cpPath = join(this.walDir, "checkpoint.json");

    if (existsSync(cpPath)) {
      const content = await readFile(cpPath, "utf-8");
      try {
        const parsed = JSON.parse(content);
        // Validate required shape before assignment
        if (
          parsed &&
          typeof parsed === "object" &&
          Array.isArray(parsed.segments) &&
          typeof parsed.lastSeq === "number"
        ) {
          this.checkpoint = parsed;
        } else {
          this.checkpoint = this.emptyCheckpoint();
        }
      } catch {
        // Corrupt checkpoint file — start fresh
        this.checkpoint = this.emptyCheckpoint();
      }
    } else {
      this.checkpoint = this.emptyCheckpoint();
      await this.saveCheckpoint();
    }
  }

  private emptyCheckpoint(): WALCheckpoint {
    return {
      lastSeq: 0,
      activeSegment: "",
      segments: [],
      lastCheckpointAt: new Date().toISOString(),
      rotationPhase: "none",
    };
  }

  private async saveCheckpoint(): Promise<void> {
    if (!this.checkpoint) return;

    const cpPath = join(this.walDir, "checkpoint.json");
    const tmpPath = `${cpPath}.tmp`;

    this.checkpoint.lastCheckpointAt = new Date().toISOString();
    await writeFile(tmpPath, JSON.stringify(this.checkpoint, null, 2), "utf-8");
    await this.fsyncFile(tmpPath);
    await rename(tmpPath, cpPath);
  }

  // ── Private: Segments ────────────────────────────────────

  private async createNewSegment(): Promise<void> {
    const segId = `segment-${Date.now()}.wal`;
    const segPath = join(this.walDir, segId);

    await writeFile(segPath, "", "utf-8");

    this.checkpoint!.segments.push({
      id: segId,
      path: segPath,
      size: 0,
      entries: 0,
      createdAt: new Date().toISOString(),
    });
    this.checkpoint!.activeSegment = segId;
    this.currentSegmentPath = segPath;
    this.currentSegmentSize = 0;

    await this.saveCheckpoint();
  }

  private async maybeRotate(): Promise<void> {
    if (!this.currentSegmentPath) return;

    const active = this.checkpoint!.segments.find((s) => s.id === this.checkpoint!.activeSegment);
    if (!active) return;

    const age = Date.now() - new Date(active.createdAt).getTime();
    if (this.currentSegmentSize >= this.maxSegmentSize || age >= this.maxSegmentAge) {
      await this.rotate();
    }
  }

  private async rotate(): Promise<void> {
    this.checkpoint!.rotationPhase = "checkpoint_written";
    await this.saveCheckpoint();

    this.checkpoint!.rotationPhase = "rotating";
    const active = this.checkpoint!.segments.find((s) => s.id === this.checkpoint!.activeSegment);
    if (active) active.closedAt = new Date().toISOString();

    await this.createNewSegment();
    await this.cleanupOldSegments();

    this.checkpoint!.rotationPhase = "none";
    await this.saveCheckpoint();
  }

  private async recoverFromInterruptedRotation(): Promise<void> {
    if (this.checkpoint!.rotationPhase === "checkpoint_written") {
      this.checkpoint!.rotationPhase = "none";
    } else if (this.checkpoint!.rotationPhase === "rotating") {
      await this.createNewSegment();
      await this.cleanupOldSegments();
      this.checkpoint!.rotationPhase = "none";
    }
    await this.saveCheckpoint();
  }

  private async cleanupOldSegments(): Promise<void> {
    const closed = this.checkpoint!.segments.filter((s) => s.closedAt);
    if (closed.length <= this.maxSegments) return;

    closed.sort((a, b) => new Date(a.closedAt!).getTime() - new Date(b.closedAt!).getTime());

    const toRemove = closed.slice(0, closed.length - this.maxSegments);
    for (const seg of toRemove) {
      try {
        const segPath = join(this.walDir, seg.id);
        await unlink(segPath);
      } catch {
        /* ok */
      }
      const idx = this.checkpoint!.segments.findIndex((s) => s.id === seg.id);
      if (idx !== -1) this.checkpoint!.segments.splice(idx, 1);
    }
  }

  // ── Private: Fsync ───────────────────────────────────────

  private async fsyncFile(filePath: string): Promise<void> {
    try {
      const fd = await open(filePath, "r");
      try {
        await fd.sync();
      } finally {
        await fd.close();
      }
    } catch {
      /* Fsync may not be supported */
    }
  }
}

/**
 * Create a WALManager with default config.
 */
export function createWALManager(walDir: string): WALManager {
  return new WALManager({ walDir });
}
