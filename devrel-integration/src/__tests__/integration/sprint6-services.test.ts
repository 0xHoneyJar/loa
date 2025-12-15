/**
 * Integration Tests for Sprint 6 Services
 *
 * Sprint 6 - Task 6.4: Integration Testing Suite
 *
 * Tests the integration between Sprint 6 services:
 * - DataExtractionService
 * - ContentValidationService
 * - RACIService
 * - UsageTracker
 *
 * Also tests integration with Sprint 4/5 dependencies:
 * - TenantContextProvider
 * - TieredCache
 *
 * Run with: npm run test:integration
 */

import { DataExtractionService } from '../../services/data-extraction-service';
import { ContentValidationService } from '../../services/content-validation-service';
import { RACIService } from '../../services/raci-service';
import { UsageTracker } from '../../services/usage-tracker';

// Mock external dependencies
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

jest.mock('../../services/tenant-context', () => ({
  getCurrentTenant: jest.fn(() => ({
    tenantId: 'test-tenant',
    name: 'Test Tenant',
    config: {
      enabledFeatures: ['transformations', 'marketing-support'],
      maxTransformationsPerDay: 100,
      maxConcurrentTransforms: 5,
      allowedPersonas: ['leadership', 'product', 'marketing', 'devrel'],
    },
    credentials: {
      linear: { teamId: 'team-123' },
    },
    metadata: {
      createdAt: new Date(),
      updatedAt: new Date(),
      status: 'active',
    },
  })),
  getCurrentTenantId: jest.fn(() => 'test-tenant'),
}));

jest.mock('../../services/tiered-cache', () => ({
  TieredCache: {
    getInstance: jest.fn(() => ({
      get: jest.fn().mockResolvedValue(null),
      set: jest.fn().mockResolvedValue(undefined),
    })),
  },
}));

