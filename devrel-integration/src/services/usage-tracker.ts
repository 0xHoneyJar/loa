/**
 * Usage Tracker Service
 *
 * Sprint 6 - Task 6.5: Usage Tracking & Unit Economics
 *
 * Provides per-tenant usage tracking to monitor costs, API calls, and
 * transformation volumes for unit economics visibility.
 *
 * Features:
 * - Track transformations (total, by persona, cached vs API)
 * - Track API calls (Claude, Google Drive, Google Docs)
 * - Estimate costs based on usage
 * - Generate usage reports
 * - Redis-based counters for real-time tracking
 * - Tenant isolation
 */

import { logger } from '../utils/logger';
import { getCurrentTenant, getCurrentTenantId } from './tenant-context';

// =============================================================================
// Types
// =============================================================================

export interface UsageMetrics {
  tenantId: string;
  period: string;
  transformations: TransformationMetrics;
  apiCalls: ApiCallMetrics;
  storage: StorageMetrics;
  costs: CostEstimates;
  generatedAt: Date;
}

export interface TransformationMetrics {
  total: number;
  byPersona: Record<string, number>;
  cachedHits: number;
  apiCalls: number;
}

export interface ApiCallMetrics {
  claude: ClaudeApiMetrics;
  googleDrive: GoogleApiMetrics;
  googleDocs: GoogleApiMetrics;
}

export interface ClaudeApiMetrics {
  count: number;
  tokensIn: number;
  tokensOut: number;
  estimatedCost: number;
}

export interface GoogleApiMetrics {
  count: number;
}

export interface StorageMetrics {
  documentsCreated: number;
  totalSizeBytes: number;
}

export interface CostEstimates {
  claudeApi: number;
  googleWorkspace: number;
  infrastructure: number;
  total: number;
  costPerTransformation: number;
  cacheEfficiency: number;
}

export interface ApiCallDetails {
  tokensIn?: number;
  tokensOut?: number;
  model?: string;
  sizeBytes?: number;
}

export interface RedisClientInterface {
  incr(key: string): Promise<number>;
  incrby(key: string, increment: number): Promise<number>;
  get(key: string): Promise<string | null>;
  mget(...keys: string[]): Promise<(string | null)[]>;
  expire(key: string, seconds: number): Promise<number>;
  keys(pattern: string): Promise<string[]>;
}

// =============================================================================
// Pricing Constants
// =============================================================================

/** Claude API pricing (per million tokens) */
const CLAUDE_PRICING = {
  sonnet: {
    input: 15, // $15/MTok
    output: 75, // $75/MTok
  },
  haiku: {
    input: 0.8, // $0.80/MTok
    output: 4, // $4/MTok
  },
  opus: {
    input: 75, // $75/MTok
    output: 150, // $150/MTok
  },
};

/** Google Workspace estimated cost per user/month */
const GOOGLE_WORKSPACE_COST_PER_USER = 12; // $12/user/month (Business Standard)

/** Infrastructure base cost per month */
const INFRASTRUCTURE_BASE_COST = 30; // $30/month for MVP

// =============================================================================
// Usage Tracker Service
// =============================================================================

export class UsageTracker {
  private static instance: UsageTracker;
  private redisClient: RedisClientInterface | null = null;
  private inMemoryCounters = new Map<string, number>();

  /**
   * Get singleton instance
   */
  static getInstance(): UsageTracker {
    if (!UsageTracker.instance) {
      UsageTracker.instance = new UsageTracker();
    }
    return UsageTracker.instance;
  }

  /**
   * Inject Redis client for persistent tracking
   */
  setRedisClient(client: RedisClientInterface): void {
    this.redisClient = client;
    logger.info('UsageTracker Redis client configured');
  }

  // ===========================================================================
  // Tracking Methods
  // ===========================================================================

  /**
   * Track a transformation
   */
  async trackTransformation(
    tenantId: string,
    persona: string,
    cached: boolean
  ): Promise<void> {
    const period = this.getCurrentPeriod();

    logger.debug('Tracking transformation', {
      tenantId,
      persona,
      cached,
      period,
    });

    try {
      await Promise.all([
        this.incrementCounter(`${tenantId}:usage:${period}:transformations:total`),
        this.incrementCounter(`${tenantId}:usage:${period}:transformations:${persona}`),
        cached
          ? this.incrementCounter(`${tenantId}:usage:${period}:transformations:cached`)
          : this.incrementCounter(`${tenantId}:usage:${period}:transformations:api`),
      ]);
    } catch (error) {
      logger.error('Failed to track transformation', {
        error: error instanceof Error ? error.message : String(error),
        tenantId,
      });
    }
  }

