import { execFile } from 'child_process';
import { promisify } from 'util';
import { logger } from './logger';
import { AppError, ErrorCode } from './errors';

/**
 * Safe Command Execution Utilities
 *
 * SECURITY FIX: MEDIUM #14
 * - Prevents command injection attacks
 * - Uses execFile instead of exec to avoid shell interpretation
 * - Validates and sanitizes all arguments
 * - Whitelists allowed commands
 */

const execFileAsync = promisify(execFile);

/**
 * Whitelist of allowed commands
 * ONLY these commands can be executed
 */
const ALLOWED_COMMANDS = new Set([
  'git',
  'npm',
  'node',
  'tsc',
  'jest',
  // Add more as needed, but be VERY careful
]);

/**
 * Command execution options
 */
export interface CommandOptions {
  cwd?: string;
  timeout?: number;
  maxBuffer?: number;
  env?: NodeJS.ProcessEnv;
}

/**
 * Command execution result
 */
export interface CommandResult {
  stdout: string;
  stderr: string;
  exitCode: number | null;
}

/**
 * Validate command name
 */
function validateCommand(command: string): void {
  // Must be in whitelist
  if (!ALLOWED_COMMANDS.has(command)) {
    throw new AppError(
      ErrorCode.INVALID_INPUT,
      'Command not allowed',
      `Attempted to execute non-whitelisted command: ${command}`,
      400
    );
  }

  // Must not contain path traversal
  if (command.includes('..') || command.includes('/') || command.includes('\\')) {
    throw new AppError(
      ErrorCode.INVALID_INPUT,
      'Invalid command format',
      `Command contains invalid characters: ${command}`,
      400
    );
  }

  // Must be alphanumeric (with dashes/underscores allowed)
  if (!/^[a-zA-Z0-9_-]+$/.test(command)) {
    throw new AppError(
      ErrorCode.INVALID_INPUT,
      'Invalid command format',
      `Command contains invalid characters: ${command}`,
      400
    );
  }
}

/**
 * Validate command arguments
 */
function validateArguments(args: string[]): void {
  for (const arg of args) {
    // Check for common injection patterns
    const dangerousPatterns = [
      /[;&|`$()]/,  // Shell metacharacters
      /\$\{/,       // Variable substitution
      /\$\(/,       // Command substitution
      />/,          // Redirection
      /<</,         // Here-doc
    ];

    for (const pattern of dangerousPatterns) {
      if (pattern.test(arg)) {
        throw new AppError(
          ErrorCode.INVALID_INPUT,
          'Invalid argument',
          `Argument contains dangerous characters: ${arg}`,
          400
        );
      }
    }

    // Limit argument length
    if (arg.length > 1000) {
      throw new AppError(
        ErrorCode.INVALID_INPUT,
        'Argument too long',
        `Argument exceeds maximum length: ${arg.length}`,
        400
      );
    }
  }
}

/**
 * Safely execute a command with validation
 *
 * SECURITY: Uses execFile (NOT exec) to prevent shell injection
 * Arguments are passed directly without shell interpretation
 */
export async function safeExecuteCommand(
  command: string,
  args: string[] = [],
  options: CommandOptions = {}
): Promise<CommandResult> {
  // Validate command
  validateCommand(command);

  // Validate arguments
  validateArguments(args);

  // Set safe defaults
  const safeOptions = {
    timeout: options.timeout || 30000, // 30 second timeout
    maxBuffer: options.maxBuffer || 1024 * 1024, // 1 MB buffer
    cwd: options.cwd,
    env: options.env || process.env,
  };

  // Log the command (for audit trail)
  logger.info('Executing command:', {
    command,
    args,
    cwd: safeOptions.cwd,
  });

  try {
    // Use execFile (NOT exec) - does NOT spawn a shell
    const { stdout, stderr } = await execFileAsync(command, args, safeOptions);

    logger.info('Command executed successfully:', { command });

    return {
      stdout: stdout.trim(),
      stderr: stderr.trim(),
      exitCode: 0,
    };
  } catch (error: any) {
    // Log failure
    logger.error('Command execution failed:', {
      command,
      args,
      error: error.message,
      code: error.code,
      signal: error.signal,
    });

    // Handle specific error cases
    if (error.code === 'ETIMEDOUT') {
      throw new AppError(
        ErrorCode.INTERNAL_ERROR,
        'Command timed out',
        `Command '${command}' exceeded timeout of ${safeOptions.timeout}ms`,
        500
      );
    }

    if (error.code === 'ENOENT') {
      throw new AppError(
        ErrorCode.INTERNAL_ERROR,
        'Command not found',
        `Command '${command}' not found in PATH`,
        500
      );
    }

    // Return failure result
    return {
      stdout: error.stdout?.trim() || '',
      stderr: error.stderr?.trim() || error.message,
      exitCode: error.code || null,
    };
  }
}

/**
 * Execute git command safely
 * Convenience wrapper with git-specific validations
 */
export async function safeGitCommand(
  args: string[],
  options: CommandOptions = {}
): Promise<CommandResult> {
  // Additional git-specific validations
  const gitSafeArgs = args.map(arg => {
    // Ensure no --exec or similar dangerous flags
    if (arg.startsWith('--exec')) {
      throw new AppError(
        ErrorCode.INVALID_INPUT,
        'Dangerous git flag not allowed',
        `Git argument not allowed: ${arg}`,
        400
      );
    }
    return arg;
  });

  return safeExecuteCommand('git', gitSafeArgs, options);
}

/**
 * Execute npm command safely
 * Convenience wrapper with npm-specific validations
 */
export async function safeNpmCommand(
  args: string[],
  options: CommandOptions = {}
): Promise<CommandResult> {
  // Additional npm-specific validations
  const npmSafeArgs = args.map(arg => {
    // Prevent script execution via npm
    if (arg === 'run-script' || arg === 'run') {
      throw new AppError(
        ErrorCode.INVALID_INPUT,
        'NPM script execution not allowed',
        'Cannot execute arbitrary npm scripts',
        400
      );
    }
    return arg;
  });

  return safeExecuteCommand('npm', npmSafeArgs, options);
}

/**
 * Example: Safely get git status
 */
export async function getGitStatus(repoPath: string): Promise<string> {
  const result = await safeGitCommand(['status', '--short'], { cwd: repoPath });

  if (result.exitCode !== 0) {
    throw new AppError(
      ErrorCode.INTERNAL_ERROR,
      'Failed to get git status',
      result.stderr,
      500
    );
  }

  return result.stdout;
}

/**
 * Example: Safely check npm version
 */
export async function getNpmVersion(): Promise<string> {
  const result = await safeNpmCommand(['--version']);

  if (result.exitCode !== 0) {
    throw new AppError(
      ErrorCode.INTERNAL_ERROR,
      'Failed to get npm version',
      result.stderr,
      500
    );
  }

  return result.stdout;
}
