/**
 * Content-Addressable Cache
 *
 * Sprint 4 - Task 4.6: Content-Addressable Cache for Transform Results
 *
 * Implements a two-tier caching system with content-based addressing:
 * - L1: In-memory LRU cache for hot data (fast, limited size)
 * - L2: Redis cache for persistent storage (slower, unlimited)
 *
 * Cache key format: {tenantId}:{cacheType}:{contentHash}:{qualifier}
 *
 * Features:
 * - Content normalization and SHA-256 hashing
 * - Tenant-isolated cache namespaces
 * - Tiered caching with automatic promotion
 * - Cache metrics tracking (hits, misses, hit rate)
 * - Configurable TTL per cache type
 */

import { createHash } from 'crypto';
import { LRUCache } from 'lru-cache';
import { logger } from '../utils/logger';
import { tenantContextProvider, getCurrentTenant } from './tenant-context';

// =============================================================================
// Types
// =============================================================================

export type CacheType = 'transform' | 'document' | 'folder' | 'context';

export interface CacheEntry<T = unknown> {
  /** The cached value */
  value: T;
  /** Content hash used as part of the key */
  contentHash: string;
  /** When the entry was created */
  createdAt: Date;
  /** When the entry expires */
  expiresAt: Date;
  /** Metadata about the cached content */
  metadata?: {
    originalSize?: number;
    persona?: string;
    sourceDocument?: string;
  };
}

export interface CacheMetrics {
  /** Total L1 cache hits */
  l1Hits: number;
  /** Total L1 cache misses */
  l1Misses: number;
  /** Total L2 cache hits */
  l2Hits: number;
  /** Total L2 cache misses */
  l2Misses: number;
  /** Total cache sets */
  sets: number;
  /** Total cache invalidations */
  invalidations: number;
  /** Entries currently in L1 cache */
  l1Size: number;
}

export interface CacheOptions {
  /** Cache type for TTL selection */
  cacheType?: CacheType;
  /** Optional qualifier (e.g., persona type) */
  qualifier?: string;
  /** Custom TTL in seconds (overrides tenant config) */
  ttlSeconds?: number;
  /** Additional metadata to store */
  metadata?: CacheEntry['metadata'];
}

// =============================================================================
// Configuration
// =============================================================================

/** Default TTLs by cache type (in seconds) */
const DEFAULT_TTL: Record<CacheType, number> = {
  transform: 30 * 60,    // 30 minutes for transform results
  document: 15 * 60,     // 15 minutes for document content
  folder: 60 * 60,       // 1 hour for folder IDs
  context: 5 * 60,       // 5 minutes for aggregated context
};

/** L1 cache configuration */
const L1_CONFIG = {
  maxEntries: 500,       // Max entries in memory
  maxSizeBytes: 50 * 1024 * 1024, // 50MB max memory
};

// =============================================================================
// Content-Addressable Cache
// =============================================================================

export class ContentAddressableCache {
  private static instance: ContentAddressableCache;

  /** L1 in-memory cache */
  private l1Cache: LRUCache<string, CacheEntry>;

  /** Cache metrics */
  private metrics: CacheMetrics = {
    l1Hits: 0,
    l1Misses: 0,
    l2Hits: 0,
    l2Misses: 0,
    sets: 0,
    invalidations: 0,
    l1Size: 0,
  };

  /** Redis client (lazy initialized) */
  private redisClient: import('ioredis').default | null = null;
  private redisInitialized = false;

  constructor() {
    this.l1Cache = new LRUCache<string, CacheEntry>({
      max: L1_CONFIG.maxEntries,
      maxSize: L1_CONFIG.maxSizeBytes,
      sizeCalculation: (entry) => {
        // Estimate size based on JSON serialization
        return JSON.stringify(entry).length;
      },
      ttl: 5 * 60 * 1000, // Default 5 min TTL for L1
      updateAgeOnGet: true, // Refresh TTL on access
    });

    logger.debug('ContentAddressableCache initialized', {
      l1MaxEntries: L1_CONFIG.maxEntries,
      l1MaxSizeBytes: L1_CONFIG.maxSizeBytes,
    });
  }

