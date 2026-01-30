/**
 * Legba Command Types
 *
 * Represents all commands that can be parsed from chat messages.
 */

/**
 * Run command - Execute a sprint on a project
 */
export interface RunCommand {
  type: 'run';
  project: string;
  sprint: number;
  branch?: string;
}

/**
 * Status command - Check session status
 */
export interface StatusCommand {
  type: 'status';
  sessionId?: string;
}

/**
 * Resume command - Continue a paused session
 */
export interface ResumeCommand {
  type: 'resume';
  sessionId: string;
}

/**
 * Abort command - Cancel a session
 */
export interface AbortCommand {
  type: 'abort';
  sessionId: string;
}

/**
 * Projects command - List registered projects
 */
export interface ProjectsCommand {
  type: 'projects';
}

/**
 * History command - Show session history for a project
 */
export interface HistoryCommand {
  type: 'history';
  project: string;
}

/**
 * Logs command - Retrieve session logs
 */
export interface LogsCommand {
  type: 'logs';
  sessionId: string;
  lines?: number; // Number of lines to retrieve
}

/**
 * Help command - Show help text
 */
export interface HelpCommand {
  type: 'help';
}

/**
 * Union type of all Legba commands
 */
export type LegbaCommand =
  | RunCommand
  | StatusCommand
  | ResumeCommand
  | AbortCommand
  | ProjectsCommand
  | HistoryCommand
  | LogsCommand
  | HelpCommand;

/**
 * Type guard for RunCommand
 */
export function isRunCommand(cmd: LegbaCommand): cmd is RunCommand {
  return cmd.type === 'run';
}

/**
 * Type guard for StatusCommand
 */
export function isStatusCommand(cmd: LegbaCommand): cmd is StatusCommand {
  return cmd.type === 'status';
}

/**
 * Type guard for ResumeCommand
 */
export function isResumeCommand(cmd: LegbaCommand): cmd is ResumeCommand {
  return cmd.type === 'resume';
}

/**
 * Type guard for AbortCommand
 */
export function isAbortCommand(cmd: LegbaCommand): cmd is AbortCommand {
  return cmd.type === 'abort';
}

/**
 * Type guard for ProjectsCommand
 */
export function isProjectsCommand(cmd: LegbaCommand): cmd is ProjectsCommand {
  return cmd.type === 'projects';
}

/**
 * Type guard for HistoryCommand
 */
export function isHistoryCommand(cmd: LegbaCommand): cmd is HistoryCommand {
  return cmd.type === 'history';
}

/**
 * Type guard for LogsCommand
 */
export function isLogsCommand(cmd: LegbaCommand): cmd is LogsCommand {
  return cmd.type === 'logs';
}

/**
 * Type guard for HelpCommand
 */
export function isHelpCommand(cmd: LegbaCommand): cmd is HelpCommand {
  return cmd.type === 'help';
}
