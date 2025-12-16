/**
 * Discussion Archive Service Tests
 *
 * Sprint 5 - Task 5.3: Discussion Archive Service
 *
 * Tests for DiscussionArchiveService functionality including:
 * - Archiving discussions
 * - Search across archived discussions
 * - Participant and channel queries
 * - Resolution and Linear issue linking
 * - Markdown formatting
 */

import {
  DiscussionArchiveService,
  ArchivedDiscussion,
  ArchiveDiscussionParams,
  DiscussionMessage,
  archiveDiscussion,
  searchDiscussions,
  getDiscussion,
  getRecentDiscussions,
} from '../discussion-archive-service';

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

// Helper to create test messages
function createTestMessages(count: number): DiscussionMessage[] {
  const messages: DiscussionMessage[] = [];
  const baseTime = new Date('2024-01-15T10:00:00Z');

  for (let i = 0; i < count; i++) {
    messages.push({
      messageId: `msg-${i}`,
      content: `Test message ${i + 1} content`,
      author: `User${(i % 3) + 1}`,
      authorId: `user-${(i % 3) + 1}`,
      timestamp: new Date(baseTime.getTime() + i * 60000),
      isThreadStarter: i === 0,
    });
  }

  return messages;
}

describe('DiscussionArchiveService', () => {
  let service: DiscussionArchiveService;

  beforeEach(() => {
    service = new DiscussionArchiveService();
    service.clearAll();
  });

  describe('archiveDiscussion', () => {
    it('should archive discussion with all fields', async () => {
      const params: ArchiveDiscussionParams = {
        channelId: 'channel-123',
        channelName: 'general',
        threadId: 'thread-456',
        topic: 'Architecture Discussion',
        messages: createTestMessages(5),
        archivedBy: 'ModeratorUser',
        resolution: 'We decided to use microservices.',
        tags: ['architecture', 'decision'],
        discordUrl: 'https://discord.com/channels/123/456/789',
      };

      const discussion = await service.archiveDiscussion(params);

      expect(discussion.id).toBeDefined();
      expect(discussion.topic).toBe('Architecture Discussion');
      expect(discussion.channelId).toBe('channel-123');
      expect(discussion.channelName).toBe('general');
      expect(discussion.threadId).toBe('thread-456');
      expect(discussion.messages).toHaveLength(5);
      expect(discussion.archivedBy).toBe('ModeratorUser');
      expect(discussion.resolution).toBe('We decided to use microservices.');
      expect(discussion.tags).toEqual(['architecture', 'decision']);
      expect(discussion.discordUrl).toBe('https://discord.com/channels/123/456/789');
    });

    it('should extract unique participants', async () => {
      const messages: DiscussionMessage[] = [
        { messageId: '1', content: 'Hi', author: 'Alice', authorId: 'a1', timestamp: new Date() },
        { messageId: '2', content: 'Hello', author: 'Bob', authorId: 'b1', timestamp: new Date() },
        { messageId: '3', content: 'Hey', author: 'Alice', authorId: 'a1', timestamp: new Date() },
        { messageId: '4', content: 'Hi all', author: 'Charlie', authorId: 'c1', timestamp: new Date() },
        { messageId: '5', content: 'Test', author: 'Bob', authorId: 'b1', timestamp: new Date() },
      ];

      const discussion = await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages,
      });

      expect(discussion.participants).toHaveLength(3);
      expect(discussion.participants).toContain('Alice');
      expect(discussion.participants).toContain('Bob');
      expect(discussion.participants).toContain('Charlie');
    });

    it('should sort messages by timestamp', async () => {
      const messages: DiscussionMessage[] = [
        { messageId: '3', content: 'Third', author: 'A', authorId: 'a', timestamp: new Date('2024-01-15T12:00:00Z') },
        { messageId: '1', content: 'First', author: 'B', authorId: 'b', timestamp: new Date('2024-01-15T10:00:00Z') },
        { messageId: '2', content: 'Second', author: 'C', authorId: 'c', timestamp: new Date('2024-01-15T11:00:00Z') },
      ];

      const discussion = await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages,
      });

      expect(discussion.messages[0].content).toBe('First');
      expect(discussion.messages[1].content).toBe('Second');
      expect(discussion.messages[2].content).toBe('Third');
    });

    it('should set startedAt from earliest message', async () => {
      const messages: DiscussionMessage[] = [
        { messageId: '1', content: 'Late', author: 'A', authorId: 'a', timestamp: new Date('2024-01-15T12:00:00Z') },
        { messageId: '2', content: 'Early', author: 'B', authorId: 'b', timestamp: new Date('2024-01-15T10:00:00Z') },
      ];

      const discussion = await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages,
      });

      expect(discussion.startedAt.getTime()).toBe(new Date('2024-01-15T10:00:00Z').getTime());
    });

    it('should generate unique archive IDs', async () => {
      const params: ArchiveDiscussionParams = {
        channelId: 'ch1',
        topic: 'Same Topic',
        messages: createTestMessages(2),
      };

      const discussion1 = await service.archiveDiscussion(params);
      const discussion2 = await service.archiveDiscussion(params);

      expect(discussion1.id).not.toBe(discussion2.id);
    });

    it('should set archivedAt timestamp', async () => {
      const before = new Date();

      const discussion = await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages: createTestMessages(1),
      });

      const after = new Date();

      expect(discussion.archivedAt.getTime()).toBeGreaterThanOrEqual(before.getTime());
      expect(discussion.archivedAt.getTime()).toBeLessThanOrEqual(after.getTime());
    });
  });

  describe('getDiscussion', () => {
    it('should retrieve archived discussion by ID', async () => {
      const archived = await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test Topic',
        messages: createTestMessages(3),
      });

      const retrieved = await service.getDiscussion(archived.id);

      expect(retrieved).not.toBeNull();
      expect(retrieved!.id).toBe(archived.id);
      expect(retrieved!.topic).toBe('Test Topic');
    });

    it('should return null for non-existent ID', async () => {
      const result = await service.getDiscussion('non-existent-id');
      expect(result).toBeNull();
    });
  });

  describe('searchDiscussions', () => {
    beforeEach(async () => {
      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Database Architecture Decision',
        messages: [
          { messageId: '1', content: 'Should we use PostgreSQL or MongoDB?', author: 'Dev1', authorId: 'd1', timestamp: new Date() },
          { messageId: '2', content: 'PostgreSQL for ACID compliance', author: 'Dev2', authorId: 'd2', timestamp: new Date() },
        ],
        tags: ['database', 'architecture'],
        resolution: 'Use PostgreSQL for all persistent data.',
      });

      await service.archiveDiscussion({
        channelId: 'ch2',
        topic: 'Frontend Framework Selection',
        messages: [
          { messageId: '3', content: 'React vs Vue debate', author: 'Dev1', authorId: 'd1', timestamp: new Date() },
          { messageId: '4', content: 'I prefer React for ecosystem', author: 'Dev3', authorId: 'd3', timestamp: new Date() },
        ],
        tags: ['frontend', 'framework'],
        resolution: 'Use React with TypeScript.',
      });

      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'API Design Principles',
        messages: [
          { messageId: '5', content: 'REST vs GraphQL', author: 'Dev2', authorId: 'd2', timestamp: new Date() },
          { messageId: '6', content: 'GraphQL for flexibility', author: 'Dev4', authorId: 'd4', timestamp: new Date() },
        ],
        tags: ['api', 'architecture'],
      });
    });

    it('should find discussions by topic', async () => {
      const results = await service.searchDiscussions('Database');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].discussion.topic).toContain('Database');
    });

    it('should find discussions by message content', async () => {
      const results = await service.searchDiscussions('PostgreSQL');

      expect(results.length).toBeGreaterThan(0);
    });

    it('should find discussions by tag', async () => {
      const results = await service.searchDiscussions('architecture');

      expect(results.length).toBe(2); // Database and API discussions
    });

    it('should find discussions by resolution', async () => {
      const results = await service.searchDiscussions('TypeScript');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].discussion.resolution).toContain('TypeScript');
    });

    it('should filter by tags', async () => {
      const results = await service.searchDiscussions('architecture', {
        tags: ['database'],
      });

      expect(results.length).toBe(1);
      expect(results[0].discussion.topic).toContain('Database');
    });

    it('should respect limit parameter', async () => {
      const results = await service.searchDiscussions('architecture', { limit: 1 });
      expect(results.length).toBe(1);
    });

    it('should return empty array for no matches', async () => {
      const results = await service.searchDiscussions('xyznonexistent123');
      expect(results).toEqual([]);
    });

    it('should include excerpts in results', async () => {
      const results = await service.searchDiscussions('PostgreSQL');

      expect(results.length).toBeGreaterThan(0);
      expect(results[0].excerpt).toBeDefined();
      expect(results[0].excerpt.length).toBeGreaterThan(0);
    });

    it('should include matched field in results', async () => {
      const results = await service.searchDiscussions('Database');

      expect(results[0].matchedField).toBeDefined();
    });

    it('should rank topic matches higher than message matches', async () => {
      // 'Database' appears in topic of first discussion
      const results = await service.searchDiscussions('Database');

      expect(results[0].matchedField).toBe('topic');
    });
  });

  describe('getRecentDiscussions', () => {
    it('should return discussions in reverse chronological order', async () => {
      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'First',
        messages: createTestMessages(1),
      });

      await new Promise(resolve => setTimeout(resolve, 10));

      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Second',
        messages: createTestMessages(1),
      });

      const recent = await service.getRecentDiscussions();

      expect(recent[0].topic).toBe('Second');
      expect(recent[1].topic).toBe('First');
    });

    it('should respect limit parameter', async () => {
      for (let i = 0; i < 5; i++) {
        await service.archiveDiscussion({
          channelId: 'ch1',
          topic: `Discussion ${i}`,
          messages: createTestMessages(1),
        });
      }

      const recent = await service.getRecentDiscussions(3);
      expect(recent).toHaveLength(3);
    });

    it('should return empty array when no discussions exist', async () => {
      const recent = await service.getRecentDiscussions();
      expect(recent).toEqual([]);
    });
  });

  describe('getDiscussionsByChannel', () => {
    it('should return discussions for specific channel', async () => {
      await service.archiveDiscussion({
        channelId: 'channel-a',
        topic: 'A1',
        messages: createTestMessages(1),
      });

      await service.archiveDiscussion({
        channelId: 'channel-b',
        topic: 'B1',
        messages: createTestMessages(1),
      });

      await service.archiveDiscussion({
        channelId: 'channel-a',
        topic: 'A2',
        messages: createTestMessages(1),
      });

      const discussions = await service.getDiscussionsByChannel('channel-a');

      expect(discussions).toHaveLength(2);
      expect(discussions.map(d => d.topic)).toContain('A1');
      expect(discussions.map(d => d.topic)).toContain('A2');
      expect(discussions.map(d => d.topic)).not.toContain('B1');
    });

    it('should return empty array for channel with no discussions', async () => {
      const discussions = await service.getDiscussionsByChannel('empty-channel');
      expect(discussions).toEqual([]);
    });
  });

  describe('getDiscussionsByParticipant', () => {
    it('should return discussions where user participated', async () => {
      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'D1',
        messages: [
          { messageId: '1', content: 'Hi', author: 'Alice', authorId: 'a', timestamp: new Date() },
        ],
      });

      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'D2',
        messages: [
          { messageId: '2', content: 'Hello', author: 'Bob', authorId: 'b', timestamp: new Date() },
        ],
      });

      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'D3',
        messages: [
          { messageId: '3', content: 'Hey', author: 'Alice', authorId: 'a', timestamp: new Date() },
          { messageId: '4', content: 'Hi', author: 'Bob', authorId: 'b', timestamp: new Date() },
        ],
      });

      const aliceDiscussions = await service.getDiscussionsByParticipant('Alice');

      expect(aliceDiscussions).toHaveLength(2);
      expect(aliceDiscussions.map(d => d.topic)).toContain('D1');
      expect(aliceDiscussions.map(d => d.topic)).toContain('D3');
    });

    it('should be case-insensitive', async () => {
      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages: [
          { messageId: '1', content: 'Hi', author: 'TestUser', authorId: 'a', timestamp: new Date() },
        ],
      });

      const lower = await service.getDiscussionsByParticipant('testuser');
      const upper = await service.getDiscussionsByParticipant('TESTUSER');

      expect(lower).toHaveLength(1);
      expect(upper).toHaveLength(1);
    });
  });

  describe('linkToLinearIssue', () => {
    it('should link discussion to Linear issue', async () => {
      const discussion = await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Bug Discussion',
        messages: createTestMessages(2),
      });

      const result = await service.linkToLinearIssue(discussion.id, {
        id: 'issue-123',
        identifier: 'LAB-456',
        url: 'https://linear.app/thj/issue/LAB-456',
      });

      expect(result).toBe(true);

      const updated = await service.getDiscussion(discussion.id);
      expect(updated!.linkedIssue).toEqual({
        id: 'issue-123',
        identifier: 'LAB-456',
        url: 'https://linear.app/thj/issue/LAB-456',
      });
    });

    it('should return false for non-existent discussion', async () => {
      const result = await service.linkToLinearIssue('non-existent', {
        id: 'issue-1',
        identifier: 'LAB-1',
        url: 'url',
      });

      expect(result).toBe(false);
    });
  });

  describe('addResolution', () => {
    it('should add resolution to discussion', async () => {
      const discussion = await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Decision Needed',
        messages: createTestMessages(2),
      });

      const result = await service.addResolution(
        discussion.id,
        'We decided to proceed with Option A.'
      );

      expect(result).toBe(true);

      const updated = await service.getDiscussion(discussion.id);
      expect(updated!.resolution).toBe('We decided to proceed with Option A.');
    });

    it('should return false for non-existent discussion', async () => {
      const result = await service.addResolution('non-existent', 'Resolution');
      expect(result).toBe(false);
    });
  });

  describe('getIndex', () => {
    it('should return index with recent discussions', async () => {
      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test 1',
        messages: createTestMessages(3),
      });

      await service.archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test 2',
        messages: createTestMessages(5),
      });

      const index = await service.getIndex();

      expect(index.totalCount).toBe(2);
      expect(index.recent).toHaveLength(2);
      expect(index.recent[0].topic).toBe('Test 2'); // Most recent first
      expect(index.recent[0].messageCount).toBe(5);
    });

    it('should return empty index when no discussions', async () => {
      const index = await service.getIndex();

      expect(index.totalCount).toBe(0);
      expect(index.recent).toHaveLength(0);
    });
  });

  describe('singleton pattern', () => {
    it('should return same instance from getInstance', () => {
      const instance1 = DiscussionArchiveService.getInstance();
      const instance2 = DiscussionArchiveService.getInstance();

      expect(instance1).toBe(instance2);
    });
  });
});

