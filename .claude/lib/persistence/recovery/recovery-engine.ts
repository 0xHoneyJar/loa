/**
 * Recovery Engine — multi-source cascade with loop detection.
 *
 * State machine: START → source1 → source2 → ... → DEGRADED
 * Loop detection prevents infinite recovery cycles.
 *
 * Extracted from deploy/loa-identity/recovery/recovery-engine.ts
 */

import type { IRecoverySource } from "./recovery-source.js";
import { PersistenceError } from "../types.js";

export type RecoveryState = "IDLE" | "RECOVERING" | "RUNNING" | "DEGRADED" | "LOOP_DETECTED";

export interface RecoveryEngineConfig {
  /** Ordered list of recovery sources (first = highest priority) */
  sources: IRecoverySource[];
  /** Max failures within window before loop detection triggers. Default: 3 */
  loopMaxFailures?: number;
  /** Loop detection window in ms. Default: 10 minutes */
  loopWindowMs?: number;
  /** Callback on state changes */
  onStateChange?: (from: RecoveryState, to: RecoveryState) => void;
  /** Callback on recovery events */
  onEvent?: (event: string, data?: Record<string, unknown>) => void;
}

interface FailureRecord {
  timestamp: number;
  source: string;
  reason: string;
}

export class RecoveryEngine {
  private state: RecoveryState = "IDLE";
  private readonly sources: IRecoverySource[];
  private readonly loopMaxFailures: number;
  private readonly loopWindowMs: number;
  private readonly onStateChange?: (from: RecoveryState, to: RecoveryState) => void;
  private readonly onEvent?: (event: string, data?: Record<string, unknown>) => void;
  private failures: FailureRecord[] = [];
  private nowFn: () => number;

  constructor(config: RecoveryEngineConfig, options?: { now?: () => number }) {
    this.sources = config.sources;
    this.loopMaxFailures = config.loopMaxFailures ?? 3;
    this.loopWindowMs = config.loopWindowMs ?? 10 * 60 * 1000;
    this.onStateChange = config.onStateChange;
    this.onEvent = config.onEvent;
    this.nowFn = options?.now ?? Date.now;
  }

  /**
   * Run recovery cascade. Returns the restored files or null on failure.
   */
  async run(): Promise<{
    state: RecoveryState;
    source: string | null;
    files: Map<string, Buffer> | null;
  }> {
    // Check loop detection
    if (this.isLoopDetected()) {
      this.transition("LOOP_DETECTED");
      this.onEvent?.("loop_detected", { failures: this.failures.length });
      return { state: "LOOP_DETECTED", source: null, files: null };
    }

    this.transition("RECOVERING");

    for (const source of this.sources) {
      this.onEvent?.("trying_source", { name: source.name });

      const available = await source.isAvailable();
      if (!available) {
        this.onEvent?.("source_unavailable", { name: source.name });
        continue;
      }

      try {
        const files = await source.restore();
        if (files && files.size > 0) {
          this.transition("RUNNING");
          this.onEvent?.("restored", { name: source.name, fileCount: files.size });
          return { state: "RUNNING", source: source.name, files };
        }

        this.recordFailure(source.name, "restore returned empty");
      } catch (e) {
        const reason = e instanceof Error ? e.message : String(e);
        this.recordFailure(source.name, reason);
        this.onEvent?.("source_failed", { name: source.name, reason });
      }
    }

    // All sources failed
    this.transition("DEGRADED");
    this.onEvent?.("all_sources_failed", {
      sourceCount: this.sources.length,
      totalFailures: this.failures.length,
    });

    return { state: "DEGRADED", source: null, files: null };
  }

  getState(): RecoveryState {
    return this.state;
  }

  /**
   * Check if loop detection has triggered.
   */
  private isLoopDetected(): boolean {
    const now = this.nowFn();
    const windowStart = now - this.loopWindowMs;
    const recentFailures = this.failures.filter((f) => f.timestamp >= windowStart);
    return recentFailures.length >= this.loopMaxFailures;
  }

  private recordFailure(source: string, reason: string): void {
    this.failures.push({
      timestamp: this.nowFn(),
      source,
      reason,
    });

    // Prune stale failure records to prevent unbounded memory growth
    const windowStart = this.nowFn() - this.loopWindowMs;
    if (this.failures.length > this.loopMaxFailures * 3) {
      this.failures = this.failures.filter((f) => f.timestamp >= windowStart);
    }
  }

  private transition(to: RecoveryState): void {
    if (this.state === to) return;
    const from = this.state;
    this.state = to;
    this.onStateChange?.(from, to);
  }
}
