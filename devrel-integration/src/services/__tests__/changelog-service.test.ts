/**
 * Changelog Service Tests
 *
 * Sprint 5 - Task 5.2: Changelog Generation Service
 *
 * Tests for ChangelogService functionality including:
 * - Adding changelog entries
 * - Creating versions from unreleased changes
 * - Processing Linear issues
 * - Markdown formatting
 * - Version queries
 */

import {
  ChangelogService,
  Changelog,
  ChangelogEntry,
  ChangelogVersion,
  AddChangeParams,
  LinearIssue,
  getChangelog,
  addChange,
  createVersion,
  formatChangelogAsMarkdown,
} from '../changelog-service';

// Mock logger
jest.mock('../../utils/logger', () => ({
  logger: {
    info: jest.fn(),
    debug: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

// Mock tenant context
jest.mock('../tenant-context', () => {
  const mockTenant = {
    tenantId: 'thj',
    name: 'The Honey Jar',
    config: {
      enabledFeatures: ['transformations', 'knowledge-base'],
      maxTransformationsPerDay: 1000,
    },
    metadata: {
      createdAt: new Date(),
      updatedAt: new Date(),
      status: 'active',
    },
  };

  return {
    getCurrentTenant: jest.fn().mockReturnValue(mockTenant),
  };
});

// Mock tiered cache
jest.mock('../tiered-cache', () => {
  const mockCache = {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue(undefined),
    getOrFetch: jest.fn().mockImplementation(
      async (_t: string, _k: string, fn: () => Promise<unknown>) => fn()
    ),
    invalidate: jest.fn().mockResolvedValue(true),
  };

  return {
    tieredCache: mockCache,
  };
});

describe('ChangelogService', () => {
  let service: ChangelogService;

  beforeEach(() => {
    service = new ChangelogService();
    service.clearAll();
  });

  describe('getChangelog', () => {
    it('should return empty changelog for new product', async () => {
      const changelog = await service.getChangelog('new-product');

      expect(changelog.product).toBe('new-product');
      expect(changelog.versions).toHaveLength(0);
      expect(changelog.unreleased.added).toHaveLength(0);
      expect(changelog.unreleased.changed).toHaveLength(0);
      expect(changelog.unreleased.fixed).toHaveLength(0);
      expect(changelog.unreleased.removed).toHaveLength(0);
      expect(changelog.unreleased.security).toHaveLength(0);
      expect(changelog.unreleased.deprecated).toHaveLength(0);
    });

    it('should return same changelog for same product', async () => {
      await service.addChange({
        product: 'test-product',
        type: 'added',
        description: 'Test feature',
      });

      const changelog1 = await service.getChangelog('test-product');
      const changelog2 = await service.getChangelog('test-product');

      expect(changelog1.unreleased.added).toHaveLength(1);
      expect(changelog2.unreleased.added).toHaveLength(1);
    });
  });

  describe('addChange', () => {
    it('should add entry to unreleased section', async () => {
      await service.addChange({
        product: 'test',
        type: 'added',
        description: 'New feature',
      });

      const changelog = await service.getChangelog('test');
      expect(changelog.unreleased.added).toHaveLength(1);
      expect(changelog.unreleased.added[0].description).toBe('New feature');
    });

    it('should categorize changes by type', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'Added' });
      await service.addChange({ product: 'test', type: 'changed', description: 'Changed' });
      await service.addChange({ product: 'test', type: 'fixed', description: 'Fixed' });
      await service.addChange({ product: 'test', type: 'removed', description: 'Removed' });
      await service.addChange({ product: 'test', type: 'security', description: 'Security' });
      await service.addChange({ product: 'test', type: 'deprecated', description: 'Deprecated' });

      const changelog = await service.getChangelog('test');
      expect(changelog.unreleased.added).toHaveLength(1);
      expect(changelog.unreleased.changed).toHaveLength(1);
      expect(changelog.unreleased.fixed).toHaveLength(1);
      expect(changelog.unreleased.removed).toHaveLength(1);
      expect(changelog.unreleased.security).toHaveLength(1);
      expect(changelog.unreleased.deprecated).toHaveLength(1);
    });

    it('should store issue metadata', async () => {
      await service.addChange({
        product: 'test',
        type: 'fixed',
        description: 'Fix bug',
        issueId: 'LAB-123',
        issueUrl: 'https://linear.app/thj/issue/LAB-123',
        labels: ['bug', 'critical'],
        author: 'Dev Name',
      });

      const changelog = await service.getChangelog('test');
      const entry = changelog.unreleased.fixed[0];

      expect(entry.issueId).toBe('LAB-123');
      expect(entry.issueUrl).toBe('https://linear.app/thj/issue/LAB-123');
      expect(entry.labels).toEqual(['bug', 'critical']);
      expect(entry.author).toBe('Dev Name');
    });

    it('should set completedAt timestamp', async () => {
      const before = new Date();

      await service.addChange({
        product: 'test',
        type: 'added',
        description: 'Test',
      });

      const after = new Date();
      const changelog = await service.getChangelog('test');
      const entry = changelog.unreleased.added[0];

      expect(entry.completedAt!.getTime()).toBeGreaterThanOrEqual(before.getTime());
      expect(entry.completedAt!.getTime()).toBeLessThanOrEqual(after.getTime());
    });

    it('should update lastUpdated timestamp', async () => {
      const changelog1 = await service.getChangelog('test');
      const firstUpdate = changelog1.lastUpdated;

      await new Promise(resolve => setTimeout(resolve, 10));

      await service.addChange({
        product: 'test',
        type: 'added',
        description: 'Test',
      });

      const changelog2 = await service.getChangelog('test');
      expect(changelog2.lastUpdated.getTime()).toBeGreaterThan(firstUpdate.getTime());
    });
  });

  describe('createVersion', () => {
    it('should create version from unreleased changes', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'Feature 1' });
      await service.addChange({ product: 'test', type: 'fixed', description: 'Bug fix 1' });

      const version = await service.createVersion({
        product: 'test',
        version: '1.0.0',
      });

      expect(version.version).toBe('1.0.0');
      expect(version.changes.added).toHaveLength(1);
      expect(version.changes.fixed).toHaveLength(1);
    });

    it('should clear unreleased after version creation', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'Feature' });

      await service.createVersion({ product: 'test', version: '1.0.0' });

      const changelog = await service.getChangelog('test');
      expect(changelog.unreleased.added).toHaveLength(0);
    });

    it('should add version to versions list', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'F1' });
      await service.createVersion({ product: 'test', version: '1.0.0' });

      await service.addChange({ product: 'test', type: 'added', description: 'F2' });
      await service.createVersion({ product: 'test', version: '1.1.0' });

      const changelog = await service.getChangelog('test');
      expect(changelog.versions).toHaveLength(2);
    });

    it('should order versions newest first', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'F1' });
      await service.createVersion({ product: 'test', version: '1.0.0' });

      await service.addChange({ product: 'test', type: 'added', description: 'F2' });
      await service.createVersion({ product: 'test', version: '2.0.0' });

      const changelog = await service.getChangelog('test');
      expect(changelog.versions[0].version).toBe('2.0.0');
      expect(changelog.versions[1].version).toBe('1.0.0');
    });

    it('should include summary in version', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'Feature' });

      const version = await service.createVersion({
        product: 'test',
        version: '1.0.0',
        summary: 'Major release with new features.',
      });

      expect(version.summary).toBe('Major release with new features.');
    });

    it('should set version date', async () => {
      const before = new Date();

      await service.addChange({ product: 'test', type: 'added', description: 'Feature' });
      const version = await service.createVersion({ product: 'test', version: '1.0.0' });

      const after = new Date();
      expect(version.date.getTime()).toBeGreaterThanOrEqual(before.getTime());
      expect(version.date.getTime()).toBeLessThanOrEqual(after.getTime());
    });
  });

  describe('processLinearIssues', () => {
    it('should convert Linear issues to changelog entries', async () => {
      const issues: LinearIssue[] = [
        {
          id: '1',
          identifier: 'LAB-1',
          title: 'Add new feature',
          url: 'https://linear.app/thj/issue/LAB-1',
          labels: [{ name: 'type:feature' }],
          state: { name: 'Done', type: 'completed' },
        },
        {
          id: '2',
          identifier: 'LAB-2',
          title: 'Fix bug',
          url: 'https://linear.app/thj/issue/LAB-2',
          labels: [{ name: 'bug' }],
          state: { name: 'Done', type: 'completed' },
        },
      ];

      const count = await service.processLinearIssues('test', issues);

      expect(count).toBe(2);

      const changelog = await service.getChangelog('test');
      expect(changelog.unreleased.added).toHaveLength(1);
      expect(changelog.unreleased.fixed).toHaveLength(1);
    });

    it('should map labels to correct change types', async () => {
      const issues: LinearIssue[] = [
        {
          id: '1',
          identifier: 'LAB-1',
          title: 'Feature',
          url: 'url',
          labels: [{ name: 'type:feature' }],
          state: { name: 'Done', type: 'completed' },
        },
        {
          id: '2',
          identifier: 'LAB-2',
          title: 'Enhancement',
          url: 'url',
          labels: [{ name: 'enhancement' }],
          state: { name: 'Done', type: 'completed' },
        },
        {
          id: '3',
          identifier: 'LAB-3',
          title: 'Security fix',
          url: 'url',
          labels: [{ name: 'security' }],
          state: { name: 'Done', type: 'completed' },
        },
      ];

      await service.processLinearIssues('test', issues);
      const changelog = await service.getChangelog('test');

      expect(changelog.unreleased.added).toHaveLength(1);
      expect(changelog.unreleased.changed).toHaveLength(1);
      expect(changelog.unreleased.security).toHaveLength(1);
    });

    it('should include assignee as author', async () => {
      const issues: LinearIssue[] = [
        {
          id: '1',
          identifier: 'LAB-1',
          title: 'Feature',
          url: 'url',
          labels: [{ name: 'feature' }],
          state: { name: 'Done', type: 'completed' },
          assignee: { name: 'Test Dev', email: 'dev@test.com' },
        },
      ];

      await service.processLinearIssues('test', issues);
      const changelog = await service.getChangelog('test');

      expect(changelog.unreleased.added[0].author).toBe('Test Dev');
    });
  });

  describe('getVersion', () => {
    it('should return version by version string', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'F1' });
      await service.createVersion({ product: 'test', version: '1.0.0' });

      await service.addChange({ product: 'test', type: 'added', description: 'F2' });
      await service.createVersion({ product: 'test', version: '1.1.0' });

      const version = await service.getVersion('test', '1.0.0');

      expect(version).not.toBeNull();
      expect(version!.version).toBe('1.0.0');
    });

    it('should return null for non-existent version', async () => {
      const version = await service.getVersion('test', '999.0.0');
      expect(version).toBeNull();
    });
  });

  describe('getChangesBetweenVersions', () => {
    beforeEach(async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'F1' });
      await service.createVersion({ product: 'test', version: '1.0.0' });

      await service.addChange({ product: 'test', type: 'added', description: 'F2' });
      await service.createVersion({ product: 'test', version: '1.1.0' });

      await service.addChange({ product: 'test', type: 'added', description: 'F3' });
      await service.createVersion({ product: 'test', version: '2.0.0' });
    });

    it('should return versions between two versions', async () => {
      const versions = await service.getChangesBetweenVersions('test', '1.0.0', '2.0.0');

      expect(versions.length).toBeGreaterThanOrEqual(2);
    });

    it('should return empty array for non-existent versions', async () => {
      const versions = await service.getChangesBetweenVersions('test', '0.0.1', '0.0.2');
      expect(versions).toEqual([]);
    });
  });

  describe('formatAsMarkdown', () => {
    it('should format changelog as markdown', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'New feature' });
      await service.addChange({ product: 'test', type: 'fixed', description: 'Bug fix' });

      const markdown = await service.formatAsMarkdown('test');

      expect(markdown).toContain('# Changelog - test');
      expect(markdown).toContain('## [Unreleased]');
      expect(markdown).toContain('### Added');
      expect(markdown).toContain('- New feature');
      expect(markdown).toContain('### Fixed');
      expect(markdown).toContain('- Bug fix');
    });

    it('should include version sections', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'Feature' });
      await service.createVersion({ product: 'test', version: '1.0.0' });

      const markdown = await service.formatAsMarkdown('test');

      expect(markdown).toContain('## [1.0.0]');
    });

    it('should include issue links', async () => {
      await service.addChange({
        product: 'test',
        type: 'added',
        description: 'Feature',
        issueId: 'LAB-123',
        issueUrl: 'https://linear.app/thj/issue/LAB-123',
      });

      const markdown = await service.formatAsMarkdown('test');

      expect(markdown).toContain('[LAB-123](https://linear.app/thj/issue/LAB-123)');
    });

    it('should include Keep a Changelog format header', async () => {
      const markdown = await service.formatAsMarkdown('test');

      expect(markdown).toContain('Keep a Changelog');
      expect(markdown).toContain('Semantic Versioning');
    });
  });

  describe('getRecentChanges', () => {
    it('should return recent changes across types', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'A1' });
      await service.addChange({ product: 'test', type: 'fixed', description: 'F1' });
      await service.addChange({ product: 'test', type: 'changed', description: 'C1' });

      const recent = await service.getRecentChanges('test', 10);

      expect(recent).toHaveLength(3);
    });

    it('should respect limit parameter', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'A1' });
      await service.addChange({ product: 'test', type: 'added', description: 'A2' });
      await service.addChange({ product: 'test', type: 'added', description: 'A3' });

      const recent = await service.getRecentChanges('test', 2);

      expect(recent).toHaveLength(2);
    });

    it('should include changes from versions', async () => {
      await service.addChange({ product: 'test', type: 'added', description: 'V1' });
      await service.createVersion({ product: 'test', version: '1.0.0' });

      await service.addChange({ product: 'test', type: 'added', description: 'Unreleased' });

      const recent = await service.getRecentChanges('test', 10);

      expect(recent.map(r => r.description)).toContain('V1');
      expect(recent.map(r => r.description)).toContain('Unreleased');
    });
  });

  describe('singleton pattern', () => {
    it('should return same instance from getInstance', () => {
      const instance1 = ChangelogService.getInstance();
      const instance2 = ChangelogService.getInstance();

      expect(instance1).toBe(instance2);
    });
  });
});

