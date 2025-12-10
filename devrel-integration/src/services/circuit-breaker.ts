/**
 * Circuit Breaker Pattern Implementation
 *
 * Implements HIGH-004: Error Handling for Failed Translations
 *
 * Provides fault tolerance by preventing cascading failures when a service
 * is experiencing issues. The circuit breaker has three states:
 *
 * - CLOSED: Normal operation, requests pass through
 * - OPEN: Service is failing, requests fail fast without attempting
 * - HALF_OPEN: Testing if service has recovered
 *
 * Features:
 * - Automatic state transitions based on failure/success rates
 * - Configurable thresholds and timeouts
 * - Detailed state tracking and logging
 * - Event callbacks for monitoring
 */

import logger from '../utils/logger';

/**
 * Circuit breaker states
 */
export enum CircuitState {
  CLOSED = 'CLOSED', // Normal operation
  OPEN = 'OPEN', // Failing, block requests
  HALF_OPEN = 'HALF_OPEN', // Testing recovery
}

/**
 * Circuit breaker configuration
 */
export interface CircuitBreakerConfig {
  /**
   * Number of failures before opening circuit (default: 5)
   */
  failureThreshold?: number;

  /**
   * Number of successes in HALF_OPEN state to close circuit (default: 2)
   */
  successThreshold?: number;

  /**
   * Time in milliseconds to wait before transitioning from OPEN to HALF_OPEN (default: 60000ms = 1 minute)
   */
  resetTimeoutMs?: number;

  /**
   * Rolling window size for tracking failures (default: 10)
   * Only the last N requests are considered for failure rate
   */
  rollingWindowSize?: number;

  /**
   * Callback invoked when circuit opens
   */
  onOpen?: (error: Error) => void;

  /**
   * Callback invoked when circuit closes
   */
  onClose?: () => void;

  /**
   * Callback invoked when circuit enters HALF_OPEN state
   */
  onHalfOpen?: () => void;
}

/**
 * Circuit breaker statistics
 */
export interface CircuitBreakerStats {
  state: CircuitState;
  failureCount: number;
  successCount: number;
  totalRequests: number;
  lastFailureTime?: Date;
  lastSuccessTime?: Date;
  openedAt?: Date;
  halfOpenedAt?: Date;
  closedAt?: Date;
}

/**
 * Circuit breaker error thrown when circuit is OPEN
 */
export class CircuitBreakerOpenError extends Error {
  constructor(serviceName: string, lastError?: Error) {
    super(
      `Circuit breaker is OPEN for ${serviceName}. ` +
      `Service is currently unavailable. ` +
      (lastError ? `Last error: ${lastError.message}` : '')
    );
    this.name = 'CircuitBreakerOpenError';
  }
}

/**
 * Default configuration
 */
const DEFAULT_CONFIG: Required<CircuitBreakerConfig> = {
  failureThreshold: 5,
  successThreshold: 2,
  resetTimeoutMs: 60000, // 1 minute
  rollingWindowSize: 10,
  onOpen: (error: Error) => {
    logger.error('Circuit breaker opened', { error: error.message });
  },
  onClose: () => {
    logger.info('Circuit breaker closed');
  },
  onHalfOpen: () => {
    logger.info('Circuit breaker half-open (testing recovery)');
  },
};

/**
 * Circuit breaker implementation
 */
export class CircuitBreaker {
  private config: Required<CircuitBreakerConfig>;
  private state: CircuitState = CircuitState.CLOSED;
  private failureCount: number = 0;
  private successCount: number = 0;
  private totalRequests: number = 0;
  private lastFailureTime?: Date;
  private lastSuccessTime?: Date;
  private openedAt?: Date;
  private halfOpenedAt?: Date;
  private closedAt?: Date;
  private lastError?: Error;
  private resetTimer?: NodeJS.Timeout;
  private recentResults: boolean[] = []; // true = success, false = failure

