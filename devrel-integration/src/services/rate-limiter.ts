/**
 * Rate Limiter
 *
 * Implements sliding window rate limiting for Discord commands and internal operations.
 * Prevents DoS attacks by limiting requests per user per time window.
 *
 * This implements CRITICAL-006 remediation (rate limiting & DoS protection).
 */

import { logger } from '../utils/logger';

export interface RateLimitState {
  count: number;
  windowStart: number;
  lastRequest?: number;
}

export interface RateLimitConfig {
  maxRequests: number;
  windowMs: number;
}

export interface RateLimitResult {
  allowed: boolean;
  resetInMs?: number;
  message?: string;
  remainingRequests?: number;
}

/**
 * Rate Limiter
 *
 * Security Controls:
 * 1. Per-user rate limiting (prevents single user abuse)
 * 2. Per-action rate limiting (different limits for different operations)
 * 3. Sliding window algorithm (smooth rate limiting over time)
 * 4. Automatic window reset (expired windows cleared)
 * 5. Detailed logging for audit trail
 * 6. Remaining request tracking (helps users understand limits)
 */
export class RateLimiter {
  private rateLimits = new Map<string, RateLimitState>();
  private pendingRequests = new Map<string, boolean>();

  /**
   * Check if user is rate limited for specific action
   *
   * Returns whether request is allowed, with metadata about rate limit status
   */
  async checkRateLimit(userId: string, action: string): Promise<RateLimitResult> {
    const key = `${userId}:${action}`;
    const now = Date.now();

    const limit = this.getRateLimitConfig(action);
    const state = this.rateLimits.get(key) || { count: 0, windowStart: now };

    // Reset window if expired
    if (now - state.windowStart > limit.windowMs) {
      state.count = 0;
      state.windowStart = now;
    }

    // Check if limit exceeded
    if (state.count >= limit.maxRequests) {
      const resetIn = limit.windowMs - (now - state.windowStart);
      const resetInSeconds = Math.ceil(resetIn / 1000);

      logger.warn(`Rate limit exceeded`, {
        userId,
        action,
        requestsInWindow: state.count,
        maxRequests: limit.maxRequests,
        windowMs: limit.windowMs,
        resetInSeconds
      });

      return {
        allowed: false,
        resetInMs: resetIn,
        message: `⏱️ Rate limit exceeded. You can make ${limit.maxRequests} requests per ${this.formatWindow(limit.windowMs)}. Try again in ${resetInSeconds} second${resetInSeconds !== 1 ? 's' : ''}.`,
        remainingRequests: 0
      };
    }

    // Increment counter
    state.count++;
    state.lastRequest = now;
    this.rateLimits.set(key, state);

    const remainingRequests = limit.maxRequests - state.count;

    logger.debug(`Rate limit check passed`, {
      userId,
      action,
      requestsInWindow: state.count,
      maxRequests: limit.maxRequests,
      remainingRequests
    });

    return {
      allowed: true,
      remainingRequests
    };
  }

  /**
   * Check if user has a pending request (for concurrent request limiting)
   */
  async checkPendingRequest(userId: string, action: string): Promise<boolean> {
    const key = `${userId}:${action}`;
    return this.pendingRequests.get(key) === true;
  }

  /**
   * Mark request as pending
   */
  async markRequestPending(userId: string, action: string): Promise<void> {
    const key = `${userId}:${action}`;
    this.pendingRequests.set(key, true);

    logger.debug(`Request marked as pending`, { userId, action });
  }

  /**
   * Clear pending request
   */
  async clearPendingRequest(userId: string, action: string): Promise<void> {
    const key = `${userId}:${action}`;
    this.pendingRequests.delete(key);

    logger.debug(`Pending request cleared`, { userId, action });
  }

