/**
 * Tiered Cache with Stale-While-Revalidate
 *
 * Sprint 5 - Task 5.4: Tiered Cache Implementation
 *
 * Enhances caching with multi-tier hierarchy and stale-while-revalidate pattern
 * for optimal performance and freshness balance.
 *
 * Architecture:
 * - L1 (In-Memory LRU): Fast, limited to 100 entries, 1-5 min TTL
 * - L2 (Redis): Shared across instances, 15-60 min TTL
 * - Stale-While-Revalidate: Return stale data immediately, refresh in background
 *
 * Flow:
 * 1. Check L1 -> If hit, return
 * 2. Check L2 -> If hit, promote to L1, return
 * 3. If stale data exists and SWR enabled -> Return stale, trigger background refresh
 * 4. Fetch from source -> Write to L1 and L2
 */

import { LRUCache } from 'lru-cache';
import { logger } from '../utils/logger';
import { getCurrentTenant, tenantContextProvider } from './tenant-context';

// =============================================================================
// Types
// =============================================================================

export interface TieredCacheOptions {
  /** Enable stale-while-revalidate pattern */
  staleWhileRevalidate?: boolean;
  /** Maximum acceptable stale time in milliseconds */
  maxStaleAge?: number;
  /** Custom L1 TTL in milliseconds (overrides default) */
  l1TtlMs?: number;
  /** Custom L2 TTL in seconds (overrides default) */
  l2TtlSeconds?: number;
  /** Cache type for config lookup */
  cacheType?: CacheTypeConfig;
}

export type CacheTypeConfig = 'documentContent' | 'folderIds' | 'transformResults' | 'context' | 'adr' | 'changelog';

export interface CacheEntry<T> {
  value: T;
  createdAt: number;
  expiresAt: number;
  /** For stale-while-revalidate: when the entry becomes stale */
  staleAt: number;
}

export interface TieredCacheMetrics {
  l1Hits: number;
  l1Misses: number;
  l2Hits: number;
  l2Misses: number;
  staleServes: number;
  backgroundRefreshes: number;
  fetchesFromSource: number;
  sets: number;
  errors: number;
}

// =============================================================================
// Configuration
// =============================================================================

/** Default TTL configuration by cache type */
const DEFAULT_CONFIG: Record<CacheTypeConfig, { l1TtlMs: number; l2TtlSeconds: number }> = {
  documentContent: { l1TtlMs: 5 * 60 * 1000, l2TtlSeconds: 15 * 60 },    // L1: 5min, L2: 15min
  folderIds: { l1TtlMs: 10 * 60 * 1000, l2TtlSeconds: 60 * 60 },          // L1: 10min, L2: 60min
  transformResults: { l1TtlMs: 5 * 60 * 1000, l2TtlSeconds: 30 * 60 },    // L1: 5min, L2: 30min
  context: { l1TtlMs: 2 * 60 * 1000, l2TtlSeconds: 10 * 60 },              // L1: 2min, L2: 10min
  adr: { l1TtlMs: 5 * 60 * 1000, l2TtlSeconds: 30 * 60 },                  // L1: 5min, L2: 30min
  changelog: { l1TtlMs: 5 * 60 * 1000, l2TtlSeconds: 30 * 60 },            // L1: 5min, L2: 30min
};

/** Default stale age for SWR (5 minutes) */
const DEFAULT_MAX_STALE_AGE = 5 * 60 * 1000;

/** L1 cache configuration */
const L1_CONFIG = {
  maxEntries: 100,
  maxSizeBytes: 10 * 1024 * 1024, // 10MB
};

// =============================================================================
// Tiered Cache Implementation
// =============================================================================

export class TieredCache {
  private static instance: TieredCache;

  /** L1 in-memory cache */
  private l1Cache: LRUCache<string, CacheEntry<unknown>>;

  /** Redis client (lazy initialized) */
  private redisClient: import('ioredis').default | null = null;
  private redisInitialized = false;

  /** Metrics tracking */
  private metrics: TieredCacheMetrics = {
    l1Hits: 0,
    l1Misses: 0,
    l2Hits: 0,
    l2Misses: 0,
    staleServes: 0,
    backgroundRefreshes: 0,
    fetchesFromSource: 0,
    sets: 0,
    errors: 0,
  };

