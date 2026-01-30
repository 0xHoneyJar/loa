/**
 * Legba - Autonomous Loa Sprint Execution Skill
 *
 * A Moltbot skill that enables chat-triggered sprint execution
 * on any project in an organization.
 */

import { parseCommand, isLegbaMessage } from './lib/command-parser.js';
import {
  SessionManager,
  createSessionManager,
  type SessionManagerConfig,
} from './lib/session-manager.js';
import { createStorage, type Storage } from './lib/storage.js';
import { createSandboxExecutor } from './lib/sandbox-executor.js';
import { createNotifier, type MoltbotContext } from './lib/notifier.js';
import { createGitHubClient, type GitHubClient } from './lib/github-client.js';
import { LegbaError, wrapError, isLegbaError } from './lib/errors.js';
import {
  validateCredentials,
  validateSessionId,
  validateCommand,
  MAX_INPUT_LENGTH,
} from './lib/validation.js';
import type {
  LegbaCommand,
  RunCommand,
  StatusCommand,
  ResumeCommand,
  AbortCommand,
  HistoryCommand,
  LogsCommand,
  ChatContext,
  Session,
  SessionState,
} from './types/index.js';

/**
 * Moltbot Skill interface
 */
export interface Message {
  text: string;
  from: {
    id: string;
    username?: string;
  };
}

export interface Context {
  platform: 'telegram' | 'discord';
  channelId: string;
  messageId: string;
  reply: (text: string) => Promise<void>;
  sendTo: (channelId: string, text: string, options?: { parseMode?: 'Markdown' | 'HTML'; replyToMessageId?: string }) => Promise<void>;
}

export interface Skill {
  name: string;
  description: string;
  triggers: RegExp[];
  handle: (message: Message, context: Context) => Promise<void>;
}

/**
 * Environment configuration
 */
export interface LegbaEnv {
  LEGBA_R2: R2Bucket;
  ANTHROPIC_API_KEY: string;
  GITHUB_TOKEN: string;
  GITHUB_APP_ID: string;
  GITHUB_APP_PRIVATE_KEY: string;
}

/**
 * R2 Bucket interface (Cloudflare Workers)
 */
interface R2Bucket {
  get(key: string): Promise<R2Object | null>;
  put(key: string, value: string | ReadableStream | ArrayBuffer): Promise<void>;
  delete(key: string): Promise<void>;
  list(options?: { prefix?: string }): Promise<{ objects: R2Object[] }>;
}

interface R2Object {
  key: string;
  text(): Promise<string>;
}

/**
 * Help text for the skill
 */
const HELP_TEXT = `
**Legba** - Autonomous Loa Sprint Execution

**Commands:**

\`legba run sprint-N on {project}\` - Execute sprint N on project
\`legba run sprint-N on {project} branch {branch}\` - Execute on specific branch
\`legba status\` - Show current session status
\`legba status {session-id}\` - Show specific session status
\`legba resume {session-id}\` - Resume paused session
\`legba abort {session-id}\` - Abort session
\`legba projects\` - List registered projects
\`legba history {project}\` - Show session history
\`legba logs {session-id}\` - Retrieve session logs
\`legba help\` - Show this help

**Examples:**
\`\`\`
legba run sprint-3 on myproject
legba run sprint-2 on myproject branch feature/auth
legba status
legba resume abc123
\`\`\`
`.trim();

/**
 * Format session state for display
 */
function formatState(state: SessionState): string {
  const stateEmoji: Record<SessionState, string> = {
    QUEUED: '⏳',
    STARTING: '🚀',
    CLONING: '📥',
    RUNNING: '⚙️',
    PAUSED: '⏸️',
    COMPLETING: '📝',
    COMPLETED: '✅',
    FAILED: '❌',
    ABORTED: '🛑',
  };
  return `${stateEmoji[state] || ''} ${state}`;
}

/**
 * Format duration in human-readable form
 */
