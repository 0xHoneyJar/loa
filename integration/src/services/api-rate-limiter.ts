/**
 * API Rate Limiter
 *
 * Throttles external API calls to prevent quota exhaustion and excessive costs.
 * Implements exponential backoff for rate limit errors.
 *
 * This implements CRITICAL-006 remediation (API call throttling).
 */

import { logger } from '../utils/logger';

export interface APILimitState {
  requestCount: number;
  windowStart: number;
  retries: number;
  lastError?: Date;
}

export interface APIThrottleConfig {
  maxRequestsPerMinute: number;
  maxRetries: number;
  initialBackoffMs: number;
  maxBackoffMs: number;
}

/**
 * API Rate Limiter
 *
 * Security Controls:
 * 1. Per-API rate limiting (Google Drive, Anthropic, Discord)
 * 2. Exponential backoff on rate limit errors
 * 3. Automatic retry with backoff
 * 4. Request counting and throttling
 * 5. Error detection and classification
 * 6. Detailed logging for debugging and audit
 */
export class APIRateLimiter {
  private apiLimits = new Map<string, APILimitState>();

  /**
   * Throttle Google Drive API calls
   *
   * Google Drive API Quota: 100 requests per 100 seconds per user
   * We set a conservative limit of 100 requests per minute
   */
  async throttleGoogleDriveAPI<T>(operation: () => Promise<T>, operationName?: string): Promise<T> {
    const api = 'google-drive';
    await this.checkAPIRateLimit(api);

    try {
      const result = await operation();

      // Record successful request
      this.recordRequest(api);

      return result;

    } catch (error) {
      if (this.isRateLimitError(error)) {
        logger.warn(`Google Drive API rate limit hit`, {
          operationName,
          error: error instanceof Error ? error.message : String(error)
        });

        // Exponential backoff
        await this.exponentialBackoff(api);

        // Retry once after backoff
        logger.info(`Retrying Google Drive API call after backoff`, { operationName });
        return await operation();
      }

      throw error;
    }
  }

  /**
   * Throttle Anthropic API calls
   *
   * Anthropic API Limits:
   * - Tier 1: 50 requests/min, 40k tokens/min
   * - Tier 2: 1000 requests/min, 80k tokens/min
   * We set a conservative limit of 20 requests per minute
   */
  async throttleAnthropicAPI<T>(operation: () => Promise<T>, operationName?: string): Promise<T> {
    const api = 'anthropic';
    await this.checkAPIRateLimit(api);

    try {
      const result = await operation();

      // Record successful request
      this.recordRequest(api);

      return result;

    } catch (error) {
      if (this.isRateLimitError(error)) {
        logger.warn(`Anthropic API rate limit hit`, {
          operationName,
          error: error instanceof Error ? error.message : String(error)
        });

        // Exponential backoff
        await this.exponentialBackoff(api);

        // Retry once after backoff
        logger.info(`Retrying Anthropic API call after backoff`, { operationName });
        return await operation();
      }

      throw error;
    }
  }

  /**
   * Throttle Discord API calls
   *
   * Discord API Rate Limits:
   * - Global: 50 requests per second
   * - Per-channel: 5 requests per 5 seconds
   * We set a conservative limit of 10 requests per minute for safety
   */
  async throttleDiscordAPI<T>(operation: () => Promise<T>, operationName?: string): Promise<T> {
    const api = 'discord';
    await this.checkAPIRateLimit(api);

    try {
      const result = await operation();

      // Record successful request
      this.recordRequest(api);

      return result;

    } catch (error) {
      if (this.isRateLimitError(error)) {
        logger.warn(`Discord API rate limit hit`, {
          operationName,
          error: error instanceof Error ? error.message : String(error)
        });

        // Discord provides retry-after header
        const retryAfter = this.extractRetryAfter(error);
        if (retryAfter) {
          logger.info(`Discord API rate limited, waiting ${retryAfter}ms`, { operationName });
          await this.delay(retryAfter);
        } else {
          // Fallback to exponential backoff
          await this.exponentialBackoff(api);
        }

        // Retry once after backoff
        logger.info(`Retrying Discord API call after backoff`, { operationName });
        return await operation();
      }

      throw error;
    }
  }

  /**
   * Check if API rate limit would be exceeded
   */
  private async checkAPIRateLimit(api: string): Promise<void> {
    const config = this.getAPIThrottleConfig(api);
    const now = Date.now();

    const state = this.apiLimits.get(api) || {
      requestCount: 0,
      windowStart: now,
      retries: 0
    };

    // Reset window if expired (1 minute window)
    if (now - state.windowStart > 60000) {
      state.requestCount = 0;
      state.windowStart = now;
      state.retries = 0;
    }

    // Check if rate limit would be exceeded
    if (state.requestCount >= config.maxRequestsPerMinute) {
      const waitTime = 60000 - (now - state.windowStart);

      logger.warn(`API rate limit reached, throttling`, {
        api,
        requestCount: state.requestCount,
        maxRequests: config.maxRequestsPerMinute,
        waitTimeMs: waitTime
      });

      // Wait until window resets
      await this.delay(waitTime);

      // Reset window
      state.requestCount = 0;
      state.windowStart = Date.now();
      state.retries = 0;
    }

    this.apiLimits.set(api, state);
  }

