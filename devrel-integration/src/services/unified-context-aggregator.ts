/**
 * Unified Context Aggregator
 *
 * Sprint 2 - Task 2.3: Context Aggregation Integration
 *
 * Extends the existing ContextAssembler to aggregate data from multiple sources:
 * - Linear API (issues, comments, status)
 * - GitHub API (PRs, commits)
 * - Discord message history (feedback captured via reactions)
 * - Local filesystem (docs/ directory)
 *
 * Features:
 * - Unified context assembly from multiple sources
 * - Context size limits to avoid API token limits
 * - Caching for 5 minutes to avoid redundant API calls
 * - Graceful degradation (continue if one source fails)
 * - Comprehensive logging and statistics
 */

import { logger, auditLog } from '../utils/logger';
import contextAssembler, { ContextAssembler, ParsedDocument } from './context-assembler';
import documentResolver from './document-resolver';
import { LinearIssue, GitHubPR, DiscordMessage } from '../prompts/persona-prompts';
import { LRUCache } from 'lru-cache';

// =============================================================================
// Types and Interfaces
// =============================================================================

export interface UnifiedContext {
  sourceDocuments: Array<{
    name: string;
    content: string;
    path: string;
    sensitivity?: string;
  }>;
  linearIssues?: LinearIssue[];
  githubPRs?: GitHubPR[];
  discordFeedback?: DiscordMessage[];
  metadata: {
    projectName: string;
    sprintId?: string;
    aggregatedAt: Date;
    sources: string[];
    statistics: {
      documentCount: number;
      linearIssueCount: number;
      githubPRCount: number;
      discordMessageCount: number;
      totalTokenEstimate: number;
    };
    warnings: string[];
    errors: string[];
  };
}

export interface AggregationOptions {
  /** Include Linear issues (default: true) */
  includeLinear?: boolean;
  /** Include GitHub PRs (default: true) */
  includeGitHub?: boolean;
  /** Include Discord feedback (default: true) */
  includeDiscord?: boolean;
  /** Linear project/team filter */
  linearProject?: string;
  /** Linear sprint filter */
  linearSprint?: string;
  /** Linear labels filter */
  linearLabels?: string[];
  /** GitHub repository (owner/repo format) */
  githubRepo?: string;
  /** GitHub branch filter */
  githubBranch?: string;
  /** Discord channel IDs to fetch from */
  discordChannelIds?: string[];
  /** Days of Discord history to fetch */
  discordDaysBack?: number;
  /** Max Linear issues to include (default: 50) */
  maxLinearIssues?: number;
  /** Max GitHub PRs to include (default: 20) */
  maxGitHubPRs?: number;
  /** Max Discord messages to include (default: 100) */
  maxDiscordMessages?: number;
  /** Max total context tokens (default: 100000) */
  maxTotalTokens?: number;
  /** Requested by (for audit logging) */
  requestedBy?: string;
}

// =============================================================================
// Cache Setup
// =============================================================================

// 5-minute cache for aggregated context
const contextCache = new LRUCache<string, UnifiedContext>({
  max: 100, // Max 100 cached contexts
  ttl: 5 * 60 * 1000, // 5 minutes TTL
});

// =============================================================================
// Unified Context Aggregator Class
// =============================================================================

export class UnifiedContextAggregator {
  private contextAssembler: ContextAssembler;

  constructor() {
    this.contextAssembler = contextAssembler;
  }

