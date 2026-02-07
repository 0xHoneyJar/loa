/**
 * Graceful Shutdown — drain → sync → exit sequence.
 *
 * Configurable timeouts, injectable callbacks, force exit fallback.
 * Per SDD Section 4.5.5.
 */
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface GracefulShutdownConfig {
  /** Drain timeout in ms. Default: 5_000 */
  drainTimeoutMs?: number;
  /** Sync timeout in ms. Default: 10_000 */
  syncTimeoutMs?: number;
  /** Force exit timeout in ms. Default: 30_000 */
  forceTimeoutMs?: number;
  /** Drain callback — flush pending work */
  onDrain?: () => Promise<void>;
  /** Sync callback — persist state */
  onSync?: () => Promise<void>;
  /** Exit function. Default: process.exit */
  exit?: (code: number) => void;
  /** Logger. Default: console.error */
  log?: (msg: string) => void;
}

// ── Implementation ───────────────────────────────────

export class GracefulShutdown {
  private readonly drainTimeoutMs: number;
  private readonly syncTimeoutMs: number;
  private readonly forceTimeoutMs: number;
  private readonly onDrain: (() => Promise<void>) | undefined;
  private readonly onSync: (() => Promise<void>) | undefined;
  private readonly exit: (code: number) => void;
  private readonly log: (msg: string) => void;
  private shuttingDown = false;
  private registeredSignals: string[] = [];

  constructor(config?: GracefulShutdownConfig) {
    this.drainTimeoutMs = config?.drainTimeoutMs ?? 5_000;
    this.syncTimeoutMs = config?.syncTimeoutMs ?? 10_000;
    this.forceTimeoutMs = config?.forceTimeoutMs ?? 30_000;
    this.onDrain = config?.onDrain;
    this.onSync = config?.onSync;
    this.exit = config?.exit ?? ((code) => process.exit(code));
    this.log = config?.log ?? ((msg) => console.error(msg));
  }

  /** Register SIGTERM/SIGINT handlers */
  register(): void {
    const handler = () => { void this.shutdown(); };
    process.on("SIGTERM", handler);
    process.on("SIGINT", handler);
    this.registeredSignals = ["SIGTERM", "SIGINT"];
  }

  /** Execute drain → sync → exit sequence */
  async shutdown(): Promise<void> {
    if (this.shuttingDown) return;
    this.shuttingDown = true;

    // Force exit timer
    const forceTimer = setTimeout(() => {
      this.log("Force exit: shutdown exceeded timeout");
      this.exit(1);
    }, this.forceTimeoutMs);

    // Prevent force timer from keeping the process alive
    if (typeof forceTimer === "object" && "unref" in forceTimer) {
      forceTimer.unref();
    }

    try {
      // Step 1: Drain
      if (this.onDrain) {
        await this.raceTimeout(this.onDrain(), this.drainTimeoutMs, "drain");
      }

      // Step 2: Sync
      if (this.onSync) {
        await this.raceTimeout(this.onSync(), this.syncTimeoutMs, "sync");
      }

      clearTimeout(forceTimer);
      this.exit(0);
    } catch (err) {
      clearTimeout(forceTimer);
      const msg = err instanceof Error ? err.message : String(err);
      this.log(`Shutdown error: ${msg}`);
      this.exit(1);
    }
  }

  /** Whether shutdown is in progress */
  isShuttingDown(): boolean {
    return this.shuttingDown;
  }

  // ── Private ────────────────────────────────────────

  private raceTimeout(
    promise: Promise<void>,
    ms: number,
    label: string,
  ): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`${label} timed out after ${ms}ms`)),
        ms,
      );
      promise.then(
        () => { clearTimeout(timer); resolve(); },
        (e) => { clearTimeout(timer); reject(e); },
      );
    });
  }
}

// ── Factory ──────────────────────────────────────────

export function createGracefulShutdown(
  config?: GracefulShutdownConfig,
): GracefulShutdown {
  return new GracefulShutdown(config);
}
