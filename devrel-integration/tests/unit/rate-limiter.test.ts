/**
 * Rate Limiter Tests
 *
 * Tests for CRITICAL-006: Rate Limiting & DoS Protection
 */

import { RateLimiter } from '../../src/services/rate-limiter';

describe('RateLimiter', () => {
  let rateLimiter: RateLimiter;

  beforeEach(() => {
    rateLimiter = new RateLimiter();
  });

  describe('checkRateLimit', () => {
    test('should allow requests within rate limit', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // First request should be allowed
      const result1 = await rateLimiter.checkRateLimit(userId, action);
      expect(result1.allowed).toBe(true);
      expect(result1.remainingRequests).toBe(4); // 5 total, 1 used

      // Second request should be allowed
      const result2 = await rateLimiter.checkRateLimit(userId, action);
      expect(result2.allowed).toBe(true);
      expect(result2.remainingRequests).toBe(3);
    });

    test('should block requests exceeding rate limit', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Make 5 requests (at limit)
      for (let i = 0; i < 5; i++) {
        const result = await rateLimiter.checkRateLimit(userId, action);
        expect(result.allowed).toBe(true);
      }

      // 6th request should be blocked
      const result = await rateLimiter.checkRateLimit(userId, action);
      expect(result.allowed).toBe(false);
      expect(result.message).toContain('Rate limit exceeded');
      expect(result.resetInMs).toBeDefined();
      expect(result.resetInMs).toBeGreaterThan(0);
    });

    test('should reset rate limit after time window expires', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Make 5 requests (at limit)
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      // 6th request should be blocked
      let result = await rateLimiter.checkRateLimit(userId, action);
      expect(result.allowed).toBe(false);

      // Wait for window to expire (simulate by resetting)
      await rateLimiter.resetRateLimit(userId, action);

      // Next request should be allowed
      result = await rateLimiter.checkRateLimit(userId, action);
      expect(result.allowed).toBe(true);
      expect(result.remainingRequests).toBe(4);
    });

    test('should enforce different limits for different actions', async () => {
      const userId = 'user123';

      // generate-summary: 5 requests/minute
      for (let i = 0; i < 5; i++) {
        const result = await rateLimiter.checkRateLimit(userId, 'generate-summary');
        expect(result.allowed).toBe(true);
      }
      const summaryResult = await rateLimiter.checkRateLimit(userId, 'generate-summary');
      expect(summaryResult.allowed).toBe(false);

      // google-docs-fetch: 100 requests/minute
      for (let i = 0; i < 100; i++) {
        const result = await rateLimiter.checkRateLimit(userId, 'google-docs-fetch');
        expect(result.allowed).toBe(true);
      }
      const docsResult = await rateLimiter.checkRateLimit(userId, 'google-docs-fetch');
      expect(docsResult.allowed).toBe(false);
    });

    test('should track limits per user independently', async () => {
      const user1 = 'user1';
      const user2 = 'user2';
      const action = 'generate-summary';

      // User 1 makes 5 requests (at limit)
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(user1, action);
      }

      // User 1 should be blocked
      const user1Result = await rateLimiter.checkRateLimit(user1, action);
      expect(user1Result.allowed).toBe(false);

      // User 2 should still be allowed
      const user2Result = await rateLimiter.checkRateLimit(user2, action);
      expect(user2Result.allowed).toBe(true);
      expect(user2Result.remainingRequests).toBe(4);
    });
  });

  describe('checkPendingRequest', () => {
    test('should return false when no pending request', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      const hasPending = await rateLimiter.checkPendingRequest(userId, action);
      expect(hasPending).toBe(false);
    });

    test('should return true when request is pending', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      await rateLimiter.markRequestPending(userId, action);

      const hasPending = await rateLimiter.checkPendingRequest(userId, action);
      expect(hasPending).toBe(true);
    });

    test('should return false after pending request cleared', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      await rateLimiter.markRequestPending(userId, action);
      await rateLimiter.clearPendingRequest(userId, action);

      const hasPending = await rateLimiter.checkPendingRequest(userId, action);
      expect(hasPending).toBe(false);
    });
  });

  describe('getRateLimitStatus', () => {
    test('should return current rate limit status', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Make 3 requests
      for (let i = 0; i < 3; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      const status = await rateLimiter.getRateLimitStatus(userId, action);
      expect(status.requestsInWindow).toBe(3);
      expect(status.maxRequests).toBe(5);
      expect(status.windowMs).toBe(60000);
      expect(status.resetInMs).toBeDefined();
    });

    test('should return zero requests when no activity', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      const status = await rateLimiter.getRateLimitStatus(userId, action);
      expect(status.requestsInWindow).toBe(0);
      expect(status.maxRequests).toBe(5);
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent CRITICAL-006 attack: 1000 rapid requests', async () => {
      const userId = 'malicious-user';
      const action = 'generate-summary';

      let allowedCount = 0;
      let blockedCount = 0;

      // Simulate 1000 rapid requests
      for (let i = 0; i < 1000; i++) {
        const result = await rateLimiter.checkRateLimit(userId, action);
        if (result.allowed) {
          allowedCount++;
        } else {
          blockedCount++;
        }
      }

      // Only first 5 requests should be allowed
      expect(allowedCount).toBe(5);
      expect(blockedCount).toBe(995);
    });

    test('should prevent concurrent request spam', async () => {
      const userId = 'malicious-user';
      const action = 'generate-summary';

      // Mark request as pending
      await rateLimiter.markRequestPending(userId, action);

      // Check pending status
      const hasPending = await rateLimiter.checkPendingRequest(userId, action);
      expect(hasPending).toBe(true);

      // Should still enforce rate limit even with pending request
      for (let i = 0; i < 5; i++) {
        await rateLimiter.checkRateLimit(userId, action);
      }

      const result = await rateLimiter.checkRateLimit(userId, action);
      expect(result.allowed).toBe(false);
    });
  });

  describe('Edge Cases', () => {
    test('should handle unknown action with default limit', async () => {
      const userId = 'user123';
      const action = 'unknown-action';

      // Make 10 requests (default limit)
      for (let i = 0; i < 10; i++) {
        const result = await rateLimiter.checkRateLimit(userId, action);
        expect(result.allowed).toBe(true);
      }

      // 11th request should be blocked
      const result = await rateLimiter.checkRateLimit(userId, action);
      expect(result.allowed).toBe(false);
    });

    test('should handle concurrent calls for same user', async () => {
      const userId = 'user123';
      const action = 'generate-summary';

      // Make concurrent calls
      const promises = Array(5).fill(null).map(() =>
        rateLimiter.checkRateLimit(userId, action)
      );

      const results = await Promise.all(promises);

      // All 5 concurrent calls should be allowed (at limit)
      results.forEach(result => {
        expect(result.allowed).toBe(true);
      });

      // Next call should be blocked
      const result = await rateLimiter.checkRateLimit(userId, action);
      expect(result.allowed).toBe(false);
    });
  });

  describe('Statistics', () => {
    test('should return rate limiter statistics', () => {
      const stats = rateLimiter.getStatistics();

      expect(stats.totalTrackedUsers).toBeDefined();
      expect(stats.totalPendingRequests).toBeDefined();
      expect(stats.rateLimitConfigs).toBeDefined();
      expect(stats.rateLimitConfigs['generate-summary']).toBeDefined();
      expect(stats.rateLimitConfigs['generate-summary'].maxRequests).toBe(5);
      expect(stats.rateLimitConfigs['generate-summary'].windowMs).toBe(60000);
    });
  });
});
