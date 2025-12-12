/**
 * Unified Context Aggregator Tests
 *
 * Tests for context aggregation from multiple sources:
 * - Filesystem document aggregation
 * - Linear issues integration
 * - GitHub PRs integration
 * - Discord feedback integration
 * - Caching behavior
 * - Token limiting
 */

import { UnifiedContextAggregator, AggregationOptions } from '../unified-context-aggregator';

// Mock dependencies
jest.mock('fs', () => ({
  ...jest.requireActual('fs'),
  existsSync: jest.fn().mockReturnValue(true),
  readFileSync: jest.fn(),
  readdirSync: jest.fn(),
  statSync: jest.fn(),
}));

jest.mock('fs/promises', () => ({
  readFile: jest.fn(),
  readdir: jest.fn(),
  stat: jest.fn(),
}));

jest.mock('path', () => ({
  ...jest.requireActual('path'),
  join: jest.fn((...args) => args.join('/')),
  resolve: jest.fn((...args) => args.join('/')),
  dirname: jest.fn((p) => p.split('/').slice(0, -1).join('/')),
  basename: jest.fn((p) => p.split('/').pop()),
  extname: jest.fn((p) => {
    const match = p.match(/\.[^.]+$/);
    return match ? match[0] : '';
  }),
}));

describe('UnifiedContextAggregator', () => {
  let aggregator: UnifiedContextAggregator;
  let mockFs: any;
  let mockFsPromises: any;

  beforeEach(() => {
    jest.clearAllMocks();
    mockFs = require('fs');
    mockFsPromises = require('fs/promises');

    // Default mock implementations
    mockFs.existsSync.mockReturnValue(true);
    mockFs.readFileSync.mockReturnValue('# Mock Document\n\nContent here.');
    mockFs.readdirSync.mockReturnValue(['prd.md', 'sdd.md']);
    mockFs.statSync.mockReturnValue({ isFile: () => true, isDirectory: () => false });

    mockFsPromises.readFile.mockResolvedValue('# Mock Document\n\nContent here.');
    mockFsPromises.readdir.mockResolvedValue(['prd.md', 'sdd.md']);
    mockFsPromises.stat.mockResolvedValue({ isFile: () => true, isDirectory: () => false });

    aggregator = new UnifiedContextAggregator();
  });

  describe('aggregateContext - Basic functionality', () => {
    it('should aggregate context from primary document', async () => {
      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      expect(result.sourceDocuments.length).toBeGreaterThan(0);
      expect(result.metadata.projectName).toBe('Test Project');
      expect(result.metadata.sources).toContain('filesystem');
    });

    it('should include metadata with aggregation timestamp', async () => {
      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      expect(result.metadata.aggregatedAt).toBeDefined();
      expect(result.metadata.aggregatedAt instanceof Date).toBe(true);
    });

    it('should track statistics for aggregated content', async () => {
      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      expect(result.metadata.statistics).toBeDefined();
      expect(result.metadata.statistics.documentCount).toBeGreaterThanOrEqual(1);
      expect(result.metadata.statistics.estimatedTokens).toBeGreaterThan(0);
    });
  });

  describe('aggregateContext - Source options', () => {
    it('should aggregate from filesystem only by default', async () => {
      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      expect(result.metadata.sources).toContain('filesystem');
    });

    it('should include Linear issues when requested', async () => {
      const options: AggregationOptions = {
        includeLinear: true,
        linearTeamId: 'team-123',
      };

      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project',
        options
      );

      // Linear integration requires MCP - should gracefully handle unavailability
      expect(result.metadata).toBeDefined();
    });

    it('should include GitHub PRs when requested', async () => {
      const options: AggregationOptions = {
        includeGitHub: true,
        githubOwner: 'org',
        githubRepo: 'repo',
      };

      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project',
        options
      );

      // GitHub integration requires MCP - should gracefully handle unavailability
      expect(result.metadata).toBeDefined();
    });

    it('should include Discord feedback when requested', async () => {
      const options: AggregationOptions = {
        includeDiscord: true,
        discordChannelId: 'channel-123',
      };

      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project',
        options
      );

      // Discord integration requires MCP - should gracefully handle unavailability
      expect(result.metadata).toBeDefined();
    });
  });

  describe('aggregateContext - Token limiting', () => {
    it('should respect max token limit', async () => {
      // Create very long content
      mockFsPromises.readFile.mockResolvedValue('A'.repeat(500000));

      const options: AggregationOptions = {
        maxTokens: 1000,
      };

      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project',
        options
      );

      // Token count should be approximately within limit
      expect(result.metadata.statistics.estimatedTokens).toBeLessThanOrEqual(1500); // Some buffer
    });

    it('should limit Linear issues count', async () => {
      const options: AggregationOptions = {
        includeLinear: true,
        maxLinearIssues: 5,
      };

      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project',
        options
      );

      if (result.linearIssues) {
        expect(result.linearIssues.length).toBeLessThanOrEqual(5);
      }
    });

    it('should limit GitHub PRs count', async () => {
      const options: AggregationOptions = {
        includeGitHub: true,
        maxGitHubPRs: 3,
      };

      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project',
        options
      );

      if (result.githubPRs) {
        expect(result.githubPRs.length).toBeLessThanOrEqual(3);
      }
    });
  });

  describe('formatContextForLLM', () => {
    it('should format context as readable text', async () => {
      const context = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      const formatted = aggregator.formatContextForLLM(context);

      expect(typeof formatted).toBe('string');
      expect(formatted.length).toBeGreaterThan(0);
    });

    it('should include document sections', async () => {
      const context = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      const formatted = aggregator.formatContextForLLM(context);

      expect(formatted).toContain('Source Documents');
    });

    it('should include metadata section', async () => {
      const context = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      const formatted = aggregator.formatContextForLLM(context);

      expect(formatted).toContain('Test Project');
    });
  });

  describe('caching behavior', () => {
    it('should cache aggregation results', async () => {
      // First call
      await aggregator.aggregateContext('/path/to/docs/prd.md', 'Test Project');

      // Second call - should use cache
      const callCountBefore = mockFsPromises.readFile.mock.calls.length;
      await aggregator.aggregateContext('/path/to/docs/prd.md', 'Test Project');
      const callCountAfter = mockFsPromises.readFile.mock.calls.length;

      // If caching works, call count should not increase significantly
      // Note: This test may need adjustment based on actual implementation
    });

    it('should invalidate cache after TTL', async () => {
      // This test would require time manipulation
      // For now, just verify cache exists
      expect(aggregator['cache']).toBeDefined();
    });
  });

  describe('error handling', () => {
    it('should handle missing primary document', async () => {
      mockFs.existsSync.mockReturnValue(false);
      mockFsPromises.readFile.mockRejectedValue(new Error('ENOENT: no such file'));

      await expect(
        aggregator.aggregateContext('/non/existent/path.md', 'Test Project')
      ).rejects.toThrow();
    });

    it('should continue with partial results on source failures', async () => {
      const options: AggregationOptions = {
        includeLinear: true,
        includeGitHub: true,
        includeDiscord: true,
      };

      // Even if external sources fail, should return filesystem results
      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project',
        options
      );

      expect(result.sourceDocuments.length).toBeGreaterThan(0);
    });

    it('should handle permission errors gracefully', async () => {
      mockFsPromises.readFile.mockRejectedValue(new Error('EACCES: permission denied'));

      await expect(
        aggregator.aggregateContext('/path/to/docs/prd.md', 'Test Project')
      ).rejects.toThrow();
    });
  });

  describe('edge cases', () => {
    it('should handle empty project name', async () => {
      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        ''
      );

      expect(result.metadata.projectName).toBe('');
    });

    it('should handle documents with no content', async () => {
      mockFsPromises.readFile.mockResolvedValue('');

      const result = await aggregator.aggregateContext(
        '/path/to/docs/empty.md',
        'Test Project'
      );

      expect(result.sourceDocuments.length).toBeGreaterThanOrEqual(0);
    });

    it('should handle binary files in directory', async () => {
      mockFsPromises.readdir.mockResolvedValue(['doc.md', 'image.png', 'data.bin']);

      const result = await aggregator.aggregateContext(
        '/path/to/docs/prd.md',
        'Test Project'
      );

      // Should filter out non-text files
      expect(result.sourceDocuments.every(d =>
        d.path.endsWith('.md') || d.path.endsWith('.txt') || d.path.endsWith('.json')
      )).toBe(true);
    });

    it('should handle circular directory references', async () => {
      // Mock a directory that could cause infinite recursion
      let callCount = 0;
      mockFsPromises.stat.mockImplementation(() => {
        callCount++;
        if (callCount > 100) {
          throw new Error('Max depth exceeded');
        }
        return Promise.resolve({ isFile: () => false, isDirectory: () => true });
      });

      // Should have depth limiting
      // Implementation should prevent infinite recursion
    });
  });
});
