/**
 * Discussion Archive Service
 *
 * Sprint 5 - Task 5.3: Discussion Archive Service
 *
 * Captures and archives important Discord discussions when 📌 reaction is added.
 * Stores full thread context with participants, timestamps, and resolution.
 *
 * Storage: Google Docs in `/Shared/Discussions/{Date}/{Topic}.md`
 *
 * Features:
 * - Capture full thread context
 * - Extract participants and timestamps
 * - Identify resolution/decision
 * - Link to Linear issues if created
 * - Full-text search across archived discussions
 */

import { logger } from '../utils/logger';
import { getCurrentTenant } from './tenant-context';
import { tieredCache } from './tiered-cache';

// =============================================================================
// Types
// =============================================================================

export interface DiscussionMessage {
  /** Discord message ID */
  messageId: string;
  /** Message content */
  content: string;
  /** Author's Discord username */
  author: string;
  /** Author's Discord ID */
  authorId: string;
  /** When the message was sent */
  timestamp: Date;
  /** Whether this message is the thread starter */
  isThreadStarter?: boolean;
  /** Attachments if any */
  attachments?: Array<{
    name: string;
    url: string;
    type: string;
  }>;
  /** Reactions on this message */
  reactions?: Array<{
    emoji: string;
    count: number;
  }>;
}

export interface ArchivedDiscussion {
  /** Unique archive ID */
  id: string;
  /** Discussion topic/title (from thread name or first message) */
  topic: string;
  /** Discord channel where discussion occurred */
  channelId: string;
  /** Discord channel name */
  channelName?: string;
  /** Thread ID if in a thread */
  threadId?: string;
  /** All messages in the discussion */
  messages: DiscussionMessage[];
  /** List of participants (unique authors) */
  participants: string[];
  /** When the discussion started */
  startedAt: Date;
  /** When the discussion was archived */
  archivedAt: Date;
  /** Who triggered the archive (added 📌 reaction) */
  archivedBy?: string;
  /** Resolution or decision reached (if any) */
  resolution?: string;
  /** Linked Linear issue if created from discussion */
  linkedIssue?: {
    id: string;
    identifier: string;
    url: string;
  };
  /** Tags for categorization */
  tags?: string[];
  /** Google Doc URL */
  documentUrl?: string;
  /** Original Discord message URL */
  discordUrl?: string;
}

export interface ArchiveDiscussionParams {
  /** Discord channel ID */
  channelId: string;
  /** Channel name (for display) */
  channelName?: string;
  /** Thread ID (if archiving a thread) */
  threadId?: string;
  /** Discussion topic/title */
  topic: string;
  /** Messages to archive */
  messages: DiscussionMessage[];
  /** Who triggered the archive */
  archivedBy?: string;
  /** Optional resolution text */
  resolution?: string;
  /** Tags for categorization */
  tags?: string[];
  /** Linked Linear issue */
  linkedIssue?: ArchivedDiscussion['linkedIssue'];
  /** Discord message URL */
  discordUrl?: string;
}

export interface DiscussionSearchResult {
  discussion: ArchivedDiscussion;
  /** Match excerpt with context */
  excerpt: string;
  /** Score indicating relevance */
  score: number;
  /** Which field matched */
  matchedField: string;
}

export interface DiscussionIndex {
  /** Total archived discussions */
  totalCount: number;
  /** Recent discussions (last 50) */
  recent: Array<{
    id: string;
    topic: string;
    archivedAt: Date;
    participantCount: number;
    messageCount: number;
  }>;
  /** Last updated */
  lastUpdated: Date;
}

// =============================================================================
// Discussion Formatting
// =============================================================================

/**
 * Format discussion as markdown for storage
 */