  /**
   * Get rate limit configuration per action
   */
  private getRateLimitConfig(action: string): RateLimitConfig {
    const configs: Record<string, RateLimitConfig> = {
      // Discord commands
      'generate-summary': {
        maxRequests: 5,      // 5 requests
        windowMs: 60000      // per 1 minute
      },

      // Google Docs operations
      'google-docs-fetch': {
        maxRequests: 100,    // 100 requests
        windowMs: 60000      // per 1 minute
      },

      // Anthropic API calls
      'anthropic-api-call': {
        maxRequests: 20,     // 20 requests
        windowMs: 60000      // per 1 minute
      },

      // Discord posting
      'discord-post': {
        maxRequests: 10,     // 10 requests
        windowMs: 60000      // per 1 minute
      },

      // DevRel translation
      'translate-document': {
        maxRequests: 10,     // 10 requests
        windowMs: 60000      // per 1 minute
      },

      // Default rate limit for unknown actions
      'default': {
        maxRequests: 10,     // 10 requests
        windowMs: 60000      // per 1 minute
      }
    };

    return configs[action] || configs['default'];
  }

  /**
   * Format time window for human-readable messages
   */
  private formatWindow(windowMs: number): string {
    const seconds = Math.floor(windowMs / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      return `${hours} hour${hours !== 1 ? 's' : ''}`;
    } else if (minutes > 0) {
      return `${minutes} minute${minutes !== 1 ? 's' : ''}`;
    } else {
      return `${seconds} second${seconds !== 1 ? 's' : ''}`;
    }
  }

  /**
   * Reset rate limit for specific user and action (for testing or admin override)
   */
  async resetRateLimit(userId: string, action: string): Promise<void> {
    const key = `${userId}:${action}`;
    this.rateLimits.delete(key);

    logger.info(`Rate limit reset`, { userId, action });
  }

  /**
   * Get current rate limit status for user and action
   */
  async getRateLimitStatus(userId: string, action: string): Promise<{
    requestsInWindow: number;
    maxRequests: number;
    windowMs: number;
    resetInMs?: number;
  }> {
    const key = `${userId}:${action}`;
    const now = Date.now();

    const limit = this.getRateLimitConfig(action);
    const state = this.rateLimits.get(key);

    if (!state) {
      return {
        requestsInWindow: 0,
        maxRequests: limit.maxRequests,
        windowMs: limit.windowMs
      };
    }

    // Check if window expired
    if (now - state.windowStart > limit.windowMs) {
      return {
        requestsInWindow: 0,
        maxRequests: limit.maxRequests,
        windowMs: limit.windowMs
      };
    }

    const resetInMs = limit.windowMs - (now - state.windowStart);

    return {
      requestsInWindow: state.count,
      maxRequests: limit.maxRequests,
      windowMs: limit.windowMs,
      resetInMs
    };
  }

  /**
   * Clean up expired rate limit entries (to prevent memory leaks)
   */
  private cleanupExpiredEntries(): void {
    const now = Date.now();
    const maxAge = 24 * 60 * 60 * 1000; // 24 hours

    for (const [key, state] of this.rateLimits.entries()) {
      if (now - state.windowStart > maxAge) {
        this.rateLimits.delete(key);
        logger.debug(`Cleaned up expired rate limit entry: ${key}`);
      }
    }
  }

  /**
   * Start periodic cleanup of expired entries
   */
  startCleanupTask(intervalMs: number = 60 * 60 * 1000): void {
    setInterval(() => {
      this.cleanupExpiredEntries();
    }, intervalMs);

    logger.info(`Rate limiter cleanup task started (interval: ${intervalMs}ms)`);
  }

  /**
   * Get statistics about rate limiting
   */
  getStatistics(): {
    totalTrackedUsers: number;
    totalPendingRequests: number;
    rateLimitConfigs: Record<string, RateLimitConfig>;
  } {
    return {
      totalTrackedUsers: this.rateLimits.size,
      totalPendingRequests: this.pendingRequests.size,
      rateLimitConfigs: {
        'generate-summary': this.getRateLimitConfig('generate-summary'),
        'google-docs-fetch': this.getRateLimitConfig('google-docs-fetch'),
        'anthropic-api-call': this.getRateLimitConfig('anthropic-api-call'),
        'discord-post': this.getRateLimitConfig('discord-post'),
        'translate-document': this.getRateLimitConfig('translate-document')
      }
    };
  }
}

// Singleton instance
export const rateLimiter = new RateLimiter();

// Start cleanup task (runs every hour)
rateLimiter.startCleanupTask();

export default rateLimiter;
