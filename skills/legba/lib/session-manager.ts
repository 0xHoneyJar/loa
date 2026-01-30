/**
 * Legba Session Manager
 *
 * Orchestrates the session lifecycle from trigger to completion.
 */

import { v4 as uuidv4 } from 'uuid';
import {
  SessionStateMachine,
  InvalidTransitionError,
} from './state-machine.js';
import { type Storage } from './storage.js';
import {
  type SandboxExecutor,
  type ExecutionConfig,
  type ExecutionResult,
} from './sandbox-executor.js';
import type {
  Session,
  SessionState,
  ChatContext,
  RunCommand,
  Project,
  QueuedRequest,
} from '../types/index.js';
import { createSession, createDefaultMetrics } from '../types/index.js';
import { redactSecrets } from './validation.js';

/**
 * Notifier interface for chat notifications
 */
export interface Notifier {
  notifyStarted(session: Session): Promise<void>;
  notifyCompleted(session: Session, prUrl: string): Promise<void>;
  notifyPaused(session: Session, reason: string): Promise<void>;
  notifyFailed(session: Session, error: string): Promise<void>;
  notifyQueued(session: Session, position: number): Promise<void>;
}

/**
 * GitHub client interface for PR creation
 */
export interface GitHubClient {
  createDraftPR(params: {
    project: Project;
    sessionId: string;
    sprint: number;
    branch: string;
    diff: string;
    summary: string;
    triggeredBy: string;
    duration: number;
  }): Promise<{ url: string; number: number }>;
}

/**
 * Error codes
 */
export const ErrorCodes = {
  E001: 'Project not found',
  E002: 'Project disabled',
  E003: 'Session already active',
  E004: 'Queue full',
  E005: 'GitHub App not installed',
  E006: 'Clone failed',
  E007: 'Circuit breaker tripped',
  E008: 'Session timeout',
} as const;

export type ErrorCode = keyof typeof ErrorCodes;

/**
 * Session manager error
 */
export class SessionError extends Error {
  constructor(
    public code: ErrorCode,
    message?: string
  ) {
    super(message ?? ErrorCodes[code]);
    this.name = 'SessionError';
  }
}

/**
 * Session Manager Configuration
 */
export interface SessionManagerConfig {
  storage: Storage;
  sandboxExecutor: SandboxExecutor;
  notifier: Notifier;
  githubClient: GitHubClient;
  r2Bucket: unknown;
  anthropicKey: string;
  githubToken: string;
}

/**
 * Session Manager
 *
 * Orchestrates the complete session lifecycle.
 */
export class SessionManager {
  private storage: Storage;
  private sandboxExecutor: SandboxExecutor;
  private notifier: Notifier;
  private githubClient: GitHubClient;
  private r2Bucket: unknown;
  private anthropicKey: string;
  private githubToken: string;

  /** Currently active session (if any) */
  private activeSession: Session | null = null;

  /**
   * H-002 FIX: Session operation lock
   * Uses a simple in-memory lock for single-instance deployments.
   * For multi-instance deployments, use storage.acquireLock() instead.
   */
  private sessionLock: Promise<void> = Promise.resolve();
  private lockQueue: Array<() => void> = [];

  constructor(config: SessionManagerConfig) {
    this.storage = config.storage;
    this.sandboxExecutor = config.sandboxExecutor;
    this.notifier = config.notifier;
    this.githubClient = config.githubClient;
    this.r2Bucket = config.r2Bucket;
    this.anthropicKey = config.anthropicKey;
    this.githubToken = config.githubToken;
  }

  /**
   * H-002 FIX: Acquire lock for session operations
   * Returns a release function that must be called when done
   */
  private async acquireLock(): Promise<() => void> {
    return new Promise((resolve) => {
      const executeWithLock = async () => {
        // Create a new lock promise
        let releaseLock: () => void;
        const newLockPromise = new Promise<void>((resolveInner) => {
          releaseLock = resolveInner;
        });

        // Replace the current lock
        const previousLock = this.sessionLock;
        this.sessionLock = newLockPromise;

        // Wait for the previous lock to be released
        await previousLock;

        // Return the release function
        resolve(() => {
          releaseLock();
        });
      };

      executeWithLock();
    });
  }

