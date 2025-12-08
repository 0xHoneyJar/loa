import crypto from 'crypto';
import { LRUCache } from 'lru-cache';
import { logger } from './logger';

/**
 * Session Management System
 *
 * SECURITY FIX: LOW #20
 * - Stateful session tracking for multi-step interactions
 * - Session token generation and validation
 * - Automatic expiration
 * - Rate limiting per session
 */

export interface UserSession {
  sessionId: string;
  userId: string;
  discordId?: string;
  createdAt: number;
  lastActivity: number;
  expiresAt: number;
  metadata: {
    ipAddress?: string;
    userAgent?: string;
    platform?: string;
  };
  state: Record<string, any>;
  actionCount: number;
}

export interface SessionOptions {
  ttl?: number; // Time to live in milliseconds
  maxActions?: number; // Max actions per session
}

const DEFAULT_TTL = 30 * 60 * 1000; // 30 minutes
const DEFAULT_MAX_ACTIONS = 100;

/**
 * Session Manager using LRU cache
 */
export class SessionManager {
  private sessions: LRUCache<string, UserSession>;
  private readonly ttl: number;
  private readonly maxActions: number;

  constructor(options: SessionOptions = {}) {
    this.ttl = options.ttl || DEFAULT_TTL;
    this.maxActions = options.maxActions || DEFAULT_MAX_ACTIONS;

    this.sessions = new LRUCache<string, UserSession>({
      max: 1000, // Max 1000 active sessions
      ttl: this.ttl,
      updateAgeOnGet: true, // Refresh TTL on access
      dispose: (session, key) => {
        logger.info('Session expired', {
          sessionId: key,
          userId: session.userId,
          duration: Date.now() - session.createdAt,
        });
      },
    });
  }

  /**
   * Generate cryptographically secure session ID
   */
  private generateSessionId(): string {
    return crypto.randomBytes(32).toString('hex');
  }

  /**
   * Create new session
   */
  createSession(
    userId: string,
    metadata: UserSession['metadata'] = {}
  ): UserSession {
    const sessionId = this.generateSessionId();
    const now = Date.now();

    const session: UserSession = {
      sessionId,
      userId,
      discordId: metadata.platform === 'discord' ? userId : undefined,
      createdAt: now,
      lastActivity: now,
      expiresAt: now + this.ttl,
      metadata,
      state: {},
      actionCount: 0,
    };

    this.sessions.set(sessionId, session);

    logger.info('Session created', {
      sessionId,
      userId,
      expiresIn: this.ttl,
    });

    return session;
  }

  /**
   * Get session by ID
   */
  getSession(sessionId: string): UserSession | null {
    const session = this.sessions.get(sessionId);

    if (!session) {
      return null;
    }

    // Check if expired
    if (Date.now() > session.expiresAt) {
      this.destroySession(sessionId);
      return null;
    }

    // Update last activity
    session.lastActivity = Date.now();
    this.sessions.set(sessionId, session);

    return session;
  }

  /**
   * Update session state
   */
  updateSessionState(
    sessionId: string,
    state: Record<string, any>
  ): UserSession | null {
    const session = this.getSession(sessionId);

    if (!session) {
      logger.warn('Attempted to update non-existent session', { sessionId });
      return null;
    }

    session.state = {
      ...session.state,
      ...state,
    };

    session.lastActivity = Date.now();
    this.sessions.set(sessionId, session);

    return session;
  }

  /**
   * Increment action count and check rate limit
   */
  recordAction(sessionId: string): boolean {
    const session = this.getSession(sessionId);

    if (!session) {
      return false;
    }

    session.actionCount++;
    session.lastActivity = Date.now();

    // Check rate limit
    if (session.actionCount > this.maxActions) {
      logger.warn('Session exceeded max actions', {
        sessionId,
        userId: session.userId,
        actionCount: session.actionCount,
        maxActions: this.maxActions,
      });

      this.destroySession(sessionId);
      return false;
    }

    this.sessions.set(sessionId, session);
    return true;
  }

  /**
   * Extend session TTL
   */
  extendSession(sessionId: string, additionalTtl?: number): boolean {
    const session = this.getSession(sessionId);

    if (!session) {
      return false;
    }

    const extension = additionalTtl || this.ttl;
    session.expiresAt = Date.now() + extension;
    session.lastActivity = Date.now();

    this.sessions.set(sessionId, session);

    logger.info('Session extended', {
      sessionId,
      userId: session.userId,
      newExpiresAt: session.expiresAt,
    });

    return true;
  }