function formatDiscussionMarkdown(discussion: ArchivedDiscussion): string {
  const lines: string[] = [];

  // Header
  lines.push(`# Discussion: ${discussion.topic}`);
  lines.push('');
  lines.push(`**Channel:** ${discussion.channelName || discussion.channelId}`);
  lines.push(`**Started:** ${discussion.startedAt.toISOString()}`);
  lines.push(`**Archived:** ${discussion.archivedAt.toISOString()}`);
  if (discussion.archivedBy) {
    lines.push(`**Archived by:** ${discussion.archivedBy}`);
  }
  lines.push(`**Participants:** ${discussion.participants.join(', ')}`);
  if (discussion.tags?.length) {
    lines.push(`**Tags:** ${discussion.tags.join(', ')}`);
  }
  if (discussion.discordUrl) {
    lines.push(`**Original:** [View on Discord](${discussion.discordUrl})`);
  }
  if (discussion.linkedIssue) {
    lines.push(`**Linear Issue:** [${discussion.linkedIssue.identifier}](${discussion.linkedIssue.url})`);
  }
  lines.push('');
  lines.push('---');
  lines.push('');

  // Resolution (if any)
  if (discussion.resolution) {
    lines.push('## Resolution');
    lines.push('');
    lines.push(discussion.resolution);
    lines.push('');
    lines.push('---');
    lines.push('');
  }

  // Messages
  lines.push('## Discussion');
  lines.push('');

  for (const msg of discussion.messages) {
    const timestamp = msg.timestamp.toISOString().replace('T', ' ').substring(0, 19);
    const prefix = msg.isThreadStarter ? '**[Thread Start]** ' : '';
    lines.push(`### ${prefix}${msg.author} - ${timestamp}`);
    lines.push('');
    lines.push(msg.content);

    if (msg.attachments?.length) {
      lines.push('');
      lines.push('**Attachments:**');
      for (const att of msg.attachments) {
        lines.push(`- [${att.name}](${att.url})`);
      }
    }

    if (msg.reactions?.length) {
      const reactionStr = msg.reactions.map(r => `${r.emoji} (${r.count})`).join(' ');
      lines.push('');
      lines.push(`*Reactions: ${reactionStr}*`);
    }

    lines.push('');
  }

  // Footer
  lines.push('---');
  lines.push('');
  lines.push('*This discussion was archived via the DevRel Integration Bot.*');

  return lines.join('\n');
}

/**
 * Generate archive ID from date and topic
 */
function generateArchiveId(topic: string, date: Date): string {
  const dateStr = date.toISOString().split('T')[0];
  const slug = topic
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .substring(0, 50);
  const timestamp = Date.now().toString(36);
  // Add random component for uniqueness when called rapidly
  const random = Math.random().toString(36).substring(2, 8);
  return `${dateStr}-${slug}-${timestamp}-${random}`;
}

// =============================================================================
// Discussion Archive Service Implementation
// =============================================================================

export class DiscussionArchiveService {
  private static instance: DiscussionArchiveService;

  /** In-memory storage for MVP (replace with Google Docs in production) */
  private archiveStore = new Map<string, ArchivedDiscussion>();

  /** Index for fast lookups */
  private indexStore = new Map<string, DiscussionIndex>();

  /** Google Docs storage service (injected) */
  private googleDocsService?: {
    createDocument(title: string, content: string, folderId?: string): Promise<{ id: string; url: string }>;
  };

  constructor() {
    // Initialize with empty stores
  }

  /**
   * Get singleton instance
   */
  static getInstance(): DiscussionArchiveService {
    if (!DiscussionArchiveService.instance) {
      DiscussionArchiveService.instance = new DiscussionArchiveService();
    }
    return DiscussionArchiveService.instance;
  }

  /**
   * Inject Google Docs service for persistence
   */
  setGoogleDocsService(service: typeof this.googleDocsService): void {
    this.googleDocsService = service;
  }

  // ===========================================================================
  // Public API
  // ===========================================================================

  /**
   * Archive a discussion
   */
  async archiveDiscussion(params: ArchiveDiscussionParams): Promise<ArchivedDiscussion> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    logger.info('Archiving discussion', {
      tenantId,
      topic: params.topic,
      messageCount: params.messages.length,
      channelId: params.channelId,
    });

    // Extract unique participants
    const participants = [...new Set(params.messages.map(m => m.author))];