  /**
   * Aggregate context from multiple sources
   */
  async aggregateContext(
    primaryDocumentPath: string,
    projectName: string,
    options: AggregationOptions = {}
  ): Promise<UnifiedContext> {
    const {
      includeLinear = true,
      includeGitHub = true,
      includeDiscord = true,
      maxLinearIssues = 50,
      maxGitHubPRs = 20,
      maxDiscordMessages = 100,
      maxTotalTokens = 100000,
      requestedBy = 'system',
    } = options;

    // Check cache first
    const cacheKey = this.generateCacheKey(primaryDocumentPath, projectName, options);
    const cachedContext = contextCache.get(cacheKey);
    if (cachedContext) {
      logger.info('Returning cached context', { cacheKey });
      return cachedContext;
    }

    logger.info('Aggregating context from multiple sources', {
      primaryDocumentPath,
      projectName,
      includeLinear,
      includeGitHub,
      includeDiscord,
    });

    const startTime = Date.now();
    const warnings: string[] = [];
    const errors: string[] = [];
    const sources: string[] = [];

    // Initialize result structure
    const result: UnifiedContext = {
      sourceDocuments: [],
      metadata: {
        projectName,
        sprintId: options.linearSprint,
        aggregatedAt: new Date(),
        sources: [],
        statistics: {
          documentCount: 0,
          linearIssueCount: 0,
          githubPRCount: 0,
          discordMessageCount: 0,
          totalTokenEstimate: 0,
        },
        warnings: [],
        errors: [],
      },
    };

    let currentTokenEstimate = 0;

    // ==========================================================================
    // Step 1: Aggregate source documents
    // ==========================================================================
    try {
      const docResult = await this.aggregateDocuments(primaryDocumentPath, requestedBy);
      result.sourceDocuments = docResult.documents;
      currentTokenEstimate += docResult.tokenEstimate;
      sources.push('local-filesystem');

      if (docResult.warnings.length > 0) {
        warnings.push(...docResult.warnings);
      }

      result.metadata.statistics.documentCount = docResult.documents.length;
      logger.info('Documents aggregated', {
        count: docResult.documents.length,
        tokenEstimate: docResult.tokenEstimate,
      });
    } catch (error) {
      const errorMsg = `Failed to aggregate documents: ${error instanceof Error ? error.message : String(error)}`;
      errors.push(errorMsg);
      logger.error(errorMsg);
    }

    // ==========================================================================
    // Step 2: Aggregate Linear issues (if enabled and under token limit)
    // ==========================================================================
    if (includeLinear && currentTokenEstimate < maxTotalTokens * 0.7) {
      try {
        const linearResult = await this.aggregateLinearIssues(options, maxLinearIssues);
        result.linearIssues = linearResult.issues;
        currentTokenEstimate += linearResult.tokenEstimate;
        sources.push('linear');

        if (linearResult.warnings.length > 0) {
          warnings.push(...linearResult.warnings);
        }

        result.metadata.statistics.linearIssueCount = linearResult.issues.length;
        logger.info('Linear issues aggregated', {
          count: linearResult.issues.length,
          tokenEstimate: linearResult.tokenEstimate,
        });
      } catch (error) {
        const errorMsg = `Failed to aggregate Linear issues: ${error instanceof Error ? error.message : String(error)}`;
        errors.push(errorMsg);
        logger.warn(errorMsg);
        // Continue with other sources (graceful degradation)
      }
    }

    // ==========================================================================
    // Step 3: Aggregate GitHub PRs (if enabled and under token limit)
    // ==========================================================================
    if (includeGitHub && currentTokenEstimate < maxTotalTokens * 0.8) {
      try {
        const githubResult = await this.aggregateGitHubPRs(options, maxGitHubPRs);
        result.githubPRs = githubResult.prs;
        currentTokenEstimate += githubResult.tokenEstimate;
        sources.push('github');

        if (githubResult.warnings.length > 0) {
          warnings.push(...githubResult.warnings);
        }

        result.metadata.statistics.githubPRCount = githubResult.prs.length;
        logger.info('GitHub PRs aggregated', {
          count: githubResult.prs.length,
          tokenEstimate: githubResult.tokenEstimate,
        });
      } catch (error) {
        const errorMsg = `Failed to aggregate GitHub PRs: ${error instanceof Error ? error.message : String(error)}`;
        errors.push(errorMsg);
        logger.warn(errorMsg);
        // Continue with other sources (graceful degradation)
      }
    }

    // ==========================================================================
    // Step 4: Aggregate Discord feedback (if enabled and under token limit)
    // ==========================================================================
    if (includeDiscord && currentTokenEstimate < maxTotalTokens * 0.9) {
      try {
        const discordResult = await this.aggregateDiscordFeedback(options, maxDiscordMessages);
        result.discordFeedback = discordResult.messages;
        currentTokenEstimate += discordResult.tokenEstimate;
        sources.push('discord');

        if (discordResult.warnings.length > 0) {
          warnings.push(...discordResult.warnings);
        }

        result.metadata.statistics.discordMessageCount = discordResult.messages.length;
        logger.info('Discord feedback aggregated', {
          count: discordResult.messages.length,
          tokenEstimate: discordResult.tokenEstimate,
        });
      } catch (error) {
        const errorMsg = `Failed to aggregate Discord feedback: ${error instanceof Error ? error.message : String(error)}`;
        errors.push(errorMsg);
        logger.warn(errorMsg);
        // Continue (graceful degradation)
      }
    }

    // ==========================================================================
    // Step 5: Finalize and cache result
    // ==========================================================================
    result.metadata.sources = sources;
    result.metadata.warnings = warnings;
    result.metadata.errors = errors;
    result.metadata.statistics.totalTokenEstimate = currentTokenEstimate;

    const duration = Date.now() - startTime;

    // Audit log
    auditLog.contextAssembly(requestedBy, primaryDocumentPath, {
      sources,
      statistics: result.metadata.statistics,
      durationMs: duration,
    });

    logger.info('Context aggregation complete', {
      sources,
      statistics: result.metadata.statistics,
      durationMs: duration,
      warningCount: warnings.length,
      errorCount: errors.length,
    });

    // Cache the result
    contextCache.set(cacheKey, result);

    return result;
  }