describe('Convenience functions', () => {
  let service: ChangelogService;

  beforeEach(() => {
    service = ChangelogService.getInstance();
    service.clearAll();
  });

  describe('getChangelog function', () => {
    it('should get changelog via convenience function', async () => {
      await addChange({ product: 'test', type: 'added', description: 'Test' });
      const changelog = await getChangelog('test');

      expect(changelog.product).toBe('test');
      expect(changelog.unreleased.added).toHaveLength(1);
    });
  });

  describe('addChange function', () => {
    it('should add change via convenience function', async () => {
      await addChange({ product: 'test', type: 'fixed', description: 'Fix' });

      const changelog = await getChangelog('test');
      expect(changelog.unreleased.fixed).toHaveLength(1);
    });
  });

  describe('createVersion function', () => {
    it('should create version via convenience function', async () => {
      await addChange({ product: 'test', type: 'added', description: 'Feature' });
      const version = await createVersion({ product: 'test', version: '1.0.0' });

      expect(version.version).toBe('1.0.0');
    });
  });

  describe('formatChangelogAsMarkdown function', () => {
    it('should format via convenience function', async () => {
      await addChange({ product: 'test', type: 'added', description: 'Test' });
      const markdown = await formatChangelogAsMarkdown('test');

      expect(markdown).toContain('# Changelog - test');
    });
  });
});

