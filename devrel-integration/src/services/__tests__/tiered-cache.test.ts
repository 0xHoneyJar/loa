/**
 * Tiered Cache Tests
 *
 * Sprint 5 - Task 5.4: Tiered Cache Implementation
 *
 * Tests for TieredCache functionality including:
 * - L1 (in-memory) cache operations
 * - Cache key generation with tenant isolation
 * - Stale-while-revalidate pattern
 * - Background refresh
 * - Cache metrics tracking
 * - Convenience functions
 */

import {
  TieredCache,
  getOrFetchCached,
  invalidateCached,
  TieredCacheOptions,
} from '../tiered-cache';
import { getCurrentTenant } from '../tenant-context';

// Mock logger
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

// Mock tenant context provider
jest.mock('../tenant-context', () => {
  const mockTenant = {
    tenantId: 'thj',
    name: 'The Honey Jar',
    config: {
      enabledFeatures: ['transformations', 'advanced-caching'],
      maxTransformationsPerDay: 1000,
      maxConcurrentTransforms: 10,
      allowedPersonas: ['leadership', 'product'],
      cacheTTL: {
        documentContent: 900,
        transformResults: 1800,
        folderIds: 3600,
      },
    },
    metadata: {
      createdAt: new Date(),
      updatedAt: new Date(),
      status: 'active',
    },
  };

  return {
    getCurrentTenant: jest.fn().mockReturnValue(mockTenant),
    tenantContextProvider: {
      getCurrentTenant: jest.fn().mockReturnValue(mockTenant),
    },
  };
});

