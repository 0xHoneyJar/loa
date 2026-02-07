/**
 * Timeout Enforcer — model-aware timeout governance with composable AbortSignals.
 *
 * Per SDD Section 4.3.5.
 */
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface TimeoutEnforcerConfig {
  defaultTimeoutMs?: number;
  modelTimeouts?: Record<string, number>;
  clock?: { now(): number };
}

export interface RunOptions {
  timeoutMs?: number;
  model?: string;
  signal?: AbortSignal;
}

// ── TimeoutEnforcer ──────────────────────────────────

export class TimeoutEnforcer {
  private readonly defaultTimeoutMs: number;
  private readonly modelTimeouts: Record<string, number>;
  private readonly clock: { now(): number };

  constructor(config?: TimeoutEnforcerConfig) {
    this.defaultTimeoutMs = config?.defaultTimeoutMs ?? 30_000;
    this.modelTimeouts = config?.modelTimeouts ?? {};
    this.clock = config?.clock ?? { now: () => Date.now() };
  }

  getTimeoutMs(model?: string): number {
    if (model && this.modelTimeouts[model] !== undefined) {
      return this.modelTimeouts[model];
    }
    return this.defaultTimeoutMs;
  }

  async run<T>(
    fn: (signal: AbortSignal) => Promise<T>,
    opts?: RunOptions,
  ): Promise<T> {
    const timeoutMs = opts?.timeoutMs ?? this.getTimeoutMs(opts?.model);
    const ac = new AbortController();

    // Compose with caller-provided signal
    let onExternalAbort: (() => void) | null = null;
    if (opts?.signal) {
      if (opts.signal.aborted) {
        ac.abort();
      } else {
        onExternalAbort = () => ac.abort();
        opts.signal.addEventListener("abort", onExternalAbort, { once: true });
      }
    }

    const timer = setTimeout(() => ac.abort(), timeoutMs);

    try {
      const result = await fn(ac.signal);
      return result;
    } catch (err: unknown) {
      if (ac.signal.aborted && !(opts?.signal?.aborted)) {
        // Timeout caused the abort (not the external signal)
        throw new LoaLibError(
          `Operation timed out after ${timeoutMs}ms`,
          "SCH_001",
          true,
        );
      }
      throw err;
    } finally {
      clearTimeout(timer);
      if (onExternalAbort && opts?.signal) {
        opts.signal.removeEventListener("abort", onExternalAbort);
      }
    }
  }
}

// ── Factory ──────────────────────────────────────────

export function createTimeoutEnforcer(config?: TimeoutEnforcerConfig): TimeoutEnforcer {
  return new TimeoutEnforcer(config);
}
