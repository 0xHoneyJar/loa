/**
 * Retry Handler with Exponential Backoff
 *
 * Implements HIGH-004: Error Handling for Failed Translations
 *
 * Provides configurable retry logic with exponential backoff to handle
 * transient failures in external API calls (Anthropic, Google Docs, etc.)
 *
 * Features:
 * - Exponential backoff (1s, 2s, 4s default)
 * - Configurable max retries
 * - Customizable retry conditions
 * - Detailed error logging
 * - Timeout support
 */

import logger from '../utils/logger';

/**
 * Retry configuration
 */
export interface RetryConfig {
  /**
   * Maximum number of retry attempts (default: 3)
   */
  maxRetries?: number;

  /**
   * Initial delay in milliseconds (default: 1000ms = 1s)
   */
  initialDelayMs?: number;

  /**
   * Backoff multiplier (default: 2 for exponential)
   */
  backoffMultiplier?: number;

  /**
   * Maximum delay between retries in milliseconds (default: 10000ms = 10s)
   */
  maxDelayMs?: number;

  /**
   * Timeout for each attempt in milliseconds (default: 30000ms = 30s)
   */
  timeoutMs?: number;

  /**
   * Custom function to determine if error is retryable
   * Returns true if should retry, false otherwise
   */
  shouldRetry?: (error: Error, attemptNumber: number) => boolean;

  /**
   * Callback invoked before each retry
   */
  onRetry?: (error: Error, attemptNumber: number, delayMs: number) => void;
}

/**
 * Result of a retry operation
 */
export interface RetryResult<T> {
  success: boolean;
  result?: T;
  error?: Error;
  attempts: number;
  totalDurationMs: number;
}

/**
 * Default retry configuration
 */
const DEFAULT_CONFIG: Required<RetryConfig> = {
  maxRetries: 3,
  initialDelayMs: 1000, // 1 second
  backoffMultiplier: 2,
  maxDelayMs: 10000, // 10 seconds
  timeoutMs: 30000, // 30 seconds
  shouldRetry: defaultShouldRetry,
  onRetry: defaultOnRetry,
};

/**
 * Default retry condition: retry on network errors and 5xx status codes
 */
function defaultShouldRetry(error: Error, _attemptNumber: number): boolean {
  // Note: maxRetries is enforced by the retry handler loop,
  // so we don't check attemptNumber here

  // Retry on network errors
  if (error.message.includes('ECONNREFUSED') ||
      error.message.includes('ETIMEDOUT') ||
      error.message.includes('ENOTFOUND') ||
      error.message.includes('network') ||
      error.message.includes('timeout')) {
    return true;
  }

  // Retry on rate limiting
  if (error.message.includes('rate limit') ||
      error.message.includes('429') ||
      error.message.includes('too many requests')) {
    return true;
  }

  // Retry on 5xx server errors
  if (error.message.includes('500') ||
      error.message.includes('502') ||
      error.message.includes('503') ||
      error.message.includes('504')) {
    return true;
  }

  // Don't retry on client errors (4xx except 429)
  if (error.message.includes('400') ||
      error.message.includes('401') ||
      error.message.includes('403') ||
      error.message.includes('404')) {
    return false;
  }

  // Retry on generic errors (unknown failures might be transient)
  return true;
}

/**
 * Default retry callback
 */
function defaultOnRetry(error: Error, attemptNumber: number, delayMs: number): void {
  logger.warn('Retrying after error', {
    error: error.message,
    attemptNumber,
    delayMs,
    nextAttempt: attemptNumber + 1,
  });
}

/**
 * Retry handler class
 */
export class RetryHandler {
  private config: Required<RetryConfig>;

  constructor(config?: RetryConfig) {
    this.config = {
      ...DEFAULT_CONFIG,
      ...config,
      shouldRetry: config?.shouldRetry || DEFAULT_CONFIG.shouldRetry,
      onRetry: config?.onRetry || DEFAULT_CONFIG.onRetry,
    };
  }