function formatDuration(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);

  if (hours > 0) {
    return `${hours}h ${minutes % 60}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  }
  return `${seconds}s`;
}

/**
 * Format session for display
 */
function formatSession(session: Session): string {
  const lines: string[] = [
    `**Session**: \`${session.id}\``,
    `**Project**: \`${session.project}\``,
    `**Sprint**: ${session.sprint}`,
    `**Branch**: \`${session.branch}\``,
    `**State**: ${formatState(session.state)}`,
    `**Triggered by**: ${session.triggeredBy}`,
  ];

  if (session.startedAt) {
    const duration = session.completedAt
      ? new Date(session.completedAt).getTime() - new Date(session.startedAt).getTime()
      : Date.now() - new Date(session.startedAt).getTime();
    lines.push(`**Duration**: ${formatDuration(duration)}`);
  }

  if (session.state === 'PAUSED' && session.pauseReason) {
    lines.push('');
    lines.push(`**Pause Reason**: ${session.pauseReason}`);
    lines.push('');
    lines.push('**Options**:');
    lines.push(`- Resume: \`legba resume ${session.id}\``);
    lines.push(`- Abort: \`legba abort ${session.id}\``);
    lines.push(`- View logs: \`legba logs ${session.id}\``);
  }

  if (session.state === 'COMPLETED' && session.prUrl) {
    lines.push('');
    lines.push(`**Draft PR**: ${session.prUrl}`);
  }

  if (session.state === 'FAILED' && session.error) {
    lines.push('');
    lines.push(`**Error**: ${session.error}`);
    lines.push(`View logs: \`legba logs ${session.id}\``);
  }

  if (session.metrics.filesChanged > 0) {
    lines.push('');
    lines.push('**Metrics**:');
    lines.push(`- Files changed: ${session.metrics.filesChanged}`);
    lines.push(`- Lines added: ${session.metrics.linesAdded}`);
    lines.push(`- Lines removed: ${session.metrics.linesRemoved}`);
  }

  return lines.join('\n');
}

/**
 * Legba Skill implementation
 */
class LegbaSkill implements Skill {
  name = 'legba';
  description = 'Autonomous Loa sprint execution';
  triggers = [/^legba\s+/i, /^\/legba\s*/i];

  private sessionManager: SessionManager | null = null;
  private storage: Storage | null = null;
  private githubClient: GitHubClient | null = null;
  private initialized = false;

  /** Validated credentials (stored after initialization) */
  private credentials: {
    anthropicKey: string;
    githubToken: string;
    githubAppId: string;
    githubAppPrivateKey: string;
  } | null = null;

  /**
   * Initialize the skill with environment configuration
   *
   * @throws Error if required credentials are missing
   */
  initialize(env: LegbaEnv): void {
    if (this.initialized) return;

    // C-001 FIX: Validate all required credentials at initialization
    // Fail fast if any are missing instead of using empty fallbacks
    const credentialValidation = validateCredentials([
      { name: 'ANTHROPIC_API_KEY', value: env.ANTHROPIC_API_KEY, required: true },
      { name: 'GITHUB_TOKEN', value: env.GITHUB_TOKEN, required: true },
      { name: 'GITHUB_APP_ID', value: env.GITHUB_APP_ID, required: true },
      { name: 'GITHUB_APP_PRIVATE_KEY', value: env.GITHUB_APP_PRIVATE_KEY, required: true },
    ]);

    if (!credentialValidation.valid) {
      throw new Error(`Legba initialization failed: ${credentialValidation.error}`);
    }

    // Store validated credentials for later use
    this.credentials = {
      anthropicKey: env.ANTHROPIC_API_KEY,
      githubToken: env.GITHUB_TOKEN,
      githubAppId: env.GITHUB_APP_ID,
      githubAppPrivateKey: env.GITHUB_APP_PRIVATE_KEY,
    };

    this.storage = createStorage(env.LEGBA_R2);

    // Create GitHub client once at initialization with validated credentials
    this.githubClient = createGitHubClient({
      appId: this.credentials.githubAppId,
      privateKey: this.credentials.githubAppPrivateKey,
    });

    this.initialized = true;
  }

  /**
   * Handle incoming messages
   */
  async handle(message: Message, context: Context): Promise<void> {
    // Check if this is a Legba message
    if (!isLegbaMessage(message.text)) {
      return;
    }

    // L-001 FIX: Validate input length to prevent DoS via regex backtracking
    const commandValidation = validateCommand(message.text);
    if (!commandValidation.valid) {
      await context.reply(
        `Invalid input: ${commandValidation.error}. Maximum length is ${MAX_INPUT_LENGTH} characters.`
      );
      return;
    }

    // Parse the command
    const command = parseCommand(message.text);
    if (!command) {
      await context.reply(
        'I didn\'t understand that command. Try `legba help` for usage.'
      );
      return;
    }

    // Create Moltbot context for notifier
    const moltbotContext: MoltbotContext = {
      reply: context.reply,
      sendTo: context.sendTo,
    };

    // Route to appropriate handler
    try {
      switch (command.type) {
        case 'run':
          await this.handleRun(command, message, context, moltbotContext);
          break;
        case 'status':
          await this.handleStatus(command, context);
          break;
        case 'resume':
          await this.handleResume(command, message, context);
          break;
        case 'abort':
          await this.handleAbort(command, message, context);
          break;
        case 'projects':
          await this.handleProjects(context);
          break;
        case 'history':
          await this.handleHistory(command, context);
          break;
        case 'logs':
          await this.handleLogs(command, message, context);
          break;
        case 'help':
          await this.handleHelp(context);
          break;
      }
    } catch (error) {
      if (isLegbaError(error)) {
        await context.reply(error.toUserMessage());
      } else {
        const wrapped = wrapError(error);
        await context.reply(wrapped.toUserMessage());
      }
    }
  }