  /**
   * Get singleton instance
   */
  static getInstance(): ContentAddressableCache {
    if (!ContentAddressableCache.instance) {
      ContentAddressableCache.instance = new ContentAddressableCache();
    }
    return ContentAddressableCache.instance;
  }

  /**
   * Initialize Redis connection (optional - cache works without Redis)
   */
  async initializeRedis(redisUrl?: string): Promise<boolean> {
    if (this.redisInitialized) {
      return this.redisClient !== null;
    }

    this.redisInitialized = true;

    try {
      const Redis = (await import('ioredis')).default;
      const url = redisUrl || process.env.REDIS_URL;

      if (!url) {
        logger.info('Redis URL not configured, using L1 cache only');
        return false;
      }

      this.redisClient = new Redis(url, {
        maxRetriesPerRequest: 3,
        retryStrategy: (times) => {
          if (times > 3) return null; // Stop retrying
          return Math.min(times * 100, 1000);
        },
        lazyConnect: true,
      });

      await this.redisClient.connect();

      this.redisClient.on('error', (err) => {
        logger.warn('Redis connection error', { error: err.message });
      });

      logger.info('Redis cache initialized');
      return true;
    } catch (error) {
      logger.warn('Failed to initialize Redis, using L1 cache only', {
        error: error instanceof Error ? error.message : String(error),
      });
      this.redisClient = null;
      return false;
    }
  }

  // ===========================================================================
  // Public Methods
  // ===========================================================================

  /**
   * Generate content hash from input
   * Normalizes content before hashing for consistent keys
   */
  generateContentHash(content: string): string {
    const normalized = this.normalizeContent(content);
    return createHash('sha256').update(normalized).digest('hex').slice(0, 16);
  }

  /**
   * Build cache key with tenant isolation
   */
  buildCacheKey(
    contentHash: string,
    cacheType: CacheType = 'transform',
    qualifier?: string
  ): string {
    const tenant = getCurrentTenant();
    const parts = [tenant.tenantId, cacheType, contentHash];
    if (qualifier) {
      parts.push(qualifier);
    }
    return parts.join(':');
  }

