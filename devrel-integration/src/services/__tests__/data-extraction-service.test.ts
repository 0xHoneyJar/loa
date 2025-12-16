/**
 * Data Extraction Service Tests
 *
 * Sprint 6 - Task 6.1: Unit tests for DataExtractionService
 */

import {
  DataExtractionService,
  LinearClientInterface,
  LinearIssue,
  LinearSprint,
} from '../data-extraction-service';

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
    config: {
      enabledFeatures: ['transformations'],
      maxTransformationsPerDay: 100,
      maxConcurrentTransforms: 5,
      allowedPersonas: ['leadership', 'product', 'marketing', 'devrel'],
    },
    metadata: {
      createdAt: new Date(),
      updatedAt: new Date(),
      status: 'active',
    },
  })),
}));

jest.mock('../tiered-cache', () => ({
  TieredCache: {
    getInstance: jest.fn(() => ({
      get: jest.fn().mockResolvedValue(null),
      set: jest.fn().mockResolvedValue(undefined),
    })),
  },
}));

describe('DataExtractionService', () => {
  let service: DataExtractionService;
  let mockLinearClient: jest.Mocked<LinearClientInterface>;

  beforeEach(() => {
    // Reset singleton
    (DataExtractionService as any).instance = undefined;
    service = DataExtractionService.getInstance();

    mockLinearClient = {
      getIssues: jest.fn(),
      getCycle: jest.fn(),
    };

    service.setLinearClient(mockLinearClient);
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('getInstance', () => {
    test('should return singleton instance', () => {
      const instance1 = DataExtractionService.getInstance();
      const instance2 = DataExtractionService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('extractUserStats', () => {
    test('should extract user stats for a product', async () => {
      const mockIssues: LinearIssue[] = [
        {
          id: 'issue-1',
          title: 'Issue 1',
          state: { name: 'Done', type: 'completed' },
          assignee: { name: 'User A' },
          createdAt: new Date().toISOString(),
          labels: { nodes: [{ name: 'feature' }] },
        },
        {
          id: 'issue-2',
          title: 'Issue 2',
          state: { name: 'In Progress', type: 'started' },
          assignee: { name: 'User B' },
          createdAt: new Date().toISOString(),
          labels: { nodes: [{ name: 'bug' }] },
        },
      ];

      mockLinearClient.getIssues.mockResolvedValue(mockIssues);

      const stats = await service.extractUserStats('TestProduct', 'last-30-days');

      expect(stats).toHaveProperty('product', 'TestProduct');
      expect(stats).toHaveProperty('period', 'last-30-days');
      expect(stats).toHaveProperty('totalUsers');
      expect(stats).toHaveProperty('activeUsers');
      expect(stats).toHaveProperty('newUsers');
      expect(stats).toHaveProperty('retentionRate');
      expect(stats).toHaveProperty('growthRate');
      expect(stats).toHaveProperty('topFeatures');
      expect(stats).toHaveProperty('generatedAt');
    });

    test('should handle empty issues list', async () => {
      mockLinearClient.getIssues.mockResolvedValue([]);

      const stats = await service.extractUserStats('EmptyProduct', 'last-7-days');

      expect(stats.totalUsers).toBeGreaterThanOrEqual(0);
      expect(stats.topFeatures).toEqual([]);
    });

    test('should extract top features from labels', async () => {
      const mockIssues: LinearIssue[] = [
        {
          id: 'issue-1',
          title: 'Issue 1',
          state: { name: 'Done', type: 'completed' },
          createdAt: new Date().toISOString(),
          labels: { nodes: [{ name: 'authentication' }, { name: 'api' }] },
        },
        {
          id: 'issue-2',
          title: 'Issue 2',
          state: { name: 'Done', type: 'completed' },
          createdAt: new Date().toISOString(),
          labels: { nodes: [{ name: 'authentication' }] },
        },
      ];

      mockLinearClient.getIssues.mockResolvedValue(mockIssues);

      const stats = await service.extractUserStats('TestProduct', 'last-30-days');

      expect(stats.topFeatures.length).toBeGreaterThan(0);
      expect(stats.topFeatures[0].name).toBe('authentication');
      expect(stats.topFeatures[0].usage).toBe(2);
    });
  });

  describe('extractFeatureUsage', () => {
    test('should extract feature usage metrics', async () => {
      const mockIssues: LinearIssue[] = [
        {
          id: 'issue-1',
          title: 'Feature Issue',
          state: { name: 'Done', type: 'completed' },
          assignee: { name: 'User A' },
          createdAt: new Date().toISOString(),
        },
      ];

      mockLinearClient.getIssues.mockResolvedValue(mockIssues);

      const usage = await service.extractFeatureUsage('authentication', 'last-30-days');

      expect(usage).toHaveProperty('feature', 'authentication');
      expect(usage).toHaveProperty('period', 'last-30-days');
      expect(usage).toHaveProperty('totalUsage');
      expect(usage).toHaveProperty('uniqueUsers');
      expect(usage).toHaveProperty('avgUsagePerUser');
      expect(usage).toHaveProperty('trend');
      expect(usage).toHaveProperty('dailyBreakdown');
    });

    test('should calculate trend from daily breakdown', async () => {
      const mockIssues: LinearIssue[] = [];
      const now = new Date();

      // Generate issues over 14 days
      for (let i = 0; i < 14; i++) {
        const date = new Date(now);
        date.setDate(date.getDate() - i);
        mockIssues.push({
          id: `issue-${i}`,
          title: `Issue ${i}`,
          state: { name: 'Done', type: 'completed' },
          createdAt: date.toISOString(),
        });
      }

      mockLinearClient.getIssues.mockResolvedValue(mockIssues);

      const usage = await service.extractFeatureUsage('test-feature', 'last-30-days');

      expect(['increasing', 'stable', 'decreasing']).toContain(usage.trend);
    });
  });

  describe('extractSprintMetrics', () => {
    test('should extract sprint metrics', async () => {
      const mockSprint: LinearSprint = {
        id: 'sprint-1',
        name: 'Sprint 1',
        startsAt: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
        endsAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
        issues: {
          nodes: [
            {
              id: 'issue-1',
              title: 'Completed Issue',
              state: { name: 'Done', type: 'completed' },
              assignee: { name: 'User A' },
              estimate: 3,
              createdAt: new Date().toISOString(),
            },
            {
              id: 'issue-2',
              title: 'In Progress Issue',
              state: { name: 'In Progress', type: 'started' },
              assignee: { name: 'User B' },
              estimate: 2,
              createdAt: new Date().toISOString(),
            },
            {
              id: 'issue-3',
              title: 'Todo Issue',
              state: { name: 'Todo', type: 'unstarted' },
              estimate: 1,
              createdAt: new Date().toISOString(),
            },
          ],
        },
      };

      mockLinearClient.getCycle.mockResolvedValue(mockSprint);

      const metrics = await service.extractSprintMetrics('sprint-1');

      expect(metrics.sprintId).toBe('sprint-1');
      expect(metrics.sprintName).toBe('Sprint 1');
      expect(metrics.totalTasks).toBe(3);
      expect(metrics.completedTasks).toBe(1);
      expect(metrics.velocity).toBe(3); // Only completed issues
      expect(metrics.tasksByStatus.done).toBe(1);
      expect(metrics.tasksByStatus.inProgress).toBe(1);
      expect(metrics.tasksByStatus.todo).toBe(1);
    });

    test('should calculate completion rate correctly', async () => {
      const mockSprint: LinearSprint = {
        id: 'sprint-2',
        name: 'Sprint 2',
        issues: {
          nodes: [
            {
              id: 'issue-1',
              title: 'Done 1',
              state: { name: 'Done', type: 'completed' },
              createdAt: new Date().toISOString(),
            },
            {
              id: 'issue-2',
              title: 'Done 2',
              state: { name: 'Done', type: 'completed' },
              createdAt: new Date().toISOString(),
            },
          ],
        },
      };

      mockLinearClient.getCycle.mockResolvedValue(mockSprint);

      const metrics = await service.extractSprintMetrics('sprint-2');

      expect(metrics.completionRate).toBe(100);
    });

    test('should throw error for non-existent sprint', async () => {
      mockLinearClient.getCycle.mockResolvedValue(null);

      await expect(service.extractSprintMetrics('non-existent')).rejects.toThrow(
        'Sprint not found: non-existent'
      );
    });

    test('should calculate contributor metrics', async () => {
      const mockSprint: LinearSprint = {
        id: 'sprint-3',
        name: 'Sprint 3',
        issues: {
          nodes: [
            {
              id: 'issue-1',
              title: 'Issue 1',
              state: { name: 'Done', type: 'completed' },
              assignee: { name: 'Alice' },
              estimate: 3,
              createdAt: new Date().toISOString(),
            },
            {
              id: 'issue-2',
              title: 'Issue 2',
              state: { name: 'Done', type: 'completed' },
              assignee: { name: 'Alice' },
              estimate: 2,
              createdAt: new Date().toISOString(),
            },
            {
              id: 'issue-3',
              title: 'Issue 3',
              state: { name: 'Done', type: 'completed' },
              assignee: { name: 'Bob' },
              estimate: 8,
              createdAt: new Date().toISOString(),
            },
          ],
        },
      };

      mockLinearClient.getCycle.mockResolvedValue(mockSprint);

      const metrics = await service.extractSprintMetrics('sprint-3');

      expect(metrics.contributors.length).toBe(2);
      // Bob has highest points (8 > 5)
      expect(metrics.contributors[0].name).toBe('Bob');
      expect(metrics.contributors[0].pointsDelivered).toBe(8);
    });
  });

  describe('formatUserStatsForDiscord', () => {
    test('should format user stats for Discord embed', async () => {
      mockLinearClient.getIssues.mockResolvedValue([]);

      const stats = await service.extractUserStats('TestProduct', 'last-30-days');
      const formatted = service.formatUserStatsForDiscord(stats);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('description');
      expect(formatted).toHaveProperty('fields');
      expect(formatted).toHaveProperty('footer');
    });
  });

  describe('formatSprintMetricsForDiscord', () => {
    test('should format sprint metrics for Discord embed', async () => {
      const mockSprint: LinearSprint = {
        id: 'sprint-1',
        name: 'Test Sprint',
        issues: { nodes: [] },
      };

      mockLinearClient.getCycle.mockResolvedValue(mockSprint);

      const metrics = await service.extractSprintMetrics('sprint-1');
      const formatted = service.formatSprintMetricsForDiscord(metrics);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('description');
      expect(formatted).toHaveProperty('fields');
    });
  });

  describe('without Linear client', () => {
    test('should return empty issues when no client configured', async () => {
      (DataExtractionService as any).instance = undefined;
      const newService = DataExtractionService.getInstance();
      // Don't set Linear client

      const stats = await newService.extractUserStats('TestProduct', 'last-30-days');

      expect(stats.topFeatures).toEqual([]);
    });
  });
});
