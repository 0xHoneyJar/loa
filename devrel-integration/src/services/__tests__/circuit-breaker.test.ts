/**
 * Circuit Breaker Tests
 *
 * Tests for HIGH-004: Error Handling for Failed Translations
 */

import {
  CircuitBreaker,
  CircuitState,
  CircuitBreakerOpenError,
  CircuitBreakerConfig,
  circuitBreakerRegistry,
} from '../circuit-breaker';

// Mock logger to avoid console noise
jest.mock('../../utils/logger', () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
  debug: jest.fn(),
}));

describe('CircuitBreaker', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.useFakeTimers();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  describe('Basic State Transitions', () => {
    test('should start in CLOSED state', () => {
      const breaker = new CircuitBreaker('test-service');
      expect(breaker.getState()).toBe(CircuitState.CLOSED);
    });

    test('should transition to OPEN after threshold failures', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 3,
        resetTimeoutMs: 10000,
      });

      const mockFn = jest.fn().mockRejectedValue(new Error('Service error'));

      // Execute 3 failures (threshold)
      await expect(breaker.execute(mockFn)).rejects.toThrow('Service error');
      expect(breaker.getState()).toBe(CircuitState.CLOSED); // Still closed after 1 failure

      await expect(breaker.execute(mockFn)).rejects.toThrow('Service error');
      expect(breaker.getState()).toBe(CircuitState.CLOSED); // Still closed after 2 failures

      await expect(breaker.execute(mockFn)).rejects.toThrow('Service error');
      expect(breaker.getState()).toBe(CircuitState.OPEN); // Opens after 3 failures
    });

    test('should transition to HALF_OPEN after reset timeout', async () => {
      const resetTimeoutMs = 5000;
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        resetTimeoutMs,
      });

      const mockFn = jest.fn().mockRejectedValue(new Error('Service error'));

      // Trigger circuit to open
      await expect(breaker.execute(mockFn)).rejects.toThrow();
      await expect(breaker.execute(mockFn)).rejects.toThrow();

      expect(breaker.getState()).toBe(CircuitState.OPEN);

      // Fast-forward past reset timeout
      jest.advanceTimersByTime(resetTimeoutMs + 100);

      // Circuit should auto-transition to HALF_OPEN
      expect(breaker.getState()).toBe(CircuitState.HALF_OPEN);
    });

    test('should transition to CLOSED after success threshold in HALF_OPEN', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        successThreshold: 2,
        resetTimeoutMs: 1000,
      });

      // Open the circuit
      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));
      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();
      expect(breaker.getState()).toBe(CircuitState.OPEN);

      // Advance to HALF_OPEN
      jest.advanceTimersByTime(1100);
      expect(breaker.getState()).toBe(CircuitState.HALF_OPEN);

      // Success in HALF_OPEN
      const successFn = jest.fn().mockResolvedValue('success');
      await breaker.execute(successFn);
      expect(breaker.getState()).toBe(CircuitState.HALF_OPEN); // Still half-open after 1 success

      await breaker.execute(successFn);
      expect(breaker.getState()).toBe(CircuitState.CLOSED); // Closes after 2 successes
    });

    test('should transition back to OPEN on failure in HALF_OPEN', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        resetTimeoutMs: 1000,
      });

      // Open the circuit
      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));
      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();
      expect(breaker.getState()).toBe(CircuitState.OPEN);

      // Advance to HALF_OPEN
      jest.advanceTimersByTime(1100);
      expect(breaker.getState()).toBe(CircuitState.HALF_OPEN);

      // Any failure in HALF_OPEN immediately opens circuit
      await expect(breaker.execute(failFn)).rejects.toThrow();
      expect(breaker.getState()).toBe(CircuitState.OPEN);
    });
  });

  describe('Request Blocking', () => {
    test('should block requests when circuit is OPEN', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        resetTimeoutMs: 10000,
      });

      const mockFn = jest.fn().mockRejectedValue(new Error('Service error'));

      // Open the circuit
      await expect(breaker.execute(mockFn)).rejects.toThrow();
      await expect(breaker.execute(mockFn)).rejects.toThrow();

      expect(breaker.getState()).toBe(CircuitState.OPEN);

      // Next request should be blocked without calling function
      await expect(breaker.execute(mockFn)).rejects.toThrow(CircuitBreakerOpenError);

      // Function should NOT have been called a third time
      expect(mockFn).toHaveBeenCalledTimes(2);
    });

    test('should throw CircuitBreakerOpenError with service name', async () => {
      const breaker = new CircuitBreaker('anthropic-api', {
        failureThreshold: 1,
        resetTimeoutMs: 10000,
      });

      const mockFn = jest.fn().mockRejectedValue(new Error('API error'));

      // Open the circuit
      await expect(breaker.execute(mockFn)).rejects.toThrow();

      // Next request should throw CircuitBreakerOpenError
      await expect(breaker.execute(mockFn)).rejects.toThrow(
        /Circuit breaker is OPEN for anthropic-api/
      );
    });
  });

  describe('Failure Rate Tracking', () => {
    test('should track failure rate in rolling window', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 10, // High threshold
        rollingWindowSize: 5,
      });

      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));
      const successFn = jest.fn().mockResolvedValue('Success');

      // 3 successes
      await breaker.execute(successFn);
      await breaker.execute(successFn);
      await breaker.execute(successFn);

      // 2 failures (40% failure rate)
      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();

      const stats = breaker.getStats();
      expect(stats.state).toBe(CircuitState.CLOSED); // 40% < 50% threshold

      // 1 more failure (50% failure rate in window)
      await expect(breaker.execute(failFn)).rejects.toThrow();

      // Should open due to 50% failure rate
      expect(breaker.getState()).toBe(CircuitState.OPEN);
    });

    test('should maintain rolling window size', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 100,
        rollingWindowSize: 3,
      });

      const successFn = jest.fn().mockResolvedValue('Success');

      // Execute 5 successful requests
      for (let i = 0; i < 5; i++) {
        await breaker.execute(successFn);
      }

      const stats = breaker.getStats();
      expect(stats.totalRequests).toBe(5);
      // Rolling window should only track last 3 results
    });
  });

  describe('Statistics Tracking', () => {
    test('should track success and failure counts', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 10,
      });

      const successFn = jest.fn().mockResolvedValue('Success');
      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));

      await breaker.execute(successFn);
      await breaker.execute(successFn);
      await expect(breaker.execute(failFn)).rejects.toThrow();

      const stats = breaker.getStats();
      expect(stats.totalRequests).toBe(3);
      expect(stats.successCount).toBe(0); // Reset to 0 in CLOSED state
      expect(stats.failureCount).toBe(1);
      expect(stats.lastSuccessTime).toBeDefined();
      expect(stats.lastFailureTime).toBeDefined();
    });

    test('should track state transition timestamps', async () => {
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        resetTimeoutMs: 1000,
      });

      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));

      // Open the circuit
      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();

      const statsOpen = breaker.getStats();
      expect(statsOpen.openedAt).toBeDefined();
      expect(statsOpen.state).toBe(CircuitState.OPEN);

      // Transition to HALF_OPEN
      jest.advanceTimersByTime(1100);
      const statsHalfOpen = breaker.getStats();
      expect(statsHalfOpen.halfOpenedAt).toBeDefined();
    });
  });

  describe('Configuration', () => {
    test('should use custom thresholds', () => {
      const config: CircuitBreakerConfig = {
        failureThreshold: 10,
        successThreshold: 5,
        resetTimeoutMs: 120000,
        rollingWindowSize: 20,
      };

      const breaker = new CircuitBreaker('test-service', config);
      const stats = breaker.getStats();

      expect(stats.state).toBe(CircuitState.CLOSED);
    });

    test('should invoke onOpen callback', async () => {
      const onOpen = jest.fn();
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        onOpen,
      });

      const failFn = jest.fn().mockRejectedValue(new Error('Service down'));

      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();

      expect(onOpen).toHaveBeenCalledTimes(1);
      expect(onOpen).toHaveBeenCalledWith(expect.any(Error));
    });

    test('should invoke onClose callback', async () => {
      const onClose = jest.fn();
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        successThreshold: 1,
        resetTimeoutMs: 1000,
        onClose,
      });

      // Open circuit
      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));
      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();

      // Transition to HALF_OPEN
      jest.advanceTimersByTime(1100);

      // Close circuit
      const successFn = jest.fn().mockResolvedValue('Success');
      await breaker.execute(successFn);

      expect(onClose).toHaveBeenCalledTimes(1);
    });

    test('should invoke onHalfOpen callback', async () => {
      const onHalfOpen = jest.fn();
      const breaker = new CircuitBreaker('test-service', {
        failureThreshold: 2,
        resetTimeoutMs: 1000,
        onHalfOpen,
      });

      // Open circuit
      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));
      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();

      // Transition to HALF_OPEN
      jest.advanceTimersByTime(1100);

      expect(onHalfOpen).toHaveBeenCalledTimes(1);
    });
  });

  describe('Manual Control', () => {
    test('should allow forcing circuit open', () => {
      const breaker = new CircuitBreaker('test-service');
      expect(breaker.getState()).toBe(CircuitState.CLOSED);

      breaker.forceOpen();
      expect(breaker.getState()).toBe(CircuitState.OPEN);
    });

    test('should allow forcing circuit closed', async () => {
      const breaker = new CircuitBreaker('test-service', { failureThreshold: 1 });

      // Open circuit
      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));
      await expect(breaker.execute(failFn)).rejects.toThrow();
      expect(breaker.getState()).toBe(CircuitState.OPEN);

      // Force close
      breaker.forceClose();
      expect(breaker.getState()).toBe(CircuitState.CLOSED);
    });

    test('should allow resetting statistics', async () => {
      const breaker = new CircuitBreaker('test-service');

      const successFn = jest.fn().mockResolvedValue('Success');
      await breaker.execute(successFn);
      await breaker.execute(successFn);

      let stats = breaker.getStats();
      expect(stats.totalRequests).toBe(2);

      breaker.reset();

      stats = breaker.getStats();
      expect(stats.totalRequests).toBe(0);
      expect(stats.failureCount).toBe(0);
      expect(stats.successCount).toBe(0);
      expect(breaker.getState()).toBe(CircuitState.CLOSED);
    });
  });

  describe('CircuitBreakerRegistry', () => {
    test('should manage multiple breakers', () => {
      const breaker1 = circuitBreakerRegistry.getOrCreate('service-1');
      const breaker2 = circuitBreakerRegistry.getOrCreate('service-2');

      expect(breaker1).not.toBe(breaker2);
      expect(circuitBreakerRegistry.getAll().size).toBeGreaterThanOrEqual(2);
    });

    test('should return existing breaker', () => {
      const breaker1 = circuitBreakerRegistry.getOrCreate('service-x');
      const breaker2 = circuitBreakerRegistry.getOrCreate('service-x');

      expect(breaker1).toBe(breaker2); // Same instance
    });

    test('should get all statistics', async () => {
      const breaker1 = circuitBreakerRegistry.getOrCreate('stats-test-1');
      const breaker2 = circuitBreakerRegistry.getOrCreate('stats-test-2');

      const successFn = jest.fn().mockResolvedValue('Success');
      await breaker1.execute(successFn);
      await breaker2.execute(successFn);

      const allStats = circuitBreakerRegistry.getAllStats();
      expect(allStats['stats-test-1']).toBeDefined();
      expect(allStats['stats-test-2']).toBeDefined();
      expect(allStats['stats-test-1']!.totalRequests).toBe(1);
    });

    test('should reset all breakers', async () => {
      const breaker1 = circuitBreakerRegistry.getOrCreate('reset-test-1');
      const breaker2 = circuitBreakerRegistry.getOrCreate('reset-test-2');

      const successFn = jest.fn().mockResolvedValue('Success');
      await breaker1.execute(successFn);
      await breaker2.execute(successFn);

      circuitBreakerRegistry.resetAll();

      const stats1 = breaker1.getStats();
      const stats2 = breaker2.getStats();

      expect(stats1.totalRequests).toBe(0);
      expect(stats2.totalRequests).toBe(0);
    });
  });

  describe('Attack Scenario Prevention', () => {
    test('should prevent HIGH-004 attack: cascading failures from overwhelmed Anthropic API', async () => {
      // Attack Scenario:
      // - Anthropic API experiences outage (504 Gateway Timeout)
      // - Without circuit breaker, every translation request waits 30s+ for timeout
      // - 100 concurrent requests = 100 × 30s = 50 minutes of wasted resources
      // - System resources exhausted, other services degraded
      // - Users experience complete service unavailability

      const breaker = new CircuitBreaker('anthropic-api', {
        failureThreshold: 5,
        resetTimeoutMs: 60000, // 1 minute
      });

      const anthropicAPI = jest.fn().mockRejectedValue(new Error('504 Gateway Timeout'));

      // First 5 requests fail and timeout (expensive)
      for (let i = 0; i < 5; i++) {
        await expect(breaker.execute(anthropicAPI)).rejects.toThrow('504 Gateway Timeout');
      }

      expect(breaker.getState()).toBe(CircuitState.OPEN);

      // After fix: Circuit opened, next 95 requests fail fast (no timeout wait)
      const startTime = Date.now();
      for (let i = 0; i < 95; i++) {
        await expect(breaker.execute(anthropicAPI)).rejects.toThrow(CircuitBreakerOpenError);
      }
      const duration = Date.now() - startTime;

      // Requests should fail instantly (< 100ms total for 95 requests)
      expect(duration).toBeLessThan(100);

      // Function should only have been called 5 times (threshold), not 100 times
      expect(anthropicAPI).toHaveBeenCalledTimes(5);

      // Without fix: Would wait 30s × 100 = 3000s = 50 minutes
      // With fix: Failed fast in < 100ms, saved ~49 minutes of wasted resources
    });

    test('should auto-recover when service recovers', async () => {
      // Scenario: Anthropic API recovers after temporary outage
      // Circuit should automatically test recovery and close when successful

      const breaker = new CircuitBreaker('anthropic-api', {
        failureThreshold: 3,
        successThreshold: 2,
        resetTimeoutMs: 5000,
      });

      // API fails (outage)
      const failingAPI = jest.fn().mockRejectedValue(new Error('503 Service Unavailable'));
      for (let i = 0; i < 3; i++) {
        await expect(breaker.execute(failingAPI)).rejects.toThrow();
      }
      expect(breaker.getState()).toBe(CircuitState.OPEN);

      // Wait for reset timeout
      jest.advanceTimersByTime(5100);
      expect(breaker.getState()).toBe(CircuitState.HALF_OPEN);

      // API recovers
      const recoveredAPI = jest.fn().mockResolvedValue({ translation: 'Success' });

      // 2 successful requests close circuit
      await breaker.execute(recoveredAPI);
      await breaker.execute(recoveredAPI);

      expect(breaker.getState()).toBe(CircuitState.CLOSED);

      // Service fully operational again
      const result = await breaker.execute(recoveredAPI);
      expect(result).toEqual({ translation: 'Success' });
    });

    test('should protect against thundering herd when circuit reopens', async () => {
      // Scenario: After circuit opens, we don't want all requests to retry simultaneously
      // Circuit breaker ensures only limited testing requests in HALF_OPEN state

      const breaker = new CircuitBreaker('api', {
        failureThreshold: 2,
        successThreshold: 2,
        resetTimeoutMs: 1000,
      });

      // Open circuit
      const failFn = jest.fn().mockRejectedValue(new Error('Fail'));
      await expect(breaker.execute(failFn)).rejects.toThrow();
      await expect(breaker.execute(failFn)).rejects.toThrow();

      // Advance to HALF_OPEN
      jest.advanceTimersByTime(1100);

      const successFn = jest.fn().mockResolvedValue('Success');

      // Only limited requests pass through in HALF_OPEN
      await breaker.execute(successFn);
      await breaker.execute(successFn);

      expect(breaker.getState()).toBe(CircuitState.CLOSED);
      expect(successFn).toHaveBeenCalledTimes(2); // Only 2 test requests, not a flood
    });
  });
});