  /**
   * Track an API call
   */
  async trackApiCall(
    tenantId: string,
    api: 'claude' | 'googleDrive' | 'googleDocs',
    details: ApiCallDetails = {}
  ): Promise<void> {
    const period = this.getCurrentPeriod();

    logger.debug('Tracking API call', {
      tenantId,
      api,
      period,
    });

    try {
      await this.incrementCounter(`${tenantId}:usage:${period}:api:${api}:count`);

      if (api === 'claude') {
        if (details.tokensIn) {
          await this.incrementCounter(
            `${tenantId}:usage:${period}:api:claude:tokens_in`,
            details.tokensIn
          );
        }
        if (details.tokensOut) {
          await this.incrementCounter(
            `${tenantId}:usage:${period}:api:claude:tokens_out`,
            details.tokensOut
          );
        }
      }

      if (details.sizeBytes) {
        await this.incrementCounter(
          `${tenantId}:usage:${period}:storage:size_bytes`,
          details.sizeBytes
        );
      }
    } catch (error) {
      logger.error('Failed to track API call', {
        error: error instanceof Error ? error.message : String(error),
        tenantId,
        api,
      });
    }
  }

  /**
   * Track document creation
   */
  async trackDocumentCreation(
    tenantId: string,
    sizeBytes: number
  ): Promise<void> {
    const period = this.getCurrentPeriod();

    try {
      await Promise.all([
        this.incrementCounter(`${tenantId}:usage:${period}:storage:documents_created`),
        this.incrementCounter(`${tenantId}:usage:${period}:storage:size_bytes`, sizeBytes),
      ]);
    } catch (error) {
      logger.error('Failed to track document creation', {
        error: error instanceof Error ? error.message : String(error),
        tenantId,
      });
    }
  }

  // ===========================================================================
  // Reporting Methods
  // ===========================================================================

  /**
   * Get usage report for a tenant and period
   */
  async getUsageReport(
    tenantId: string,
    period?: string
  ): Promise<UsageMetrics> {
    const reportPeriod = period ?? this.getCurrentPeriod();

    logger.info('Generating usage report', {
      tenantId,
      period: reportPeriod,
    });

    try {
      // Fetch all counters for the period
      const prefix = `${tenantId}:usage:${reportPeriod}`;

      const [
        totalTransformations,
        cachedTransformations,
        apiTransformations,
        claudeCount,
        claudeTokensIn,
        claudeTokensOut,
        googleDriveCount,
        googleDocsCount,
        documentsCreated,
        storageSizeBytes,
      ] = await this.getCounters([
        `${prefix}:transformations:total`,
        `${prefix}:transformations:cached`,
        `${prefix}:transformations:api`,
        `${prefix}:api:claude:count`,
        `${prefix}:api:claude:tokens_in`,
        `${prefix}:api:claude:tokens_out`,
        `${prefix}:api:googleDrive:count`,
        `${prefix}:api:googleDocs:count`,
        `${prefix}:storage:documents_created`,
        `${prefix}:storage:size_bytes`,
      ]);

      // Get persona breakdown
      const personaKeys = await this.getKeysMatching(`${prefix}:transformations:*`);
      const byPersona: Record<string, number> = {};

      for (const key of personaKeys) {
        const match = key.match(/:transformations:(\w+)$/);
        if (match && !['total', 'cached', 'api'].includes(match[1])) {
          byPersona[match[1]] = await this.getCounter(key);
        }
      }

      // Calculate costs
      const claudeCost = this.calculateClaudeCost(claudeTokensIn, claudeTokensOut);
      const googleCost = GOOGLE_WORKSPACE_COST_PER_USER; // Simplified estimate
      const infraCost = INFRASTRUCTURE_BASE_COST;
      const totalCost = claudeCost + googleCost + infraCost;

      const costPerTransformation = totalTransformations > 0
        ? totalCost / totalTransformations
        : 0;

      const cacheEfficiency = totalTransformations > 0
        ? cachedTransformations / totalTransformations
        : 0;

      const report: UsageMetrics = {
        tenantId,
        period: reportPeriod,
        transformations: {
          total: totalTransformations,
          byPersona,
          cachedHits: cachedTransformations,
          apiCalls: apiTransformations,
        },
        apiCalls: {
          claude: {
            count: claudeCount,
            tokensIn: claudeTokensIn,
            tokensOut: claudeTokensOut,
            estimatedCost: claudeCost,
          },
          googleDrive: { count: googleDriveCount },
          googleDocs: { count: googleDocsCount },
        },
        storage: {
          documentsCreated,
          totalSizeBytes: storageSizeBytes,
        },
        costs: {
          claudeApi: claudeCost,
          googleWorkspace: googleCost,
          infrastructure: infraCost,
          total: totalCost,
          costPerTransformation,
          cacheEfficiency,
        },
        generatedAt: new Date(),
      };

      logger.info('Usage report generated', {
        tenantId,
        period: reportPeriod,
        totalTransformations,
        totalCost: totalCost.toFixed(2),
      });

      return report;
    } catch (error) {
      logger.error('Failed to generate usage report', {
        error: error instanceof Error ? error.message : String(error),
        tenantId,
      });
      throw error;
    }
  }

