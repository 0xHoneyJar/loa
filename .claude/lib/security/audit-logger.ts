/**
 * Audit Logger — integrity-verified JSONL logger with SHA-256 hash chaining.
 *
 * Provides integrity verification (detecting accidental corruption and
 * unauthorized modification by external processes), NOT tamper-proof guarantees
 * against a privileged attacker. Per SDD Section 4.1.2.
 *
 * Single-process assumption: one Node.js process writes to a given log path
 * at any time. The internal promise queue serializes concurrent calls within
 * one process only.
 */
import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  statSync,
  writeFileSync,
  fdatasyncSync,
  openSync,
  closeSync,
} from "node:fs";
import { dirname } from "node:path";
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface AuditEntry {
  timestamp: string;
  event: string;
  actor: string;
  data: Record<string, unknown>;
  previousHash: string;
  hash: string;
}

export interface AuditLoggerConfig {
  logPath: string;
  clock?: { now(): number };
  hmacKey?: Buffer;
  maxSegmentBytes?: number;     // Default: 10MB
  onDiskFull?: "block" | "warn"; // Default: 'block'
  /** If true, verify() returns valid:true even when unparseable lines are skipped. Default: false */
  lenientVerify?: boolean;
}

// ── Constants ────────────────────────────────────────

const GENESIS_HASH = "GENESIS";
const DEFAULT_MAX_SEGMENT_BYTES = 10 * 1024 * 1024; // 10MB
const LARGE_ENTRY_THRESHOLD = 64 * 1024; // 64KB — fsync after write

/** Constant-time hash comparison to prevent timing side-channel attacks (SEC-AUDIT TS-CRIT-01). */
function safeHashEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;

  const isHex = (s: string) => s.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(s);

  if (isHex(a) && isHex(b)) {
    const ba = Buffer.from(a, "hex");
    const bb = Buffer.from(b, "hex");
    if (ba.length !== bb.length) return false;
    return timingSafeEqual(ba, bb);
  }

  // Fallback for non-hex strings (e.g. GENESIS sentinel)
  const ba = Buffer.from(a, "utf8");
  const bb = Buffer.from(b, "utf8");
  if (ba.length !== bb.length) return false;
  return timingSafeEqual(ba, bb);
}

// ── AuditLogger Class ────────────────────────────────

export class AuditLogger {
  private readonly logPath: string;
  private readonly clock: { now(): number };
  private readonly hmacKey: Buffer | undefined;
  private readonly maxSegmentBytes: number;
  private readonly onDiskFull: "block" | "warn";
  private readonly lenientVerify: boolean;
  private previousHash: string = GENESIS_HASH;
  private currentSize: number = 0;
  private queue: Promise<void> = Promise.resolve();

  constructor(config: AuditLoggerConfig) {
    this.logPath = config.logPath;
    this.clock = config.clock ?? { now: () => Date.now() };
    this.hmacKey = config.hmacKey;
    this.maxSegmentBytes = config.maxSegmentBytes ?? DEFAULT_MAX_SEGMENT_BYTES;
    this.onDiskFull = config.onDiskFull ?? "block";
    this.lenientVerify = config.lenientVerify ?? false;

    // Ensure directory exists
    const dir = dirname(this.logPath);
    if (!existsSync(dir)) {
      mkdirSync(dir, { recursive: true });
    }

    // Crash recovery: detect and truncate incomplete last line
    this.recoverFromCrash();
  }

  async append(
    event: string,
    actor: string,
    data: Record<string, unknown>,
  ): Promise<void> {
    return this.enqueue(() => this.doAppend(event, actor, data));
  }

  async verify(): Promise<{
    valid: boolean;
    brokenAt?: number;
    entries: number;
    truncated?: number;
  }> {
    return this.enqueue(() => this.doVerify());
  }

  async rotate(): Promise<void> {
    return this.enqueue(() => this.doRotate());
  }

  async close(): Promise<void> {
    // Drain the queue
    await this.queue;
  }

  // ── Private: Queue ─────────────────────────────────

  private enqueue<T>(fn: () => T): Promise<T> {
    const result = this.queue.then(fn);
    // Update queue chain (ignore errors for chaining, they're thrown to caller)
    this.queue = result.then(
      () => {},
      () => {},
    );
    return result;
  }

  // ── Private: Append ────────────────────────────────