  /**
   * Destroy session
   */
  destroySession(sessionId: string): boolean {
    const session = this.sessions.get(sessionId);

    if (!session) {
      return false;
    }

    this.sessions.delete(sessionId);

    logger.info('Session destroyed', {
      sessionId,
      userId: session.userId,
      duration: Date.now() - session.createdAt,
      actionCount: session.actionCount,
    });

    return true;
  }

  /**
   * Get all sessions for a user
   */
  getUserSessions(userId: string): UserSession[] {
    const userSessions: UserSession[] = [];

    this.sessions.forEach((session) => {
      if (session.userId === userId) {
        userSessions.push(session);
      }
    });

    return userSessions;
  }

  /**
   * Destroy all sessions for a user
   */
  destroyUserSessions(userId: string): number {
    let count = 0;

    this.sessions.forEach((session, sessionId) => {
      if (session.userId === userId) {
        this.sessions.delete(sessionId);
        count++;
      }
    });

    logger.info('User sessions destroyed', { userId, count });

    return count;
  }

  /**
   * Get active session count
   */
  getActiveSessionCount(): number {
    return this.sessions.size;
  }

  /**
   * Get session statistics
   */
  getStatistics(): {
    activeSessions: number;
    averageActionCount: number;
    averageSessionDuration: number;
    oldestSession: number;
  } {
    let totalActions = 0;
    let totalDuration = 0;
    let oldestTimestamp = Date.now();
    const now = Date.now();

    this.sessions.forEach((session) => {
      totalActions += session.actionCount;
      totalDuration += now - session.createdAt;
      if (session.createdAt < oldestTimestamp) {
        oldestTimestamp = session.createdAt;
      }
    });

    const count = this.sessions.size;

    return {
      activeSessions: count,
      averageActionCount: count > 0 ? totalActions / count : 0,
      averageSessionDuration: count > 0 ? totalDuration / count : 0,
      oldestSession: count > 0 ? now - oldestTimestamp : 0,
    };
  }

  /**
   * Clean up expired sessions (called periodically)
   */
  cleanup(): number {
    const now = Date.now();
    let cleaned = 0;

    this.sessions.forEach((session, sessionId) => {
      if (now > session.expiresAt) {
        this.sessions.delete(sessionId);
        cleaned++;
      }
    });

    if (cleaned > 0) {
      logger.info('Session cleanup completed', { cleaned });
    }

    return cleaned;
  }
}

// Global session manager instance
export const sessionManager = new SessionManager({
  ttl: DEFAULT_TTL,
  maxActions: DEFAULT_MAX_ACTIONS,
});

// Run cleanup every 5 minutes
setInterval(() => {
  sessionManager.cleanup();
}, 5 * 60 * 1000);

/**
 * Session middleware for Express
 */
export function sessionMiddleware(
  req: any,
  _res: any,
  next: () => void
): void {
  const sessionId = req.headers['x-session-id'] as string;

  if (sessionId) {
    const session = sessionManager.getSession(sessionId);
    if (session) {
      req.session = session;
    }
  }

  next();
}

/**
 * Create session for Discord user
 */
export function createDiscordSession(
  discordUserId: string,
  metadata: Partial<UserSession['metadata']> = {}
): UserSession {
  return sessionManager.createSession(discordUserId, {
    ...metadata,
    platform: 'discord',
  });
}

/**
 * Example: Multi-step workflow state management
 */
export interface WorkflowState {
  step: number;
  totalSteps: number;
  data: Record<string, any>;
  completed: boolean;
}

export function initWorkflow(
  sessionId: string,
  totalSteps: number
): WorkflowState {
  const workflow: WorkflowState = {
    step: 1,
    totalSteps,
    data: {},
    completed: false,
  };

  sessionManager.updateSessionState(sessionId, { workflow });

  return workflow;
}

export function advanceWorkflow(
  sessionId: string,
  stepData: Record<string, any>
): WorkflowState | null {
  const session = sessionManager.getSession(sessionId);

  if (!session || !session.state['workflow']) {
    return null;
  }

  const workflow: WorkflowState = session.state['workflow'];
  workflow.data = { ...workflow.data, ...stepData };
  workflow.step++;

  if (workflow.step > workflow.totalSteps) {
    workflow.completed = true;
  }

  sessionManager.updateSessionState(sessionId, { workflow });

  return workflow;
}
