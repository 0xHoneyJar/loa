/**
 * Retry Handler Tests
 *
 * Tests for HIGH-004: Error Handling for Failed Translations
 */

import { RetryHandler, retry, RetryConfig } from '../retry-handler';

// Mock logger to avoid console noise
jest.mock('../../utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
}));

describe('RetryHandler', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Basic Retry Logic', () => {
    test('should succeed on first attempt', async () => {
      const handler = new RetryHandler();
      const mockFn = jest.fn().mockResolvedValue('success');

      const result = await handler.execute(mockFn, 'test-operation');

      expect(result.success).toBe(true);
      expect(result.result).toBe('success');
      expect(result.attempts).toBe(1);
      expect(mockFn).toHaveBeenCalledTimes(1);
    });

    test('should retry on failure and eventually succeed', async () => {
      const handler = new RetryHandler({ maxRetries: 3, initialDelayMs: 10 });
      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('Temporary failure'))
        .mockRejectedValueOnce(new Error('Temporary failure'))
        .mockResolvedValue('success');

      const result = await handler.execute(mockFn, 'test-operation');

      expect(result.success).toBe(true);
      expect(result.result).toBe('success');
      expect(result.attempts).toBe(3);
      expect(mockFn).toHaveBeenCalledTimes(3);
    });

    test('should exhaust retries and fail', async () => {
      const handler = new RetryHandler({ maxRetries: 2, initialDelayMs: 10 });
      const mockFn = jest.fn().mockRejectedValue(new Error('Permanent failure'));

      const result = await handler.execute(mockFn, 'test-operation');

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
      expect(result.error?.message).toBe('Permanent failure');
      expect(result.attempts).toBe(3); // Initial attempt + 2 retries
      expect(mockFn).toHaveBeenCalledTimes(3);
    });

    test('should return error details when all retries fail', async () => {
      const handler = new RetryHandler({ maxRetries: 1, initialDelayMs: 10 });
      const mockFn = jest.fn().mockRejectedValue(new Error('Service unavailable'));

      const result = await handler.execute(mockFn, 'api-call');

      expect(result.success).toBe(false);
      expect(result.error?.message).toBe('Service unavailable');
      expect(result.attempts).toBe(2);
    });
  });

  describe('Exponential Backoff', () => {
    test('should use exponential backoff (1s, 2s, 4s)', async () => {
      const handler = new RetryHandler({
        maxRetries: 3,
        initialDelayMs: 1000,
        backoffMultiplier: 2,
      });

      const delays: number[] = [];
      let onRetryCalls = 0;

      handler.updateConfig({
        onRetry: (_error, _attemptNumber, delayMs) => {
          delays.push(delayMs);
          onRetryCalls++;
        },
      });

      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('Fail 1'))
        .mockRejectedValueOnce(new Error('Fail 2'))
        .mockRejectedValueOnce(new Error('Fail 3'))
        .mockRejectedValue(new Error('Fail 4'));

      await handler.execute(mockFn, 'test-backoff');

      expect(onRetryCalls).toBe(3);
      expect(delays[0]).toBe(1000); // 1s
      expect(delays[1]).toBe(2000); // 2s
      expect(delays[2]).toBe(4000); // 4s
    });

    test('should respect max delay', async () => {
      const handler = new RetryHandler({
        maxRetries: 5,
        initialDelayMs: 10,
        backoffMultiplier: 2,
        maxDelayMs: 30, // Cap at 30ms
      });

      const delays: number[] = [];

      handler.updateConfig({
        onRetry: (_error, _attemptNumber, delayMs) => {
          delays.push(delayMs);
        },
      });

      const mockFn = jest.fn().mockRejectedValue(new Error('Fail'));

      await handler.execute(mockFn, 'test-max-delay');

      expect(delays[0]).toBe(10); // 10ms
      expect(delays[1]).toBe(20); // 20ms
      expect(delays[2]).toBe(30); // 40ms capped at 30ms
      expect(delays[3]).toBe(30); // 80ms capped at 30ms
      expect(delays[4]).toBe(30); // 160ms capped at 30ms
    });
  });

  describe('Custom Retry Conditions', () => {
    test('should retry only on network errors', async () => {
      const shouldRetry = (error: Error, attemptNumber: number) => {
        return error.message.includes('network') && attemptNumber <= 3;
      };

      const handler = new RetryHandler({
        maxRetries: 3,
        initialDelayMs: 10,
        shouldRetry,
      });

      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('network timeout'))
        .mockRejectedValueOnce(new Error('network timeout'))
        .mockResolvedValue('success');

      const result = await handler.execute(mockFn, 'network-test');

      expect(result.success).toBe(true);
      expect(result.attempts).toBe(3);
    });

    test('should not retry on client errors (4xx)', async () => {
      const handler = new RetryHandler({ maxRetries: 3, initialDelayMs: 10 });
      const mockFn = jest.fn().mockRejectedValue(new Error('400 Bad Request'));

      const result = await handler.execute(mockFn, 'client-error-test');

      expect(result.success).toBe(false);
      expect(result.attempts).toBe(1); // No retries for 4xx
      expect(mockFn).toHaveBeenCalledTimes(1);
    });

    test('should retry on server errors (5xx)', async () => {
      const handler = new RetryHandler({ maxRetries: 2, initialDelayMs: 10 });
      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('503 Service Unavailable'))
        .mockResolvedValue('success');

      const result = await handler.execute(mockFn, 'server-error-test');

      expect(result.success).toBe(true);
      expect(result.attempts).toBe(2);
    });

    test('should retry on rate limit errors (429)', async () => {
      const handler = new RetryHandler({ maxRetries: 2, initialDelayMs: 10 });
      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('429 Too Many Requests'))
        .mockResolvedValue('success');

      const result = await handler.execute(mockFn, 'rate-limit-test');

      expect(result.success).toBe(true);
      expect(result.attempts).toBe(2);
    });
  });

  describe('Timeout Handling', () => {
    test('should timeout long-running operations', async () => {
      const handler = new RetryHandler({
        maxRetries: 1,
        initialDelayMs: 10,
        timeoutMs: 100, // 100ms timeout
      });

      const mockFn = jest.fn().mockImplementation(
        () =>
          new Promise(resolve => {
            setTimeout(() => resolve('too slow'), 500);
          })
      );

      const result = await handler.execute(mockFn, 'timeout-test');

      expect(result.success).toBe(false);
      expect(result.error?.message).toContain('timed out');
    });

    test('should not timeout fast operations', async () => {
      const handler = new RetryHandler({
        maxRetries: 1,
        initialDelayMs: 10,
        timeoutMs: 1000, // 1s timeout
      });

      const mockFn = jest.fn().mockImplementation(
        () =>
          new Promise(resolve => {
            setTimeout(() => resolve('fast'), 50);
          })
      );

      const result = await handler.execute(mockFn, 'no-timeout-test');

      expect(result.success).toBe(true);
      expect(result.result).toBe('fast');
    });
  });

  describe('Callbacks', () => {
    test('should invoke onRetry callback', async () => {
      const onRetry = jest.fn();
      const handler = new RetryHandler({
        maxRetries: 2,
        initialDelayMs: 10,
        onRetry,
      });

      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('Fail 1'))
        .mockRejectedValueOnce(new Error('Fail 2'))
        .mockResolvedValue('success');

      await handler.execute(mockFn, 'callback-test');

      expect(onRetry).toHaveBeenCalledTimes(2);
      expect(onRetry).toHaveBeenCalledWith(expect.any(Error), 1, 10);
      expect(onRetry).toHaveBeenCalledWith(expect.any(Error), 2, 20);
    });
  });

  describe('Configuration', () => {
    test('should use custom configuration', async () => {
      const config: RetryConfig = {
        maxRetries: 5,
        initialDelayMs: 500,
        backoffMultiplier: 3,
        maxDelayMs: 5000,
        timeoutMs: 10000,
      };

      const handler = new RetryHandler(config);
      const actualConfig = handler.getConfig();

      expect(actualConfig.maxRetries).toBe(5);
      expect(actualConfig.initialDelayMs).toBe(500);
      expect(actualConfig.backoffMultiplier).toBe(3);
      expect(actualConfig.maxDelayMs).toBe(5000);
      expect(actualConfig.timeoutMs).toBe(10000);
    });

    test('should allow config updates', async () => {
      const handler = new RetryHandler({ maxRetries: 2 });

      handler.updateConfig({ maxRetries: 5, initialDelayMs: 100 });

      const config = handler.getConfig();
      expect(config.maxRetries).toBe(5);
      expect(config.initialDelayMs).toBe(100);
    });
  });

  describe('Convenience Function', () => {
    test('should work with retry() convenience function', async () => {
      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('Temporary'))
        .mockResolvedValue('success');

      const result = await retry(mockFn, { maxRetries: 2, initialDelayMs: 10 }, 'convenience-test');

      expect(result).toBe('success');
      expect(mockFn).toHaveBeenCalledTimes(2);
    });

    test('should throw error when retries exhausted', async () => {
      const mockFn = jest.fn().mockRejectedValue(new Error('Permanent failure'));

      await expect(
        retry(mockFn, { maxRetries: 1, initialDelayMs: 10 }, 'fail-test')
      ).rejects.toThrow('Permanent failure');

      expect(mockFn).toHaveBeenCalledTimes(2);
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent HIGH-004 attack: cascading failures from translation API', async () => {
      // Attack Scenario:
      // - Anthropic API experiences temporary outage
      // - Without retry logic, all translation requests fail immediately
      // - Users flood support with "translation broken" messages
      // - Service appears completely down despite API being intermittent

      const handler = new RetryHandler({
        maxRetries: 3,
        initialDelayMs: 1000,
        backoffMultiplier: 2,
      });

      // Simulate intermittent API failure (fails twice, then succeeds)
      const anthropicAPI = jest
        .fn()
        .mockRejectedValueOnce(new Error('503 Service Unavailable'))
        .mockRejectedValueOnce(new Error('503 Service Unavailable'))
        .mockResolvedValue({ translation: 'Executive Summary...' });

      const result = await handler.execute(anthropicAPI, 'translation-api-call');

      // After fix: Retries succeeded, translation delivered
      expect(result.success).toBe(true);
      expect(result.result).toEqual({ translation: 'Executive Summary...' });
      expect(result.attempts).toBe(3);
      expect(anthropicAPI).toHaveBeenCalledTimes(3);

      // Without fix: Would have failed on first attempt, no retry
    });

    test('should handle network timeout gracefully with retries', async () => {
      const handler = new RetryHandler({
        maxRetries: 2,
        initialDelayMs: 10,
        timeoutMs: 100,
      });

      // Simulate network timeout followed by successful response
      const networkCall = jest
        .fn()
        .mockImplementationOnce(
          () =>
            new Promise((_, reject) => {
              setTimeout(() => reject(new Error('ETIMEDOUT')), 200);
            })
        )
        .mockResolvedValue('success');

      const result = await handler.execute(networkCall, 'network-test');

      expect(result.success).toBe(true);
      expect(result.attempts).toBe(2);
    });

    test('should prevent service degradation from rate limiting', async () => {
      // Scenario: Anthropic API rate limit hit
      // With retries, we wait and retry instead of failing immediately

      const handler = new RetryHandler({
        maxRetries: 3,
        initialDelayMs: 1000,
      });

      const rateLimitedAPI = jest
        .fn()
        .mockRejectedValueOnce(new Error('429 Rate limit exceeded'))
        .mockResolvedValue('success');

      const result = await handler.execute(rateLimitedAPI, 'rate-limited-api');

      expect(result.success).toBe(true);
      expect(result.attempts).toBe(2);
    });
  });

  describe('Duration Tracking', () => {
    test('should track total duration', async () => {
      const handler = new RetryHandler({ maxRetries: 2, initialDelayMs: 50 });
      const mockFn = jest
        .fn()
        .mockRejectedValueOnce(new Error('Fail'))
        .mockResolvedValue('success');

      const result = await handler.execute(mockFn, 'duration-test');

      expect(result.totalDurationMs).toBeGreaterThan(0);
      // Should include at least one 50ms delay
      expect(result.totalDurationMs).toBeGreaterThanOrEqual(50);
    });
  });
});