  /**
   * Handle run command - Execute a sprint on a project
   */
  private async handleRun(
    command: RunCommand,
    message: Message,
    context: Context,
    moltbotContext: MoltbotContext
  ): Promise<void> {
    // C-001 FIX: Verify initialization with validated credentials
    if (!this.storage || !this.credentials || !this.githubClient) {
      throw new LegbaError('E011', 'Skill not initialized. Call initialize() first.');
    }

    // Create session manager with the current context's notifier
    // Using validated credentials from initialization (no empty fallbacks)
    const notifier = createNotifier(moltbotContext);
    const sandboxExecutor = createSandboxExecutor();

    const sessionManager = createSessionManager({
      storage: this.storage,
      sandboxExecutor,
      notifier,
      githubClient: this.githubClient,
      r2Bucket: {},
      anthropicKey: this.credentials.anthropicKey,
      githubToken: this.credentials.githubToken,
    });

    // Create chat context
    const chatContext: ChatContext = {
      platform: context.platform,
      channelId: context.channelId,
      messageId: context.messageId,
      userId: message.from.id,
    };

    // Get username for triggered by
    const triggeredBy = message.from.username || message.from.id;

    // Start the session
    const session = await sessionManager.startSession(
      command,
      chatContext,
      triggeredBy
    );

    // If session is queued, notification was already sent by notifier
    // If session started, notification was already sent by notifier
    // So we don't need to send additional messages here
  }

  /**
   * Handle status command - Show session status
   */
  private async handleStatus(
    command: StatusCommand,
    context: Context
  ): Promise<void> {
    if (!this.storage) {
      throw new LegbaError('E011', 'Skill not initialized');
    }

    if (command.sessionId) {
      // Get specific session
      const session = await this.storage.getSession(command.sessionId);
      if (!session) {
        throw new LegbaError('E009');
      }
      await context.reply(formatSession(session));
    } else {
      // Get current/recent sessions
      const sessions = await this.storage.listSessions();

      // Find active session (non-terminal state)
      const active = sessions.find(
        (s) => !['COMPLETED', 'FAILED', 'ABORTED'].includes(s.state)
      );

      if (active) {
        await context.reply(
          `**Current Active Session**\n\n${formatSession(active)}`
        );
      } else if (sessions.length > 0) {
        // Show most recent session
        const recent = sessions.sort((a, b) =>
          (b.completedAt || b.startedAt || '') > (a.completedAt || a.startedAt || '') ? 1 : -1
        )[0];
        await context.reply(
          `**No active session**\n\nMost recent session:\n\n${formatSession(recent)}`
        );
      } else {
        await context.reply(
          `**No active session**\n\nNo sessions have been run yet. Start one with:\n\`legba run sprint-N on {project}\``
        );
      }
    }
  }

  /**
   * Handle resume command - Continue a paused session
   */
  private async handleResume(
    command: ResumeCommand,
    message: Message,
    context: Context
  ): Promise<void> {
    // C-001 FIX: Verify initialization
    if (!this.storage || !this.credentials || !this.githubClient) {
      throw new LegbaError('E011', 'Skill not initialized');
    }

    // H-001 FIX: Validate session ID format
    const sessionValidation = validateSessionId(command.sessionId);
    if (!sessionValidation.valid) {
      throw new LegbaError('E009', sessionValidation.error);
    }

    const session = await this.storage.getSession(command.sessionId);
    if (!session) {
      throw new LegbaError('E009');
    }

    // H-003 FIX: Authorization check - verify user owns the session or has admin privileges
    const requestingUserId = message.from.id;
    const requestingUsername = message.from.username || message.from.id;
    if (!this.isAuthorizedForSession(session, requestingUserId, requestingUsername)) {
      throw new LegbaError(
        'E010',
        'You are not authorized to resume this session. Only the session owner can resume it.'
      );
    }

    if (session.state !== 'PAUSED') {
      throw new LegbaError(
        'E010',
        `Session is in state ${session.state}, not PAUSED`
      );
    }

    // Create session manager to handle resume using validated credentials
    const moltbotContext: MoltbotContext = {
      reply: context.reply,
      sendTo: context.sendTo,
    };
    const notifier = createNotifier(moltbotContext);
    const sandboxExecutor = createSandboxExecutor();

    const sessionManager = createSessionManager({
      storage: this.storage,
      sandboxExecutor,
      notifier,
      githubClient: this.githubClient,
      r2Bucket: {},
      anthropicKey: this.credentials.anthropicKey,
      githubToken: this.credentials.githubToken,
    });

    await sessionManager.resumeSession(command.sessionId);

    await context.reply(
      `Resuming session \`${command.sessionId}\`...\n\n` +
      `Sprint ${session.sprint} on \`${session.project}\` will continue from where it paused.`
    );
  }