    // Get earliest and latest timestamps
    const sortedMessages = [...params.messages].sort(
      (a, b) => a.timestamp.getTime() - b.timestamp.getTime()
    );
    const startedAt = sortedMessages[0]?.timestamp || new Date();

    // Generate archive ID
    const id = generateArchiveId(params.topic, new Date());

    // Create archived discussion
    const discussion: ArchivedDiscussion = {
      id,
      topic: params.topic,
      channelId: params.channelId,
      channelName: params.channelName,
      threadId: params.threadId,
      messages: sortedMessages,
      participants,
      startedAt,
      archivedAt: new Date(),
      archivedBy: params.archivedBy,
      resolution: params.resolution,
      linkedIssue: params.linkedIssue,
      tags: params.tags,
      discordUrl: params.discordUrl,
    };

    // Store in Google Docs if available
    if (this.googleDocsService) {
      try {
        const content = formatDiscussionMarkdown(discussion);
        const doc = await this.googleDocsService.createDocument(
          `Discussion: ${params.topic}`,
          content
        );
        discussion.documentUrl = doc.url;
        logger.info('Discussion stored in Google Docs', { id, documentUrl: doc.url });
      } catch (error) {
        logger.warn('Failed to store discussion in Google Docs', {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    // Store in memory
    const key = this.getArchiveKey(tenantId, id);
    this.archiveStore.set(key, discussion);

    // Update index
    await this.updateIndex(tenantId, discussion);

    // Invalidate cache
    await tieredCache.invalidate(tenantId, 'discussion:index');
    await tieredCache.invalidate(tenantId, 'discussion:recent');

    logger.info('Discussion archived successfully', {
      tenantId,
      id,
      topic: params.topic,
      participants: participants.length,
      messageCount: params.messages.length,
    });

    return discussion;
  }

  /**
   * Get archived discussion by ID
   */
  async getDiscussion(id: string): Promise<ArchivedDiscussion | null> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const cacheKey = `discussion:${id}`;

    // Check cache
    const cached = await tieredCache.get<ArchivedDiscussion>(tenantId, cacheKey);
    if (cached) {
      return cached;
    }

    // Get from store
    const key = this.getArchiveKey(tenantId, id);
    const discussion = this.archiveStore.get(key) || null;

    if (discussion) {
      // Cache for future lookups
      await tieredCache.set(tenantId, cacheKey, discussion, 30 * 60); // 30 min TTL
    }

    return discussion;
  }

  /**
   * Search archived discussions
   */
  async searchDiscussions(
    query: string,
    options?: { limit?: number; tags?: string[] }
  ): Promise<DiscussionSearchResult[]> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const limit = options?.limit || 20;
    const filterTags = options?.tags;

    logger.debug('Searching discussions', { tenantId, query, options });

    const results: DiscussionSearchResult[] = [];
    const queryLower = query.toLowerCase();
    const queryTerms = queryLower.split(/\s+/).filter(t => t.length > 2);

    // Search through all discussions
    for (const [key, discussion] of this.archiveStore.entries()) {
      if (!key.startsWith(`${tenantId}:`)) continue;

      // Filter by tags if specified
      if (filterTags?.length) {
        const hasMatchingTag = filterTags.some(tag =>
          discussion.tags?.includes(tag)
        );
        if (!hasMatchingTag) continue;
      }

      const { score, excerpt, matchedField } = this.calculateSearchMatch(
        discussion,
        queryTerms
      );

      if (score > 0) {
        results.push({ discussion, excerpt, score, matchedField });
      }
    }

    // Sort by score and limit results
    return results
      .sort((a, b) => b.score - a.score)
      .slice(0, limit);
  }

  /**
   * Get recent discussions
   */
  async getRecentDiscussions(limit: number = 20): Promise<ArchivedDiscussion[]> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const cacheKey = 'discussion:recent';

    return await tieredCache.getOrFetch(
      tenantId,
      cacheKey,
      async () => {
        const discussions: ArchivedDiscussion[] = [];

        for (const [key, discussion] of this.archiveStore.entries()) {
          if (key.startsWith(`${tenantId}:`)) {
            discussions.push(discussion);
          }
        }

        return discussions
          .sort((a, b) => b.archivedAt.getTime() - a.archivedAt.getTime())
          .slice(0, limit);
      },
      { l2TtlSeconds: 5 * 60 }
    );
  }