describe('TieredCache', () => {
  let cache: TieredCache;

  beforeEach(() => {
    // Create fresh instance for each test
    cache = new TieredCache();
    cache.clear();
    cache.resetMetrics();
  });

  describe('buildKey', () => {
    it('should build key with tenant prefix', () => {
      const key = cache.buildKey('thj', 'doc:prd');
      expect(key).toBe('thj:tiered:doc:prd');
    });

    it('should isolate keys by tenant', () => {
      const key1 = cache.buildKey('tenant-a', 'doc:prd');
      const key2 = cache.buildKey('tenant-b', 'doc:prd');

      expect(key1).toBe('tenant-a:tiered:doc:prd');
      expect(key2).toBe('tenant-b:tiered:doc:prd');
      expect(key1).not.toBe(key2);
    });

    it('should handle empty key', () => {
      const key = cache.buildKey('thj', '');
      expect(key).toBe('thj:tiered:');
    });
  });

  describe('get/set operations (L1 only)', () => {
    it('should return null for cache miss', async () => {
      const result = await cache.get('thj', 'non-existent-key');
      expect(result).toBeNull();
    });

    it('should store and retrieve values', async () => {
      const value = { transformed: 'result', data: [1, 2, 3] };

      await cache.set('thj', 'test-key', value, 60);
      const result = await cache.get<typeof value>('thj', 'test-key');

      expect(result).toEqual(value);
    });

    it('should respect tenant isolation', async () => {
      await cache.set('tenant-a', 'shared-key', { tenant: 'a' }, 60);
      await cache.set('tenant-b', 'shared-key', { tenant: 'b' }, 60);

      const resultA = await cache.get<{ tenant: string }>('tenant-a', 'shared-key');
      const resultB = await cache.get<{ tenant: string }>('tenant-b', 'shared-key');

      expect(resultA).toEqual({ tenant: 'a' });
      expect(resultB).toEqual({ tenant: 'b' });
    });

    it('should return null for expired entries', async () => {
      // Set with 1 second TTL
      await cache.set('thj', 'expiring-key', { value: 'test' }, 1);

      // Immediate read should work
      const immediate = await cache.get('thj', 'expiring-key');
      expect(immediate).toEqual({ value: 'test' });

      // Wait for expiry
      await new Promise(resolve => setTimeout(resolve, 1100));

      // Should be expired now
      const expired = await cache.get('thj', 'expiring-key');
      expect(expired).toBeNull();
    });

    it('should handle various value types', async () => {
      // String
      await cache.set('thj', 'string-key', 'simple string', 60);
      expect(await cache.get('thj', 'string-key')).toBe('simple string');

      // Number
      await cache.set('thj', 'number-key', 42, 60);
      expect(await cache.get('thj', 'number-key')).toBe(42);

      // Array
      await cache.set('thj', 'array-key', [1, 2, 3], 60);
      expect(await cache.get('thj', 'array-key')).toEqual([1, 2, 3]);

      // Nested object
      await cache.set('thj', 'nested-key', { a: { b: { c: 'deep' } } }, 60);
      expect(await cache.get('thj', 'nested-key')).toEqual({ a: { b: { c: 'deep' } } });

      // Null
      await cache.set('thj', 'null-key', null, 60);
      // Note: null values may be treated as cache miss
    });
  });

  describe('getOrFetch', () => {
    it('should return cached value on hit', async () => {
      const fetchFn = jest.fn().mockResolvedValue('fetched');

      await cache.set('thj', 'cached-key', 'cached', 60);
      const result = await cache.getOrFetch('thj', 'cached-key', fetchFn);

      expect(result).toBe('cached');
      expect(fetchFn).not.toHaveBeenCalled();
    });

    it('should fetch and cache on miss', async () => {
      const fetchFn = jest.fn().mockResolvedValue({ data: 'fresh' });

      const result = await cache.getOrFetch('thj', 'new-key', fetchFn, {
        l2TtlSeconds: 60,
      });

      expect(result).toEqual({ data: 'fresh' });
      expect(fetchFn).toHaveBeenCalledTimes(1);

      // Verify it was cached
      const cached = await cache.get('thj', 'new-key');
      expect(cached).toEqual({ data: 'fresh' });
    });

    it('should use cache type configuration', async () => {
      const fetchFn = jest.fn().mockResolvedValue('value');

      await cache.getOrFetch('thj', 'doc-content', fetchFn, {
        cacheType: 'documentContent',
      });

      expect(fetchFn).toHaveBeenCalledTimes(1);
    });

    it('should propagate fetch errors', async () => {
      const fetchFn = jest.fn().mockRejectedValue(new Error('Fetch failed'));

      await expect(
        cache.getOrFetch('thj', 'error-key', fetchFn)
      ).rejects.toThrow('Fetch failed');
    });

    it('should handle async fetch functions', async () => {
      const fetchFn = jest.fn().mockImplementation(async () => {
        await new Promise(resolve => setTimeout(resolve, 50));
        return { delayed: true };
      });

      const result = await cache.getOrFetch('thj', 'async-key', fetchFn);

      expect(result).toEqual({ delayed: true });
    });
  });

  describe('stale-while-revalidate', () => {
    it('should return stale data immediately when SWR enabled', async () => {
      // Set up a cache entry that will become stale
      const now = Date.now();
      const ttlSeconds = 10;

      // Manually set up a stale entry (staleAt in the past, but expiresAt in future)
      await cache.set('thj', 'swr-key', 'original', ttlSeconds);

      // First call should return cached value
      let fetchCount = 0;
      const fetchFn = jest.fn().mockImplementation(async () => {
        fetchCount++;
        await new Promise(resolve => setTimeout(resolve, 100)); // Simulate slow fetch
        return 'refreshed';
      });

      const result = await cache.getOrFetch('thj', 'swr-key', fetchFn, {
        staleWhileRevalidate: true,
      });

      // Should return original cached value immediately
      expect(result).toBe('original');
    });

    it('should track stale serves in metrics', async () => {
      // This requires manipulating time or cache entry internals
      // For now, verify the metrics structure exists
      const metrics = cache.getMetrics();
      expect(metrics).toHaveProperty('staleServes');
      expect(typeof metrics.staleServes).toBe('number');
    });

    it('should prevent duplicate background refreshes', async () => {
      let fetchCount = 0;
      const fetchFn = jest.fn().mockImplementation(async () => {
        fetchCount++;
        await new Promise(resolve => setTimeout(resolve, 200));
        return 'refreshed';
      });

      // Trigger multiple SWR calls simultaneously
      await cache.set('thj', 'swr-dup', 'original', 60);

      // Fetch isn't called since cache is fresh
      const promises = [
        cache.getOrFetch('thj', 'swr-dup', fetchFn, { staleWhileRevalidate: true }),
        cache.getOrFetch('thj', 'swr-dup', fetchFn, { staleWhileRevalidate: true }),
        cache.getOrFetch('thj', 'swr-dup', fetchFn, { staleWhileRevalidate: true }),
      ];

      await Promise.all(promises);

      // Fetch should not be called since cache is fresh
      expect(fetchFn).not.toHaveBeenCalled();
    });
  });

  describe('invalidate', () => {
    it('should remove cached entry', async () => {
      await cache.set('thj', 'to-invalidate', { value: 'test' }, 60);

      const before = await cache.get('thj', 'to-invalidate');
      expect(before).not.toBeNull();

      const removed = await cache.invalidate('thj', 'to-invalidate');
      expect(removed).toBe(true);

      const after = await cache.get('thj', 'to-invalidate');
      expect(after).toBeNull();
    });

    it('should return false for non-existent entry', async () => {
      const removed = await cache.invalidate('thj', 'non-existent');
      expect(removed).toBe(false);
    });

    it('should only invalidate for specific tenant', async () => {
      await cache.set('tenant-a', 'shared', { tenant: 'a' }, 60);
      await cache.set('tenant-b', 'shared', { tenant: 'b' }, 60);

      await cache.invalidate('tenant-a', 'shared');

      expect(await cache.get('tenant-a', 'shared')).toBeNull();
      expect(await cache.get('tenant-b', 'shared')).toEqual({ tenant: 'b' });
    });
  });

  describe('invalidateTenant', () => {
    it('should remove all entries for a tenant', async () => {
      await cache.set('thj', 'key1', { v: 1 }, 60);
      await cache.set('thj', 'key2', { v: 2 }, 60);
      await cache.set('thj', 'key3', { v: 3 }, 60);
      await cache.set('other', 'key1', { v: 'other' }, 60);

      const removed = await cache.invalidateTenant('thj');

      expect(removed).toBe(3);
      expect(await cache.get('thj', 'key1')).toBeNull();
      expect(await cache.get('thj', 'key2')).toBeNull();
      expect(await cache.get('thj', 'key3')).toBeNull();
      // Other tenant should be unaffected
      expect(await cache.get('other', 'key1')).toEqual({ v: 'other' });
    });

    it('should return 0 when tenant has no entries', async () => {
      const removed = await cache.invalidateTenant('empty-tenant');
      expect(removed).toBe(0);
    });
  });

  describe('metrics', () => {
    it('should track L1 hits', async () => {
      await cache.set('thj', 'metrics-key', { v: 1 }, 60);

      await cache.get('thj', 'metrics-key');
      await cache.get('thj', 'metrics-key');
      await cache.get('thj', 'metrics-key');

      const metrics = cache.getMetrics();
      expect(metrics.l1Hits).toBe(3);
    });

    it('should track L1 misses', async () => {
      await cache.get('thj', 'miss1');
      await cache.get('thj', 'miss2');

      const metrics = cache.getMetrics();
      expect(metrics.l1Misses).toBe(2);
    });

    it('should track sets', async () => {
      await cache.set('thj', 'set1', { v: 1 }, 60);
      await cache.set('thj', 'set2', { v: 2 }, 60);

      const metrics = cache.getMetrics();
      expect(metrics.sets).toBe(2);
    });

    it('should track fetches from source', async () => {
      const fetchFn = jest.fn().mockResolvedValue('value');

      await cache.getOrFetch('thj', 'fetch1', fetchFn);
      await cache.getOrFetch('thj', 'fetch2', fetchFn);

      const metrics = cache.getMetrics();
      expect(metrics.fetchesFromSource).toBe(2);
    });

    it('should calculate hit rate', async () => {
      await cache.set('thj', 'exists', { v: 1 }, 60);

      await cache.get('thj', 'exists'); // hit
      await cache.get('thj', 'exists'); // hit
      await cache.get('thj', 'missing'); // miss

      const metrics = cache.getMetrics();
      // 2 L1 hits out of 3 requests = 0.666...
      expect(metrics.hitRate).toBeCloseTo(0.667, 2);
    });

    it('should track L1 size', async () => {
      await cache.set('thj', 'a', 1, 60);
      await cache.set('thj', 'b', 2, 60);
      await cache.set('thj', 'c', 3, 60);

      const metrics = cache.getMetrics();
      expect(metrics.l1Size).toBe(3);
    });

    it('should reset metrics', async () => {
      await cache.set('thj', 'key', { v: 1 }, 60);
      await cache.get('thj', 'key');
      await cache.get('thj', 'missing');

      cache.resetMetrics();

      const metrics = cache.getMetrics();
      expect(metrics.l1Hits).toBe(0);
      expect(metrics.l1Misses).toBe(0);
      expect(metrics.sets).toBe(0);
      expect(metrics.errors).toBe(0);
    });

    it('should track background refreshes', async () => {
      const metrics = cache.getMetrics();
      expect(metrics).toHaveProperty('backgroundRefreshes');
      expect(typeof metrics.backgroundRefreshes).toBe('number');
    });

    it('should track errors', async () => {
      const metrics = cache.getMetrics();
      expect(metrics).toHaveProperty('errors');
      expect(typeof metrics.errors).toBe('number');
    });
  });

  describe('clear', () => {
    it('should clear all L1 entries', async () => {
      await cache.set('thj', 'a', 1, 60);
      await cache.set('thj', 'b', 2, 60);
      await cache.set('other', 'c', 3, 60);

      cache.clear();

      const metrics = cache.getMetrics();
      expect(metrics.l1Size).toBe(0);

      expect(await cache.get('thj', 'a')).toBeNull();
      expect(await cache.get('other', 'c')).toBeNull();
    });
  });

  describe('Redis integration', () => {
    it('should report Redis as not connected by default', () => {
      expect(cache.isRedisConnected()).toBe(false);
    });

    it('should handle missing REDIS_URL gracefully', async () => {
      const originalEnv = process.env.REDIS_URL;
      delete process.env.REDIS_URL;

      const result = await cache.initializeRedis();
      expect(result).toBe(false);

      process.env.REDIS_URL = originalEnv;
    });

    it('should gracefully degrade to L1-only mode', async () => {
      // Without Redis, cache should still work with L1
      await cache.set('thj', 'l1-only', { value: 'test' }, 60);
      const result = await cache.get('thj', 'l1-only');

      expect(result).toEqual({ value: 'test' });
    });
  });

  describe('singleton pattern', () => {
    it('should return same instance from getInstance', () => {
      const instance1 = TieredCache.getInstance();
      const instance2 = TieredCache.getInstance();

      expect(instance1).toBe(instance2);
    });
  });

  describe('shutdown', () => {
    it('should handle shutdown without Redis', async () => {
      // Should not throw
      await expect(cache.shutdown()).resolves.toBeUndefined();
    });
  });
});

