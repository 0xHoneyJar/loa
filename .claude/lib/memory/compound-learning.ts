/**
 * Compound Learning Cycle — trajectory logging → pattern extraction → quality-gated persistence.
 * Per SDD Section 4.2.3.
 */
import type { MemoryEntry, GateResult } from "./quality-gates.js";

// ── Types ────────────────────────────────────────────

export interface Pattern {
  content: string;
  frequency: number;
  confidence: number;
  firstSeen: number;
  lastSeen: number;
  sources: string[];
}

export interface CompoundLearningConfig {
  qualityGates?: (entry: MemoryEntry) => GateResult;
  clock?: { now(): number };
  logger?: { info(msg: string): void };
  /** Maximum number of entries to retain. Oldest entries evicted when exceeded. Default: 10000 */
  maxEntries?: number;
}

// ── CompoundLearningCycle Class ──────────────────────

export class CompoundLearningCycle {
  private readonly entries: MemoryEntry[] = [];
  private readonly qualityGates?: (entry: MemoryEntry) => GateResult;
  private readonly clock: { now(): number };
  private readonly logger?: { info(msg: string): void };
  private readonly maxEntries: number;

  constructor(config?: CompoundLearningConfig) {
    this.qualityGates = config?.qualityGates;
    this.clock = config?.clock ?? { now: () => Date.now() };
    this.logger = config?.logger;
    this.maxEntries = config?.maxEntries ?? 10_000;
  }

  addTrajectoryEntry(entry: MemoryEntry): void {
    this.entries.push(entry);
    // Evict oldest entries when cap exceeded
    if (this.entries.length > this.maxEntries) {
      this.entries.splice(0, this.entries.length - this.maxEntries);
    }
    this.logger?.info(`Trajectory entry added: ${entry.source}`);
  }

  extractPatterns(): Pattern[] {
    // Group entries by normalized content (lowercase, trimmed)
    const groups = new Map<string, MemoryEntry[]>();

    for (const entry of this.entries) {
      const key = entry.content.toLowerCase().trim();
      const existing = groups.get(key);
      if (existing) {
        existing.push(entry);
      } else {
        groups.set(key, [entry]);
      }
    }

    // Convert groups with frequency > 1 to patterns
    const patterns: Pattern[] = [];
    for (const [, group] of groups) {
      if (group.length < 2) continue;

      const timestamps = group.map((e) => e.timestamp);
      const sources = [...new Set(group.map((e) => e.source))];

      patterns.push({
        content: group[0].content,
        frequency: group.length,
        confidence: Math.min(1, group.length / 5), // Confidence scales with frequency, max at 5
        firstSeen: timestamps.reduce((a, b) => Math.min(a, b), Infinity),
        lastSeen: timestamps.reduce((a, b) => Math.max(a, b), -Infinity),
        sources,
      });
    }

    // Sort by frequency descending
    patterns.sort((a, b) => b.frequency - a.frequency);
    return patterns;
  }

  getQualifiedLearnings(): MemoryEntry[] {
    if (!this.qualityGates) return [...this.entries];

    return this.entries.filter((entry) => {
      const result = this.qualityGates!(entry);
      return result.pass;
    });
  }

  getEntryCount(): number {
    return this.entries.length;
  }
}

export function createCompoundLearningCycle(
  config?: CompoundLearningConfig,
): CompoundLearningCycle {
  return new CompoundLearningCycle(config);
}