  // ===========================================================================
  // Document Aggregation
  // ===========================================================================

  private async aggregateDocuments(
    primaryDocumentPath: string,
    requestedBy: string
  ): Promise<{
    documents: UnifiedContext['sourceDocuments'];
    tokenEstimate: number;
    warnings: string[];
  }> {
    const warnings: string[] = [];
    const documents: UnifiedContext['sourceDocuments'] = [];
    let tokenEstimate = 0;

    // Use existing ContextAssembler for document aggregation
    const assemblyResult = await this.contextAssembler.assembleContext(primaryDocumentPath, {
      maxContextDocuments: 10,
      failOnValidationError: false,
      requestedBy,
    });

    // Add primary document
    documents.push({
      name: assemblyResult.primaryDocument.frontmatter.title || primaryDocumentPath,
      content: assemblyResult.primaryDocument.body,
      path: assemblyResult.primaryDocument.path,
      sensitivity: assemblyResult.primaryDocument.frontmatter.sensitivity,
    });
    tokenEstimate += this.estimateTokens(assemblyResult.primaryDocument.body);

    // Add context documents
    for (const contextDoc of assemblyResult.contextDocuments) {
      documents.push({
        name: contextDoc.frontmatter.title || contextDoc.path,
        content: contextDoc.body,
        path: contextDoc.path,
        sensitivity: contextDoc.frontmatter.sensitivity,
      });
      tokenEstimate += this.estimateTokens(contextDoc.body);
    }

    // Add any warnings from assembly
    warnings.push(...assemblyResult.warnings);

    // Add rejected contexts as warnings
    for (const rejected of assemblyResult.rejectedContexts) {
      warnings.push(`Context rejected: ${rejected.path} - ${rejected.reason}`);
    }

    return { documents, tokenEstimate, warnings };
  }

  // ===========================================================================
  // Linear Integration
  // ===========================================================================

  private async aggregateLinearIssues(
    options: AggregationOptions,
    maxIssues: number
  ): Promise<{
    issues: LinearIssue[];
    tokenEstimate: number;
    warnings: string[];
  }> {
    const warnings: string[] = [];
    const issues: LinearIssue[] = [];

    // In a real implementation, this would call the Linear MCP
    // For now, we check if LINEAR_API_KEY is available
    if (!process.env.LINEAR_API_KEY) {
      warnings.push('LINEAR_API_KEY not configured - skipping Linear integration');
      return { issues, tokenEstimate: 0, warnings };
    }

    try {
      // This would be replaced with actual Linear MCP calls
      // Example: await mcp__linear__list_issues({ project: options.linearProject, ... })
      logger.info('Linear integration - would fetch issues', {
        project: options.linearProject,
        sprint: options.linearSprint,
        labels: options.linearLabels,
        maxIssues,
      });

      // Placeholder for actual implementation
      // The integration would use the Linear MCP tools available in the system

      // For now, return empty with a note
      warnings.push('Linear integration active but no issues fetched (MCP integration pending)');
    } catch (error) {
      throw error;
    }

    const tokenEstimate = issues.reduce(
      (total, issue) =>
        total + this.estimateTokens(issue.title + (issue.description || '')),
      0
    );

    return { issues, tokenEstimate, warnings };
  }

  // ===========================================================================
  // GitHub Integration
  // ===========================================================================

  private async aggregateGitHubPRs(
    options: AggregationOptions,
    maxPRs: number
  ): Promise<{
    prs: GitHubPR[];
    tokenEstimate: number;
    warnings: string[];
  }> {
    const warnings: string[] = [];
    const prs: GitHubPR[] = [];

    // In a real implementation, this would call the GitHub MCP
    if (!process.env.GITHUB_TOKEN && !options.githubRepo) {
      warnings.push('GitHub not configured - skipping GitHub integration');
      return { prs, tokenEstimate: 0, warnings };
    }

    try {
      // This would be replaced with actual GitHub MCP calls
      // Example: await mcp__github__list_pull_requests({ owner, repo, ... })
      logger.info('GitHub integration - would fetch PRs', {
        repo: options.githubRepo,
        branch: options.githubBranch,
        maxPRs,
      });

      // Placeholder for actual implementation
      warnings.push('GitHub integration active but no PRs fetched (MCP integration pending)');
    } catch (error) {
      throw error;
    }

    const tokenEstimate = prs.reduce(
      (total, pr) => total + this.estimateTokens(pr.title + (pr.description || '')),
      0
    );

    return { prs, tokenEstimate, warnings };
  }

