import { LinearClient } from '@linear/sdk';
import Bottleneck from 'bottleneck';
import CircuitBreaker from 'opossum';
import { LRUCache } from 'lru-cache';
import { logger } from '../utils/logger';
import { AppError, ErrorCode } from '../utils/errors';

// Initialize Linear client
const linearClient = new LinearClient({
  apiKey: process.env['LINEAR_API_TOKEN']!,
});

// LINEAR API RATE LIMITING
// Linear allows 2000 req/hour = ~33 req/min
const linearRateLimiter = new Bottleneck({
  reservoir: 100, // Start with 100 requests
  reservoirRefreshAmount: 33,
  reservoirRefreshInterval: 60 * 1000, // 33 requests per minute
  maxConcurrent: 5, // Max 5 concurrent requests
  minTime: 100, // Min 100ms between requests
});

linearRateLimiter.on('failed', async (error: any) => {
  const retryAfter = error.response?.headers?.['retry-after'];
  if (retryAfter) {
    logger.warn(`Linear rate limit hit, retrying after ${retryAfter}s`);
    return parseInt(retryAfter) * 1000; // Retry after specified time
  }
  return 5000; // Default 5s retry
});

// CIRCUIT BREAKER
// LOW-006: Adjusted thresholds to be less aggressive for flaky networks
const linearCircuitBreaker = new CircuitBreaker(
  async (apiCall: () => Promise<any>) => apiCall(),
  {
    timeout: 10000, // 10s timeout
    errorThresholdPercentage: 70, // Open after 70% errors (was 50%)
    resetTimeout: 30000, // Try again after 30s
    rollingCountTimeout: 60000, // 1 minute window
    rollingCountBuckets: 10,
    volumeThreshold: 20, // Min 20 requests before opening (was 10)
  }
);

linearCircuitBreaker.on('open', () => {
  logger.error('🔴 Linear API circuit breaker OPENED - too many failures');
});

linearCircuitBreaker.on('halfOpen', () => {
  logger.info('🟡 Linear API circuit breaker HALF-OPEN - testing recovery');
});

linearCircuitBreaker.on('close', () => {
  logger.info('🟢 Linear API circuit breaker CLOSED - service restored');
});

// REQUEST DEDUPLICATION CACHE
const requestCache = new LRUCache<string, Promise<any>>({
  max: 100,
  ttl: 5000, // 5 seconds
});

// WRAPPED LINEAR API METHODS

/**
 * Create a Linear issue with rate limiting and circuit breaker protection
 */
export async function createLinearIssue(data: {
  title: string;
  description?: string;
  teamId: string;
  labelIds?: string[];
  assigneeId?: string;
  priority?: number;
  stateId?: string;
}): Promise<any> {
  try {
    return await linearCircuitBreaker.fire(() =>
      linearRateLimiter.schedule(() => linearClient.createIssue(data))
    );
  } catch (error: any) {
    if (linearCircuitBreaker.opened) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'Linear integration is temporarily unavailable. Please try again later.',
        `Linear circuit breaker is open: ${error.message}`,
        503
      );
    }

    // Handle specific Linear API errors
    if (error.message?.includes('Unauthorized') || error.message?.includes('401')) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'Linear integration is temporarily unavailable.',
        `Linear API auth failed: ${error.message}`,
        503
      );
    }

    throw new AppError(
      ErrorCode.SERVICE_UNAVAILABLE,
      'Unable to create Linear issue. Please try again.',
      `Linear API error: ${error.message}`,
      503
    );
  }
}

/**
 * Get a Linear issue with caching to prevent duplicate requests
 */
export async function getLinearIssue(id: string): Promise<any> {
  const cacheKey = `issue:${id}`;

  // Return in-flight request if exists
  if (requestCache.has(cacheKey)) {
    return requestCache.get(cacheKey);
  }

  // Make new request
  const promise = (async () => {
    try {
      return await linearCircuitBreaker.fire(() =>
        linearRateLimiter.schedule(() => linearClient.issue(id))
      );
    } catch (error: any) {
      if (linearCircuitBreaker.opened) {
        throw new AppError(
          ErrorCode.SERVICE_UNAVAILABLE,
          'Linear integration is temporarily unavailable.',
          `Linear circuit breaker is open: ${error.message}`,
          503
        );
      }

      if (error.message?.includes('Not Found') || error.message?.includes('404')) {
        throw new AppError(
          ErrorCode.NOT_FOUND,
          `Issue ${id} not found.`,
          `Linear issue ${id} not found: ${error.message}`,
          404
        );
      }

      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'Unable to fetch issue from Linear. Please try again.',
        `Linear API error: ${error.message}`,
        503
      );
    }
  })();

  requestCache.set(cacheKey, promise);
  return promise;
}