  /**
   * Start a new session
   *
   * H-002 FIX: Uses locking to prevent race conditions in session management
   */
  async startSession(
    command: RunCommand,
    chatContext: ChatContext,
    triggeredBy: string
  ): Promise<Session> {
    // H-002 FIX: Acquire lock before checking/modifying session state
    const releaseLock = await this.acquireLock();

    try {
      // 1. Validate project exists and is enabled
      const project = await this.storage.getProject(command.project);
      if (!project) {
        throw new SessionError('E001');
      }
      if (!project.enabled) {
        throw new SessionError('E002');
      }

      // 2. Check for active session (within lock to prevent race condition)
      // H-002 FIX: Also check storage for any active sessions (handles multi-instance case)
      const storedSessions = await this.storage.listSessions();
      const activeStoredSession = storedSessions.find(
        (s) => !this.isTerminalState(s.state)
      );

      if (
        (this.activeSession && !this.isTerminalState(this.activeSession.state)) ||
        activeStoredSession
      ) {
        // Queue the request
        const request: QueuedRequest = {
          id: uuidv4(),
          project: command.project,
          sprint: command.sprint,
          branch: command.branch ?? project.defaultBranch,
          chatContext,
          triggeredBy,
          queuedAt: new Date().toISOString(),
        };

        const position = await this.storage.enqueue(request);
        if (position < 0) {
          throw new SessionError('E004');
        }

        // Create a queued session record
        const session = createSession(
          request.id,
          command.project,
          command.sprint,
          request.branch,
          chatContext,
          triggeredBy
        );

        await this.storage.saveSession(session);
        await this.notifier.notifyQueued(session, position);

        return session;
      }

      // 3. Create session record
      const session = createSession(
        uuidv4(),
        command.project,
        command.sprint,
        command.branch ?? project.defaultBranch,
        chatContext,
        triggeredBy
      );

      // H-002 FIX: Set active session and persist BEFORE releasing lock
      this.activeSession = session;
      await this.storage.saveSession(session);

      // 4. Notify user of start
      await this.notifier.notifyStarted(session);

      // 5. Execute asynchronously (don't await - return immediately)
      // Note: Lock is released before execution starts
      this.executeSession(session, project).catch((error) => {
        // Handle async errors
        console.error('Session execution failed:', error);
      });

      return session;
    } finally {
      // H-002 FIX: Always release lock
      releaseLock();
    }
  }

  /**
   * Execute a session (called asynchronously)
   */
  private async executeSession(session: Session, project: Project): Promise<void> {
    const stateMachine = new SessionStateMachine(session.state);

    try {
      // Transition to STARTING
      await this.transitionState(session, stateMachine, 'STARTING');

      // Transition to CLONING
      await this.transitionState(session, stateMachine, 'CLONING');

      // Transition to RUNNING
      await this.transitionState(session, stateMachine, 'RUNNING');
      session.startedAt = new Date().toISOString();
      await this.storage.saveSession(session);

      // Execute in sandbox
      const config: ExecutionConfig = {
        sessionId: session.id,
        project: session.project,
        sprint: session.sprint,
        branch: session.branch,
        repoUrl: project.repoUrl,
        r2Bucket: this.r2Bucket,
        anthropicKey: this.anthropicKey,
        githubToken: this.githubToken,
      };

      const result = await this.sandboxExecutor.execute(config);

      // M-002 FIX: Store logs with secrets redacted
      const sanitizedLogs = redactSecrets(result.logs);
      await this.storage.appendLog(session.id, 'claude-output', sanitizedLogs);

      // Check for circuit breaker
      if (result.circuitBreaker.tripped) {
        await this.pauseSession(session, stateMachine, result.circuitBreaker.reason!);
        return;
      }

      // Check for failure
      if (!result.success) {
        await this.failSession(session, stateMachine, `Execution failed with exit code ${result.exitCode}`);
        return;
      }

      // Transition to COMPLETING
      await this.transitionState(session, stateMachine, 'COMPLETING');

      // Create draft PR
      const pr = await this.githubClient.createDraftPR({
        project,
        sessionId: session.id,
        sprint: session.sprint,
        branch: session.branch,
        diff: result.diff,
        summary: this.extractSummary(result.logs),
        triggeredBy: session.triggeredBy,
        duration: result.duration,
      });

      // Update session with PR URL
      session.prUrl = pr.url;
      session.metrics = this.extractMetrics(result);
      session.completedAt = new Date().toISOString();

      // Transition to COMPLETED
      await this.transitionState(session, stateMachine, 'COMPLETED');

      // Notify user
      await this.notifier.notifyCompleted(session, pr.url);

      // Process queue
      await this.processQueue();
    } catch (error) {
      // Handle unexpected errors
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      await this.failSession(session, stateMachine, errorMessage);
    } finally {
      // Clear active session if this was it
      if (this.activeSession?.id === session.id) {
        this.activeSession = null;
      }
    }
  }

  /**
   * Transition session state
   */
  private async transitionState(
    session: Session,
    stateMachine: SessionStateMachine,
    newState: SessionState
  ): Promise<void> {
    stateMachine.transition(newState);
    session.state = newState;
    await this.storage.saveSession(session);
  }

  /**
   * Pause a session (circuit breaker tripped)
   */
  private async pauseSession(
    session: Session,
    stateMachine: SessionStateMachine,
    reason: string
  ): Promise<void> {
    stateMachine.transition('PAUSED');
    session.state = 'PAUSED';
    session.pausedAt = new Date().toISOString();
    session.pauseReason = reason;
    await this.storage.saveSession(session);
    await this.notifier.notifyPaused(session, reason);
  }

  /**
   * Fail a session
   */
  private async failSession(
    session: Session,
    stateMachine: SessionStateMachine,
    error: string
  ): Promise<void> {
    try {
      stateMachine.transition('FAILED');
    } catch {
      // May already be in a terminal state
    }
    session.state = 'FAILED';
    session.error = error;
    session.completedAt = new Date().toISOString();
    await this.storage.saveSession(session);
    await this.notifier.notifyFailed(session, error);
  }