  /**
   * Handle abort command - Cancel a session
   */
  private async handleAbort(
    command: AbortCommand,
    message: Message,
    context: Context
  ): Promise<void> {
    // C-001 FIX: Verify initialization
    if (!this.storage || !this.credentials || !this.githubClient) {
      throw new LegbaError('E011', 'Skill not initialized');
    }

    // H-001 FIX: Validate session ID format
    const sessionValidation = validateSessionId(command.sessionId);
    if (!sessionValidation.valid) {
      throw new LegbaError('E009', sessionValidation.error);
    }

    const session = await this.storage.getSession(command.sessionId);
    if (!session) {
      throw new LegbaError('E009');
    }

    // H-003 FIX: Authorization check - verify user owns the session or has admin privileges
    const requestingUserId = message.from.id;
    const requestingUsername = message.from.username || message.from.id;
    if (!this.isAuthorizedForSession(session, requestingUserId, requestingUsername)) {
      throw new LegbaError(
        'E010',
        'You are not authorized to abort this session. Only the session owner can abort it.'
      );
    }

    const terminalStates: SessionState[] = ['COMPLETED', 'FAILED', 'ABORTED'];
    if (terminalStates.includes(session.state)) {
      throw new LegbaError(
        'E010',
        `Session is already in terminal state ${session.state}`
      );
    }

    // Create session manager to handle abort using validated credentials
    const moltbotContext: MoltbotContext = {
      reply: context.reply,
      sendTo: context.sendTo,
    };
    const notifier = createNotifier(moltbotContext);
    const sandboxExecutor = createSandboxExecutor();

    const sessionManager = createSessionManager({
      storage: this.storage,
      sandboxExecutor,
      notifier,
      githubClient: this.githubClient,
      r2Bucket: {},
      anthropicKey: this.credentials.anthropicKey,
      githubToken: this.credentials.githubToken,
    });

    await sessionManager.abortSession(command.sessionId);

    await context.reply(
      `Session \`${command.sessionId}\` has been aborted.\n\n` +
      `Sprint ${session.sprint} on \`${session.project}\` was cancelled.\n\n` +
      `View logs: \`legba logs ${command.sessionId}\``
    );
  }

  /**
   * Handle projects command - List registered projects
   */
  private async handleProjects(context: Context): Promise<void> {
    if (!this.storage) {
      throw new LegbaError('E011', 'Skill not initialized');
    }

    const registry = await this.storage.getRegistry();

    if (!registry || registry.projects.length === 0) {
      await context.reply(
        `**Registered Projects**\n\n` +
        `*No projects registered yet*\n\n` +
        `Projects are configured in the Legba registry.`
      );
      return;
    }

    const projects = registry.projects;
    const lines: string[] = ['**Registered Projects**\n'];

    for (const project of projects) {
      const status = project.enabled ? '✅' : '❌';
      lines.push(
        `${status} **${project.name}** (\`${project.id}\`)\n` +
        `   Repo: ${project.repoUrl}\n` +
        `   Default branch: \`${project.defaultBranch}\``
      );
    }

    await context.reply(lines.join('\n'));
  }