  // ===========================================================================
  // Discord Integration
  // ===========================================================================

  private async aggregateDiscordFeedback(
    options: AggregationOptions,
    maxMessages: number
  ): Promise<{
    messages: DiscordMessage[];
    tokenEstimate: number;
    warnings: string[];
  }> {
    const warnings: string[] = [];
    const messages: DiscordMessage[] = [];

    // In a real implementation, this would call the Discord MCP
    if (!process.env.DISCORD_BOT_TOKEN) {
      warnings.push('DISCORD_BOT_TOKEN not configured - skipping Discord integration');
      return { messages, tokenEstimate: 0, warnings };
    }

    try {
      // This would be replaced with actual Discord MCP calls
      // Example: await mcp__discord__read_messages({ channel_id, limit, ... })
      logger.info('Discord integration - would fetch feedback', {
        channelIds: options.discordChannelIds,
        daysBack: options.discordDaysBack || 7,
        maxMessages,
      });

      // Placeholder for actual implementation
      warnings.push('Discord integration active but no messages fetched (MCP integration pending)');
    } catch (error) {
      throw error;
    }

    const tokenEstimate = messages.reduce(
      (total, msg) => total + this.estimateTokens(msg.content),
      0
    );

    return { messages, tokenEstimate, warnings };
  }

  // ===========================================================================
  // Helper Methods
  // ===========================================================================

  /**
   * Estimate token count for text (rough approximation: 1 token ≈ 4 chars)
   */
  private estimateTokens(text: string): number {
    return Math.ceil(text.length / 4);
  }

  /**
   * Generate cache key from aggregation parameters
   */
  private generateCacheKey(
    primaryDocPath: string,
    projectName: string,
    options: AggregationOptions
  ): string {
    const keyParts = [
      primaryDocPath,
      projectName,
      options.linearProject || '',
      options.linearSprint || '',
      options.githubRepo || '',
      options.githubBranch || '',
      (options.discordChannelIds || []).join(','),
    ];
    return keyParts.join('|');
  }

  /**
   * Clear the context cache
   */
  clearCache(): void {
    contextCache.clear();
    logger.info('Context cache cleared');
  }

  /**
   * Get cache statistics
   */
  getCacheStats(): {
    size: number;
    maxSize: number;
  } {
    return {
      size: contextCache.size,
      maxSize: 100,
    };
  }

  /**
   * Format unified context as text for LLM input
   */
  formatContextForLLM(context: UnifiedContext): string {
    const sections: string[] = [];

    // Source documents
    if (context.sourceDocuments.length > 0) {
      sections.push('# Source Documents\n');
      for (const doc of context.sourceDocuments) {
        sections.push(`## ${doc.name}\n\n${doc.content}\n`);
      }
    }

    // Linear issues
    if (context.linearIssues && context.linearIssues.length > 0) {
      sections.push('# Related Linear Issues\n');
      for (const issue of context.linearIssues) {
        sections.push(`- **${issue.title}** (${issue.status})`);
        if (issue.description) {
          sections.push(`  ${issue.description.substring(0, 200)}...`);
        }
      }
      sections.push('');
    }

    // GitHub PRs
    if (context.githubPRs && context.githubPRs.length > 0) {
      sections.push('# Related Pull Requests\n');
      for (const pr of context.githubPRs) {
        sections.push(`- **#${pr.number}: ${pr.title}** (${pr.status})`);
        if (pr.description) {
          sections.push(`  ${pr.description.substring(0, 200)}...`);
        }
      }
      sections.push('');
    }

    // Discord feedback
    if (context.discordFeedback && context.discordFeedback.length > 0) {
      sections.push('# Community Feedback\n');
      for (const msg of context.discordFeedback) {
        sections.push(`- "${msg.content.substring(0, 200)}..." — ${msg.author}`);
      }
      sections.push('');
    }

    return sections.join('\n');
  }
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const unifiedContextAggregator = new UnifiedContextAggregator();
export default unifiedContextAggregator;