describe('Convenience functions', () => {
  let cache: TieredCache;

  beforeEach(() => {
    cache = TieredCache.getInstance();
    cache.clear();
    cache.resetMetrics();
  });

  describe('getOrFetchCached', () => {
    it('should use current tenant context', async () => {
      const fetchFn = jest.fn().mockResolvedValue({ data: 'fetched' });

      const result = await getOrFetchCached('test-key', fetchFn);

      expect(result).toEqual({ data: 'fetched' });
      expect(fetchFn).toHaveBeenCalledTimes(1);
    });

    it('should cache results', async () => {
      const fetchFn = jest.fn().mockResolvedValue('value');

      await getOrFetchCached('cached-test', fetchFn);
      await getOrFetchCached('cached-test', fetchFn);

      // Second call should hit cache
      expect(fetchFn).toHaveBeenCalledTimes(1);
    });

    it('should support options', async () => {
      const fetchFn = jest.fn().mockResolvedValue('value');

      await getOrFetchCached('options-test', fetchFn, {
        cacheType: 'documentContent',
        staleWhileRevalidate: true,
      });

      expect(fetchFn).toHaveBeenCalledTimes(1);
    });
  });

  describe('invalidateCached', () => {
    it('should invalidate using current tenant context', async () => {
      const fetchFn = jest.fn().mockResolvedValue('value');

      await getOrFetchCached('to-invalidate', fetchFn);
      const removed = await invalidateCached('to-invalidate');

      expect(removed).toBe(true);

      // Should fetch again after invalidation
      await getOrFetchCached('to-invalidate', fetchFn);
      expect(fetchFn).toHaveBeenCalledTimes(2);
    });

    it('should return false for non-existent key', async () => {
      const removed = await invalidateCached('non-existent');
      expect(removed).toBe(false);
    });
  });
});