describe('Label to change type mapping', () => {
  let service: ChangelogService;

  beforeEach(() => {
    service = new ChangelogService();
    service.clearAll();
  });

  const testCases: Array<{ labels: string[]; expectedType: string }> = [
    { labels: ['type:feature'], expectedType: 'added' },
    { labels: ['feature'], expectedType: 'added' },
    { labels: ['type:enhancement'], expectedType: 'changed' },
    { labels: ['enhancement'], expectedType: 'changed' },
    { labels: ['type:bugfix'], expectedType: 'fixed' },
    { labels: ['bug'], expectedType: 'fixed' },
    { labels: ['type:security'], expectedType: 'security' },
    { labels: ['security'], expectedType: 'security' },
    { labels: ['deprecation'], expectedType: 'deprecated' },
    { labels: ['refactor'], expectedType: 'changed' },
    { labels: ['unknown-label'], expectedType: 'changed' }, // Default
  ];

  for (const { labels, expectedType } of testCases) {
    it(`should map labels [${labels.join(', ')}] to ${expectedType}`, async () => {
      const issues: LinearIssue[] = [
        {
          id: '1',
          identifier: 'LAB-1',
          title: 'Test',
          url: 'url',
          labels: labels.map(name => ({ name })),
          state: { name: 'Done', type: 'completed' },
        },
      ];

      await service.processLinearIssues('test', issues);
      const changelog = await service.getChangelog('test');

      const allChanges = [
        ...changelog.unreleased.added.map(e => ({ ...e, type: 'added' })),
        ...changelog.unreleased.changed.map(e => ({ ...e, type: 'changed' })),
        ...changelog.unreleased.fixed.map(e => ({ ...e, type: 'fixed' })),
        ...changelog.unreleased.removed.map(e => ({ ...e, type: 'removed' })),
        ...changelog.unreleased.security.map(e => ({ ...e, type: 'security' })),
        ...changelog.unreleased.deprecated.map(e => ({ ...e, type: 'deprecated' })),
      ];

      expect(allChanges).toHaveLength(1);
      expect(allChanges[0].type).toBe(expectedType);
    });
  }
});