  /**
   * Handle history command - Show session history for a project
   */
  private async handleHistory(
    command: HistoryCommand,
    context: Context
  ): Promise<void> {
    if (!this.storage) {
      throw new LegbaError('E011', 'Skill not initialized');
    }

    const sessions = await this.storage.listSessions();
    const projectSessions = command.project
      ? sessions.filter((s) => s.project === command.project)
      : sessions;

    if (projectSessions.length === 0) {
      const projectFilter = command.project
        ? ` for \`${command.project}\``
        : '';
      await context.reply(
        `**Session History${projectFilter}**\n\n` +
        `*No sessions yet*`
      );
      return;
    }

    // Sort by most recent first
    const sorted = projectSessions.sort((a, b) =>
      (b.completedAt || b.startedAt || '') > (a.completedAt || a.startedAt || '') ? 1 : -1
    );

    // Take last 10
    const recent = sorted.slice(0, 10);

    const projectFilter = command.project
      ? ` for \`${command.project}\``
      : '';
    const lines: string[] = [`**Session History${projectFilter}**\n`];

    for (const session of recent) {
      const date = session.completedAt || session.startedAt || 'unknown';
      const shortDate = date.split('T')[0];
      const state = formatState(session.state);
      const prLink = session.prUrl ? ` • [PR](${session.prUrl})` : '';

      lines.push(
        `\`${session.id.slice(0, 8)}\` | Sprint ${session.sprint} | ${state} | ${shortDate}${prLink}`
      );
    }

    if (sorted.length > 10) {
      lines.push(`\n*Showing 10 of ${sorted.length} sessions*`);
    }

    await context.reply(lines.join('\n'));
  }

  /**
   * Handle logs command - Retrieve session logs
   */
  private async handleLogs(
    command: LogsCommand,
    message: Message,
    context: Context
  ): Promise<void> {
    if (!this.storage) {
      throw new LegbaError('E011', 'Skill not initialized');
    }

    // H-001 FIX: Validate session ID format
    const sessionValidation = validateSessionId(command.sessionId);
    if (!sessionValidation.valid) {
      throw new LegbaError('E009', sessionValidation.error);
    }

    const session = await this.storage.getSession(command.sessionId);
    if (!session) {
      throw new LegbaError('E009');
    }

    // H-003/M-002 FIX: Authorization check - restrict log access to session owner
    // Logs may contain sensitive information, so we limit access
    const requestingUserId = message.from.id;
    const requestingUsername = message.from.username || message.from.id;
    if (!this.isAuthorizedForSession(session, requestingUserId, requestingUsername)) {
      throw new LegbaError(
        'E010',
        'You are not authorized to view logs for this session.'
      );
    }

    const logs = await this.storage.getLog(command.sessionId, 'claude-output');
    if (!logs) {
      await context.reply(
        `**Logs for session \`${command.sessionId}\`**\n\n` +
        `*No logs available yet*\n\n` +
        `Session state: ${formatState(session.state)}`
      );
      return;
    }

    // Get last N lines
    const lines = logs.split('\n');
    const limit = command.lines || 100;
    const tail = lines.slice(-limit);
    const truncated = lines.length > limit;

    const stateNote = ['RUNNING', 'CLONING', 'STARTING'].includes(session.state)
      ? '\n\n*Session is still running - logs may be incomplete*'
      : '';

    const truncatedNote = truncated
      ? `\n\n*Showing last ${limit} of ${lines.length} lines*`
      : '';

    await context.reply(
      `**Logs for session \`${command.sessionId}\`**\n\n` +
      '```\n' +
      tail.join('\n') +
      '\n```' +
      stateNote +
      truncatedNote
    );
  }

  /**
   * H-003 FIX: Check if a user is authorized to perform operations on a session
   *
   * Authorization rules:
   * 1. The user who triggered the session is always authorized
   * 2. Users with matching username (case-insensitive) are authorized
   * 3. TODO: Add admin/role-based access in future
   */
  private isAuthorizedForSession(
    session: Session,
    requestingUserId: string,
    requestingUsername: string
  ): boolean {
    // Check if the requesting user matches the session triggeredBy field
    // The triggeredBy field contains either username or user ID
    const sessionOwner = session.triggeredBy.toLowerCase();
    const requestingIdLower = requestingUserId.toLowerCase();
    const requestingUsernameLower = requestingUsername.toLowerCase();

    // Match by user ID or username
    if (sessionOwner === requestingIdLower || sessionOwner === requestingUsernameLower) {
      return true;
    }

    // Check chat context if available
    if (session.chatContext?.userId === requestingUserId) {
      return true;
    }

    return false;
  }

  /**
   * Handle help command - Show help text
   */
  private async handleHelp(context: Context): Promise<void> {
    await context.reply(HELP_TEXT);
  }
}

/**
 * Export the skill instance
 */
export default new LegbaSkill();

/**
 * Export the skill class for testing
 */
export { LegbaSkill };

/**
 * Re-export types and utilities
 */
export * from './types/index.js';
export { parseCommand, isLegbaMessage, formatCommand } from './lib/command-parser.js';
export {
  SessionStateMachine,
  InvalidTransitionError,
  isValidTransition,
  getValidTransitions,
} from './lib/state-machine.js';
export { LegbaError, isLegbaError, wrapError } from './lib/errors.js';