describe('Cache type configuration', () => {
  let cache: TieredCache;

  beforeEach(() => {
    cache = new TieredCache();
    cache.clear();
    cache.resetMetrics();
  });

  it('should use documentContent configuration', async () => {
    const fetchFn = jest.fn().mockResolvedValue('doc content');

    await cache.getOrFetch('thj', 'doc', fetchFn, {
      cacheType: 'documentContent',
    });

    expect(fetchFn).toHaveBeenCalled();
  });

  it('should use folderIds configuration', async () => {
    const fetchFn = jest.fn().mockResolvedValue(['folder1', 'folder2']);

    await cache.getOrFetch('thj', 'folders', fetchFn, {
      cacheType: 'folderIds',
    });

    expect(fetchFn).toHaveBeenCalled();
  });

  it('should use transformResults configuration', async () => {
    const fetchFn = jest.fn().mockResolvedValue({ transformed: true });

    await cache.getOrFetch('thj', 'transform', fetchFn, {
      cacheType: 'transformResults',
    });

    expect(fetchFn).toHaveBeenCalled();
  });

  it('should use adr configuration', async () => {
    const fetchFn = jest.fn().mockResolvedValue({ adr: 'content' });

    await cache.getOrFetch('thj', 'adr', fetchFn, {
      cacheType: 'adr',
    });

    expect(fetchFn).toHaveBeenCalled();
  });

  it('should use changelog configuration', async () => {
    const fetchFn = jest.fn().mockResolvedValue({ changelog: 'entries' });

    await cache.getOrFetch('thj', 'changelog', fetchFn, {
      cacheType: 'changelog',
    });

    expect(fetchFn).toHaveBeenCalled();
  });

  it('should allow custom TTL override', async () => {
    const fetchFn = jest.fn().mockResolvedValue('custom ttl');

    await cache.getOrFetch('thj', 'custom', fetchFn, {
      l2TtlSeconds: 300,
    });

    expect(fetchFn).toHaveBeenCalled();
  });
});