  /**
   * Get discussions by channel
   */
  async getDiscussionsByChannel(channelId: string): Promise<ArchivedDiscussion[]> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    const discussions: ArchivedDiscussion[] = [];

    for (const [key, discussion] of this.archiveStore.entries()) {
      if (key.startsWith(`${tenantId}:`) && discussion.channelId === channelId) {
        discussions.push(discussion);
      }
    }

    return discussions.sort((a, b) => b.archivedAt.getTime() - a.archivedAt.getTime());
  }

  /**
   * Get discussions by participant
   */
  async getDiscussionsByParticipant(participant: string): Promise<ArchivedDiscussion[]> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    const discussions: ArchivedDiscussion[] = [];
    const participantLower = participant.toLowerCase();

    for (const [key, discussion] of this.archiveStore.entries()) {
      if (!key.startsWith(`${tenantId}:`)) continue;

      const hasParticipant = discussion.participants.some(
        p => p.toLowerCase() === participantLower
      );

      if (hasParticipant) {
        discussions.push(discussion);
      }
    }

    return discussions.sort((a, b) => b.archivedAt.getTime() - a.archivedAt.getTime());
  }

  /**
   * Link discussion to Linear issue
   */
  async linkToLinearIssue(
    discussionId: string,
    issue: ArchivedDiscussion['linkedIssue']
  ): Promise<boolean> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    const key = this.getArchiveKey(tenantId, discussionId);
    const discussion = this.archiveStore.get(key);

    if (!discussion) {
      logger.warn('Discussion not found for linking', { discussionId });
      return false;
    }

    discussion.linkedIssue = issue;

    // Invalidate cache
    await tieredCache.invalidate(tenantId, `discussion:${discussionId}`);

    logger.info('Discussion linked to Linear issue', {
      discussionId,
      issueId: issue?.identifier,
    });

    return true;
  }

  /**
   * Add resolution to discussion
   */
  async addResolution(discussionId: string, resolution: string): Promise<boolean> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;

    const key = this.getArchiveKey(tenantId, discussionId);
    const discussion = this.archiveStore.get(key);

    if (!discussion) {
      logger.warn('Discussion not found for resolution', { discussionId });
      return false;
    }

    discussion.resolution = resolution;

    // Invalidate cache
    await tieredCache.invalidate(tenantId, `discussion:${discussionId}`);

    logger.info('Resolution added to discussion', { discussionId });

    return true;
  }

  /**
   * Get discussion index
   */
  async getIndex(): Promise<DiscussionIndex> {
    const tenant = getCurrentTenant();
    const tenantId = tenant.tenantId;
    const cacheKey = 'discussion:index';

    return await tieredCache.getOrFetch(
      tenantId,
      cacheKey,
      async () => {
        const key = `index:${tenantId}`;
        return this.indexStore.get(key) || {
          totalCount: 0,
          recent: [],
          lastUpdated: new Date(),
        };
      },
      { l2TtlSeconds: 10 * 60 }
    );
  }

  /**
   * Clear all archives (for testing)
   */
  clearAll(): void {
    this.archiveStore.clear();
    this.indexStore.clear();
  }

  // ===========================================================================
  // Private Methods
  // ===========================================================================

  /**
   * Get archive key with tenant scope
   */
  private getArchiveKey(tenantId: string, id: string): string {
    return `${tenantId}:${id}`;
  }

  /**
   * Update index with new discussion
   */
  private async updateIndex(
    tenantId: string,
    discussion: ArchivedDiscussion
  ): Promise<void> {
    const key = `index:${tenantId}`;
    let index = this.indexStore.get(key);

    if (!index) {
      index = {
        totalCount: 0,
        recent: [],
        lastUpdated: new Date(),
      };
      this.indexStore.set(key, index);
    }

    // Add to recent
    index.recent.unshift({
      id: discussion.id,
      topic: discussion.topic,
      archivedAt: discussion.archivedAt,
      participantCount: discussion.participants.length,
      messageCount: discussion.messages.length,
    });

    // Keep only last 50 in recent
    index.recent = index.recent.slice(0, 50);
    index.totalCount++;
    index.lastUpdated = new Date();
  }

  /**
   * Calculate search match score and excerpt
   */
  private calculateSearchMatch(
    discussion: ArchivedDiscussion,
    queryTerms: string[]
  ): { score: number; excerpt: string; matchedField: string } {
    let score = 0;
    let excerpt = '';
    let matchedField = '';

    const topicLower = discussion.topic.toLowerCase();
    const resolutionLower = (discussion.resolution || '').toLowerCase();
    const tagsLower = (discussion.tags || []).join(' ').toLowerCase();
    const messagesLower = discussion.messages.map(m => m.content.toLowerCase()).join(' ');

    for (const term of queryTerms) {
      // Topic matches are most valuable
      if (topicLower.includes(term)) {
        score += 10;
        if (!excerpt) {
          excerpt = discussion.topic;
          matchedField = 'topic';
        }
      }

      // Tags are second most valuable
      if (tagsLower.includes(term)) {
        score += 8;
        if (!excerpt) {
          excerpt = `Tags: ${discussion.tags?.join(', ')}`;
          matchedField = 'tags';
        }
      }

      // Resolution matches
      if (resolutionLower.includes(term)) {
        score += 5;
        if (!excerpt) {
          excerpt = this.extractExcerpt(discussion.resolution || '', term);
          matchedField = 'resolution';
        }
      }

      // Message content matches
      if (messagesLower.includes(term)) {
        score += 2;
        if (!excerpt) {
          // Find the message with the match
          const matchingMsg = discussion.messages.find(m =>
            m.content.toLowerCase().includes(term)
          );
          if (matchingMsg) {
            excerpt = this.extractExcerpt(matchingMsg.content, term);
            matchedField = 'messages';
          }
        }
      }
    }

    // Default excerpt if no match
    if (!excerpt && score > 0) {
      excerpt = discussion.topic;
      matchedField = 'topic';
    }

    return { score, excerpt, matchedField };
  }

  /**
   * Extract excerpt around a match term
   */
  private extractExcerpt(text: string, term: string): string {
    const lower = text.toLowerCase();
    const index = lower.indexOf(term.toLowerCase());

    if (index === -1) {
      return text.substring(0, 100) + (text.length > 100 ? '...' : '');
    }

    const start = Math.max(0, index - 50);
    const end = Math.min(text.length, index + term.length + 100);
    let excerpt = text.substring(start, end);

    if (start > 0) excerpt = '...' + excerpt;
    if (end < text.length) excerpt = excerpt + '...';

    return excerpt;
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const discussionArchiveService = DiscussionArchiveService.getInstance();
export default discussionArchiveService;

// =============================================================================
// Convenience Functions
// =============================================================================

/**
 * Archive a discussion
 */
export async function archiveDiscussion(
  params: ArchiveDiscussionParams
): Promise<ArchivedDiscussion> {
  return discussionArchiveService.archiveDiscussion(params);
}

/**
 * Search discussions
 */
export async function searchDiscussions(
  query: string,
  options?: { limit?: number; tags?: string[] }
): Promise<DiscussionSearchResult[]> {
  return discussionArchiveService.searchDiscussions(query, options);
}

/**
 * Get discussion by ID
 */
export async function getDiscussion(id: string): Promise<ArchivedDiscussion | null> {
  return discussionArchiveService.getDiscussion(id);
}

/**
 * Get recent discussions
 */
export async function getRecentDiscussions(limit?: number): Promise<ArchivedDiscussion[]> {
  return discussionArchiveService.getRecentDiscussions(limit);
}
