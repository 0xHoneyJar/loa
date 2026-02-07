/**
 * WAL Pruner — multi-target WAL pruning with configurable limits.
 *
 * Sequential execution per target (single-writer safety).
 * Per SDD Section 4.5.4.
 */
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface WALEntry {
  timestamp: number;
  [key: string]: unknown;
}

export interface WALPruneTarget {
  /** Human-readable name */
  name: string;
  /** Read current entries */
  read(): Promise<WALEntry[]>;
  /** Write back surviving entries */
  write(entries: WALEntry[]): Promise<void>;
}

export interface PruneResult {
  total: number;
  perTarget: Map<string, number>;
}

export interface WALPrunerConfig {
  /** Max entries per target. Default: 10_000 */
  maxEntries?: number;
  /** Max age in ms. Default: 7 days */
  maxAgeMs?: number;
  /** Injectable clock. Default: Date.now */
  now?: () => number;
}

// ── Implementation ───────────────────────────────────

export class WALPruner {
  private readonly maxEntries: number;
  private readonly maxAgeMs: number;
  private readonly now: () => number;

  constructor(config?: WALPrunerConfig) {
    this.maxEntries = config?.maxEntries ?? 10_000;
    this.maxAgeMs = config?.maxAgeMs ?? 7 * 24 * 60 * 60 * 1000;
    this.now = config?.now ?? Date.now;
  }

  async prune(targets: WALPruneTarget[]): Promise<PruneResult> {
    let total = 0;
    const perTarget = new Map<string, number>();

    // Sequential execution per target (single-writer)
    for (const target of targets) {
      const entries = await target.read();
      const cutoff = this.now() - this.maxAgeMs;

      // Filter by age
      let survivors = entries.filter((e) => e.timestamp >= cutoff);

      // Cap by max entries (keep newest)
      if (survivors.length > this.maxEntries) {
        survivors.sort((a, b) => b.timestamp - a.timestamp);
        survivors = survivors.slice(0, this.maxEntries);
      }

      const pruned = entries.length - survivors.length;
      if (pruned > 0) {
        await target.write(survivors);
      }

      perTarget.set(target.name, pruned);
      total += pruned;
    }

    return { total, perTarget };
  }
}

// ── Factory ──────────────────────────────────────────

export function createWALPruner(config?: WALPrunerConfig): WALPruner {
  return new WALPruner(config);
}