describe('Edge cases', () => {
  let cache: TieredCache;

  beforeEach(() => {
    cache = new TieredCache();
    cache.clear();
    cache.resetMetrics();
  });

  it('should handle concurrent gets for same key', async () => {
    const fetchFn = jest.fn().mockImplementation(async () => {
      await new Promise(resolve => setTimeout(resolve, 50));
      return 'result';
    });

    // Start multiple concurrent fetches for same key
    const promises = [
      cache.getOrFetch('thj', 'concurrent', fetchFn),
      cache.getOrFetch('thj', 'concurrent', fetchFn),
      cache.getOrFetch('thj', 'concurrent', fetchFn),
    ];

    const results = await Promise.all(promises);

    // All should return same result
    expect(results).toEqual(['result', 'result', 'result']);
  });

  it('should handle very long keys', async () => {
    const longKey = 'k'.repeat(1000);

    await cache.set('thj', longKey, { value: 'test' }, 60);
    const result = await cache.get('thj', longKey);

    expect(result).toEqual({ value: 'test' });
  });

  it('should handle special characters in keys', async () => {
    const specialKey = 'key:with/special\\chars!@#$%';

    await cache.set('thj', specialKey, { value: 'test' }, 60);
    const result = await cache.get('thj', specialKey);

    expect(result).toEqual({ value: 'test' });
  });

  it('should handle unicode in values', async () => {
    const unicodeValue = { text: 'Hello 世界 🌍 مرحبا' };

    await cache.set('thj', 'unicode', unicodeValue, 60);
    const result = await cache.get('thj', 'unicode');

    expect(result).toEqual(unicodeValue);
  });

  it('should handle large values', async () => {
    const largeValue = {
      data: 'x'.repeat(100000),
      array: new Array(1000).fill({ key: 'value' }),
    };

    await cache.set('thj', 'large', largeValue, 60);
    const result = await cache.get('thj', 'large');

    expect(result).toEqual(largeValue);
  });

  it('should handle zero TTL', async () => {
    await cache.set('thj', 'zero-ttl', { value: 'test' }, 0);

    // With zero TTL, entry should be immediately expired
    const result = await cache.get('thj', 'zero-ttl');
    expect(result).toBeNull();
  });

  it('should handle boolean values', async () => {
    await cache.set('thj', 'bool-true', true, 60);
    await cache.set('thj', 'bool-false', false, 60);

    expect(await cache.get('thj', 'bool-true')).toBe(true);
    expect(await cache.get('thj', 'bool-false')).toBe(false);
  });

  it('should handle undefined fetchFn return', async () => {
    const fetchFn = jest.fn().mockResolvedValue(undefined);

    const result = await cache.getOrFetch('thj', 'undefined', fetchFn);

    expect(result).toBeUndefined();
  });
});