describe('Convenience functions', () => {
  let service: DiscussionArchiveService;

  beforeEach(() => {
    service = DiscussionArchiveService.getInstance();
    service.clearAll();
  });

  describe('archiveDiscussion function', () => {
    it('should archive via convenience function', async () => {
      const discussion = await archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages: createTestMessages(2),
      });

      expect(discussion.id).toBeDefined();
      expect(discussion.topic).toBe('Test');
    });
  });

  describe('searchDiscussions function', () => {
    it('should search via convenience function', async () => {
      await archiveDiscussion({
        channelId: 'ch1',
        topic: 'Searchable Topic',
        messages: createTestMessages(1),
      });

      const results = await searchDiscussions('Searchable');
      expect(results.length).toBeGreaterThan(0);
    });
  });

  describe('getDiscussion function', () => {
    it('should get discussion via convenience function', async () => {
      const archived = await archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages: createTestMessages(1),
      });

      const retrieved = await getDiscussion(archived.id);
      expect(retrieved).not.toBeNull();
      expect(retrieved!.topic).toBe('Test');
    });
  });

  describe('getRecentDiscussions function', () => {
    it('should get recent via convenience function', async () => {
      await archiveDiscussion({
        channelId: 'ch1',
        topic: 'Test',
        messages: createTestMessages(1),
      });

      const recent = await getRecentDiscussions();
      expect(recent).toHaveLength(1);
    });
  });
});

