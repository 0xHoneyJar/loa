/**
 * Rate Limiter Tests
 *
 * Tests for sliding window rate limiting to prevent DoS attacks.
 * Validates:
 * - Per-user request counting
 * - Sliding window algorithm
 * - Rate limit enforcement
 * - Window reset behavior
 * - Concurrent request handling
 * - Statistics and monitoring
 *
 * This tests CRITICAL-006 remediation (rate limiting & DoS protection).
 */

import { RateLimiter } from '../rate-limiter';

describe('RateLimiter', () => {
  let rateLimiter: RateLimiter;

  beforeEach(() => {
    rateLimiter = new RateLimiter();
  });

  describe('checkRateLimit - Basic functionality', () => {
    it('should allow requests within limit', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      const result = await rateLimiter.checkRateLimit(userId, action);

      expect(result.allowed).toBe(true);
      expect(result.remainingRequests).toBeGreaterThan(0);
    });

    it('should track remaining requests', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      const result1 = await rateLimiter.checkRateLimit(userId, action);
      const result2 = await rateLimiter.checkRateLimit(userId, action);

      expect(result1.remainingRequests).toBeGreaterThan(result2.remainingRequests!);
    });

    it('should decrement remaining requests on each call', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      const result1 = await rateLimiter.checkRateLimit(userId, action);
      const remaining1 = result1.remainingRequests!;

      const result2 = await rateLimiter.checkRateLimit(userId, action);
      const remaining2 = result2.remainingRequests!;

      expect(remaining2).toBe(remaining1 - 1);
    });
  });

  describe('checkRateLimit - Rate limit enforcement', () => {
    it('should block requests after exceeding limit', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Make requests up to limit (5 for generate-summary)
      for (let i = 0; i < 5; i++) {
        const result = await rateLimiter.checkRateLimit(userId, action);
        expect(result.allowed).toBe(true);
      }

      // 6th request should be blocked
      const blockedResult = await rateLimiter.checkRateLimit(userId, action);
      expect(blockedResult.allowed).toBe(false);
      expect(blockedResult.remainingRequests).toBe(0);
      expect(blockedResult.message).toContain('Rate limit exceeded');
    });

    it('should provide reset time when blocked', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Exhaust rate limit
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      // Check blocked request
      const blockedResult = await rateLimiter.checkRateLimit(userId, action);

      expect(blockedResult.allowed).toBe(false);
      expect(blockedResult.resetInMs).toBeGreaterThan(0);
      expect(blockedResult.resetInMs).toBeLessThanOrEqual(60000); // 1 minute max
    });

    it('should include user-friendly message', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Exhaust rate limit
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      const blockedResult = await rateLimiter.checkRateLimit(userId, action);

      expect(blockedResult.message).toContain('Rate limit exceeded');
      expect(blockedResult.message).toContain('5 requests per');
      expect(blockedResult.message).toContain('Try again in');
    });
  });

  describe('checkRateLimit - Sliding window behavior', () => {
    it('should reset window after time expires', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Exhaust rate limit
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      // Verify blocked
      const blockedResult = await rateLimiter.checkRateLimit(userId, action);
      expect(blockedResult.allowed).toBe(false);

      // Wait for window to expire (simulate with manual reset for testing)
      await rateLimiter.resetRateLimit(userId, action);

      // Should allow requests again
      const afterResetResult = await rateLimiter.checkRateLimit(userId, action);
      expect(afterResetResult.allowed).toBe(true);
    });

    it('should maintain separate windows per user', async () => {
      const user1 = 'user1';
      const user2 = 'user2';
      const action = 'generate-summary';

      // Exhaust rate limit for user1
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(user1, action);
      }

      // user1 should be blocked
      const user1Result = await rateLimiter.checkRateLimit(user1, action);
      expect(user1Result.allowed).toBe(false);

      // user2 should still be allowed
      const user2Result = await rateLimiter.checkRateLimit(user2, action);
      expect(user2Result.allowed).toBe(true);
    });

    it('should maintain separate windows per action', async () => {
      const userId = 'user123';
      const action1 = 'generate-summary';
      const action2 = 'discord-post';

      // Exhaust rate limit for action1
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action1);
      }

      // action1 should be blocked
      const action1Result = await rateLimiter.checkRateLimit(userId, action1);
      expect(action1Result.allowed).toBe(false);

      // action2 should still be allowed
      const action2Result = await rateLimiter.checkRateLimit(userId, action2);
      expect(action2Result.allowed).toBe(true);
    });
  });

  describe('checkRateLimit - Different action types', () => {
    it('should enforce different limits for different actions', async () => {
      const userId = 'user123';

      // generate-summary: 5 requests/minute
      for (let i = 0; i < 5; i++) {
        const result = await rateLimiter.checkRateLimit(userId, 'generate-summary');
        expect(result.allowed).toBe(true);
      }
      const summaryBlocked = await rateLimiter.checkRateLimit(userId, 'generate-summary');
      expect(summaryBlocked.allowed).toBe(false);

      // google-docs-fetch: 100 requests/minute (higher limit)
      for (let i = 0; i < 50; i++) {
        const result = await rateLimiter.checkRateLimit(userId, 'google-docs-fetch');
        expect(result.allowed).toBe(true);
      }
    });

    it('should use default limit for unknown actions', async () => {
      const userId = 'user123';
      const unknownAction = 'unknown-action';

      // Default: 10 requests/minute
      for (let i = 0; i < 10; i++) {
        const result = await rateLimiter.checkRateLimit(userId, unknownAction);
        expect(result.allowed).toBe(true);
      }

      // 11th request should be blocked
      const blockedResult = await rateLimiter.checkRateLimit(userId, unknownAction);
      expect(blockedResult.allowed).toBe(false);
    });
  });

  describe('checkPendingRequest - Concurrent request prevention', () => {
    it('should detect pending requests', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Initially no pending request
      const noPending = await rateLimiter.checkPendingRequest(userId, action);
      expect(noPending).toBe(false);

      // Mark as pending
      await rateLimiter.markRequestPending(userId, action);

      // Should now be pending
      const hasPending = await rateLimiter.checkPendingRequest(userId, action);
      expect(hasPending).toBe(true);
    });

    it('should clear pending requests', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Mark as pending
      await rateLimiter.markRequestPending(userId, action);
      expect(await rateLimiter.checkPendingRequest(userId, action)).toBe(true);

      // Clear pending
      await rateLimiter.clearPendingRequest(userId, action);

      // Should no longer be pending
      const notPending = await rateLimiter.checkPendingRequest(userId, action);
      expect(notPending).toBe(false);
    });

    it('should track pending requests separately per user', async () => {
      const user1 = 'user1';
      const user2 = 'user2';
      const action = 'generate-summary';

      // Mark user1 as pending
      await rateLimiter.markRequestPending(user1, action);

      // user1 should be pending, user2 should not
      expect(await rateLimiter.checkPendingRequest(user1, action)).toBe(true);
      expect(await rateLimiter.checkPendingRequest(user2, action)).toBe(false);
    });

    it('should track pending requests separately per action', async () => {
      const userId = 'user123';
      const action1 = 'generate-summary';
      const action2 = 'discord-post';

      // Mark action1 as pending
      await rateLimiter.markRequestPending(userId, action1);

      // action1 should be pending, action2 should not
      expect(await rateLimiter.checkPendingRequest(userId, action1)).toBe(true);
      expect(await rateLimiter.checkPendingRequest(userId, action2)).toBe(false);
    });
  });

  describe('getRateLimitStatus', () => {
    it('should return status for new user', async () => {
      const userId = 'newUser';
      const action = 'generate-summary';

      const status = await rateLimiter.getRateLimitStatus(userId, action);

      expect(status.requestsInWindow).toBe(0);
      expect(status.maxRequests).toBe(5);
      expect(status.windowMs).toBe(60000);
    });

    it('should return current request count', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Make 3 requests
      for (let i = 0; i < 3; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      const status = await rateLimiter.getRateLimitStatus(userId, action);

      expect(status.requestsInWindow).toBe(3);
      expect(status.maxRequests).toBe(5);
    });

    it('should include reset time', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Make a request to start window
      await rateLimiter.checkRateLimit(userId, action);

      const status = await rateLimiter.getRateLimitStatus(userId, action);

      expect(status.resetInMs).toBeDefined();
      expect(status.resetInMs!).toBeGreaterThan(0);
      expect(status.resetInMs!).toBeLessThanOrEqual(60000);
    });
  });

  describe('resetRateLimit', () => {
    it('should reset rate limit for user', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Exhaust rate limit
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      // Verify blocked
      const blockedResult = await rateLimiter.checkRateLimit(userId, action);
      expect(blockedResult.allowed).toBe(false);

      // Reset
      await rateLimiter.resetRateLimit(userId, action);

      // Should be allowed again
      const afterResetResult = await rateLimiter.checkRateLimit(userId, action);
      expect(afterResetResult.allowed).toBe(true);
    });

    it('should only reset specific user-action pair', async () => {
      const userId = 'user123';
      const action1 = 'generate-summary';
      const action2 = 'discord-post';

      // Exhaust both limits
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action1);
      }
      for (let i = 0; i < 10; i++) {
        await rateLimiter.checkRateLimit(userId, action2);
      }

      // Reset only action1
      await rateLimiter.resetRateLimit(userId, action1);

      // action1 should be allowed, action2 still blocked
      const action1Result = await rateLimiter.checkRateLimit(userId, action1);
      const action2Result = await rateLimiter.checkRateLimit(userId, action2);

      expect(action1Result.allowed).toBe(true);
      expect(action2Result.allowed).toBe(false);
    });
  });

  describe('getStatistics', () => {
    it('should return statistics', () => {
      const stats = rateLimiter.getStatistics();

      expect(stats).toHaveProperty('totalTrackedUsers');
      expect(stats).toHaveProperty('totalPendingRequests');
      expect(stats).toHaveProperty('rateLimitConfigs');
    });

    it('should track user count', async () => {
      const stats1 = rateLimiter.getStatistics();
      const initialCount = stats1.totalTrackedUsers;

      // Add some users
      await rateLimiter.checkRateLimit('user1', 'generate-summary');
      await rateLimiter.checkRateLimit('user2', 'generate-summary');

      const stats2 = rateLimiter.getStatistics();

      expect(stats2.totalTrackedUsers).toBeGreaterThan(initialCount);
    });

    it('should track pending request count', async () => {
      const stats1 = rateLimiter.getStatistics();
      const initialCount = stats1.totalPendingRequests;

      // Add pending requests
      await rateLimiter.markRequestPending('user1', 'action1');
      await rateLimiter.markRequestPending('user2', 'action2');

      const stats2 = rateLimiter.getStatistics();

      expect(stats2.totalPendingRequests).toBe(initialCount + 2);
    });

    it('should include rate limit configs', () => {
      const stats = rateLimiter.getStatistics();

      expect(stats.rateLimitConfigs).toHaveProperty('generate-summary');
      expect(stats.rateLimitConfigs).toHaveProperty('google-docs-fetch');
      expect(stats.rateLimitConfigs).toHaveProperty('anthropic-api-call');
      expect(stats.rateLimitConfigs).toHaveProperty('discord-post');
      expect(stats.rateLimitConfigs).toHaveProperty('translate-document');
    });
  });

  describe('DoS attack scenarios', () => {
    it('should block rapid-fire requests from single user', async () => {
      const userId = 'attacker';
      const action = 'generate-summary';
      let blockedCount = 0;
      let allowedCount = 0;

      // Simulate 100 rapid requests
      for (let i = 0; i < 100; i++) {
        const result = await rateLimiter.checkRateLimit(userId, action);
        if (result.allowed) {
          allowedCount++;
        } else {
          blockedCount++;
        }
      }

      // Should only allow 5 requests (the limit)
      expect(allowedCount).toBe(5);
      expect(blockedCount).toBe(95);
    });

    it('should handle multiple users without interference', async () => {
      const action = 'generate-summary';
      const users = Array.from({ length: 10 }, (_, i) => `user${i}`);

      // Each user makes 5 requests (at their limit)
      const results = await Promise.all(
        users.map(async (userId) => {
          const userResults = [];
          for (let i = 0; i < 5; i++) {
            userResults.push(await rateLimiter.checkRateLimit(userId, action));
          }
          return userResults;
        })
      );

      // All users should be allowed their full quota
      results.forEach((userResults) => {
        userResults.forEach((result) => {
          expect(result.allowed).toBe(true);
        });
      });
    });

    it('should handle burst followed by sustained requests', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Burst: 5 requests immediately
      for (let i = 0; i < 5; i++) {
        const result = await rateLimiter.checkRateLimit(userId, action);
        expect(result.allowed).toBe(true);
      }

      // More requests should be blocked
      for (let i = 0; i < 10; i++) {
        const result = await rateLimiter.checkRateLimit(userId, action);
        expect(result.allowed).toBe(false);
      }
    });
  });

  describe('Edge cases', () => {
    it('should handle empty user ID', async () => {
      const result = await rateLimiter.checkRateLimit('', 'generate-summary');

      expect(result).toBeDefined();
      expect(result.allowed).toBeDefined();
    });

    it('should handle very long user IDs', async () => {
      const longUserId = 'a'.repeat(1000);
      const result = await rateLimiter.checkRateLimit(longUserId, 'generate-summary');

      expect(result).toBeDefined();
      expect(result.allowed).toBe(true);
    });

    it('should handle special characters in user ID', async () => {
      const userId = 'user@#$%^&*()';
      const result = await rateLimiter.checkRateLimit(userId, 'generate-summary');

      expect(result).toBeDefined();
      expect(result.allowed).toBe(true);
    });

    it('should handle concurrent requests from same user', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Simulate concurrent requests
      const results = await Promise.all([
        rateLimiter.checkRateLimit(userId, action),
        rateLimiter.checkRateLimit(userId, action),
        rateLimiter.checkRateLimit(userId, action),
      ]);

      // All should be processed
      results.forEach((result) => {
        expect(result).toBeDefined();
        expect(result.allowed).toBeDefined();
      });
    });
  });
});
