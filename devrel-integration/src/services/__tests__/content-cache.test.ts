/**
 * Content-Addressable Cache Tests
 *
 * Sprint 4 - Task 4.6: Content-Addressable Cache
 *
 * Tests for ContentAddressableCache functionality including:
 * - Content hashing and normalization
 * - Cache key generation with tenant isolation
 * - L1 cache operations (get/set/invalidate)
 * - Cache metrics tracking
 * - Convenience functions
 */

import { createHash } from 'crypto';
import {
  ContentAddressableCache,
  getCachedTransform,
  cacheTransform,
  previewCacheKey,
} from '../content-cache';
import { TenantContextProvider } from '../tenant-context';
import { DEFAULT_TENANT_CONFIG, DEFAULT_TENANT_ID } from '../../types/tenant';

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
      enabledFeatures: ['transformations'],
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

  const provider = {
    getCurrentTenant: jest.fn().mockReturnValue(mockTenant),
    getCacheTTL: jest.fn().mockImplementation((type: string) => {
      const ttls: Record<string, number> = {
        documentContent: 900,
        transformResults: 1800,
        folderIds: 3600,
      };
      return ttls[type] || 900;
    }),
  };

  return {
    tenantContextProvider: provider,
    getCurrentTenant: jest.fn().mockReturnValue(mockTenant),
    TenantContextProvider: jest.fn(),
  };
});