  /** Track in-flight background refreshes to prevent duplicate fetches */
  private refreshInProgress = new Set<string>();

  constructor() {
    this.l1Cache = new LRUCache<string, CacheEntry<unknown>>({
      max: L1_CONFIG.maxEntries,
      maxSize: L1_CONFIG.maxSizeBytes,
      sizeCalculation: (entry) => JSON.stringify(entry).length,
      ttl: 5 * 60 * 1000, // Default 5 min
      updateAgeOnGet: false, // Don't extend TTL on read for SWR
    });

    logger.debug('TieredCache initialized', {
      l1MaxEntries: L1_CONFIG.maxEntries,
      l1MaxSizeBytes: L1_CONFIG.maxSizeBytes,
    });
  }

  /**
   * Get singleton instance
   */
  static getInstance(): TieredCache {
    if (!TieredCache.instance) {
      TieredCache.instance = new TieredCache();
    }
    return TieredCache.instance;
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
        logger.info('TieredCache: Redis URL not configured, using L1 only');
        return false;
      }

      this.redisClient = new Redis(url, {
        maxRetriesPerRequest: 3,
        retryStrategy: (times) => {
          if (times > 3) return null;
          return Math.min(times * 100, 1000);
        },
        lazyConnect: true,
      });

      await this.redisClient.connect();

      this.redisClient.on('error', (err) => {
        logger.warn('TieredCache: Redis error', { error: err.message });
      });