describe('Sprint 6 Services Integration', () => {
  // Reset singletons before each test
  beforeEach(() => {
    (DataExtractionService as any).instance = undefined;
    (ContentValidationService as any).instance = undefined;
    (RACIService as any).instance = undefined;
    (UsageTracker as any).instance = undefined;
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('Service Initialization', () => {
    test('all Sprint 6 services should initialize as singletons', () => {
      const dataService = DataExtractionService.getInstance();
      const validationService = ContentValidationService.getInstance();
      const raciService = RACIService.getInstance();
      const usageTracker = UsageTracker.getInstance();

      expect(dataService).toBeDefined();
      expect(validationService).toBeDefined();
      expect(raciService).toBeDefined();
      expect(usageTracker).toBeDefined();

      // Verify singleton pattern
      expect(DataExtractionService.getInstance()).toBe(dataService);
      expect(ContentValidationService.getInstance()).toBe(validationService);
      expect(RACIService.getInstance()).toBe(raciService);
      expect(UsageTracker.getInstance()).toBe(usageTracker);
    });
  });

  describe('DataExtractionService Integration', () => {
    let service: DataExtractionService;

    beforeEach(() => {
      service = DataExtractionService.getInstance();

      // Configure mock Linear client
      service.setLinearClient({
        getIssues: jest.fn().mockResolvedValue([
          {
            id: 'issue-1',
            title: 'Test Issue',
            state: { name: 'Done', type: 'completed' },
            assignee: { name: 'Test User' },
            estimate: 3,
            createdAt: new Date().toISOString(),
            labels: { nodes: [{ name: 'feature' }] },
          },
        ]),
        getCycle: jest.fn().mockResolvedValue({
          id: 'sprint-1',
          name: 'Sprint 1',
          issues: {
            nodes: [
              {
                id: 'issue-1',
                title: 'Issue 1',
                state: { name: 'Done', type: 'completed' },
                assignee: { name: 'User A' },
                estimate: 3,
                createdAt: new Date().toISOString(),
              },
            ],
          },
        }),
      });
    });

    test('should extract user stats with tenant context', async () => {
      const stats = await service.extractUserStats('TestProduct', 'last-30-days');

      expect(stats.product).toBe('TestProduct');
      expect(stats).toHaveProperty('totalUsers');
      expect(stats).toHaveProperty('activeUsers');
      expect(stats).toHaveProperty('topFeatures');
    });

    test('should extract feature usage with caching integration', async () => {
      const usage = await service.extractFeatureUsage('authentication', 'last-7-days');

      expect(usage.feature).toBe('authentication');
      expect(usage).toHaveProperty('totalUsage');
      expect(usage).toHaveProperty('trend');
    });

    test('should extract sprint metrics', async () => {
      const metrics = await service.extractSprintMetrics('sprint-1');

      expect(metrics.sprintId).toBe('sprint-1');
      expect(metrics).toHaveProperty('completedTasks');
      expect(metrics).toHaveProperty('velocity');
      expect(metrics).toHaveProperty('tasksByStatus');
    });

    test('should format stats for Discord', async () => {
      const stats = await service.extractUserStats('TestProduct', 'last-30-days');
      const formatted = service.formatUserStatsForDiscord(stats);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('fields');
    });
  });

  describe('ContentValidationService Integration', () => {
    let service: ContentValidationService;

    beforeEach(() => {
      service = ContentValidationService.getInstance();
    });

    test('should validate content with rule-based validation', async () => {
      const content = 'Our product helps users manage tasks efficiently.';
      const report = await service.validateContent(content, 'TestProduct');

      expect(report).toHaveProperty('verdict');
      expect(report).toHaveProperty('findings');
      expect(report).toHaveProperty('suggestions');
      expect(report).toHaveProperty('overallScore');
    });

    test('should detect issues in problematic content', async () => {
      const content = 'Our product is 100% secure and guaranteed to 10x your investment on blockchain.';
      const report = await service.validateContent(content, 'TestProduct');

      expect(report.findings.length).toBeGreaterThan(0);
      expect(report.verdict).not.toBe('accurate');
    });

    test('should use registered documentation', async () => {
      service.registerDocumentation({
        name: 'Test PRD',
        type: 'prd',
        content: 'Product requirements for TestProduct.',
      });

      const report = await service.validateContent('Test content', 'TestProduct');

      expect(report.documentationSourcesChecked).toContain('Test PRD');
    });

    test('should format report for Discord', async () => {
      const report = await service.validateContent('Test content', 'TestProduct');
      const formatted = service.formatReportForDiscord(report);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('fields');
    });

    test('should respect strictness levels', async () => {
      const content = 'Our product always delivers.';

      const relaxedReport = await service.validateContent(content, 'TestProduct', {
        strictness: 'relaxed',
      });

      const strictReport = await service.validateContent(content, 'TestProduct', {
        strictness: 'strict',
      });

      expect(strictReport.findings.length).toBeGreaterThanOrEqual(
        relaxedReport.findings.length
      );
    });
  });

  describe('RACIService Integration', () => {
    let service: RACIService;

    beforeEach(() => {
      service = RACIService.getInstance();
    });

    test('should generate RACI matrix with default team', async () => {
      const matrix = await service.generateRACIMatrix('TestProduct', 'feature-launch');

      expect(matrix.product).toBe('TestProduct');
      expect(matrix.initiative).toBe('feature-launch');
      expect(matrix.tasks.length).toBeGreaterThan(0);
      expect(matrix.teamMembers.length).toBeGreaterThan(0);
      expect(matrix.assignments.length).toBe(matrix.tasks.length);
    });

    test('should use different templates', async () => {
      const productLaunch = await service.generateRACIMatrix('Product', 'launch', {
        template: 'product_launch',
      });

      const securityRelease = await service.generateRACIMatrix('Product', 'security', {
        template: 'security_release',
      });

      expect(productLaunch.tasks).not.toEqual(securityRelease.tasks);
    });

    test('should calculate summary correctly', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'initiative');

      expect(matrix.summary).toHaveProperty('totalTasks');
      expect(matrix.summary).toHaveProperty('totalMembers');
      expect(matrix.summary).toHaveProperty('responsibleCount');
      expect(matrix.summary).toHaveProperty('accountableCount');
      expect(matrix.summary).toHaveProperty('unassignedTasks');
    });

    test('should format matrix for Discord', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'initiative');
      const formatted = service.formatMatrixForDiscord(matrix);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('fields');
    });

    test('should integrate with Linear for team data', async () => {
      service.setLinearClient({
        getTeam: jest.fn().mockResolvedValue({
          id: 'team-123',
          name: 'Engineering',
          members: {
            nodes: [
              { id: 'user-1', name: 'alice-engineer', displayName: 'Alice' },
              { id: 'user-2', name: 'bob-pm', displayName: 'Bob' },
            ],
          },
        }),
      });

      const matrix = await service.generateRACIMatrix('Product', 'initiative');

      expect(matrix.teamMembers.length).toBe(2);
      expect(matrix.teamMembers.some((m) => m.name === 'Alice')).toBe(true);
    });
  });

  describe('UsageTracker Integration', () => {
    let tracker: UsageTracker;

    beforeEach(() => {
      tracker = UsageTracker.getInstance();
      tracker.clearInMemoryCounters();
    });

    test('should track transformations and generate report', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);
      await tracker.trackTransformation('test-tenant', 'marketing', true);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.transformations.total).toBe(2);
      expect(report.transformations.cachedHits).toBe(1);
      expect(report.transformations.apiCalls).toBe(1);
    });

    test('should track API calls', async () => {
      await tracker.trackApiCall('test-tenant', 'claude', {
        tokensIn: 1000,
        tokensOut: 500,
      });
      await tracker.trackApiCall('test-tenant', 'googleDocs', {});

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.apiCalls.claude.count).toBe(1);
      expect(report.apiCalls.claude.tokensIn).toBe(1000);
      expect(report.apiCalls.googleDocs.count).toBe(1);
    });

    test('should calculate costs', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);

      const report = await tracker.getUsageReport('test-tenant');

      expect(report.costs.total).toBeGreaterThan(0);
      expect(report.costs.costPerTransformation).toBeGreaterThan(0);
    });

    test('should compare periods', async () => {
      const comparison = await tracker.getUsageComparison('test-tenant');

      expect(comparison).toHaveProperty('current');
      expect(comparison).toHaveProperty('previous');
      expect(comparison).toHaveProperty('changes');
    });

    test('should format report for Discord', async () => {
      await tracker.trackTransformation('test-tenant', 'leadership', false);

      const report = await tracker.getUsageReport('test-tenant');
      const formatted = tracker.formatReportForDiscord(report);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('fields');
    });
  });

  describe('Cross-Service Integration', () => {
    test('services should work together for marketing workflow', async () => {
      const dataService = DataExtractionService.getInstance();
      const validationService = ContentValidationService.getInstance();
      const raciService = RACIService.getInstance();
      const tracker = UsageTracker.getInstance();

      tracker.clearInMemoryCounters();

      // Configure data service
      dataService.setLinearClient({
        getIssues: jest.fn().mockResolvedValue([
          {
            id: 'issue-1',
            title: 'Feature Implementation',
            state: { name: 'Done', type: 'completed' },
            createdAt: new Date().toISOString(),
          },
        ]),
        getCycle: jest.fn().mockResolvedValue({
          id: 'sprint-1',
          name: 'Sprint 1',
          issues: { nodes: [] },
        }),
      });

      // Step 1: Extract data for marketing
      const stats = await dataService.extractUserStats('MiBera', 'last-30-days');
      expect(stats.product).toBe('MiBera');

      // Step 2: Track the extraction
      await tracker.trackApiCall('test-tenant', 'claude', { tokensIn: 500, tokensOut: 100 });

      // Step 3: Validate marketing content
      const marketingContent = `MiBera has ${stats.totalUsers} users this month.`;
      const validation = await validationService.validateContent(marketingContent, 'MiBera');
      expect(validation).toHaveProperty('verdict');

      // Step 4: Generate RACI for marketing campaign
      const raci = await raciService.generateRACIMatrix('MiBera', 'marketing-campaign', {
        template: 'marketing_campaign',
      });
      expect(raci.tasks.some((t) => t.category === 'marketing')).toBe(true);

      // Step 5: Check usage metrics
      const usageReport = await tracker.getUsageReport('test-tenant');
      expect(usageReport.apiCalls.claude.count).toBe(1);
    });

    test('services should handle tenant isolation', async () => {
      const tracker = UsageTracker.getInstance();
      tracker.clearInMemoryCounters();

      // Track for tenant A
      await tracker.trackTransformation('tenant-a', 'leadership', false);
      await tracker.trackTransformation('tenant-a', 'marketing', true);

      // Track for tenant B
      await tracker.trackTransformation('tenant-b', 'product', false);

      // Verify isolation
      const reportA = await tracker.getUsageReport('tenant-a');
      const reportB = await tracker.getUsageReport('tenant-b');

      expect(reportA.transformations.total).toBe(2);
      expect(reportB.transformations.total).toBe(1);
    });
  });

  describe('Error Handling', () => {
    test('DataExtractionService should handle missing sprint gracefully', async () => {
      const service = DataExtractionService.getInstance();

      service.setLinearClient({
        getIssues: jest.fn().mockResolvedValue([]),
        getCycle: jest.fn().mockResolvedValue(null),
      });

      await expect(service.extractSprintMetrics('non-existent')).rejects.toThrow(
        'Sprint not found'
      );
    });

    test('ContentValidationService should handle Google Docs errors', async () => {
      const service = ContentValidationService.getInstance();

      // No Google Docs client configured
      await expect(
        service.validateGoogleDoc('https://docs.google.com/document/d/abc/edit', 'Product')
      ).rejects.toThrow('Google Docs client not configured');
    });

    test('RACIService should fall back when Linear fails', async () => {
      const service = RACIService.getInstance();

      service.setLinearClient({
        getTeam: jest.fn().mockRejectedValue(new Error('API error')),
      });

      // Should not throw, should use default team
      const matrix = await service.generateRACIMatrix('Product', 'initiative');
      expect(matrix.teamMembers.length).toBeGreaterThan(0);
    });

    test('UsageTracker should handle Redis failures gracefully', async () => {
      const tracker = UsageTracker.getInstance();
      tracker.clearInMemoryCounters();

      const mockRedis = {
        incr: jest.fn().mockRejectedValue(new Error('Redis error')),
        incrby: jest.fn().mockRejectedValue(new Error('Redis error')),
        get: jest.fn().mockRejectedValue(new Error('Redis error')),
        mget: jest.fn().mockRejectedValue(new Error('Redis error')),
        expire: jest.fn().mockRejectedValue(new Error('Redis error')),
        keys: jest.fn().mockRejectedValue(new Error('Redis error')),
      };

      tracker.setRedisClient(mockRedis);

      // Should not throw, should fall back to in-memory
      await expect(
        tracker.trackTransformation('test-tenant', 'leadership', false)
      ).resolves.not.toThrow();

      const report = await tracker.getUsageReport('test-tenant');
      expect(report).toBeDefined();
    });
  });

  describe('Performance', () => {
    test('services should complete within reasonable time', async () => {
      const startTime = Date.now();

      const dataService = DataExtractionService.getInstance();
      const validationService = ContentValidationService.getInstance();
      const raciService = RACIService.getInstance();

      dataService.setLinearClient({
        getIssues: jest.fn().mockResolvedValue([]),
        getCycle: jest.fn().mockResolvedValue({ id: '1', name: 'Sprint', issues: { nodes: [] } }),
      });

      await Promise.all([
        dataService.extractUserStats('Product', 'last-30-days'),
        validationService.validateContent('Test content', 'Product'),
        raciService.generateRACIMatrix('Product', 'initiative'),
      ]);

      const elapsed = Date.now() - startTime;

      // All operations should complete within 1 second
      expect(elapsed).toBeLessThan(1000);
    });
  });
});