describe('Edge cases', () => {
  let service: DiscussionArchiveService;

  beforeEach(() => {
    service = new DiscussionArchiveService();
    service.clearAll();
  });

  it('should handle empty message array', async () => {
    const discussion = await service.archiveDiscussion({
      channelId: 'ch1',
      topic: 'Empty',
      messages: [],
    });

    expect(discussion.messages).toHaveLength(0);
    expect(discussion.participants).toHaveLength(0);
  });

  it('should handle special characters in topic', async () => {
    const discussion = await service.archiveDiscussion({
      channelId: 'ch1',
      topic: 'Topic with "quotes" & <special> chars!',
      messages: createTestMessages(1),
    });

    expect(discussion.topic).toBe('Topic with "quotes" & <special> chars!');
  });

  it('should handle unicode in messages', async () => {
    const messages: DiscussionMessage[] = [
      {
        messageId: '1',
        content: '你好世界 🌍 émoji test',
        author: 'User',
        authorId: 'u1',
        timestamp: new Date(),
      },
    ];

    const discussion = await service.archiveDiscussion({
      channelId: 'ch1',
      topic: 'Unicode Test',
      messages,
    });

    expect(discussion.messages[0].content).toBe('你好世界 🌍 émoji test');
  });

  it('should handle messages with attachments', async () => {
    const messages: DiscussionMessage[] = [
      {
        messageId: '1',
        content: 'Here is the file',
        author: 'User',
        authorId: 'u1',
        timestamp: new Date(),
        attachments: [
          { name: 'file.pdf', url: 'https://cdn.discord.com/file.pdf', type: 'application/pdf' },
        ],
      },
    ];

    const discussion = await service.archiveDiscussion({
      channelId: 'ch1',
      topic: 'File Sharing',
      messages,
    });

    expect(discussion.messages[0].attachments).toHaveLength(1);
    expect(discussion.messages[0].attachments![0].name).toBe('file.pdf');
  });

  it('should handle messages with reactions', async () => {
    const messages: DiscussionMessage[] = [
      {
        messageId: '1',
        content: 'Great idea!',
        author: 'User',
        authorId: 'u1',
        timestamp: new Date(),
        reactions: [
          { emoji: '👍', count: 5 },
          { emoji: '🎉', count: 2 },
        ],
      },
    ];

    const discussion = await service.archiveDiscussion({
      channelId: 'ch1',
      topic: 'Reactions',
      messages,
    });

    expect(discussion.messages[0].reactions).toHaveLength(2);
  });

  it('should handle very long message content', async () => {
    const longContent = 'A'.repeat(10000);
    const messages: DiscussionMessage[] = [
      {
        messageId: '1',
        content: longContent,
        author: 'User',
        authorId: 'u1',
        timestamp: new Date(),
      },
    ];

    const discussion = await service.archiveDiscussion({
      channelId: 'ch1',
      topic: 'Long Message',
      messages,
    });

    expect(discussion.messages[0].content.length).toBe(10000);
  });
});