  private doAppend(
    event: string,
    actor: string,
    data: Record<string, unknown>,
  ): void {
    // Check rotation
    if (this.currentSize >= this.maxSegmentBytes) {
      this.doRotate();
    }

    const timestamp = new Date(this.clock.now()).toISOString();
    const entryWithoutHash = { timestamp, event, actor, data, previousHash: this.previousHash };
    const payload = JSON.stringify(entryWithoutHash);
    const hash = this.computeHash(this.previousHash, payload);

    const entry: AuditEntry = { ...entryWithoutHash, hash };
    const line = JSON.stringify(entry) + "\n";

    try {
      appendFileSync(this.logPath, line, { flag: "a" });

      // fsync for large entries to reduce torn-write window
      if (line.length > LARGE_ENTRY_THRESHOLD) {
        try {
          const fd = openSync(this.logPath, "r+");
          fdatasyncSync(fd);
          closeSync(fd);
        } catch {
          // Best effort — fsync failure is not fatal
        }
      }

      this.previousHash = hash;
      this.currentSize += Buffer.byteLength(line, "utf-8");
    } catch (err: unknown) {
      const error = err as NodeJS.ErrnoException;
      if (error.code === "ENOSPC") {
        if (this.onDiskFull === "block") {
          throw new LoaLibError(
            "Disk full — audit write blocked to preserve integrity",
            "SEC_002",
            true,
            error,
          );
        }
        // warn mode: log to stderr, don't throw
        process.stderr.write(`[audit-logger] WARN: disk full, entry dropped\n`);
        return;
      }
      throw error;
    }
  }

  // ── Private: Verify ────────────────────────────────

  private doVerify(): {
    valid: boolean;
    brokenAt?: number;
    entries: number;
    truncated?: number;
  } {
    if (!existsSync(this.logPath)) {
      return { valid: true, entries: 0 };
    }

    const content = readFileSync(this.logPath, "utf-8");
    const lines = content.split("\n").filter((l) => l.trim().length > 0);
    let prevHash = GENESIS_HASH;
    let truncated = 0;

    for (let i = 0; i < lines.length; i++) {
      let entry: AuditEntry;
      try {
        entry = JSON.parse(lines[i]);
      } catch {
        truncated++;
        continue;
      }

      if (!safeHashEqual(entry.previousHash, prevHash)) {
        return { valid: false, brokenAt: i, entries: lines.length, truncated };
      }

      const entryWithoutHash = {
        timestamp: entry.timestamp,
        event: entry.event,
        actor: entry.actor,
        data: entry.data,
        previousHash: entry.previousHash,
      };
      const payload = JSON.stringify(entryWithoutHash);
      const expectedHash = this.computeHash(prevHash, payload);

      if (!safeHashEqual(entry.hash, expectedHash)) {
        return { valid: false, brokenAt: i, entries: lines.length, truncated };
      }

      prevHash = entry.hash;
    }

    const valid = truncated > 0 ? this.lenientVerify : true;
    return { valid, entries: lines.length, ...(truncated > 0 ? { truncated } : {}) };
  }

  // ── Private: Rotate ────────────────────────────────

  private doRotate(): void {
    if (!existsSync(this.logPath)) return;

    const timestamp = new Date(this.clock.now()).toISOString().replace(/[:.]/g, "-");
    const rotatedPath = `${this.logPath}.${timestamp}.jsonl`;

    renameSync(this.logPath, rotatedPath);
    this.currentSize = 0;
    // previousHash carries forward — preserves chain continuity
  }

  // ── Private: Hash ──────────────────────────────────

  private computeHash(previousHash: string, payload: string): string {
    const data = previousHash + payload;
    if (this.hmacKey) {
      return createHmac("sha256", this.hmacKey).update(data).digest("hex");
    }
    return createHash("sha256").update(data).digest("hex");
  }

  // ── Private: Crash Recovery ────────────────────────

  private recoverFromCrash(): void {
    if (!existsSync(this.logPath)) {
      this.currentSize = 0;
      return;
    }

    const content = readFileSync(this.logPath, "utf-8");
    const lines = content.split("\n");

    // Remove trailing empty line from split
    if (lines.length > 0 && lines[lines.length - 1] === "") {
      lines.pop();
    }

    let truncatedCount = 0;
    const validLines: string[] = [];

    for (const line of lines) {
      if (line.trim().length === 0) continue;
      try {
        JSON.parse(line);
        validLines.push(line);
      } catch {
        // Incomplete/corrupt line — truncate
        truncatedCount++;
      }
    }

    if (truncatedCount > 0) {
      // Backup original file before truncation to preserve forensic evidence (SEC-AUDIT TS-HIGH-01)
      const corruptPath = `${this.logPath}.${new Date().toISOString().replace(/[:.]/g, "-")}.corrupt`;
      try {
        writeFileSync(corruptPath, content);
      } catch {
        // Best effort — backup failure should not prevent recovery
      }
      // Rewrite file with only valid lines
      writeFileSync(this.logPath, validLines.map((l) => l + "\n").join(""));
      process.stderr.write(
        `[audit-logger] SEC_003: truncated ${truncatedCount} incomplete line(s) on recovery (backup: ${corruptPath})\n`,
      );
    }

    // Restore chain state from last valid entry
    if (validLines.length > 0) {
      const lastEntry: AuditEntry = JSON.parse(validLines[validLines.length - 1]);
      this.previousHash = lastEntry.hash;
    }
    // Use statSync for accurate byte-level size (FR-4: fixes UTF-16 vs UTF-8 drift)
    this.currentSize = existsSync(this.logPath) ? statSync(this.logPath).size : 0;
  }
}

export function createAuditLogger(config: AuditLoggerConfig): AuditLogger {
  return new AuditLogger(config);
}
