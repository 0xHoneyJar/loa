/**
 * Standalone Circuit Breaker with lazy timeout checking.
 *
 * States: CLOSED → OPEN (after N failures) → HALF_OPEN (after timeout) → CLOSED
 *
 * No timers — state transitions happen lazily on execute()/getState() calls.
 * This avoids timer leaks and makes the component fully testable with fake clocks.
 *
 * Extracted from deploy/loa-identity/scheduler/scheduler.ts
 */

import { PersistenceError } from "./types.js";

// ── Types ────────────────────────────────────────────────────

export type CircuitBreakerState = "CLOSED" | "OPEN" | "HALF_OPEN";

export interface CircuitBreakerConfig {
  /** Number of consecutive failures before opening the circuit. Default: 3 */
  maxFailures: number;
  /** Time in ms before attempting half-open probe. Default: 5 minutes */
  resetTimeMs: number;
  /** Number of successful probes in HALF_OPEN before closing. Default: 1 */
  halfOpenRetries: number;
  /** Optional task ID for cross-repo tracking (finn convergence) */
  taskId?: string;
  /** Enable probe counter for convergence monitoring. Default: false */
  enableProbeCounter?: boolean;
}

export type CircuitBreakerStateChangeCallback = (
  from: CircuitBreakerState,
  to: CircuitBreakerState,
) => void;

// ── Defaults ─────────────────────────────────────────────────

const DEFAULT_CONFIG: CircuitBreakerConfig = {
  maxFailures: 3,
  resetTimeMs: 5 * 60 * 1000,
  halfOpenRetries: 1,
};

// ── Implementation ───────────────────────────────────────────

export class CircuitBreaker {
  private state: CircuitBreakerState = "CLOSED";
  private consecutiveFailures = 0;
  private halfOpenSuccesses = 0;
  private lastFailureTime = -1;
  private readonly config: CircuitBreakerConfig;
  private onStateChange?: CircuitBreakerStateChangeCallback;
  private nowFn: () => number;
  private readonly taskId: string | undefined;
  private probeCount = 0;

  constructor(
    config?: Partial<CircuitBreakerConfig>,
    options?: {
      onStateChange?: CircuitBreakerStateChangeCallback;
      /** Injectable clock for testing. Defaults to Date.now */
      now?: () => number;
    },
  ) {
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.onStateChange = options?.onStateChange;
    this.nowFn = options?.now ?? Date.now;
    this.taskId = config?.taskId;
  }

  /**
   * Execute a function through the circuit breaker.
   * Throws PersistenceError with code CB_OPEN if the circuit is open.
   */
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    const currentState = this.getState();

    if (currentState === "OPEN") {
      throw new PersistenceError(
        "CB_OPEN",
        `Circuit breaker is OPEN (${this.consecutiveFailures} failures, ` +
          `resets in ${this.msUntilReset()}ms)`,
      );
    }

    if (currentState === "HALF_OPEN" && this.config.enableProbeCounter) {
      this.probeCount++;
    }

    try {
      const result = await fn();
      this.recordSuccess();
      return result;
    } catch (error) {
      this.recordFailure();
      throw error;
    }
  }

  /**
   * Record a successful operation.
   */
  recordSuccess(): void {
    if (this.state === "HALF_OPEN") {
      this.halfOpenSuccesses++;
      if (this.halfOpenSuccesses >= this.config.halfOpenRetries) {
        this.transition("CLOSED");
        this.consecutiveFailures = 0;
        this.halfOpenSuccesses = 0;
      }
    } else {
      this.consecutiveFailures = 0;
    }
  }

  /**
   * Record a failed operation.
   */
  recordFailure(): void {
    this.consecutiveFailures++;
    this.lastFailureTime = this.nowFn();

    if (this.state === "HALF_OPEN") {
      // Half-open probe failed — go back to OPEN
      this.halfOpenSuccesses = 0;
      this.transition("OPEN");
    } else if (this.consecutiveFailures >= this.config.maxFailures) {
      this.transition("OPEN");
    }
  }

  /**
   * Get the current state, lazily transitioning OPEN → HALF_OPEN if timeout elapsed.
   */
  getState(): CircuitBreakerState {
    if (this.state === "OPEN" && this.lastFailureTime >= 0) {
      const elapsed = this.nowFn() - this.lastFailureTime;
      if (elapsed >= this.config.resetTimeMs) {
        this.transition("HALF_OPEN");
        this.halfOpenSuccesses = 0;
      }
    }
    return this.state;
  }

  /**
   * Force-reset the circuit breaker to CLOSED state.
   */
  reset(): void {
    this.consecutiveFailures = 0;
    this.halfOpenSuccesses = 0;
    this.lastFailureTime = -1;
    this.transition("CLOSED");
  }

  /**
   * Get the number of consecutive failures.
   */
  getFailureCount(): number {
    return this.consecutiveFailures;
  }

  /**
   * Get the optional task ID (finn convergence).
   */
  getTaskId(): string | undefined {
    return this.taskId;
  }

  /**
   * Get the number of HALF_OPEN probe attempts (only counted when enableProbeCounter is true).
   */
  getProbeCount(): number {
    return this.probeCount;
  }

  // ── Private ──────────────────────────────────────────────

  private transition(to: CircuitBreakerState): void {
    if (this.state === to) return;
    const from = this.state;
    this.state = to;
    this.onStateChange?.(from, to);
  }

  private msUntilReset(): number {
    if (this.state !== "OPEN" || this.lastFailureTime < 0) return 0;
    const elapsed = this.nowFn() - this.lastFailureTime;
    return Math.max(0, this.config.resetTimeMs - elapsed);
  }
}