  /**
   * Get value from cache (checks L1, then L2)
   */
  async get<T>(
    content: string,
    options: CacheOptions = {}
  ): Promise<T | null> {
    const contentHash = this.generateContentHash(content);
    const cacheKey = this.buildCacheKey(
      contentHash,
      options.cacheType || 'transform',
      options.qualifier
    );

    // Check L1 cache
    const l1Entry = this.l1Cache.get(cacheKey);
    if (l1Entry) {
      this.metrics.l1Hits++;
      logger.debug('Cache L1 hit', { cacheKey, contentHash });
      return l1Entry.value as T;
    }
    this.metrics.l1Misses++;

    // Check L2 cache (Redis)
    if (this.redisClient) {
      try {
        const l2Data = await this.redisClient.get(cacheKey);
        if (l2Data) {
          this.metrics.l2Hits++;
          const entry = JSON.parse(l2Data) as CacheEntry<T>;

          // Promote to L1
          this.l1Cache.set(cacheKey, entry);
          this.metrics.l1Size = this.l1Cache.size;

          logger.debug('Cache L2 hit (promoted to L1)', { cacheKey, contentHash });
          return entry.value;
        }
        this.metrics.l2Misses++;
      } catch (error) {
        logger.warn('Redis get error', {
          cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    logger.debug('Cache miss', { cacheKey, contentHash });
    return null;
  }

  /**
   * Get value by pre-computed hash (for cases where hash is already known)
   */
  async getByHash<T>(
    contentHash: string,
    options: CacheOptions = {}
  ): Promise<T | null> {
    const cacheKey = this.buildCacheKey(
      contentHash,
      options.cacheType || 'transform',
      options.qualifier
    );

    // Check L1 cache
    const l1Entry = this.l1Cache.get(cacheKey);
    if (l1Entry) {
      this.metrics.l1Hits++;
      return l1Entry.value as T;
    }
    this.metrics.l1Misses++;

    // Check L2 cache (Redis)
    if (this.redisClient) {
      try {
        const l2Data = await this.redisClient.get(cacheKey);
        if (l2Data) {
          this.metrics.l2Hits++;
          const entry = JSON.parse(l2Data) as CacheEntry<T>;
          this.l1Cache.set(cacheKey, entry);
          this.metrics.l1Size = this.l1Cache.size;
          return entry.value;
        }
        this.metrics.l2Misses++;
      } catch (error) {
        logger.warn('Redis get error', { cacheKey, error: error instanceof Error ? error.message : String(error) });
      }
    }

    return null;
  }

  /**
   * Set value in cache (writes to both L1 and L2)
   */
  async set<T>(
    content: string,
    value: T,
    options: CacheOptions = {}
  ): Promise<string> {
    const contentHash = this.generateContentHash(content);
    const cacheType = options.cacheType || 'transform';
    const cacheKey = this.buildCacheKey(contentHash, cacheType, options.qualifier);

    // Determine TTL
    const ttlSeconds = this.getTTL(cacheType, options.ttlSeconds);
    const now = new Date();
    const expiresAt = new Date(now.getTime() + ttlSeconds * 1000);

    const entry: CacheEntry<T> = {
      value,
      contentHash,
      createdAt: now,
      expiresAt,
      metadata: {
        ...options.metadata,
        originalSize: content.length,
      },
    };

    // Write to L1
    this.l1Cache.set(cacheKey, entry, { ttl: ttlSeconds * 1000 });
    this.metrics.sets++;
    this.metrics.l1Size = this.l1Cache.size;

    // Write to L2 (Redis)
    if (this.redisClient) {
      try {
        await this.redisClient.setex(cacheKey, ttlSeconds, JSON.stringify(entry));
        logger.debug('Cache set (L1 + L2)', { cacheKey, contentHash, ttlSeconds });
      } catch (error) {
        logger.warn('Redis set error', {
          cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    } else {
      logger.debug('Cache set (L1 only)', { cacheKey, contentHash, ttlSeconds });
    }

    return contentHash;
  }

  /**
   * Invalidate cache entry by content
   */
  async invalidate(content: string, options: CacheOptions = {}): Promise<boolean> {
    const contentHash = this.generateContentHash(content);
    return this.invalidateByHash(contentHash, options);
  }

  /**
   * Invalidate cache entry by hash
   */
  async invalidateByHash(
    contentHash: string,
    options: CacheOptions = {}
  ): Promise<boolean> {
    const cacheKey = this.buildCacheKey(
      contentHash,
      options.cacheType || 'transform',
      options.qualifier
    );

    // Remove from L1
    const hadL1 = this.l1Cache.delete(cacheKey);
    this.metrics.l1Size = this.l1Cache.size;

    // Remove from L2
    let hadL2 = false;
    if (this.redisClient) {
      try {
        const deleted = await this.redisClient.del(cacheKey);
        hadL2 = deleted > 0;
      } catch (error) {
        logger.warn('Redis delete error', {
          cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    if (hadL1 || hadL2) {
      this.metrics.invalidations++;
      logger.debug('Cache invalidated', { cacheKey, contentHash, hadL1, hadL2 });
    }

    return hadL1 || hadL2;
  }

  /**
   * Invalidate all cache entries for current tenant
   */
  async invalidateTenant(): Promise<number> {
    const tenant = getCurrentTenant();
    const prefix = `${tenant.tenantId}:`;
    let count = 0;

    // Clear matching entries from L1
    for (const key of this.l1Cache.keys()) {
      if (key.startsWith(prefix)) {
        this.l1Cache.delete(key);
        count++;
      }
    }
    this.metrics.l1Size = this.l1Cache.size;

    // Clear matching entries from L2 (Redis)
    if (this.redisClient) {
      try {
        const keys = await this.redisClient.keys(`${prefix}*`);
        if (keys.length > 0) {
          const deleted = await this.redisClient.del(...keys);
          count += deleted;
        }
      } catch (error) {
        logger.warn('Redis tenant invalidation error', {
          tenantId: tenant.tenantId,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    this.metrics.invalidations += count;
    logger.info('Tenant cache invalidated', { tenantId: tenant.tenantId, entriesRemoved: count });
    return count;
  }

  /**
   * Clear entire cache (L1 only - Redis entries expire naturally)
   */
  clear(): void {
    this.l1Cache.clear();
    this.metrics.l1Size = 0;
    logger.info('L1 cache cleared');
  }

  /**
   * Get cache metrics
   */
  getMetrics(): CacheMetrics & { hitRate: number } {
    const totalRequests = this.metrics.l1Hits + this.metrics.l1Misses;
    const totalHits = this.metrics.l1Hits + this.metrics.l2Hits;
    const hitRate = totalRequests > 0 ? totalHits / totalRequests : 0;

    return {
      ...this.metrics,
      l1Size: this.l1Cache.size,
      hitRate,
    };
  }

  /**
   * Reset metrics (useful for testing)
   */
  resetMetrics(): void {
    this.metrics = {
      l1Hits: 0,
      l1Misses: 0,
      l2Hits: 0,
      l2Misses: 0,
      sets: 0,
      invalidations: 0,
      l1Size: this.l1Cache.size,
    };
  }

  /**
   * Check if Redis is connected
   */
  isRedisConnected(): boolean {
    return this.redisClient !== null && this.redisClient.status === 'ready';
  }

  /**
   * Shutdown Redis connection
   */
  async shutdown(): Promise<void> {
    if (this.redisClient) {
      await this.redisClient.quit();
      this.redisClient = null;
      logger.info('Redis connection closed');
    }
  }

  // ===========================================================================
  // Private Methods
  // ===========================================================================

  /**
   * Normalize content for consistent hashing
   * - Trims whitespace
   * - Collapses multiple whitespace to single space
   * - Converts to lowercase (optional, configurable)
   */
  private normalizeContent(content: string): string {
    return content
      .trim()
      .replace(/\s+/g, ' ');
  }

  /**
   * Get TTL for cache type, considering tenant configuration
   */
  private getTTL(cacheType: CacheType, customTtl?: number): number {
    if (customTtl !== undefined) {
      return customTtl;
    }

    // Try to get tenant-specific TTL
    try {
      const ttlKey = this.mapCacheTypeToTenantTTL(cacheType);
      if (ttlKey) {
        return tenantContextProvider.getCacheTTL(ttlKey);
      }
    } catch {
      // Tenant context may not be available
    }

    return DEFAULT_TTL[cacheType];
  }

  /**
   * Map cache type to tenant TTL config key
   */
  private mapCacheTypeToTenantTTL(
    cacheType: CacheType
  ): 'documentContent' | 'transformResults' | 'folderIds' | null {
    switch (cacheType) {
      case 'document':
        return 'documentContent';
      case 'transform':
        return 'transformResults';
      case 'folder':
        return 'folderIds';
      default:
        return null;
    }
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const contentCache = ContentAddressableCache.getInstance();
export default contentCache;

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Get cached transform result for content + persona combination
 */
export async function getCachedTransform<T>(
  content: string,
  persona: string
): Promise<T | null> {
  return contentCache.get<T>(content, {
    cacheType: 'transform',
    qualifier: persona,
  });
}

/**
 * Cache transform result for content + persona combination
 */
export async function cacheTransform<T>(
  content: string,
  persona: string,
  result: T,
  sourceDocument?: string
): Promise<string> {
  return contentCache.set(content, result, {
    cacheType: 'transform',
    qualifier: persona,
    metadata: { persona, sourceDocument },
  });
}

/**
 * Generate cache key preview (for logging/debugging)
 */
export function previewCacheKey(
  content: string,
  cacheType: CacheType = 'transform',
  qualifier?: string
): string {
  const hash = contentCache.generateContentHash(content);
  return contentCache.buildCacheKey(hash, cacheType, qualifier);
}