  /**
   * Resume a paused session
   *
   * M-005 FIX: Properly save state before starting execution
   * H-002 FIX: Uses locking to prevent concurrent resumes
   */
  async resumeSession(sessionId: string): Promise<Session> {
    // H-002 FIX: Acquire lock to prevent concurrent resume operations
    const releaseLock = await this.acquireLock();

    try {
      const session = await this.storage.getSession(sessionId);
      if (!session) {
        throw new SessionError('E001', 'Session not found');
      }

      if (session.state !== 'PAUSED') {
        throw new Error(`Cannot resume session in state ${session.state}`);
      }

      // H-002 FIX: Check if there's already an active session
      if (this.activeSession && !this.isTerminalState(this.activeSession.state)) {
        throw new Error('Cannot resume: another session is already active');
      }

      const project = await this.storage.getProject(session.project);
      if (!project) {
        throw new SessionError('E001');
      }

      // M-005 FIX: Clear pause state and save BEFORE starting execution
      session.pausedAt = undefined;
      session.pauseReason = undefined;
      session.state = 'RUNNING'; // Explicitly set state before execution

      // M-005 FIX: Persist updated state before execution
      await this.storage.saveSession(session);

      this.activeSession = session;

      // Re-execute (will start from RUNNING state)
      this.executeSession(session, project).catch((error) => {
        console.error('Session resume failed:', error);
      });

      return session;
    } finally {
      // H-002 FIX: Always release lock
      releaseLock();
    }
  }

  /**
   * Abort a session
   */
  async abortSession(sessionId: string): Promise<Session> {
    const session = await this.storage.getSession(sessionId);
    if (!session) {
      throw new SessionError('E001', 'Session not found');
    }

    const stateMachine = new SessionStateMachine(session.state);
    if (!stateMachine.canAbort()) {
      throw new Error(`Cannot abort session in state ${session.state}`);
    }

    stateMachine.transition('ABORTED');
    session.state = 'ABORTED';
    session.completedAt = new Date().toISOString();
    await this.storage.saveSession(session);

    // Clear active session if this was it
    if (this.activeSession?.id === sessionId) {
      this.activeSession = null;
    }

    // Process queue
    await this.processQueue();

    return session;
  }

  /**
   * Get session status
   */
  async getStatus(sessionId?: string): Promise<Session | null> {
    if (sessionId) {
      return this.storage.getSession(sessionId);
    }
    return this.activeSession;
  }

  /**
   * Process the queue after a session completes
   */
  private async processQueue(): Promise<void> {
    if (this.activeSession) {
      return; // Still have an active session
    }

    const request = await this.storage.dequeue();
    if (!request) {
      return; // Queue empty
    }

    // Start the queued session
    const command: RunCommand = {
      type: 'run',
      project: request.project,
      sprint: request.sprint,
      branch: request.branch,
    };

    // Update the existing session record
    const session = await this.storage.getSession(request.id);
    if (session) {
      this.activeSession = session;
      const project = await this.storage.getProject(session.project);
      if (project) {
        await this.notifier.notifyStarted(session);
        this.executeSession(session, project).catch((error) => {
          console.error('Queued session execution failed:', error);
        });
      }
    }
  }

  /**
   * Check if a state is terminal
   */
  private isTerminalState(state: SessionState): boolean {
    return ['COMPLETED', 'FAILED', 'ABORTED'].includes(state);
  }

  /**
   * Extract summary from execution logs
   */
  private extractSummary(logs: string): string {
    // Look for summary sections in the logs
    const summaryMatch = logs.match(/## Summary\n([\s\S]*?)(?=\n##|$)/i);
    if (summaryMatch) {
      return summaryMatch[1].trim();
    }

    // Fall back to last 500 characters
    return logs.slice(-500).trim();
  }

  /**
   * Extract metrics from execution result
   */
  private extractMetrics(result: ExecutionResult): Session['metrics'] {
    const metrics = createDefaultMetrics();
    metrics.duration = result.duration;

    // Count files changed from diff
    const fileMatches = result.diff.match(/^diff --git/gm);
    if (fileMatches) {
      metrics.filesChanged = fileMatches.length;
    }

    // Count lines added/removed
    const addedMatches = result.diff.match(/^\+[^+]/gm);
    const removedMatches = result.diff.match(/^-[^-]/gm);
    metrics.linesAdded = addedMatches?.length ?? 0;
    metrics.linesRemoved = removedMatches?.length ?? 0;

    // Try to extract test results
    const testsMatch = result.logs.match(/(\d+)\s+tests?\s+(passed|passing)/i);
    if (testsMatch) {
      metrics.testsPassed = parseInt(testsMatch[1], 10);
      metrics.testsRun = metrics.testsPassed;
    }

    return metrics;
  }
}

/**
 * Create a session manager
 */
export function createSessionManager(config: SessionManagerConfig): SessionManager {
  return new SessionManager(config);
}