describe('Edge cases', () => {
  let service: ChangelogService;

  beforeEach(() => {
    service = new ChangelogService();
    service.clearAll();
  });

  it('should handle special characters in descriptions', async () => {
    await service.addChange({
      product: 'test',
      type: 'added',
      description: 'Feature with "quotes" & <tags>',
    });

    const changelog = await service.getChangelog('test');
    expect(changelog.unreleased.added[0].description).toBe('Feature with "quotes" & <tags>');
  });

  it('should handle unicode in descriptions', async () => {
    await service.addChange({
      product: 'test',
      type: 'added',
      description: '新功能 🚀 émoji',
    });

    const changelog = await service.getChangelog('test');
    expect(changelog.unreleased.added[0].description).toBe('新功能 🚀 émoji');
  });

  it('should handle empty product name', async () => {
    await service.addChange({
      product: '',
      type: 'added',
      description: 'Test',
    });

    const changelog = await service.getChangelog('');
    expect(changelog.unreleased.added).toHaveLength(1);
  });

  it('should handle many changes efficiently', async () => {
    for (let i = 0; i < 100; i++) {
      await service.addChange({
        product: 'test',
        type: 'added',
        description: `Feature ${i}`,
      });
    }

    const changelog = await service.getChangelog('test');
    expect(changelog.unreleased.added).toHaveLength(100);
  });
});