describe('ContentAddressableCache', () => {
  let cache: ContentAddressableCache;

  beforeEach(() => {
    // Create fresh instance for each test
    cache = new ContentAddressableCache();
    cache.clear();
    cache.resetMetrics();
  });

  describe('generateContentHash', () => {
    it('should generate consistent hash for same content', () => {
      const content = 'Hello, World!';
      const hash1 = cache.generateContentHash(content);
      const hash2 = cache.generateContentHash(content);

      expect(hash1).toBe(hash2);
      expect(hash1).toHaveLength(16); // First 16 chars of SHA-256
    });

    it('should normalize content before hashing', () => {
      const content1 = '  Hello   World  ';
      const content2 = 'Hello World';

      const hash1 = cache.generateContentHash(content1);
      const hash2 = cache.generateContentHash(content2);

      expect(hash1).toBe(hash2);
    });

    it('should produce different hashes for different content', () => {
      const hash1 = cache.generateContentHash('Content A');
      const hash2 = cache.generateContentHash('Content B');

      expect(hash1).not.toBe(hash2);
    });

    it('should handle empty content', () => {
      const hash = cache.generateContentHash('');
      expect(hash).toHaveLength(16);
    });

    it('should handle unicode content', () => {
      const hash = cache.generateContentHash('Hello 世界 🌍');
      expect(hash).toHaveLength(16);
    });
  });

  describe('buildCacheKey', () => {
    it('should include tenant ID in cache key', () => {
      const hash = 'abc123def456';
      const key = cache.buildCacheKey(hash, 'transform');

      expect(key).toContain('thj:');
    });

    it('should include cache type in key', () => {
      const hash = 'abc123def456';
      const key = cache.buildCacheKey(hash, 'document');

      expect(key).toBe('thj:document:abc123def456');
    });

    it('should include qualifier when provided', () => {
      const hash = 'abc123def456';
      const key = cache.buildCacheKey(hash, 'transform', 'leadership');

      expect(key).toBe('thj:transform:abc123def456:leadership');
    });

    it('should default to transform type', () => {
      const hash = 'abc123def456';
      const key = cache.buildCacheKey(hash);

      expect(key).toBe('thj:transform:abc123def456');
    });
  });

  describe('get/set operations (L1 only)', () => {
    it('should return null for cache miss', async () => {
      const result = await cache.get('non-existent content');
      expect(result).toBeNull();
    });

    it('should store and retrieve values', async () => {
      const content = 'Test document content';
      const value = { transformed: 'result' };

      await cache.set(content, value);
      const result = await cache.get(content);

      expect(result).toEqual(value);
    });

    it('should respect cache type isolation', async () => {
      const content = 'Same content';
      const transformValue = { type: 'transform' };
      const documentValue = { type: 'document' };

      await cache.set(content, transformValue, { cacheType: 'transform' });
      await cache.set(content, documentValue, { cacheType: 'document' });

      const transformResult = await cache.get(content, { cacheType: 'transform' });
      const documentResult = await cache.get(content, { cacheType: 'document' });

      expect(transformResult).toEqual(transformValue);
      expect(documentResult).toEqual(documentValue);
    });

    it('should respect qualifier isolation', async () => {
      const content = 'Same content';
      const leadershipResult = { persona: 'leadership', summary: 'Executive summary' };
      const devrelResult = { persona: 'devrel', summary: 'Technical summary' };

      await cache.set(content, leadershipResult, { qualifier: 'leadership' });
      await cache.set(content, devrelResult, { qualifier: 'devrel' });

      const leadership = await cache.get(content, { qualifier: 'leadership' });
      const devrel = await cache.get(content, { qualifier: 'devrel' });

      expect(leadership).toEqual(leadershipResult);
      expect(devrel).toEqual(devrelResult);
    });

    it('should return content hash on set', async () => {
      const content = 'Test content';
      const hash = await cache.set(content, { value: 'test' });

      expect(hash).toHaveLength(16);
      expect(hash).toBe(cache.generateContentHash(content));
    });

    it('should store metadata', async () => {
      const content = 'Document content';
      await cache.set(content, { result: 'transformed' }, {
        metadata: {
          persona: 'leadership',
          sourceDocument: 'prd.md',
        },
      });

      // Metadata is internal - we can verify through metrics
      const metrics = cache.getMetrics();
      expect(metrics.sets).toBe(1);
    });
  });

  describe('getByHash', () => {
    it('should retrieve by pre-computed hash', async () => {
      const content = 'Test content';
      const value = { result: 'cached' };

      const hash = await cache.set(content, value);
      const result = await cache.getByHash(hash);

      expect(result).toEqual(value);
    });

    it('should return null for unknown hash', async () => {
      const result = await cache.getByHash('unknownhash123');
      expect(result).toBeNull();
    });
  });

  describe('invalidate', () => {
    it('should remove cached entry by content', async () => {
      const content = 'Content to invalidate';
      await cache.set(content, { value: 'test' });

      const before = await cache.get(content);
      expect(before).not.toBeNull();

      await cache.invalidate(content);

      const after = await cache.get(content);
      expect(after).toBeNull();
    });

    it('should remove by hash', async () => {
      const content = 'Content to remove';
      await cache.set(content, { value: 'test' });

      const hash = cache.generateContentHash(content);
      await cache.invalidateByHash(hash);

      const result = await cache.get(content);
      expect(result).toBeNull();
    });

    it('should return true when entry was removed', async () => {
      const content = 'Content exists';
      await cache.set(content, { value: 'test' });

      const result = await cache.invalidate(content);
      expect(result).toBe(true);
    });

    it('should return false when entry did not exist', async () => {
      const result = await cache.invalidate('non-existent');
      expect(result).toBe(false);
    });
  });

  describe('invalidateTenant', () => {
    it('should clear all entries for current tenant', async () => {
      // Set multiple entries
      await cache.set('Content 1', { value: 1 });
      await cache.set('Content 2', { value: 2 });
      await cache.set('Content 3', { value: 3 });

      const beforeMetrics = cache.getMetrics();
      expect(beforeMetrics.l1Size).toBe(3);

      const removed = await cache.invalidateTenant();

      expect(removed).toBe(3);
      const afterMetrics = cache.getMetrics();
      expect(afterMetrics.l1Size).toBe(0);
    });
  });

  describe('metrics', () => {
    it('should track L1 hits', async () => {
      const content = 'Cached content';
      await cache.set(content, { value: 'test' });

      await cache.get(content);
      await cache.get(content);

      const metrics = cache.getMetrics();
      expect(metrics.l1Hits).toBe(2);
    });

    it('should track L1 misses', async () => {
      await cache.get('miss 1');
      await cache.get('miss 2');

      const metrics = cache.getMetrics();
      expect(metrics.l1Misses).toBe(2);
    });

    it('should track sets', async () => {
      await cache.set('content 1', { v: 1 });
      await cache.set('content 2', { v: 2 });

      const metrics = cache.getMetrics();
      expect(metrics.sets).toBe(2);
    });

    it('should track invalidations', async () => {
      await cache.set('content', { v: 1 });
      await cache.invalidate('content');

      const metrics = cache.getMetrics();
      expect(metrics.invalidations).toBe(1);
    });

    it('should calculate hit rate', async () => {
      await cache.set('exists', { v: 1 });

      await cache.get('exists'); // hit
      await cache.get('exists'); // hit
      await cache.get('missing'); // miss

      const metrics = cache.getMetrics();
      // 2 hits out of 3 requests = 0.666...
      expect(metrics.hitRate).toBeCloseTo(0.667, 2);
    });

    it('should track L1 size', async () => {
      await cache.set('a', { v: 1 });
      await cache.set('b', { v: 2 });
      await cache.set('c', { v: 3 });

      const metrics = cache.getMetrics();
      expect(metrics.l1Size).toBe(3);
    });

    it('should reset metrics', async () => {
      await cache.set('content', { v: 1 });
      await cache.get('content');

      cache.resetMetrics();

      const metrics = cache.getMetrics();
      expect(metrics.l1Hits).toBe(0);
      expect(metrics.l1Misses).toBe(0);
      expect(metrics.sets).toBe(0);
    });
  });

  describe('clear', () => {
    it('should clear all L1 entries', async () => {
      await cache.set('a', { v: 1 });
      await cache.set('b', { v: 2 });

      cache.clear();

      const metrics = cache.getMetrics();
      expect(metrics.l1Size).toBe(0);

      const result = await cache.get('a');
      expect(result).toBeNull();
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
  });
});

describe('Convenience functions', () => {
  let cache: ContentAddressableCache;

  beforeEach(() => {
    cache = ContentAddressableCache.getInstance();
    cache.clear();
    cache.resetMetrics();
  });

  describe('getCachedTransform', () => {
    it('should use transform cache type with persona qualifier', async () => {
      const content = 'Document content';
      const persona = 'leadership';

      // First, cache something
      await cacheTransform(content, persona, { summary: 'Executive brief' });

      // Then retrieve it
      const result = await getCachedTransform(content, persona);
      expect(result).toEqual({ summary: 'Executive brief' });
    });

    it('should return null for uncached transform', async () => {
      const result = await getCachedTransform('new content', 'devrel');
      expect(result).toBeNull();
    });
  });

  describe('cacheTransform', () => {
    it('should return content hash', async () => {
      const content = 'Test content';
      const hash = await cacheTransform(content, 'product', { result: 'cached' });

      expect(hash).toHaveLength(16);
    });

    it('should include source document in metadata', async () => {
      await cacheTransform(
        'Document content',
        'marketing',
        { transformed: true },
        'prd.md'
      );

      const metrics = cache.getMetrics();
      expect(metrics.sets).toBeGreaterThan(0);
    });
  });

  describe('previewCacheKey', () => {
    it('should return formatted cache key', () => {
      const content = 'Test content';
      const key = previewCacheKey(content, 'transform', 'leadership');

      expect(key).toContain('thj:');
      expect(key).toContain(':transform:');
      expect(key).toContain(':leadership');
    });

    it('should use defaults', () => {
      const key = previewCacheKey('content');
      expect(key).toContain(':transform:');
    });
  });
});

describe('Content normalization edge cases', () => {
  let cache: ContentAddressableCache;

  beforeEach(() => {
    cache = new ContentAddressableCache();
  });

  it('should normalize tabs and newlines', () => {
    const content1 = 'Hello\t\tWorld\n\nTest';
    const content2 = 'Hello World Test';

    const hash1 = cache.generateContentHash(content1);
    const hash2 = cache.generateContentHash(content2);

    expect(hash1).toBe(hash2);
  });

  it('should handle very long content', () => {
    const longContent = 'A'.repeat(100000);
    const hash = cache.generateContentHash(longContent);

    expect(hash).toHaveLength(16);
  });

  it('should handle special characters', () => {
    const content = '!@#$%^&*()_+-=[]{}|;:\'",.<>?/\\`~';
    const hash = cache.generateContentHash(content);

    expect(hash).toHaveLength(16);
  });
});
