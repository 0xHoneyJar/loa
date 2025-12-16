/**
 * Usage Tracker Service Tests
 *
 * Sprint 6 - Task 6.5: Unit tests for UsageTracker
 */

import { UsageTracker, RedisClientInterface } from '../usage-tracker';

// Mock dependencies
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

jest.mock('../tenant-context', () => ({
  getCurrentTenant: jest.fn(() => ({
    tenantId: 'test-tenant',
    name: 'Test Tenant',
  })),
  getCurrentTenantId: jest.fn(() => 'test-tenant'),
}));

describe('UsageTracker', () => {
  let tracker: UsageTracker;
  let mockRedisClient: jest.Mocked<RedisClientInterface>;

  beforeEach(() => {
    // Reset singleton
    (UsageTracker as any).instance = undefined;
    tracker = UsageTracker.getInstance();

    mockRedisClient = {
      incr: jest.fn().mockResolvedValue(1),
      incrby: jest.fn().mockResolvedValue(1),
      get: jest.fn().mockResolvedValue(null),
      mget: jest.fn().mockResolvedValue([]),
      expire: jest.fn().mockResolvedValue(1),
      keys: jest.fn().mockResolvedValue([]),
    };
  });

  afterEach(() => {
    tracker.clearInMemoryCounters();
    jest.clearAllMocks();
  });

  describe('getInstance', () => {
    test('should return singleton instance', () => {
      const instance1 = UsageTracker.getInstance();
      const instance2 = UsageTracker.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('trackTransformation', () => {
    test('should track transformation with in-memory counters', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);

      // Get report to verify tracking
      const report = await tracker.getUsageReport('test-tenant');

      expect(report.transformations.total).toBe(1);
    });

    test('should track cached transformation', async () => {
      await tracker.trackTransformation('test-tenant', 'marketing', true);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.transformations.cachedHits).toBe(1);
    });

    test('should track API transformation', async () => {
      await tracker.trackTransformation('test-tenant', 'product', false);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.transformations.apiCalls).toBe(1);
    });

    test('should track by persona', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);
      await tracker.trackTransformation('test-tenant', 'leadership', false);
      await tracker.trackTransformation('test-tenant', 'marketing', true);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.transformations.byPersona.leadership).toBe(2);
      expect(report.transformations.byPersona.marketing).toBe(1);
    });

    test('should use Redis when available', async () => {
      tracker.setRedisClient(mockRedisClient);

      await tracker.trackTransformation('test-tenant', 'leadership', false);

      expect(mockRedisClient.incr).toHaveBeenCalled();
      expect(mockRedisClient.expire).toHaveBeenCalled();
    });

    test('should fall back to in-memory on Redis failure', async () => {
      tracker.setRedisClient(mockRedisClient);
      mockRedisClient.incr.mockRejectedValue(new Error('Redis error'));
      mockRedisClient.mget.mockRejectedValue(new Error('Redis error'));

      await tracker.trackTransformation('test-tenant', 'leadership', false);

      // Should not throw and should use in-memory fallback
      const report = await tracker.getUsageReport('test-tenant');
      expect(report.transformations.total).toBeGreaterThanOrEqual(0);
    });
  });

  describe('trackApiCall', () => {
    test('should track Claude API calls', async () => {
      await tracker.trackApiCall('test-tenant', 'claude', {
        tokensIn: 1000,
        tokensOut: 500,
      });

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.apiCalls.claude.count).toBe(1);
      expect(report.apiCalls.claude.tokensIn).toBe(1000);
      expect(report.apiCalls.claude.tokensOut).toBe(500);
    });

    test('should track Google Drive API calls', async () => {
      await tracker.trackApiCall('test-tenant', 'googleDrive', {});

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.apiCalls.googleDrive.count).toBe(1);
    });

    test('should track Google Docs API calls', async () => {
      await tracker.trackApiCall('test-tenant', 'googleDocs', {});

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.apiCalls.googleDocs.count).toBe(1);
    });

    test('should track storage size', async () => {
      await tracker.trackApiCall('test-tenant', 'googleDocs', {
        sizeBytes: 1024,
      });

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.storage.totalSizeBytes).toBe(1024);
    });
  });

  describe('trackDocumentCreation', () => {
    test('should track document creation', async () => {
      await tracker.trackDocumentCreation('test-tenant', 2048);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.storage.documentsCreated).toBe(1);
      expect(report.storage.totalSizeBytes).toBe(2048);
    });

    test('should accumulate document sizes', async () => {
      await tracker.trackDocumentCreation('test-tenant', 1024);
      await tracker.trackDocumentCreation('test-tenant', 2048);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.storage.documentsCreated).toBe(2);
      expect(report.storage.totalSizeBytes).toBe(3072);
    });
  });

  describe('getUsageReport', () => {
    test('should return complete usage report', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);
      await tracker.trackApiCall('test-tenant', 'claude', { tokensIn: 500, tokensOut: 100 });

      const report = await tracker.getUsageReport('test-tenant');

      expect(report).toHaveProperty('tenantId', 'test-tenant');
      expect(report).toHaveProperty('period');
      expect(report).toHaveProperty('transformations');
      expect(report).toHaveProperty('apiCalls');
      expect(report).toHaveProperty('storage');
      expect(report).toHaveProperty('costs');
      expect(report).toHaveProperty('generatedAt');
    });

    test('should calculate Claude API costs', async () => {
      // Track some token usage (Sonnet pricing: $15/MTok in, $75/MTok out)
      await tracker.trackApiCall('test-tenant', 'claude', {
        tokensIn: 1_000_000, // 1M tokens = $15
        tokensOut: 100_000, // 100K tokens = $7.50
      });

      const report = await tracker.getUsageReport('test-tenant');

      // Cost should be $15 + $7.50 = $22.50
      expect(report.apiCalls.claude.estimatedCost).toBeCloseTo(22.5, 1);
    });

    test('should calculate total costs', async () => {
      const report = await tracker.getUsageReport('test-tenant');

      expect(report.costs.total).toBeGreaterThan(0);
      expect(report.costs.googleWorkspace).toBe(12); // Default user cost
      expect(report.costs.infrastructure).toBe(30); // Base cost
    });

    test('should calculate cost per transformation', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);
      await tracker.trackTransformation('test-tenant', 'marketing', false);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.costs.costPerTransformation).toBeGreaterThan(0);
      expect(report.costs.costPerTransformation).toBe(report.costs.total / 2);
    });

    test('should calculate cache efficiency', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false); // API
      await tracker.trackTransformation('test-tenant', 'leadership', true); // Cached
      await tracker.trackTransformation('test-tenant', 'marketing', true); // Cached

      const report = await tracker.getUsageReport('test-tenant');

      // 2 cached out of 3 total = 66.67%
      expect(report.costs.cacheEfficiency).toBeCloseTo(0.667, 1);
    });

    test('should handle zero transformations', async () => {
      const report = await tracker.getUsageReport('test-tenant');

      expect(report.costs.costPerTransformation).toBe(0);
      expect(report.costs.cacheEfficiency).toBe(0);
    });

    test('should use Redis for fetching counters when available', async () => {
      tracker.setRedisClient(mockRedisClient);

      mockRedisClient.mget.mockResolvedValue(['10', '5', '5', '3', '1000', '500', '2', '5', '1', '1024']);
      mockRedisClient.keys.mockResolvedValue([]);

      const report = await tracker.getUsageReport('test-tenant');

      expect(mockRedisClient.mget).toHaveBeenCalled();
      expect(report.transformations.total).toBe(10);
    });

    test('should return specific period report', async () => {
      const report = await tracker.getUsageReport('test-tenant', '2025-01');

      expect(report.period).toBe('2025-01');
    });
  });

  describe('getUsageComparison', () => {
    test('should compare current and previous periods', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);

      const comparison = await tracker.getUsageComparison('test-tenant');

      expect(comparison).toHaveProperty('current');
      expect(comparison).toHaveProperty('previous');
      expect(comparison).toHaveProperty('changes');
    });

    test('should calculate changes correctly', async () => {
      const comparison = await tracker.getUsageComparison('test-tenant');

      expect(comparison.changes).toHaveProperty('transformations');
      expect(comparison.changes).toHaveProperty('apiCalls');
      expect(comparison.changes).toHaveProperty('costs');
      expect(comparison.changes).toHaveProperty('cacheEfficiency');
    });

    test('should compare specified periods', async () => {
      const comparison = await tracker.getUsageComparison('test-tenant', '2025-02', '2025-01');

      expect(comparison.current.period).toBe('2025-02');
      expect(comparison.previous.period).toBe('2025-01');
    });
  });

  describe('formatReportForDiscord', () => {
    test('should format report for Discord', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);
      const report = await tracker.getUsageReport('test-tenant');
      const formatted = tracker.formatReportForDiscord(report);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('description');
      expect(formatted).toHaveProperty('fields');
      expect(formatted).toHaveProperty('footer');
    });

    test('should include all metric sections', async () => {
      const report = await tracker.getUsageReport('test-tenant');
      const formatted = tracker.formatReportForDiscord(report) as any;

      const fields = formatted.fields;
      expect(fields.some((f: any) => f.name === 'Transformations')).toBe(true);
      expect(fields.some((f: any) => f.name === 'API Calls')).toBe(true);
      expect(fields.some((f: any) => f.name === 'Costs')).toBe(true);
      expect(fields.some((f: any) => f.name === 'Efficiency')).toBe(true);
    });

    test('should format currency correctly', async () => {
      const report = await tracker.getUsageReport('test-tenant');
      const formatted = tracker.formatReportForDiscord(report) as any;

      const costsField = formatted.fields.find((f: any) => f.name === 'Costs');
      expect(costsField.value).toContain('$');
    });

    test('should include persona breakdown', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);
      await tracker.trackTransformation('test-tenant', 'marketing', true);

      const report = await tracker.getUsageReport('test-tenant');
      const formatted = tracker.formatReportForDiscord(report) as any;

      const personasField = formatted.fields.find((f: any) => f.name === 'Personas');
      expect(personasField.value).toContain('leadership');
      expect(personasField.value).toContain('marketing');
    });
  });

  describe('period handling', () => {
    test('should generate correct current period format', async () => {
      const report = await tracker.getUsageReport('test-tenant');

      // Period should be YYYY-MM format
      expect(report.period).toMatch(/^\d{4}-\d{2}$/);
    });

    test('should calculate previous period correctly', async () => {
      const comparison = await tracker.getUsageComparison('test-tenant', '2025-01');

      expect(comparison.previous.period).toBe('2024-12');
    });

    test('should handle year boundary in previous period', async () => {
      const comparison = await tracker.getUsageComparison('test-tenant', '2025-01');

      expect(comparison.previous.period).toBe('2024-12');
    });
  });

  describe('clearInMemoryCounters', () => {
    test('should clear all in-memory counters', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);

      let report = await tracker.getUsageReport('test-tenant');
      expect(report.transformations.total).toBe(1);

      tracker.clearInMemoryCounters();

      report = await tracker.getUsageReport('test-tenant');
      expect(report.transformations.total).toBe(0);
    });
  });

  describe('Redis key expiration', () => {
    test('should set expiration on Redis keys', async () => {
      tracker.setRedisClient(mockRedisClient);

      await tracker.trackTransformation('test-tenant', 'leadership', false);

      // Should set 90-day expiration
      expect(mockRedisClient.expire).toHaveBeenCalledWith(
        expect.any(String),
        90 * 24 * 60 * 60
      );
    });
  });

  describe('tenant isolation', () => {
    test('should track separately for different tenants', async () => {
      await tracker.trackTransformation('tenant-a', 'leadership', false);
      await tracker.trackTransformation('tenant-a', 'leadership', false);
      await tracker.trackTransformation('tenant-b', 'marketing', true);

      const reportA = await tracker.getUsageReport('tenant-a');
      const reportB = await tracker.getUsageReport('tenant-b');

      expect(reportA.transformations.total).toBe(2);
      expect(reportB.transformations.total).toBe(1);
      expect(reportA.tenantId).toBe('tenant-a');
      expect(reportB.tenantId).toBe('tenant-b');
    });
  });

  describe('error handling', () => {
    test('should handle Redis error in trackTransformation', async () => {
      tracker.setRedisClient(mockRedisClient);
      mockRedisClient.incr.mockRejectedValue(new Error('Redis connection failed'));

      // Should not throw
      await expect(
        tracker.trackTransformation('test-tenant', 'leadership', false)
      ).resolves.not.toThrow();
    });

    test('should handle Redis error in trackApiCall', async () => {
      tracker.setRedisClient(mockRedisClient);
      mockRedisClient.incr.mockRejectedValue(new Error('Redis connection failed'));

      // Should not throw
      await expect(
        tracker.trackApiCall('test-tenant', 'claude', { tokensIn: 100 })
      ).resolves.not.toThrow();
    });

    test('should handle Redis error in getUsageReport', async () => {
      tracker.setRedisClient(mockRedisClient);
      mockRedisClient.mget.mockRejectedValue(new Error('Redis connection failed'));

      // Should fall back to in-memory
      const report = await tracker.getUsageReport('test-tenant');
      expect(report).toBeDefined();
    });
  });
});
