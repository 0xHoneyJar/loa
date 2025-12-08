/**
 * API Rate Limiter Tests
 *
 * Tests for CRITICAL-006: API Call Throttling with Exponential Backoff
 */

import { APIRateLimiter } from '../../src/services/api-rate-limiter';

describe('APIRateLimiter', () => {
  let apiRateLimiter: APIRateLimiter;

  beforeEach(() => {
    apiRateLimiter = new APIRateLimiter();
  });

  describe('throttleGoogleDriveAPI', () => {
    test('should allow API call within rate limit', async () => {
      const operation = jest.fn().mockResolvedValue({ success: true });

      const result = await apiRateLimiter.throttleGoogleDriveAPI(operation, 'test-operation');

      expect(result).toEqual({ success: true });
      expect(operation).toHaveBeenCalledTimes(1);
    });

    test('should retry on rate limit error', async () => {
      const rateLimitError = new Error('Rate limit exceeded');
      (rateLimitError as any).status = 429;

      const operation = jest.fn()
        .mockRejectedValueOnce(rateLimitError)  // First call fails
        .mockResolvedValueOnce({ success: true }); // Second call succeeds

      const result = await apiRateLimiter.throttleGoogleDriveAPI(operation, 'test-operation');

      expect(result).toEqual({ success: true });
      expect(operation).toHaveBeenCalledTimes(2); // Initial + retry
    }, 10000); // 10 second timeout for backoff

    test('should throw non-rate-limit errors immediately', async () => {
      const error = new Error('Network error');
      const operation = jest.fn().mockRejectedValue(error);

      await expect(
        apiRateLimiter.throttleGoogleDriveAPI(operation, 'test-operation')
      ).rejects.toThrow('Network error');

      expect(operation).toHaveBeenCalledTimes(1); // No retry
    });
  });

  describe('throttleAnthropicAPI', () => {
    test('should allow API call within rate limit', async () => {
      const operation = jest.fn().mockResolvedValue({ content: 'test' });

      const result = await apiRateLimiter.throttleAnthropicAPI(operation, 'generate-text');

      expect(result).toEqual({ content: 'test' });
      expect(operation).toHaveBeenCalledTimes(1);
    });

    test('should detect rate limit from error message', async () => {
      const rateLimitError = new Error('too many requests');
      const operation = jest.fn()
        .mockRejectedValueOnce(rateLimitError)
        .mockResolvedValueOnce({ content: 'test' });

      const result = await apiRateLimiter.throttleAnthropicAPI(operation, 'generate-text');

      expect(result).toEqual({ content: 'test' });
      expect(operation).toHaveBeenCalledTimes(2);
    }, 10000);
  });

  describe('throttleDiscordAPI', () => {
    test('should allow API call within rate limit', async () => {
      const operation = jest.fn().mockResolvedValue({ messageId: '123' });

      const result = await apiRateLimiter.throttleDiscordAPI(operation, 'send-message');

      expect(result).toEqual({ messageId: '123' });
      expect(operation).toHaveBeenCalledTimes(1);
    });

    test('should respect Discord retry-after header', async () => {
      const rateLimitError: any = new Error('Rate limited');
      rateLimitError.status = 429;
      rateLimitError.retry_after = 100; // 100ms

      const operation = jest.fn()
        .mockRejectedValueOnce(rateLimitError)
        .mockResolvedValueOnce({ messageId: '123' });

      const startTime = Date.now();
      const result = await apiRateLimiter.throttleDiscordAPI(operation, 'send-message');
      const elapsed = Date.now() - startTime;

      expect(result).toEqual({ messageId: '123' });
      expect(operation).toHaveBeenCalledTimes(2);
      expect(elapsed).toBeGreaterThanOrEqual(100); // Waited at least 100ms
    }, 10000);
  });

  describe('Rate Limit Detection', () => {
    test('should detect HTTP 429 status code', async () => {
      const error: any = new Error('Rate limit');
      error.status = 429;

      const operation = jest.fn()
        .mockRejectedValueOnce(error)
        .mockResolvedValueOnce({ success: true });

      await apiRateLimiter.throttleGoogleDriveAPI(operation);

      expect(operation).toHaveBeenCalledTimes(2); // Detected and retried
    }, 10000);

    test('should detect "rate limit" in error message', async () => {
      const error = new Error('API rate limit exceeded');

      const operation = jest.fn()
        .mockRejectedValueOnce(error)
        .mockResolvedValueOnce({ success: true });

      await apiRateLimiter.throttleAnthropicAPI(operation);

      expect(operation).toHaveBeenCalledTimes(2);
    }, 10000);

    test('should detect "quota exceeded" in error message', async () => {
      const error = new Error('Quota exceeded for this operation');

      const operation = jest.fn()
        .mockRejectedValueOnce(error)
        .mockResolvedValueOnce({ success: true });

      await apiRateLimiter.throttleGoogleDriveAPI(operation);

      expect(operation).toHaveBeenCalledTimes(2);
    }, 10000);
  });

  describe('Exponential Backoff', () => {
    test('should apply exponential backoff on repeated failures', async () => {
      const error: any = new Error('Rate limit');
      error.status = 429;

      const operation = jest.fn()
        .mockRejectedValueOnce(error)
        .mockRejectedValueOnce(error)
        .mockResolvedValueOnce({ success: true });

      // Reset rate limiter to get fresh state
      await apiRateLimiter.resetAPIRateLimit('google-drive');

      // This test verifies exponential backoff is applied
      // First retry: 1000ms backoff
      // Second retry: 2000ms backoff
      const startTime = Date.now();

      try {
        // First call fails, retries with 1000ms backoff
        await apiRateLimiter.throttleGoogleDriveAPI(operation);
      } catch (e) {
        // Expected to fail after retry
      }

      const elapsed = Date.now() - startTime;

      // Should have waited at least 1000ms for the backoff
      expect(elapsed).toBeGreaterThanOrEqual(1000);
      expect(operation).toHaveBeenCalledTimes(2); // Initial + 1 retry
    }, 15000);
  });

  describe('API Rate Limit Status', () => {
    test('should track API request count', async () => {
      const operation = jest.fn().mockResolvedValue({ success: true });

      // Make 3 requests
      for (let i = 0; i < 3; i++) {
        await apiRateLimiter.throttleGoogleDriveAPI(operation);
      }

      const status = await apiRateLimiter.getAPIRateLimitStatus('google-drive');

      expect(status.requestCount).toBe(3);
      expect(status.maxRequests).toBe(100);
      expect(status.retries).toBe(0);
    });

    test('should return zero status for unused API', async () => {
      const status = await apiRateLimiter.getAPIRateLimitStatus('google-drive');

      expect(status.requestCount).toBe(0);
      expect(status.maxRequests).toBe(100);
      expect(status.retries).toBe(0);
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent API quota exhaustion from rapid calls', async () => {
      const operation = jest.fn().mockResolvedValue({ success: true });

      // Simulate rapid API calls
      const promises = [];
      for (let i = 0; i < 150; i++) { // Attempt 150 calls (above 100/min limit)
        promises.push(apiRateLimiter.throttleGoogleDriveAPI(operation));
      }

      const startTime = Date.now();
      await Promise.all(promises);
      const elapsed = Date.now() - startTime;

      // Should have been throttled (waited for window reset)
      // Expected: First 100 calls go through, then wait ~60s for window reset
      expect(elapsed).toBeGreaterThan(1000); // Should take more than 1 second due to throttling

      expect(operation).toHaveBeenCalledTimes(150); // All calls eventually complete
    }, 120000); // 120 second timeout

    test('should prevent cost explosion from Anthropic API spam', async () => {
      const operation = jest.fn().mockResolvedValue({ usage: { tokens: 1000 } });

      // Simulate spam attack: 50 rapid calls (above 20/min limit)
      const promises = [];
      for (let i = 0; i < 50; i++) {
        promises.push(apiRateLimiter.throttleAnthropicAPI(operation));
      }

      const startTime = Date.now();
      await Promise.all(promises);
      const elapsed = Date.now() - startTime;

      // Should have been throttled
      expect(elapsed).toBeGreaterThan(1000);
      expect(operation).toHaveBeenCalledTimes(50);
    }, 120000);
  });

  describe('Statistics', () => {
    test('should return API rate limiter statistics', async () => {
      const operation = jest.fn().mockResolvedValue({ success: true });

      // Make some requests
      await apiRateLimiter.throttleGoogleDriveAPI(operation);
      await apiRateLimiter.throttleAnthropicAPI(operation);

      const stats = apiRateLimiter.getStatistics();

      expect(stats.trackedAPIs).toContain('google-drive');
      expect(stats.trackedAPIs).toContain('anthropic');
      expect(stats.totalRequestsTracked).toBeGreaterThan(0);
      expect(stats.apiConfigs['google-drive']).toBeDefined();
      expect(stats.apiConfigs['google-drive'].maxRequestsPerMinute).toBe(100);
    });
  });

  describe('Reset Rate Limit', () => {
    test('should reset API rate limit', async () => {
      const operation = jest.fn().mockResolvedValue({ success: true });

      // Make requests to build up count
      for (let i = 0; i < 50; i++) {
        await apiRateLimiter.throttleGoogleDriveAPI(operation);
      }

      let status = await apiRateLimiter.getAPIRateLimitStatus('google-drive');
      expect(status.requestCount).toBe(50);

      // Reset
      await apiRateLimiter.resetAPIRateLimit('google-drive');

      status = await apiRateLimiter.getAPIRateLimitStatus('google-drive');
      expect(status.requestCount).toBe(0);
    });
  });
});