  /**
   * Get usage comparison between two periods
   */
  async getUsageComparison(
    tenantId: string,
    currentPeriod?: string,
    previousPeriod?: string
  ): Promise<{
    current: UsageMetrics;
    previous: UsageMetrics;
    changes: UsageChanges;
  }> {
    const current = currentPeriod ?? this.getCurrentPeriod();
    const previous = previousPeriod ?? this.getPreviousPeriod(current);

    const [currentReport, previousReport] = await Promise.all([
      this.getUsageReport(tenantId, current),
      this.getUsageReport(tenantId, previous),
    ]);

    const changes = this.calculateChanges(currentReport, previousReport);

    return {
      current: currentReport,
      previous: previousReport,
      changes,
    };
  }

  // ===========================================================================
  // Counter Operations
  // ===========================================================================

  /**
   * Increment a counter
   */
  private async incrementCounter(key: string, amount: number = 1): Promise<number> {
    if (this.redisClient) {
      try {
        const result = amount === 1
          ? await this.redisClient.incr(key)
          : await this.redisClient.incrby(key, amount);

        // Set expiry to 90 days for usage data
        await this.redisClient.expire(key, 90 * 24 * 60 * 60);

        return result;
      } catch (error) {
        logger.warn('Redis increment failed, using in-memory', {
          error: error instanceof Error ? error.message : String(error),
          key,
        });
      }
    }

    // Fallback to in-memory
    const current = this.inMemoryCounters.get(key) ?? 0;
    const newValue = current + amount;
    this.inMemoryCounters.set(key, newValue);
    return newValue;
  }

  /**
   * Get a single counter value
   */
  private async getCounter(key: string): Promise<number> {
    if (this.redisClient) {
      try {
        const value = await this.redisClient.get(key);
        return value ? parseInt(value, 10) : 0;
      } catch (error) {
        logger.warn('Redis get failed, using in-memory', {
          error: error instanceof Error ? error.message : String(error),
          key,
        });
      }
    }

    return this.inMemoryCounters.get(key) ?? 0;
  }

