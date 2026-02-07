/**
 * Context Tracker — token usage monitoring with configurable thresholds.
 * Per SDD Section 4.2.2.
 */

// ── Types ────────────────────────────────────────────

export interface ITokenCounter {
  count(text: string): number;
}

export type UsageLevel = "normal" | "warning" | "critical" | "emergency";

export interface ContextTrackerConfig {
  maxTokens: number;
  tokenCounter: ITokenCounter;
  thresholds?: { warning: number; critical: number; emergency: number };
  clock?: { now(): number };
}

// ── ContextTracker Class ─────────────────────────────

export class ContextTracker {
  private readonly maxTokens: number;
  private readonly tokenCounter: ITokenCounter;
  private readonly thresholds: { warning: number; critical: number; emergency: number };
  private totalUsed: number = 0;

  constructor(config: ContextTrackerConfig) {
    this.maxTokens = config.maxTokens;
    this.tokenCounter = config.tokenCounter;
    this.thresholds = config.thresholds ?? {
      warning: 0.6,
      critical: 0.7,
      emergency: 0.8,
    };
  }

  track(text: string): {
    tokens: number;
    totalUsed: number;
    level: UsageLevel;
  } {
    const tokens = this.tokenCounter.count(text);
    this.totalUsed += tokens;
    return {
      tokens,
      totalUsed: this.totalUsed,
      level: this.computeLevel(),
    };
  }

  getUsage(): {
    used: number;
    max: number;
    percent: number;
    level: UsageLevel;
  } {
    return {
      used: this.totalUsed,
      max: this.maxTokens,
      percent: this.maxTokens > 0 ? this.totalUsed / this.maxTokens : 0,
      level: this.computeLevel(),
    };
  }

  reset(): void {
    this.totalUsed = 0;
  }

  // ── Private ────────────────────────────────────────

  private computeLevel(): UsageLevel {
    const percent = this.maxTokens > 0 ? this.totalUsed / this.maxTokens : 0;
    if (percent >= this.thresholds.emergency) return "emergency";
    if (percent >= this.thresholds.critical) return "critical";
    if (percent >= this.thresholds.warning) return "warning";
    return "normal";
  }
}

export function createContextTracker(
  config: ContextTrackerConfig,
): ContextTracker {
  return new ContextTracker(config);
}