/**
 * Update a Linear issue
 */
export async function updateLinearIssue(
  id: string,
  data: {
    title?: string;
    description?: string;
    stateId?: string;
    assigneeId?: string | null;
    priority?: number;
    labelIds?: string[];
  }
): Promise<any> {
  try {
    return await linearCircuitBreaker.fire(() =>
      linearRateLimiter.schedule(() => linearClient.updateIssue(id, data))
    );
  } catch (error: any) {
    if (linearCircuitBreaker.opened) {
      throw new AppError(
        ErrorCode.SERVICE_UNAVAILABLE,
        'Linear integration is temporarily unavailable.',
        `Linear circuit breaker is open: ${error.message}`,
        503
      );
    }

    if (error.message?.includes('Not Found')) {
      throw new AppError(
        ErrorCode.NOT_FOUND,
        `Issue ${id} not found.`,
        `Linear issue ${id} not found: ${error.message}`,
        404
      );
    }

    throw new AppError(
      ErrorCode.SERVICE_UNAVAILABLE,
      'Unable to update Linear issue. Please try again.',
      `Linear API error: ${error.message}`,
      503
    );
  }
}

/**
 * Get team issues with filters
 */
export async function getTeamIssues(teamId?: string, filter?: any): Promise<any[]> {
  const effectiveTeamId = teamId || process.env['LINEAR_TEAM_ID'];

  if (!effectiveTeamId) {
    logger.warn('No team ID provided and LINEAR_TEAM_ID not configured');
    return [];
  }

  try {
    const result = await linearCircuitBreaker.fire(() =>
      linearRateLimiter.schedule(() =>
        linearClient.issues({
          filter: {
            team: { id: { eq: effectiveTeamId } },
            ...filter,
          },
        })
      )
    );
    return result.nodes || [];
  } catch (error: any) {
    if (linearCircuitBreaker.opened) {
      logger.error('Linear circuit breaker is open, returning empty array');
      return [];
    }

    logger.error('Error fetching team issues:', error);
    return [];
  }
}

/**
 * Create a draft Linear issue
 */
export async function createDraftIssue(
  title: string,
  description: string,
  teamId?: string
): Promise<any> {
  const effectiveTeamId = teamId || process.env['LINEAR_TEAM_ID'];

  if (!effectiveTeamId) {
    throw new AppError(
      ErrorCode.CONFIGURATION_ERROR,
      'Linear team ID not configured',
      'LINEAR_TEAM_ID not set',
      500
    );
  }

  return createLinearIssue({
    title,
    description,
    teamId: effectiveTeamId,
  });
}

/**
 * Get current sprint/cycle
 */
export async function getCurrentSprint(teamId?: string): Promise<any> {
  const effectiveTeamId = teamId || process.env['LINEAR_TEAM_ID'];

  if (!effectiveTeamId) {
    logger.warn('No team ID provided and LINEAR_TEAM_ID not configured');
    return null;
  }

  try {
    const team = await linearRateLimiter.schedule(() =>
      linearClient.team(effectiveTeamId)
    );

    const cycles = await team.cycles();
    const activeCycle = cycles.nodes.find((c: any) => !c.completedAt);

    return activeCycle || null;
  } catch (error) {
    logger.error('Error fetching current sprint:', error);
    return null;
  }
}

/**
 * Get monitoring stats for observability
 */
export function getLinearServiceStats() {
  const rateLimiterStats = linearRateLimiter.counts();
  const circuitBreakerStats = linearCircuitBreaker.stats;

  return {
    rateLimiter: {
      executing: rateLimiterStats.EXECUTING,
      queued: rateLimiterStats.QUEUED,
      done: rateLimiterStats.DONE,
      received: rateLimiterStats.RECEIVED,
    },
    circuitBreaker: {
      state: linearCircuitBreaker.opened
        ? 'open'
        : linearCircuitBreaker.halfOpen
        ? 'half-open'
        : 'closed',
      stats: circuitBreakerStats,
    },
  };
}

// MONITORING: Log stats periodically
setInterval(() => {
  const stats = linearRateLimiter.counts();
  logger.info(`Linear API stats: ${stats.EXECUTING} executing, ${stats.QUEUED} queued`);

  if (stats.QUEUED > 50) {
    logger.warn('⚠️ Linear API queue building up - may need to scale');
  }
}, 60000); // Every minute