  constructor(
    private serviceName: string,
    config?: CircuitBreakerConfig
  ) {
    this.config = {
      ...DEFAULT_CONFIG,
      ...config,
      onOpen: config?.onOpen || DEFAULT_CONFIG.onOpen,
      onClose: config?.onClose || DEFAULT_CONFIG.onClose,
      onHalfOpen: config?.onHalfOpen || DEFAULT_CONFIG.onHalfOpen,
    };

    logger.info('Circuit breaker initialized', {
      serviceName: this.serviceName,
      config: this.config,
    });
  }

  /**
   * Execute a function with circuit breaker protection
   */
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    // Check if circuit is OPEN
    if (this.state === CircuitState.OPEN) {
      // Check if reset timeout has elapsed
      if (this.shouldAttemptReset()) {
        this.transitionToHalfOpen();
      } else {
        throw new CircuitBreakerOpenError(this.serviceName, this.lastError);
      }
    }

    // Attempt to execute the function
    this.totalRequests++;

    try {
      const result = await fn();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure(error instanceof Error ? error : new Error(String(error)));
      throw error;
    }
  }

  /**
   * Handle successful execution
   */
  private onSuccess(): void {
    this.lastSuccessTime = new Date();
    this.recordResult(true);

    logger.debug('Circuit breaker: request succeeded', {
      serviceName: this.serviceName,
      state: this.state,
      successCount: this.successCount,
    });

    if (this.state === CircuitState.HALF_OPEN) {
      this.successCount++;

      // Check if we should close the circuit
      if (this.successCount >= this.config.successThreshold) {
        this.transitionToClosed();
      }
    } else if (this.state === CircuitState.CLOSED) {
      // Reset failure count on success in CLOSED state
      this.failureCount = 0;
    }
  }

  /**
   * Handle failed execution
   */
  private onFailure(error: Error): void {
    this.lastFailureTime = new Date();
    this.lastError = error;
    this.recordResult(false);

    logger.warn('Circuit breaker: request failed', {
      serviceName: this.serviceName,
      state: this.state,
      failureCount: this.failureCount,
      error: error.message,
    });

    if (this.state === CircuitState.HALF_OPEN) {
      // Any failure in HALF_OPEN immediately opens circuit again
      this.transitionToOpen(error);
    } else if (this.state === CircuitState.CLOSED) {
      this.failureCount++;

      // Check if we should open the circuit
      const recentFailureRate = this.getRecentFailureRate();

      // Require minimum sample size before checking failure rate to avoid premature opening
      // Use smaller of: failure threshold OR rolling window size (but at least 5)
      const minSampleSize = Math.min(
        this.config.failureThreshold,
        Math.max(this.config.rollingWindowSize / 2, 5)
      );
      const hasEnoughData = this.recentResults.length >= minSampleSize;

      if (this.failureCount >= this.config.failureThreshold ||
          (hasEnoughData && recentFailureRate >= 0.5)) {
        this.transitionToOpen(error);
      }
    }
  }

  /**
   * Record result in rolling window
   */
  private recordResult(success: boolean): void {
    this.recentResults.push(success);

    // Maintain rolling window size
    if (this.recentResults.length > this.config.rollingWindowSize) {
      this.recentResults.shift();
    }
  }

  /**
   * Get recent failure rate (0.0 to 1.0)
   */
  private getRecentFailureRate(): number {
    if (this.recentResults.length === 0) {
      return 0;
    }

    const failures = this.recentResults.filter(r => !r).length;
    return failures / this.recentResults.length;
  }

  /**
   * Check if we should attempt to reset (transition to HALF_OPEN)
   */
  private shouldAttemptReset(): boolean {
    if (!this.openedAt) {
      return false;
    }

    const elapsedMs = Date.now() - this.openedAt.getTime();
    return elapsedMs >= this.config.resetTimeoutMs;
  }

  /**
   * Transition to OPEN state
   */
  private transitionToOpen(error: Error): void {
    if (this.state === CircuitState.OPEN) {
      return; // Already open
    }

    logger.error(`Circuit breaker OPENING for ${this.serviceName}`, {
      failureCount: this.failureCount,
      threshold: this.config.failureThreshold,
      error: error.message,
    });

    this.state = CircuitState.OPEN;
    this.openedAt = new Date();
    this.successCount = 0;

    // Clear any existing reset timer
    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
    }

    // Schedule automatic transition to HALF_OPEN
    this.resetTimer = setTimeout(() => {
      this.transitionToHalfOpen();
    }, this.config.resetTimeoutMs);

    // Invoke callback
    this.config.onOpen(error);
  }

  /**
   * Transition to HALF_OPEN state
   */
  private transitionToHalfOpen(): void {
    if (this.state === CircuitState.HALF_OPEN) {
      return; // Already half-open
    }

    logger.info(`Circuit breaker HALF-OPEN for ${this.serviceName} (testing recovery)`);

    this.state = CircuitState.HALF_OPEN;
    this.halfOpenedAt = new Date();
    this.successCount = 0;
    this.failureCount = 0;

    // Invoke callback
    this.config.onHalfOpen();
  }

  /**
   * Transition to CLOSED state
   */
  private transitionToClosed(): void {
    if (this.state === CircuitState.CLOSED) {
      return; // Already closed
    }

    logger.info(`Circuit breaker CLOSED for ${this.serviceName} (service recovered)`);

    this.state = CircuitState.CLOSED;
    this.closedAt = new Date();
    this.failureCount = 0;
    this.successCount = 0;
    this.recentResults = [];

    // Clear reset timer
    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
      this.resetTimer = undefined;
    }

    // Invoke callback
    this.config.onClose();
  }

  /**
   * Get current state
   */
  getState(): CircuitState {
    return this.state;
  }

  /**
   * Get current statistics
   */
  getStats(): CircuitBreakerStats {
    return {
      state: this.state,
      failureCount: this.failureCount,
      successCount: this.successCount,
      totalRequests: this.totalRequests,
      lastFailureTime: this.lastFailureTime,
      lastSuccessTime: this.lastSuccessTime,
      openedAt: this.openedAt,
      halfOpenedAt: this.halfOpenedAt,
      closedAt: this.closedAt,
    };
  }

  /**
   * Force open the circuit (for testing/maintenance)
   */
  forceOpen(): void {
    this.transitionToOpen(new Error('Manually opened'));
  }

  /**
   * Force close the circuit (for testing/recovery)
   */
  forceClose(): void {
    this.transitionToClosed();
  }

  /**
   * Reset statistics
   */
  reset(): void {
    this.failureCount = 0;
    this.successCount = 0;
    this.totalRequests = 0;
    this.recentResults = [];
    this.lastFailureTime = undefined;
    this.lastSuccessTime = undefined;
    this.transitionToClosed();
  }
}

/**
 * Circuit breaker registry for managing multiple breakers
 */
export class CircuitBreakerRegistry {
  private breakers: Map<string, CircuitBreaker> = new Map();

  /**
   * Get or create a circuit breaker for a service
   */
  getOrCreate(serviceName: string, config?: CircuitBreakerConfig): CircuitBreaker {
    if (!this.breakers.has(serviceName)) {
      this.breakers.set(serviceName, new CircuitBreaker(serviceName, config));
    }
    return this.breakers.get(serviceName)!;
  }

  /**
   * Get all breakers
   */
  getAll(): Map<string, CircuitBreaker> {
    return this.breakers;
  }

  /**
   * Get statistics for all breakers
   */
  getAllStats(): Record<string, CircuitBreakerStats> {
    const stats: Record<string, CircuitBreakerStats> = {};
    this.breakers.forEach((breaker, name) => {
      stats[name] = breaker.getStats();
    });
    return stats;
  }

  /**
   * Reset all breakers
   */
  resetAll(): void {
    this.breakers.forEach(breaker => breaker.reset());
  }
}

/**
 * Export default registry
 */
export const circuitBreakerRegistry = new CircuitBreakerRegistry();
export default circuitBreakerRegistry;