  /**
   * Get multiple counter values
   */
  private async getCounters(keys: string[]): Promise<number[]> {
    if (this.redisClient) {
      try {
        const values = await this.redisClient.mget(...keys);
        return values.map((v) => (v ? parseInt(v, 10) : 0));
      } catch (error) {
        logger.warn('Redis mget failed, using in-memory', {
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    return keys.map((key) => this.inMemoryCounters.get(key) ?? 0);
  }

  /**
   * Get keys matching a pattern
   */
  private async getKeysMatching(pattern: string): Promise<string[]> {
    if (this.redisClient) {
      try {
        return await this.redisClient.keys(pattern);
      } catch (error) {
        logger.warn('Redis keys failed, using in-memory', {
          error: error instanceof Error ? error.message : String(error),
          pattern,
        });
      }
    }

    // Match keys from in-memory store
    const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
    return Array.from(this.inMemoryCounters.keys()).filter((k) => regex.test(k));
  }

  // ===========================================================================
  // Utility Methods
  // ===========================================================================

  /**
   * Get current period string (YYYY-MM)
   */
  private getCurrentPeriod(): string {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  }

  /**
   * Get previous period string
   */
  private getPreviousPeriod(current: string): string {
    const [year, month] = current.split('-').map(Number);
    const prevMonth = month === 1 ? 12 : month - 1;
    const prevYear = month === 1 ? year - 1 : year;
    return `${prevYear}-${String(prevMonth).padStart(2, '0')}`;
  }

  /**
   * Calculate Claude API cost
   */
  private calculateClaudeCost(tokensIn: number, tokensOut: number, model: string = 'sonnet'): number {
    const pricing = CLAUDE_PRICING[model as keyof typeof CLAUDE_PRICING] ?? CLAUDE_PRICING.sonnet;
    const inputCost = (tokensIn / 1_000_000) * pricing.input;
    const outputCost = (tokensOut / 1_000_000) * pricing.output;
    return inputCost + outputCost;
  }

  /**
   * Calculate usage changes between periods
   */
  private calculateChanges(current: UsageMetrics, previous: UsageMetrics): UsageChanges {
    const calcChange = (curr: number, prev: number): number => {
      if (prev === 0) return curr > 0 ? 100 : 0;
      return ((curr - prev) / prev) * 100;
    };

    return {
      transformations: calcChange(
        current.transformations.total,
        previous.transformations.total
      ),
      apiCalls: calcChange(
        current.apiCalls.claude.count + current.apiCalls.googleDrive.count + current.apiCalls.googleDocs.count,
        previous.apiCalls.claude.count + previous.apiCalls.googleDrive.count + previous.apiCalls.googleDocs.count
      ),
      costs: calcChange(current.costs.total, previous.costs.total),
      cacheEfficiency: current.costs.cacheEfficiency - previous.costs.cacheEfficiency,
    };
  }

  /**
   * Clear in-memory counters (for testing)
   */
  clearInMemoryCounters(): void {
    this.inMemoryCounters.clear();
    logger.debug('In-memory counters cleared');
  }

  // ===========================================================================
  // Formatting Methods
  // ===========================================================================

  /**
   * Format usage report for Discord
   */
  formatReportForDiscord(report: UsageMetrics): object {
    const formatCurrency = (amount: number): string => `$${amount.toFixed(2)}`;
    const formatPercent = (value: number): string => `${(value * 100).toFixed(1)}%`;

    return {
      title: `Usage Report: ${report.period}`,
      description: `Tenant: ${report.tenantId}`,
      fields: [
        {
          name: 'Transformations',
          value: [
            `Total: ${report.transformations.total}`,
            `Cached: ${report.transformations.cachedHits}`,
            `API: ${report.transformations.apiCalls}`,
          ].join('\n'),
          inline: true,
        },
        {
          name: 'API Calls',
          value: [
            `Claude: ${report.apiCalls.claude.count}`,
            `Drive: ${report.apiCalls.googleDrive.count}`,
            `Docs: ${report.apiCalls.googleDocs.count}`,
          ].join('\n'),
          inline: true,
        },
        {
          name: 'Costs',
          value: [
            `Claude: ${formatCurrency(report.costs.claudeApi)}`,
            `Google: ${formatCurrency(report.costs.googleWorkspace)}`,
            `Infra: ${formatCurrency(report.costs.infrastructure)}`,
            `**Total: ${formatCurrency(report.costs.total)}**`,
          ].join('\n'),
          inline: true,
        },
        {
          name: 'Efficiency',
          value: [
            `Cost/Transform: ${formatCurrency(report.costs.costPerTransformation)}`,
            `Cache Hit Rate: ${formatPercent(report.costs.cacheEfficiency)}`,
          ].join('\n'),
          inline: false,
        },
        {
          name: 'Personas',
          value: Object.entries(report.transformations.byPersona)
            .map(([persona, count]) => `• ${persona}: ${count}`)
            .join('\n') || 'No data',
          inline: false,
        },
      ],
      footer: { text: `Generated at ${report.generatedAt.toISOString()}` },
    };
  }
}

// =============================================================================
// Additional Types
// =============================================================================

export interface UsageChanges {
  transformations: number;
  apiCalls: number;
  costs: number;
  cacheEfficiency: number;
}

// =============================================================================
// Export Singleton Instance
// =============================================================================

export const usageTracker = UsageTracker.getInstance();
export default usageTracker;
