/**
 * RACI Service Tests
 *
 * Sprint 6 - Task 6.3: Unit tests for RACIService
 */

import {
  RACIService,
  LinearClientInterface,
  GoogleDocsClientInterface,
  TeamMember,
  RACITask,
} from '../raci-service';

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
    credentials: {
      linear: {
        teamId: 'team-123',
      },
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

describe('RACIService', () => {
  let service: RACIService;
  let mockLinearClient: jest.Mocked<LinearClientInterface>;
  let mockGoogleDocsClient: jest.Mocked<GoogleDocsClientInterface>;

  beforeEach(() => {
    // Reset singleton
    (RACIService as any).instance = undefined;
    service = RACIService.getInstance();

    mockLinearClient = {
      getTeam: jest.fn(),
    };

    mockGoogleDocsClient = {
      createDocument: jest.fn(),
    };
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('getInstance', () => {
    test('should return singleton instance', () => {
      const instance1 = RACIService.getInstance();
      const instance2 = RACIService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('generateRACIMatrix', () => {
    test('should generate RACI matrix with default team', async () => {
      const matrix = await service.generateRACIMatrix('TestProduct', 'token-launch');

      expect(matrix.product).toBe('TestProduct');
      expect(matrix.initiative).toBe('token-launch');
      expect(matrix.tasks.length).toBeGreaterThan(0);
      expect(matrix.teamMembers.length).toBeGreaterThan(0);
      expect(matrix.assignments.length).toBe(matrix.tasks.length);
      expect(matrix.summary).toBeDefined();
    });

    test('should generate tasks based on template', async () => {
      const productLaunchMatrix = await service.generateRACIMatrix('Product', 'launch', {
        template: 'product_launch',
      });

      const featureReleaseMatrix = await service.generateRACIMatrix('Product', 'feature', {
        template: 'feature_release',
      });

      expect(productLaunchMatrix.tasks.length).toBeGreaterThan(0);
      expect(featureReleaseMatrix.tasks.length).toBeGreaterThan(0);
      // Product launch typically has more tasks
      expect(productLaunchMatrix.tasks.length).toBeGreaterThanOrEqual(
        featureReleaseMatrix.tasks.length
      );
    });

    test('should use custom tasks when provided', async () => {
      const customTasks: RACITask[] = [
        {
          id: 'custom-1',
          name: 'Custom Task 1',
          description: 'Custom description',
          category: 'development',
          priority: 'high',
        },
        {
          id: 'custom-2',
          name: 'Custom Task 2',
          description: 'Another custom task',
          category: 'marketing',
          priority: 'medium',
        },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'custom-initiative', {
        customTasks,
      });

      expect(matrix.tasks).toEqual(customTasks);
    });

    test('should use custom team when provided', async () => {
      const customTeam: TeamMember[] = [
        { id: 'user-1', name: 'Alice', role: 'engineer', department: 'Engineering' },
        { id: 'user-2', name: 'Bob', role: 'product_manager', department: 'Product' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTeam,
      });

      expect(matrix.teamMembers).toEqual(customTeam);
    });

    test('should fetch team from Linear when available', async () => {
      service.setLinearClient(mockLinearClient);

      mockLinearClient.getTeam.mockResolvedValue({
        id: 'team-123',
        name: 'Engineering',
        members: {
          nodes: [
            { id: 'user-1', name: 'alice', displayName: 'Alice' },
            { id: 'user-2', name: 'bob-pm', displayName: 'Bob' },
          ],
        },
      });

      const matrix = await service.generateRACIMatrix('Product', 'initiative');

      expect(mockLinearClient.getTeam).toHaveBeenCalled();
      expect(matrix.teamMembers.length).toBe(2);
    });

    test('should fall back to defaults when Linear fails', async () => {
      service.setLinearClient(mockLinearClient);
      mockLinearClient.getTeam.mockRejectedValue(new Error('API error'));

      const matrix = await service.generateRACIMatrix('Product', 'initiative');

      expect(matrix.teamMembers.length).toBeGreaterThan(0);
    });
  });

  describe('RACI assignment rules', () => {
    test('should assign R to engineers for development tasks', async () => {
      const customTasks: RACITask[] = [
        {
          id: 'dev-task',
          name: 'Development Task',
          description: 'Build feature',
          category: 'development',
          priority: 'high',
        },
      ];

      const customTeam: TeamMember[] = [
        { id: 'eng-1', name: 'Engineer', role: 'engineer', department: 'Engineering' },
        { id: 'pm-1', name: 'PM', role: 'product_manager', department: 'Product' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTasks,
        customTeam,
      });

      const devTaskAssignments = matrix.assignments[0];
      const engineerAssignment = devTaskAssignments.find((a) => a.memberId === 'eng-1');
      const pmAssignment = devTaskAssignments.find((a) => a.memberId === 'pm-1');

      expect(engineerAssignment?.role).toBe('R');
      expect(pmAssignment?.role).toBe('A');
    });

    test('should assign R to marketing for marketing tasks', async () => {
      const customTasks: RACITask[] = [
        {
          id: 'mkt-task',
          name: 'Marketing Task',
          description: 'Create campaign',
          category: 'marketing',
          priority: 'high',
        },
      ];

      const customTeam: TeamMember[] = [
        { id: 'mkt-1', name: 'Marketer', role: 'marketing_lead', department: 'Marketing' },
        { id: 'pm-1', name: 'PM', role: 'product_manager', department: 'Product' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTasks,
        customTeam,
      });

      const mktTaskAssignments = matrix.assignments[0];
      const marketerAssignment = mktTaskAssignments.find((a) => a.memberId === 'mkt-1');

      expect(marketerAssignment?.role).toBe('R');
    });

    test('should assign R to DevOps for deployment tasks', async () => {
      const customTasks: RACITask[] = [
        {
          id: 'deploy-task',
          name: 'Deployment',
          description: 'Deploy to production',
          category: 'deployment',
          priority: 'high',
        },
      ];

      const customTeam: TeamMember[] = [
        { id: 'devops-1', name: 'DevOps', role: 'devops', department: 'Engineering' },
        { id: 'eng-1', name: 'Engineer', role: 'engineer', department: 'Engineering' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTasks,
        customTeam,
      });

      const deployAssignments = matrix.assignments[0];
      const devopsAssignment = deployAssignments.find((a) => a.memberId === 'devops-1');

      expect(devopsAssignment?.role).toBe('R');
    });

    test('should include reasons when requested', async () => {
      const customTasks: RACITask[] = [
        {
          id: 'task-1',
          name: 'Task',
          description: 'Description',
          category: 'development',
          priority: 'high',
        },
      ];

      const customTeam: TeamMember[] = [
        { id: 'eng-1', name: 'Engineer', role: 'engineer', department: 'Engineering' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTasks,
        customTeam,
        includeReasons: true,
      });

      const hasReasons = matrix.assignments.some((taskAssignments) =>
        taskAssignments.some((a) => a.reason !== undefined && a.role !== '')
      );

      expect(hasReasons).toBe(true);
    });
  });

  describe('summary calculation', () => {
    test('should calculate correct summary', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'initiative');

      expect(matrix.summary.totalTasks).toBe(matrix.tasks.length);
      expect(matrix.summary.totalMembers).toBe(matrix.teamMembers.length);
      expect(matrix.summary.responsibleCount).toBeGreaterThanOrEqual(0);
      expect(matrix.summary.accountableCount).toBeGreaterThanOrEqual(0);
      expect(matrix.summary.consultedCount).toBeGreaterThanOrEqual(0);
      expect(matrix.summary.informedCount).toBeGreaterThanOrEqual(0);
    });

    test('should identify unassigned tasks', async () => {
      // With no matching roles, tasks may be unassigned
      const customTasks: RACITask[] = [
        {
          id: 'task-1',
          name: 'Task without R/A',
          description: 'No one responsible',
          category: 'development',
          priority: 'high',
        },
      ];

      const customTeam: TeamMember[] = [
        { id: 'stakeholder-1', name: 'Stakeholder', role: 'stakeholder', department: 'External' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTasks,
        customTeam,
      });

      // Task should be unassigned since stakeholder doesn't have R or A for development
      expect(matrix.summary.unassignedTasks.length).toBeGreaterThan(0);
    });

    test('should identify overloaded members', async () => {
      const customTasks: RACITask[] = Array.from({ length: 10 }, (_, i) => ({
        id: `task-${i}`,
        name: `Task ${i}`,
        description: 'Description',
        category: 'development' as const,
        priority: 'high' as const,
      }));

      const customTeam: TeamMember[] = [
        { id: 'eng-1', name: 'Engineer', role: 'engineer', department: 'Engineering' },
        { id: 'pm-1', name: 'PM', role: 'product_manager', department: 'Product' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTasks,
        customTeam,
      });

      // Engineer should be overloaded with 10 R assignments
      expect(matrix.summary.overloadedMembers.length).toBeGreaterThan(0);
    });
  });

  describe('generateRACIDocument', () => {
    test('should generate matrix and create document', async () => {
      service.setGoogleDocsClient(mockGoogleDocsClient);

      mockGoogleDocsClient.createDocument.mockResolvedValue({
        documentId: 'doc-123',
        url: 'https://docs.google.com/document/d/doc-123/edit',
      });

      const result = await service.generateRACIDocument('Product', 'initiative');

      expect(result.matrix).toBeDefined();
      expect(result.documentUrl).toBe('https://docs.google.com/document/d/doc-123/edit');
      expect(mockGoogleDocsClient.createDocument).toHaveBeenCalled();
    });

    test('should return empty URL when no Google Docs client', async () => {
      const result = await service.generateRACIDocument('Product', 'initiative');

      expect(result.matrix).toBeDefined();
      expect(result.documentUrl).toBe('');
    });

    test('should handle document creation failure', async () => {
      service.setGoogleDocsClient(mockGoogleDocsClient);
      mockGoogleDocsClient.createDocument.mockRejectedValue(new Error('API error'));

      const result = await service.generateRACIDocument('Product', 'initiative');

      expect(result.matrix).toBeDefined();
      expect(result.documentUrl).toBe('');
    });
  });

  describe('formatMatrixForDiscord', () => {
    test('should format matrix for Discord embed', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'initiative');
      const formatted = service.formatMatrixForDiscord(matrix);

      expect(formatted).toHaveProperty('title');
      expect(formatted).toHaveProperty('description');
      expect(formatted).toHaveProperty('fields');
      expect(formatted).toHaveProperty('footer');
    });

    test('should include task and team summaries', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'initiative');
      const formatted = service.formatMatrixForDiscord(matrix) as any;

      const fields = formatted.fields;
      expect(fields.some((f: any) => f.name === 'Tasks')).toBe(true);
      expect(fields.some((f: any) => f.name === 'Team')).toBe(true);
      expect(fields.some((f: any) => f.name === 'Assignments')).toBe(true);
    });

    test('should indicate issues when present', async () => {
      const customTasks: RACITask[] = [
        {
          id: 'task-1',
          name: 'Task',
          description: 'Description',
          category: 'development',
          priority: 'high',
        },
      ];

      const customTeam: TeamMember[] = [
        { id: 'stakeholder-1', name: 'Stakeholder', role: 'stakeholder', department: 'External' },
      ];

      const matrix = await service.generateRACIMatrix('Product', 'initiative', {
        customTasks,
        customTeam,
      });

      const formatted = service.formatMatrixForDiscord(matrix) as any;
      const issuesField = formatted.fields.find((f: any) => f.name === 'Issues');

      expect(issuesField.value).toContain('⚠️');
    });
  });

  describe('template types', () => {
    test('should generate tasks for product_launch template', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'launch', {
        template: 'product_launch',
      });

      expect(matrix.tasks.some((t) => t.name.includes('launch') || t.category === 'deployment')).toBe(
        true
      );
    });

    test('should generate tasks for feature_release template', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'feature', {
        template: 'feature_release',
      });

      expect(matrix.tasks.some((t) => t.category === 'development')).toBe(true);
    });

    test('should generate tasks for security_release template', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'security-fix', {
        template: 'security_release',
      });

      expect(matrix.tasks.some((t) => t.category === 'security')).toBe(true);
    });

    test('should generate tasks for marketing_campaign template', async () => {
      const matrix = await service.generateRACIMatrix('Product', 'campaign', {
        template: 'marketing_campaign',
      });

      expect(matrix.tasks.some((t) => t.category === 'marketing')).toBe(true);
    });
  });

  describe('role inference', () => {
    test('should infer engineer role from name', async () => {
      service.setLinearClient(mockLinearClient);

      mockLinearClient.getTeam.mockResolvedValue({
        id: 'team-123',
        name: 'Team',
        members: {
          nodes: [{ id: 'user-1', name: 'john-engineer' }],
        },
      });

      const matrix = await service.generateRACIMatrix('Product', 'initiative');

      expect(matrix.teamMembers[0].role).toBe('engineer');
    });

    test('should infer product_manager role from name', async () => {
      service.setLinearClient(mockLinearClient);

      mockLinearClient.getTeam.mockResolvedValue({
        id: 'team-123',
        name: 'Team',
        members: {
          nodes: [{ id: 'user-1', name: 'jane-pm' }],
        },
      });

      const matrix = await service.generateRACIMatrix('Product', 'initiative');

      expect(matrix.teamMembers[0].role).toBe('product_manager');
    });
  });
});