      logger.info('TieredCache: Redis initialized');
      return true;
    } catch (error) {
      logger.warn('TieredCache: Failed to initialize Redis', {
        error: error instanceof Error ? error.message : String(error),
      });
      this.redisClient = null;
      return false;
    }
  }

  // ===========================================================================
  // Public API
  // ===========================================================================

  /**
   * Build cache key with tenant isolation
   */
  buildKey(tenantId: string, key: string): string {
    return `${tenantId}:tiered:${key}`;
  }

  /**
   * Get value from cache (L1 -> L2)
   */
  async get<T>(tenantId: string, key: string): Promise<T | null> {
    const cacheKey = this.buildKey(tenantId, key);

    // Check L1
    const l1Entry = this.l1Cache.get(cacheKey) as CacheEntry<T> | undefined;
    if (l1Entry && Date.now() < l1Entry.expiresAt) {
      this.metrics.l1Hits++;
      logger.debug('TieredCache L1 hit', { key: cacheKey });
      return l1Entry.value;
    }
    this.metrics.l1Misses++;

    // Check L2 (Redis)
    if (this.redisClient) {
      try {
        const l2Data = await this.redisClient.get(cacheKey);
        if (l2Data) {
          const entry = JSON.parse(l2Data) as CacheEntry<T>;
          if (Date.now() < entry.expiresAt) {
            this.metrics.l2Hits++;
            // Promote to L1
            this.l1Cache.set(cacheKey, entry, { ttl: entry.expiresAt - Date.now() });
            logger.debug('TieredCache L2 hit, promoted to L1', { key: cacheKey });
            return entry.value;
          }
        }
        this.metrics.l2Misses++;
      } catch (error) {
        logger.warn('TieredCache Redis get error', {
          key: cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
        this.metrics.errors++;
      }
    }

    logger.debug('TieredCache miss', { key: cacheKey });
    return null;
  }

  /**
   * Set value in cache (both L1 and L2)
   */
  async set<T>(
    tenantId: string,
    key: string,
    value: T,
    ttlSeconds: number
  ): Promise<void> {
    const cacheKey = this.buildKey(tenantId, key);
    const now = Date.now();
    const ttlMs = ttlSeconds * 1000;

    const entry: CacheEntry<T> = {
      value,
      createdAt: now,
      expiresAt: now + ttlMs,
      staleAt: now + (ttlMs * 0.8), // Stale at 80% of TTL
    };

    // Write to L1
    this.l1Cache.set(cacheKey, entry, { ttl: ttlMs });
    this.metrics.sets++;

    // Write to L2 (Redis)
    if (this.redisClient) {
      try {
        await this.redisClient.setex(cacheKey, ttlSeconds, JSON.stringify(entry));
        logger.debug('TieredCache set (L1 + L2)', { key: cacheKey, ttlSeconds });
      } catch (error) {
        logger.warn('TieredCache Redis set error', {
          key: cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
        this.metrics.errors++;
      }
    } else {
      logger.debug('TieredCache set (L1 only)', { key: cacheKey, ttlSeconds });
    }
  }

  /**
   * Get value from cache or fetch from source
   * Supports stale-while-revalidate pattern
   */
  async getOrFetch<T>(
    tenantId: string,
    key: string,
    fetchFn: () => Promise<T>,
    options: TieredCacheOptions = {}
  ): Promise<T> {
    const cacheKey = this.buildKey(tenantId, key);
    const cacheType = options.cacheType || 'context';
    const config = DEFAULT_CONFIG[cacheType];
    const l2TtlSeconds = options.l2TtlSeconds ?? config.l2TtlSeconds;
    const maxStaleAge = options.maxStaleAge ?? DEFAULT_MAX_STALE_AGE;
    const staleWhileRevalidate = options.staleWhileRevalidate ?? false;

    const now = Date.now();

    // Check L1
    const l1Entry = this.l1Cache.get(cacheKey) as CacheEntry<T> | undefined;
    if (l1Entry) {
      // Fresh data
      if (now < l1Entry.staleAt) {
        this.metrics.l1Hits++;
        logger.debug('TieredCache L1 hit (fresh)', { key: cacheKey });
        return l1Entry.value;
      }

      // Stale but within acceptable range for SWR
      if (staleWhileRevalidate && now < l1Entry.expiresAt) {
        this.metrics.l1Hits++;
        this.metrics.staleServes++;
        logger.debug('TieredCache L1 hit (stale, SWR)', { key: cacheKey });

        // Trigger background refresh if not already in progress
        this.triggerBackgroundRefresh(tenantId, key, fetchFn, l2TtlSeconds);

        return l1Entry.value;
      }
    }
    this.metrics.l1Misses++;

    // Check L2 (Redis)
    if (this.redisClient) {
      try {
        const l2Data = await this.redisClient.get(cacheKey);
        if (l2Data) {
          const entry = JSON.parse(l2Data) as CacheEntry<T>;

          // Fresh data
          if (now < entry.staleAt) {
            this.metrics.l2Hits++;
            // Promote to L1
            this.l1Cache.set(cacheKey, entry, { ttl: entry.expiresAt - now });
            logger.debug('TieredCache L2 hit (fresh), promoted to L1', { key: cacheKey });
            return entry.value;
          }

          // Stale but within acceptable range for SWR
          if (staleWhileRevalidate && now < entry.expiresAt && now - entry.staleAt < maxStaleAge) {
            this.metrics.l2Hits++;
            this.metrics.staleServes++;
            // Promote to L1
            this.l1Cache.set(cacheKey, entry, { ttl: entry.expiresAt - now });
            logger.debug('TieredCache L2 hit (stale, SWR), promoted to L1', { key: cacheKey });

            // Trigger background refresh
            this.triggerBackgroundRefresh(tenantId, key, fetchFn, l2TtlSeconds);

            return entry.value;
          }
        }
        this.metrics.l2Misses++;
      } catch (error) {
        logger.warn('TieredCache Redis get error in getOrFetch', {
          key: cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
        this.metrics.errors++;
      }
    }

    // Fetch from source
    logger.debug('TieredCache fetching from source', { key: cacheKey });
    this.metrics.fetchesFromSource++;

    const value = await fetchFn();
    await this.set(tenantId, key, value, l2TtlSeconds);
    return value;
  }

  /**
   * Invalidate cache entry
   */
  async invalidate(tenantId: string, key: string): Promise<boolean> {
    const cacheKey = this.buildKey(tenantId, key);
    let invalidated = false;

    // Remove from L1
    if (this.l1Cache.delete(cacheKey)) {
      invalidated = true;
    }

    // Remove from L2
    if (this.redisClient) {
      try {
        const deleted = await this.redisClient.del(cacheKey);
        if (deleted > 0) invalidated = true;
      } catch (error) {
        logger.warn('TieredCache Redis delete error', {
          key: cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
        this.metrics.errors++;
      }
    }

    if (invalidated) {
      logger.debug('TieredCache invalidated', { key: cacheKey });
    }
    return invalidated;
  }

  /**
   * Invalidate all entries for a tenant
   */
  async invalidateTenant(tenantId: string): Promise<number> {
    const prefix = `${tenantId}:tiered:`;
    let count = 0;

    // Clear L1
    for (const key of this.l1Cache.keys()) {
      if (key.startsWith(prefix)) {
        this.l1Cache.delete(key);
        count++;
      }
    }

    // Clear L2
    if (this.redisClient) {
      try {
        const keys = await this.redisClient.keys(`${prefix}*`);
        if (keys.length > 0) {
          const deleted = await this.redisClient.del(...keys);
          count += deleted;
        }
      } catch (error) {
        logger.warn('TieredCache Redis tenant invalidation error', {
          tenantId,
          error: error instanceof Error ? error.message : String(error),
        });
        this.metrics.errors++;
      }
    }

    logger.info('TieredCache tenant invalidated', { tenantId, entriesRemoved: count });
    return count;
  }

  /**
   * Get cache metrics
   */
  getMetrics(): TieredCacheMetrics & { hitRate: number; l1Size: number } {
    const totalRequests = this.metrics.l1Hits + this.metrics.l1Misses;
    const totalHits = this.metrics.l1Hits + this.metrics.l2Hits;
    const hitRate = totalRequests > 0 ? totalHits / totalRequests : 0;

    return {
      ...this.metrics,
      hitRate,
      l1Size: this.l1Cache.size,
    };
  }

  /**
   * Reset metrics (for testing)
   */
  resetMetrics(): void {
    this.metrics = {
      l1Hits: 0,
      l1Misses: 0,
      l2Hits: 0,
      l2Misses: 0,
      staleServes: 0,
      backgroundRefreshes: 0,
      fetchesFromSource: 0,
      sets: 0,
      errors: 0,
    };
  }

  /**
   * Clear all L1 entries
   */
  clear(): void {
    this.l1Cache.clear();
    logger.info('TieredCache L1 cleared');
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
      logger.info('TieredCache Redis connection closed');
    }
  }

  // ===========================================================================
  // Private Methods
  // ===========================================================================

  /**
   * Trigger background refresh for stale-while-revalidate
   */
  private triggerBackgroundRefresh<T>(
    tenantId: string,
    key: string,
    fetchFn: () => Promise<T>,
    ttlSeconds: number
  ): void {
    const cacheKey = this.buildKey(tenantId, key);

    // Prevent duplicate refreshes
    if (this.refreshInProgress.has(cacheKey)) {
      return;
    }

    this.refreshInProgress.add(cacheKey);
    this.metrics.backgroundRefreshes++;

    // Run refresh in background (don't await)
    setImmediate(async () => {
      try {
        logger.debug('TieredCache background refresh started', { key: cacheKey });
        const value = await fetchFn();
        await this.set(tenantId, key, value, ttlSeconds);
        logger.debug('TieredCache background refresh completed', { key: cacheKey });
      } catch (error) {
        logger.warn('TieredCache background refresh failed', {
          key: cacheKey,
          error: error instanceof Error ? error.message : String(error),
        });
        this.metrics.errors++;
      } finally {
        this.refreshInProgress.delete(cacheKey);
      }
    });
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const tieredCache = TieredCache.getInstance();
export default tieredCache;

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Get or fetch with current tenant context
 */
export async function getOrFetchCached<T>(
  key: string,
  fetchFn: () => Promise<T>,
  options: TieredCacheOptions = {}
): Promise<T> {
  const tenant = getCurrentTenant();
  return tieredCache.getOrFetch(tenant.tenantId, key, fetchFn, options);
}

/**
 * Invalidate cache with current tenant context
 */
export async function invalidateCached(key: string): Promise<boolean> {
  const tenant = getCurrentTenant();
  return tieredCache.invalidate(tenant.tenantId, key);
}
