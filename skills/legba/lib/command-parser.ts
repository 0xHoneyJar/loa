/**
 * Legba Command Parser
 *
 * Parses natural language chat messages into structured commands.
 */

import type { LegbaCommand } from '../types/index.js';
import {
  validateProjectId,
  validateSessionId,
  validateBranchName,
  validateSprintNumber,
  MAX_INPUT_LENGTH,
  MIN_SPRINT,
  MAX_SPRINT,
} from './validation.js';

/**
 * H-001 FIX: Stricter regular expression patterns for command parsing
 *
 * Key changes:
 * - Project IDs: lowercase alphanumeric with hyphens, 2-64 chars
 * - Session IDs: UUID v4 format only
 * - Branch names: Git-safe characters only
 * - Sprint numbers: Validated against bounds
 */
const PATTERNS = {
  // legba run sprint-3 on myproject
  // legba run sprint 3 on myproject
  // legba run sprint-03 on myproject branch feature/x
  // H-001 FIX: Use stricter patterns for project ID (lowercase alphanumeric + hyphens)
  // and branch name (git-safe characters)
  run: /^legba\s+run\s+sprint[- ]?(\d{1,4})\s+on\s+([a-z0-9][a-z0-9-]{0,62}[a-z0-9]|[a-z0-9]{1,2})(?:\s+branch\s+([a-zA-Z0-9._/-]+))?$/i,

  // legba status
  // legba status abc123 or legba status UUID
  // H-001 FIX: Session ID must be UUID format or short ID (8 hex chars)
  status: /^legba\s+status(?:\s+([a-f0-9-]{8,36}))?$/i,

  // legba resume {uuid}
  // H-001 FIX: Require UUID format for session ID
  resume: /^legba\s+resume\s+([a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12})$/i,

  // legba abort {uuid}
  // H-001 FIX: Require UUID format for session ID
  abort: /^legba\s+abort\s+([a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12})$/i,

  // legba projects
  projects: /^legba\s+projects$/i,

  // legba history myproject
  // H-001 FIX: Strict project ID pattern
  history: /^legba\s+history\s+([a-z0-9][a-z0-9-]{0,62}[a-z0-9]|[a-z0-9]{1,2})$/i,

  // legba logs {uuid}
  // H-001 FIX: Require UUID format for session ID
  logs: /^legba\s+logs\s+([a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12})$/i,

  // legba help
  // legba
  help: /^legba(?:\s+help)?$/i,
};

/**
 * Parse a chat message into a Legba command.
 *
 * @param message - The raw message text from chat
 * @returns The parsed command, or null if not recognized
 *
 * @example
 * parseCommand('legba run sprint-3 on myproject')
 * // => { type: 'run', project: 'myproject', sprint: 3 }
 *
 * @example
 * parseCommand('legba status')
 * // => { type: 'status' }
 *
 * @example
 * parseCommand('hello world')
 * // => null
 */
export function parseCommand(message: string): LegbaCommand | null {
  // L-001 FIX: Validate input length before regex processing
  if (message.length > MAX_INPUT_LENGTH) {
    return null;
  }

  // Normalize whitespace
  const normalized = message.trim().replace(/\s+/g, ' ');

  // Try run command
  const runMatch = normalized.match(PATTERNS.run);
  if (runMatch) {
    const sprint = parseInt(runMatch[1], 10);

    // L-002 FIX: Validate sprint number range
    if (sprint < MIN_SPRINT || sprint > MAX_SPRINT) {
      return null;
    }

    const project = runMatch[2].toLowerCase(); // Normalize to lowercase

    // H-001 FIX: Additional validation for project ID
    const projectValidation = validateProjectId(project);
    if (!projectValidation.valid) {
      return null;
    }

    // H-001 FIX: Validate branch if provided
    const branch = runMatch[3];
    if (branch) {
      const branchValidation = validateBranchName(branch);
      if (!branchValidation.valid) {
        return null;
      }
    }

    return {
      type: 'run',
      sprint,
      project,
      branch,
    };
  }

  // Try status command
  const statusMatch = normalized.match(PATTERNS.status);
  if (statusMatch) {
    return {
      type: 'status',
      sessionId: statusMatch[1],
    };
  }

  // Try resume command
  const resumeMatch = normalized.match(PATTERNS.resume);
  if (resumeMatch) {
    return {
      type: 'resume',
      sessionId: resumeMatch[1],
    };
  }

  // Try abort command
  const abortMatch = normalized.match(PATTERNS.abort);
  if (abortMatch) {
    return {
      type: 'abort',
      sessionId: abortMatch[1],
    };
  }

  // Try projects command
  if (PATTERNS.projects.test(normalized)) {
    return { type: 'projects' };
  }

  // Try history command
  const historyMatch = normalized.match(PATTERNS.history);
  if (historyMatch) {
    return {
      type: 'history',
      project: historyMatch[1],
    };
  }

  // Try logs command
  const logsMatch = normalized.match(PATTERNS.logs);
  if (logsMatch) {
    return {
      type: 'logs',
      sessionId: logsMatch[1],
    };
  }

  // Try help command
  if (PATTERNS.help.test(normalized)) {
    return { type: 'help' };
  }

  // Not a recognized command
  return null;
}

/**
 * Check if a message looks like it might be a Legba command
 * (starts with "legba" or "/legba")
 */
export function isLegbaMessage(message: string): boolean {
  const normalized = message.trim().toLowerCase();
  return normalized.startsWith('legba') || normalized.startsWith('/legba');
}

/**
 * Format a command back into a string (for display purposes)
 */
export function formatCommand(command: LegbaCommand): string {
  switch (command.type) {
    case 'run':
      let runStr = `legba run sprint-${command.sprint} on ${command.project}`;
      if (command.branch) {
        runStr += ` branch ${command.branch}`;
      }
      return runStr;

    case 'status':
      return command.sessionId
        ? `legba status ${command.sessionId}`
        : 'legba status';

    case 'resume':
      return `legba resume ${command.sessionId}`;

    case 'abort':
      return `legba abort ${command.sessionId}`;

    case 'projects':
      return 'legba projects';

    case 'history':
      return `legba history ${command.project}`;

    case 'logs':
      return `legba logs ${command.sessionId}`;

    case 'help':
      return 'legba help';
  }
}