  /**
   * Record successful API request
   */
  private recordRequest(api: string): void {
    const state = this.apiLimits.get(api);
    if (state) {
      state.requestCount++;
      state.retries = 0; // Reset retry counter on success
      this.apiLimits.set(api, state);
    }
  }

  /**
   * Exponential backoff for rate limited APIs
   */
  private async exponentialBackoff(api: string): Promise<void> {
    const config = this.getAPIThrottleConfig(api);
    const state = this.apiLimits.get(api) || { requestCount: 0, windowStart: Date.now(), retries: 0 };

    // Calculate backoff time: initialBackoff * 2^retries
    const backoffMs = Math.min(
      config.initialBackoffMs * Math.pow(2, state.retries),
      config.maxBackoffMs
    );

    logger.info(`Applying exponential backoff`, {
      api,
      retries: state.retries,
      backoffMs,
      backoffSeconds: Math.ceil(backoffMs / 1000)
    });

    await this.delay(backoffMs);

    // Increment retry counter
    state.retries++;
    state.lastError = new Date();
    this.apiLimits.set(api, state);

    // Prevent infinite retries
    if (state.retries > config.maxRetries) {
      throw new Error(`Max retries exceeded for ${api} API (${state.retries} retries)`);
    }
  }

  /**
   * Check if error is a rate limit error
   */
  private isRateLimitError(error: any): boolean {
    if (!error) return false;

    const message = error.message?.toLowerCase() || '';
    const code = error.code?.toString() || '';
    const status = error.status || error.statusCode || 0;

    // Common rate limit indicators
    return (
      status === 429 ||                           // HTTP 429 Too Many Requests
      message.includes('rate limit') ||
      message.includes('too many requests') ||
      message.includes('quota exceeded') ||
      message.includes('throttled') ||
      code === 'RATE_LIMIT_EXCEEDED' ||
      code === '429'
    );
  }

  /**
   * Extract retry-after value from error (Discord-specific)
   */
  private extractRetryAfter(error: any): number | null {
    if (!error) return null;

    // Discord returns retry_after in milliseconds
    if (error.retry_after) {
      return error.retry_after;
    }

    // Check headers (some APIs return Retry-After header in seconds)
    if (error.response?.headers?.['retry-after']) {
      const retryAfter = parseInt(error.response.headers['retry-after'], 10);
      return retryAfter * 1000; // Convert seconds to milliseconds
    }

    return null;
  }

  /**
   * Get API throttle configuration
   */
  private getAPIThrottleConfig(api: string): APIThrottleConfig {
    const configs: Record<string, APIThrottleConfig> = {
      'google-drive': {
        maxRequestsPerMinute: 100,
        maxRetries: 3,
        initialBackoffMs: 1000,  // Start with 1 second
        maxBackoffMs: 30000      // Max 30 seconds
      },
      'anthropic': {
        maxRequestsPerMinute: 20,
        maxRetries: 3,
        initialBackoffMs: 2000,  // Start with 2 seconds
        maxBackoffMs: 60000      // Max 60 seconds
      },
      'discord': {
        maxRequestsPerMinute: 10,
        maxRetries: 3,
        initialBackoffMs: 1000,  // Start with 1 second
        maxBackoffMs: 10000      // Max 10 seconds
      }
    };

    return configs[api] || {
      maxRequestsPerMinute: 10,
      maxRetries: 3,
      initialBackoffMs: 1000,
      maxBackoffMs: 30000
    };
  }

  /**
   * Delay helper
   */
  private delay(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Reset API rate limit (for testing or admin override)
   */
  async resetAPIRateLimit(api: string): Promise<void> {
    this.apiLimits.delete(api);
    logger.info(`API rate limit reset`, { api });
  }

  /**
   * Get current API rate limit status
   */
  async getAPIRateLimitStatus(api: string): Promise<{
    requestCount: number;
    maxRequests: number;
    windowStart: Date;
    retries: number;
    lastError?: Date;
  }> {
    const config = this.getAPIThrottleConfig(api);
    const state = this.apiLimits.get(api);

    if (!state) {
      return {
        requestCount: 0,
        maxRequests: config.maxRequestsPerMinute,
        windowStart: new Date(),
        retries: 0
      };
    }

    return {
      requestCount: state.requestCount,
      maxRequests: config.maxRequestsPerMinute,
      windowStart: new Date(state.windowStart),
      retries: state.retries,
      lastError: state.lastError
    };
  }

  /**
   * Get statistics about API rate limiting
   */
  getStatistics(): {
    trackedAPIs: string[];
    totalRequestsTracked: number;
    apiConfigs: Record<string, APIThrottleConfig>;
  } {
    const trackedAPIs = Array.from(this.apiLimits.keys());
    const totalRequestsTracked = Array.from(this.apiLimits.values())
      .reduce((sum, state) => sum + state.requestCount, 0);

    return {
      trackedAPIs,
      totalRequestsTracked,
      apiConfigs: {
        'google-drive': this.getAPIThrottleConfig('google-drive'),
        'anthropic': this.getAPIThrottleConfig('anthropic'),
        'discord': this.getAPIThrottleConfig('discord')
      }
    };
  }
}

// Singleton instance
export const apiRateLimiter = new APIRateLimiter();
export default apiRateLimiter;