  /**
   * Execute a function with retry logic
   *
   * @param fn - Async function to execute
   * @param context - Optional context for logging
   * @returns RetryResult with success status and result/error
   */
  async execute<T>(
    fn: () => Promise<T>,
    context?: string
  ): Promise<RetryResult<T>> {
    const startTime = Date.now();
    let lastError: Error | undefined;
    let attemptNumber = 0;

    logger.info('Starting retry handler', {
      context,
      maxRetries: this.config.maxRetries,
      initialDelayMs: this.config.initialDelayMs,
    });

    while (attemptNumber <= this.config.maxRetries) {
      attemptNumber++;

      try {
        logger.debug(`Attempt ${attemptNumber}/${this.config.maxRetries + 1}`, { context });

        // Execute with timeout
        const result = await this.executeWithTimeout(fn, this.config.timeoutMs);

        // Success!
        const duration = Date.now() - startTime;
        logger.info('Retry handler succeeded', {
          context,
          attempts: attemptNumber,
          totalDurationMs: duration,
        });

        return {
          success: true,
          result,
          attempts: attemptNumber,
          totalDurationMs: duration,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));

        logger.warn(`Attempt ${attemptNumber} failed`, {
          context,
          error: lastError.message,
          attemptNumber,
        });

        // Check if we should retry
        const shouldRetry = this.config.shouldRetry(lastError, attemptNumber);

        if (!shouldRetry || attemptNumber > this.config.maxRetries) {
          // No more retries
          const duration = Date.now() - startTime;
          logger.error('Retry handler exhausted all attempts', {
            context,
            attempts: attemptNumber,
            totalDurationMs: duration,
            finalError: lastError.message,
          });

          return {
            success: false,
            error: lastError,
            attempts: attemptNumber,
            totalDurationMs: duration,
          };
        }

        // Calculate delay with exponential backoff
        const delay = this.calculateDelay(attemptNumber);

        // Invoke retry callback
        this.config.onRetry(lastError, attemptNumber, delay);

        // Wait before next attempt
        await this.sleep(delay);
      }
    }

    // Should never reach here, but TypeScript needs it
    const duration = Date.now() - startTime;
    return {
      success: false,
      error: lastError || new Error('Unknown error'),
      attempts: attemptNumber,
      totalDurationMs: duration,
    };
  }

  /**
   * Calculate delay with exponential backoff
   */
  private calculateDelay(attemptNumber: number): number {
    const delay = this.config.initialDelayMs * Math.pow(this.config.backoffMultiplier, attemptNumber - 1);
    return Math.min(delay, this.config.maxDelayMs);
  }

  /**
   * Execute function with timeout
   */
  private executeWithTimeout<T>(fn: () => Promise<T>, timeoutMs: number): Promise<T> {
    return Promise.race([
      fn(),
      new Promise<T>((_, reject) =>
        setTimeout(() => reject(new Error(`Operation timed out after ${timeoutMs}ms`)), timeoutMs)
      ),
    ]);
  }

  /**
   * Sleep for specified milliseconds
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Get current configuration
   */
  getConfig(): Required<RetryConfig> {
    return { ...this.config };
  }

  /**
   * Update configuration
   */
  updateConfig(config: Partial<RetryConfig>): void {
    this.config = {
      ...this.config,
      ...config,
      shouldRetry: config.shouldRetry || this.config.shouldRetry,
      onRetry: config.onRetry || this.config.onRetry,
    };
  }
}

/**
 * Convenience function to retry an operation with default config
 */
export async function retry<T>(
  fn: () => Promise<T>,
  config?: RetryConfig,
  context?: string
): Promise<T> {
  const handler = new RetryHandler(config);
  const result = await handler.execute(fn, context);

  if (!result.success) {
    throw result.error || new Error('Retry failed');
  }

  return result.result as T;
}

/**
 * Export default instance
 */
export default new RetryHandler();
